#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors
"""Independent bounded diagnostics; not an implicit complete 17-case qualification."""

import argparse
import asyncio
import copy
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import traceback

PIN = "1e17b41f05a134b33ebcc00f93b84be14a0a3363"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--checkout", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    checkout = args.checkout.resolve()
    revision = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=checkout, text=True).strip()
    assert revision == PIN
    sys.path.insert(0, str(checkout))
    from src.cards import ALL_CARDS
    from src.engine import Game, ZoneType, Event, EventType
    from src.engine.priority import PlayerAction, ActionType, ActionValidator
    from src.engine.turn import Phase, Step
    from src.engine.targeting import Target
    from src.server.session import GameSession

    args.output.mkdir(parents=True, exist_ok=True)
    output = Path(tempfile.mkdtemp(prefix="independent-", dir=args.output.resolve()))
    (output / "probe.py").write_bytes(Path(__file__).read_bytes())
    observations = {}
    results = []

    def card(g, owner, name, zone):
        definition = ALL_CARDS[name]
        return g.create_object(name=name, owner_id=owner, zone=zone,
                               characteristics=copy.deepcopy(definition.characteristics), card_def=definition)

    def fixture(players=2):
        g = Game(mode="mtg")
        seats = [g.add_player(chr(65+i)) for i in range(players)]
        for p in seats:
            for _ in range(30):
                card(g, p.id, "Plains", ZoneType.LIBRARY)
        g.turn_manager.set_turn_order([p.id for p in seats])
        turn = g.turn_manager.turn_state
        turn.active_player_id = seats[0].id
        turn.phase, turn.step, turn.turn_number = Phase.PRECOMBAT_MAIN, Step.MAIN, 1
        g.state.active_player, g.state.turn_number = seats[0].id, 1
        g.priority_system.priority_player = seats[0].id
        return g, seats

    def opening():
        g = Game(mode="mtg")
        seats = [g.add_player(name) for name in "AB"]
        for p in seats:
            for _ in range(60):
                card(g, p.id, "Plains", ZoneType.LIBRARY)
        kept = []
        def keep(player, hand, count):
            kept.append({"player": player, "hand": len(hand), "mulligans": count})
            return True
        g.get_mulligan_decision = keep
        class MainReached(Exception):
            pass
        async def human(player, actions):
            if g.turn_manager.turn_state.phase == Phase.PRECOMBAT_MAIN:
                observations["mainActor"] = player
                observations["mainLegalCount"] = len(actions)
                raise MainReached()
            return PlayerAction(type=ActionType.PASS, player_id=player)
        g.priority_system.get_human_action = human
        async def run():
            await g.start_game()
            try:
                await g.run_turn(seats[0].id)
            except MainReached:
                pass
        asyncio.run(run())
        observations.update(keeps=kept, hands=[len(g.get_hand(p.id)) for p in seats],
                            libraries=[g.get_library_size(p.id) for p in seats])
        assert len(kept) == 2 and all(k["hand"] == 7 for k in kept)
        assert observations["hands"] == [7, 7]
        assert observations["libraries"] == [53, 53]
        assert observations["mainActor"] == seats[0].id and observations["mainLegalCount"] > 0

    def land_priority():
        g, seats = fixture()
        a, b = seats
        first, second = [card(g, a.id, "Plains", ZoneType.HAND) for _ in range(2)]
        validator = ActionValidator(g.state, g.priority_system)
        action = PlayerAction(type=ActionType.PLAY_LAND, player_id=a.id, card_id=first.id)
        assert validator.validate(action)[0]
        asyncio.run(g.priority_system._execute_action(action))
        before = (len(g.get_hand(a.id)), len(g.get_battlefield()))
        second_ok = validator.validate(PlayerAction(type=ActionType.PLAY_LAND, player_id=a.id, card_id=second.id))[0]
        wrong_ok = validator.validate(PlayerAction(type=ActionType.PLAY_LAND, player_id=b.id, card_id=second.id))[0]
        observations.update(firstZone=first.zone.name, secondZone=second.zone.name,
                            before=before, after=(len(g.get_hand(a.id)), len(g.get_battlefield())),
                            secondAccepted=second_ok, wrongActorAccepted=wrong_ok)
        assert first.zone == ZoneType.BATTLEFIELD and second.zone == ZoneType.HAND
        assert before == (1, 1) and not second_ok and not wrong_ok
        assert before == observations["after"]

    def bolt(creature=False):
        g, seats = fixture()
        a, b = seats
        mountain = card(g, a.id, "Mountain", ZoneType.BATTLEFIELD)
        spell = card(g, a.id, "Lightning Bolt", ZoneType.HAND)
        victim = card(g, b.id, "Grizzly Bears", ZoneType.BATTLEFIELD) if creature else b
        action = PlayerAction(type=ActionType.CAST_SPELL, player_id=a.id, card_id=spell.id,
                              targets=[[Target(id=victim.id, is_player=not creature) ]])
        assert ActionValidator(g.state, g.priority_system).validate(action)[0]
        asyncio.run(g.priority_system._execute_action(action))
        observations.update(beforeLife=b.life, stack=[i.card_id for i in g.stack.get_items()],
                            spellBefore=spell.zone.name, mountainTapped=mountain.state.tapped)
        assert b.life == 20 and spell.id in observations["stack"] and spell.zone == ZoneType.STACK
        for event in g.stack.resolve_top():
            g.emit(event)
        g.check_state_based_actions()
        observations.update(afterLife=b.life, spellAfter=spell.zone.name,
                            victimZone=victim.zone.name if creature else "player",
                            battlefield=[o.id for o in g.get_battlefield()])
        assert spell.zone == ZoneType.GRAVEYARD and mountain.state.tapped
        if creature:
            assert victim.zone == ZoneType.GRAVEYARD and b.life == 20
            assert victim.id not in observations["battlefield"]
        else:
            assert b.life == 17

    def privacy():
        g = Game(mode="mtg")
        seats = [g.add_player(name) for name in "AB"]
        a, b = seats
        for p, name in [(a, "Plains"), (b, "Island")]:
            for _ in range(30):
                card(g, p.id, name, ZoneType.LIBRARY)
        secrets = [card(g, a.id, "Lightning Bolt", ZoneType.HAND), card(g, b.id, "Murder", ZoneType.HAND)]
        public = card(g, a.id, "Grizzly Bears", ZoneType.BATTLEFIELD)
        library_ids = {i for p in seats for i in g.state.zones[f"library_{p.id}"].objects}
        session = GameSession(id="independent-private-views", game=g, mode="human_vs_human")
        violations = []
        for viewer in [a.id, b.id, None]:
            view = session.get_client_state(viewer).model_dump()
            (output / f"view-{viewer}.json").write_text(json.dumps(view, indent=2))
            encoded = json.dumps(view)
            for secret in secrets:
                present = json.dumps(secret.id) in encoded or json.dumps(secret.name) in encoded
                if (secret.owner == viewer) != present:
                    violations.append({"viewer": viewer, "handOwner": secret.owner, "present": present})
            if any(json.dumps(i) in encoded for i in library_ids):
                violations.append({"viewer": viewer, "libraryIdentityLeak": True})
            if any(json.dumps(name) in encoded for name in ["Plains", "Island"]):
                violations.append({"viewer": viewer, "libraryNameLeak": True})
            for secret in secrets:
                if viewer != secret.owner and secret.card_def.text and secret.card_def.text in encoded:
                    violations.append({"viewer": viewer, "privateCardTextLeak": secret.id})
            assert json.dumps(public.id) in encoded
            assert all(p["library_size"] == 30 and p["hand_size"] == 1 for p in view["players"].values())
        observations.update(secretCount=2, libraryIdsChecked=len(library_ids), violations=violations)
        assert not violations

    def four_player_loss_cleanup():
        g, seats = fixture(4)
        departed = seats[2]
        bears = card(g, departed.id, "Grizzly Bears", ZoneType.BATTLEFIELD)
        # Independent CR 800.4a diagnostic: life-zero SBA, not the frozen concession scenario.
        g.emit(Event(type=EventType.LIFE_CHANGE, payload={"player": departed.id, "amount": -20}))
        g.check_state_based_actions()
        zones = [name for name, zone in g.state.zones.items() if bears.id in zone.objects]
        view = GameSession(id="independent-loss-view", game=g, mode="human_vs_human").get_client_state(seats[0].id).model_dump()
        (output / "loss-public-view.json").write_text(json.dumps(view, indent=2))
        observations.update(life=departed.life, hasLost=departed.has_lost, gameOver=g.is_game_over(),
                            activeZonesContainingBears=zones, publicStillContainsBears=json.dumps(bears.id) in json.dumps(view))
        assert departed.has_lost and not g.is_game_over()
        assert not zones and not observations["publicStillContainsBears"], "Departed player's owned Bears must leave all active zones and public views"

    def four_player_concede_route():
        from src.server.routes.match import concede_match
        from src.server.session import session_manager
        async def run():
            session = await session_manager.create_session(mode="human_vs_human", game_mode="mtg")
            try:
                seats = [session.add_player(name) for name in "ABCD"]
                bears = card(session.game, seats[2], "Grizzly Bears", ZoneType.BATTLEFIELD)
                session.game.priority_system.priority_player = seats[0]
                result = await concede_match(session.id, seats[2])
                observations.update(response=result, sessionFinished=session.is_finished,
                                    winner=session.winner_id, engineGameOver=session.game.is_game_over(),
                                    registeredPlayers=len(session.game.state.players),
                                    bearsStillOnBattlefield=bears.id in session.game.state.zones["battlefield"].objects)
                assert not session.is_finished and session.winner_id is None, "One concession must not finish a four-player session"
            finally:
                await session_manager.remove_session(session.id)
        asyncio.run(run())

    cases = [("opening", opening), ("land_priority", land_priority), ("bolt_player", bolt),
             ("bolt_creature", lambda: bolt(True)), ("hidden_views", privacy),
             ("four_player_loss_cleanup_diagnostic", four_player_loss_cleanup),
             ("four_player_concede_route_diagnostic", four_player_concede_route)]
    for name, fn in cases:
        observations.clear()
        item = {"id": name, "status": "UNVERIFIED", "layer": "fixture"}
        try:
            fn()
            item.update(status="PASS", layer="engine")
        except AssertionError as error:
            item.update(status="FAIL", layer="adapter" if name == "four_player_concede_route_diagnostic" else "engine",
                        error=str(error), traceback=traceback.format_exc())
        except Exception as error:
            item.update(error=str(error), traceback=traceback.format_exc())
        item["observed"] = copy.deepcopy(observations)
        results.append(item)
        print(json.dumps(item), flush=True)
    report = {"engine": "Hyperdraft", "revision": revision, "source": "https://github.com/discordwell/Hyperdraft",
              "scope": "Seven independent diagnostics, not the complete frozen 17-case report. Explicit fixture setup; real rules operations; no upstream patch.",
              "cases": results}
    (output / "results.json").write_text(json.dumps(report, indent=2) + "\n")
    print(output, flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
