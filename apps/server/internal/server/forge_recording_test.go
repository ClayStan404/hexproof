// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package server

import (
	"context"
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"hexproof/server/internal/protocol"
	"hexproof/server/internal/room"
	"hexproof/server/internal/rulesengine/forge"
)

type recordingRuntime struct {
	forge.Runtime
	batch *forge.ReplayBatch
}

func (r recordingRuntime) Replay(context.Context, string, int64) (*forge.ReplayBatch, error) {
	return r.batch, nil
}

func recordingFixture(t *testing.T) (*Handler, *room.Room, forgeRoomGame, []*Session) {
	t.Helper()
	cfg := DefaultConfig()
	cfg.RetentionDir = t.TempDir()
	h := retentionHandler(t, cfg)
	players := []*Session{retentionSession(h, "alice"), retentionSession(h, "bob"), retentionSession(h, "spectator")}
	for _, player := range players {
		player.DisplayName = player.ConnectionID
	}
	r, err := room.NewWithRulesMode("RECORD", "Recorded match", protocol.FormatModern, protocol.MatchBO3, protocol.CardLoadBackground,
		protocol.RulesModeForge, 2, true, false, "alice", "alice", time.Now())
	if err != nil {
		t.Fatal(err)
	}
	r.Seats[1] = room.Seat{Occupied: true, DisplayName: "bob", ConnectionID: "bob"}
	r.Spectators = append(r.Spectators, room.Spectator{DisplayName: "spectator", ConnectionID: "spectator"})
	r.Phase = protocol.RoomPhaseStarted
	view := forge.GameView{GameID: "record-1", ActivePlayerID: "player-0", PriorityPlayerID: "player-1", Turn: 1, Step: "main1",
		Players: []forge.PlayerView{{ID: "player-0", Name: "alice", Status: "playing", Life: 20}, {ID: "player-1", Name: "bob", Status: "playing", Life: 20}}, Stack: []forge.StackObjectView{},
		Zones: []forge.ZoneView{{Zone: "hand", OwnerID: "player-0", Count: 1, Cards: []forge.CardView{{ID: "card-1", Visibility: "visible", Identity: &forge.CardIdentityView{Name: "SECRET A"}}}},
			{Zone: "hand", OwnerID: "player-1", Count: 1, Cards: []forge.CardView{{ID: "card-2", Visibility: "visible", Identity: &forge.CardIdentityView{Name: "SECRET B"}}}}}}
	raw, _ := json.Marshal(view)
	batch := &forge.ReplayBatch{Complete: true, LastSequence: 1, Frames: []forge.ReplayFrame{{Sequence: 1, Kind: "SpellAbilityCast", Actor: 1, Text: "bob casts a spell", View: raw, Combat: []forge.ReplayRelation{}}}}
	game := forgeRoomGame{gameID: "record-1", sessionID: "record-1", client: recordingRuntime{batch: batch}, playerToSeat: map[int]int{0: 0, 1: 1}, seatToPlayer: map[int]int{0: 0, 1: 1}}
	return h, r, game, players
}

func recordingRead(t *testing.T, h *Handler, sess *Session, id, token string) protocol.Envelope {
	t.Helper()
	env, _ := protocol.NewEnvelope(protocol.TypeForgeReplayGet, protocol.ForgeReplayGet{ReplayID: id, Token: token})
	env.ID = "download"
	if err := h.handleForgeReplayGet(sess, env); err != nil {
		t.Fatal(err)
	}
	select {
	case raw := <-sess.Send:
		var result protocol.Envelope
		if err := json.Unmarshal(raw, &result); err != nil {
			t.Fatal(err)
		}
		return result
	default:
		t.Fatal("no replay response")
		return protocol.Envelope{}
	}
}

func TestForgeRecordingWholeMatchGateAndParticipantCapabilities(t *testing.T) {
	h, r, game, players := recordingFixture(t)
	h.collectForgeReplay(r, game)
	h.collectForgeReplay(r, game) // Retry must not duplicate history.
	record := h.forgeReplays.active[r]
	if len(record.Frames) != 1 || record.Frames[0].ActorSeat != 1 || record.Frames[0].Snapshot.ActiveSeat != 0 {
		t.Fatal("recording lost actor, turn owner, or deduplication")
	}
	h.publishForgeReplay(r)
	for _, player := range players[:2] {
		var env protocol.Envelope
		json.Unmarshal(<-player.Send, &env)
		if env.Type != protocol.TypeForgeReplayGrant {
			t.Fatal("participant not granted a replay")
		}
		var grant protocol.ForgeReplayGrant
		env.DecodePayload(&grant)
		if grant.Token == "" || strings.Contains(string(env.Payload), "SECRET") {
			t.Fatal("live grant exposed a frame or lacked its private capability")
		}
	}
	if len(players[2].Send) != 0 {
		t.Fatal("spectator received a private replay grant")
	}
	if recordingRead(t, h, players[0], record.Grant.ReplayID, record.Tokens[0]).Type != protocol.TypeError {
		t.Fatal("live match downloaded")
	}
	r.Game = &room.GameState{Result: &protocol.GameResult{MatchFinished: false}}
	h.publishForgeReplay(r)
	if recordingRead(t, h, players[0], record.Grant.ReplayID, record.Tokens[0]).Type != protocol.TypeError {
		t.Fatal("BO3 sideboard disclosed hands")
	}
	r.Game.Result.MatchFinished = true
	h.publishForgeReplay(r)
	for _, player := range players[:2] {
		<-player.Send
	}
	if recordingRead(t, h, players[2], record.Grant.ReplayID, strings.Repeat("0", 64)).Type != protocol.TypeError {
		t.Fatal("stranger downloaded full replay")
	}
	for seat, player := range players[:2] {
		result := recordingRead(t, h, player, record.Grant.ReplayID, record.Tokens[seat])
		if result.Type != protocol.TypeForgeReplayPage || !strings.Contains(string(result.Payload), "SECRET A") || !strings.Contains(string(result.Payload), "SECRET B") {
			t.Fatalf("participant replay incomplete: %s", result.Payload)
		}
		if strings.Contains(string(result.Payload), record.Tokens[seat]) {
			t.Fatal("exportable frames contain access credentials")
		}
	}
	info, err := os.Stat(filepath.Join(h.config.RetentionDir, "forge", record.Grant.ReplayID+".json.gz"))
	if err != nil || info.Mode().Perm() != 0600 {
		t.Fatal("private recording file permissions", err)
	}
	// A new handler has no room/session authority but the dedicated capability
	// still retrieves a finished archive; this is separate from reconnect tokens.
	reloaded := retentionHandler(t, h.config)
	if recordingRead(t, reloaded, players[0], record.Grant.ReplayID, record.Tokens[0]).Type != protocol.TypeForgeReplayPage {
		t.Fatal("finished archive did not survive server restart")
	}
}

