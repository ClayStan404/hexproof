// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors
//! Independent owner-selected semantics through the pinned public engine API.
use forge_carddb::parse_card_script;
use forge_foundation::{PhaseType, ZoneType};
use manabrew_engine::agent::{
    ManaAbilityOption, ManaCostAction, PlayCardMode, PlayerAgent, PriorityActionSpace, TargetChoice,
};
use manabrew_engine::card::CardInstance;
use manabrew_engine::combat::DefenderId;
use manabrew_engine::game::GameState;
use manabrew_engine::game_loop::GameLoop;
use manabrew_engine::ids::{CardId, PlayerId};
use manabrew_engine::mana::ManaPool;
use manabrew_engine::player::actions::PlayerAction;
use manabrew_engine::spellability::SpellAbility;
use rand::SeedableRng;
use serde_json::{Value, json};
use std::collections::VecDeque;
use std::sync::{Arc, Mutex};

const A: PlayerId = PlayerId(0);
const B: PlayerId = PlayerId(1);

fn observation(id: &str, value: Value) {
    println!(
        "HEXPROOF_OBSERVATION {}",
        json!({"case_id": id, "observations": value})
    );
}

fn card(game: &mut GameState, owner: PlayerId, script: &str, zone: ZoneType) -> CardId {
    let path =
        std::path::PathBuf::from(std::env::var("HEXPROOF_CARD_SCRIPTS").unwrap()).join(script);
    let text = std::fs::read_to_string(path).expect("fixture card script must exist");
    let rules = parse_card_script(&text).expect("pinned real card script parses");
    let id = game.create_card(CardInstance::from_rules(&rules, owner));
    game.move_card(id, zone, owner);
    id
}

#[derive(Default)]
struct Control {
    plays: VecDeque<CardId>,
    target: Option<CardId>,
    attack: Option<CardId>,
    block: Option<CardId>,
    concede: bool,
    snapshots: Vec<Value>,
    choices: usize,
    legal: Vec<CardId>,
    mode: Option<PlayCardMode>,
    activations: VecDeque<CardId>,
    mana_actions: VecDeque<CardId>,
    legal_details: Vec<Value>,
    confirmations: Vec<String>,
    prefer_player_target: bool,
    external: Option<(
        std::sync::mpsc::Sender<Value>,
        std::sync::mpsc::Receiver<(PlayerId, PlayerAction)>,
    )>,
}

struct Bridge(Arc<Mutex<Control>>);

