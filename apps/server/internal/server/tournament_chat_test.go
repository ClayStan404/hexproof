// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package server

import (
	"fmt"
	"strings"
	"testing"
	"time"

	"hexproof/server/internal/protocol"
	"hexproof/server/internal/tournament"
)

func receiveEventEnvelope(t *testing.T, sess *Session) protocol.Envelope {
	t.Helper()
	select {
	case bytes := <-sess.Send:
		env, err := protocol.ParseEnvelope(bytes)
		if err != nil {
			t.Fatal(err)
		}
		return env
	default:
		t.Fatal("missing event envelope")
		return protocol.Envelope{}
	}
}

func TestTournamentChatAudienceHistoryAndLimits(t *testing.T) {
	h := NewHandler()
	owner := tournamentAudienceSession("owner", "Judge")
	viewer := tournamentAudienceSession("viewer", "Viewer")
	outsider := tournamentAudienceSession("outsider", "Outside")
	event, err := tournament.New("CHAT1234", tournament.Config{
		Name: "Chat event", Format: "Modern", MatchMode: "bo3",
		RoundMinutes: 50, MaxPlayers: 8,
	}, owner.DisplayName, owner.ConnectionID, tournament.CredentialHash("token"), time.Now())
	if err != nil {
		t.Fatal(err)
	}
	entry, err := h.tournaments.create(event)
	if err != nil {
		t.Fatal(err)
	}
	owner.setTournament(tournamentBinding{TournamentID: event.ID, Role: tournament.RoleOrganizer})
	viewer.setTournament(tournamentBinding{TournamentID: event.ID, Role: tournament.RoleViewer})
	outsider.setTournament(tournamentBinding{TournamentID: "OTHER", Role: tournament.RoleViewer})
	for _, sess := range []*Session{owner, viewer, outsider} {
		h.registerSession(sess)
	}
	send := func(sess *Session, eventID, text string) {
		t.Helper()
		env, _ := protocol.NewEnvelope(protocol.TypeTournamentChatSend,
			protocol.TournamentChatSend{TournamentID: eventID, Text: text})
		env.ID = "chat-request"
		if err := h.handleTournamentChatSend(sess, env); err != nil {
			t.Fatal(err)
		}
	}
	owner.DisplayName = "Not the registered organizer name"
	send(owner, event.ID, " Welcome! ")
	own := receiveEventEnvelope(t, owner)
	other := receiveEventEnvelope(t, viewer)
	if own.Type != protocol.TypeTournamentChatMessage || own.ID != "chat-request" || other.ID != "" {
		t.Fatalf("invalid chat acknowledgement: %+v / %+v", own, other)
	}
	var message protocol.TournamentChatMessage
	if err := other.DecodePayload(&message); err != nil {
		t.Fatal(err)
	}
	if message.DisplayName != "Judge" || message.Text != "Welcome!" || message.Sequence != 1 {
		t.Fatalf("unexpected message: %+v", message)
	}
	if len(outsider.Send) != 0 {
		t.Fatal("chat leaked to another event")
	}
	if len(event.Participants) != 0 {
		t.Fatal("organizing or chatting auto-registered owner")
	}
	for _, text := range []string{" ", strings.Repeat("中", 501), "a\x00b"} {
		send(viewer, event.ID, text)
		if receiveEventEnvelope(t, viewer).Type != protocol.TypeError {
			t.Fatal("accepted invalid chat")
		}
	}
	send(outsider, event.ID, "cross-event")
	if receiveEventEnvelope(t, outsider).Type != protocol.TypeError {
		t.Fatal("cross-event send accepted")
	}
	// Simulate a replaced organizer connection; its old binding cannot speak as Judge.
	event.OrganizerConnectionID = "replacement"
	send(owner, event.ID, "stale")
	if receiveEventEnvelope(t, owner).Type != protocol.TypeError {
		t.Fatal("stale organizer accepted")
	}
	event.OrganizerConnectionID = owner.ConnectionID
	for index := 0; index < 105; index++ {
		viewer.RemoteIP = fmt.Sprint(index)
		send(viewer, event.ID, fmt.Sprint(index))
		receiveEventEnvelope(t, viewer)
		receiveEventEnvelope(t, owner)
	}
	if len(entry.chat) != 100 || entry.chat[0].Sequence != 7 {
		t.Fatal("history is not bounded")
	}
	h.sendTournamentChatHistory(viewer)
	history := receiveEventEnvelope(t, viewer)
	var payload protocol.TournamentChatHistory
	if err := history.DecodePayload(&payload); err != nil {
		t.Fatal(err)
	}
	if history.Type != protocol.TypeTournamentChatHistory || len(payload.Messages) != 100 {
		t.Fatal("missing re-entry history")
	}
	viewer.RemoteIP = "rate-limit"
	for index := 0; index < 30; index++ {
		send(viewer, event.ID, "message")
		receiveEventEnvelope(t, viewer)
		receiveEventEnvelope(t, owner)
	}
	send(viewer, event.ID, "too fast")
	errorEnvelope := receiveEventEnvelope(t, viewer)
	var errorPayload protocol.ErrorPayload
	_ = errorEnvelope.DecodePayload(&errorPayload)
	if errorPayload.Code != protocol.ErrRateLimited {
		t.Fatalf("rate error: %+v", errorPayload)
	}
	participant, err := event.Register("Registered player", viewer.ConnectionID,
		tournament.CredentialHash("participant-token"), time.Now())
	if err != nil {
		t.Fatal(err)
	}
	viewer.setTournament(tournamentBinding{
		TournamentID: event.ID, Role: tournament.RoleParticipant, ParticipantID: participant.ID,
	})
	viewer.RemoteIP = "participant"
	send(viewer, event.ID, "Participant message")
	receiveEventEnvelope(t, viewer)
	participantMessage := receiveEventEnvelope(t, owner)
	if err := participantMessage.DecodePayload(&message); err != nil {
		t.Fatal(err)
	}
	if message.DisplayName != participant.DisplayName {
		t.Fatalf("participant author was not server-assigned: %+v", message)
	}
	participant.ConnectionID = "replacement-player"
	send(viewer, event.ID, "stale participant")
	stale := receiveEventEnvelope(t, viewer)
	if err := stale.DecodePayload(&errorPayload); err != nil {
		t.Fatal(err)
	}
	if stale.Type != protocol.TypeError || errorPayload.Code != protocol.ErrTournamentForbidden {
		t.Fatalf("stale participant accepted: %+v", stale)
	}
}
