//go:build engineintegration

// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package forgehost

import (
	"context"
	"encoding/json"
	"os"
	"path/filepath"
	"testing"
	"time"

	"hexproof/server/internal/rulesengine/forge"
)

// This gate uses independent native processes, including their hidden library
// order and RNG digests. A transport-only fake cannot qualify migration.
func TestLiveCheckpointReplay(t *testing.T) {
	root, overlay := os.Getenv("HEXPROOF_REAL_FORGE_ROOT"), os.Getenv("HEXPROOF_TEST_FORGE_OVERLAY")
	if root == "" || overlay == "" {
		t.Fatal("HEXPROOF_REAL_FORGE_ROOT and HEXPROOF_TEST_FORGE_OVERLAY are required")
	}
	config := forge.JavaOverlayProcessConfig(os.Getenv("HEXPROOF_FORGE_JAVA"), filepath.Join(root, "forge-harness.jar"), filepath.Join(root, "forge-gui"), overlay)
	config.Args = append([]string{"-Xmx768m", "-XX:+UseSerialGC", "-XX:ActiveProcessorCount=2", "-Djava.awt.headless=true"}, config.Args...)
	start := func(ctx context.Context) (forge.Runtime, error) { return forge.Start(ctx, config) }
	ctx, cancel := context.WithTimeout(t.Context(), 3*time.Minute)
	defer cancel()
	original := NewExecutor("ROOM", start, nil)
	defer original.Cancel("")
	engineID := NewID()
	deck := make([]forge.CardIdentity, 60)
	for i := range deck {
		deck[i].Name = "Forest"
		if i >= 28 {
			deck[i].Name = "Grizzly Bears"
		}
	}
	request := forge.StartGameRequest{GameID: "replay-native", Variant: "Constructed", StartingLife: 20, Seed: 424242,
		Players: []forge.PlayerConfig{{Name: "Host", Deck: deck}, {Name: "Opponent", Deck: deck}}}
	response := original.Execute(ctx, Request{RoomID: "ROOM", EngineID: engineID, ID: 1, Command: "start", Start: &request})
	if response.Error != "" {
		t.Fatal(response.Error)
	}
	publications := []*Publication{response.Publication}
	record := &Runtime{}
	record.recordCheckpoint(Request{Command: "start", Start: &request}, response.Publication)
	if record.checkpoint == nil {
		t.Fatal("initial native position has no integrity digest")
	}
	for step := range 80 {
		prompt, err := forge.NormalizePrompt(response.Publication.Prompt)
		if err != nil {
			t.Fatal(err)
		}
		answer := forge.PromptResponse{ResponseID: "$submit"}
		switch prompt.Kind {
		case "mulligan":
			answer.ResponseID = "$keep"
		case "chooseAction":
			answer.ResponseID = "$pass"
			for _, option := range prompt.Options {
				if option.Kind == "playLand" {
					answer.ResponseID = option.ResponseID
					break
				}
			}
		case "chooseBoolean", "chooseFromSelection":
			answer.ChoiceIDs = []string{prompt.Choices[0].ResponseID}
		case "chooseCards", "mulliganPutBack":
			for _, card := range prompt.Cards[:prompt.CardMinimum] {
				answer.CardIDs = append(answer.CardIDs, card.ID)
			}
		case "chooseAttackers", "chooseBlockers":
		case "acknowledge", "revealCards", "diceRolled":
			answer.ResponseID = "$ack"
		default:
			t.Fatalf("replay fixture needs policy for %s", prompt.Kind)
		}
		action, err := forge.BuildPromptResponse(response.Publication.Prompt, prompt.PlayerIndex, prompt.PromptID, answer)
		if err != nil {
			t.Fatal(err)
		}
		op := Request{RoomID: "ROOM", EngineID: engineID, ID: uint64(step + 2), Command: "action", Action: action}
		response = original.Execute(ctx, op)
		if response.Error != "" {
			t.Fatalf("step %d: %s", step, response.Error)
		}
		publications = append(publications, response.Publication)
		record.recordCheckpoint(op, response.Publication)
		if record.checkpoint == nil {
			t.Fatalf("native digest lost at step %d", step)
		}
	}
	checkpoint, err := record.Checkpoint()
	if err != nil {
		t.Fatal(err)
	}
	if output := os.Getenv("HEXPROOF_CHECKPOINT_EXPORT"); output != "" {
		writeCheckpointFixture(t, output, checkpointExchangeArtifact{checkpoint, publications})
	}
	original.Cancel("") // Recovery must work after the original process is gone.
	successor := NewExecutor("ROOM", start, nil)
	defer successor.Cancel("")
	started := time.Now()
	restored := successor.Execute(ctx, Request{RoomID: "ROOM", EngineID: NewID(), ID: 1, Command: "restore", Checkpoint: &checkpoint})
	if restored.Error != "" {
		t.Fatalf("native replay: %s", restored.Error)
	}
	// Visual observations carry wall-clock timing; the rest of the position,
	// including private integrity hashes and prompts, must match byte-for-byte.
	wantPosition, gotPosition := *response.Publication, *restored.Publication
	wantPosition.Replay, gotPosition.Replay = nil, nil
	want, _ := json.Marshal(wantPosition)
	got, _ := json.Marshal(gotPosition)
	if string(want) != string(got) {
		t.Fatal("restored publication differs")
	}
	t.Logf("replayed %d accepted decisions in %s", len(checkpoint.Actions), time.Since(started))
}
