// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package server

import (
	"fmt"
	"reflect"
	"strings"
	"testing"
	"time"

	"hexproof/server/internal/protocol"
	"hexproof/server/internal/tournament"
)

func TestTournamentAutomaticDeckLockReachesCreatorJoinerAndSpectator(t *testing.T) {
	for _, round := range []int{1, 2, 3} {
		t.Run(fmt.Sprintf("round-%d", round), func(t *testing.T) {
			h := retentionHandler(t, DefaultConfig())
			creator := retentionSession(h, "creator")
			joiner := retentionSession(h, "joiner")
			watcher := retentionSession(h, "watcher")
			event, err := tournament.New("DECKLOCK", tournament.Config{
				Name: "Constructed deck lock", Format: "Modern", MatchMode: protocol.MatchBO1,
				RulesMode: protocol.RulesModeManual, RoundMinutes: 50, MaxPlayers: 4,
			}, "Judge", "judge", tournament.CredentialHash("judge-token"), time.Now())
			if err != nil {
				t.Fatal(err)
			}
			decks := []protocol.DeckSelect{
				{Name: "Private creator deck", Format: protocol.FormatModern, DeckFormat: protocol.DeckFormatModern,
					Mainboard: []protocol.DeckCard{{Name: "Forest", Count: 60, SetCode: "M21", CollectorNumber: "273"}},
					Sideboard: []protocol.DeckCard{{Name: "Negate", Count: 2, SetCode: "M21", CollectorNumber: "59"}}},
				{Name: "Private joiner deck", Format: protocol.FormatModern, DeckFormat: protocol.DeckFormatModern,
					Mainboard: []protocol.DeckCard{{Name: "Island", Count: 60, SetCode: "M21", CollectorNumber: "265"}}},
			}
			ids := make([]string, 0, 2)
			for index, sess := range []*Session{creator, joiner} {
				participant, registerErr := event.Register(sess.DisplayName, sess.ConnectionID,
					tournament.CredentialHash(sess.ConnectionID), time.Now())
				if registerErr != nil {
					t.Fatal(registerErr)
				}
				// Enter the production pairing handler with the deck recorded in
				// round one; the current room must apply and project its own lock.
				participant.Deck = &decks[index]
				ids = append(ids, participant.ID)
				sess.setTournament(tournamentBinding{TournamentID: event.ID,
					Role: tournament.RoleParticipant, ParticipantID: participant.ID})
			}
			event.Status, event.Stage = tournament.StatusRunning, protocol.LimitedStageCompetition
			pair := tournament.Pairing{ID: "pair", PlayerAID: ids[0], PlayerBID: ids[1]}
			event.Rounds = []tournament.Round{{Number: round, Pairings: []tournament.Pairing{pair}}}
			if _, err := h.tournaments.create(event); err != nil {
				t.Fatal(err)
			}
			open, _ := protocol.NewEnvelope(protocol.TypeTournamentOpenMatch,
				protocol.TournamentPairingCommand{PairingID: pair.ID})
			if err := h.handleTournamentOpenMatch(creator, open); err != nil {
				t.Fatal(err)
			}
			if creator.Room() == nil {
				t.Fatal("creator did not enter the pairing room")
			}
			locked := round >= 2
			assertTournamentDeckRoomWire(t, creator, []int{0}, locked)

			watch, _ := protocol.NewEnvelope(protocol.TypeRoomJoin,
				protocol.RoomJoin{RoomID: creator.Room().ID, AsSpectator: true})
			if err := h.handleRoomJoin(watcher, watch); err != nil {
				t.Fatal(err)
			}
			if watcher.Room() != creator.Room() {
				t.Fatal("spectator did not enter the same pairing room")
			}
			assertTournamentDeckRoomWire(t, creator, []int{0}, locked)
			assertTournamentDeckRoomWire(t, watcher, []int{0}, locked)

			if err := h.handleTournamentOpenMatch(joiner, open); err != nil {
				t.Fatal(err)
			}
			if joiner.Room() != creator.Room() {
				t.Fatal("joiner did not enter the same pairing room")
			}
			for _, sess := range []*Session{creator, joiner, watcher} {
				assertTournamentDeckRoomWire(t, sess, []int{0, 1}, locked)
			}
			if !locked {
				return
			}
			operation, err := h.hub.lockRoomOperation(creator.Room().ID)
			if err != nil {
				t.Fatal(err)
			}
			operation.mu.Lock()
			defer operation.mu.Unlock()
			defer operation.opMu.Unlock()
			for index, sess := range []*Session{creator, joiner} {
				seat := operation.room.FindSeatByConnection(sess.ConnectionID)
				expected := decks[index]
				// SelectDeck canonicalizes an absent Modern commander list to
				// an empty slice; all names, printings and quantities stay exact.
				expected.Commanders = []string{}
				if seat != index || !reflect.DeepEqual(operation.room.Seats[seat].RegisteredDeck, &expected) ||
					!reflect.DeepEqual(operation.room.Seats[seat].Deck, &expected) {
					t.Errorf("%s automatic deck differs from its exact first-round registration", sess.ConnectionID)
				}
				changed := decks[index]
				changed.Name = "Different tournament deck"
				if _, selectErr := operation.room.SelectDeck(sess.ConnectionID, changed); selectErr == nil ||
					selectErr.Error() != protocol.ErrTournamentForbidden {
					t.Errorf("%s locked deck change returned %v", sess.ConnectionID, selectErr)
				}
			}
		})
	}
}

