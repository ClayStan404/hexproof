// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors
//! Fixed independent Oracle-text fixtures; all tested outcomes use reducer actions.
use engine::game::combat::AttackTarget;
use engine::game::engine::{apply, start_game_with_starting_player};
use engine::game::scenario::{GameRunner, GameScenario, P0, P1};
use engine::game::visibility::filter_state_for_viewer;
use engine::parser::oracle_nom::primitives::parse_mana_cost;
use engine::types::actions::{GameAction, MulliganChoice};
use engine::types::game_state::WaitingFor;
use engine::types::identifiers::ObjectId;
use engine::types::mana::{ManaColor, ManaCost};
use engine::types::phase::Phase;
use engine::types::player::PlayerId;
use engine::types::zones::Zone;
use serde_json::{Value, json};

fn observe(id: &str, value: Value) {
    println!(
        "HEXPROOF_OBSERVATION {}",
        json!({"case_id":id,"observations":value})
    );
}
fn cost(text: &str) -> ManaCost {
    parse_mana_cost(text).expect("fixture cost parses").1
}
fn scenario() -> GameScenario {
    let mut s = GameScenario::new();
    s.at_phase(Phase::PreCombatMain);
    for p in [P0, P1] {
        s.with_library_top(p, &vec!["Plains"; 30]);
    }
    s
}
fn cast_bolt(s: &mut GameScenario, p: PlayerId) -> ObjectId {
    s.add_spell_to_hand_from_oracle(
        p,
        "Lightning Bolt",
        true,
        "Lightning Bolt deals 3 damage to any target.",
    )
    .with_mana_cost(cost("{R}"))
    .id()
}
fn pass(r: &mut GameRunner) {
    r.act(GameAction::PassPriority)
        .expect("legal explicit priority pass");
}

#[test]
fn opening() {
    let mut s = GameScenario::new();
    for p in [P0, P1] {
        s.with_library_top(p, &vec!["Plains"; 60]);
    }
    let mut r = s.build();
    start_game_with_starting_player(r.state_mut(), P0);
    let mut keeps = 0;
    for _ in 0..30 {
        if r.state().phase == Phase::PreCombatMain {
            break;
        }
        match r.state().waiting_for {
            WaitingFor::MulliganDecision { .. } => {
                r.act(GameAction::MulliganDecision {
                    choice: MulliganChoice::Keep,
                })
                .unwrap();
                keeps += 1;
            }
            WaitingFor::Priority { .. } => pass(&mut r),
            _ => panic!("unhandled opening prompt: {:?}", r.state().waiting_for),
        }
    }
    let hands: Vec<_> = r.state().players.iter().map(|p| p.hand.len()).collect();
    let libraries: Vec<_> = r.state().players.iter().map(|p| p.library.len()).collect();
    observe(
        "opening",
        json!({"hands":hands,"libraries":libraries,"keep_decisions":keeps,"phase":format!("{:?}",r.state().phase),"active":r.state().active_player.0,"priority":r.state().priority_player.0}),
    );
    assert_eq!(hands, vec![7, 7]);
    assert_eq!(libraries, vec![53, 53]);
    assert_eq!(keeps, 2);
    assert_eq!(r.state().phase, Phase::PreCombatMain);
    assert_eq!(r.state().priority_player, P0);
}

#[test]
fn land_priority() {
    let mut s = scenario();
    let a = s.add_land_to_hand(P0, "Plains").id();
    let b = s.add_land_to_hand(P0, "Plains").id();
    let mut r = s.build();
    let before = serde_json::to_value(r.state()).unwrap();
    let wrong = apply(r.state_mut(), P1, GameAction::PassPriority);
    let wrong_unchanged = serde_json::to_value(r.state()).unwrap() == before;
    assert!(wrong.is_err());
    assert!(wrong_unchanged);
    let cid = r.state().objects[&a].card_id;
    r.act(GameAction::PlayLand {
        object_id: a,
        card_id: cid,
    })
    .unwrap();
    let cid = r.state().objects[&b].card_id;
    let before = serde_json::to_value(r.state()).unwrap();
    let second = r.act(GameAction::PlayLand {
        object_id: b,
        card_id: cid,
    });
    let second_unchanged = serde_json::to_value(r.state()).unwrap() == before;
    observe(
        "land_priority",
        json!({"first_zone":r.state().objects[&a].zone,"second_zone":r.state().objects[&b].zone,"second_rejected":second.is_err(),"second_unchanged":second_unchanged,"wrong_actor_rejected":wrong.is_err(),"wrong_actor_unchanged":wrong_unchanged}),
    );
    assert_eq!(r.state().objects[&a].zone, Zone::Battlefield);
    assert_eq!(r.state().objects[&b].zone, Zone::Hand);
    assert!(second.is_err());
    assert!(second_unchanged);
}

#[test]
fn bolt_player() {
    let mut s = scenario();
    let land = s.add_basic_land(P0, ManaColor::Red);
    let bolt = cast_bolt(&mut s, P0);
    let mut r = s.build();
    let committed = r.cast(bolt).target_player(P1).commit();
    let before_life = committed.state().players[1].life;
    let before_stack = committed.state().stack.len();
    assert_eq!(before_life, 20);
    assert_eq!(before_stack, 1);
    committed.resolve();
    observe(
        "bolt_player",
        json!({"before_life":before_life,"before_stack":before_stack,"after_life":r.state().players[1].life,"bolt_zone":r.state().objects[&bolt].zone,"mountain_tapped":r.state().objects[&land].tapped}),
    );
    assert_eq!(r.state().players[1].life, 17);
    assert_eq!(r.state().objects[&bolt].zone, Zone::Graveyard);
    assert!(r.state().objects[&land].tapped);
}

#[test]
fn bolt_creature() {
    let mut s = scenario();
    s.add_basic_land(P0, ManaColor::Red);
    let bolt = cast_bolt(&mut s, P0);
    let bears = s.add_creature(P1, "Grizzly Bears", 2, 2).id();
    let mut r = s.build();
    r.cast(bolt).target_object(bears).resolve();
    observe(
        "bolt_creature",
        json!({"bears_zone":r.state().objects[&bears].zone,"bolt_zone":r.state().objects[&bolt].zone,"defender_life":r.state().players[1].life}),
    );
    assert_eq!(r.state().objects[&bears].zone, Zone::Graveyard);
    assert_eq!(r.state().objects[&bolt].zone, Zone::Graveyard);
    assert_eq!(r.state().players[1].life, 20);
}

