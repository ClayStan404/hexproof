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

func retentionHandler(t *testing.T, config Config) *Handler {
	t.Helper()
	h, err := NewHandlerWithConfig(config)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = h.Close() })
	return h
}

func retentionSession(h *Handler, id string) *Session {
	sess := testTournamentSession(id, "192.0.2.90")
	sess.Send = make(chan []byte, 64)
	h.registerSession(sess)
	return sess
}

func retentionOwner(h *Handler, event *tournament.Tournament) *Session {
	owner := retentionSession(h, "organizer")
	entry := h.tournaments.entry(event.ID)
	entry.mu.Lock()
	event.OrganizerConnectionID = owner.ConnectionID
	entry.mu.Unlock()
	owner.setTournament(tournamentBinding{TournamentID: event.ID, Role: tournament.RoleOrganizer})
	h.refreshTournament(event.ID)
	return owner
}

func waitTournamentRemoved(t *testing.T, h *Handler, id string) {
	t.Helper()
	deadline := time.NewTimer(3 * time.Second)
	defer deadline.Stop()
	tick := time.NewTicker(5 * time.Millisecond)
	defer tick.Stop()
	for h.tournaments.entry(id) != nil {
		select {
		case <-tick.C:
		case <-deadline.C:
			t.Fatal("timer did not reclaim the unattended tournament")
		}
	}
}

func TestTournamentUnattendedDefaults(t *testing.T) {
	config := DefaultConfig()
	if config.TournamentInactiveTTL != 5*time.Minute || config.TournamentAbandonedTTL != 5*time.Minute {
		t.Fatal("registration and running events must receive five minutes to reconnect")
	}
	if config.TournamentClosedTTL != 24*time.Hour {
		t.Fatal("completed/cancelled history retention changed")
	}
}

func TestTournamentUnattendedOriginIgnoresViewersChatAndActivity(t *testing.T) {
	h := retentionHandler(t, DefaultConfig())
	event := addLiveTournament(t, h, "UNATTENDED", tournament.StatusRegistration, time.Now().UTC())
	owner := retentionOwner(h, event)
	h.unregisterSession(owner)
	entry := h.tournaments.entry(event.ID)
	entry.mu.Lock()
	since := entry.unattendedSince
	entry.mu.Unlock()
	if since.IsZero() {
		t.Fatal("last organizer disconnect did not start the reconnect grace")
	}
	viewer := retentionSession(h, "viewer")
	if err := h.handleTournamentEnter(viewer, tournamentEnterEnvelope(t, "watch", event.ID, "")); err != nil {
		t.Fatal(err)
	}
	chat, _ := protocol.NewEnvelope(protocol.TypeTournamentChatSend,
		protocol.TournamentChatSend{TournamentID: event.ID, Text: "Anyone still here?"})
	if err := h.handleTournamentChatSend(viewer, chat); err != nil {
		t.Fatal(err)
	}
	entry.mu.Lock()
	event.LastActivityAt = since.Add(24 * time.Hour)
	entry.mu.Unlock()
	h.evictExpiredTournaments(since.Add(4 * time.Minute))
	entry.mu.Lock()
	unchanged := entry.unattendedSince.Equal(since)
	entry.mu.Unlock()
	if !unchanged || h.tournaments.entry(event.ID) == nil {
		t.Fatal("a viewer or activity timestamp altered the reconnect grace")
	}
	h.evictExpiredTournaments(since.Add(5 * time.Minute))
	if h.tournaments.entry(event.ID) != nil || viewer.Tournament().TournamentID != "" {
		t.Fatal("ordinary viewer prevented cleanup or retained a stale binding")
	}
	var sawLeft bool
	for len(viewer.Send) > 0 {
		env, err := protocol.ParseEnvelope(<-viewer.Send)
		if err != nil {
			t.Fatal(err)
		}
		sawLeft = sawLeft || env.Type == protocol.TypeTournamentLeft
	}
	if !sawLeft {
		t.Fatal("cleanup did not notify the remaining viewer")
	}
}

