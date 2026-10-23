// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package feedback

import (
	"context"
	"crypto/subtle"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"sync"
	"time"
)

const reservationBytes int64 = 2*MaxUpload + 128<<10
const stateReserve int64 = 16 << 20

type entry struct {
	gate       chan struct{}
	record     Record // Submission bytes remain on disk, not in the index.
	delivery   Delivery
	bytes      int64
	stateBytes int64
	ready      bool
	live       bool
}

type Store struct {
	mu              sync.Mutex
	ops             sync.WaitGroup
	closeOnce       sync.Once
	closeErr        error
	dir             string
	lock            *os.File
	limits          Limits
	entries         map[string]*entry
	used            int64
	reserved        int64
	reservedRecords int
	closed          bool
	now             func() time.Time
	fault           func(string) error
	space           func(string) (int64, error)
}

type Reservation struct {
	store *Store
	once  sync.Once
}

func OpenStore(dir string, limits Limits) (*Store, error) {
	return openStore(dir, limits, time.Now, nil)
}

func openStore(dir string, limits Limits, now func() time.Time, fault func(string) error) (*Store, error) {
	if err := os.MkdirAll(dir, 0700); err != nil {
		return nil, err
	}
	if err := os.Chmod(dir, 0700); err != nil {
		return nil, err
	}
	lock, err := lockStore(dir)
	if err != nil {
		return nil, fmt.Errorf("feedback store is unavailable or already locked")
	}
	s := &Store{dir: dir, lock: lock, limits: limits.defaults(), entries: map[string]*entry{}, now: now, fault: fault, space: freeBytes}
	if err := s.recover(); err != nil {
		lock.Close()
		return nil, err
	}
	return s, nil
}

func (s *Store) check(stage string) error {
	if s.fault != nil {
		return s.fault(stage)
	}
	return nil
}

func syncDirectory(path string) error {
	f, err := os.Open(path)
	if err != nil {
		return err
	}
	defer f.Close()
	return f.Sync()
}

func privateWrite(path string, raw []byte) error {
	f, err := os.OpenFile(path, os.O_CREATE|os.O_EXCL|os.O_WRONLY, 0600)
	if err != nil {
		return err
	}
	if _, err = f.Write(raw); err == nil {
		err = f.Sync()
	}
	if closeErr := f.Close(); err == nil {
		err = closeErr
	}
	return err
}

func atomicJSON(dir, name string, value any) error {
	raw, err := json.Marshal(value)
	if err != nil {
		return err
	}
	f, err := os.CreateTemp(dir, ".state-")
	if err != nil {
		return err
	}
	nameTmp := f.Name()
	defer os.Remove(nameTmp)
	if _, err = f.Write(raw); err == nil {
		err = f.Sync()
	}
	if closeErr := f.Close(); err == nil {
		err = closeErr
	}
	if err != nil {
		return err
	}
	if err = os.Rename(nameTmp, filepath.Join(dir, name)); err != nil {
		return err
	}
	return syncDirectory(dir)
}

func readRecord(path string) (Record, int64, error) {
	var r Record
	f, err := os.Open(path)
	if err != nil {
		return r, 0, err
	}
	defer f.Close()
	info, err := f.Stat()
	if err != nil || !info.Mode().IsRegular() {
		return r, 0, ErrInvalid
	}
	raw, err := readBounded(f, 8<<20)
	if err != nil {
		return r, 0, err
	}
	// Private records contain bounded base64 blobs, exceeding public JSON scalar
	// limits. Public payload validation occurred before the durable commit.
	if err = json.Unmarshal(raw, &r); err != nil {
		return r, 0, ErrInvalid
	}
	if !validID(r.Receipt.SubmissionID) || r.Receipt.Receipt != r.Receipt.SubmissionID || !validHash(r.SecretHash) || !validHash(r.Digest) || r.Receipt.SchemaVersion != 1 || r.Receipt.State != "received" {
		return r, 0, ErrInvalid
	}
	a, err := time.Parse(time.RFC3339Nano, r.Receipt.AcceptedAt)
	if err != nil {
		return r, 0, ErrInvalid
	}
	expires, err := time.Parse(time.RFC3339Nano, r.Receipt.ContentExpiresAt)
	if err != nil || !expires.Equal(a.Add(90*24*time.Hour)) {
		return r, 0, ErrInvalid
	}
	if r.Tombstone {
		if r.Submission != nil {
			return r, 0, ErrInvalid
		}
	} else {
		if r.Submission == nil || r.Submission.Manifest.SubmissionID != r.Receipt.SubmissionID || r.Submission.Digest != r.Digest || len(r.Submission.Blobs) != len(r.Submission.Manifest.Attachments) {
			return r, 0, ErrInvalid
		}
		for _, b := range r.Submission.Blobs {
			if hashBytes(b.Bytes) != b.Attachment.SHA256 || int64(len(b.Bytes)) != b.Attachment.ByteLength {
				return r, 0, ErrInvalid
			}
		}
	}
	return r, info.Size(), nil
}

