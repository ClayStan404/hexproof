// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors
//! Synthetic complete games through the actor-validated reducer and an external
//! scripted controller. No AI decision engine and no forced concessions.
use engine::{
    game::{
        engine::{apply, start_game_with_starting_player},
        scenario::GameScenario,
    },
    types::{
        actions::{GameAction, MulliganChoice},
        game_state::WaitingFor,
        player::PlayerId,
        zones::Zone,
    },
};
use serde_json::{json, Value};
fn complete(count: u8) {
    let mut s = GameScenario::new_n_player(count, 20260909);
    let mut ids = Vec::new();
    for p in 0..count {
        for _ in 0..30 {
            ids.push(s.add_basic_land(PlayerId(p), engine::types::mana::ManaColor::Green));
            ids.push(
                s.add_creature_to_hand_from_oracle(PlayerId(p), "Grizzly Bears", 2, 2, "")
                    .with_mana_cost(
                        engine::parser::oracle_nom::primitives::parse_mana_cost("{1}{G}")
                            .unwrap()
                            .1,
                    )
                    .id(),
            );
        }
    }
    let mut r = s.build();
    // Only deck-zone construction occurs here; all play starts with the normal
    // opening/mulligan flow and uses reducer actions thereafter.
    for id in ids {
        engine::game::zones::move_to_zone(r.state_mut(), id, Zone::Library, &mut Vec::new());
    }
    start_game_with_starting_player(r.state_mut(), PlayerId(0));
    let (requests, prompts) = std::sync::mpsc::channel::<(PlayerId, Vec<GameAction>)>();
    let (replies, answers) = std::sync::mpsc::channel();
    let controller = std::thread::spawn(move || {
        for (actor, mut actions) in prompts {
            // Human-visible legal choices only. Prefer land, creature, attack
            // with as many legal attackers as available, decline blocks.
            actions.sort_by_key(|a| match a {
                GameAction::MulliganDecision {
                    choice: MulliganChoice::Keep,
                } => 0,
                GameAction::PlayLand { .. } => 1,
                GameAction::CastSpell { .. } => 2,
                GameAction::DeclareAttackers { attacks, .. } => 100 - attacks.len().min(90),
                GameAction::DeclareBlockers { assignments } => 10 + assignments.len(),
                GameAction::PassPriority => 900,
                GameAction::Concede { .. } => 10000,
                _ => 100,
            });
            if replies
                .send((
                    actor,
                    actions
                        .into_iter()
                        .next()
                        .expect("native legal action required"),
                ))
                .is_err()
            {
                break;
            }
        }
    });
    let mut trace: Vec<Value> = Vec::new();
    let mut after_elimination = false;
    let mut continued = false;
    let mut casts = 0;
    let mut attacks = 0;
    let mut keeps = 0;
    for step in 0..10000 {
        if matches!(r.state().waiting_for, WaitingFor::GameOver { .. }) {
            break;
        }
        let actor = r
            .state()
            .waiting_for
            .acting_players()
            .first()
            .copied()
            .expect("pending acting human seat");
        let (actions, _, _) = engine::ai_support::legal_actions_for_viewer(r.state(), actor);
        if actions.is_empty() {
            panic!(
                "native full legal actions empty at {:?}",
                r.state().waiting_for
            );
        }
        requests.send((actor, actions)).unwrap();
        let (responding_actor, action) = answers
            .recv_timeout(std::time::Duration::from_secs(10))
            .unwrap();
        assert_eq!(actor, responding_actor);
        if matches!(action, GameAction::CastSpell { .. }) {
            casts += 1;
        }
        if let GameAction::DeclareAttackers {
            attacks: chosen, ..
        } = &action
        {
            attacks += chosen.len();
        }
        if matches!(
            action,
            GameAction::MulliganDecision {
                choice: MulliganChoice::Keep
            }
        ) {
            keeps += 1;
        }
        assert!(!matches!(action, GameAction::Concede { .. }));
        let alive = r
            .state()
            .players
            .iter()
            .filter(|p| !p.is_eliminated)
            .count();
        if after_elimination
            && matches!(
                action,
                GameAction::PassPriority
                    | GameAction::CastSpell { .. }
                    | GameAction::PlayLand { .. }
            )
        {
            continued = true;
        }
        if alive > 1 && alive < (count as usize) {
            after_elimination = true;
        }
        trace.push(json!({"step":step,"actor":actor.0,"turn":r.state().turn_number,"phase":r.state().phase,"waiting":r.state().waiting_for,"alive":alive,"life":r.state().players.iter().map(|p|p.life).collect::<Vec<_>>(),"action":action}));
        if let Err(error) = apply(r.state_mut(), responding_actor, action) {
            panic!("native offered action rejected: {error:?}");
        }
    }
    drop(requests);
    controller.join().unwrap();
    let alive = r
        .state()
        .players
        .iter()
        .filter(|p| !p.is_eliminated)
        .count();
    let winner = match r.state().waiting_for {
        WaitingFor::GameOver { winner } => winner.map(|p| p.0),
        _ => None,
    };
    let output = std::path::PathBuf::from(std::env::var("HEXPROOF_EVAL_OUTPUT").unwrap());
    std::fs::write(
        output.join(format!("complete-{count}p-trace.json")),
        serde_json::to_string_pretty(&trace).unwrap(),
    )
    .unwrap();
    println!(
        "HEXPROOF_OBSERVATION {}",
        json!({"case_id":format!("complete_{count}p"),"observations":{"players":count,"synthetic_decks":"30 Forest + 30 Grizzly Bears per seat; not tournament-legal reference decks","winner":winner,"turn":r.state().turn_number,"alive":alive,"life":r.state().players.iter().map(|p|p.life).collect::<Vec<_>>(),"waiting":r.state().waiting_for,"controller_decisions":trace.len(),"creature_casts":casts,"attack_assignments":attacks,"opening_keeps":keeps,"continued_after_first_elimination":continued,"forced_concedes":0}})
    );
    assert!(winner.is_some());
    assert_eq!(alive, 1);
    assert!(casts > 0 && attacks > 0);
    assert_eq!(keeps, count as usize);
    if count == 4 {
        assert!(continued);
    }
}
#[test]
fn complete_2p() {
    complete(2);
}
#[test]
fn complete_4p() {
    complete(4);
}