#[test]
fn counterspell() {
    let mut s = scenario();
    s.add_basic_land(P0, ManaColor::Red);
    let bolt = cast_bolt(&mut s, P0);
    s.add_basic_land(P1, ManaColor::Blue);
    s.add_basic_land(P1, ManaColor::Blue);
    let counter = s
        .add_spell_to_hand_from_oracle(P1, "Counterspell", true, "Counter target spell.")
        .with_mana_cost(cost("{U}{U}"))
        .id();
    let mut r = s.build();
    let mut first = r.cast(bolt).target_player(P1).commit();
    first.act(GameAction::PassPriority).unwrap();
    let second = first.cast(counter).target_object(bolt).commit();
    let stack: Vec<_> = second.state().stack.iter().map(|e| e.source_id.0).collect();
    assert_eq!(stack, vec![bolt.0, counter.0]);
    second.resolve();
    drop(first);
    r.advance_until_stack_empty();
    observe(
        "counterspell",
        json!({"stack_before":stack,"life":r.state().players.iter().map(|p|p.life).collect::<Vec<_>>(),"bolt_zone":r.state().objects[&bolt].zone,"counter_zone":r.state().objects[&counter].zone,"stack_after":r.state().stack.len()}),
    );
    assert_eq!(r.state().players[0].life, 20);
    assert_eq!(r.state().players[1].life, 20);
    assert_eq!(r.state().objects[&bolt].zone, Zone::Graveyard);
    assert_eq!(r.state().objects[&counter].zone, Zone::Graveyard);
    assert!(r.state().stack.is_empty());
}

#[test]
fn etb_draw() {
    let mut s = scenario();
    s.add_basic_land(P0, ManaColor::Green);
    s.add_basic_land(P0, ManaColor::White);
    let visionary = s
        .add_creature_to_hand_from_oracle(
            P0,
            "Elvish Visionary",
            1,
            1,
            "When Elvish Visionary enters, draw a card.",
        )
        .with_mana_cost(cost("{1}{G}"))
        .id();
    let mut r = s.build();
    let committed = r.cast(visionary).commit();
    assert_eq!(committed.state().stack.len(), 1);
    drop(committed);
    for _ in 0..8 {
        if r.state().objects[&visionary].zone == Zone::Battlefield {
            break;
        }
        pass(&mut r);
    }
    let creature_zone = r.state().objects[&visionary].zone;
    let library_before_trigger = r.state().players[0].library.len();
    let trigger_stack = r.state().stack.len();
    assert_eq!(creature_zone, Zone::Battlefield);
    assert_eq!(library_before_trigger, 30);
    assert_eq!(trigger_stack, 1);
    r.advance_until_stack_empty();
    observe(
        "etb_draw",
        json!({"creature_zone":creature_zone,"library_before_trigger":library_before_trigger,"trigger_stack":trigger_stack,"library_after":r.state().players[0].library.len(),"hand_after":r.state().players[0].hand.len()}),
    );
    assert_eq!(r.state().players[0].library.len(), 29);
    assert_eq!(r.state().players[0].hand.len(), 1);
}

#[test]
fn blocked_combat() {
    let mut s = scenario();
    let a = s.add_creature(P0, "Grizzly Bears", 2, 2).id();
    let b = s.add_creature(P1, "Grizzly Bears", 2, 2).id();
    let mut r = s.build();
    r.advance_to_combat();
    r.declare_attackers(&[(a, AttackTarget::Player(P1))])
        .unwrap();
    for _ in 0..10 {
        if matches!(r.state().waiting_for, WaitingFor::DeclareBlockers { .. }) {
            break;
        }
        pass(&mut r);
    }
    r.declare_blockers(&[(b, a)]).unwrap();
    r.combat_damage();
    observe(
        "blocked_combat",
        json!({"attacker_zone":r.state().objects[&a].zone,"blocker_zone":r.state().objects[&b].zone,"life":r.state().players.iter().map(|p|p.life).collect::<Vec<_>>()}),
    );
    assert_eq!(r.state().objects[&a].zone, Zone::Graveyard);
    assert_eq!(r.state().objects[&b].zone, Zone::Graveyard);
    assert_eq!(r.state().players[0].life, 20);
    assert_eq!(r.state().players[1].life, 20);
}

#[test]
fn four_player_departure() {
    let mut s = GameScenario::new_n_player(4, 20260909);
    s.at_phase(Phase::PreCombatMain);
    for p in 0..4 {
        s.with_library_top(PlayerId(p), &vec!["Plains"; 30]);
    }
    let land = s.add_land_to_hand(P0, "Plains").id();
    let bears = s.add_creature(PlayerId(2), "Grizzly Bears", 2, 2).id();
    let mut r = s.build();
    apply(
        r.state_mut(),
        PlayerId(2),
        GameAction::Concede {
            player_id: PlayerId(2),
        },
    )
    .unwrap();
    let alive = r
        .state()
        .players
        .iter()
        .filter(|p| !p.is_eliminated)
        .count();
    let bears_in_exile = r.state().exile.contains(&bears);
    let view = filter_state_for_viewer(r.state(), P0);
    let first = json!({"alive":alive,"bears_in_battlefield":r.state().battlefield.contains(&bears),"bears_in_exile":bears_in_exile,"bears_visible_in_public_exile":view.exile.contains(&bears),"waiting":r.state().waiting_for});
    let cid = r.state().objects[&land].card_id;
    apply(
        r.state_mut(),
        P0,
        GameAction::PlayLand {
            object_id: land,
            card_id: cid,
        },
    )
    .unwrap();
    assert_eq!(r.state().objects[&land].zone, Zone::Battlefield);
    assert!(!matches!(
        r.state().waiting_for,
        WaitingFor::GameOver { .. }
    ));
    for p in [1, 3] {
        apply(
            r.state_mut(),
            PlayerId(p),
            GameAction::Concede {
                player_id: PlayerId(p),
            },
        )
        .unwrap();
    }
    observe(
        "four_player_departure",
        json!({"first_departure":first,"continued_land":r.state().objects[&land].zone,"final_waiting":r.state().waiting_for}),
    );
    assert!(matches!(
        r.state().waiting_for,
        WaitingFor::GameOver { winner: Some(P0) }
    ));
    assert_eq!(alive, 3);
    assert!(
        !bears_in_exile,
        "owned Bears must leave the game, not enter its public exile zone"
    );
}

