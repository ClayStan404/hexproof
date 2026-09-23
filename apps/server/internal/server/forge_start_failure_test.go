// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package server

import (
	"context"
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"hexproof/server/internal/forgehost"
	"hexproof/server/internal/protocol"
	"hexproof/server/internal/room"
	"hexproof/server/internal/rulesengine/forge"
)

func addStartFailureSpectator(t *testing.T, h *Handler, r *room.Room) *Session {
	t.Helper()
	s := &Session{ConnectionID: r.ID + "-observer", DisplayName: "Observer", Send: make(chan []byte, 64)}
	entry, err := h.hub.beginJoin(r.ID, "")
	if err != nil {
		t.Fatal(err)
	}
	_, _, err = h.hub.joinRoom(entry, s, true)
	entry.opMu.Unlock()
	if err != nil {
		t.Fatal(err)
	}
	s.setRoom(r)
	h.sessionsMu.Lock()
	h.sessions[s.ConnectionID] = s
	h.sessionsMu.Unlock()
	return s
}

func TestForgeInitialStartFailureNotifiesEveryMemberWithOnlyOwnedDetails(t *testing.T) {
	for _, mode := range []string{protocol.CardLoadBackground, protocol.CardLoadPreload} {
		t.Run(mode, func(t *testing.T) {
			h, dir := newSupervisedForgeHandler(t)
			r, players := newWaitingSupervisedRoom(t, h, "deck-failure", protocol.RulesModeForge)
			r.CardLoadMode = mode
			for i, p := range players {
				deck := *r.Seats[i].Deck
				deck.Mainboard = append([]protocol.DeckCard(nil), deck.Mainboard...)
				deck.Mainboard[0].Name = []string{"OwnerAlpha", "OwnerBeta"}[i]
				deck.Sideboard = []protocol.DeckCard{{Name: "SideBeta", Count: 1, SetCode: "M21", CollectorNumber: "272"}}
				if _, err := h.hub.SelectDeck(p.ConnectionID, deck, r); err != nil {
					t.Fatal(err)
				}
			}
			observer := addStartFailureSpectator(t, h, r)
			members := append(append([]*Session(nil), players...), observer)
			raw := []byte(`{"reason":"deck_rejected","issues":[{"playerIndex":0,"section":"mainboard","cardIndex":0,"code":"printing_unavailable"},{"playerIndex":1,"section":"sideboard","cardIndex":0,"code":"printing_unavailable"}]}`)
			if err := os.WriteFile(filepath.Join(dir, "deck-failure.json"), raw, 0600); err != nil {
				t.Fatal(err)
			}
			request, _ := protocol.NewEnvelope(protocol.TypePlayerReady, protocol.PlayerReady{Ready: true})
			for _, p := range players {
				request.ID = "last-start"
				if err := h.handlePlayerReady(p, request); err != nil {
					t.Fatal(err)
				}
			}
			if mode == protocol.CardLoadPreload {
				request, _ = protocol.NewEnvelope(protocol.TypeClientLoadComplete, protocol.ClientLoadComplete{LoadID: r.LoadID})
				request.ID = "last-start"
				for _, p := range players {
					if err := h.handleClientLoadComplete(p, request); err != nil {
						t.Fatal(err)
					}
				}
			}
			assertSupervisedPhase(t, h, r, protocol.RoomPhaseWaiting)
			for i, member := range members {
				var failure protocol.ErrorPayload
				found, waitingBeforeFailure := 0, false
				for len(member.Send) > 0 {
					var envelope protocol.Envelope
					_ = json.Unmarshal(<-member.Send, &envelope)
					if envelope.Type == protocol.TypeRoomSnapshot {
						var snap protocol.RoomSnapshot
						_ = envelope.DecodePayload(&snap)
						waitingBeforeFailure = snap.Phase == protocol.RoomPhaseWaiting
					}
					if envelope.Type != protocol.TypeError {
						continue
					}
					found++
					if !waitingBeforeFailure {
						t.Fatal("error preceded rollback snapshot")
					}
					if err := envelope.DecodePayload(&failure); err != nil {
						t.Fatal(err)
					}
					wantID := ""
					if i == 1 {
						wantID = request.ID
					}
					if envelope.ID != wantID {
						t.Fatal("failure correlation escaped triggering member")
					}
				}
				if found != 1 || failure.RulesStartFailure == nil || failure.RulesStartFailure.Reason != "deck_rejected" {
					t.Fatal("member did not receive exactly one useful start failure")
				}
				if strings.Contains(failure.Message, "Owner") || strings.Contains(failure.Message, "private") {
					t.Fatal("private data entered generic failure")
				}
				details := failure.RulesStartFailure.Issues
				if i == 2 {
					if len(details) != 0 {
						t.Fatal("spectator received registered card identity")
					}
				} else {
					want := []string{"OwnerAlpha", "SideBeta"}[i]
					if len(details) != 1 || details[0].CardName != want || details[0].Deck != "player" {
						t.Fatal("deck issue sent to wrong owner")
					}
				}
			}
			// Cleanup watchers must not replace the actionable failure afterward.
			time.Sleep(20 * time.Millisecond)
			for _, member := range members {
				if len(member.Send) != 0 {
					t.Fatal("late supervisor event replaced start failure")
				}
			}
			for _, seat := range r.Seats {
				if seat.Ready || seat.Deck == nil {
					t.Fatal("rollback did not preserve deck and clear readiness")
				}
			}
		})
	}
}