func TestTournamentOrganizerExplicitLeaveKeepsParticipants(t *testing.T) {
	for _, participantState := range []string{"none", "offline", "online"} {
		t.Run(participantState, func(t *testing.T) {
			h := retentionHandler(t, DefaultConfig())
			event := addLiveTournament(t, h, "LEAVE", tournament.StatusRegistration, time.Now().UTC())
			owner := retentionOwner(h, event)
			if participantState != "none" {
				entry := h.tournaments.entry(event.ID)
				entry.mu.Lock()
				player, err := event.Register("Player", "player", tournament.CredentialHash("player-token"), time.Now())
				entry.mu.Unlock()
				if err != nil {
					t.Fatal(err)
				}
				if participantState == "online" {
					sess := retentionSession(h, "player")
					sess.setTournament(tournamentBinding{TournamentID: event.ID, Role: tournament.RoleParticipant, ParticipantID: player.ID})
				}
			}
			viewer := retentionSession(h, "viewer")
			viewer.setTournament(tournamentBinding{TournamentID: event.ID, Role: tournament.RoleViewer})
			leave, _ := protocol.NewEnvelope(protocol.TypeTournamentLeave, protocol.EmptyPayload{})
			if err := h.handleTournamentLeave(owner, leave); err != nil {
				t.Fatal(err)
			}
			entry := h.tournaments.entry(event.ID)
			if participantState == "none" {
				if entry != nil || viewer.Tournament().TournamentID != "" {
					t.Fatal("empty registration was not reclaimed on explicit organizer leave")
				}
				return
			}
			if entry == nil {
				t.Fatal("organizer departure deleted other participants' registration")
			}
			entry.mu.Lock()
			since, timer := entry.unattendedSince, entry.cleanupTimer
			entry.mu.Unlock()
			if participantState == "online" {
				if !since.IsZero() || timer != nil {
					t.Fatal("online participant was treated as an unattended event")
				}
				h.evictExpiredTournaments(time.Now().Add(24 * time.Hour))
				if h.tournaments.entry(event.ID) == nil {
					t.Fatal("online participant did not protect the event")
				}
			} else if since.IsZero() || timer == nil {
				t.Fatal("offline participants did not receive a reconnect grace")
			}
		})
	}
}

func TestTournamentUnattendedTimerRunsWithoutBrowserPolling(t *testing.T) {
	for _, status := range []string{tournament.StatusRegistration, tournament.StatusRunning, tournament.StatusCancelled} {
		t.Run(status, func(t *testing.T) {
			config := DefaultConfig()
			config.TournamentInactiveTTL = 40 * time.Millisecond
			config.TournamentAbandonedTTL = config.TournamentInactiveTTL
			config.TournamentClosedTTL = config.TournamentInactiveTTL
			h := retentionHandler(t, config)
			now := time.Now().UTC()
			event := addLiveTournament(t, h, "TIMER", status, now)
			if status == tournament.StatusCancelled {
				event.ClosedAt = now
			}
			viewer := retentionSession(h, "viewer")
			viewer.setTournament(tournamentBinding{TournamentID: event.ID, Role: tournament.RoleViewer})
			h.refreshTournament(event.ID)
			waitTournamentRemoved(t, h, event.ID)
			if viewer.Tournament().TournamentID != "" {
				t.Fatal("timer expiry left the viewer bound")
			}
		})
	}
}

