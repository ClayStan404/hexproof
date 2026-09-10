// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors
//! Complete synthetic games, using a separate scripted human-controller thread.
//! Policy is intentionally simple: first legal cast, all attacks, no blocks.
use forge_foundation::ZoneType;
use manabrew_engine::{
    agent::{ManaAbilityOption, ManaCostAction, PlayerAgent, PriorityActionSpace},
    card::CardInstance,
    combat::DefenderId,
    game::GameState,
    game_loop::GameLoop,
    ids::{CardId, PlayerId},
    mana::ManaPool,
    player::actions::PlayerAction,
    spellability::SpellAbility,
};
use rand::SeedableRng;
use serde_json::{json, Value};
use std::sync::{
    mpsc::{channel, Receiver, Sender},
    Arc, Mutex,
};

enum Reply {
    Action(PlayerAction),
    Attacks(Vec<(CardId, DefenderId)>),
    Cards(Vec<CardId>),
    Yes,
}
enum Prompt {
    Action(PlayerId, Vec<manabrew_engine::agent::PlayOption>),
    Attacks(PlayerId, Vec<CardId>, Vec<DefenderId>),
    Cards(PlayerId, Vec<CardId>, usize),
    Yes(PlayerId, &'static str),
}
struct Human {
    tx: Sender<Prompt>,
    rx: Receiver<(PlayerId, Reply)>,
    trace: Arc<Mutex<Vec<Value>>>,
}
impl Human {
    fn ask(&mut self, player: PlayerId, prompt: Prompt) -> Reply {
        self.tx.send(prompt).unwrap();
        let (actor, answer) = self
            .rx
            .recv_timeout(std::time::Duration::from_secs(10))
            .expect("bounded external controller response");
        assert_eq!(actor, player, "authenticated controller identity");
        answer
    }
}
impl PlayerAgent for Human {
    fn choose_land_or_spell(&mut self, p: PlayerId) -> Option<bool> {
        assert!(matches!(
            self.ask(p, Prompt::Yes(p, "land_or_spell")),
            Reply::Yes
        ));
        Some(true)
    }
    fn choose_target_any(
        &mut self,
        _: PlayerId,
        players: &[PlayerId],
        cards: &[CardId],
        _: Option<&SpellAbility>,
    ) -> manabrew_engine::agent::TargetChoice {
        players
            .first()
            .copied()
            .map(manabrew_engine::agent::TargetChoice::Player)
            .or_else(|| {
                cards
                    .first()
                    .copied()
                    .map(manabrew_engine::agent::TargetChoice::Card)
            })
            .unwrap_or(manabrew_engine::agent::TargetChoice::None)
    }
    fn choose_targets_for(
        &mut self,
        sa: &mut SpellAbility,
        game: &GameState,
        pools: &[ManaPool],
    ) -> bool {
        manabrew_engine::spellability::choose_targets_by_kind(self, sa, game, pools)
    }
    fn snapshot_state(&mut self, game: &GameState, _: &[ManaPool]) {
        let mut trace = self.trace.lock().unwrap();
        assert!(trace.len() < 20000, "bounded complete game snapshots");
        trace.push(json!({"kind":"state","turn":game.turn.turn_number,"phase":format!("{:?}",game.turn.phase),"active":game.active_player().0,"priority":game.turn.priority_player.0,"alive":game.alive_players().len(),"life":game.players.iter().map(|p|p.life).collect::<Vec<_>>(),"hands":game.player_order.iter().map(|p|game.cards_in_zone(ZoneType::Hand,*p).len()).collect::<Vec<_>>(),"stack":game.stack.len()}));
    }
    fn mulligan_decision(&mut self, p: PlayerId, _: &[CardId], _: u32) -> bool {
        matches!(self.ask(p, Prompt::Yes(p, "keep")), Reply::Yes)
    }
    fn choose_action(
        &mut self,
        p: PlayerId,
        s: Option<&PriorityActionSpace>,
        request: &mut dyn FnMut() -> PriorityActionSpace,
    ) -> PlayerAction {
        let requested;
        let space = if let Some(space) = s {
            space
        } else {
            requested = request();
            &requested
        };
        match self.ask(p, Prompt::Action(p, space.playable.clone())) {
            Reply::Action(a) => a,
            _ => panic!("wrong response kind"),
        }
    }
    fn choose_attackers(
        &mut self,
        p: PlayerId,
        available: &[CardId],
        defenders: &[DefenderId],
    ) -> Vec<(CardId, DefenderId)> {
        match self.ask(
            p,
            Prompt::Attacks(p, available.to_vec(), defenders.to_vec()),
        ) {
            Reply::Attacks(a) => a,
            _ => panic!("wrong response kind"),
        }
    }
    fn choose_blockers(
        &mut self,
        p: PlayerId,
        _: &[CardId],
        _: &[CardId],
        _: Option<usize>,
    ) -> Vec<(CardId, CardId)> {
        assert!(matches!(
            self.ask(p, Prompt::Yes(p, "no_blocks")),
            Reply::Yes
        ));
        Vec::new()
    }
    fn choose_discard(&mut self, p: PlayerId, hand: &[CardId], num: usize) -> Vec<CardId> {
        match self.ask(p, Prompt::Cards(p, hand.to_vec(), num)) {
            Reply::Cards(c) => c,
            _ => panic!("wrong response kind"),
        }
    }
    fn choose_target_player(
        &mut self,
        _: PlayerId,
        valid: &[PlayerId],
        _: Option<&SpellAbility>,
    ) -> Option<PlayerId> {
        valid.first().copied()
    }
    fn choose_target_card(
        &mut self,
        _: PlayerId,
        valid: &[CardId],
        _: Option<&SpellAbility>,
    ) -> Option<CardId> {
        valid.first().copied()
    }
    fn pay_mana_cost(
        &mut self,
        p: PlayerId,
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
        assert!(matches!(
            self.ask(p, Prompt::Yes(p, "pay_normal_auto")),
            Reply::Yes
        ));
        ManaCostAction::Pay { auto: true }
    }
}
fn complete(count: usize) {
    let names: Vec<_> = (0..count)
        .map(|n| format!("Scripted human seat {n}"))
        .collect();
    let mut game = GameState::new(&names.iter().map(String::as_str).collect::<Vec<_>>(), 20);
    let root = std::path::PathBuf::from(std::env::var("HEXPROOF_CARD_SCRIPTS").unwrap());
    for p in 0..count {
        for n in 0..60 {
            let path = if n % 2 == 0 {
                "f/forest.txt"
            } else {
                "g/grizzly_bears.txt"
            };
            let rules =
                forge_carddb::parse_card_script(&std::fs::read_to_string(root.join(path)).unwrap())
                    .unwrap();
            let id = game.create_card(CardInstance::from_rules(&rules, PlayerId(p as u32)));
            game.move_card(id, ZoneType::Library, PlayerId(p as u32));
        }
    }
    let trace = Arc::new(Mutex::new(Vec::new()));
    let mut threads = Vec::new();
    let mut agents: Vec<Box<dyn PlayerAgent>> = Vec::new();
    for _ in 0..count {
        let (tx, requests) = channel();
        let (answers, rx) = channel();
        let events = trace.clone();
        threads.push(std::thread::spawn(move|| { for prompt in requests { let (owner,reply,event)=match prompt {
            Prompt::Action(p,choices)=> {let action=choices.first().copied().map(PlayerAction::CastSpell).unwrap_or(PlayerAction::PassPriority);let event=json!({"kind":"priority_reply","actor":p.0,"offered":choices,"action":format!("{:?}",action)});(p,Reply::Action(action),event)},
            Prompt::Attacks(p,cards,defenders)=> {let attacks=defenders.first().map(|d|cards.iter().map(|c|(*c,*d)).collect()).unwrap_or_default();(p,Reply::Attacks(attacks),json!({"kind":"attack_reply","actor":p.0,"available":cards,"defenders":format!("{:?}",defenders)}))},
            Prompt::Cards(p,cards,num)=>(p,Reply::Cards(cards.into_iter().take(num).collect()),json!({"kind":"discard_reply","actor":p.0,"count":num})),
            Prompt::Yes(p,kind)=>(p,Reply::Yes,json!({"kind":kind,"actor":p.0})),
        }; events.lock().unwrap().push(event); if answers.send((owner,reply)).is_err(){break;} } }));
        agents.push(Box::new(Human {
            tx,
            rx,
            trace: trace.clone(),
        }));
    }
    let mut driver = GameLoop::new(count);
    let mut rng = rand::rngs::StdRng::seed_from_u64(20260909);
    let winner = driver.run(&mut game, &mut agents, &mut rng, 100);
    drop(agents);
    for handle in threads {
        handle.join().unwrap();
    }
    let events = trace.lock().unwrap();
    let after_elimination = events.iter().position(|e| {
        e["kind"] == "state"
            && e["alive"]
                .as_u64()
                .is_some_and(|a| a > 1 && a < (count as u64))
    });
    let continued = after_elimination.is_some_and(|i| {
        events[i + 1..]
            .iter()
            .any(|e| e["kind"] == "priority_reply")
    });
    let casts = events
        .iter()
        .filter(|e| {
            e["kind"] == "priority_reply"
                && e["action"]
                    .as_str()
                    .is_some_and(|s| s.starts_with("CastSpell"))
        })
        .count();
    let paid = events
        .iter()
        .filter(|e| e["kind"] == "pay_normal_auto")
        .count();
    let path = std::path::PathBuf::from(std::env::var("HEXPROOF_EVAL_OUTPUT").unwrap())
        .join(format!("complete-{count}p-trace.json"));
    std::fs::write(path, serde_json::to_string_pretty(&*events).unwrap()).unwrap();
    println!(
        "HEXPROOF_OBSERVATION {}",
        json!({"case_id":format!("complete_{count}p"),"observations":{"players":count,"synthetic_decks":"30 Forest + 30 Grizzly Bears per seat; not tournament-legal reference decks","game_over":game.game_over,"winner":winner.map(|p|p.0),"turn":game.turn.turn_number,"alive":game.alive_players().len(),"life":game.players.iter().map(|p|p.life).collect::<Vec<_>>(),"casts_including_lands":casts,"normal_payment_confirmations":paid,"controller_events":events.len(),"continued_after_first_elimination":continued,"forced_concedes":0}})
    );
    assert!(game.game_over && winner.is_some());
    assert_eq!(game.alive_players().len(), 1);
    assert!(casts > 0 && paid > 0);
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
