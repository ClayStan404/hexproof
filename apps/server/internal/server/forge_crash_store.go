// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package server

import (
	"encoding/json"
	"sort"
	"sync"
	"time"

	"hexproof/server/internal/protocol"
)

const (
	forgeCrashTTL              = 7 * 24 * time.Hour
	maxForgeCrashReports       = 256
	maxForgeCrashReportBytes   = 64 << 10
	maxForgeCrashStoreBytes    = 16 << 20
	forgeCrashCollectionWindow = 5 * time.Second
)

type forgeCrashEntry struct {
	data       []byte
	roomID     string
	recipients map[string]bool
	created    time.Time
	revision   int
	occurredAt string
}

// Eligibility is bound to connection continuity, never a seat or room name.
// Entries contain no room/runtime pointers, decks or reconnect credentials.
type forgeCrashStore struct {
	mu          sync.Mutex
	entries     map[string]*forgeCrashEntry
	bytes       int
	closed      bool
	done        chan struct{}
	wg          sync.WaitGroup
	archive     *forgeCrashArchive
	maintenance bool
	collectors  int
}

func newForgeCrashStore(dir string) *forgeCrashStore {
	return &forgeCrashStore{entries: make(map[string]*forgeCrashEntry), done: make(chan struct{}), archive: newForgeCrashArchive(dir)}
}

func (s *forgeCrashStore) put(report protocol.RulesCrashReport, roomID string, recipients []string, now time.Time) bool {
	if s == nil {
		return false
	}
	data, err := json.Marshal(report)
	if err != nil || len(data) > maxForgeCrashReportBytes {
		return false
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.closed {
		return false
	}
	s.pruneLocked(now)
	entry := s.entries[report.ReportID]
	if entry != nil {
		if report.Revision <= entry.revision || roomID != entry.roomID || report.OccurredAt != entry.occurredAt {
			return false
		}
		s.bytes -= len(entry.data)
	} else {
		// A collected revision may only update an existing incident, not
		// resurrect a pruned record or overwrite eligibility after resume.
		if report.Revision != 1 {
			return false
		}
		entry = &forgeCrashEntry{roomID: roomID, created: now, occurredAt: report.OccurredAt, recipients: make(map[string]bool)}
		for _, id := range recipients {
			if id != "" {
				entry.recipients[id] = true
			}
		}
		s.entries[report.ReportID] = entry
		s.startMaintenanceLocked()
	}
	entry.data, entry.revision = data, report.Revision
	s.bytes += len(data)
	s.pruneLocked(now)
	if s.entries[report.ReportID] == nil {
		return false
	}
	s.archive.enqueue(report)
	return true
}

func (s *forgeCrashStore) pruneLocked(now time.Time) {
	for id, entry := range s.entries {
		if !now.Before(entry.created.Add(forgeCrashTTL)) {
			s.bytes -= len(entry.data)
			delete(s.entries, id)
		}
	}
	for len(s.entries) > maxForgeCrashReports || s.bytes > maxForgeCrashStoreBytes {
		oldestID := ""
		var oldest time.Time
		for id, entry := range s.entries {
			if oldestID == "" || entry.created.Before(oldest) {
				oldestID, oldest = id, entry.created
			}
		}
		if oldestID == "" {
			break
		}
		s.bytes -= len(s.entries[oldestID].data)
		delete(s.entries, oldestID)
	}
}

func (s *forgeCrashStore) forMember(roomID, connectionID string, now time.Time) []protocol.RulesCrashReport {
	if s == nil {
		return nil
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	s.pruneLocked(now)
	var entries []*forgeCrashEntry
	for _, entry := range s.entries {
		if entry.roomID != roomID || !entry.recipients[connectionID] {
			continue
		}
		entries = append(entries, entry)
	}
	sort.Slice(entries, func(i, j int) bool { return entries[i].created.Before(entries[j].created) })
	var reports []protocol.RulesCrashReport
	for _, entry := range entries {
		var report protocol.RulesCrashReport
		if json.Unmarshal(entry.data, &report) == nil {
			reports = append(reports, report)
		}
	}
	return reports
}

func (s *forgeCrashStore) recipients(reportID string, now time.Time) []string {
	if s == nil {
		return nil
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	s.pruneLocked(now)
	var ids []string
	if entry := s.entries[reportID]; entry != nil {
		for id := range entry.recipients {
			ids = append(ids, id)
		}
	}
	return ids
}

func (s *forgeCrashStore) rebind(roomID, oldID, newID string) {
	if s == nil || oldID == "" || newID == "" {
		return
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	s.pruneLocked(time.Now())
	for _, entry := range s.entries {
		if entry.roomID == roomID && entry.recipients[oldID] {
			delete(entry.recipients, oldID)
			entry.recipients[newID] = true
		}
	}
}

func (s *forgeCrashStore) collect(work func(<-chan struct{})) bool {
	if s == nil {
		return false
	}
	s.mu.Lock()
	if s.closed || s.collectors >= maxForgeCrashReports {
		s.mu.Unlock()
		return false
	}
	s.collectors++
	s.wg.Add(1)
	s.mu.Unlock()
	go func() {
		defer func() { s.mu.Lock(); s.collectors--; s.mu.Unlock(); s.wg.Done() }()
		work(s.done)
	}()
	return true
}

// Start lazily on the first stored incident; idle handlers need no timer.
// Caller holds s.mu, fencing WaitGroup.Add against Close.
func (s *forgeCrashStore) startMaintenanceLocked() {
	if s.maintenance || s.closed {
		return
	}
	s.maintenance = true
	s.wg.Add(1)
	go func() {
		defer s.wg.Done()
		ticker := time.NewTicker(time.Minute)
		defer ticker.Stop()
		for {
			select {
			case <-s.done:
				return
			case now := <-ticker.C:
				s.mu.Lock()
				s.pruneLocked(now)
				s.mu.Unlock()
			}
		}
	}()
}

func (s *forgeCrashStore) close() {
	if s == nil {
		return
	}
	s.mu.Lock()
	if s.closed {
		s.mu.Unlock()
		return
	}
	s.closed = true
	close(s.done)
	s.mu.Unlock()
	s.wg.Wait()
	s.archive.close()
}