#[test]
fn hidden_views() {
    let mut s = GameScenario::new();
    s.at_phase(Phase::PreCombatMain);
    s.with_cards_in_hand(P0, &["Counterspell"]);
    s.with_cards_in_hand(P1, &["Lightning Bolt"]);
    s.with_library_top(P0, &["Elvish Visionary"]);
    s.with_library_top(P1, &["Willbender"]);
    let public = s.add_creature(P0, "Grizzly Bears", 2, 2).id();
    let r = s.build();
    let mut observations = Vec::new();
    for viewer in [P0, P1, PlayerId(255)] {
        let view = filter_state_for_viewer(r.state(), viewer);
        let value = serde_json::to_value(&view).unwrap();
        let text = value.to_string();
        let own_visible = if viewer == P0 {
            text.contains("Counterspell")
        } else if viewer == P1 {
            text.contains("Lightning Bolt")
        } else {
            true
        };
        let other_hidden = if viewer == P0 {
            !text.contains("Lightning Bolt")
        } else if viewer == P1 {
            !text.contains("Counterspell")
        } else {
            !text.contains("Lightning Bolt") && !text.contains("Counterspell")
        };
        let libraries_hidden = !text.contains("Elvish Visionary") && !text.contains("Willbender");
        let public_visible = view.objects[&public].name == "Grizzly Bears";
        observations.push(json!({"viewer":viewer.0,"own_visible":own_visible,"other_hidden":other_hidden,"libraries_hidden":libraries_hidden,"public_visible":public_visible,"hand_counts":view.players.iter().map(|p|p.hand.len()).collect::<Vec<_>>(),"library_counts":view.players.iter().map(|p|p.library.len()).collect::<Vec<_>>() }));
        std::fs::write(
            std::path::PathBuf::from(std::env::var("HEXPROOF_EVAL_OUTPUT").unwrap())
                .join(format!("view-{}.json", viewer.0)),
            serde_json::to_string_pretty(&value).unwrap(),
        )
        .unwrap();
        assert!(own_visible && other_hidden && libraries_hidden && public_visible);
        assert_eq!(
            view.players
                .iter()
                .map(|p| p.hand.len())
                .collect::<Vec<_>>(),
            vec![1, 1]
        );
        assert_eq!(
            view.players
                .iter()
                .map(|p| p.library.len())
                .collect::<Vec<_>>(),
            vec![1, 1]
        );
    }
    let tracking = library_tracking();
    observe(
        "hidden_views",
        json!({"views":observations,"library_tracking":tracking}),
    );
    assert!(
        tracking["all_viewers_hide_known_card_position"]
            .as_bool()
            .unwrap(),
        "public card identity must not remain trackable by stable library object IDs after a real shuffle"
    );
    assert!(
        tracking["all_viewers_hide_all_private_library_ids"]
            .as_bool()
            .unwrap(),
        "every private library identity must disappear from projected library lists and object maps, not only the previously public card"
    );
}

fn library_tracking() -> Value {
    let mut s = scenario();
    for _ in 0..3 {
        s.add_basic_land(P0, ManaColor::Blue);
    }
    let known = s.add_creature(P1, "Grizzly Bears", 2, 2).id();
    let ebb = s
        .add_spell_to_hand_from_oracle(
            P0,
            "Time Ebb",
            false,
            "Put target creature on top of its owner's library.",
        )
        .with_mana_cost(cost("{2}{U}"))
        .id();
    let mut r = s.build();
    let public = filter_state_for_viewer(r.state(), PlayerId(255));
    assert_eq!(public.objects[&known].name, "Grizzly Bears");
    r.cast(ebb).target_object(known).resolve();
    assert_eq!(r.state().objects[&known].zone, Zone::Library);
    assert_eq!(r.state().players[1].library.len(), 31);
    let before: Vec<_> = r.state().players[1].library.iter().map(|id| id.0).collect();
    let mut events = Vec::new();
    engine::game::effects::change_zone::shuffle_library(r.state_mut(), P1, &mut events);
    let after: Vec<_> = r.state().players[1].library.iter().map(|id| id.0).collect();
    assert!(
        !events.is_empty(),
        "actual shuffle must emit its engine event"
    );
    assert_ne!(
        before, after,
        "fixed seeded multi-card shuffle must change this fixture's order"
    );
    let authority_position = after.iter().position(|id| *id == known.0).unwrap();
    let mut projections = Vec::new();
    let mut all_hidden = true;
    let private_ids: Vec<_> = r
        .state()
        .players
        .iter()
        .flat_map(|p| p.library.iter().copied())
        .collect();
    let mut all_library_ids_hidden = true;
    for viewer in [P0, P1, PlayerId(255)] {
        let view = filter_state_for_viewer(r.state(), viewer);
        let exposed_order: Vec<_> = view.players[1].library.iter().map(|id| id.0).collect();
        let recovered_position = exposed_order.iter().position(|id| *id == known.0);
        let retained_library_ids: Vec<_> = view
            .players
            .iter()
            .flat_map(|p| p.library.iter())
            .filter(|id| private_ids.contains(id))
            .map(|id| id.0)
            .collect();
        let retained_object_ids: Vec<_> = private_ids
            .iter()
            .filter(|id| view.objects.contains_key(id))
            .map(|id| id.0)
            .collect();
        all_hidden &= recovered_position.is_none();
        all_library_ids_hidden &= retained_library_ids.is_empty() && retained_object_ids.is_empty();
        projections.push(json!({"viewer":viewer.0,"exposed_order":exposed_order,
            "retained_private_library_ids":retained_library_ids,"retained_private_object_ids":retained_object_ids,
            "recovered_position":recovered_position,"matches_authority_position":recovered_position==Some(authority_position)}));
        std::fs::write(
            std::path::PathBuf::from(std::env::var("HEXPROOF_EVAL_OUTPUT").unwrap())
                .join(format!("library-track-view-{}.json", viewer.0)),
            serde_json::to_string_pretty(&view).unwrap(),
        )
        .unwrap();
    }
    json!({"setup":"Public Grizzly Bears is legally Time-Ebbed into a 30-card library, then the engine's actual seeded shuffle primitive runs. No rule grants post-shuffle knowledge.",
        "public_known_object_id":known.0,"before_shuffle_order":before,"authority_after_shuffle_order":after,
        "authority_position":authority_position,"shuffle_events":events,"projections":projections,
        "authority_all_private_library_ids":private_ids.iter().map(|id|id.0).collect::<Vec<_>>(),
        "all_viewers_hide_known_card_position":all_hidden,"all_viewers_hide_all_private_library_ids":all_library_ids_hidden})
}