func (s *Store) recover() error {
	items, err := os.ReadDir(s.dir)
	if err != nil {
		return err
	}
	for _, item := range items {
		name := item.Name()
		if strings.HasPrefix(name, ".stage-") {
			if err := os.RemoveAll(filepath.Join(s.dir, name)); err != nil {
				return err
			}
			continue
		}
		if name == ".lock" || name == "admin.sock" {
			continue
		}
		if name == "native.sock" && item.Type()&os.ModeSocket != 0 {
			continue
		}
		if !validID(name) || !item.IsDir() || item.Type()&os.ModeSymlink != 0 {
			return fmt.Errorf("unexpected feedback store member")
		}
		if len(s.entries) >= s.limits.MaxIdentities {
			return ErrCapacity
		}
		path := filepath.Join(s.dir, name)
		r, n, err := readRecord(filepath.Join(path, "record.json"))
		if err != nil || r.Receipt.SubmissionID != name {
			return fmt.Errorf("feedback record requires operator recovery")
		}
		files, err := os.ReadDir(path)
		if err != nil {
			return err
		}
		for _, f := range files {
			if strings.HasPrefix(f.Name(), ".state-") {
				if err := os.Remove(filepath.Join(path, f.Name())); err != nil {
					return err
				}
			}
		}
		e := &entry{gate: make(chan struct{}, 1), record: r, bytes: n, ready: true, delivery: Delivery{State: "pending"}}
		e.record.Submission = nil
		var data []byte
		deliveryFile, err := os.Open(filepath.Join(path, "delivery.json"))
		if err == nil {
			data, err = readBounded(deliveryFile, 4096)
			deliveryFile.Close()
		}
		if err == nil {
			if len(data) > 4096 || decodeClosed(data, &e.delivery) != nil || !validDelivery(e.delivery) {
				return fmt.Errorf("feedback delivery requires operator recovery")
			}
			e.stateBytes = int64(len(data))
		} else if !os.IsNotExist(err) {
			return err
		}
		if e.delivery.State == "transmitting" {
			e.delivery.State = "uncertain"
			e.delivery.Code = "interrupted"
			e.delivery.UpdatedAt = s.now()
			if err := atomicJSON(path, "delivery.json", e.delivery); err != nil {
				return err
			}
			encoded, _ := json.Marshal(e.delivery)
			e.stateBytes = int64(len(encoded))
		}
		// Complete both directory syncs before publishing a recovered receipt.
		if err := syncDirectory(path); err != nil {
			return err
		}
		s.entries[name] = e
		s.used += n + e.stateBytes
	}
	return syncDirectory(s.dir)
}

func validDelivery(d Delivery) bool {
	return oneOf(d.State, "pending", "transmitting", "retry_wait", "handed_off", "needs_attention", "uncertain", "discarded") && d.Attempts >= 0 && d.Attempts <= 100000 && len(d.Code) <= 64
}

func (s *Store) Close() error {
	s.closeOnce.Do(func() {
		s.mu.Lock()
		s.closed = true
		s.mu.Unlock()
		s.ops.Wait()
		s.closeErr = s.lock.Close()
	})
	return s.closeErr
}

func (s *Store) begin() bool {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.closed {
		return false
	}
	s.ops.Add(1)
	return true
}

func (s *Store) Reserve() (*Reservation, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.closed {
		return nil, ErrUnavailable
	}
	full := 0
	for _, e := range s.entries {
		if !e.record.Tombstone {
			full++
		}
	}
	free, err := s.space(s.dir)
	if err != nil {
		return nil, ErrUnavailable
	}
	if full+s.reservedRecords >= s.limits.MaxRecords || len(s.entries)+s.reservedRecords >= s.limits.MaxIdentities || s.used+s.reserved+reservationBytes+stateReserve > s.limits.MaxBytes || free-s.reserved-reservationBytes < s.limits.MinFreeBytes {
		return nil, ErrCapacity
	}
	s.reserved += reservationBytes
	s.reservedRecords++
	return &Reservation{store: s}, nil
}