impl PlayerAgent for Bridge {
    fn mulligan_decision(&mut self, _: PlayerId, _: &[CardId], _: u32) -> bool {
        true
    }
    fn snapshot_state(&mut self, game: &GameState, _: &[ManaPool]) {
        self.0.lock().unwrap().snapshots.push(json!({
            "phase": format!("{:?}", game.turn.phase), "priority": game.turn.priority_player.0,
            "stack": game.stack.len(), "stack_names": game.stack.iter().map(|e|e.spell_ability.source.map(|id|game.card(id).card_name.clone())).collect::<Vec<_>>(),
            "stack_details": game.stack.iter().map(|e|json!({"trigger":e.spell_ability.is_trigger,"source_zone":e.spell_ability.source.map(|id|format!("{:?}",game.card(id).zone))})).collect::<Vec<_>>(),
            "life": game.players.iter().map(|p|p.life).collect::<Vec<_>>(),
            "hands":game.player_order.iter().map(|p|game.cards_in_zone(ZoneType::Hand,*p).len()).collect::<Vec<_>>(),
            "libraries":game.player_order.iter().map(|p|game.cards_in_zone(ZoneType::Library,*p).len()).collect::<Vec<_>>()
        }));
    }
    fn choose_action(
        &mut self,
        player: PlayerId,
        offered: Option<&PriorityActionSpace>,
        request: &mut dyn FnMut() -> PriorityActionSpace,
    ) -> PlayerAction {
        let requested;
        let space = if let Some(s) = offered {
            s
        } else {
            requested = request();
            &requested
        };
        let mut plan = self.0.lock().unwrap();
        plan.choices += 1;
        assert!(
            plan.choices < 200,
            "adapter exceeded bounded decision count"
        );
        plan.legal = space.playable.iter().map(|p| p.card_id).collect();
        plan.legal_details.push(json!({"playable":space.playable,"activatable":space.activatable.iter().map(|a|json!({"card":a.card_id.0,"index":a.ability_index,"description":a.description})).collect::<Vec<_>>(),"tappable":space.tappable_lands}));
        if let Some((prompt, replies)) = &plan.external {
            prompt.send(json!({"kind":"decision","owner":player.0,"playable":space.playable,"snapshot":plan.snapshots.last()})).unwrap();
            for _ in 0..8 {
                let (actor, action) = replies
                    .recv_timeout(std::time::Duration::from_secs(10))
                    .expect("external controller must reply");
                if actor == player {
                    return action;
                }
                prompt.send(json!({"kind":"rejected_wrong_actor","actor":actor.0,"owner":player.0,"snapshot":plan.snapshots.last()})).unwrap();
            }
            panic!("too many unauthorized external responses");
        }
        if plan.concede {
            plan.concede = false;
            return PlayerAction::Concede;
        }
        if let Some(id) = plan.plays.front().copied() {
            if let Some(play) = space
                .playable
                .iter()
                .find(|p| p.card_id == id && plan.mode.is_none_or(|mode| p.mode == mode))
            {
                plan.plays.pop_front();
                return PlayerAction::CastSpell(*play);
            }
        }
        if let Some(id) = plan.activations.front().copied() {
            if let Some(action) = space.activatable.iter().find(|a| a.card_id == id) {
                plan.activations.pop_front();
                return PlayerAction::ActivateAbility(
                    manabrew_engine::player::actions::AbilityRef {
                        card_id: id,
                        ability_index: action.ability_index,
                    },
                );
            }
        }
        if let Some(id) = plan.mana_actions.front().copied() {
            if space.tappable_lands.contains(&id) {
                plan.mana_actions.pop_front();
                return PlayerAction::ActivateMana(id, None, None);
            }
        }
        PlayerAction::PassPriority
    }
    fn choose_attackers(
        &mut self,
        _: PlayerId,
        available: &[CardId],
        defenders: &[DefenderId],
    ) -> Vec<(CardId, DefenderId)> {
        self.0
            .lock()
            .unwrap()
            .attack
            .filter(|a| available.contains(a))
            .and_then(|a| defenders.first().map(|d| vec![(a, *d)]))
            .unwrap_or_default()
    }
    fn choose_blockers(
        &mut self,
        _: PlayerId,
        attackers: &[CardId],
        available: &[CardId],
        _: Option<usize>,
    ) -> Vec<(CardId, CardId)> {
        self.0
            .lock()
            .unwrap()
            .block
            .filter(|b| available.contains(b))
            .and_then(|b| attackers.first().map(|a| vec![(b, *a)]))
            .unwrap_or_default()
    }
    fn choose_target_player(
        &mut self,
        _: PlayerId,
        valid: &[PlayerId],
        _: Option<&SpellAbility>,
    ) -> Option<PlayerId> {
        valid.iter().copied().find(|p| *p == B)
    }
    fn choose_target_card(
        &mut self,
        _: PlayerId,
        valid: &[CardId],
        _: Option<&SpellAbility>,
    ) -> Option<CardId> {
        self.0
            .lock()
            .unwrap()
            .target
            .filter(|c| valid.contains(c))
            .or_else(|| valid.first().copied())
    }
    fn choose_target_any(
        &mut self,
        _: PlayerId,
        players: &[PlayerId],
        cards: &[CardId],
        _: Option<&SpellAbility>,
    ) -> TargetChoice {
        if self.0.lock().unwrap().prefer_player_target && players.contains(&B) {
            return TargetChoice::Player(B);
        }
        if let Some(c) = self.0.lock().unwrap().target.filter(|c| cards.contains(c)) {
            TargetChoice::Card(c)
        } else if players.contains(&B) {
            TargetChoice::Player(B)
        } else {
            TargetChoice::None
        }
    }
    fn choose_targets_for(
        &mut self,
        sa: &mut SpellAbility,
        game: &GameState,
        pools: &[ManaPool],
    ) -> bool {
        manabrew_engine::spellability::choose_targets_by_kind(self, sa, game, pools)
    }
    fn choose_land_or_spell(&mut self, _: PlayerId) -> Option<bool> {
        Some(true)
    }
    fn confirm_action(
        &mut self,
        _: PlayerId,
        _: Option<&str>,
        message: &str,
        _: &[String],
        _: Option<CardId>,
        _: Option<manabrew_engine::ability::api_type::ApiType>,
    ) -> bool {
        self.0
            .lock()
            .unwrap()
            .confirmations
            .push(message.to_string());
        true
    }
    fn pay_mana_cost(
        &mut self,
        _: PlayerId,
        _: CardId,
        _: &str,
        _: &str,
        _: &str,
        _: &str,
        _: bool,
        _: bool,
        _: &[CardId],
        _: &[ManaAbilityOption],
        _: &[CardId],
        _: &[CardId],
        _: &ManaPool,
    ) -> ManaCostAction {
        ManaCostAction::Pay { auto: true }
    }
}

fn setup(
    count: usize,
) -> (
    GameState,
    GameLoop,
    Vec<Box<dyn PlayerAgent>>,
    Vec<Arc<Mutex<Control>>>,
) {
    let names: Vec<_> = (0..count)
        .map(|n| format!("Qualification seat {n}"))
        .collect();
    let refs: Vec<_> = names.iter().map(String::as_str).collect();
    let mut game = GameState::new(&refs, 20);
    game.turn.phase = PhaseType::Main1;
    game.turn.active_player = A;
    game.turn.priority_player = A;
    for p in 0..count {
        for _ in 0..30 {
            card(
                &mut game,
                PlayerId(p as u32),
                "p/plains.txt",
                ZoneType::Library,
            );
        }
    }
    let plans: Vec<_> = (0..count)
        .map(|_| Arc::new(Mutex::new(Control::default())))
        .collect();
    let agents = plans
        .iter()
        .map(|p| Box::new(Bridge(p.clone())) as Box<dyn PlayerAgent>)
        .collect();
    let mut driver = GameLoop::new(count);
    driver.set_provide_priority_action_space(false);
    (game, driver, agents, plans)
}

#[test]
fn opening() {
    let (mut game, mut driver, mut agents, plans) = setup(2);
    for p in [A, B] {
        for _ in 0..30 {
            card(&mut game, p, "p/plains.txt", ZoneType::Library);
        }
    }
    driver.setup(
        &mut game,
        &mut agents,
        &mut rand::rngs::StdRng::seed_from_u64(20260909),
    );
    let hands: Vec<_> = [A, B]
        .map(|p| game.cards_in_zone(ZoneType::Hand, p).len())
        .into();
    let libraries: Vec<_> = [A, B]
        .map(|p| game.cards_in_zone(ZoneType::Library, p).len())
        .into();
    let starting_player = game.active_player();
    driver.run_turn(
        &mut game,
        &mut agents,
        &mut rand::rngs::StdRng::seed_from_u64(20260909),
    );
    let snapshots = plans[0].lock().unwrap().snapshots.clone();
    let main = snapshots
        .iter()
        .find(|v| v["phase"] == "Main1" && v["hands"] == json!([7, 7]))
        .cloned();
    observation(
        "opening",
        json!({"hands":hands,"libraries":libraries,"starting_player":starting_player.0,"first_main":main,"life":[game.player(A).life,game.player(B).life]}),
    );
    assert_eq!(hands, vec![7, 7]);
    assert_eq!(libraries, vec![53, 53]);
    assert_eq!(starting_player, A);
    assert!(main.is_some());
}

