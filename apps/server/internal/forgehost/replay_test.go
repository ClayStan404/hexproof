// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package forgehost

import (
	"testing"

	"hexproof/server/internal/rulesengine/forge"
)

func TestVisualReplayDoesNotChangeMigrationHashes(t *testing.T) {
	executor := NewExecutor("ROOM", checkpointStart, nil)
	defer executor.Cancel("")
	result := executor.Execute(t.Context(), Request{RoomID: "ROOM", EngineID: NewID(), ID: 1, Command: "start",
		Start: &forge.StartGameRequest{GameID: "game", Variant: "Constructed", Players: make([]forge.PlayerConfig, 2)}})
	publication := result.Publication
	if publication == nil {
		t.Fatal(result.Error)
	}
	publication.Replay = &forge.ReplayBatch{Complete: true, LastSequence: 3,
		Frames: []forge.ReplayFrame{{Sequence: 3, ElapsedMS: 1200}}}
	first, err := publicationDigest(publication)
	if err != nil {
		t.Fatal(err)
	}
	peerHash := HashPublication(publication)
	publication.Replay.Frames[0].ElapsedMS = 90000
	publication.Replay.Complete = false
	second, err := publicationDigest(publication)
	if err != nil || first != second || peerHash != HashPublication(publication) {
		t.Fatal("observations changed position identity")
	}
	publication.Revision++
	changed, err := publicationDigest(publication)
	if err != nil || changed == first || HashPublication(publication) == peerHash {
		t.Fatal("actual game state excluded from position identity")
	}
}