#[test]
fn tokens() {
    let mut s = scenario();
    s.add_basic_land(P0, ManaColor::White);
    s.add_basic_land(P0, ManaColor::White);
    let spell = s
        .add_spell_to_hand_from_oracle(
            P0,
            "Raise the Alarm",
            true,
            "Create two 1/1 white Soldier creature tokens.",
        )
        .with_mana_cost(cost("{1}{W}"))
        .id();
    let mut r = s.build();
    r.cast(spell).resolve();
    let tokens:Vec<_>=r.state().objects.values().filter(|o|o.is_token&&o.zone==Zone::Battlefield).map(|o|json!({"name":o.name,"power":o.power,"toughness":o.toughness,"controller":o.controller.0,"colors":o.color,"types":o.card_types})).collect();
    observe(
        "tokens",
        json!({"tokens":tokens,"spell_zone":r.state().objects[&spell].zone,"library":r.state().players[0].library.len(),"hand":r.state().players[0].hand.len()}),
    );
    assert_eq!(tokens.len(), 2);
    for token in &tokens {
        assert_eq!(token["power"], 1);
        assert_eq!(token["toughness"], 1);
        assert_eq!(token["controller"], 0);
        assert!(token["types"].to_string().contains("Soldier"));
        assert!(token["types"].to_string().contains("Creature"));
        assert!(token["colors"].to_string().contains("White"));
        assert_eq!(token["colors"].as_array().unwrap().len(), 1);
    }
    assert_eq!(r.state().objects[&spell].zone, Zone::Graveyard);
    assert_eq!(r.state().players[0].library.len(), 30);
    assert_eq!(r.state().players[0].hand.len(), 0);
}

#[test]
fn replacement() {
    let mut s = scenario();
    s.add_enchantment_from_oracle(P0,"Rest in Peace","When Rest in Peace enters, exile all graveyards.\nIf a card or token would be put into a graveyard from anywhere, exile it instead.");
    s.add_basic_land(P0, ManaColor::Red);
    let bolt = cast_bolt(&mut s, P0);
    let bears = s.add_creature(P1, "Grizzly Bears", 2, 2).id();
    let mut r = s.build();
    r.cast(bolt).target_object(bears).resolve();
    observe(
        "replacement",
        json!({"bears_zone":r.state().objects[&bears].zone,"bolt_zone":r.state().objects[&bolt].zone,"graveyards":r.state().players.iter().map(|p|p.graveyard.len()).collect::<Vec<_>>()}),
    );
    assert_eq!(r.state().objects[&bears].zone, Zone::Exile);
    assert_eq!(r.state().objects[&bolt].zone, Zone::Exile);
    assert!(r.state().players.iter().all(|p| p.graveyard.is_empty()));
}

#[test]
fn copy() {
    let mut s = scenario();
    s.add_basic_land(P0, ManaColor::Green);
    for _ in 0..4 {
        s.add_basic_land(P0, ManaColor::Blue);
    }
    let bears = s.add_creature(P1, "Grizzly Bears", 2, 2).id();
    let growth = s
        .add_spell_to_hand_from_oracle(
            P0,
            "Giant Growth",
            true,
            "Target creature gets +3/+3 until end of turn.",
        )
        .with_mana_cost(cost("{G}"))
        .id();
    let clone = s
        .add_creature_to_hand_from_oracle(
            P0,
            "Clone",
            0,
            0,
            "You may have Clone enter as a copy of any creature on the battlefield.",
        )
        .with_mana_cost(cost("{3}{U}"))
        .id();
    let mut r = s.build();
    r.cast(growth).target_object(bears).resolve();
    assert_eq!(r.state().objects[&bears].power, Some(5));
    r.cast(clone)
        .copy_target(bears)
        .accept_optional()
        .replacement_choice(0)
        .resolve();
    observe(
        "copy",
        json!({"waiting":r.state().waiting_for,"clone_zone":r.state().objects[&clone].zone,"clone_name":r.state().objects[&clone].name,"clone_power":r.state().objects[&clone].power,"clone_toughness":r.state().objects[&clone].toughness,"original_power":r.state().objects[&bears].power,"original_toughness":r.state().objects[&bears].toughness}),
    );
    assert_eq!(r.state().objects[&clone].zone, Zone::Battlefield);
    assert_eq!(r.state().objects[&clone].name, "Grizzly Bears");
    assert_eq!(r.state().objects[&clone].power, Some(2));
    assert_eq!(r.state().objects[&clone].toughness, Some(2));
    assert_eq!(r.state().objects[&bears].power, Some(5));
    assert_eq!(r.state().objects[&bears].toughness, Some(5));
}

fn commander_scenario() -> (GameScenario, ObjectId) {
    let mut s = GameScenario::new_with_format(
        engine::types::format::FormatConfig::commander(),
        4,
        20260909,
    );
    s.at_phase(Phase::PreCombatMain);
    let mut commander = ObjectId(0);
    for p in 0..4 {
        let p = PlayerId(p);
        s.with_library_top(p, &vec!["Plains"; 30]);
        let id = s
            .add_creature_to_hand(p, "Isamaru, Hound of Konda", 2, 2)
            .as_legendary()
            .with_mana_cost(cost("{W}"))
            .id();
        s.with_commander(id);
        if p == P0 {
            commander = id;
        }
    }
    (s, commander)
}