#[test]
fn land_priority() {
    let (mut game, mut driver, mut agents, plans) = setup(2);
    let first = card(&mut game, A, "p/plains.txt", ZoneType::Hand);
    let second = card(&mut game, A, "p/plains.txt", ZoneType::Hand);
    let (prompt_send, prompt_recv) = std::sync::mpsc::channel();
    let (reply_send, reply_recv) = std::sync::mpsc::channel();
    plans[0].lock().unwrap().external = Some((prompt_send, reply_recv));
    let controller = std::thread::spawn(move || {
        let first_prompt = prompt_recv
            .recv_timeout(std::time::Duration::from_secs(10))
            .unwrap();
        reply_send
            .send((
                B,
                PlayerAction::CastSpell(manabrew_engine::agent::PlayOption::normal(first)),
            ))
            .unwrap();
        let rejection = prompt_recv
            .recv_timeout(std::time::Duration::from_secs(10))
            .unwrap();
        assert_eq!(rejection["kind"], "rejected_wrong_actor");
        assert_eq!(first_prompt["snapshot"], rejection["snapshot"]);
        reply_send
            .send((
                A,
                PlayerAction::CastSpell(manabrew_engine::agent::PlayOption::normal(first)),
            ))
            .unwrap();
        let second_prompt = prompt_recv
            .recv_timeout(std::time::Duration::from_secs(10))
            .unwrap();
        reply_send.send((A, PlayerAction::PassPriority)).unwrap();
        (first_prompt, rejection, second_prompt)
    });
    driver.step_main_phase(&mut game, &mut agents);
    let (first_prompt, rejection, second_prompt) = controller.join().unwrap();
    let count = game.cards_in_zone(ZoneType::Battlefield, A).len();
    let plan = plans[0].lock().unwrap();
    observation(
        "land_priority",
        json!({"lands":count,"second_zone":format!("{:?}",game.card(second).zone),"second_advertised":plan.legal.contains(&second),"decisions":plan.choices,"first_prompt":first_prompt,"wrong_actor_rejection":rejection,"second_prompt":second_prompt,"snapshots":plan.snapshots,"human_control":"Engine thread blocked on external response channel; host rejects a different actor without advancing state."}),
    );
    assert_eq!(count, 1);
    assert_eq!(game.card(second).zone, ZoneType::Hand);
    assert!(!plan.legal.contains(&second));
}

fn bolt(creature: bool, counter: bool) {
    let (mut game, mut driver, mut agents, plans) = setup(2);
    let mountain = card(&mut game, A, "m/mountain.txt", ZoneType::Battlefield);
    let spell = card(&mut game, A, "l/lightning_bolt.txt", ZoneType::Hand);
    plans[0].lock().unwrap().plays.push_back(spell);
    let target = creature.then(|| card(&mut game, B, "g/grizzly_bears.txt", ZoneType::Battlefield));
    plans[0].lock().unwrap().target = target;
    let reply = if counter {
        card(&mut game, B, "i/island.txt", ZoneType::Battlefield);
        card(&mut game, B, "i/island.txt", ZoneType::Battlefield);
        let id = card(&mut game, B, "c/counterspell.txt", ZoneType::Hand);
        plans[1].lock().unwrap().plays.push_back(id);
        Some(id)
    } else {
        None
    };
    driver.step_main_phase(&mut game, &mut agents);
    let id = if counter {
        "counterspell"
    } else if creature {
        "bolt_creature"
    } else {
        "bolt_player"
    };
    let snapshots = plans[0].lock().unwrap().snapshots.clone();
    let paid_tapped = game.card(mountain).tapped;
    observation(
        id,
        json!({"life":game.players.iter().map(|p|p.life).collect::<Vec<_>>(),"defender_life":game.player(B).life,"mountain_tapped":paid_tapped,"target_zone":target.map(|t|format!("{:?}",game.card(t).zone)),"spell_zone":format!("{:?}",game.card(spell).zone),"counter_zone":reply.map(|t|format!("{:?}",game.card(t).zone)),"stack":game.stack.len(),"snapshots":snapshots}),
    );
    assert_eq!(game.card(spell).zone, ZoneType::Graveyard);
    assert_eq!(game.stack.len(), 0);
    assert!(paid_tapped);
    assert!(
        snapshots
            .iter()
            .any(|v| v["stack"] == 1 && v["life"][1] == 20)
    );
    if counter {
        assert!(
            snapshots
                .iter()
                .any(|v| v["stack_names"] == json!(["Lightning Bolt", "Counterspell"]))
        );
    }
    if let Some(t) = target {
        assert_eq!(game.card(t).zone, ZoneType::Graveyard);
        assert_eq!(game.player(B).life, 20);
    } else {
        assert_eq!(game.player(B).life, if counter { 20 } else { 17 });
    }
    if let Some(c) = reply {
        assert_eq!(game.card(c).zone, ZoneType::Graveyard);
    }
}

#[test]
fn bolt_player() {
    bolt(false, false);
}
#[test]
fn bolt_creature() {
    bolt(true, false);
}
#[test]
fn counterspell() {
    bolt(false, true);
}

