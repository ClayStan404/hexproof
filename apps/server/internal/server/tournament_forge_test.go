// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package server

import (
	"reflect"
	"testing"
	"time"

	"hexproof/server/internal/protocol"
	"hexproof/server/internal/rulesengine/forge"
	"hexproof/server/internal/tournament"
)

func TestForgeTournamentCreationRequiresAvailableRuntime(t *testing.T) {
	for _, available := range []bool{false, true} {
		h := retentionHandler(t, DefaultConfig())
		// No game is started here; advertise a configured runtime for admission.
		if available {
			h.forgeRuntime = &forge.ProcessConfig{}
		}
		owner := retentionSession(h, "owner")
		env, _ := protocol.NewEnvelope(protocol.TypeTournamentCreate, protocol.TournamentCreate{
			Name: "Forge Swiss", Format: "Modern", MatchMode: protocol.MatchBO3,
			RulesMode: protocol.RulesModeForge, RoundMinutes: 50, MaxPlayers: 4,
		})
		if err := h.handleTournamentCreate(owner, env); err != nil {
			t.Fatal(err)
		}
		if !available {
			if payload := readWireError(t, owner); payload.Code != protocol.ErrRulesUnavailable {
				t.Fatalf("unavailable: %+v", payload)
			}
			if len(h.tournaments.list()) != 0 || owner.Tournament().TournamentID != "" {
				t.Fatal("unavailable Forge published or bound an event")
			}
			continue
		}
		listed := h.tournaments.list()
		if len(listed) != 1 || listed[0].RulesMode != protocol.RulesModeForge {
			t.Fatalf("rules missing from discovery: %+v", listed)
		}
		entry := h.tournaments.entry(listed[0].TournamentID)
		entry.mu.Lock()
		snapshot := tournamentSnapshot(entry.event, tournamentBinding{Role: tournament.RoleViewer})
		entry.mu.Unlock()
		if snapshot.RulesMode != protocol.RulesModeForge {
			t.Fatal("event projection lost rules mode")
		}
	}
}

