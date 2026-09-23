// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package forgehost

import (
	"hexproof/server/internal/rulesengine/forge"
	"testing"
)

func TestHostedAIStartHasNoMigrationCheckpoint(t *testing.T) {
	link, ctx := newRelayFixture(t, checkpointStart)
	engine, _ := link.NewRuntime()
	request := forge.StartGameRequest{GameID: "ai", Variant: "Constructed", Players: []forge.PlayerConfig{{Name: "Human"}, {Name: "AI", AI: true, AIDifficulty: "normal"}}}
	if _, err := engine.StartGame(ctx, request); err != nil {
		t.Fatal(err)
	}
	if _, err := engine.Checkpoint(); err == nil {
		t.Fatal("AI thread replay advertised as deterministic")
	}
}

func TestHostedAIRejectsUnsupportedControllerLayouts(t *testing.T) {
	for _, request := range []forge.StartGameRequest{
		{GameID: "ai", Variant: "Commander", Players: []forge.PlayerConfig{{}, {AI: true, AIDifficulty: "normal"}}},
		{GameID: "ai", Variant: "Constructed", Players: []forge.PlayerConfig{{AI: true, AIDifficulty: "normal"}, {}}},
		{GameID: "ai", Variant: "Constructed", Players: []forge.PlayerConfig{{AI: true, AIDifficulty: "normal"}, {AI: true, AIDifficulty: "normal"}}},
	} {
		executor := NewExecutor("ROOM", checkpointStart, nil)
		response := executor.Execute(t.Context(), Request{RoomID: "ROOM", EngineID: NewID(), ID: 1, Command: "start", Start: &request})
		if response.Error != "invalid" {
			t.Fatalf("unsupported hosted AI scope accepted: %+v", response)
		}
	}
}
