// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package forgehost

import (
	"context"
	"encoding/json"
	"strings"
	"testing"

	"hexproof/server/internal/rulesengine/forge"
)

type checkpointFixture struct{ *fixtureRuntime }

func (f checkpointFixture) Snapshot(ctx context.Context, session string, viewer int) (json.RawMessage, error) {
	raw, err := f.fixtureRuntime.Snapshot(ctx, session, viewer)
	if err != nil {
		return nil, err
	}
	var view map[string]any
	_ = json.Unmarshal(raw, &view)
	view["integrityHash"] = strings.Repeat("a", 64)
	return json.Marshal(view)
}
func checkpointStart(context.Context) (forge.Runtime, error) {
	return checkpointFixture{&fixtureRuntime{done: make(chan struct{})}}, nil
}

func TestCheckpointReplaysThroughNewLinkAndKeepsLaterHistory(t *testing.T) {
	link, ctx := newRelayFixture(t, checkpointStart)
	engine, _ := link.NewRuntime()
	handle, err := engine.StartGame(ctx, forge.StartGameRequest{GameID: "private-game", Variant: "Constructed", Players: make([]forge.PlayerConfig, 2)})
	if err != nil {
		t.Fatal(err)
	}
	for range 3 {
		if err := engine.SubmitAction(ctx, handle.SessionID, json.RawMessage(`{"pass":true}`)); err != nil {
			t.Fatal(err)
		}
	}
	engine.Invalidate()
	journal, err := engine.Checkpoint()
	if err != nil || len(journal.Actions) != 3 {
		t.Fatalf("confirmed journal unavailable after loss: %v", err)
	}
	other, ctx := newRelayFixture(t, checkpointStart)
	restored, _ := other.NewRuntime()
	if _, err := restored.RestoreGame(ctx, journal); err != nil {
		t.Fatal(err)
	}
	if err := restored.SubmitAction(ctx, handle.SessionID, json.RawMessage(`{"pass":true}`)); err != nil {
		t.Fatal(err)
	}
	next, err := restored.Checkpoint()
	if err != nil || len(next.Actions) != 4 {
		t.Fatal("restored game did not retain complete earlier history")
	}
	next.Actions[0].Digest = "changed"
	independent, _ := restored.Checkpoint()
	if independent.Actions[0].Digest == "changed" {
		t.Fatal("caller mutated retained journal")
	}
}

func TestCheckpointMismatchNeverPublishesOrKeepsReplacementEngine(t *testing.T) {
	original := NewExecutor("ROOM", checkpointStart, nil)
	defer original.Cancel("")
	req := Request{RoomID: "ROOM", EngineID: NewID(), ID: 1, Command: "start", Start: &forge.StartGameRequest{GameID: "game", Variant: "Constructed", Players: make([]forge.PlayerConfig, 2)}}
	first := original.Execute(t.Context(), req)
	record := &Runtime{}
	record.recordCheckpoint(req, first.Publication)
	journal, _ := record.Checkpoint()
	for _, mutation := range []struct {
		name string
		edit func(*Checkpoint)
	}{
		{"runtime", func(c *Checkpoint) { c.RuntimeID = "old" }},
		{"digest", func(c *Checkpoint) { c.InitialDigest = strings.Repeat("0", 64) }},
		{"malformed_digest", func(c *Checkpoint) { c.InitialDigest = strings.Repeat("z", 64) }},
		{"action", func(c *Checkpoint) {
			c.Actions = []ReplayAction{{Action: json.RawMessage(`{"pass":true}`), Digest: c.InitialDigest}}
		}},
	} {
		t.Run(mutation.name, func(t *testing.T) {
			candidate := journal
			mutation.edit(&candidate)
			e := NewExecutor("ROOM", checkpointStart, nil)
			defer e.Cancel("")
			response := e.Execute(t.Context(), Request{RoomID: "ROOM", EngineID: NewID(), ID: 1, Command: "restore", Checkpoint: &candidate})
			if response.Error == "" || response.Publication != nil {
				t.Fatal("unverified replay was published")
			}
			if _, alive := e.State(); alive {
				t.Fatal("failed replacement remained alive")
			}
		})
	}
	// Exhaustion is not truncation: never offer a partial history as recoverable.
	record.checkpointBytes = MaxCheckpointBytes
	record.recordCheckpoint(Request{Command: "action", Action: json.RawMessage(`{}`)}, first.Publication)
	if record.CanMigrate() || record.checkpoint != nil {
		t.Fatal("oversized journal remained available")
	}
	if _, err := canonicalJSON([]byte(`{} {}`)); err == nil {
		t.Fatal("accepted trailing document")
	}
}