#[test]
fn etb_draw() {
    let (mut game, mut driver, mut agents, plans) = setup(2);
    card(&mut game, A, "f/forest.txt", ZoneType::Battlefield);
    card(&mut game, A, "p/plains.txt", ZoneType::Battlefield);
    let spell = card(&mut game, A, "e/elvish_visionary.txt", ZoneType::Hand);
    plans[0].lock().unwrap().plays.push_back(spell);
    driver.step_main_phase(&mut game, &mut agents);
    let hand = game.cards_in_zone(ZoneType::Hand, A).len();
    observation(
        "etb_draw",
        json!({"hand":hand,"library":game.cards_in_zone(ZoneType::Library,A).len(),"creature_zone":format!("{:?}",game.card(spell).zone),"stack":game.stack.len(),"snapshots":plans[0].lock().unwrap().snapshots}),
    );
    assert_eq!(game.card(spell).zone, ZoneType::Battlefield);
    assert_eq!(hand, 1);
    assert_eq!(game.cards_in_zone(ZoneType::Library, A).len(), 29);
    assert!(plans[0].lock().unwrap().snapshots.iter().any(|v| {
        v["libraries"][0] == 30
            && v["stack_details"]
                .as_array()
                .unwrap()
                .iter()
                .any(|d| d["trigger"] == true && d["source_zone"] == "Battlefield")
    }));
}

#[test]
fn blocked_combat() {
    let (mut game, mut driver, mut agents, plans) = setup(2);
    let attacker = card(&mut game, A, "g/grizzly_bears.txt", ZoneType::Battlefield);
    let blocker = card(&mut game, B, "g/grizzly_bears.txt", ZoneType::Battlefield);
    game.card_mut(attacker).summoning_sick = false;
    game.card_mut(blocker).summoning_sick = false;
    plans[0].lock().unwrap().attack = Some(attacker);
    plans[1].lock().unwrap().block = Some(blocker);
    driver.step_combat(&mut game, &mut agents);
    observation(
        "blocked_combat",
        json!({"attacker_zone":format!("{:?}",game.card(attacker).zone),"blocker_zone":format!("{:?}",game.card(blocker).zone),"life":game.players.iter().map(|p|p.life).collect::<Vec<_>>()}),
    );
    assert_eq!(game.card(attacker).zone, ZoneType::Graveyard);
    assert_eq!(game.card(blocker).zone, ZoneType::Graveyard);
    assert_eq!(game.player(A).life, 20);
    assert_eq!(game.player(B).life, 20);
}

#[test]
fn four_player_departure() {
    let (mut game, mut driver, mut agents, plans) = setup(4);
    let land = card(&mut game, A, "p/plains.txt", ZoneType::Hand);
    let bears = card(
        &mut game,
        PlayerId(2),
        "g/grizzly_bears.txt",
        ZoneType::Battlefield,
    );
    manabrew_engine::player::concede(&mut game, PlayerId(2));
    plans[0].lock().unwrap().plays.push_back(land);
    driver.priority_round(&mut game, &mut agents, true);
    let alive = game.alive_players().len();
    let first_over = game.game_over;
    let bears_zone = game.card(bears).zone;
    let bears_in_any_zone = game
        .iter_zones()
        .any(|(_, zone)| zone.cards.contains(&bears));
    let bears_indexed = game.card_zone_location(bears).is_some();
    std::fs::write(
        std::path::PathBuf::from(std::env::var("HEXPROOF_EVAL_OUTPUT").unwrap()).join("departure-state.json"),
        serde_json::to_string_pretty(&json!({"game":game,"zones":game.iter_zones().map(|(_,z)|z).collect::<Vec<_>>(),"departed_card":bears.0})).unwrap(),
    ).unwrap();
    let continued = game.card(land).zone == ZoneType::Battlefield;
    for p in [B, PlayerId(3)] {
        manabrew_engine::player::concede(&mut game, p);
    }
    game.check_state_based_actions();
    observation(
        "four_player_departure",
        json!({"alive_after_first":alive,"game_over_after_first":first_over,"owned_bears_zone_after_departure":format!("{:?}",bears_zone),"bears_in_any_zone_store":bears_in_any_zone,"bears_in_zone_index":bears_indexed,"continued":continued,"final_game_over":game.game_over,"winner":game.winner.map(|p|p.0)}),
    );
    assert_eq!(alive, 3);
    assert!(!first_over);
    assert!(continued);
    assert!(
        !bears_in_any_zone && !bears_indexed,
        "departed owned object must be absent from all authoritative zone stores and the reverse zone index"
    );
    assert!(game.game_over);
    assert_eq!(game.winner, Some(A));
    assert_eq!(
        bears_zone,
        ZoneType::None,
        "departing player's owned permanent must leave the game"
    );
}

#[test]
fn replacement() {
    let (mut game, mut driver, mut agents, plans) = setup(2);
    card(&mut game, A, "r/rest_in_peace.txt", ZoneType::Battlefield);
    card(&mut game, A, "m/mountain.txt", ZoneType::Battlefield);
    let bears = card(&mut game, B, "g/grizzly_bears.txt", ZoneType::Battlefield);
    let bolt = card(&mut game, A, "l/lightning_bolt.txt", ZoneType::Hand);
    plans[0].lock().unwrap().plays.push_back(bolt);
    plans[0].lock().unwrap().target = Some(bears);
    driver.step_main_phase(&mut game, &mut agents);
    let graves: Vec<_> = [A, B]
        .map(|p| game.cards_in_zone(ZoneType::Graveyard, p).len())
        .into();
    observation(
        "replacement",
        json!({"bears_zone":format!("{:?}",game.card(bears).zone),"bolt_zone":format!("{:?}",game.card(bolt).zone),"graveyards":graves}),
    );
    assert_eq!(game.card(bears).zone, ZoneType::Exile);
    assert_eq!(game.card(bolt).zone, ZoneType::Exile);
    assert_eq!(graves, vec![0, 0]);
}

