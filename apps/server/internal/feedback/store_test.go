// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package feedback

import (
	"context"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"sync/atomic"
	"testing"
	"time"
)

var testNow = time.Date(2026, 10, 9, 12, 0, 0, 0, time.UTC)
var testSecret = []byte("01234567890123456789012345678901")

const testID = "83bd35d6-dd11-4a73-9f35-4ed43b6ab8b1"

func testSubmission(t *testing.T) Submission {
	t.Helper()
	raw, err := os.ReadFile("../../../../testdata/feedback/v1/valid-no-attachments.json")
	if err != nil {
		t.Fatal(err)
	}
	m, err := validateManifest(raw, testID, testNow)
	if err != nil {
		t.Fatal(err)
	}
	return Submission{Manifest: m, Digest: Digest(raw), Blobs: []Blob{}}
}

func testStore(t *testing.T) (*Store, *atomic.Int64) {
	t.Helper()
	clock := &atomic.Int64{}
	clock.Store(testNow.Unix())
	s, err := openStore(t.TempDir(), Limits{}, func() time.Time { return time.Unix(clock.Load(), 0) }, nil)
	if err != nil {
		t.Fatal(err)
	}
	s.space = func(string) (int64, error) { return 1 << 40, nil }
	t.Cleanup(func() { s.Close() })
	return s, clock
}

func acceptTest(t *testing.T, s *Store) Receipt {
	t.Helper()
	r, err := s.Reserve()
	if err != nil {
		t.Fatal(err)
	}
	defer r.Release()
	receipt, created, err := s.Accept(context.Background(), r, testSecret, testSubmission(t))
	if err != nil || !created {
		t.Fatalf("accept created=%v err=%v", created, err)
	}
	return receipt
}

func TestStoreDurabilityAuthAndIdempotency(t *testing.T) {
	s, _ := testStore(t)
	receipt := acceptTest(t, s)
	if _, err := OpenStore(s.dir, Limits{}); err == nil {
		t.Fatal("second writer acquired live store")
	}
	if _, err := s.Lookup(context.Background(), testID, []byte("wrong"), ""); !errors.Is(err, ErrNotFound) {
		t.Fatal(err)
	}
	if _, err := s.Lookup(context.Background(), testID, testSecret, hashBytes([]byte("changed"))); !errors.Is(err, ErrConflict) {
		t.Fatal(err)
	}
	r, err := s.Reserve()
	if err != nil {
		t.Fatal(err)
	}
	defer r.Release()
	again, created, err := s.Accept(context.Background(), r, testSecret, testSubmission(t))
	if err != nil || created || again != receipt {
		t.Fatal("duplicate changed receipt", again, err)
	}
	if err := s.Close(); err != nil {
		t.Fatal(err)
	}
	reopened, err := openStore(s.dir, Limits{}, func() time.Time { return testNow }, nil)
	if err != nil {
		t.Fatal(err)
	}
	defer reopened.Close()
	again, err = reopened.Lookup(context.Background(), testID, testSecret, "")
	if err != nil || again != receipt {
		t.Fatal("lost response recovery", again, err)
	}
	for _, name := range []string{s.dir, filepath.Join(s.dir, testID)} {
		info, _ := os.Stat(name)
		if info.Mode().Perm() != 0700 {
			t.Fatal("directory permissions")
		}
	}
	info, _ := os.Stat(filepath.Join(s.dir, testID, "record.json"))
	if info.Mode().Perm() != 0600 {
		t.Fatal("file permissions")
	}
}

