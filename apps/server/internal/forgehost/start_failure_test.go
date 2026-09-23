// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package forgehost

import (
	"context"
	"encoding/json"
	"errors"
	"strings"
	"testing"

	"hexproof/server/internal/rulesengine/forge"
)

type rejectedDeckRuntime struct{ *fixtureRuntime }

func (r *rejectedDeckRuntime) StartGame(_ context.Context, request forge.StartGameRequest) (forge.SessionHandle, error) {
	return forge.SessionHandle{}, forge.ParseStartFailure(json.RawMessage(`{"reason":"deck_rejected","issues":[{"playerIndex":1,"section":"sideboard","cardIndex":0,"code":"printing_unavailable"}]}`), request)
}

func TestPrivateRelayRetainsVerifiedStartFailureWithoutCardIdentity(t *testing.T) {
	request := forge.StartGameRequest{GameID: "failure", Variant: "Constructed", Players: []forge.PlayerConfig{
		{Name: "First", Deck: []forge.CardIdentity{{Name: "Forest"}}},
		{Name: "Second", Deck: []forge.CardIdentity{{Name: "Forest"}}, Sideboard: []forge.CardIdentity{{Name: "Private sideboard card", SetCode: "ABC", CollectorNumber: "123"}}},
	}}
	start := func(context.Context) (forge.Runtime, error) {
		return &rejectedDeckRuntime{&fixtureRuntime{done: make(chan struct{})}}, nil
	}
	executor := NewExecutor("ROOM", start, nil)
	defer executor.Cancel("")
	response := executor.Execute(t.Context(), Request{RoomID: "ROOM", EngineID: NewID(), ID: 1, Command: "start", Start: &request})
	raw, _ := json.Marshal(response)
	if response.Error == "" || response.StartFailure == nil || strings.Contains(string(raw), "Private") || response.Publication != nil {
		t.Fatal("helper failure leaked identity or lost detail")
	}
	link, ctx := newRelayFixture(t, start)
	runtime, err := link.NewRuntime()
	if err != nil {
		t.Fatal(err)
	}
	defer runtime.Close()
	_, err = runtime.StartGame(ctx, request)
	var detail *forge.StartError
	if !errors.As(err, &detail) || len(detail.Issues()) != 1 || detail.Issues()[0].Card != request.Players[1].Sideboard[0] {
		t.Fatal("private relay lost validated owner details")
	}
	if strings.Contains(err.Error(), "Private") {
		t.Fatal("private details entered error text")
	}
}

func TestPrivateRelayPreservesSafeRuntimeTimeout(t *testing.T) {
	link, ctx := newRelayFixture(t, func(context.Context) (forge.Runtime, error) { return nil, context.DeadlineExceeded })
	runtime, err := link.NewRuntime()
	if err != nil {
		t.Fatal(err)
	}
	defer runtime.Close()
	_, err = runtime.StartGame(ctx, forge.StartGameRequest{GameID: "timeout", Variant: "Constructed", Players: make([]forge.PlayerConfig, 2)})
	var detail *forge.StartError
	if !errors.As(err, &detail) || detail.Reason() != "runtime_timeout" || len(detail.Issues()) != 0 {
		t.Fatal("private helper timeout became a generic engine error")
	}
}