fn register_token(driver: &mut GameLoop, name: &str) {
    let path = std::path::PathBuf::from(std::env::var("HEXPROOF_CARD_SCRIPTS").unwrap())
        .parent()
        .unwrap()
        .join("tokenscripts")
        .join(format!("{name}.txt"));
    let rules = parse_card_script(&std::fs::read_to_string(path).unwrap()).unwrap();
    let mut template = CardInstance::from_rules(&rules, A);
    template.is_token = true;
    driver.register_token(name, template);
}

#[test]
fn tokens() {
    let (mut game, mut driver, mut agents, plans) = setup(2);
    for _ in 0..2 {
        card(&mut game, A, "p/plains.txt", ZoneType::Battlefield);
    }
    register_token(&mut driver, "w_1_1_soldier");
    let spell = card(&mut game, A, "r/raise_the_alarm.txt", ZoneType::Hand);
    plans[0].lock().unwrap().plays.push_back(spell);
    driver.step_main_phase(&mut game, &mut agents);
    let tokens:Vec<_>=game.cards_in_zone(ZoneType::Battlefield,A).iter().filter(|c|game.card(**c).is_token).map(|c|{
        let token=game.card(*c);json!({"name":token.card_name,"power":token.power(),"toughness":token.toughness(),"controller":token.controller.0,"creature":token.type_line.is_creature(),"white":token.color==forge_foundation::ColorSet::WHITE,"soldier":token.type_line.has_subtype("Soldier")})
    }).collect();
    let library = game.cards_in_zone(ZoneType::Library, A).len();
    let hand = game.cards_in_zone(ZoneType::Hand, A).len();
    observation(
        "tokens",
        json!({"tokens":tokens,"spell_zone":format!("{:?}",game.card(spell).zone),"library":library,"hand":hand}),
    );
    assert_eq!(tokens.len(), 2);
    assert!(tokens.iter().all(|t| t["power"] == 1
        && t["toughness"] == 1
        && t["controller"] == 0
        && t["creature"] == true
        && t["white"] == true
        && t["soldier"] == true));
    assert_eq!(game.card(spell).zone, ZoneType::Graveyard);
    assert_eq!(library, 30);
    assert_eq!(hand, 0);
}

#[test]
fn copy() {
    let (mut game, mut driver, mut agents, plans) = setup(2);
    card(&mut game, A, "f/forest.txt", ZoneType::Battlefield);
    for _ in 0..4 {
        card(&mut game, A, "i/island.txt", ZoneType::Battlefield);
    }
    let bears = card(&mut game, B, "g/grizzly_bears.txt", ZoneType::Battlefield);
    let growth = card(&mut game, A, "g/giant_growth.txt", ZoneType::Hand);
    let clone = card(&mut game, A, "c/clone.txt", ZoneType::Hand);
    plans[0].lock().unwrap().target = Some(bears);
    plans[0].lock().unwrap().plays.push_back(growth);
    driver.step_main_phase(&mut game, &mut agents);
    assert_eq!(game.card(bears).power(), 5);
    plans[0].lock().unwrap().plays.push_back(clone);
    driver.step_main_phase(&mut game, &mut agents);
    observation(
        "copy",
        json!({"clone_zone":format!("{:?}",game.card(clone).zone),"clone_name":game.card(clone).card_name,"clone_power":game.card(clone).power(),"clone_toughness":game.card(clone).toughness(),"original_power":game.card(bears).power(),"original_toughness":game.card(bears).toughness()}),
    );
    assert_eq!(game.card(clone).zone, ZoneType::Battlefield);
    assert_eq!(game.card(clone).card_name, "Grizzly Bears");
    assert_eq!(game.card(clone).power(), 2);
    assert_eq!(game.card(clone).toughness(), 2);
    assert_eq!(game.card(bears).power(), 5);
    assert_eq!(game.card(bears).toughness(), 5);
}

fn commander_setup() -> (
    GameState,
    GameLoop,
    Vec<Box<dyn PlayerAgent>>,
    Vec<Arc<Mutex<Control>>>,
    CardId,
) {
    let (_, driver, agents, plans) = setup(4);
    let registered: Vec<_> = (0..4)
        .map(|n| {
            manabrew_engine::player::RegisteredPlayer::for_commander(
                format!("Commander seat {n}"),
                vec!["Isamaru, Hound of Konda".to_string()],
            )
        })
        .collect();
    let mut game = GameState::new_from_registered_players(&registered);
    game.turn.phase = PhaseType::Main1;
    game.turn.active_player = A;
    game.turn.priority_player = A;
    let mut first = CardId(0);
    for (n, rp) in registered.iter().enumerate() {
        let player = PlayerId(n as u32);
        for _ in 0..30 {
            card(&mut game, player, "p/plains.txt", ZoneType::Library);
        }
        let cmdr = card(
            &mut game,
            player,
            "i/isamaru_hound_of_konda.txt",
            ZoneType::Command,
        );
        game.initialize_player_commanders_from_registered(player, rp, None);
        if n == 0 {
            first = cmdr;
        }
    }
    (game, driver, agents, plans, first)
}

fn tapped(game: &GameState, player: PlayerId) -> usize {
    game.cards_in_zone(ZoneType::Battlefield, player)
        .iter()
        .filter(|id| game.card(**id).tapped)
        .count()
}