func TestAcceptanceFaultRecoveryAndPublicationGate(t *testing.T) {
	for _, stage := range []string{"write", "file_sync", "stage_sync", "rename", "parent_sync"} {
		t.Run(stage, func(t *testing.T) {
			s, _ := testStore(t)
			s.fault = func(at string) error {
				if at == stage || at == "reconcile" {
					return ErrUnavailable
				}
				return nil
			}
			r, err := s.Reserve()
			if err != nil {
				t.Fatal(err)
			}
			_, _, err = s.Accept(context.Background(), r, testSecret, testSubmission(t))
			r.Release()
			if err == nil {
				t.Fatal("injected failure acknowledged")
			}
			if _, err := s.Lookup(context.Background(), testID, testSecret, ""); err == nil {
				t.Fatal("unpublished receipt visible")
			}
			s.Close()
			reopened, err := openStore(s.dir, Limits{}, func() time.Time { return testNow }, nil)
			if err != nil {
				t.Fatal(err)
			}
			defer reopened.Close()
			_, err = reopened.Lookup(context.Background(), testID, testSecret, "")
			if stage == "rename" || stage == "parent_sync" {
				if err != nil {
					t.Fatal("recovery failed", err)
				}
			} else if !errors.Is(err, ErrNotFound) {
				t.Fatal("staged item published", err)
			}
		})
	}
	t.Run("lookup waits before publish and close retains lock", func(t *testing.T) {
		s, _ := testStore(t)
		entered := make(chan struct{})
		unblock := make(chan struct{})
		s.fault = func(stage string) error {
			if stage == "rename" {
				close(entered)
				<-unblock
			}
			return nil
		}
		r, err := s.Reserve()
		if err != nil {
			t.Fatal(err)
		}
		sub := testSubmission(t)
		accepted := make(chan error, 1)
		go func() { _, _, err := s.Accept(context.Background(), r, testSecret, sub); r.Release(); accepted <- err }()
		<-entered
		ctx, cancel := context.WithTimeout(context.Background(), 30*time.Millisecond)
		defer cancel()
		if _, err := s.Lookup(ctx, testID, testSecret, ""); !errors.Is(err, ErrUnavailable) {
			t.Fatal("gate failed", err)
		}
		closed := make(chan struct{})
		go func() { s.Close(); close(closed) }()
		select {
		case <-closed:
			t.Fatal("closed during commit")
		case <-time.After(20 * time.Millisecond):
		}
		if other, err := OpenStore(s.dir, Limits{}); err == nil {
			other.Close()
			t.Fatal("lock released while writing")
		}
		close(unblock)
		if err := <-accepted; err != nil {
			t.Fatal(err)
		}
		<-closed
	})
}

func TestOutboxRestartUnknownAndAdminClaims(t *testing.T) {
	s, _ := testStore(t)
	acceptTest(t, s)
	job, err := s.Claim(context.Background())
	if err != nil || job == nil {
		t.Fatal(job, err)
	}
	if _, err := s.Admin(context.Background(), AdminRequest{Action: "retry", Receipt: testID}); !errors.Is(err, ErrBusy) {
		t.Fatal("live retry", err)
	}
	if second, err := s.Claim(context.Background()); err != nil || second != nil {
		t.Fatal("duplicate claim", second, err)
	}
	s.Close()
	s2, err := openStore(s.dir, Limits{}, func() time.Time { return testNow }, nil)
	if err != nil {
		t.Fatal(err)
	}
	defer s2.Close()
	stats, err := s2.Stats(context.Background())
	if err != nil || stats.Uncertain != 1 {
		t.Fatal(stats, err)
	}
	if job, err := s2.Claim(context.Background()); err != nil || job != nil {
		t.Fatal("uncertain auto-retried")
	}
	if _, err := s2.Admin(context.Background(), AdminRequest{Action: "retry", Receipt: testID}); err != nil {
		t.Fatal(err)
	}
	job, err = s2.Claim(context.Background())
	if err != nil || job == nil || job.Attempt != 2 {
		t.Fatal(job, err)
	}
	s2.fault = func(stage string) error {
		if stage == "delivery_finish" {
			return ErrUnavailable
		}
		return nil
	}
	if err := s2.Finish(context.Background(), *job, MailResult{"handed_off", "relay_accepted"}); err == nil {
		t.Fatal("outcome write failure hidden")
	}
	if job, err := s2.Claim(context.Background()); err != nil || job != nil {
		t.Fatal("unknown acceptance auto-retried")
	}
	if _, err := s2.Admin(context.Background(), AdminRequest{Action: "confirm", Receipt: testID}); err != nil {
		t.Fatal(err)
	}
}

