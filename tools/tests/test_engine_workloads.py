#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors

import copy
import importlib.util
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1] / "engine-eval"
SPEC = importlib.util.spec_from_file_location("engine_workloads", ROOT / "workload_driver.py")
workloads = importlib.util.module_from_spec(SPEC)
sys.path.insert(0, str(ROOT))
try:
    SPEC.loader.exec_module(workloads)
finally:
    sys.path.pop(0)


class WorkloadTests(unittest.TestCase):
    def event(self):
        players = [{"id": i, "life": 20, "handCount": 1, "libraryCount": 39} for i in range(2)]
        return {"kind": "chooseAction", "actor": 0, "views": [
            {"viewer": viewer, "players": copy.deepcopy(players), "stack": [],
             "zones": [{"owner": i, "zone": "battlefield", "cards": []} for i in range(2)] +
                      [{"owner": viewer, "zone": "hand", "cards": [] if viewer < 0 else
                        [{"id": "engine-card-1" if viewer == 0 else "engine-card-10", "name": "Forest"}]}]}
            for viewer in [-1, 0, 1]]}

    def test_complete_string_ids_not_prefixes(self):
        workloads.verify_views(self.event(), 2)

    def test_erased_owner_hand_is_not_private_projection_success(self):
        event = self.event()
        event["views"][1]["zones"][-1]["cards"] = []
        with self.assertRaises(AssertionError):
            workloads.verify_views(event, 2)

    def test_duplicate_or_missing_view_rejected(self):
        for remove in [True, False]:
            event = self.event()
            if remove:
                event["views"].pop()
            else:
                event["views"].append(copy.deepcopy(event["views"][0]))
            with self.assertRaises(AssertionError):
                workloads.verify_views(event, 2)

    def test_library_identifiers_and_other_hand_rejected(self):
        event = self.event()
        event["views"][0]["zones"].append({"owner": 0, "zone": "library", "cards": [{"id": "known", "name": "Hidden card"}]})
        with self.assertRaises(AssertionError):
            workloads.verify_views(event, 2)
        event = self.event()
        event["views"][0]["unexpected"] = {"cardId": "engine-card-1"}
        with self.assertRaises(AssertionError):
            workloads.verify_views(event, 2)

    def test_zone_counts_accept_both_bridge_protocols(self):
        event = self.event()
        spec = {"startingLife": 20, "players": [{"cards": [{"count": 40}], "commanders": []}] * 2}
        workloads.verify_opening(event, spec)
        view = event["views"][0]
        for owner in [0, 1]:
            view["zones"] += [{"owner": owner, "zone": "hand", "count": 1, "cards": []},
                              {"owner": owner, "zone": "library", "count": 39, "cards": []}]
            view["players"][owner].pop("handCount")
            view["players"][owner].pop("libraryCount")
        workloads.verify_opening(event, spec)

    def test_unregistered_or_multiple_winner_rejected(self):
        event = {"gameOver": True, "naturalCompletion": True, "winner": 99,
                 "view": {"players": [{"id": 0, "life": -1, "hasLost": True}, {"id": 1, "life": -1, "hasLost": True}]}}
        spec = {"players": [{}, {}]}
        self.assertFalse(workloads.terminal_ok(event, spec))
        event["winner"] = 0
        event["view"]["players"][0].update(life=10, hasLost=False, hasWon=True)
        self.assertTrue(workloads.terminal_ok(event, spec))
        event["view"]["players"][1]["hasWon"] = True
        self.assertFalse(workloads.terminal_ok(event, spec))

    def test_positive_life_commander_loser_requires_real_loss_flag(self):
        event = {"gameOver": True, "naturalCompletion": True, "winner": 0,
                 "view": {"players": [{"id": 0, "life": 10}, {"id": 1, "life": 19, "status": "lost"}]}}
        self.assertTrue(workloads.terminal_ok(event, {"players": [{}, {}]}))
        event["view"]["players"][1]["status"] = "playing"
        self.assertFalse(workloads.terminal_ok(event, {"players": [{}, {}]}))

    def test_every_cast_attempt_needs_new_paid_stack_object(self):
        event = self.event()
        old = {"id": "stack-1", "cardId": "bolt-1", "name": "Firebolt"}
        event["views"][0]["stack"] = [old]
        transfers = workloads.Transfers()
        transfers.selected(event, {"category": "cast", "cardId": "bolt-1"})
        with self.assertRaises(AssertionError):
            transfers.observe(event)
        event["views"][0]["stack"] = [{**old, "id": "stack-2"}]
        transfers.observe(event)
        self.assertEqual(transfers.checked_casts, 1)

    def test_provisional_cast_does_not_count_as_payment(self):
        event = self.event()
        transfers = workloads.Transfers()
        transfers.selected(event, {"category": "cast", "cardId": "bear-1"})
        event["kind"] = "payManaCost"
        event["views"][0]["stack"] = [{"id": "stack-1", "cardId": "bear-1", "name": "Bears"}]
        transfers.observe(event)
        self.assertEqual(transfers.checked_casts, 0)
        event["kind"] = "chooseAction"
        transfers.observe(event)
        self.assertEqual(transfers.checked_casts, 1)

    def test_land_must_move_from_hand_to_battlefield_immediately(self):
        event = self.event()
        transfers = workloads.Transfers()
        transfers.selected(event, {"category": "land", "cardId": "engine-card-1"})
        with self.assertRaises(AssertionError):
            transfers.observe(event)
        view = event["views"][1]
        view["zones"][0]["cards"] = view["zones"][-1]["cards"]
        view["zones"][-1]["cards"] = []
        view["players"][0]["handCount"] = 0
        transfers.observe(event)
        self.assertEqual(transfers.checked_lands, 1)


if __name__ == "__main__":
    unittest.main()