#[test]
fn commander_tax() {
    let (mut s, commander) = commander_scenario();
    let plains: Vec<_> = (0..4)
        .map(|_| s.add_basic_land(P0, ManaColor::White))
        .collect();
    for _ in 0..3 {
        s.add_basic_land(P0, ManaColor::Black);
    }
    let murder = s
        .add_spell_to_hand_from_oracle(P0, "Murder", true, "Destroy target creature.")
        .with_mana_cost(cost("{1}{B}{B}"))
        .id();
    let mut r = s.build();
    assert!(r.state().players.iter().all(|p| p.life == 40));
    assert_eq!(r.state().command_zone.len(), 4);
    r.cast(commander).resolve();
    assert_eq!(r.state().objects[&commander].zone, Zone::Battlefield);
    let paid_first = plains
        .iter()
        .filter(|id| r.state().objects[id].tapped)
        .count();
    assert_eq!(paid_first, 1);
    r.cast(murder).target_object(commander).resolve();
    let offered = matches!(
        r.state().waiting_for,
        WaitingFor::CommanderZoneChoice { .. }
    );
    assert!(offered);
    r.act(GameAction::DecideOptionalEffect { accept: true })
        .unwrap();
    assert_eq!(r.state().objects[&commander].zone, Zone::Command);
    let mut insufficient = r.state().clone();
    // Independent branch fixture limits available mana to W before admission.
    for id in &plains {
        insufficient.objects.get_mut(id).unwrap().tapped = true;
    }
    insufficient.objects.get_mut(&plains[1]).unwrap().tapped = false;
    let swamps: Vec<_> = insufficient
        .objects
        .iter()
        .filter(|(_, o)| o.card_types.subtypes.contains(&"Swamp".to_string()))
        .map(|(id, _)| *id)
        .collect();
    for id in swamps {
        insufficient.objects.get_mut(&id).unwrap().tapped = true;
    }
    let insufficient_rejected =
        !engine::game::casting::can_cast_object_now(&insufficient, P0, commander);
    assert!(insufficient_rejected);
    let tax = engine::game::commander::commander_tax(r.state(), commander);
    assert_eq!(tax, 2);
    let before = r
        .state()
        .objects
        .values()
        .filter(|o| o.zone == Zone::Battlefield && o.tapped)
        .count();
    r.cast(commander).resolve();
    let paid_second = r
        .state()
        .objects
        .values()
        .filter(|o| o.zone == Zone::Battlefield && o.tapped)
        .count()
        - before;
    observe(
        "commander_tax",
        json!({"starting_life":[40,40,40,40],"starting_commanders":4,"first_paid":paid_first,"return_offered":offered,"tax":tax,"insufficient_W_rejected":insufficient_rejected,"second_paid":paid_second,"commander_zone":r.state().objects[&commander].zone}),
    );
    assert_eq!(paid_second, 3);
    assert_eq!(r.state().objects[&commander].zone, Zone::Battlefield);
}

#[test]
fn commander_damage() {
    let (mut s, commander) = commander_scenario();
    s.add_basic_land(P0, ManaColor::White);
    for _ in 0..3 {
        s.add_basic_land(P0, ManaColor::Red);
    }
    let fire = s
        .add_spell_to_hand_from_oracle(
            P0,
            "Soul's Fire",
            true,
            "Target creature you control deals damage equal to its power to any target.",
        )
        .with_mana_cost(cost("{2}{R}"))
        .id();
    let mut r = s.build();
    r.cast(commander).resolve();
    // Precombat fixture: commander controlled since turn start; 19 prior combat damage.
    r.state_mut()
        .objects
        .get_mut(&commander)
        .unwrap()
        .summoning_sick = false;
    r.state_mut()
        .commander_damage
        .push(engine::types::game_state::CommanderDamageEntry {
            player: P1,
            commander,
            damage: 19,
        });
    let mut noncombat = GameRunner::from_state(r.state().clone());
    noncombat
        .cast(fire)
        .target_object(commander)
        .target_player(P1)
        .resolve();
    let noncombat_total = noncombat
        .state()
        .commander_damage
        .iter()
        .find(|d| d.player == P1 && d.commander == commander)
        .unwrap()
        .damage;
    assert_eq!(noncombat_total, 19);
    assert_eq!(noncombat.state().players[1].life, 38);
    r.advance_to_combat();
    r.declare_attackers(&[(commander, AttackTarget::Player(P1))])
        .unwrap();
    for _ in 0..20 {
        match r.state().waiting_for {
            WaitingFor::DeclareBlockers { .. } => {
                r.declare_blockers(&[]).unwrap();
            }
            WaitingFor::Priority { .. } => pass(&mut r),
            _ => break,
        }
        if r.state().players[1].is_eliminated {
            break;
        }
    }
    let total = r
        .state()
        .commander_damage
        .iter()
        .find(|d| d.player == P1 && d.commander == commander)
        .map(|d| d.damage);
    let waiting_after_damage = r.state().waiting_for.clone();
    let survivor = waiting_after_damage
        .acting_player()
        .filter(|p| !r.state().players[p.0 as usize].is_eliminated);
    let before_continuation = serde_json::to_value(r.state()).unwrap();
    let continued = if let Some(actor) = survivor {
        matches!(r.state().waiting_for, WaitingFor::Priority { .. })
            && apply(r.state_mut(), actor, GameAction::PassPriority).is_ok()
            && serde_json::to_value(r.state()).unwrap() != before_continuation
    } else {
        false
    };
    observe(
        "commander_damage",
        json!({"combat_total":total,"defender_life":r.state().players[1].life,"defender_eliminated":r.state().players[1].is_eliminated,"alive":r.state().players.iter().filter(|p|!p.is_eliminated).count(),"noncombat_total":noncombat_total,"noncombat_life":noncombat.state().players[1].life,"waiting":waiting_after_damage,"surviving_actor":survivor,"surviving_priority_action_accepted_and_progressed":continued,"after_continuation_waiting":r.state().waiting_for}),
    );
    assert_eq!(total, Some(21));
    assert!(r.state().players[1].is_eliminated);
    assert_eq!(r.state().players[1].life, 38);
    assert_eq!(
        r.state()
            .players
            .iter()
            .filter(|p| !p.is_eliminated)
            .count(),
        3
    );
    assert!(!matches!(
        r.state().waiting_for,
        WaitingFor::GameOver { .. }
    ));
    assert!(
        continued,
        "continued game requires an actual surviving actor's accepted priority action and changed state; no actor or an eliminated seat's commander choice is insufficient"
    );
}

