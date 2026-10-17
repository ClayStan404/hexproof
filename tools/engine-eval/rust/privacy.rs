// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors
use forge_foundation::{CardTypeLine, ColorSet, ManaCost, ZoneType};
use manabrew_agent_interface::game_view_dto::{CardView, GameViewDto, GameViewDtoExt, ZoneKind};
use manabrew_engine::card::CardInstance;
use manabrew_engine::game::GameState;
use manabrew_engine::ids::{CardId, PlayerId};
use manabrew_engine::mana::ManaPool;
use rand::SeedableRng;
use serde_json::json;

fn add(game: &mut GameState, owner: PlayerId, name: &str, zone: ZoneType) -> CardId {
    let card = CardInstance::new(
        CardId(0),
        name.to_string(),
        owner,
        CardTypeLine::parse("Creature Bear"),
        ManaCost::no_cost(),
        ColorSet::GREEN,
        Some(2),
        Some(2),
        vec![],
        vec![],
    );
    let id = game.create_card(card);
    game.move_card(id, zone, owner);
    id
}

fn host_view(mut dto: GameViewDto, viewer: Option<PlayerId>) -> GameViewDto {
    for zone in &mut dto.zones {
        if zone.zone == ZoneKind::Hand
            && viewer
                .map(manabrew_agent_interface::ids_codec::player_id_str)
                .as_ref()
                != Some(&zone.owner_id)
        {
            zone.cards = (0..zone.count)
                .map(|n| CardView::Hidden {
                    id: format!("hidden-{}-{n}", zone.owner_id),
                })
                .collect();
        }
    }
    dto
}

fn contains_exact_string(value: &serde_json::Value, target: &str) -> bool {
    match value {
        serde_json::Value::String(text) => text == target,
        serde_json::Value::Array(values) => values.iter().any(|v| contains_exact_string(v, target)),
        serde_json::Value::Object(fields) => fields
            .iter()
            .any(|(key, value)| key == target || contains_exact_string(value, target)),
        _ => false,
    }
}

#[test]
fn departure_projection() {
    let Ok(directory) = std::env::var("HEXPROOF_STATE_DIR") else {
        println!("Departure projection requires --state-dir; no observed coverage.");
        return;
    };
    let path = std::path::PathBuf::from(&directory).join("departure-state.json");
    if !path.is_file() {
        println!("No saved departure state in selected run; no observed coverage.");
        return;
    }
    let saved: serde_json::Value =
        serde_json::from_str(&std::fs::read_to_string(path).unwrap()).unwrap();
    let mut game: GameState = serde_json::from_value(saved["game"].clone()).unwrap();
    let mut zones = manabrew_engine::zone::ZoneStore::new(&game.player_order);
    for value in saved["zones"].as_array().unwrap() {
        let zone: manabrew_engine::zone::Zone = serde_json::from_value(value.clone()).unwrap();
        zones.replace_cards(zone.zone_type, zone.owner, zone.cards);
    }
    game.replace_zone_store(zones);
    let id = CardId(saved["departed_card"].as_u64().unwrap() as u32);
    let wire_id = manabrew_agent_interface::ids_codec::card_id_str(id);
    assert!(!game.iter_zones().any(|(_, zone)| zone.cards.contains(&id)));
    let mut records = Vec::new();
    let mut all_hidden = true;
    for viewer in [
        Some(PlayerId(0)),
        Some(PlayerId(1)),
        Some(PlayerId(2)),
        Some(PlayerId(3)),
        None,
    ] {
        let dto = GameViewDto::from_engine(
            &game,
            &vec![ManaPool::default(); 4],
            viewer.unwrap_or(PlayerId(0)),
            "departure",
        );
        let value = serde_json::to_value(&dto).unwrap();
        let id_leak = contains_exact_string(&value, &wire_id);
        let name_leak = contains_exact_string(&value, "Grizzly Bears");
        all_hidden &= !id_leak && !name_leak;
        records.push(json!({"viewer":viewer.map(|p|p.0),"id_leak":id_leak,"name_leak":name_leak}));
        std::fs::write(
            std::path::PathBuf::from(std::env::var("HEXPROOF_EVAL_OUTPUT").unwrap())
                .join(format!("departure-view-{:?}.json", viewer.map(|p| p.0))),
            serde_json::to_string_pretty(&value).unwrap(),
        )
        .unwrap();
    }
    println!(
        "HEXPROOF_OBSERVATION {}",
        json!({"case_id":"departure_projection","observations":{"state_directory":directory,"departed_card_id":wire_id,"views":records,"all_viewers_hide_departed_object":all_hidden}})
    );
    assert!(
        all_hidden,
        "departed object's identity must not remain in any native viewer DTO"
    );
}