func TestOutboxRetryBudgetExpiresBeforeClaimAndSurvivesRestart(t *testing.T) {
	for _, futureBackoff := range []bool{false, true} {
		t.Run(fmt.Sprintf("future_backoff_%v", futureBackoff), func(t *testing.T) {
			s, clock := testStore(t)
			acceptTest(t, s)
			job, err := s.Claim(context.Background())
			if err != nil || job == nil {
				t.Fatal(job, err)
			}
			if err := s.Finish(context.Background(), *job, MailResult{"retry_wait", "relay_temporary"}); err != nil {
				t.Fatal(err)
			}
			if futureBackoff {
				e := s.get(testID)
				if err := acquire(context.Background(), e); err != nil {
					t.Fatal(err)
				}
				e.delivery.NextAttempt = testNow.Add(8 * 24 * time.Hour)
				if err := s.saveDeliveryLocked(testID, e, e.delivery); err != nil {
					t.Fatal(err)
				}
				release(e)
			}
			clock.Store(testNow.Add(7 * 24 * time.Hour).Unix())
			if job, err := s.Claim(context.Background()); err != nil || job != nil {
				t.Fatalf("expired retry reached sender: job=%v err=%v", job, err)
			}
			result, err := s.Admin(context.Background(), AdminRequest{Action: "inspect", Receipt: testID})
			if err != nil || result.Delivery.State != "needs_attention" || result.Delivery.Code != "retry_exhausted" || result.Delivery.Attempts != 1 || !result.Delivery.NextAttempt.IsZero() {
				t.Fatalf("expiry was not persisted: %+v %v", result.Delivery, err)
			}
			if err := s.Close(); err != nil {
				t.Fatal(err)
			}
			reopened, err := openStore(s.dir, Limits{}, func() time.Time { return time.Unix(clock.Load(), 0) }, nil)
			if err != nil {
				t.Fatal(err)
			}
			defer reopened.Close()
			if job, err := reopened.Claim(context.Background()); err != nil || job != nil {
				t.Fatal("restart reauthorized expired retry", job, err)
			}
			if _, err := reopened.Admin(context.Background(), AdminRequest{Action: "retry", Receipt: testID}); err != nil {
				t.Fatal(err)
			}
			if job, err := reopened.Claim(context.Background()); err != nil || job == nil || job.Attempt != 2 {
				t.Fatal("explicit operator retry blocked", job, err)
			}
		})
	}
}

func TestQuotaTombstoneAndRetention(t *testing.T) {
	s, clock := testStore(t)
	s.limits.MaxRecords = 1
	acceptTest(t, s)
	if _, err := s.Reserve(); !errors.Is(err, ErrCapacity) {
		t.Fatal("record cap", err)
	}
	if _, err := s.Lookup(context.Background(), testID, testSecret, ""); err != nil {
		t.Fatal("full store blocked receipt", err)
	}
	if _, err := s.Admin(context.Background(), AdminRequest{Action: "discard", Receipt: testID}); err != nil {
		t.Fatal(err)
	}
	if _, err := s.Lookup(context.Background(), testID, testSecret, ""); !errors.Is(err, ErrExpired) {
		t.Fatal(err)
	}
	r, err := s.Reserve()
	if err != nil {
		t.Fatal("discard did not restore capacity", err)
	}
	r.Release()
	clock.Store(testNow.Add(121 * 24 * time.Hour).Unix())
	if err := s.Prune(context.Background()); err != nil {
		t.Fatal(err)
	}
	if _, err := s.Lookup(context.Background(), testID, testSecret, ""); !errors.Is(err, ErrNotFound) {
		t.Fatal(err)
	}
	if len(s.IDs()) != 0 {
		t.Fatal("tombstone not pruned")
	}
}

func TestRetentionMarksUndeliveredWithoutPretendingHandoff(t *testing.T) {
	s, clock := testStore(t)
	acceptTest(t, s)
	clock.Store(testNow.Add(91 * 24 * time.Hour).Unix())
	if err := s.Prune(context.Background()); err != nil {
		t.Fatal(err)
	}
	stats, err := s.Stats(context.Background())
	if err != nil || stats.ExpiredUndelivered != 1 || stats.Tombstones != 1 {
		t.Fatal(stats, err)
	}
}
