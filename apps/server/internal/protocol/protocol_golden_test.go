// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package protocol

import (
	"bytes"
	"testing"
)

func TestGoldenFixtures(t *testing.T) {
	t.Run("session-hello.json", func(t *testing.T) {
		data := loadFixture(t, "session-hello.json")
		top := topKeys(t, data)
		if _, ok := top["v"]; ok {
			t.Fatalf("session.hello fixture must not carry top-level v: %s", data)
		}
		env, err := ParseEnvelope(data)
		if err != nil {
			t.Fatalf("parse hello fixture: %v", err)
		}
		if env.Type != TypeSessionHello {
			t.Fatalf("type = %q, want %q", env.Type, TypeSessionHello)
		}
		if env.ID != "req-1" {
			t.Fatalf("id = %q, want req-1", env.ID)
		}
		var h SessionHello
		if err := env.DecodePayload(&h); err != nil {
			t.Fatalf("decode hello payload: %v", err)
		}
		if h.Protocol != ProtocolVersion {
			t.Fatalf("offered protocol = %q, want %q", h.Protocol, ProtocolVersion)
		}
	})

	t.Run("session-welcome.json", func(t *testing.T) {
		data := loadFixture(t, "session-welcome.json")
		top := topKeys(t, data)
		if _, ok := top["v"]; ok {
			t.Fatalf("welcome fixture must not carry top-level v: %s", data)
		}
		env, err := ParseEnvelope(data)
		if err != nil {
			t.Fatalf("parse welcome fixture: %v", err)
		}
		if env.Type != TypeSessionWelcome {
			t.Fatalf("type = %q, want %q", env.Type, TypeSessionWelcome)
		}
		// seq is per-room and lives only on room.snapshot/room.event (plan §2).
		// session.welcome is session-level and must NOT carry seq. The handler
		// (handleHello) does not stamp seq on welcome; the fixture must match.
		if env.HasSeq() {
			t.Fatalf("welcome fixture must not carry seq: %s", data)
		}
		var w SessionWelcome
		if err := env.DecodePayload(&w); err != nil {
			t.Fatalf("decode welcome payload: %v", err)
		}
		if err := ValidateWelcome(w); err != nil {
			t.Fatalf("welcome fixture v invalid: %v", err)
		}
		if w.ResumeToken == "" {
			t.Fatal("welcome fixture must carry a resume credential")
		}
	})

	t.Run("session-resume-hello.json", func(t *testing.T) {
		env, err := ParseEnvelope(loadFixture(t, "session-resume-hello.json"))
		if err != nil {
			t.Fatalf("parse resume hello fixture: %v", err)
		}
		var hello SessionHello
		if err := env.DecodePayload(&hello); err != nil {
			t.Fatalf("decode resume hello payload: %v", err)
		}
		if env.Type != TypeSessionHello || hello.ResumeToken == "" ||
			hello.LastSeq != 41 {
			t.Fatalf("resume hello fixture = env %+v payload %+v", env, hello)
		}
	})

	t.Run("session-resumed.json", func(t *testing.T) {
		data := loadFixture(t, "session-resumed.json")
		top := topKeys(t, data)
		if _, ok := top["v"]; ok {
			t.Fatalf("resumed welcome must not carry top-level v: %s", data)
		}
		env, err := ParseEnvelope(data)
		if err != nil {
			t.Fatalf("parse resumed welcome fixture: %v", err)
		}
		var welcome SessionWelcome
		if err := env.DecodePayload(&welcome); err != nil {
			t.Fatalf("decode resumed welcome payload: %v", err)
		}
		if !welcome.Resumed || welcome.RoomID != "ABCDEF" ||
			welcome.Role != RolePlayer || welcome.Seat == nil ||
			*welcome.Seat != 0 || !welcome.Host ||
			welcome.ResumeToken == "" {
			t.Fatalf("resumed welcome fixture = %+v", welcome)
		}
	})

	t.Run("error.json", func(t *testing.T) {
		data := loadFixture(t, "error.json")
		env, err := ParseEnvelope(data)
		if err != nil {
			t.Fatalf("parse error fixture: %v", err)
		}
		if env.Type != TypeError {
			t.Fatalf("type = %q, want %q", env.Type, TypeError)
		}
		if env.ID != "req-9" {
			t.Fatalf("error fixture must echo correlation id; got %q", env.ID)
		}
		var ep ErrorPayload
		if err := env.DecodePayload(&ep); err != nil {
			t.Fatalf("decode error payload: %v", err)
		}
		if ep.Code != "room_full" {
			t.Fatalf("code = %q, want room_full", ep.Code)
		}
	})

	t.Run("room-create.json", func(t *testing.T) {
		env, err := ParseEnvelope(loadFixture(t, "room-create.json"))
		if err != nil {
			t.Fatalf("parse: %v", err)
		}
		if env.Type != TypeRoomCreate || env.ID != "c1" {
			t.Fatalf("type/id = %q/%q", env.Type, env.ID)
		}
		var rc RoomCreate
		if err := env.DecodePayload(&rc); err != nil {
			t.Fatalf("decode: %v", err)
		}
		if rc.Format != FormatEDH || rc.MaxSeats != 4 || rc.MatchMode != MatchBO3 ||
			rc.CardLoadMode != CardLoadPreload || !rc.SpectatorsSeeHands {
			t.Fatalf("room.create = %+v", rc)
		}
	})

	t.Run("room-created.json", func(t *testing.T) {
		env, err := ParseEnvelope(loadFixture(t, "room-created.json"))
		if err != nil {
			t.Fatalf("parse: %v", err)
		}
		if env.Type != TypeRoomCreated {
			t.Fatalf("type = %q", env.Type)
		}
		if env.HasSeq() {
			t.Fatalf("room.created must not carry seq")
		}
		var rc RoomCreated
		if err := env.DecodePayload(&rc); err != nil {
			t.Fatalf("decode: %v", err)
		}
		if rc.RoomID != "ABCDEF" || rc.HostSeat != 0 {
			t.Fatalf("room.created = %+v", rc)
		}
		if rc.Settings.HasPassword {
			t.Fatal("hasPassword should be false")
		}
		if rc.Settings.CardLoadMode != CardLoadPreload {
			t.Fatalf("cardLoadMode = %q", rc.Settings.CardLoadMode)
		}
		if !rc.Settings.SpectatorsSeeHands {
			t.Fatal("spectator hand visibility should be enabled")
		}
	})

	t.Run("room-join-player.json", func(t *testing.T) {
		env, err := ParseEnvelope(loadFixture(t, "room-join-player.json"))
		if err != nil {
			t.Fatalf("parse: %v", err)
		}
		var rj RoomJoin
		if err := env.DecodePayload(&rj); err != nil {
			t.Fatalf("decode: %v", err)
		}
		if rj.AsSpectator {
			t.Fatal("player join should have asSpectator=false")
		}
	})

	t.Run("room-join-spectator.json", func(t *testing.T) {
		env, err := ParseEnvelope(loadFixture(t, "room-join-spectator.json"))
		if err != nil {
			t.Fatalf("parse: %v", err)
		}
		var rj RoomJoin
		if err := env.DecodePayload(&rj); err != nil {
			t.Fatalf("decode: %v", err)
		}
		if !rj.AsSpectator {
			t.Fatal("spectator join should have asSpectator=true")
		}
	})

	t.Run("room-snapshot-owner.json", func(t *testing.T) {
		env, err := ParseEnvelope(loadFixture(t, "room-snapshot-owner.json"))
		if err != nil {
			t.Fatalf("parse: %v", err)
		}
		if env.Type != TypeRoomSnapshot {
			t.Fatalf("type = %q", env.Type)
		}
		if !env.HasSeq() || env.SeqValue() != 1 {
			t.Fatalf("snapshot seq = %v, want 1", env.SeqValue())
		}
		var snap RoomSnapshot
		if err := env.DecodePayload(&snap); err != nil {
			t.Fatalf("decode: %v", err)
		}
		if len(snap.Seats) != 4 || !snap.Seats[0].Host || snap.Seats[0].DisplayName != "Alice" {
			t.Fatalf("seats = %+v", snap.Seats)
		}
	})

	t.Run("room-snapshot-opponent.json", func(t *testing.T) {
		// Oppponent-view fixture. In P1 owner and opponent snapshots have the
		// same public shape (no hidden zones yet); P3 will diverge them with
		// redaction. Pin the seat-occupancy difference vs the owner fixture so
		// this file is a live golden source, not an orphan.
		env, err := ParseEnvelope(loadFixture(t, "room-snapshot-opponent.json"))
		if err != nil {
			t.Fatalf("parse: %v", err)
		}
		if env.Type != TypeRoomSnapshot {
			t.Fatalf("type = %q", env.Type)
		}
		if !env.HasSeq() || env.SeqValue() != 2 {
			t.Fatalf("snapshot seq = %v, want 2", env.SeqValue())
		}
		var snap RoomSnapshot
		if err := env.DecodePayload(&snap); err != nil {
			t.Fatalf("decode: %v", err)
		}
		// Two seats occupied (Alice host + Bob), vs owner fixture's one.
		occupied := 0
		for _, s := range snap.Seats {
			if s.Occupied {
				occupied++
			}
		}
		if occupied != 2 {
			t.Fatalf("occupied seats = %d, want 2", occupied)
		}
		if !snap.Seats[0].Host || snap.Seats[1].DisplayName != "Bob" {
			t.Fatalf("seats = %+v", snap.Seats)
		}
	})

	t.Run("deck-select.json", func(t *testing.T) {
		env, err := ParseEnvelope(loadFixture(t, "deck-select.json"))
		if err != nil {
			t.Fatalf("parse: %v", err)
		}
		var deck DeckSelect
		if err := env.DecodePayload(&deck); err != nil {
			t.Fatalf("decode: %v", err)
		}
		if env.Type != TypeDeckSelect || env.ID != "d1" || deck.Format != FormatModern {
			t.Fatalf("deck.select = type %q id %q payload %+v", env.Type, env.ID, deck)
		}
		if len(deck.Mainboard) != 1 || deck.Mainboard[0].Name != "Lightning Bolt" ||
			deck.Mainboard[0].Count != MinMainboardCards ||
			deck.Mainboard[0].TypeLine != "Instant" {
			t.Fatalf("mainboard = %+v", deck.Mainboard)
		}
	})

	t.Run("deck-selected.json", func(t *testing.T) {
		env, err := ParseEnvelope(loadFixture(t, "deck-selected.json"))
		if err != nil {
			t.Fatalf("parse: %v", err)
		}
		var selected DeckSelected
		if err := env.DecodePayload(&selected); err != nil {
			t.Fatalf("decode: %v", err)
		}
		if env.Type != TypeDeckSelected || env.ID != "d1" || selected.Seat != 0 {
			t.Fatalf("deck.selected = type %q id %q payload %+v", env.Type, env.ID, selected)
		}
	})

	t.Run("player-ready.json", func(t *testing.T) {
		env, err := ParseEnvelope(loadFixture(t, "player-ready.json"))
		if err != nil {
			t.Fatalf("parse: %v", err)
		}
		var ready PlayerReady
		if err := env.DecodePayload(&ready); err != nil {
			t.Fatalf("decode: %v", err)
		}
		if env.Type != TypePlayerReady || env.ID != "r1" || !ready.Ready {
			t.Fatalf("player.ready = type %q id %q payload %+v", env.Type, env.ID, ready)
		}
	})

	t.Run("player-ready-changed.json", func(t *testing.T) {
		env, err := ParseEnvelope(loadFixture(t, "player-ready-changed.json"))
		if err != nil {
			t.Fatalf("parse: %v", err)
		}
		var ready PlayerReadyChanged
		if err := env.DecodePayload(&ready); err != nil {
			t.Fatalf("decode: %v", err)
		}
		if env.Type != TypePlayerReadyChanged || env.ID != "r1" || !ready.Ready {
			t.Fatalf("player.ready_changed = type %q id %q payload %+v", env.Type, env.ID, ready)
		}
	})

	t.Run("room-snapshot-ready.json", func(t *testing.T) {
		data := loadFixture(t, "room-snapshot-ready.json")
		env, err := ParseEnvelope(data)
		if err != nil {
			t.Fatalf("parse: %v", err)
		}
		var snapshot RoomSnapshot
		if err := env.DecodePayload(&snapshot); err != nil {
			t.Fatalf("decode: %v", err)
		}
		if !env.HasSeq() || env.SeqValue() != 7 || !snapshot.Seats[0].DeckSelected || !snapshot.Seats[0].Ready {
			t.Fatalf("ready snapshot = seq %d seats %+v", env.SeqValue(), snapshot.Seats)
		}
		for _, hidden := range []string{"Lightning Bolt", "M11", "149"} {
			if bytes.Contains(data, []byte(hidden)) {
				t.Fatalf("ready snapshot leaked %q: %s", hidden, data)
			}
		}
	})

	t.Run("match-load-required.json", func(t *testing.T) {
		data := loadFixture(t, "match-load-required.json")
		env, err := ParseEnvelope(data)
		if err != nil {
			t.Fatalf("parse: %v", err)
		}
		var required MatchLoadRequired
		if err := env.DecodePayload(&required); err != nil {
			t.Fatalf("decode: %v", err)
		}
		if env.Type != TypeMatchLoadRequired || !env.HasSeq() || required.LoadID != 1 || len(required.CardKeys) != 2 {
			t.Fatalf("match.load_required = env %+v payload %+v", env, required)
		}
		for _, forbidden := range []string{"count", "seat", "sideboard", "deckName"} {
			if bytes.Contains(data, []byte(`"`+forbidden+`"`)) {
				t.Fatalf("load keys leaked %q grouping: %s", forbidden, data)
			}
		}
	})

	t.Run("client-load-complete.json", func(t *testing.T) {
		env, err := ParseEnvelope(loadFixture(t, "client-load-complete.json"))
		if err != nil {
			t.Fatalf("parse: %v", err)
		}
		var complete ClientLoadComplete
		if err := env.DecodePayload(&complete); err != nil {
			t.Fatalf("decode: %v", err)
		}
		if env.Type != TypeClientLoadComplete || env.ID != "l1" || complete.LoadID != 1 {
			t.Fatalf("client.load_complete = env %+v payload %+v", env, complete)
		}
	})

	t.Run("client-load-completed.json", func(t *testing.T) {
		env, err := ParseEnvelope(loadFixture(t, "client-load-completed.json"))
		if err != nil {
			t.Fatalf("parse: %v", err)
		}
		var completed ClientLoadCompleted
		if err := env.DecodePayload(&completed); err != nil {
			t.Fatalf("decode: %v", err)
		}
		if env.Type != TypeClientLoadCompleted || env.ID != "l1" || completed.RoomID != "ABCDEF" {
			t.Fatalf("client.load_completed = env %+v payload %+v", env, completed)
		}
	})

	t.Run("room-snapshot-loading.json", func(t *testing.T) {
		env, err := ParseEnvelope(loadFixture(t, "room-snapshot-loading.json"))
		if err != nil {
			t.Fatalf("parse: %v", err)
		}
		var snapshot RoomSnapshot
		if err := env.DecodePayload(&snapshot); err != nil {
			t.Fatalf("decode: %v", err)
		}
		if snapshot.Phase != RoomPhaseLoading || snapshot.LoadID != 1 ||
			snapshot.CardLoadMode != CardLoadPreload || !snapshot.Seats[0].Loaded {
			t.Fatalf("loading snapshot = %+v", snapshot)
		}
	})

	t.Run("match-started.json", func(t *testing.T) {
		env, err := ParseEnvelope(loadFixture(t, "match-started.json"))
		if err != nil {
			t.Fatalf("parse: %v", err)
		}
		var started MatchStarted
		if err := env.DecodePayload(&started); err != nil {
			t.Fatalf("decode: %v", err)
		}
		if env.Type != TypeMatchStarted || !env.HasSeq() || started.RoomID != "ABCDEF" || started.LoadID != 1 {
			t.Fatalf("match.started = env %+v payload %+v", env, started)
		}
	})

	t.Run("game-snapshot-owner.json", func(t *testing.T) {
		env, err := ParseEnvelope(loadFixture(t, "game-snapshot-owner.json"))
		if err != nil {
			t.Fatalf("parse: %v", err)
		}
		var snapshot GameSnapshot
		if err := env.DecodePayload(&snapshot); err != nil {
			t.Fatalf("decode: %v", err)
		}
		if env.Type != TypeGameSnapshot || env.SeqValue() != 12 || snapshot.StartingSeat != 1 {
			t.Fatalf("owner game snapshot = env %+v payload %+v", env, snapshot)
		}
		if len(snapshot.Seats) != 2 || len(snapshot.Seats[0].Hand) != 7 || len(snapshot.Seats[1].Hand) != 0 {
			t.Fatalf("owner projected hands = %+v", snapshot.Seats)
		}
		if len(snapshot.Seats[0].Counters) != PlayerCounterSlotCount ||
			snapshot.Seats[0].Counters[0].Key != "counter-1" ||
			snapshot.Seats[0].Counters[6].Label != "" ||
			snapshot.Seats[0].CounterCount != 3 ||
			snapshot.Seats[1].CounterCount != 1 {
			t.Fatalf("owner projected counters = %+v", snapshot.Seats[0].Counters)
		}
	})

	t.Run("game-snapshot-opponent.json", func(t *testing.T) {
		data := loadFixture(t, "game-snapshot-opponent.json")
		env, err := ParseEnvelope(data)
		if err != nil {
			t.Fatalf("parse: %v", err)
		}
		var snapshot GameSnapshot
		if err := env.DecodePayload(&snapshot); err != nil {
			t.Fatalf("decode: %v", err)
		}
		if len(snapshot.Seats[0].Hand) != 0 || len(snapshot.Seats[1].Hand) != 7 {
			t.Fatalf("opponent projected hands = %+v", snapshot.Seats)
		}
		if len(snapshot.Seats[0].Counters) != PlayerCounterSlotCount ||
			len(snapshot.Seats[1].Counters) != PlayerCounterSlotCount ||
			snapshot.Seats[0].CounterCount != 3 ||
			snapshot.Seats[1].CounterCount != 1 {
			t.Fatalf("opponent projected counters = %+v", snapshot.Seats)
		}
		for _, hidden := range []string{"Lightning Bolt", "Mountain", "s0-c1"} {
			if bytes.Contains(data, []byte(hidden)) {
				t.Fatalf("opponent snapshot leaked %q: %s", hidden, data)
			}
		}
	})

	t.Run("game-draw.json", func(t *testing.T) {
		env, err := ParseEnvelope(loadFixture(t, "game-draw.json"))
		if err != nil {
			t.Fatalf("parse: %v", err)
		}
		if env.Type != TypeGameDraw || env.ID != "g1" {
			t.Fatalf("game.draw = %+v", env)
		}
		var draw GameDraw
		if err := env.DecodePayload(&draw); err != nil ||
			draw.Count == nil || *draw.Count != 3 {
			t.Fatalf("game.draw payload = %+v err=%v", draw, err)
		}
	})

	t.Run("game-drawn.json", func(t *testing.T) {
		env, err := ParseEnvelope(loadFixture(t, "game-drawn.json"))
		if err != nil {
			t.Fatalf("parse: %v", err)
		}
		var drawn GameDrawn
		if err := env.DecodePayload(&drawn); err != nil {
			t.Fatalf("decode: %v", err)
		}
		if env.Type != TypeGameDrawn || drawn.Seat != 0 || drawn.Count != 3 {
			t.Fatalf("game.drawn = env %+v payload %+v", env, drawn)
		}
	})

	t.Run("game-shuffle-library.json", func(t *testing.T) {
		env, err := ParseEnvelope(loadFixture(t, "game-shuffle-library.json"))
		if err != nil {
			t.Fatalf("parse: %v", err)
		}
		if env.Type != TypeGameShuffleLibrary || env.ID != "shuffle-1" {
			t.Fatalf("game.shuffle_library = %+v", env)
		}
	})

	t.Run("game-library-shuffled.json", func(t *testing.T) {
		env, err := ParseEnvelope(loadFixture(t, "game-library-shuffled.json"))
		if err != nil {
			t.Fatalf("parse: %v", err)
		}
		var shuffled GameLibraryShuffled
		if err := env.DecodePayload(&shuffled); err != nil {
			t.Fatalf("decode: %v", err)
		}
		if env.Type != TypeGameLibraryShuffled ||
			shuffled.RoomID != "room-1" || shuffled.Seat != 0 {
			t.Fatalf("game.library_shuffled = env %+v payload %+v",
				env, shuffled)
		}
	})

	t.Run("game-mulligan.json", func(t *testing.T) {
		env, err := ParseEnvelope(loadFixture(t, "game-mulligan.json"))
		if err != nil {
			t.Fatalf("parse: %v", err)
		}
		if env.Type != TypeGameMulligan || env.ID != "g2" {
			t.Fatalf("game.mulligan = %+v", env)
		}
	})

	t.Run("game-mulliganed.json", func(t *testing.T) {
		env, err := ParseEnvelope(loadFixture(t, "game-mulliganed.json"))
		if err != nil {
			t.Fatalf("parse: %v", err)
		}
		var mulliganed GameMulliganed
		if err := env.DecodePayload(&mulliganed); err != nil {
			t.Fatalf("decode: %v", err)
		}
		if env.Type != TypeGameMulliganed || mulliganed.HandSize != 7 ||
			mulliganed.MulliganCount != 1 {
			t.Fatalf("game.mulliganed = env %+v payload %+v", env, mulliganed)
		}
	})

	t.Run("game-discard-hand.json", func(t *testing.T) {
		env, err := ParseEnvelope(loadFixture(t, "game-discard-hand.json"))
		var discard GameDiscardHand
		if err != nil || env.DecodePayload(&discard) != nil ||
			env.Type != TypeGameDiscardHand || env.ID != "discard-hand-1" ||
			discard.All {
			t.Fatalf("game.discard_hand = env %+v payload %+v err %v",
				env, discard, err)
		}
	})

	t.Run("game-hand-discarded.json", func(t *testing.T) {
		env, err := ParseEnvelope(loadFixture(t, "game-hand-discarded.json"))
		var discarded GameHandDiscarded
		if err != nil || env.DecodePayload(&discarded) != nil ||
			env.Type != TypeGameHandDiscarded || env.ID != "discard-hand-1" ||
			discarded.RoomID != "room-1" || discarded.Seat != 0 ||
			discarded.Count != 1 {
			t.Fatalf("game.hand_discarded = env %+v payload %+v err %v",
				env, discarded, err)
		}
	})

}
