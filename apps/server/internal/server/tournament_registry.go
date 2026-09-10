// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package server

import (
	"sort"
	"sync"
	"time"

	"hexproof/server/internal/protocol"
	"hexproof/server/internal/tournament"
)

type tournamentRegistry struct {
	mu        sync.Mutex
	maxEvents int
	events    map[string]*tournamentEntry
	closed    bool
}

type tournamentEntry struct {
	opMu              sync.Mutex
	mu                sync.Mutex
	event             *tournament.Tournament
	chat              []protocol.TournamentChatMessage
	chatSequence      int
	unattendedSince   time.Time
	cleanupDeadline   time.Time
	cleanupTimer      *time.Timer
	cleanupGeneration uint64
}

func newTournamentRegistry(maxEvents int) *tournamentRegistry {
	return &tournamentRegistry{
		maxEvents: maxEvents,
		events:    make(map[string]*tournamentEntry),
	}
}

func (r *tournamentRegistry) create(event *tournament.Tournament) (*tournamentEntry, error) {
	r.mu.Lock()
	defer r.mu.Unlock()
	if r.closed {
		return nil, &protocolError{code: protocol.ErrInternal, message: "tournament registry is closed"}
	}
	if _, exists := r.events[event.ID]; exists {
		return nil, &protocolError{code: protocol.ErrInternal, message: "tournament id collision"}
	}
	if r.maxEvents > 0 && len(r.events) >= r.maxEvents {
		return nil, &protocolError{
			code: protocol.ErrServerLimit, message: "maximum tournaments reached",
		}
	}
	entry := &tournamentEntry{event: event, unattendedSince: event.CreatedAt}
	r.events[event.ID] = entry
	return entry, nil
}

func (r *tournamentRegistry) snapshot() map[string]*tournamentEntry {
	r.mu.Lock()
	defer r.mu.Unlock()
	entries := make(map[string]*tournamentEntry, len(r.events))
	for id, entry := range r.events {
		entries[id] = entry
	}
	return entries
}

func (r *tournamentRegistry) deleteIfSame(id string, expected *tournamentEntry) bool {
	r.mu.Lock()
	if r.events[id] != expected {
		r.mu.Unlock()
		return false
	}
	delete(r.events, id)
	r.mu.Unlock()
	expected.mu.Lock()
	stopTournamentCleanupLocked(expected)
	expected.mu.Unlock()
	return true
}

func (r *tournamentRegistry) close() {
	r.mu.Lock()
	r.closed = true
	entries := make([]*tournamentEntry, 0, len(r.events))
	for _, entry := range r.events {
		entries = append(entries, entry)
	}
	r.mu.Unlock()
	for _, entry := range entries {
		entry.mu.Lock()
		stopTournamentCleanupLocked(entry)
		entry.mu.Unlock()
	}
}

func (r *tournamentRegistry) entry(id string) *tournamentEntry {
	r.mu.Lock()
	defer r.mu.Unlock()
	return r.events[id]
}

func (r *tournamentRegistry) lockOperation(id string) (*tournamentEntry, error) {
	entry := r.entry(id)
	if entry == nil {
		return nil, &protocolError{
			code: protocol.ErrTournamentNotFound, message: "tournament not found",
		}
	}
	entry.opMu.Lock()
	r.mu.Lock()
	current := r.events[id]
	r.mu.Unlock()
	if current != entry {
		entry.opMu.Unlock()
		return nil, &protocolError{
			code: protocol.ErrTournamentNotFound, message: "tournament not found",
		}
	}
	return entry, nil
}

func (r *tournamentRegistry) list() []protocol.TournamentListEntry {
	r.mu.Lock()
	entries := make([]*tournamentEntry, 0, len(r.events))
	for _, entry := range r.events {
		entries = append(entries, entry)
	}
	r.mu.Unlock()

	listed := make([]protocol.TournamentListEntry, 0, len(entries))
	for _, entry := range entries {
		entry.mu.Lock()
		event := entry.event
		if event.IsCubeRoom() {
			entry.mu.Unlock()
			continue
		}
		checkedIn := 0
		for _, participant := range event.Participants {
			if participant.CheckedIn {
				checkedIn++
			}
		}
		listed = append(listed, protocol.TournamentListEntry{
			TournamentID: event.ID, Name: event.Name, Format: event.Format,
			EventType: event.EventType, Coordinator: event.Coordinator, Stage: event.Stage,
			MatchMode: event.MatchMode, Status: event.Status,
			Registered: len(event.Participants), CheckedIn: checkedIn,
			MaxPlayers: event.MaxPlayers, CurrentRound: len(event.Rounds),
			PlannedRounds: event.PlannedRounds,
			RegistrationOpen: event.Status == tournament.StatusRegistration &&
				len(event.Participants) < event.MaxPlayers,
		})
		entry.mu.Unlock()
	}
	sort.Slice(listed, func(left, right int) bool {
		return listed[left].TournamentID < listed[right].TournamentID
	})
	return listed
}

// clearRoomLocked clears a pairing room id from one tournament. The caller
// must already hold entry.opMu so pairing mutations stay in the documented
// tournament-then-room lock order.
func (r *tournamentRegistry) clearRoomLocked(entry *tournamentEntry, roomID string) {
	if entry == nil || roomID == "" {
		return
	}
	entry.mu.Lock()
	entry.event.ClearRoom(roomID)
	entry.mu.Unlock()
}