func TestForgeLimitedPairingPreservesModeLockedPoolAndNativeVariant(t *testing.T) {
	for _, eventType := range []string{protocol.LimitedEventSetSealed,
		protocol.LimitedEventSetDraft, protocol.LimitedEventCubeDraft} {
		t.Run(eventType, func(t *testing.T) {
			h := retentionHandler(t, DefaultConfig())
			h.forgeRuntime = &forge.ProcessConfig{}
			host, guest := retentionSession(h, "host"), retentionSession(h, "guest")
			event, err := tournament.New("LIMITED", tournament.Config{
				Name: "Pairing fixture", Format: "Modern", MatchMode: protocol.MatchBO3,
				RulesMode: protocol.RulesModeForge,
			}, "Judge", "judge", tournament.CredentialHash("judge-token"), time.Now())
			if err != nil {
				t.Fatal(err)
			}
			deck := protocol.DeckSelect{Name: "Locked pool", Format: protocol.FormatModern,
				DeckFormat: protocol.DeckFormatLimited,
				Mainboard: []protocol.DeckCard{{Name: "Forest", Count: 17},
					{Name: "Grizzly Bears", SetCode: "M10", CollectorNumber: "189", Count: 23}},
				Sideboard: []protocol.DeckCard{{Name: "Giant Growth", SetCode: "M10", CollectorNumber: "184", Count: 44}},
			}
			ids := []string{}
			for _, sess := range []*Session{host, guest} {
				p, registerErr := event.Register(sess.DisplayName, sess.ConnectionID,
					tournament.CredentialHash(sess.ConnectionID), time.Now())
				if registerErr != nil {
					t.Fatal(registerErr)
				}
				p.Deck = &deck
				ids = append(ids, p.ID)
				sess.setTournament(tournamentBinding{TournamentID: event.ID,
					Role: tournament.RoleParticipant, ParticipantID: p.ID})
			}
			// Distribution/containment has its own domain tests. Enter the actual
			// pairing handler with completed, private Limited submissions.
			event.EventType, event.Format = eventType, "Limited"
			event.Status, event.Stage = tournament.StatusRunning, protocol.LimitedStageCompetition
			pair := tournament.Pairing{ID: "pair", PlayerAID: ids[0], PlayerBID: ids[1]}
			if eventType == protocol.LimitedEventCubeDraft {
				event.Coordinator = protocol.LimitedCoordinatorCasual
				event.CasualPairings = []tournament.Pairing{pair}
			} else {
				event.Rounds = []tournament.Round{{Number: 1, Pairings: []tournament.Pairing{pair}}}
			}
			if _, err := h.tournaments.create(event); err != nil {
				t.Fatal(err)
			}
			open, _ := protocol.NewEnvelope(protocol.TypeTournamentOpenMatch,
				protocol.TournamentPairingCommand{PairingID: pair.ID})
			h.forgeMu.Lock()
			h.forgeRetryAfter = time.Now().Add(time.Minute)
			h.forgeMu.Unlock()
			if err := h.handleTournamentOpenMatch(host, open); err != nil {
				t.Fatal(err)
			}
			if payload := readWireError(t, host); payload.Code != protocol.ErrRulesUnavailable || host.Room() != nil {
				t.Fatalf("unavailable Forge opened or downgraded a pairing: %+v", payload)
			}
			h.forgeMu.Lock()
			h.forgeRetryAfter = time.Time{}
			h.forgeMu.Unlock()
			for _, sess := range []*Session{host, guest} {
				if err := h.handleTournamentOpenMatch(sess, open); err != nil {
					t.Fatal(err)
				}
				if sess.Room() == nil {
					t.Fatalf("no pairing room: %+v", receiveEventEnvelope(t, sess))
				}
				// A launch backoff must not prevent the other participant from
				// entering the already-created table or resuming a live game.
				h.forgeMu.Lock()
				h.forgeRetryAfter = time.Now().Add(time.Minute)
				h.forgeMu.Unlock()
			}
			h.forgeMu.Lock()
			h.forgeRetryAfter = time.Time{}
			h.forgeMu.Unlock()
			r := host.Room()
			if r != guest.Room() || r.RulesMode != protocol.RulesModeForge || r.HostingMode != "server" ||
				r.DeckFormat != protocol.DeckFormatLimited || !r.LimitedDeckLocked {
				t.Fatal("pairing lost its rules mode, server hosting or Limited lock")
			}
			var created protocol.RoomCreated
			for len(host.Send) > 0 {
				env := receiveEventEnvelope(t, host)
				if env.Type == protocol.TypeRoomCreated {
					if err := env.DecodePayload(&created); err != nil {
						t.Fatal(err)
					}
				}
			}
			if created.Settings.RulesMode != protocol.RulesModeForge || created.Settings.HostingMode != "server" {
				t.Fatal("room.created omitted rules or hosting mode")
			}
			operation, err := h.hub.lockRoomOperation(r.ID)
			if err != nil {
				t.Fatal(err)
			}
			operation.mu.Lock()
			for _, sess := range []*Session{host, guest} {
				if _, err := r.SetReady(sess.ConnectionID, true); err != nil {
					t.Fatal(err)
				}
			}
			players, err := r.RulesStartPlayers()
			operation.mu.Unlock()
			operation.opMu.Unlock()
			if err != nil {
				t.Fatal(err)
			}
			request, seats, err := forgeStartRequest(r, players)
			if err != nil || request.Variant != "Limited" || request.StartingLife != 20 ||
				!reflect.DeepEqual(seats, []int{0, 1}) || len(request.Players[0].Deck) != 40 ||
				len(request.Players[0].Sideboard) != 44 || request.Players[0].Sideboard[43].SetCode != "M10" {
				t.Fatalf("Limited native request: %+v %v", request, err)
			}
		})
	}
}
