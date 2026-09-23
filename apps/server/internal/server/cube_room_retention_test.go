// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package server

import (
	"testing"
	"time"

	"hexproof/server/internal/protocol"
	"hexproof/server/internal/room"
	"hexproof/server/internal/tournament"
)

func TestCubeTableViewReentryReleasesRoomBeforeRetention(t *testing.T) {
	for _, eventType := range []string{protocol.LimitedEventCubeDraft, protocol.LimitedEventCommanderCube} {
		for _, occupied := range []bool{true, false} {
			name := eventType + "/spectator_only"
			if occupied {
				name = eventType + "/offline_player_hold"
			}
			t.Run(name, func(t *testing.T) {
				h := retentionHandler(t, DefaultConfig())
				since := time.Now().UTC().Add(-time.Hour)
				event := addLiveTournament(t, h, "REJOIN", tournament.StatusRunning, since)
				event.EventType = eventType
				event.Coordinator = protocol.LimitedCoordinatorCasual
				event.Stage = protocol.LimitedStageCompetition
				entry := h.tournaments.entry(event.ID)
				format, deckFormat := protocol.FormatModern, protocol.DeckFormatLimited
				if eventType == protocol.LimitedEventCommanderCube {
					format, deckFormat = protocol.FormatEDH, protocol.DeckFormatCommanderLimited
				}
				// An offline occupied seat is retained during transport recovery,
				// even when the event's unattended grace has already expired.
				host := &Session{ConnectionID: "offline-player", DisplayName: "Offline player"}
				r, _, _, table, err := h.hub.createTournamentRoom("Retained table", format, deckFormat,
					protocol.MatchBO1, protocol.CardLoadBackground, protocol.RulesModeManual, 2, event.ID, "pairing", "player", host)
				if err != nil {
					t.Fatal(err)
				}
				table.opMu.Unlock()
				viewer := retentionSession(h, "table-viewer")
				operation, err := h.hub.beginJoin(r.ID, "")
				if err != nil {
					t.Fatal(err)
				}
				_, _, err = h.hub.joinRoom(operation, viewer, true)
				operation.opMu.Unlock()
				if err != nil {
					t.Fatal(err)
				}
				if !occupied {
					table.mu.Lock()
					r.Seats[r.HostSeat] = room.Seat{}
					table.mu.Unlock()
					host.setRoom(nil)
				}
				enter := cubeCommandEnvelope(t, protocol.TypeTournamentEnter,
					protocol.TournamentEnter{TournamentID: event.ID})
				done := make(chan error, 1)
				go func() { done <- h.handleTournamentEnter(viewer, enter) }()
				select {
				case err := <-done:
					if err != nil {
						t.Fatal(err)
					}
				case <-time.After(3 * time.Second):
					t.Fatal("table view reentry deadlocked against unattended event cleanup")
				}
				if reply := cubeReply(t, viewer); reply.Type != protocol.TypeTournamentEntered {
					t.Fatalf("table spectator could not restore its public Cube view: %s", reply.Payload)
				}
				if occupied {
					binding := viewer.Tournament()
					if binding.Role != tournament.RoleViewer || binding.ParticipantID != "" || viewer.Room() != r {
						t.Fatal("spectator reentry changed table membership or acquired a private draft seat")
					}
					entry.mu.Lock()
					retry := entry.cleanupTimer != nil && entry.cleanupDeadline.After(time.Now())
					unchanged := entry.unattendedSince.Equal(since)
					entry.mu.Unlock()
					if !retry || !unchanged || h.hub.FindRoom(r.ID) != r || h.tournaments.entry(event.ID) != entry {
						t.Fatal("reentry skipped retention reconciliation or destroyed an offline player's held table")
					}
				} else if viewer.Room() != nil || viewer.Tournament().TournamentID != "" ||
					h.hub.FindRoom(r.ID) != nil || h.tournaments.entry(event.ID) != nil {
					t.Fatal("spectator reentry prevented expiry or retained stale room/pod bindings")
				}
			})
		}
	}
}