// Inspect the serialized envelopes actually queued for each member. Looking
// only at Room.Seats or a freshly requested Snapshot would miss stale broadcasts.
func assertTournamentDeckRoomWire(t *testing.T, sess *Session, occupied []int, locked bool) {
	t.Helper()
	count := 0
	for len(sess.Send) > 0 {
		env := receiveEventEnvelope(t, sess)
		if env.Type == protocol.TypeError {
			t.Fatalf("%s received error: %s", sess.ConnectionID, env.Payload)
		}
		if env.Type == protocol.TypeTournamentSnapshot {
			var snapshot protocol.TournamentSnapshot
			if err := env.DecodePayload(&snapshot); err != nil {
				t.Fatal(err)
			}
			for _, participant := range snapshot.Participants {
				if participant.Deck != nil {
					t.Errorf("running event exposed a registered deck to %s", sess.ConnectionID)
				}
			}
		}
		if env.Type != protocol.TypeRoomSnapshot {
			continue
		}
		count++
		var snapshot protocol.RoomSnapshot
		if err := env.DecodePayload(&snapshot); err != nil {
			t.Fatal(err)
		}
		if env.SeqPtr == nil || *env.SeqPtr == 0 || snapshot.SpectatorsSeeHands {
			t.Errorf("%s room snapshot lost sequencing or spectator privacy", sess.ConnectionID)
		}
		for _, seat := range occupied {
			if seat >= len(snapshot.Seats) || !snapshot.Seats[seat].Occupied {
				t.Fatalf("%s snapshot omitted occupied seat %d", sess.ConnectionID, seat)
			}
			value := snapshot.Seats[seat]
			if value.DeckSelected != locked || value.DeckLocked != locked {
				t.Errorf("%s wire seat %d: deckSelected=%v deckLocked=%v, want both %v",
					sess.ConnectionID, seat, value.DeckSelected, value.DeckLocked, locked)
			}
		}
		for _, hidden := range []string{"Private creator deck", "Private joiner deck", "Forest", "Island", "Negate", "mainboard", "sideboard"} {
			if snapshot.OwnDeckName == hidden {
				continue
			}
			if strings.Contains(string(env.Payload), hidden) {
				t.Errorf("%s room snapshot exposed private deck data %q", sess.ConnectionID, hidden)
			}
		}
		wantName := ""
		if locked && sess.ConnectionID == "creator" {
			wantName = "Private creator deck"
		} else if locked && sess.ConnectionID == "joiner" {
			wantName = "Private joiner deck"
		}
		if snapshot.OwnDeckName != wantName {
			t.Errorf("%s own deck name = %q, want %q", sess.ConnectionID, snapshot.OwnDeckName, wantName)
		}
	}
	if count != 1 {
		t.Errorf("%s received %d room snapshots for the operation, want one complete projection", sess.ConnectionID, count)
	}
}
