// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package server

import (
	"context"
	"encoding/json"
	"fmt"
	"hexproof/server/internal/protocol"
	"hexproof/server/internal/rulesengine/forge"
	"os"
	"strings"
	"testing"
)

func TestForgeAIStartRequestAndTargets(t *testing.T) {
	config := DefaultConfig()
	handler, err := NewHandlerWithConfig(config)
	if err != nil {
		t.Fatal(err)
	}
	defer handler.Close()
	host := &Session{ConnectionID: "host", DisplayName: "Human"}
	r, snapshot, _, entry, err := handler.hub.createRoom("AI", protocol.FormatModern, protocol.DeckFormatCustom, protocol.MatchBO1, protocol.CardLoadBackground, protocol.RulesModeForge, "server", 2, true, false, "", "", "", "", host, protocol.AIDifficultyHard)
	if err != nil {
		t.Fatal(err)
	}
	defer entry.opMu.Unlock()
	if snapshot.AIDifficulty != protocol.AIDifficultyHard || snapshot.Seats[1].Controller != protocol.SeatControllerForgeAI {
		t.Fatal("AI seat missing from first publication")
	}
	deck := modernTestDeck("Private AI deck")
	if _, err := r.ConfigureAI("host", protocol.RoomAIConfigure{Difficulty: protocol.AIDifficultyHard, Deck: &deck}); err != nil {
		t.Fatal(err)
	}
	if _, err := r.SelectDeck("host", deck); err != nil {
		t.Fatal(err)
	}
	if _, err := r.SetReady("host", true); err != nil {
		t.Fatal(err)
	}
	players, err := r.RulesStartPlayers()
	if err != nil {
		t.Fatal(err)
	}
	request, _, err := forgeStartRequest(r, players)
	if err != nil || !request.Players[1].AI || request.Players[0].AI || request.Players[1].AIDifficulty != protocol.AIDifficultyHard {
		t.Fatalf("controller lost: %+v %v", request, err)
	}
	targets, err := handler.hub.RulesPlayerTargets(r)
	if err != nil || len(targets) != 1 || targets["host"] != 0 {
		t.Fatalf("AI acquired prompt target: %v %v", targets, err)
	}
	if _, err := handler.hub.RulesActorSeat(r, ""); err == nil {
		t.Fatal("anonymous actor acquired AI")
	}
	metadata, metadataErr := handler.hub.GameProjections(r)
	if metadataErr != nil || len(metadata) != 1 {
		t.Fatalf("AI acquired metadata target: %v", metadataErr)
	}
	projections, _, err := handler.hub.RulesProjectionTargets(r)
	if err != nil || len(projections) != 1 {
		t.Fatal("AI acquired projection audience")
	}
}

func TestForgeAIRejectsLegacyRuntimeAtRoomCreation(t *testing.T) {
	if os.Getenv("HEXPROOF_FORGE_AI_LEGACY_HELPER") == "1" {
		runForgeProbeHelper(t)
		return
	}
	config := DefaultConfig()
	config.ForgeRuntime = &forge.ProcessConfig{Command: os.Args[0], Args: []string{"-test.run=^TestForgeAIRejectsLegacyRuntimeAtRoomCreation$"}, Env: []string{"HEXPROOF_FORGE_AI_LEGACY_HELPER=1"}}
	srv, handler := newConfiguredTestServer(t, config)
	defer handler.Close()
	host := dial(t, srv)
	defer host.close()
	welcome := host.hello("Human")
	var capabilities protocol.SessionWelcome
	if err := welcome.DecodePayload(&capabilities); err != nil {
		t.Fatal(err)
	}
	if !capabilities.ForgeRulesAvailable || capabilities.ForgeAIAvailable {
		t.Fatal("legacy runtime advertised AI")
	}
	request, _ := protocol.NewEnvelope(protocol.TypeRoomCreate, protocol.RoomCreate{Name: "AI", Format: protocol.FormatModern, DeckFormat: protocol.DeckFormatCustom, MatchMode: protocol.MatchBO1, RulesMode: protocol.RulesModeForge, AIDifficulty: protocol.AIDifficultyNormal})
	request.ID = "ai-create"
	host.send(request)
	response := host.recvType(protocol.TypeError)
	var failure protocol.ErrorPayload
	if err := response.DecodePayload(&failure); err != nil || failure.Code != protocol.ErrRulesUnavailable {
		t.Fatalf("legacy runtime accepted AI room: %s", response.Payload)
	}
}

