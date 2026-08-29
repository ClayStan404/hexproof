// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package server

import (
	"testing"
	"time"

	"hexproof/server/internal/protocol"
	"hexproof/server/internal/tournament"
)

func TestTournamentDecklistIsPrivateUntilCompletion(t *testing.T) {
	now := time.Date(2026, 8, 8, 12, 0, 0, 0, time.UTC)
	event, err := tournament.New("ABC12345", tournament.Config{
		Name: "Saturday Swiss", Format: "Pioneer", MatchMode: protocol.MatchBO3,
		RoundMinutes: 50, MaxPlayers: 32,
	}, "Judge", "organizer", tournament.CredentialHash("organizer-token"), now)
	if err != nil {
		t.Fatalf("new tournament: %v", err)
	}
	participant, err := event.Register("Alice", "alice-conn",
		tournament.CredentialHash("alice-token"), now)
	if err != nil {
		t.Fatalf("register: %v", err)
	}
	event.Status = tournament.StatusRunning
	deck := protocol.DeckSelect{
		Name: "Azorius Control", Format: protocol.FormatModern,
		Mainboard: []protocol.DeckCard{{
			Name: "Island", Count: 4, SetCode: "M21", CollectorNumber: "265",
		}},
		Sideboard: []protocol.DeckCard{{
			Name: "Negate", Count: 2, SetCode: "M21", CollectorNumber: "59",
		}},
	}
	actor := tournament.Actor{
		ConnectionID: participant.ConnectionID, Role: tournament.RoleParticipant,
		ParticipantID: participant.ID,
	}
	if !event.RecordDeck(actor, deck) {
		t.Fatal("record tournament deck failed")
	}

	running := tournamentSnapshot(event, tournamentBinding{Role: tournament.RoleViewer})
	if len(running.Participants) != 1 || running.Participants[0].Deck != nil {
		t.Fatalf("running snapshot exposed deck: %+v", running.Participants)
	}

	event.Status = tournament.StatusCompleted
	completed := tournamentSnapshot(event, tournamentBinding{Role: tournament.RoleViewer})
	if len(completed.Participants) != 1 || completed.Participants[0].Deck == nil ||
		completed.Participants[0].Deck.Name != deck.Name ||
		len(completed.Participants[0].Deck.Mainboard) != 1 {
		t.Fatalf("completed snapshot deck = %+v", completed.Participants)
	}
	completed.Participants[0].Deck.Mainboard[0].Name = "Mutated"
	if participant.Deck.Mainboard[0].Name != "Island" {
		t.Fatal("snapshot deck aliases authoritative tournament state")
	}
}

func TestClearTournamentParticipantBindingsRestoresViewerState(t *testing.T) {
	participant := &Session{ConnectionID: "participant"}
	participant.setTournament(tournamentBinding{
		TournamentID: "ABC12345", Role: tournament.RoleParticipant,
		ParticipantID: "p-1",
	})
	organizer := &Session{ConnectionID: "organizer"}
	organizer.setTournament(tournamentBinding{
		TournamentID: "ABC12345", Role: tournament.RoleOrganizer,
		ParticipantID: "p-1",
	})
	other := &Session{ConnectionID: "other"}
	other.setTournament(tournamentBinding{
		TournamentID: "ABC12345", Role: tournament.RoleParticipant,
		ParticipantID: "p-2",
	})
	handler := &Handler{sessions: map[string]*Session{
		participant.ConnectionID: participant,
		organizer.ConnectionID:   organizer,
		other.ConnectionID:       other,
	}}

	handler.clearTournamentParticipantBindings("ABC12345", "p-1")

	if binding := participant.Tournament(); binding.Role != tournament.RoleViewer ||
		binding.ParticipantID != "" {
		t.Fatalf("participant binding = %+v", binding)
	}
	if binding := organizer.Tournament(); binding.Role != tournament.RoleOrganizer ||
		binding.ParticipantID != "" {
		t.Fatalf("organizer binding = %+v", binding)
	}
	if binding := other.Tournament(); binding.ParticipantID != "p-2" {
		t.Fatalf("unrelated binding changed: %+v", binding)
	}
}