func TestTournamentCredentialRecoveryCancelsUnattendedTimer(t *testing.T) {
	config := DefaultConfig()
	config.TournamentInactiveTTL = 100 * time.Millisecond
	h := retentionHandler(t, config)
	event := addLiveTournament(t, h, "RECONNECT", tournament.StatusRegistration, time.Now().UTC())
	owner := retentionOwner(h, event)
	h.unregisterSession(owner)
	entry := h.tournaments.entry(event.ID)
	entry.mu.Lock()
	deadline := entry.cleanupDeadline
	entry.mu.Unlock()
	replacement := retentionSession(h, "replacement")
	if err := h.handleTournamentEnter(replacement, tournamentEnterEnvelope(t, "recover", event.ID, "credential")); err != nil {
		t.Fatal(err)
	}
	entry.mu.Lock()
	stopped := entry.unattendedSince.IsZero() && entry.cleanupTimer == nil
	entry.mu.Unlock()
	if !stopped || replacement.Tournament().Role != tournament.RoleOrganizer {
		t.Fatal("authenticated organizer recovery did not cancel unattended cleanup")
	}
	<-time.After(time.Until(deadline) + 20*time.Millisecond)
	if h.tournaments.entry(event.ID) != entry {
		t.Fatal("old timer evicted a recovered tournament")
	}
	h.unregisterSession(replacement)
	waitTournamentRemoved(t, h, event.ID)
}

func retentionPairing(t *testing.T, h *Handler, event *tournament.Tournament) (*Session, *room.Room, *roomEntry) {
	t.Helper()
	host := retentionSession(h, "table-host")
	host.ResumeToken = "table-resume"
	r, _, _, operation, err := h.hub.createTournamentRoom("Pairing", protocol.FormatModern,
		protocol.DeckFormatModern, protocol.MatchBO3, protocol.CardLoadBackground, protocol.RulesModeManual, 2,
		event.ID, "pairing", "player", host)
	if err != nil {
		t.Fatal(err)
	}
	operation.opMu.Unlock()
	return host, r, operation
}

func TestTournamentPairingPlayersAndReconnectHoldsProtectCleanup(t *testing.T) {
	config := DefaultConfig()
	config.TournamentAbandonedTTL = 30 * time.Millisecond
	config.ReconnectWindow = 150 * time.Millisecond
	h := retentionHandler(t, config)
	event := addLiveTournament(t, h, "PAIRING", tournament.StatusRunning, time.Now().Add(-time.Hour))
	host, r, _ := retentionPairing(t, h, event)
	h.evictExpiredTournaments(time.Now().UTC())
	entry := h.tournaments.entry(event.ID)
	if entry == nil {
		t.Fatal("player in a pairing table without a lobby binding lost the event")
	}
	h.holdForReconnect(host, r)
	h.unregisterSession(host)
	entry.mu.Lock()
	since := entry.unattendedSince
	entry.mu.Unlock()
	// Expired event grace must not invalidate the already-issued room hold.
	h.evictExpiredTournaments(since.Add(config.TournamentAbandonedTTL))
	if h.tournaments.entry(event.ID) == nil || h.hub.FindRoom(r.ID) == nil {
		t.Fatal("unattended cleanup destroyed a valid room reconnect hold")
	}
	waitTournamentRemoved(t, h, event.ID)
	if h.hub.FindRoom(r.ID) != nil {
		t.Fatal("last player hold expired without removing its abandoned table")
	}
}

func TestTournamentSpectatorOnlyTableDoesNotKeepAbandonedEvent(t *testing.T) {
	h := retentionHandler(t, DefaultConfig())
	event := addLiveTournament(t, h, "SPECTATOR", tournament.StatusRunning, time.Now().Add(-time.Hour))
	host, r, roomEntry := retentionPairing(t, h, event)
	viewer := retentionSession(h, "viewer")
	operation, err := h.hub.beginJoin(r.ID, "")
	if err != nil {
		t.Fatal(err)
	}
	_, _, err = h.hub.joinRoom(operation, viewer, true)
	operation.opMu.Unlock()
	if err != nil {
		t.Fatal(err)
	}
	// Model the last reconnect hold having released its player seat while a
	// spectator remains. No live player's identity may be cleared by cleanup.
	roomEntry.mu.Lock()
	r.Seats[r.HostSeat] = room.Seat{}
	roomEntry.mu.Unlock()
	host.setRoom(nil)
	h.evictExpiredTournaments(time.Now().UTC())
	if h.tournaments.entry(event.ID) != nil || h.hub.FindRoom(r.ID) != nil || viewer.Room() != nil {
		t.Fatal("spectator-only room retained the unattended event or stale membership")
	}
	assertTournamentAudienceTypes(t, viewer, protocol.TypeRoomDisbanded)
}

