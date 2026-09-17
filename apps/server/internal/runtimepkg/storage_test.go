// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package runtimepkg

import (
	"context"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func TestCleanupPreservesCurrentActiveLegacyAndUnownedFiles(t *testing.T) {
	base := t.TempDir()
	current := PackageID() + "-current"
	active := strings.Repeat("1", 20) + "-active"
	unused := strings.Repeat("2", 20) + "-unused"
	legacy := strings.Repeat("3", 20) + "-legacy"
	for _, name := range []string{current, active, unused, legacy, "my-decks"} {
		path := filepath.Join(base, name)
		if err := os.MkdirAll(path, 0700); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(filepath.Join(path, "payload"), []byte("owned fixture"), 0600); err != nil {
			t.Fatal(err)
		}
		if name != legacy && name != "my-decks" {
			if err := os.WriteFile(filepath.Join(path, ".managed-v1"), []byte(name[:20]), 0600); err != nil {
				t.Fatal(err)
			}
		}
	}
	if err := os.WriteFile(filepath.Join(base, PackageID()+".current"), []byte(current), 0600); err != nil {
		t.Fatal(err)
	}
	lease, err := lockFile(t.Context(), filepath.Join(base, active, ".use.lock"), false)
	if err != nil {
		t.Fatal(err)
	}
	defer lease.Close()
	if err := os.MkdirAll(filepath.Join(base, "downloads"), 0700); err != nil {
		t.Fatal(err)
	}
	archive := filepath.Join(base, "downloads", strings.Repeat("a", 64)+".zip.part")
	if err := os.WriteFile(archive, []byte("partial bytes"), 0600); err != nil {
		t.Fatal(err)
	}
	result, err := ClearCache(t.Context(), base)
	if err != nil || result.FreedBytes == 0 || result.KeptGenerations != 3 {
		t.Fatalf("cleanup result: %+v / %v", result, err)
	}
	for _, path := range []string{archive, filepath.Join(base, unused)} {
		if _, err := os.Stat(path); !os.IsNotExist(err) {
			t.Fatalf("reproducible unused cache survived: %s", path)
		}
	}
	for _, name := range []string{current, active, legacy, "my-decks"} {
		if _, err := os.Stat(filepath.Join(base, name, "payload")); err != nil {
			t.Fatalf("cleanup touched retained data: %s / %v", name, err)
		}
	}
	lease.Close()
	if _, err := ClearCache(t.Context(), base); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(filepath.Join(base, active)); !os.IsNotExist(err) {
		t.Fatal("released old generation was not cleaned up")
	}
}

func TestCacheLockCancellationAndDiskProbe(t *testing.T) {
	base := t.TempDir()
	if available, err := freeBytes(base); err != nil || available == 0 {
		t.Fatalf("native disk probe failed: %d / %v", available, err)
	}
	lock, err := lockFile(t.Context(), filepath.Join(base, ".cache.lock"), true)
	if err != nil {
		t.Fatal(err)
	}
	defer lock.Close()
	ctx, cancel := context.WithTimeout(t.Context(), 60*time.Millisecond)
	defer cancel()
	if _, err := ClearCache(ctx, base); err != context.DeadlineExceeded {
		t.Fatalf("cleanup bypassed another preparer's lock or ignored cancellation: %v", err)
	}
}