func TestForgeRecordingReconnectDoesNotGrantReplacementOrSpectator(t *testing.T) {
	h, r, game, players := recordingFixture(t)
	h.collectForgeReplay(r, game)
	record := h.forgeReplays.active[r]
	resumed := retentionSession(h, "resumed")
	resumed.DisplayName = "alice"
	r.Seats[0].ConnectionID = resumed.ConnectionID
	h.publishForgeReplay(r)
	if len(resumed.Send) != 0 {
		t.Fatal("a new occupant acquired the previous seat's replay")
	}
	h.forgeReplays.rebind(r, players[0].ConnectionID, resumed.ConnectionID)
	h.publishForgeReplay(r)
	var envelope protocol.Envelope
	json.Unmarshal(<-resumed.Send, &envelope)
	var grant protocol.ForgeReplayGrant
	envelope.DecodePayload(&grant)
	if grant.Token != record.Tokens[0] {
		t.Fatal("authenticated reconnect lost its replay capability")
	}
}

func TestForgeRecordingExpiryAndGapAreExplicit(t *testing.T) {
	h, r, game, players := recordingFixture(t)
	batch := game.client.(recordingRuntime).batch
	batch.Frames[0].Sequence = 3
	batch.LastSequence = 3
	h.collectForgeReplay(r, game)
	record := h.forgeReplays.active[r]
	if record.Grant.Complete {
		t.Fatal("missing history was presented as complete")
	}
	r.Game = &room.GameState{Result: &protocol.GameResult{MatchFinished: true}}
	h.publishForgeReplay(r)
	for _, player := range players[:2] {
		<-player.Send
	}
	record.Grant.ExpiresAt = time.Now().Add(-time.Hour).Format(time.RFC3339)
	if recordingRead(t, h, players[0], record.Grant.ReplayID, record.Tokens[0]).Type != protocol.TypeError {
		t.Fatal("expired private replay was served")
	}
}

func TestForgeRecordingNewMatchAndRemovedRoom(t *testing.T) {
	h, r, game, _ := recordingFixture(t)
	h.collectForgeReplay(r, game)
	old := h.forgeReplays.active[r]
	r.Game = &room.GameState{Result: &protocol.GameResult{MatchFinished: true}}
	h.publishForgeReplay(r)
	h.collectForgeReplay(r, game)
	if h.forgeReplays.active[r] != old || len(old.Frames) != 1 {
		t.Fatal("finished retry started a new recording")
	}
	game.gameID = "next-match"
	r.Game = nil
	h.collectForgeReplay(r, game)
	current := h.forgeReplays.active[r]
	if current == old || current.Grant.ReplayID == old.Grant.ReplayID || current.Grant.Finished {
		t.Fatal("new match reused the previous archive")
	}
	h.forgeReplays.discard(r.ID)
	if len(h.forgeReplays.active) != 0 || h.forgeReplays.bytes != int64(old.Bytes) {
		t.Fatal("room removal retained active history")
	}
	if _, err := h.forgeReplays.load(old.Grant.ReplayID); err != nil {
		t.Fatal("finished recording lost on next match removal", err)
	}
}

func TestForgeRecordingDiskQuota(t *testing.T) {
	h, r, game, _ := recordingFixture(t)
	h.forgeReplays.config.RetentionMaxFiles = 1
	h.collectForgeReplay(r, game)
	first := h.forgeReplays.active[r]
	r.Game = &room.GameState{Result: &protocol.GameResult{MatchFinished: true}}
	h.publishForgeReplay(r)
	game.gameID = "second-match"
	h.collectForgeReplay(r, game)
	second := h.forgeReplays.active[r]
	h.publishForgeReplay(r)
	files, err := filepath.Glob(filepath.Join(h.config.RetentionDir, "forge", "*.json.gz"))
	if err != nil || len(files) != 1 {
		t.Fatalf("archive quota not enforced: %v %v", files, err)
	}
	if _, err := h.forgeReplays.load(first.Grant.ReplayID); err == nil {
		t.Fatal("evicted private archive still available")
	}
	if _, err := h.forgeReplays.load(second.Grant.ReplayID); err != nil {
		t.Fatal(err)
	}
}
