// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package server

import (
	"sync/atomic"
	"testing"
	"time"

	"hexproof/server/internal/protocol"
	"hexproof/server/internal/tournament"
)

func draftProjectionSessions(t *testing.T, h *Handler) (*tournament.Tournament, []*Session) {
	t.Helper()
	event := projectionTestEvent(t, h, "PRESENCE", protocol.LimitedEventSetDraft, 2, true)
	sessions := make([]*Session, 0, 2)
	for _, participant := range event.Participants {
		sess := &Session{ConnectionID: participant.ConnectionID, DisplayName: participant.DisplayName, Send: make(chan []byte, 64)}
		sess.setTournament(tournamentBinding{TournamentID: event.ID, ParticipantID: participant.ID, Role: tournament.RoleParticipant})
		h.registerSession(sess)
		sessions = append(sessions, sess)
	}
	return event, sessions
}

func TestDraftDepartureBroadcastsPresence(t *testing.T) {
	for _, departure := range []string{"disconnect", "switch", "create", "leave"} {
		t.Run(departure, func(t *testing.T) {
			h := NewHandler()
			event, sessions := draftProjectionSessions(t, h)
			departing, observer := sessions[0], sessions[1]
			participantID := departing.Tournament().ParticipantID
			switch departure {
			case "disconnect":
				h.unregisterSession(departing)
			case "switch":
				next := projectionTestEvent(t, h, "NEXT1234", "", 2, false)
				enter, _ := protocol.NewEnvelope(protocol.TypeTournamentEnter, protocol.TournamentEnter{TournamentID: next.ID})
				if err := h.handleTournamentEnter(departing, enter); err != nil {
					t.Fatal(err)
				}
			case "create":
				create, _ := protocol.NewEnvelope(protocol.TypeTournamentCreate, protocol.TournamentCreate{
					Name: "New event", Format: "Modern", MatchMode: "bo3", RoundMinutes: 50, MaxPlayers: 8,
				})
				if err := h.handleTournamentCreate(departing, create); err != nil {
					t.Fatal(err)
				}
			case "leave":
				if err := h.handleTournamentLeave(departing, protocol.Envelope{Type: protocol.TypeTournamentLeave}); err != nil {
					t.Fatal(err)
				}
			}
			found := false
			for len(observer.Send) > 0 {
				env, err := protocol.ParseEnvelope(<-observer.Send)
				if err != nil {
					t.Fatal(err)
				}
				if env.Type != protocol.TypeTournamentSnapshot {
					continue
				}
				var snapshot protocol.TournamentSnapshot
				if err := env.DecodePayload(&snapshot); err != nil {
					t.Fatal(err)
				}
				for _, participant := range snapshot.Participants {
					if snapshot.TournamentID == event.ID && participant.ParticipantID == participantID {
						found = true
						if participant.Online {
							t.Error("departed participant still appears online")
						}
					}
				}
			}
			if !found {
				t.Fatal("departure did not refresh public presence without another pick")
			}
		})
	}
}

func TestTournamentLeaveCannotRegressConcurrentPick(t *testing.T) {
	h := NewHandler()
	event, sessions := draftProjectionSessions(t, h)
	picker := sessions[0]
	viewer := &Session{ConnectionID: "leaving-viewer", Send: make(chan []byte, 64)}
	viewer.setTournament(tournamentBinding{TournamentID: event.ID, Role: tournament.RoleViewer})
	h.registerSession(viewer)
	private := event.LimitedSnapshot(picker.Tournament().ParticipantID)
	pick, _ := protocol.NewEnvelope(protocol.TypeLimitedPick, protocol.LimitedPick{InstanceID: private.CurrentPack[0].InstanceID})
	serializing, resume := make(chan struct{}), make(chan struct{})
	var paused atomic.Bool
	h.marshalEnvelope = func(env protocol.Envelope) ([]byte, error) {
		if env.Type == protocol.TypeTournamentSnapshot && paused.CompareAndSwap(false, true) {
			close(serializing)
			<-resume
		}
		return env.Marshal()
	}
	leaveDone, pickDone := make(chan error, 1), make(chan error, 1)
	go func() {
		leaveDone <- h.handleTournamentLeave(viewer, protocol.Envelope{Type: protocol.TypeTournamentLeave})
	}()
	select {
	case <-serializing:
	case <-time.After(3 * time.Second):
		close(resume)
		t.Fatal("leave did not reach projection serialization")
	}
	go func() { pickDone <- h.handleLimitedPick(picker, pick) }()
	select {
	case <-pickDone:
		close(resume)
		t.Fatal("pick bypassed the in-flight leave projection")
	case <-time.After(30 * time.Millisecond):
	}
	close(resume)
	for _, done := range []chan error{leaveDone, pickDone} {
		select {
		case err := <-done:
			if err != nil {
				t.Fatal(err)
			}
		case <-time.After(3 * time.Second):
			t.Fatal("concurrent leave/pick did not finish")
		}
	}
	lastPool := -1
	for len(picker.Send) > 0 {
		env, _ := protocol.ParseEnvelope(<-picker.Send)
		if env.Type == protocol.TypeLimitedSnapshot {
			var snapshot protocol.LimitedSnapshot
			if err := env.DecodePayload(&snapshot); err != nil {
				t.Fatal(err)
			}
			if len(snapshot.Pool) < lastPool {
				t.Error("an older full snapshot rolled back the picked pool")
			}
			lastPool = len(snapshot.Pool)
		}
	}
	if lastPool != 1 {
		t.Fatalf("last private pool has %d cards, want 1", lastPool)
	}
}