#[test]
fn hidden_views() {
    let mut game = GameState::new(&["Owner", "Opponent"], 20);
    add(&mut game, PlayerId(0), "Counterspell", ZoneType::Hand);
    add(&mut game, PlayerId(1), "Lightning Bolt", ZoneType::Hand);
    add(
        &mut game,
        PlayerId(0),
        "Elvish Visionary",
        ZoneType::Library,
    );
    add(&mut game, PlayerId(1), "Willbender", ZoneType::Library);
    add(
        &mut game,
        PlayerId(0),
        "Grizzly Bears",
        ZoneType::Battlefield,
    );
    let mut records = vec![];
    for viewer in [Some(PlayerId(0)), Some(PlayerId(1)), None] {
        // Native API requires a human seat; spectator uses a harmless seat for
        // conversion, followed by host redaction of every private hand.
        let native = GameViewDto::from_engine(
            &game,
            &[ManaPool::default(), ManaPool::default()],
            viewer.unwrap_or(PlayerId(0)),
            "qualification",
        );
        let native_text = serde_json::to_string(&native).unwrap();
        let native_leaks =
            native_text.contains("Counterspell") && native_text.contains("Lightning Bolt");
        assert!(
            native_leaks,
            "native-failure classification requires actual disclosure evidence"
        );
        let native_zones = serde_json::to_value(&native.zones).unwrap();
        let adapted = host_view(native, viewer);
        let adapted_text = serde_json::to_string(&adapted).unwrap();
        let own = match viewer {
            Some(PlayerId(0)) => adapted_text.contains("Counterspell"),
            Some(PlayerId(1)) => adapted_text.contains("Lightning Bolt"),
            _ => true,
        };
        let other = match viewer {
            Some(PlayerId(0)) => !adapted_text.contains("Lightning Bolt"),
            Some(PlayerId(1)) => !adapted_text.contains("Counterspell"),
            _ => !adapted_text.contains("Lightning Bolt") && !adapted_text.contains("Counterspell"),
        };
        let libraries =
            !adapted_text.contains("Elvish Visionary") && !adapted_text.contains("Willbender");
        let public = adapted_text.contains("Grizzly Bears");
        records.push(json!({"viewer":viewer.map(|p|p.0),"native_leaks_both_hands":native_leaks,"native_zones":native_zones,"host_own_visible":own,"host_other_hidden":other,"host_libraries_hidden":libraries,"host_public_visible":public}));
        let path = std::path::PathBuf::from(std::env::var("HEXPROOF_EVAL_OUTPUT").unwrap())
            .join(format!("host-view-{:?}.json", viewer.map(|p| p.0)));
        std::fs::write(path, serde_json::to_string_pretty(&adapted).unwrap()).unwrap();
        assert!(
            own && other && libraries && public,
            "host projection must retain correct visible information"
        );
        assert!(
            adapted
                .zones
                .iter()
                .filter(|z| z.zone == ZoneKind::Hand || z.zone == ZoneKind::Library)
                .all(|z| z.count == 1)
        );
    }
    println!(
        "HEXPROOF_OBSERVATION {}",
        json!({"case_id":"hidden_views","observations":{"views":records,"library_tracking":library_tracking(),"native_privacy_pass":false,"host_projection_pass":true,"scope":"Basic hidden zones plus public-to-library stable-ID tracking after actual shuffle; face-down cards and private choice prompts need separate coverage."}})
    );
}