func TestForgeAIConfigureUsesHostAuthorityAndPrivateReply(t *testing.T) {
	config := DefaultConfig()
	config.AllowPlayerHosting = true
	srv, handler := newConfiguredTestServer(t, config)
	defer handler.Close()
	host := dial(t, srv)
	defer host.close()
	host.hello("Human")
	create, _ := protocol.NewEnvelope(protocol.TypeRoomCreate, protocol.RoomCreate{Name: "AI", Format: protocol.FormatModern, DeckFormat: protocol.DeckFormatCustom, MatchMode: protocol.MatchBO1, RulesMode: protocol.RulesModeForge, HostingMode: "player", AIDifficulty: "normal", AllowSpectators: true})
	create.ID = "create"
	host.send(create)
	created := host.recvType(protocol.TypeRoomCreated)
	var info protocol.RoomCreated
	if err := created.DecodePayload(&info); err != nil {
		t.Fatal(err)
	}
	host.recvType(protocol.TypeRoomSnapshot)
	observer := dial(t, srv)
	defer observer.close()
	observer.hello("Observer")
	join, _ := protocol.NewEnvelope(protocol.TypeRoomJoin, protocol.RoomJoin{RoomID: info.RoomID, AsSpectator: true, AcceptPlayerHost: true})
	join.ID = "watch"
	observer.send(join)
	observer.recvType(protocol.TypeRoomJoined)
	observer.recvType(protocol.TypeRoomSnapshot)
	host.recvType(protocol.TypeRoomSnapshot)
	deck := modernTestDeck("Secret AI deck")
	command, _ := protocol.NewEnvelope(protocol.TypeRoomAIConfigure, protocol.RoomAIConfigure{Difficulty: "easy", Deck: &deck})
	command.ID = "configure"
	observer.send(command)
	rejected := observer.recvType(protocol.TypeError)
	var failure protocol.ErrorPayload
	_ = rejected.DecodePayload(&failure)
	if failure.Code != protocol.ErrNotHost {
		t.Fatal("observer configured AI")
	}
	host.send(command)
	reply := host.recvType(protocol.TypeRoomSnapshot)
	if reply.ID != "configure" || strings.Contains(string(reply.Payload), "Secret AI") {
		t.Fatal("configuration reply uncorrelated or private")
	}
	broadcast := observer.recvType(protocol.TypeRoomSnapshot)
	var snapshot protocol.RoomSnapshot
	if err := broadcast.DecodePayload(&snapshot); err != nil || snapshot.AIDifficulty != "easy" || !snapshot.Seats[1].Ready || !snapshot.Seats[1].DeckSelected {
		t.Fatalf("invalid AI update: %s", broadcast.Payload)
	}
	if strings.Contains(string(broadcast.Payload), "Secret AI") {
		t.Fatal("AI deck leaked to spectator")
	}
}

// The adapter validates card-name restrictions after the public response has
// passed structural validation. A rejected name must leave the AI game usable.
func TestForgeAIRejectedCardNamePreservesDecisionUnlessNativeFailed(t *testing.T) {
	for _, fatal := range []bool{false, true} {
		t.Run(fmt.Sprintf("fatal=%t", fatal), func(t *testing.T) {
			handler, err := NewHandlerWithConfig(DefaultConfig())
			if err != nil {
				t.Fatal(err)
			}
			defer handler.Close()
			host := &Session{ConnectionID: "human", DisplayName: "Human", Send: make(chan []byte, 16)}
			r, _, _, entry, err := handler.hub.createRoom("AI", protocol.FormatModern, protocol.DeckFormatCustom, protocol.MatchBO1, protocol.CardLoadBackground, protocol.RulesModeForge, "server", 2, false, false, "", "", "", "", host, "normal")
			if err != nil {
				t.Fatal(err)
			}
			r.Phase = protocol.RoomPhaseStarted
			entry.opMu.Unlock()
			runtime := &aiRejectedActionRuntime{healthy: true, fatal: fatal}
			game := forgeRoomGame{client: runtime, sessionID: "session", gameID: "game", nativeAI: true, seatToPlayer: map[int]int{0: 0, 1: 1}, playerToSeat: map[int]int{0: 0, 1: 1}, promptState: &forgePromptState{}}
			promptID, err := handler.publicForgePromptID(game, 1)
			if err != nil {
				t.Fatal(err)
			}
			handler.forgeMu.Lock()
			handler.forgeGames[r.ID] = game
			handler.forgeMu.Unlock()
			defer func() { handler.forgeMu.Lock(); delete(handler.forgeGames, r.ID); handler.forgeMu.Unlock() }()
			env, _ := protocol.NewEnvelope(protocol.TypeRulesRespond, protocol.RulesRespond{PromptID: promptID, ResponseID: "$submit", Name: "Not a legal card name"})
			env.ID = "bad-name"
			if err := handler.handleRulesRespond(host, env); err != nil {
				t.Fatal(err)
			}
			if runtime.submitted != 1 {
				t.Fatal("fixture did not reach native validation")
			}
			if fatal {
				if r.Phase != protocol.RoomPhaseWaiting {
					t.Fatal("fatal native failure retained live game")
				}
			} else {
				if r.Phase != protocol.RoomPhaseStarted || !runtime.Healthy() || !game.promptState.matches(promptID, 1) {
					t.Fatal("recoverable card-name rejection aborted AI game")
				}
				if _, ok := handler.forgeGame(r.ID); !ok {
					t.Fatal("recoverable rejection removed runtime")
				}
			}
		})
	}
}

type aiRejectedActionRuntime struct {
	forge.Runtime
	healthy   bool
	fatal     bool
	submitted int
}

func (r *aiRejectedActionRuntime) Healthy() bool { return r.healthy }
func (r *aiRejectedActionRuntime) Invalidate()   { r.healthy = false }
func (r *aiRejectedActionRuntime) Prompt(context.Context, string, int) (json.RawMessage, error) {
	return json.RawMessage(`{"promptId":1,"decidingPlayerId":"player-0","input":{"type":"chooseCardName","message":"Choose a nonland card name","canCancel":true}}`), nil
}
func (r *aiRejectedActionRuntime) SubmitAction(context.Context, string, json.RawMessage) error {
	r.submitted++
	if r.fatal {
		r.healthy = false
	}
	return forge.ErrRuntime
}