#[test]
fn commander_tax() {
    let (mut game, mut driver, mut agents, plans, commander) = commander_setup();
    assert!(game.players.iter().all(|p| p.life == 40));
    assert!(
        game.player_order
            .iter()
            .all(|p| game.player_registered_commanders(*p).len() == 1
                && game.card(game.player_registered_commanders(*p)[0]).zone == ZoneType::Command)
    );
    let plains: Vec<_> = (0..4)
        .map(|_| card(&mut game, A, "p/plains.txt", ZoneType::Battlefield))
        .collect();
    for _ in 0..3 {
        card(&mut game, A, "s/swamp.txt", ZoneType::Battlefield);
    }
    let murder = card(&mut game, A, "m/murder.txt", ZoneType::Hand);
    plans[0].lock().unwrap().plays.push_back(commander);
    driver.step_main_phase(&mut game, &mut agents);
    let first_paid = tapped(&game, A);
    assert_eq!(game.card(commander).zone, ZoneType::Battlefield);
    assert_eq!(first_paid, 1);
    plans[0].lock().unwrap().target = Some(commander);
    plans[0].lock().unwrap().plays.push_back(murder);
    driver.step_main_phase(&mut game, &mut agents);
    let offered = plans[0].lock().unwrap().confirmations.clone();
    let return_offered = offered.iter().any(|s| s.contains("command zone"));
    observation(
        "commander_tax",
        json!({"stage":"after-destroy","return_offered":return_offered,"confirmations":offered,"commander_zone":format!("{:?}",game.card(commander).zone),"first_paid":first_paid}),
    );
    assert!(return_offered);
    assert_eq!(game.card(commander).zone, ZoneType::Command);
    let mut poor = game.clone();
    for id in poor.cards_in_zone(ZoneType::Battlefield, A).to_vec() {
        poor.card_mut(id).tapped = true;
    }
    poor.card_mut(plains[0]).tapped = false;
    let (_, mut poor_driver, mut poor_agents, poor_plans) = setup(4);
    poor_plans[0].lock().unwrap().plays.push_back(commander);
    poor_driver.priority_round(&mut poor, &mut poor_agents, true);
    let insufficient_rejected = !poor_plans[0].lock().unwrap().legal.contains(&commander);
    assert!(insufficient_rejected);
    assert_eq!(poor.card(commander).zone, ZoneType::Command);
    let tax = game.player_commander_tax(A, commander);
    let before = tapped(&game, A);
    plans[0].lock().unwrap().plays.push_back(commander);
    driver.step_main_phase(&mut game, &mut agents);
    let paid_second = tapped(&game, A) - before;
    observation(
        "commander_tax",
        json!({"starting_life":[40,40,40,40],"registered_commanders":4,"first_paid":first_paid,"return_offered":return_offered,"confirmations":offered,"tax":tax,"insufficient_W_rejected":insufficient_rejected,"paid_second":paid_second,"zone":format!("{:?}",game.card(commander).zone)}),
    );
    assert_eq!(tax, 2);
    assert_eq!(paid_second, 3);
    assert_eq!(game.card(commander).zone, ZoneType::Battlefield);
}

#[test]
fn commander_damage() {
    let (mut game, mut driver, mut agents, plans, commander) = commander_setup();
    card(&mut game, A, "p/plains.txt", ZoneType::Battlefield);
    for _ in 0..3 {
        card(&mut game, A, "m/mountain.txt", ZoneType::Battlefield);
    }
    let fire = card(&mut game, A, "s/souls_fire.txt", ZoneType::Hand);
    plans[0].lock().unwrap().plays.push_back(commander);
    driver.step_main_phase(&mut game, &mut agents);
    assert_eq!(game.card(commander).zone, ZoneType::Battlefield);
    game.card_mut(commander).summoning_sick = false;
    game.player_add_commander_damage(B, commander, 19);
    let mut noncombat = game.clone();
    let (_, mut nc_driver, mut nc_agents, nc_plans) = setup(4);
    nc_plans[0].lock().unwrap().target = Some(commander);
    nc_plans[0].lock().unwrap().prefer_player_target = true;
    nc_plans[0].lock().unwrap().plays.push_back(fire);
    nc_driver.step_main_phase(&mut noncombat, &mut nc_agents);
    let nc_damage = noncombat
        .player(B)
        .commander_damage_received
        .get(&commander.0)
        .copied();
    observation(
        "commander_damage",
        json!({"stage":"noncombat","life":noncombat.player(B).life,"counter":nc_damage,"spell_zone":format!("{:?}",noncombat.card(fire).zone)}),
    );
    assert_eq!(noncombat.player(B).life, 38);
    assert_eq!(nc_damage, Some(19));
    plans[0].lock().unwrap().attack = Some(commander);
    driver.step_combat(&mut game, &mut agents);
    let damage = game
        .player(B)
        .commander_damage_received
        .get(&commander.0)
        .copied();
    let previous = plans[0].lock().unwrap().choices;
    driver.priority_round(&mut game, &mut agents, true);
    let continued = plans[0].lock().unwrap().choices > previous;
    observation(
        "commander_damage",
        json!({"combat_total":damage,"defender_life":game.player(B).life,"defender_lost":game.player(B).has_lost,"alive":game.alive_players().len(),"game_over":game.game_over,"continued_decision":continued,"noncombat_total":nc_damage,"noncombat_life":noncombat.player(B).life}),
    );
    assert_eq!(damage, Some(21));
    assert_eq!(game.player(B).life, 38);
    assert!(game.player(B).has_lost);
    assert_eq!(game.alive_players().len(), 3);
    assert!(!game.game_over && continued);
}

