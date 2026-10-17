// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package server

import (
	"encoding/json"
	"log"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"sync"
	"time"

	"hexproof/server/internal/protocol"
)

const (
	forgeCrashArchiveAge         = 7 * 24 * time.Hour
	forgeCrashArchiveCount       = 256
	forgeCrashArchiveBytes       = 16 << 20
	forgeCrashArchiveReportBytes = 64 << 10
)

type forgeCrashArchiveEntry struct {
	id       string
	revision int
	first    time.Time
	raw      []byte
}

// The archive has one writer and a bounded coalescing inbox. Room cleanup only
// queues immutable JSON; disk latency and storage failures stay off room locks.
type forgeCrashArchive struct {
	dir     string
	mu      sync.Mutex
	pending map[string]forgeCrashArchiveEntry
	closed  bool
	wake    chan struct{}
	stop    chan struct{}
	done    chan struct{}
	now     func() time.Time
}

func newForgeCrashArchive(retentionDir string) *forgeCrashArchive {
	if retentionDir == "" {
		return nil
	}
	a := &forgeCrashArchive{dir: filepath.Join(retentionDir, "forge-crashes"), pending: make(map[string]forgeCrashArchiveEntry), wake: make(chan struct{}, 1), stop: make(chan struct{}), done: make(chan struct{}), now: time.Now}
	go a.run()
	return a
}

func crashArchiveID(id string) bool {
	if len(id) == 0 || len(id) > 128 {
		return false
	}
	for _, r := range id {
		if !(r >= 'a' && r <= 'z' || r >= 'A' && r <= 'Z' || r >= '0' && r <= '9' || r == '-' || r == '_') {
			return false
		}
	}
	return true
}

func (a *forgeCrashArchive) enqueue(report protocol.RulesCrashReport) {
	if a == nil || !crashArchiveID(report.ReportID) || report.SchemaVersion != 1 || report.Revision < 1 || report.Revision > 2 {
		return
	}
	first, err := time.Parse(time.RFC3339Nano, report.OccurredAt)
	if err != nil || !first.Add(forgeCrashArchiveAge).After(a.now()) {
		return
	}
	raw, err := json.Marshal(report)
	if err != nil || len(raw) > forgeCrashArchiveReportBytes {
		return
	}
	a.mu.Lock()
	defer a.mu.Unlock()
	if a.closed {
		return
	}
	old, exists := a.pending[report.ReportID]
	if exists && (old.revision >= report.Revision || !old.first.Equal(first)) {
		return
	}
	if !exists && len(a.pending) >= forgeCrashArchiveCount {
		return
	}
	a.pending[report.ReportID] = forgeCrashArchiveEntry{report.ReportID, report.Revision, first, raw}
	select {
	case a.wake <- struct{}{}:
	default:
	}
}

func (a *forgeCrashArchive) close() {
	if a == nil {
		return
	}
	a.mu.Lock()
	if !a.closed {
		a.closed = true
		close(a.stop)
	}
	a.mu.Unlock()
	// Shutdown is bounded even when an operating-system filesystem call stalls.
	select {
	case <-a.done:
	case <-time.After(2 * time.Second):
	}
}

func (a *forgeCrashArchive) take() map[string]forgeCrashArchiveEntry {
	a.mu.Lock()
	defer a.mu.Unlock()
	values := a.pending
	a.pending = make(map[string]forgeCrashArchiveEntry)
	return values
}

func (a *forgeCrashArchive) run() {
	defer close(a.done)
	if os.MkdirAll(a.dir, 0700) != nil || os.Chmod(a.dir, 0700) != nil {
		log.Print("forge crash archive: storage unavailable")
		return
	}
	a.prune()
	ticker := time.NewTicker(time.Minute)
	defer ticker.Stop()
	for {
		select {
		case <-a.wake:
			a.flush()
		case <-ticker.C:
			a.prune()
		case <-a.stop:
			a.flush()
			return
		}
	}
}

func (a *forgeCrashArchive) flush() {
	for _, entry := range a.take() {
		if !entry.first.Add(forgeCrashArchiveAge).After(a.now()) {
			continue
		}
		path := filepath.Join(a.dir, entry.id+".json")
		if old, ok := a.read(path); ok && (old.revision >= entry.revision || !old.first.Equal(entry.first)) {
			continue
		}
		file, err := os.CreateTemp(a.dir, ".crash-*")
		if err != nil {
			log.Print("forge crash archive: write failed")
			continue
		}
		temporary := file.Name()
		if err = file.Chmod(0600); err == nil {
			_, err = file.Write(entry.raw)
		}
		if err == nil {
			err = file.Sync()
		}
		closeErr := file.Close()
		if err == nil {
			err = closeErr
		}
		if err == nil {
			err = os.Rename(temporary, path)
		}
		if err != nil {
			log.Print("forge crash archive: write failed")
		}
		_ = os.Remove(temporary)
	}
	a.prune()
}

func (a *forgeCrashArchive) read(path string) (forgeCrashArchiveEntry, bool) {
	info, err := os.Lstat(path)
	if err != nil || !info.Mode().IsRegular() || info.Size() > forgeCrashArchiveReportBytes {
		return forgeCrashArchiveEntry{}, false
	}
	raw, err := os.ReadFile(path)
	var report protocol.RulesCrashReport
	if err != nil || json.Unmarshal(raw, &report) != nil || report.SchemaVersion != 1 || !crashArchiveID(report.ReportID) || report.Revision < 1 || report.Revision > 2 || filepath.Base(path) != report.ReportID+".json" {
		return forgeCrashArchiveEntry{}, false
	}
	first, err := time.Parse(time.RFC3339Nano, report.OccurredAt)
	if err != nil {
		return forgeCrashArchiveEntry{}, false
	}
	return forgeCrashArchiveEntry{report.ReportID, report.Revision, first, raw}, true
}

func (a *forgeCrashArchive) prune() {
	files, err := os.ReadDir(a.dir)
	if err != nil {
		return
	}
	var entries []forgeCrashArchiveEntry
	total := 0
	for _, file := range files {
		if file.IsDir() {
			continue
		}
		name := file.Name()
		if !strings.HasSuffix(name, ".json") {
			if strings.HasPrefix(name, ".crash-") {
				_ = os.Remove(filepath.Join(a.dir, name))
			}
			continue
		}
		entry, ok := a.read(filepath.Join(a.dir, name))
		if !ok || !entry.first.Add(forgeCrashArchiveAge).After(a.now()) {
			_ = os.Remove(filepath.Join(a.dir, name))
			continue
		}
		entries = append(entries, entry)
		total += len(entry.raw)
	}
	sort.Slice(entries, func(i, j int) bool { return entries[i].first.Before(entries[j].first) })
	for len(entries) > forgeCrashArchiveCount || total > forgeCrashArchiveBytes {
		old := entries[0]
		entries = entries[1:]
		total -= len(old.raw)
		_ = os.Remove(filepath.Join(a.dir, old.id+".json"))
	}
}