#[test]
fn morph() {
    let mut s = scenario();
    for _ in 0..3 {
        s.add_basic_land(P0, ManaColor::White);
    }
    for _ in 0..2 {
        s.add_basic_land(P0, ManaColor::Blue);
    }
    let card=s.add_creature_to_hand_from_oracle(P0,"Willbender",1,2,"Morph {1}{U}\nWhen Willbender is turned face up, change the target of target spell or ability with a single target.").with_mana_cost(cost("{1}{U}")).id();
    let mut r = s.build();
    let committed = r
        .cast(card)
        .casting_variant(engine::types::game_state::CastingVariant::FaceDown)
        .alternative_cast(engine::types::actions::AlternativeCastDecision::Alternative)
        .commit();
    assert_eq!(committed.state().stack.len(), 1);
    drop(committed);
    let stack = r.state().objects[&card].clone();
    let paid_down = r
        .state()
        .objects
        .values()
        .filter(|o| o.zone == Zone::Battlefield && o.tapped)
        .count();
    let mut privacy = Vec::new();
    let mut leaks = Vec::new();
    for viewer in [P1, PlayerId(255)] {
        let view = filter_state_for_viewer(r.state(), viewer);
        let value = serde_json::to_value(&view).unwrap();
        let text = value.to_string();
        privacy.push(!text.contains("Willbender"));
        collect_identity_paths(&value, "", &mut leaks);
        std::fs::write(
            std::path::PathBuf::from(std::env::var("HEXPROOF_EVAL_OUTPUT").unwrap())
                .join(format!("morph-stack-view-{}.json", viewer.0)),
            serde_json::to_string_pretty(&value).unwrap(),
        )
        .unwrap();
    }
    r.advance_until_stack_empty();
    let down = r.state().objects[&card].clone();
    for viewer in [P1, PlayerId(255)] {
        let view = filter_state_for_viewer(r.state(), viewer);
        let value = serde_json::to_value(&view).unwrap();
        let text = value.to_string();
        privacy.push(!text.contains("Willbender"));
        collect_identity_paths(&value, "", &mut leaks);
        std::fs::write(
            std::path::PathBuf::from(std::env::var("HEXPROOF_EVAL_OUTPUT").unwrap())
                .join(format!("morph-battlefield-view-{}.json", viewer.0)),
            serde_json::to_string_pretty(&value).unwrap(),
        )
        .unwrap();
    }
    r.act(GameAction::TurnFaceUp {
        object_id: card,
        x: 0,
    })
    .unwrap();
    let up = &r.state().objects[&card];
    let paid_total = r
        .state()
        .objects
        .values()
        .filter(|o| o.zone == Zone::Battlefield && o.tapped)
        .count();
    observe(
        "morph",
        json!({"leak_paths":leaks,"paid_face_down":paid_down,"paid_total_after_face_up":paid_total,"stack_name":stack.name,"stack_power":stack.power,"stack_toughness":stack.toughness,"down_name":down.name,"down_power":down.power,"down_toughness":down.toughness,"down_color":down.color,"down_abilities":down.abilities.len(),"privacy":privacy,"same_object":up.id==card,"up_name":up.name,"up_power":up.power,"up_toughness":up.toughness,"waiting":r.state().waiting_for}),
    );
    assert!(privacy.iter().all(|v| *v));
    assert!(stack.name.is_empty());
    assert_eq!(paid_down, 3);
    assert_eq!(paid_total, 5);
    assert_eq!(stack.power, Some(2));
    assert_eq!(stack.toughness, Some(2));
    assert!(stack.color.is_empty());
    assert!(stack.abilities.is_empty());
    assert_eq!(stack.mana_cost, ManaCost::NoCost);
    assert_eq!(down.mana_cost, ManaCost::NoCost);
    assert!(down.name.is_empty());
    assert_eq!(down.power, Some(2));
    assert_eq!(down.toughness, Some(2));
    assert!(down.color.is_empty());
    assert!(down.abilities.is_empty());
    assert_eq!(up.name, "Willbender");
    assert_eq!(up.power, Some(1));
    assert_eq!(up.toughness, Some(2));
    assert_eq!(up.id, card);
}

fn collect_identity_paths(value: &Value, path: &str, found: &mut Vec<String>) {
    match value {
        Value::String(s) if s.contains("Willbender") => found.push(path.to_string()),
        Value::Array(items) => {
            for (i, v) in items.iter().enumerate() {
                collect_identity_paths(v, &format!("{path}/{i}"), found);
            }
        }
        Value::Object(items) => {
            for (k, v) in items {
                collect_identity_paths(v, &format!("{path}/{k}"), found);
            }
        }
        _ => {}
    }
}

#[test]
fn adventure() {
    let mut s = scenario();
    for _ in 0..4 {
        s.add_basic_land(P0, ManaColor::Green);
    }
    let beast = s
        .add_creature_to_hand_from_oracle(
            P0,
            "Lovestruck Beast",
            5,
            5,
            "Lovestruck Beast can't attack unless you control a 1/1 creature.",
        )
        .with_mana_cost(cost("{2}{G}"))
        .id();
    // Parse the printed second face independently, then attach that initial
    // card-face data through Phase's own face-snapshot API.
    let mut faces = GameScenario::new();
    let desire = faces
        .add_spell_to_hand_from_oracle(
            P0,
            "Heart's Desire",
            false,
            "Create a 1/1 white Human creature token.",
        )
        .with_mana_cost(cost("{G}"))
        .id();
    let face_runner = faces.build();
    let mut back =
        engine::game::printed_cards::snapshot_object_face(&face_runner.state().objects[&desire]);
    back.layout_kind = Some(engine::types::card::LayoutKind::Adventure);
    back.is_swap_snapshot = false;
    back.card_types.subtypes.push("Adventure".to_string());
    back.color = vec![ManaColor::Green];
    let mut r = s.build();
    r.state_mut().objects.get_mut(&beast).unwrap().back_face = Some(back);
    r.cast(beast).adventure_face(false).resolve();
    let exiled = r.state().objects[&beast].zone;
    let tokens: Vec<_> = r.state().objects.values().filter(|o| o.is_token && o.zone==Zone::Battlefield)
        .map(|o| json!({"power":o.power,"toughness":o.toughness,"types":o.card_types,"color":o.color,"controller":o.controller.0})).collect();
    observe(
        "adventure",
        json!({"stage":"after-adventure","exiled_zone":exiled,"tokens":tokens,"waiting":r.state().waiting_for}),
    );
    assert_eq!(exiled, Zone::Exile);
    assert_eq!(tokens.len(), 1);
    assert_eq!(tokens[0]["power"], 1);
    assert_eq!(tokens[0]["toughness"], 1);
    assert_eq!(tokens[0]["controller"], 0);
    assert!(tokens[0]["types"].to_string().contains("Human"));
    assert!(tokens[0]["types"].to_string().contains("Creature"));
    assert_eq!(tokens[0]["color"], json!(["White"]));
    let paid_first = r
        .state()
        .objects
        .values()
        .filter(|o| o.zone == Zone::Battlefield && o.tapped)
        .count();
    assert_eq!(paid_first, 1);
    r.cast(beast).adventure_face(true).resolve();
    let final_card = &r.state().objects[&beast];
    let paid_total = r
        .state()
        .objects
        .values()
        .filter(|o| o.zone == Zone::Battlefield && o.tapped)
        .count();
    observe(
        "adventure",
        json!({"exiled_zone":exiled,"tokens":tokens,"paid_adventure":paid_first,"paid_total":paid_total,
        "creature_name":final_card.name,"creature_zone":final_card.zone,"power":final_card.power,"toughness":final_card.toughness,"same_card":final_card.id==beast}),
    );
    assert_eq!(final_card.name, "Lovestruck Beast");
    assert_eq!(final_card.zone, Zone::Battlefield);
    assert_eq!(final_card.power, Some(5));
    assert_eq!(final_card.toughness, Some(5));
    assert_eq!(paid_total, 4);
}