#[test]
fn modal_dfc() {
    let (mut game, mut driver, mut agents, plans) = setup(2);
    let recovery = card(
        &mut game,
        A,
        "b/bala_ged_recovery_bala_ged_sanctuary.txt",
        ZoneType::Hand,
    );
    plans[0].lock().unwrap().mode = Some(PlayCardMode::BackFaceLand);
    plans[0].lock().unwrap().plays.push_back(recovery);
    // Enter through a full normal turn. The land option is first offered in
    // Main1; after that turn it must still be tapped. This avoids restarting a
    // partially completed turn when testing the subsequent untap.
    let mut rng = rand::rngs::StdRng::seed_from_u64(20260909);
    driver.run_turn(&mut game, &mut agents, &mut rng);
    let entry = game.card(recovery).clone();
    observation(
        "modal_dfc",
        json!({"stage":"land-entry","name":entry.card_name,"tapped":entry.tapped,"zone":format!("{:?}",entry.zone),"legal":plans[0].lock().unwrap().legal_details}),
    );
    assert_eq!(entry.zone, ZoneType::Battlefield);
    assert_eq!(entry.card_name, "Bala Ged Sanctuary");
    assert!(entry.is_land() && entry.tapped);
    assert!(
        game.stack.is_empty()
            && game.cards_in_zone(ZoneType::Graveyard, A).is_empty()
            && game.cards_in_zone(ZoneType::Hand, A).is_empty()
    );
    // Complete the opponent's turn, then advance through the real beginning
    // of player 0's next turn (including untap).
    driver.run_turn(&mut game, &mut agents, &mut rng);
    driver.step_untap(&mut game, &mut agents);
    let untapped = !game.card(recovery).tapped;
    plans[0].lock().unwrap().mana_actions.push_back(recovery);
    driver.priority_round(&mut game, &mut agents, true);
    let pool = json!({"green":driver.pool(A).green(),"total":driver.pool(A).total_mana()});
    observation(
        "modal_dfc",
        json!({"entry_name":entry.card_name,"entered_tapped":entry.tapped,"no_sorcery_effect":true,"untapped":untapped,"final_tapped":game.card(recovery).tapped,"pool":pool,"active":game.active_player().0,"legal":plans[0].lock().unwrap().legal_details}),
    );
    assert!(untapped && game.card(recovery).tapped);
    assert_eq!(driver.pool(A).green(), 1);
    assert_eq!(driver.pool(A).total_mana(), 1);
    assert!(
        driver
            .pool(A)
            .can_pay(&forge_foundation::ManaCost::parse("G"))
    );
}

#[test]
fn morph() {
    let (mut game, mut driver, mut agents, plans) = setup(2);
    for _ in 0..4 {
        card(&mut game, A, "p/plains.txt", ZoneType::Battlefield);
    }
    card(&mut game, A, "i/island.txt", ZoneType::Battlefield);
    let willbender = card(&mut game, A, "w/willbender.txt", ZoneType::Hand);
    plans[0].lock().unwrap().mode = Some(PlayCardMode::Alternative(
        manabrew_engine::spellability::AlternativeCost::Morph,
    ));
    plans[0].lock().unwrap().plays.push_back(willbender);
    driver.priority_round(&mut game, &mut agents, true);
    let stack = game.card(willbender).clone();
    let paid_down = tapped(&game, A);
    std::fs::write(
        std::path::PathBuf::from(std::env::var("HEXPROOF_EVAL_OUTPUT").unwrap())
            .join("morph-stack-state.json"),
        serde_json::to_string(
            &json!({"game":game,"zones":game.iter_zones().map(|(_,zone)|zone).collect::<Vec<_>>()}),
        )
        .unwrap(),
    )
    .unwrap();
    observation(
        "morph",
        json!({"stage":"stack","name":stack.card_name,"face_down":stack.face_down,"power":stack.power(),"toughness":stack.toughness(),"color":format!("{:?}",stack.color),"mana_cost":stack.mana_cost,"zone":format!("{:?}",stack.zone),"paid_down":paid_down,"legal":plans[0].lock().unwrap().legal_details}),
    );
    assert_eq!(stack.zone, ZoneType::Stack);
    assert_eq!(paid_down, 3);
    driver.step_main_phase(&mut game, &mut agents);
    let down = game.card(willbender).clone();
    std::fs::write(
        std::path::PathBuf::from(std::env::var("HEXPROOF_EVAL_OUTPUT").unwrap())
            .join("morph-battlefield-state.json"),
        serde_json::to_string(
            &json!({"game":game,"zones":game.iter_zones().map(|(_,zone)|zone).collect::<Vec<_>>()}),
        )
        .unwrap(),
    )
    .unwrap();
    plans[0].lock().unwrap().activations.push_back(willbender);
    driver.step_main_phase(&mut game, &mut agents);
    let up = game.card(willbender);
    observation(
        "morph",
        json!({"stack_name":stack.card_name,"stack_power":stack.power(),"stack_toughness":stack.toughness(),"stack_color":format!("{:?}",stack.color),"stack_cost":stack.mana_cost,"down_name":down.card_name,"down_power":down.power(),"down_toughness":down.toughness(),"down_color":format!("{:?}",down.color),"down_cost":down.mana_cost,"paid_down":paid_down,"paid_total":tapped(&game,A),"up_name":up.card_name,"up_power":up.power(),"up_toughness":up.toughness(),"same_id":up.id==willbender,"up_face_down":up.face_down,"legal":plans[0].lock().unwrap().legal_details}),
    );
    assert!(stack.face_down && down.face_down && !up.face_down);
    assert!(stack.card_name.is_empty() && down.card_name.is_empty());
    assert_eq!(stack.power(), 2);
    assert_eq!(stack.toughness(), 2);
    assert_eq!(down.power(), 2);
    assert_eq!(down.toughness(), 2);
    assert_eq!(stack.color, forge_foundation::ColorSet::COLORLESS);
    assert_eq!(down.color, forge_foundation::ColorSet::COLORLESS);
    assert_eq!(stack.mana_cost, forge_foundation::ManaCost::no_cost());
    assert_eq!(down.mana_cost, forge_foundation::ManaCost::no_cost());
    assert_eq!(up.card_name, "Willbender");
    assert_eq!(up.power(), 1);
    assert_eq!(up.toughness(), 2);
    assert_eq!(tapped(&game, A), 5);
}