func TestTournamentCleanupTimerStopsOnDeleteAndShutdown(t *testing.T) {
	h := retentionHandler(t, DefaultConfig())
	for _, closeHandler := range []bool{false, true} {
		event := addLiveTournament(t, h, "STOP", tournament.StatusRegistration, time.Now().UTC())
		entry := h.tournaments.entry(event.ID)
		h.refreshTournament(event.ID)
		if closeHandler {
			_ = h.Close()
		} else if !h.tournaments.deleteIfSame(event.ID, entry) {
			t.Fatal("failed to delete old event")
		}
		entry.mu.Lock()
		stopped := entry.cleanupTimer == nil && entry.cleanupDeadline.IsZero()
		entry.mu.Unlock()
		if !stopped {
			t.Fatal("registry removal or shutdown retained an event timer")
		}
		if h.tryEvictTournament(event.ID, entry, time.Now().Add(time.Hour)) {
			t.Fatal("stale cleanup operated on a removed event or closed registry")
		}
	}
}

func TestTournamentStaleCredentialDoesNotKeepEventAlive(t *testing.T) {
	h := retentionHandler(t, DefaultConfig())
	event := addLiveTournament(t, h, "TRANSFER", tournament.StatusRegistration, time.Now().UTC())
	oldOwner := retentionOwner(h, event)
	entry := h.tournaments.entry(event.ID)
	entry.mu.Lock()
	// A newer credential owner is no longer connected. The old transport is
	// still registered, but no longer owns organizer authority.
	_, _, ok := event.BindCredential(tournament.CredentialHash("credential"), "gone-owner", time.Now())
	entry.mu.Unlock()
	if !ok || oldOwner.Tournament().Role != tournament.RoleOrganizer {
		t.Fatal("failed to construct stale organizer binding")
	}
	now := time.Now().UTC()
	h.evictExpiredTournaments(now)
	entry.mu.Lock()
	since := entry.unattendedSince
	entry.mu.Unlock()
	if since.IsZero() {
		t.Fatal("stale organizer transport kept the event alive")
	}
	h.evictExpiredTournaments(since.Add(h.config.TournamentInactiveTTL))
	if h.tournaments.entry(event.ID) != nil {
		t.Fatal("stale organizer transport prevented expiry")
	}
}

func TestTournamentStaleCleanupCannotEvictReplacement(t *testing.T) {
	h := retentionHandler(t, DefaultConfig())
	old := addLiveTournament(t, h, "REUSED", tournament.StatusRegistration, time.Now().UTC())
	oldEntry := h.tournaments.entry(old.ID)
	h.refreshTournament(old.ID)
	if !h.tournaments.deleteIfSame(old.ID, oldEntry) {
		t.Fatal("old tournament was not deleted")
	}
	replacement := addLiveTournament(t, h, old.ID, tournament.StatusRegistration, time.Now().UTC())
	newEntry := h.tournaments.entry(replacement.ID)
	h.refreshTournament(replacement.ID)
	if h.tryEvictTournament(old.ID, oldEntry, time.Now().Add(time.Hour)) {
		t.Fatal("stale timer evicted a replacement tournament")
	}
	newEntry.mu.Lock()
	hasTimer := newEntry.cleanupTimer != nil
	newEntry.mu.Unlock()
	if !hasTimer || h.tournaments.entry(replacement.ID) != newEntry {
		t.Fatal("stale cleanup interfered with the replacement's retention")
	}
}
