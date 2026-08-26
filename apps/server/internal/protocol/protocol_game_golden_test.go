// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package protocol

import (
	"bytes"
	"testing"
)

func TestGoldenGameActionFixtures(t *testing.T) {
	t.Run("game-move-card.json", func(t *testing.T) {
		env, err := ParseEnvelope(loadFixture(t, "game-move-card.json"))
		if err != nil {
			t.Fatalf("parse: %v", err)
		}
		var move GameMoveCard
		if err := env.DecodePayload(&move); err != nil {
			t.Fatalf("decode: %v", err)
		}
		if env.Type != TypeGameMoveCard || env.ID != "g3" ||
			move.CardID != "s1-gy1" || move.FromZone != ZoneGraveyard ||
			move.ToZone != ZoneBattlefield || move.Position == nil ||
			move.FromSeat == nil || *move.FromSeat != 1 ||
			move.ToSeat == nil || *move.ToSeat != 0 ||
			move.Position.X != 0.25 || move.Position.Y != 0.6 {
			t.Fatalf("game.move_card = env %+v payload %+v", env, move)
		}
	})

	t.Run("game-card-moved.json", func(t *testing.T) {
		env, err := ParseEnvelope(loadFixture(t, "game-card-moved.json"))
		if err != nil {
			t.Fatalf("parse: %v", err)
		}
		var moved GameCardMoved
		if err := env.DecodePayload(&moved); err != nil {
			t.Fatalf("decode: %v", err)
		}
		if env.Type != TypeGameCardMoved || env.ID != "g3" ||
			moved.CardID != "s1-gy1" || moved.Seat != 0 ||
			moved.FromSeat != 1 || moved.ToSeat != 0 ||
			moved.Position == nil ||
			moved.Position.X != 0.25 {
			t.Fatalf("game.card_moved = env %+v payload %+v", env, moved)
		}
	})

	t.Run("game-set-tapped.json", func(t *testing.T) {
		env, err := ParseEnvelope(loadFixture(t, "game-set-tapped.json"))
		if err != nil {
			t.Fatalf("parse: %v", err)
		}
		var request GameSetTapped
		if err := env.DecodePayload(&request); err != nil {
			t.Fatalf("decode: %v", err)
		}
		if env.Type != TypeGameSetTapped || env.ID != "g3-tap" ||
			request.CardID != "s0-c1" || !request.Tapped {
			t.Fatalf("game.set_tapped = env %+v payload %+v", env, request)
		}
	})

	t.Run("game-set-card-counter.json", func(t *testing.T) {
		env, err := ParseEnvelope(loadFixture(t, "game-set-card-counter.json"))
		if err != nil {
			t.Fatalf("parse: %v", err)
		}
		var request GameSetCardCounter
		if err := env.DecodePayload(&request); err != nil {
			t.Fatalf("decode: %v", err)
		}
		if env.Type != TypeGameSetCardCounter ||
			request.CardID != "s0-c1" ||
			request.Kind != CardCounterKindAbility ||
			request.Label != "Flying" || request.Value == nil ||
			*request.Value != 1 {
			t.Fatalf("game.set_card_counter = env %+v payload %+v",
				env, request)
		}
	})

	t.Run("game-card-counter-set.json", func(t *testing.T) {
		env, err := ParseEnvelope(loadFixture(t, "game-card-counter-set.json"))
		if err != nil {
			t.Fatalf("parse: %v", err)
		}
		var reply GameCardCounterSet
		if err := env.DecodePayload(&reply); err != nil {
			t.Fatalf("decode: %v", err)
		}
		if env.Type != TypeGameCardCounterSet ||
			reply.Counter.ID != "ability-1" ||
			reply.Counter.Label != "Flying" || reply.Counter.Value != 1 {
			t.Fatalf("game.card_counter_set = env %+v payload %+v",
				env, reply)
		}
	})

	t.Run("game-tapped-set.json", func(t *testing.T) {
		env, err := ParseEnvelope(loadFixture(t, "game-tapped-set.json"))
		if err != nil {
			t.Fatalf("parse: %v", err)
		}
		var reply GameTappedSet
		if err := env.DecodePayload(&reply); err != nil {
			t.Fatalf("decode: %v", err)
		}
		if env.Type != TypeGameTappedSet || reply.Seat != 1 ||
			reply.CardID != "s0-c1" || !reply.Tapped {
			t.Fatalf("game.tapped_set = env %+v payload %+v", env, reply)
		}
	})

	t.Run("game-reveal.json", func(t *testing.T) {
		env, err := ParseEnvelope(loadFixture(t, "game-reveal.json"))
		if err != nil {
			t.Fatalf("parse: %v", err)
		}
		var reveal GameReveal
		if err := env.DecodePayload(&reveal); err != nil {
			t.Fatalf("decode: %v", err)
		}
		if env.Type != TypeGameReveal || env.ID != "reveal-17" ||
			reveal.Zone != ZoneHand || len(reveal.CardIDs) != 0 {
			t.Fatalf("game.reveal = env %+v payload %+v", env, reveal)
		}
	})

	t.Run("game-revealed.json", func(t *testing.T) {
		env, err := ParseEnvelope(loadFixture(t, "game-revealed.json"))
		if err != nil {
			t.Fatalf("parse: %v", err)
		}
		var revealed GameRevealed
		if err := env.DecodePayload(&revealed); err != nil {
			t.Fatalf("decode: %v", err)
		}
		if env.Type != TypeGameRevealed || env.ID != "reveal-17" ||
			revealed.RoomID != "ABCDEF" || revealed.Seat != 0 ||
			revealed.Zone != ZoneHand || revealed.Count != 2 {
			t.Fatalf("game.revealed = env %+v payload %+v", env, revealed)
		}
	})

	t.Run("game-dump-zone.json", func(t *testing.T) {
		env, err := ParseEnvelope(loadFixture(t, "game-dump-zone.json"))
		if err != nil {
			t.Fatalf("parse: %v", err)
		}
		var dump GameDumpZone
		if err := env.DecodePayload(&dump); err != nil {
			t.Fatalf("decode: %v", err)
		}
		if env.Type != TypeGameDumpZone || env.ID != "dump-18" ||
			dump.Zone != "library" || dump.TopCount != 3 {
			t.Fatalf("game.dump_zone = env %+v payload %+v", env, dump)
		}
	})

	t.Run("game-zone-dumped.json", func(t *testing.T) {
		env, err := ParseEnvelope(loadFixture(t, "game-zone-dumped.json"))
		if err != nil {
			t.Fatalf("parse: %v", err)
		}
		var dump GameZoneDumped
		if err := env.DecodePayload(&dump); err != nil {
			t.Fatalf("decode: %v", err)
		}
		if env.Type != TypeGameZoneDumped || env.ID != "dump-18" ||
			dump.RoomID != "ABCDEF" || dump.Zone != "library" ||
			dump.TopCount != 3 ||
			len(dump.Cards) != 2 || dump.Cards[1].Name != "Demonic Tutor" {
			t.Fatalf("game.zone_dumped = env %+v payload %+v", env, dump)
		}
	})

	t.Run("game-search-library.json", func(t *testing.T) {
		env, err := ParseEnvelope(loadFixture(t, "game-search-library.json"))
		if err != nil {
			t.Fatalf("parse: %v", err)
		}
		var search GameSearchLibrary
		if err := env.DecodePayload(&search); err != nil {
			t.Fatalf("decode: %v", err)
		}
		if env.Type != TypeGameSearchLibrary || env.ID != "search-19" ||
			len(search.CardIDs) != 2 || search.CardIDs[0] != "s0-c8" ||
			search.ToZone != LibraryDestinationGraveyard ||
			search.ToSeat == nil || *search.ToSeat != 0 ||
			search.Reveal || !search.Randomize || search.Position != nil {
			t.Fatalf("game.search_library = env %+v payload %+v", env, search)
		}
	})

	t.Run("game-library-searched.json", func(t *testing.T) {
		env, err := ParseEnvelope(loadFixture(t, "game-library-searched.json"))
		if err != nil {
			t.Fatalf("parse: %v", err)
		}
		var searched GameLibrarySearched
		if err := env.DecodePayload(&searched); err != nil {
			t.Fatalf("decode: %v", err)
		}
		if env.Type != TypeGameLibrarySearched || env.ID != "search-19" ||
			searched.RoomID != "ABCDEF" || searched.Seat != 0 ||
			searched.ToSeat != 0 ||
			searched.ToZone != LibraryDestinationGraveyard ||
			searched.Revealed || searched.Count != 2 {
			t.Fatalf("game.library_searched = env %+v payload %+v", env, searched)
		}
	})

	t.Run("game-recall-revealed.json", func(t *testing.T) {
		env, err := ParseEnvelope(loadFixture(t, "game-recall-revealed.json"))
		if err != nil {
			t.Fatalf("parse: %v", err)
		}
		var recall GameRecallRevealed
		if err := env.DecodePayload(&recall); err != nil ||
			env.Type != TypeGameRecallRevealed || env.ID != "recall-20" {
			t.Fatalf("game.recall_revealed = env %+v payload %+v err %v",
				env, recall, err)
		}
	})

	t.Run("game-revealed-recalled.json", func(t *testing.T) {
		env, err := ParseEnvelope(loadFixture(t, "game-revealed-recalled.json"))
		if err != nil {
			t.Fatalf("parse: %v", err)
		}
		var recalled GameRevealedRecalled
		if err := env.DecodePayload(&recalled); err != nil ||
			env.Type != TypeGameRevealedRecalled || env.ID != "recall-20" ||
			recalled.RoomID != "ABCDEF" || recalled.Seat != 0 ||
			recalled.Count != 2 {
			t.Fatalf("game.revealed_recalled = env %+v payload %+v err %v",
				env, recalled, err)
		}
	})

	t.Run("game-move-cards.json", func(t *testing.T) {
		env, err := ParseEnvelope(loadFixture(t, "game-move-cards.json"))
		if err != nil {
			t.Fatalf("parse: %v", err)
		}
		var move GameMoveCards
		if err := env.DecodePayload(&move); err != nil ||
			env.Type != TypeGameMoveCards || env.ID != "move-cards-21" ||
			len(move.CardIDs) != 2 || move.ToZone != ZoneLibrary ||
			move.LibraryPlacement != LibraryPlacementBottom || move.Randomize {
			t.Fatalf("game.move_cards = env %+v payload %+v err %v",
				env, move, err)
		}
	})

	t.Run("game-cards-moved.json", func(t *testing.T) {
		env, err := ParseEnvelope(loadFixture(t, "game-cards-moved.json"))
		if err != nil {
			t.Fatalf("parse: %v", err)
		}
		var moved GameCardsMoved
		if err := env.DecodePayload(&moved); err != nil ||
			env.Type != TypeGameCardsMoved || env.ID != "move-cards-21" ||
			moved.RoomID != "ABCDEF" || moved.Seat != 0 ||
			moved.Count != 2 || moved.ToZone != ZoneLibrary {
			t.Fatalf("game.cards_moved = env %+v payload %+v err %v",
				env, moved, err)
		}
	})

	t.Run("game-move-library-cards.json", func(t *testing.T) {
		env, err := ParseEnvelope(loadFixture(t, "game-move-library-cards.json"))
		var move GameMoveLibraryCards
		if err != nil || env.DecodePayload(&move) != nil ||
			env.Type != TypeGameMoveLibraryCards ||
			env.ID != "move-library-cards-23" || move.Count != 3 ||
			move.ToZone != ZoneGraveyard {
			t.Fatalf("game.move_library_cards = env %+v payload %+v err %v",
				env, move, err)
		}
	})

	t.Run("game-library-cards-moved.json", func(t *testing.T) {
		env, err := ParseEnvelope(loadFixture(t, "game-library-cards-moved.json"))
		var moved GameLibraryCardsMoved
		if err != nil || env.DecodePayload(&moved) != nil ||
			env.Type != TypeGameLibraryCardsMoved ||
			env.ID != "move-library-cards-23" ||
			moved.RoomID != "ABCDEF" || moved.Seat != 0 ||
			moved.Count != 3 || moved.ToZone != ZoneGraveyard {
			t.Fatalf("game.library_cards_moved = env %+v payload %+v err %v",
				env, moved, err)
		}
	})

	t.Run("game-reorder-library.json", func(t *testing.T) {
		env, err := ParseEnvelope(loadFixture(t, "game-reorder-library.json"))
		if err != nil {
			t.Fatalf("parse: %v", err)
		}
		var reorder GameReorderLibrary
		if err := env.DecodePayload(&reorder); err != nil ||
			env.Type != TypeGameReorderLibrary || env.ID != "reorder-22" ||
			len(reorder.CardIDs) != 2 || reorder.CardIDs[0] != "s0-c9" {
			t.Fatalf("game.reorder_library = env %+v payload %+v err %v",
				env, reorder, err)
		}
	})

	t.Run("game-library-reordered.json", func(t *testing.T) {
		env, err := ParseEnvelope(loadFixture(t, "game-library-reordered.json"))
		if err != nil {
			t.Fatalf("parse: %v", err)
		}
		var reordered GameLibraryReordered
		if err := env.DecodePayload(&reordered); err != nil ||
			env.Type != TypeGameLibraryReordered || env.ID != "reorder-22" ||
			reordered.RoomID != "ABCDEF" || reordered.Seat != 0 ||
			reordered.Count != 2 {
			t.Fatalf("game.library_reordered = env %+v payload %+v err %v",
				env, reordered, err)
		}
	})

	t.Run("game-snapshot-shared.json", func(t *testing.T) {
		env, err := ParseEnvelope(loadFixture(t, "game-snapshot-shared.json"))
		if err != nil {
			t.Fatalf("parse: %v", err)
		}
		var snapshot GameSnapshot
		if err := env.DecodePayload(&snapshot); err != nil {
			t.Fatalf("decode: %v", err)
		}
		if env.Type != TypeGameSnapshot || env.SeqValue() != 18 ||
			len(snapshot.Stack) != 1 || len(snapshot.Revealed) != 1 ||
			snapshot.Stack[0].OwnerSeat != 0 ||
			snapshot.Stack[0].Name != "Lightning Bolt" ||
			snapshot.Revealed[0].Name != "Mountain" {
			t.Fatalf("shared game snapshot = env %+v payload %+v", env, snapshot)
		}
	})

	t.Run("game-snapshot-move-owner.json", func(t *testing.T) {
		env, err := ParseEnvelope(loadFixture(t, "game-snapshot-move-owner.json"))
		if err != nil {
			t.Fatalf("parse: %v", err)
		}
		var snapshot GameSnapshot
		if err := env.DecodePayload(&snapshot); err != nil {
			t.Fatalf("decode: %v", err)
		}
		if len(snapshot.Seats) != 2 || len(snapshot.Seats[0].Hand) != 1 ||
			len(snapshot.Seats[0].Battlefield) != 1 ||
			snapshot.Seats[0].Battlefield[0].Position == nil ||
			snapshot.ActiveSeat != 1 || snapshot.CurrentPhase != GamePhaseUntap {
			t.Fatalf("owner move snapshot = %+v", snapshot.Seats)
		}
	})

	t.Run("game-snapshot-move-opponent.json", func(t *testing.T) {
		data := loadFixture(t, "game-snapshot-move-opponent.json")
		env, err := ParseEnvelope(data)
		if err != nil {
			t.Fatalf("parse: %v", err)
		}
		var snapshot GameSnapshot
		if err := env.DecodePayload(&snapshot); err != nil {
			t.Fatalf("decode: %v", err)
		}
		if len(snapshot.Seats) != 2 || len(snapshot.Seats[0].Hand) != 0 ||
			snapshot.Seats[0].HandCount != 1 ||
			len(snapshot.Seats[0].Battlefield) != 1 ||
			snapshot.Seats[0].Battlefield[0].Name != "Lightning Bolt" {
			t.Fatalf("opponent move snapshot = %+v", snapshot.Seats)
		}
		for _, hidden := range []string{"Mountain", "s0-c2"} {
			if bytes.Contains(data, []byte(hidden)) {
				t.Fatalf("opponent move snapshot leaked %q: %s", hidden, data)
			}
		}
	})

	t.Run("game-set-phase.json", func(t *testing.T) {
		env, err := ParseEnvelope(loadFixture(t, "game-set-phase.json"))
		if err != nil {
			t.Fatalf("parse: %v", err)
		}
		var request GameSetPhase
		if err := env.DecodePayload(&request); err != nil {
			t.Fatalf("decode: %v", err)
		}
		if env.Type != TypeGameSetPhase || env.ID != "phase-15" ||
			request.Phase != GamePhaseDeclareAttackers {
			t.Fatalf("game.set_phase = env %+v payload %+v", env, request)
		}
	})

	t.Run("game-phase-set.json", func(t *testing.T) {
		env, err := ParseEnvelope(loadFixture(t, "game-phase-set.json"))
		if err != nil {
			t.Fatalf("parse: %v", err)
		}
		var reply GamePhaseSet
		if err := env.DecodePayload(&reply); err != nil {
			t.Fatalf("decode: %v", err)
		}
		if env.Type != TypeGamePhaseSet || env.ID != "phase-15" ||
			reply.RoomID != "ABCDEF" || reply.Seat != 1 ||
			reply.Phase != GamePhaseDeclareAttackers {
			t.Fatalf("game.phase_set = env %+v payload %+v", env, reply)
		}
	})

	t.Run("game-set-counter.json", func(t *testing.T) {
		env, err := ParseEnvelope(loadFixture(t, "game-set-counter.json"))
		if err != nil {
			t.Fatalf("parse: %v", err)
		}
		var request GameSetCounter
		if err := env.DecodePayload(&request); err != nil {
			t.Fatalf("decode: %v", err)
		}
		if env.Type != TypeGameSetCounter || env.ID != "counter-1" ||
			request.Counter != PlayerCounterLife || request.Value == nil ||
			*request.Value != 19 || request.Delta != nil || request.Label != nil {
			t.Fatalf("game.set_counter = env %+v payload %+v", env, request)
		}
	})

	t.Run("game-adjust-counter.json", func(t *testing.T) {
		env, err := ParseEnvelope(loadFixture(t, "game-adjust-counter.json"))
		if err != nil {
			t.Fatalf("parse: %v", err)
		}
		var request GameSetCounter
		if err := env.DecodePayload(&request); err != nil {
			t.Fatalf("decode: %v", err)
		}
		if request.Counter != "counter-1" || request.Delta == nil ||
			*request.Delta != 1 || request.Value != nil || request.Label != nil {
			t.Fatalf("adjust counter payload = %+v", request)
		}
	})

	t.Run("game-rename-counter.json", func(t *testing.T) {
		env, err := ParseEnvelope(loadFixture(t, "game-rename-counter.json"))
		if err != nil {
			t.Fatalf("parse: %v", err)
		}
		var request GameSetCounter
		if err := env.DecodePayload(&request); err != nil {
			t.Fatalf("decode: %v", err)
		}
		if request.Counter != "counter-1" || request.Label == nil ||
			*request.Label != "Energy" || request.Value != nil ||
			request.Delta != nil {
			t.Fatalf("rename counter payload = %+v", request)
		}
	})

	t.Run("game-counter-set.json", func(t *testing.T) {
		env, err := ParseEnvelope(loadFixture(t, "game-counter-set.json"))
		if err != nil {
			t.Fatalf("parse: %v", err)
		}
		var reply GameCounterSet
		if err := env.DecodePayload(&reply); err != nil {
			t.Fatalf("decode: %v", err)
		}
		if env.Type != TypeGameCounterSet || env.ID != "counter-1" ||
			reply.RoomID != "ABCDEF" || reply.Seat != 0 ||
			reply.Counter != PlayerCounterLife || reply.Value != 19 {
			t.Fatalf("game.counter_set = env %+v payload %+v", env, reply)
		}
	})

	t.Run("game-counter-set-pip.json", func(t *testing.T) {
		env, err := ParseEnvelope(loadFixture(t, "game-counter-set-pip.json"))
		if err != nil {
			t.Fatalf("parse: %v", err)
		}
		var reply GameCounterSet
		if err := env.DecodePayload(&reply); err != nil {
			t.Fatalf("decode: %v", err)
		}
		if reply.Counter != "counter-1" || reply.Value != 1 ||
			reply.Label != "Energy" {
			t.Fatalf("pip game.counter_set = %+v", reply)
		}
	})

	t.Run("game-set-counter-count.json", func(t *testing.T) {
		env, err := ParseEnvelope(loadFixture(t, "game-set-counter-count.json"))
		if err != nil {
			t.Fatalf("parse: %v", err)
		}
		var request GameSetCounterCount
		if err := env.DecodePayload(&request); err != nil {
			t.Fatalf("decode: %v", err)
		}
		if env.Type != TypeGameSetCounterCount ||
			env.ID != "counter-count-1" || request.Count != 3 {
			t.Fatalf("game.set_counter_count = env %+v payload %+v",
				env, request)
		}
	})

	t.Run("game-counter-count-set.json", func(t *testing.T) {
		env, err := ParseEnvelope(loadFixture(t, "game-counter-count-set.json"))
		if err != nil {
			t.Fatalf("parse: %v", err)
		}
		var reply GameCounterCountSet
		if err := env.DecodePayload(&reply); err != nil {
			t.Fatalf("decode: %v", err)
		}
		if env.Type != TypeGameCounterCountSet ||
			env.ID != "counter-count-1" || reply.RoomID != "ABCDEF" ||
			reply.Seat != 0 || reply.Count != 3 {
			t.Fatalf("game.counter_count_set = env %+v payload %+v",
				env, reply)
		}
	})

	t.Run("game-concede.json", func(t *testing.T) {
		env, err := ParseEnvelope(loadFixture(t, "game-concede.json"))
		if err != nil {
			t.Fatalf("parse: %v", err)
		}
		var request GameConcede
		if err := env.DecodePayload(&request); err != nil {
			t.Fatalf("decode: %v", err)
		}
		if env.Type != TypeGameConcede || env.ID != "concede-17" ||
			len(env.Payload) != 0 {
			t.Fatalf("game.concede = %+v", env)
		}
	})

	t.Run("game-conceded.json", func(t *testing.T) {
		env, err := ParseEnvelope(loadFixture(t, "game-conceded.json"))
		if err != nil {
			t.Fatalf("parse: %v", err)
		}
		var reply GameConceded
		if err := env.DecodePayload(&reply); err != nil {
			t.Fatalf("decode: %v", err)
		}
		if env.Type != TypeGameConceded || env.ID != "concede-17" ||
			reply.RoomID != "ABCDEF" || reply.GameNumber != 1 ||
			reply.ConcededSeat != 0 || reply.WinnerSeat != 1 ||
			reply.MatchFinished || len(reply.Score) != 2 ||
			reply.Score[1] != 1 {
			t.Fatalf("game.conceded = env %+v payload %+v", env, reply)
		}
	})

	t.Run("game-say.json", func(t *testing.T) {
		env, err := ParseEnvelope(loadFixture(t, "game-say.json"))
		if err != nil {
			t.Fatalf("parse: %v", err)
		}
		var request GameSay
		if err := env.DecodePayload(&request); err != nil {
			t.Fatalf("decode: %v", err)
		}
		if env.Type != TypeGameSay || env.ID != "say-20" ||
			request.Message != "Good luck!" {
			t.Fatalf("game.say = env %+v payload %+v", env, request)
		}
	})

	t.Run("game-said.json", func(t *testing.T) {
		env, err := ParseEnvelope(loadFixture(t, "game-said.json"))
		if err != nil {
			t.Fatalf("parse: %v", err)
		}
		var reply GameSaid
		if err := env.DecodePayload(&reply); err != nil {
			t.Fatalf("decode: %v", err)
		}
		if env.Type != TypeGameSaid || env.ID != "say-20" ||
			reply.RoomID != "ABCDEF" || reply.LogID != 42 {
			t.Fatalf("game.said = env %+v payload %+v", env, reply)
		}
	})

	t.Run("game-return-to-room.json", func(t *testing.T) {
		env, err := ParseEnvelope(loadFixture(t, "game-return-to-room.json"))
		if err != nil {
			t.Fatalf("parse: %v", err)
		}
		var request GameReturnToRoom
		if err := env.DecodePayload(&request); err != nil {
			t.Fatalf("decode: %v", err)
		}
		if env.Type != TypeGameReturnToRoom || env.ID != "return-18" {
			t.Fatalf("game.return_to_room = %+v", env)
		}
	})

	t.Run("game-returned-to-room.json", func(t *testing.T) {
		env, err := ParseEnvelope(loadFixture(t, "game-returned-to-room.json"))
		if err != nil {
			t.Fatalf("parse: %v", err)
		}
		var reply GameReturnedToRoom
		if err := env.DecodePayload(&reply); err != nil {
			t.Fatalf("decode: %v", err)
		}
		if env.Type != TypeGameReturnedToRoom || env.ID != "return-18" ||
			reply.RoomID != "ABCDEF" {
			t.Fatalf("game.returned_to_room = env %+v payload %+v", env, reply)
		}
	})

	t.Run("game-snapshot-finished.json", func(t *testing.T) {
		data := loadFixture(t, "game-snapshot-finished.json")
		env, err := ParseEnvelope(data)
		if err != nil {
			t.Fatalf("parse: %v", err)
		}
		var snapshot GameSnapshot
		if err := env.DecodePayload(&snapshot); err != nil {
			t.Fatalf("decode: %v", err)
		}
		if env.Type != TypeGameSnapshot || env.SeqValue() != 24 ||
			snapshot.ActiveSeat != -1 || snapshot.Result == nil ||
			snapshot.Result.Reason != GameResultConcede ||
			snapshot.Result.WinnerSeat != 1 ||
			snapshot.Result.ConcededSeat != 0 ||
			snapshot.Result.MatchFinished ||
			len(snapshot.Score) != 2 || snapshot.Score[1] != 1 ||
			len(snapshot.Log) != 1 || snapshot.Log[0].Kind != "concede" {
			t.Fatalf("finished game snapshot = env %+v payload %+v",
				env, snapshot)
		}
		for _, hidden := range []string{"Lightning Bolt", "s0-c1", `"hand"`} {
			if bytes.Contains(data, []byte(hidden)) {
				t.Fatalf("finished snapshot leaked %q: %s", hidden, data)
			}
		}
	})

	t.Run("game-snapshot-departure.json", func(t *testing.T) {
		data := loadFixture(t, "game-snapshot-departure.json")
		env, err := ParseEnvelope(data)
		if err != nil {
			t.Fatalf("parse: %v", err)
		}
		var snapshot GameSnapshot
		if err := env.DecodePayload(&snapshot); err != nil {
			t.Fatalf("decode: %v", err)
		}
		if env.Type != TypeGameSnapshot || env.SeqValue() != 25 ||
			snapshot.ActiveSeat != -1 || snapshot.Result == nil ||
			snapshot.Result.Reason != GameResultDeparture ||
			snapshot.Result.WinnerSeat != 0 ||
			snapshot.Result.ConcededSeat != 1 ||
			!snapshot.Result.MatchFinished ||
			len(snapshot.Score) != 2 || snapshot.Score[0] != 2 ||
			len(snapshot.Log) != 1 || snapshot.Log[0].Kind != "departure" {
			t.Fatalf("departure game snapshot = env %+v payload %+v",
				env, snapshot)
		}
	})

	t.Run("game-next-turn.json", func(t *testing.T) {
		env, err := ParseEnvelope(loadFixture(t, "game-next-turn.json"))
		if err != nil {
			t.Fatalf("parse: %v", err)
		}
		if env.Type != TypeGameNextTurn || env.ID != "turn-16" ||
			len(env.Payload) != 0 {
			t.Fatalf("game.next_turn = %+v", env)
		}
	})

	t.Run("game-turn-advanced.json", func(t *testing.T) {
		env, err := ParseEnvelope(loadFixture(t, "game-turn-advanced.json"))
		if err != nil {
			t.Fatalf("parse: %v", err)
		}
		var reply GameTurnAdvanced
		if err := env.DecodePayload(&reply); err != nil {
			t.Fatalf("decode: %v", err)
		}
		if env.Type != TypeGameTurnAdvanced || env.ID != "turn-16" ||
			reply.RoomID != "ABCDEF" || reply.ActiveSeat != 0 ||
			reply.CurrentPhase != GamePhaseUntap {
			t.Fatalf("game.turn_advanced = env %+v payload %+v", env, reply)
		}
	})

	t.Run("room-full-error.json", func(t *testing.T) {
		env, err := ParseEnvelope(loadFixture(t, "room-full-error.json"))
		if err != nil {
			t.Fatalf("parse: %v", err)
		}
		var ep ErrorPayload
		if err := env.DecodePayload(&ep); err != nil {
			t.Fatalf("decode: %v", err)
		}
		if ep.Code != ErrRoomFull {
			t.Fatalf("code = %q, want %q", ep.Code, ErrRoomFull)
		}
	})

	t.Run("wrong-password-error.json", func(t *testing.T) {
		env, err := ParseEnvelope(loadFixture(t, "wrong-password-error.json"))
		if err != nil {
			t.Fatalf("parse: %v", err)
		}
		var ep ErrorPayload
		if err := env.DecodePayload(&ep); err != nil {
			t.Fatalf("decode: %v", err)
		}
		if ep.Code != ErrWrongPassword {
			t.Fatalf("code = %q, want %q", ep.Code, ErrWrongPassword)
		}
	})
}