#[test]
fn adventure() {
    let (mut game, mut driver, mut agents, plans) = setup(2);
    let rules_path = std::path::PathBuf::from(std::env::var("HEXPROOF_CARD_SCRIPTS").unwrap())
        .join("l/lovestruck_beast_hearts_desire.txt");
    let rules = parse_card_script(&std::fs::read_to_string(rules_path).unwrap()).unwrap();
    let parsed_other = rules.other_part.as_ref().map(|face| face.name.clone());
    assert_eq!(parsed_other.as_deref(), Some("Heart's Desire"));
    for _ in 0..4 {
        card(&mut game, A, "f/forest.txt", ZoneType::Battlefield);
    }
    let beast = card(
        &mut game,
        A,
        "l/lovestruck_beast_hearts_desire.txt",
        ZoneType::Hand,
    );
    register_token(&mut driver, "w_1_1_human");
    driver.priority_round(&mut game, &mut agents, true);
    let options = plans[0].lock().unwrap().legal_details.clone();
    let other = game.card(beast).other_part.as_ref().map(|p| p.name.clone());
    let adventure_hook =
        manabrew_engine::card::card_factory_util::setup_adventure_ability(game.card_mut(beast))
            .is_some();
    plans[0].lock().unwrap().plays.push_back(beast);
    driver.priority_round(&mut game, &mut agents, true);
    let stack_name = game
        .stack
        .iter()
        .last()
        .and_then(|e| e.spell_ability.source)
        .map(|id| game.card(id).card_name.clone());
    observation(
        "adventure",
        json!({"coverageComplete":false,"diagnosticScope":"Missing runtime Adventure face/hook; token/exile/recast lifecycle is not implemented by this probe","parsed_rules_second_face":parsed_other,"parsed_split_type":rules.split_type,"assembled_instance_second_face":other,"legal_options":options,"adventure_factory_hook_present":adventure_hook,"normal_cast_stack_name":stack_name,"paid_for_normal_cast":tapped(&game,A),"requested_adventure":"Heart's Desire","native_play_modes":"Normal/BackFaceLand/RoomRightSplit/Alternative; no Adventure face selector"}),
    );
    assert!(
        other.is_some() && adventure_hook,
        "parsed Adventure face is discarded by card assembly and its native factory hook is unimplemented; normal option only casts Beast"
    );
}

fn prepare_trial(removal: bool) {
    let case_id = if removal {
        "prepare_source_leaves"
    } else {
        "prepare_cast"
    };
    let (mut game, mut driver, mut agents, plans) = setup(2);
    for _ in 0..3 {
        card(&mut game, A, "m/mountain.txt", ZoneType::Battlefield);
    }
    let text = std::fs::read_to_string(
        std::path::PathBuf::from(std::env::var("HEXPROOF_CARD_SCRIPTS").unwrap())
            .join("g/goblin_glasswright_craft_with_pride.txt"),
    )
    .unwrap();
    let rules = parse_card_script(&text).unwrap();
    let glass = card(
        &mut game,
        A,
        "g/goblin_glasswright_craft_with_pride.txt",
        ZoneType::Hand,
    );
    let bolt = if removal {
        card(&mut game, B, "m/mountain.txt", ZoneType::Battlefield);
        Some(card(&mut game, B, "l/lightning_bolt.txt", ZoneType::Hand))
    } else {
        None
    };
    register_token(&mut driver, "c_a_treasure_sac");
    driver.priority_round(&mut game, &mut agents, true);
    let hand_options = plans[0].lock().unwrap().legal_details.clone();
    plans[0].lock().unwrap().plays.push_back(glass);
    driver.step_main_phase(&mut game, &mut agents);
    let entered = game.card(glass).clone();
    let copies = game.cards_in_zone(ZoneType::Exile, A).to_vec();
    let paid_creature = tapped(&game, A);
    if let Some(bolt) = bolt {
        plans[1].lock().unwrap().target = Some(glass);
        plans[1].lock().unwrap().plays.push_back(bolt);
        driver.step_main_phase(&mut game, &mut agents);
    }
    observation(
        case_id,
        json!({"coverageComplete":false,"diagnosticScope":"Missing preparation/exile-copy mechanism; full prepared copy lifecycle is not implemented by this probe","bundled_script_has_prepare":text.contains("AlternateMode:Prepare"),"parsed_split_type":rules.split_type,"parsed_alternate":rules.other_part.as_ref().map(|p|p.name.clone()),"assembled_alternate":entered.other_part.as_ref().map(|p|p.name.clone()),"hand_options":hand_options,"entered_zone":format!("{:?}",entered.zone),"power":entered.power(),"toughness":entered.toughness(),"paid_creature":paid_creature,"associated_exile_copies":copies,"after_zone":format!("{:?}",game.card(glass).zone),"bolt_zone":bolt.map(|id|format!("{:?}",game.card(id).zone)),"legal_options":plans[0].lock().unwrap().legal_details}),
    );
    assert_eq!(entered.zone, ZoneType::Battlefield);
    assert_eq!(paid_creature, 2);
    if removal {
        assert_eq!(game.card(glass).zone, ZoneType::Graveyard);
    }
    assert_eq!(
        copies.len(),
        1,
        "real bundled Prepare card entered, but engine did not create its linked prepared sorcery copy"
    );
}

#[test]
fn prepare_cast() {
    prepare_trial(false);
}

#[test]
fn prepare_source_leaves() {
    prepare_trial(true);
}