func TestForgeStartFailureAIIdentitiesGoOnlyToHost(t *testing.T) {
	h, _ := newSupervisedForgeHandler(t)
	r, players := newWaitingSupervisedRoom(t, h, "ai-failure", protocol.RulesModeForge)
	observer := addStartFailureSpectator(t, h, r)
	entry := h.hub.roomEntryFor(r.ID)
	entry.mu.Lock()
	r.Seats[1].Controller = protocol.SeatControllerForgeAI
	r.Seats[1].ConnectionID = ""
	entry.mu.Unlock()
	request := forge.StartGameRequest{Players: []forge.PlayerConfig{{Deck: []forge.CardIdentity{{Name: "Human private"}}}, {AI: true, Deck: []forge.CardIdentity{{Name: "AI private", SetCode: "M21", CollectorNumber: "272"}}}}}
	detail := forge.ParseStartFailure(json.RawMessage(`{"reason":"deck_rejected","issues":[{"playerIndex":1,"section":"mainboard","cardIndex":0,"code":"printing_unavailable"}]}`), request)
	h.sendForgeStartFailure(r, players[0], "ai-ready", &roomForgeStartFailure{cause: detail, seats: []int{0, 1}})
	for _, member := range []*Session{players[0], observer} {
		var env protocol.Envelope
		_ = json.Unmarshal(<-member.Send, &env)
		var payload protocol.ErrorPayload
		_ = env.DecodePayload(&payload)
		if member == players[0] {
			if len(payload.RulesStartFailure.Issues) != 1 || payload.RulesStartFailure.Issues[0].Deck != "ai" || payload.RulesStartFailure.Issues[0].CardName != "AI private" {
				t.Fatal("host lost AI deck details")
			}
		} else if len(payload.RulesStartFailure.Issues) != 0 {
			t.Fatal("AI card leaked beyond its configuring host")
		}
	}
}

func TestForgeStartFailureCategoriesDoNotExposeCauses(t *testing.T) {
	for _, test := range []struct {
		err    error
		reason string
	}{
		{errForgeCapacity, "capacity"}, {context.DeadlineExceeded, "runtime_timeout"},
		{forge.ErrStartRejected, "start_rejected"}, {errForgeRuntimeUnavailable, "runtime_unavailable"},
		{forgehost.ErrUnavailable, "runtime_unavailable"}, {forge.ErrClosed, "runtime_failed"},
		{errors.New("private card /path token=secret"), "runtime_failed"},
	} {
		if forgeStartFailureReason(test.err) != test.reason {
			t.Fatal("wrong failure category")
		}
		_, message := forgeStartFailure(test.err)
		if strings.Contains(message, "private") || strings.Contains(message, "secret") {
			t.Fatal("cause escaped fixed error")
		}
	}
}