#[test]
fn modal_dfc() {
    let mut s = scenario();
    let recovery = s
        .add_spell_to_hand_from_oracle(
            P0,
            "Bala Ged Recovery",
            false,
            "Return target card from your graveyard to your hand.",
        )
        .with_mana_cost(cost("{2}{G}"))
        .id();
    let mut faces = GameScenario::new();
    let sanctuary = faces
        .add_land_from_oracle(
            P0,
            "Bala Ged Sanctuary",
            "Bala Ged Sanctuary enters tapped.\n{T}: Add {G}.",
        )
        .id();
    let face_runner = faces.build();
    let mut back =
        engine::game::printed_cards::snapshot_object_face(&face_runner.state().objects[&sanctuary]);
    back.layout_kind = Some(engine::types::card::LayoutKind::Modal);
    back.is_swap_snapshot = false;
    let mut r = s.build();
    r.state_mut().objects.get_mut(&recovery).unwrap().back_face = Some(back);
    let card_id = r.state().objects[&recovery].card_id;
    r.act(GameAction::PlayLand {
        object_id: recovery,
        card_id,
    })
    .unwrap();
    let entered = r.state().objects[&recovery].clone();
    observe(
        "modal_dfc",
        json!({"stage":"land-entry","name":entered.name,"zone":entered.zone,"tapped":entered.tapped,"types":entered.card_types,"waiting":r.state().waiting_for}),
    );
    assert_eq!(entered.name, "Bala Ged Sanctuary");
    assert_eq!(entered.zone, Zone::Battlefield);
    assert!(entered.tapped);
    assert!(
        entered
            .card_types
            .core_types
            .contains(&engine::types::card_type::CoreType::Land)
    );
    assert!(r.state().stack.is_empty());
    assert!(r.state().players[0].hand.is_empty());
    assert!(r.state().players[0].graveyard.is_empty());
    // Advance real turns, including automatic untap, not a fixture untap.
    for _ in 0..120 {
        if !r.state().objects[&recovery].tapped
            && r.state().active_player == P0
            && r.state().phase == Phase::PreCombatMain
        {
            break;
        }
        match r.state().waiting_for {
            WaitingFor::Priority { .. } => pass(&mut r),
            WaitingFor::DeclareAttackers { .. } => {
                r.declare_attackers(&[]).unwrap();
            }
            WaitingFor::DeclareBlockers { .. } => {
                r.declare_blockers(&[]).unwrap();
            }
            _ => panic!("unhandled MDFC turn prompt: {:?}", r.state().waiting_for),
        }
    }
    assert!(!r.state().objects[&recovery].tapped);
    // Human grouped actions retain manual mana activation; AI search candidates
    // intentionally omit it outside payment to avoid search-tree pollution.
    let (_, _, grouped) = engine::ai_support::legal_actions_full(r.state());
    let actions = grouped.get(&recovery).cloned().unwrap_or_default();
    observe(
        "modal_dfc",
        json!({"stage":"after-real-untap","land":r.state().objects[&recovery],"actions":actions,"waiting":r.state().waiting_for}),
    );
    let action = actions
        .into_iter()
        .find(|a| matches!(a,GameAction::TapLandForMana { selection } | GameAction::ActivateManaSource { selection } if selection.source.object_id==recovery))
        .expect("land mana action must be offered");
    r.act(action).unwrap();
    let green = r.state().players[0]
        .mana_pool
        .count_color(engine::types::mana::ManaType::Green);
    observe(
        "modal_dfc",
        json!({"entry_name":entered.name,"entered_tapped":entered.tapped,"entry_land":true,"no_sorcery_effect":true,
        "final_tapped":r.state().objects[&recovery].tapped,"green_mana":green,"phase":r.state().phase,"active":r.state().active_player.0}),
    );
    assert!(r.state().objects[&recovery].tapped);
    assert_eq!(green, 1);
}

fn prepare_fixture(removal: bool) -> (GameRunner, ObjectId, Option<ObjectId>) {
    prepare_fixture_with_restriction(removal, false)
}

fn prepare_fixture_with_restriction(
    removal: bool,
    restricted: bool,
) -> (GameRunner, ObjectId, Option<ObjectId>) {
    let mut s = scenario();
    if restricted {
        s.add_creature_from_oracle(
            P1,
            "Drannith Magistrate",
            1,
            3,
            "Your opponents can't cast spells from anywhere other than their hands.",
        );
    }
    for _ in 0..3 {
        s.add_basic_land(P0, ManaColor::Red);
    }
    let glass = s
        .add_creature_to_hand_from_oracle(
            P0,
            "Goblin Glasswright",
            2,
            2,
            "This creature enters prepared.",
        )
        .with_mana_cost(cost("{1}{R}"))
        .id();
    let bolt = if removal {
        s.add_basic_land(P1, ManaColor::Red);
        Some(cast_bolt(&mut s, P1))
    } else {
        None
    };
    let mut faces = GameScenario::new();
    let craft = faces
        .add_spell_to_hand_from_oracle(P0, "Craft with Pride", false, "Create a Treasure token.")
        .with_mana_cost(cost("{R}"))
        .id();
    let face_runner = faces.build();
    let mut back =
        engine::game::printed_cards::snapshot_object_face(&face_runner.state().objects[&craft]);
    back.layout_kind = Some(engine::types::card::LayoutKind::Prepare);
    back.is_swap_snapshot = false;
    back.color = vec![ManaColor::Red];
    let mut r = s.build();
    r.state_mut().objects.get_mut(&glass).unwrap().back_face = Some(back);
    (r, glass, bolt)
}