func (r *Reservation) Release() {
	if r == nil {
		return
	}
	r.once.Do(func() {
		r.store.mu.Lock()
		defer r.store.mu.Unlock()
		r.store.reserved -= reservationBytes
		r.store.reservedRecords--
	})
}

func (s *Store) get(id string) *entry {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.closed {
		return nil
	}
	return s.entries[id]
}

func acquire(ctx context.Context, e *entry) error {
	select {
	case e.gate <- struct{}{}:
		return nil
	case <-ctx.Done():
		return ErrUnavailable
	}
}
func release(e *entry) { <-e.gate }

func authenticated(e *entry, secret []byte) bool {
	return subtle.ConstantTimeCompare([]byte(e.record.SecretHash), []byte(hashBytes(secret))) == 1
}

func (s *Store) readyLocked(e *entry, id string) error {
	if e.ready {
		return nil
	}
	path := filepath.Join(s.dir, id)
	if err := s.check("reconcile"); err != nil {
		return ErrUnavailable
	}
	r, n, err := readRecord(filepath.Join(path, "record.json"))
	if err != nil {
		return ErrUnavailable
	}
	if err = syncDirectory(path); err != nil {
		return ErrUnavailable
	}
	if err = syncDirectory(s.dir); err != nil {
		return ErrUnavailable
	}
	r.Submission = nil
	s.mu.Lock()
	s.used += n - e.bytes
	e.bytes = n
	e.record = r
	e.ready = true
	s.mu.Unlock()
	return nil
}

func (s *Store) Lookup(ctx context.Context, id string, secret []byte, digest string) (Receipt, error) {
	if !s.begin() {
		return Receipt{}, ErrUnavailable
	}
	defer s.ops.Done()
	e := s.get(id)
	if e == nil {
		return Receipt{}, ErrNotFound
	}
	if err := acquire(ctx, e); err != nil {
		return Receipt{}, err
	}
	defer release(e)
	if !authenticated(e, secret) {
		return Receipt{}, ErrNotFound
	}
	if err := s.readyLocked(e, id); err != nil {
		return Receipt{}, err
	}
	if e.record.Tombstone || !s.now().Before(mustTime(e.record.Receipt.ContentExpiresAt)) {
		return Receipt{}, ErrExpired
	}
	if digest != "" && e.record.Digest != digest {
		return Receipt{}, ErrConflict
	}
	return e.record.Receipt, nil
}

func mustTime(s string) time.Time { t, _ := time.Parse(time.RFC3339Nano, s); return t }

func (s *Store) Accept(ctx context.Context, reservation *Reservation, secret []byte, sub Submission) (Receipt, bool, error) {
	if !s.begin() {
		return Receipt{}, false, ErrUnavailable
	}
	defer s.ops.Done()
	if reservation == nil || reservation.store != s {
		return Receipt{}, false, ErrCapacity
	}
	id := sub.Manifest.SubmissionID
	if !validID(id) || len(secret) != 32 || !validHash(sub.Digest) {
		return Receipt{}, false, ErrInvalid
	}
	s.mu.Lock()
	if s.closed {
		s.mu.Unlock()
		return Receipt{}, false, ErrUnavailable
	}
	e := s.entries[id]
	if e == nil {
		now := s.now().UTC()
		r := Receipt{SchemaVersion: 1, SubmissionID: id, Receipt: id, AcceptedAt: now.Format(time.RFC3339Nano), ContentExpiresAt: now.Add(90 * 24 * time.Hour).Format(time.RFC3339Nano), State: "received"}
		e = &entry{gate: make(chan struct{}, 1), record: Record{Receipt: r, SecretHash: hashBytes(secret), Digest: sub.Digest}, delivery: Delivery{State: "pending"}}
		e.gate <- struct{}{}
		s.entries[id] = e
		s.mu.Unlock()
	} else {
		s.mu.Unlock()
		r, err := s.Lookup(ctx, id, secret, sub.Digest)
		return r, false, err
	}
	defer release(e)
	stage, err := os.MkdirTemp(s.dir, ".stage-")
	if err != nil {
		s.removeUnpublished(id, e)
		return Receipt{}, false, ErrUnavailable
	}
	defer os.RemoveAll(stage)
	r := e.record
	r.Submission = &sub
	raw, err := json.Marshal(r)
	if err != nil || int64(len(raw)) > reservationBytes {
		s.removeUnpublished(id, e)
		return Receipt{}, false, ErrInvalid
	}
	fail := func() (Receipt, bool, error) { s.removeUnpublished(id, e); return Receipt{}, false, ErrUnavailable }
	if s.check("write") != nil {
		return fail()
	}
	if err = privateWrite(filepath.Join(stage, "record.json"), raw); err != nil {
		return fail()
	}
	if s.check("file_sync") != nil {
		return fail()
	}
	if err = syncDirectory(stage); err != nil {
		return fail()
	}
	if s.check("stage_sync") != nil {
		return fail()
	}
	if err = os.Rename(stage, filepath.Join(s.dir, id)); err != nil {
		return fail()
	}
	// The entry remains unpublished on every post-rename failure. Lookup and
	// recovery must finish durability before returning its receipt.
	s.mu.Lock()
	e.bytes = int64(len(raw))
	s.used += e.bytes
	s.mu.Unlock()
	if s.check("rename") != nil {
		return Receipt{}, false, ErrUnavailable
	}
	if err = syncDirectory(s.dir); err != nil {
		return Receipt{}, false, ErrUnavailable
	}
	if s.check("parent_sync") != nil {
		return Receipt{}, false, ErrUnavailable
	}
	e.ready = true
	return e.record.Receipt, true, nil
}