fn library_tracking() -> serde_json::Value {
    let mut game = GameState::new(&["Owner", "Opponent"], 20);
    for owner in [PlayerId(0), PlayerId(1)] {
        for n in 0..6 {
            add(
                &mut game,
                owner,
                &format!("Private library card {n}"),
                ZoneType::Library,
            );
        }
    }
    let known = add(&mut game, PlayerId(1), "Willbender", ZoneType::Battlefield);
    add(
        &mut game,
        PlayerId(0),
        "Grizzly Bears",
        ZoneType::Battlefield,
    );
    let public = GameViewDto::from_engine(
        &game,
        &[ManaPool::default(), ManaPool::default()],
        PlayerId(0),
        "tracking",
    );
    let known_wire_id = manabrew_agent_interface::ids_codec::card_id_str(known);
    let public_text = serde_json::to_string(&public).unwrap();
    assert!(public_text.contains("Willbender") && public_text.contains(&known_wire_id));
    // Projection-boundary audit: real engine zone-move and shuffle primitives,
    // not a spell-specific resolution test or expected-outcome mutation.
    game.move_card(known, ZoneType::Library, PlayerId(1));
    game.move_cards_to_zone_top(ZoneType::Library, PlayerId(1), &[known]);
    let before = game.cards_in_zone(ZoneType::Library, PlayerId(1)).to_vec();
    manabrew_engine::player::shuffle(
        &mut game,
        PlayerId(1),
        &mut rand::rngs::StdRng::seed_from_u64(20260909),
    );
    let after = game.cards_in_zone(ZoneType::Library, PlayerId(1)).to_vec();
    assert_ne!(
        before, after,
        "fixed seeded shuffle must change this multi-card order"
    );
    let mut views = Vec::new();
    for viewer in [Some(PlayerId(0)), Some(PlayerId(1)), None] {
        let dto = host_view(
            GameViewDto::from_engine(
                &game,
                &[ManaPool::default(), ManaPool::default()],
                viewer.unwrap_or(PlayerId(0)),
                "tracking",
            ),
            viewer,
        );
        let text = serde_json::to_string(&dto).unwrap();
        let libraries: Vec<_> = dto
            .zones
            .iter()
            .filter(|z| z.zone == ZoneKind::Library)
            .collect();
        let no_ids_or_order = libraries.iter().all(|z| z.cards.is_empty());
        let known_id_absent = !text.contains(&known_wire_id);
        let names_absent = !text.contains("Willbender") && !text.contains("Private library card");
        assert!(no_ids_or_order && known_id_absent && names_absent);
        assert_eq!(
            libraries.iter().map(|z| z.count).collect::<Vec<_>>(),
            vec![6, 7]
        );
        assert!(text.contains("Grizzly Bears"));
        views.push(json!({"viewer":viewer.map(|p|p.0),"library_cards_empty":no_ids_or_order,"known_id_absent_from_entire_payload":known_id_absent,"private_names_absent":names_absent,"library_counts":[6,7]}));
        std::fs::write(
            std::path::PathBuf::from(std::env::var("HEXPROOF_EVAL_OUTPUT").unwrap())
                .join(format!("library-track-view-{:?}.json", viewer.map(|p| p.0))),
            serde_json::to_string_pretty(&dto).unwrap(),
        )
        .unwrap();
    }
    json!({"setup":"Engine zone-move/top-placement and seeded actual shuffle primitives; native library DTO is count-only; host redactor still only changes hands.",
        "public_known_id":known_wire_id,"before_shuffle_order":before.iter().map(|id|id.0).collect::<Vec<_>>(),
        "authority_after_shuffle_order":after.iter().map(|id|id.0).collect::<Vec<_>>(),"views":views,"all_viewers_hide_known_card_position":true})
}

#[test]
fn morph_projection() {
    let Ok(directory) = std::env::var("HEXPROOF_STATE_DIR") else {
        println!(
            "Morph projection requires --state-dir from a real semantic run; not counted as executed coverage."
        );
        return;
    };
    let mut records = Vec::new();
    let mut all_private = true;
    for stage in ["stack", "battlefield"] {
        let path = std::path::PathBuf::from(&directory).join(format!("morph-{stage}-state.json"));
        let saved: serde_json::Value =
            serde_json::from_str(&std::fs::read_to_string(path).unwrap()).unwrap();
        let mut game: GameState = serde_json::from_value(saved["game"].clone()).unwrap();
        // GameState deliberately skips its runtime ZoneStore during serde.
        // Restore the separately recorded exact engine zone orders; do not
        // synthesize card characteristics or alter the observed Morph state.
        let mut zones = manabrew_engine::zone::ZoneStore::new(&game.player_order);
        for value in saved["zones"].as_array().unwrap() {
            let zone: manabrew_engine::zone::Zone = serde_json::from_value(value.clone()).unwrap();
            zones.replace_cards(zone.zone_type, zone.owner, zone.cards);
        }
        game.replace_zone_store(zones);
        for viewer in [Some(PlayerId(0)), Some(PlayerId(1)), None] {
            let dto = host_view(
                GameViewDto::from_engine(
                    &game,
                    &[ManaPool::default(), ManaPool::default()],
                    viewer.unwrap_or(PlayerId(0)),
                    "morph",
                ),
                viewer,
            );
            let text = serde_json::to_string(&dto).unwrap();
            let unauthorized = viewer != Some(PlayerId(0));
            let leak = unauthorized && text.contains("Willbender");
            all_private &= !leak;
            records.push(
                json!({"stage":stage,"viewer":viewer.map(|p|p.0),"unauthorized_name_leak":leak}),
            );
            std::fs::write(
                std::path::PathBuf::from(std::env::var("HEXPROOF_EVAL_OUTPUT").unwrap())
                    .join(format!("morph-{stage}-view-{:?}.json", viewer.map(|p| p.0))),
                serde_json::to_string_pretty(&dto).unwrap(),
            )
            .unwrap();
        }
    }
    println!(
        "HEXPROOF_OBSERVATION {}",
        json!({"case_id":"morph_projection","observations":{"state_directory":directory,"views":records,"all_private":all_private}})
    );
    assert!(
        all_private,
        "real Morph states expose Willbender through native DTO despite evaluated hand redaction"
    );
}