fn prepared_copies(r: &GameRunner, source: ObjectId) -> Vec<ObjectId> {
    r.state()
        .objects
        .values()
        .filter(|o| o.prepared_copy_source == Some(source) && o.zone == Zone::Exile)
        .map(|o| o.id)
        .collect()
}

#[test]
fn prepare_cast() {
    let (mut r, glass, _) = prepare_fixture(false);
    let before = serde_json::to_value(r.state()).unwrap();
    let hand_cast = r.act(GameAction::CastPreparedCopy { source: glass });
    let hand_unchanged = before == serde_json::to_value(r.state()).unwrap();
    assert!(hand_cast.is_err() && hand_unchanged);
    r.cast(glass).resolve();
    let copies = prepared_copies(&r, glass);
    observe(
        "prepare_cast",
        json!({"stage":"prepared-entry","source":r.state().objects[&glass],"copies":copies,"hand_cast_rejected":hand_cast.is_err(),"hand_unchanged":hand_unchanged}),
    );
    assert!(r.state().objects[&glass].prepared.is_some());
    assert_eq!(r.state().objects[&glass].power, Some(2));
    assert_eq!(r.state().objects[&glass].toughness, Some(2));
    let paid_creature = r
        .state()
        .objects
        .values()
        .filter(|o| o.zone == Zone::Battlefield && o.tapped)
        .count();
    assert_eq!(paid_creature, 2);
    r.act(GameAction::CastPreparedCopy { source: glass })
        .unwrap();
    let copy = r
        .state()
        .objects
        .values()
        .find(|o| o.prepared_copy_source == Some(glass) && o.zone == Zone::Stack)
        .expect("cast must materialize real stack copy")
        .id;
    let on_stack = r.state().objects.get(&copy).map(|o| o.zone) == Some(Zone::Stack);
    let unprepared = r.state().objects[&glass].prepared.is_none();
    let paid_total = r
        .state()
        .objects
        .values()
        .filter(|o| o.zone == Zone::Battlefield && o.tapped)
        .count();
    observe(
        "prepare_cast",
        json!({"stage":"cast-copy","on_stack":on_stack,"unprepared":unprepared,"paid_total":paid_total,"waiting":r.state().waiting_for}),
    );
    assert!(on_stack && unprepared);
    assert_eq!(paid_total, 3);
    r.advance_until_stack_empty();
    let treasures: Vec<_> = r
        .state()
        .objects
        .values()
        .filter(|o| o.is_token && o.zone == Zone::Battlefield)
        .map(|o| json!({"name":o.name,"types":o.card_types,"controller":o.controller.0}))
        .collect();
    let copy_gone = !r.state().objects.contains_key(&copy);
    let recast = r.act(GameAction::CastPreparedCopy { source: glass });
    observe(
        "prepare_cast",
        json!({"hand_cast_rejected":true,"hand_unchanged":hand_unchanged,"associated_exile_copies":copies,"entered_prepared":true,"source_id":glass,"on_stack":on_stack,"unprepared":unprepared,"paid_creature":paid_creature,"paid_total":paid_total,"treasures":treasures,"copy_gone":copy_gone,"recast_rejected":recast.is_err()}),
    );
    assert_eq!(treasures.len(), 1);
    assert!(treasures[0]["types"].to_string().contains("Treasure"));
    assert!(treasures[0]["types"].to_string().contains("Artifact"));
    assert_eq!(treasures[0]["controller"], 0);
    assert!(copy_gone && recast.is_err());
    assert_eq!(
        copies.len(),
        1,
        "entering prepared must immediately create a linked exile copy, not defer creation until casting"
    );
}

#[test]
fn prepare_source_leaves() {
    let (mut r, glass, bolt) = prepare_fixture(true);
    r.cast(glass).resolve();
    let copies = prepared_copies(&r, glass);
    observe(
        "prepare_source_leaves",
        json!({"stage":"prepared-entry","source":r.state().objects[&glass],"copies":copies}),
    );
    assert!(r.state().objects[&glass].prepared.is_some());
    pass(&mut r);
    r.cast(bolt.unwrap()).target_object(glass).resolve();
    let copy_gone = copies
        .iter()
        .all(|copy| !r.state().objects.contains_key(copy));
    let source_zone = r.state().objects[&glass].zone;
    let recast = r.act(GameAction::CastPreparedCopy { source: glass });
    observe(
        "prepare_source_leaves",
        json!({"associated_exile_copies_before":copies,"source_zone":source_zone,"copy_gone":copy_gone,"copy_unavailable":recast.is_err(),"bolt_zone":r.state().objects[&bolt.unwrap()].zone}),
    );
    assert_eq!(source_zone, Zone::Graveyard);
    assert!(copy_gone && recast.is_err());
    assert_eq!(
        copies.len(),
        1,
        "no linked copy existed before real Bolt removal, so this is not a successful cleanup qualification"
    );
}

#[test]
fn supplemental_prepare_cast_restriction() {
    let (mut r, glass, _) = prepare_fixture_with_restriction(false, true);
    r.cast(glass).resolve();
    assert!(r.state().objects[&glass].prepared.is_some());
    let actions = engine::ai_support::legal_actions(r.state());
    let offered = actions
        .iter()
        .any(|a| matches!(a,GameAction::CastPreparedCopy{source} if *source==glass));
    let before = serde_json::to_value(r.state()).unwrap();
    let cast = r.act(GameAction::CastPreparedCopy { source: glass });
    let unchanged = before == serde_json::to_value(r.state()).unwrap();
    observe(
        "supplemental_prepare_cast_restriction",
        json!({"restriction":"Drannith Magistrate: opponent cannot cast outside hand","source_prepared":r.state().objects[&glass].prepared.is_some(),"prepared_action_offered":offered,"cast_rejected":cast.is_err(),"unchanged":unchanged,"error":format!("{:?}",cast)}),
    );
    assert!(
        !offered && cast.is_err() && unchanged,
        "a lazily represented prepared copy must still obey its real exile casting restriction"
    );
}