func (s *Store) removeUnpublished(id string, e *entry) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.entries[id] == e {
		delete(s.entries, id)
	}
}

func (s *Store) IDs() []string {
	s.mu.Lock()
	defer s.mu.Unlock()
	ids := make([]string, 0, len(s.entries))
	for id := range s.entries {
		ids = append(ids, id)
	}
	sort.Strings(ids)
	return ids
}

// Prune is also called at startup; an expired undelivered item is exposed by
// Stats before cleanup and never transitions to handed_off.
func (s *Store) Prune(ctx context.Context) error {
	if !s.begin() {
		return ErrUnavailable
	}
	defer s.ops.Done()
	for _, id := range s.IDs() {
		e := s.get(id)
		if e == nil {
			continue
		}
		if err := acquire(ctx, e); err != nil {
			return err
		}
		if e.live {
			release(e)
			continue
		}
		if err := s.readyLocked(e, id); err != nil {
			release(e)
			return err
		}
		now := s.now()
		accepted := mustTime(e.record.Receipt.AcceptedAt)
		if !now.Before(accepted.Add(120 * 24 * time.Hour)) {
			if err := os.RemoveAll(filepath.Join(s.dir, id)); err != nil {
				release(e)
				return err
			}
			if err := syncDirectory(s.dir); err != nil {
				e.ready = false
				release(e)
				return err
			}
			s.mu.Lock()
			s.used -= e.bytes + e.stateBytes
			delete(s.entries, id)
			s.mu.Unlock()
		} else if !now.Before(mustTime(e.record.Receipt.ContentExpiresAt)) && !e.record.Tombstone {
			if err := s.discardLocked(id, e, "expired"); err != nil {
				release(e)
				return err
			}
		}
		release(e)
	}
	return nil
}

func (s *Store) discardLocked(id string, e *entry, reason string) error {
	if reason == "expired" && e.delivery.State != "handed_off" {
		reason = "expired_undelivered"
	}
	r := e.record
	r.Tombstone = true
	r.Submission = nil
	if err := atomicJSON(filepath.Join(s.dir, id), "record.json", r); err != nil {
		e.ready = false
		return err
	}
	raw, _ := json.Marshal(r)
	s.mu.Lock()
	s.used += int64(len(raw)) - e.bytes
	e.bytes = int64(len(raw))
	e.record = r
	s.mu.Unlock()
	d := e.delivery
	d.State = "discarded"
	d.Code = reason
	d.UpdatedAt = s.now()
	if err := s.saveDeliveryLocked(id, e, d); err != nil {
		return err
	}
	e.delivery = d
	return nil
}

// Account for persistent outbox bytes as well as content. Its atomic temporary
// copy is covered by the reserved state-write headroom.
func (s *Store) saveDeliveryLocked(id string, e *entry, d Delivery) error {
	err := atomicJSON(filepath.Join(s.dir, id), "delivery.json", d)
	if info, statErr := os.Stat(filepath.Join(s.dir, id, "delivery.json")); statErr == nil {
		s.mu.Lock()
		s.used += info.Size() - e.stateBytes
		e.stateBytes = info.Size()
		s.mu.Unlock()
	}
	return err
}
