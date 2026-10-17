// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package server

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"testing"
	"time"

	"hexproof/server/internal/protocol"
)

func archiveFixture(t *testing.T, now time.Time) *forgeCrashArchive {
	t.Helper()
	return &forgeCrashArchive{dir: t.TempDir(), pending: make(map[string]forgeCrashArchiveEntry), wake: make(chan struct{}, 1), now: func() time.Time { return now }}
}

func archiveReport(id string, at time.Time, revision int) protocol.RulesCrashReport {
	return protocol.RulesCrashReport{SchemaVersion: 1, ReportID: id, Revision: revision, OccurredAt: at.UTC().Format(time.RFC3339Nano)}
}

func TestForgeCrashArchiveRevisionDoesNotRenewRetention(t *testing.T) {
	now := time.Now().UTC()
	a := archiveFixture(t, now)
	first := now.Add(-6 * 24 * time.Hour)
	a.enqueue(archiveReport("incident", first, 1))
	a.flush()
	a.enqueue(archiveReport("incident", now, 2))
	a.flush()
	old, ok := a.read(filepath.Join(a.dir, "incident.json"))
	if !ok || old.revision != 1 || !old.first.Equal(first) {
		t.Fatal("revision changed original occurrence time")
	}
	a.enqueue(archiveReport("incident", first, 2))
	a.flush()
	a.enqueue(archiveReport("incident", first, 1))
	a.flush()
	old, ok = a.read(filepath.Join(a.dir, "incident.json"))
	if !ok || old.revision != 2 {
		t.Fatal("older revision replaced final report")
	}
	a.now = func() time.Time { return now.Add(2 * 24 * time.Hour) }
	a.prune()
	if _, err := os.Stat(filepath.Join(a.dir, "incident.json")); !os.IsNotExist(err) {
		t.Fatal("expired report survived prune")
	}
}

func TestForgeCrashArchiveBoundsPermissionsAndStorageFailure(t *testing.T) {
	now := time.Now().UTC()
	a := archiveFixture(t, now)
	for i := 0; i < forgeCrashArchiveCount+20; i++ {
		report := archiveReport(fmt.Sprintf("incident-%03d", i), now.Add(time.Duration(i)*time.Millisecond), 1)
		raw, _ := json.Marshal(report)
		if err := os.WriteFile(filepath.Join(a.dir, report.ReportID+".json"), raw, 0600); err != nil {
			t.Fatal(err)
		}
	}
	a.prune()
	files, err := os.ReadDir(a.dir)
	if err != nil || len(files) != forgeCrashArchiveCount {
		t.Fatalf("archive cap failed: %d %v", len(files), err)
	}
	for i := 0; i < forgeCrashArchiveCount+20; i++ {
		a.enqueue(archiveReport(fmt.Sprintf("queue-%d", i), now.Add(time.Hour), 1))
	}
	if len(a.pending) != forgeCrashArchiveCount {
		t.Fatal("pending archive queue unbounded")
	}
	a.flush()
	if runtime.GOOS != "windows" {
		info, err := os.Stat(filepath.Join(a.dir, "queue-0.json"))
		if err != nil || info.Mode().Perm() != 0600 {
			t.Fatalf("report permissions: %v %v", info, err)
		}
	}
	tooLarge := archiveReport("too-large", now, 1)
	tooLarge.Failure.Code = strings.Repeat("x", forgeCrashArchiveReportBytes)
	a.enqueue(tooLarge)
	a.enqueue(archiveReport("../escape", now, 1))
	if len(a.pending) != 0 {
		t.Fatal("oversized or escaping filename queued")
	}
	broken := filepath.Join(t.TempDir(), "file")
	if err := os.WriteFile(broken, []byte("occupied"), 0600); err != nil {
		t.Fatal(err)
	}
	disabled := newForgeCrashArchive(broken)
	disabled.enqueue(archiveReport("notice-still-works", now, 1))
	disabled.close()
	if newForgeCrashArchive("") != nil {
		t.Fatal("empty retention path enabled archive")
	}
	var absent *forgeCrashArchive
	absent.enqueue(archiveReport("safe", now, 1))
	absent.close()
}

func TestForgeCrashArchiveAsynchronousWriterAndShutdown(t *testing.T) {
	root := t.TempDir()
	a := newForgeCrashArchive(root)
	a.enqueue(archiveReport("persisted", time.Now(), 1))
	a.close()
	path := filepath.Join(root, "forge-crashes", "persisted.json")
	if _, err := os.Stat(path); err != nil {
		t.Fatalf("queued report not flushed: %v", err)
	}
	if runtime.GOOS != "windows" {
		info, err := os.Stat(filepath.Dir(path))
		if err != nil || info.Mode().Perm() != 0700 {
			t.Fatal("archive directory not private")
		}
	}
}
