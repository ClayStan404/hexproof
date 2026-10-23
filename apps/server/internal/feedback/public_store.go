// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package feedback

import (
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

// PublicStore has one process writer and serial durable transactions. Payloads
// stay on disk; only bounded receipts and delivery metadata occupy the index.
// Any ambiguous persistence error fails closed until a recovery reopen.
type PublicStore struct {
	mu             sync.Mutex
	dir            string
	lock           *os.File
	limits         Limits
	entries        map[string]PublicRecord
	sizes          map[string]int64
	live           map[string]bool
	used           int64
	failed, closed bool
	now            func() time.Time
	fault          func(string) error
}

func OpenPublicStore(dir string, limits Limits) (*PublicStore, error) {
	return openPublicStore(dir, limits, time.Now, nil)
}
func openPublicStore(dir string, limits Limits, now func() time.Time, fault func(string) error) (*PublicStore, error) {
	if err := os.MkdirAll(dir, 0700); err != nil {
		return nil, err
	}
	if err := os.Chmod(dir, 0700); err != nil {
		return nil, err
	}
	lock, err := lockStore(dir)
	if err != nil {
		return nil, fmt.Errorf("public feedback store unavailable")
	}
	s := &PublicStore{dir: dir, lock: lock, limits: limits.defaults(), entries: map[string]PublicRecord{}, sizes: map[string]int64{}, live: map[string]bool{}, now: now, fault: fault}
	fail := func(err error) (*PublicStore, error) { lock.Close(); return nil, err }
	items, err := os.ReadDir(dir)
	if err != nil {
		return fail(err)
	}
	for _, item := range items {
		name := item.Name()
		if name == ".lock" {
			continue
		}
		if strings.HasPrefix(name, ".state-") {
			if err := os.Remove(filepath.Join(dir, name)); err != nil {
				return fail(err)
			}
			continue
		}
		if _, _, ok := contributionName(name); ok && item.Type().IsRegular() {
			continue
		}
		if !strings.HasSuffix(name, ".json") || !validID(strings.TrimSuffix(name, ".json")) || !item.Type().IsRegular() {
			return fail(ErrInvalid)
		}
		id := strings.TrimSuffix(name, ".json")
		r, n, err := s.read(id)
		if err != nil {
			return fail(err)
		}
		if len(s.entries) >= s.limits.MaxIdentities {
			return fail(ErrCapacity)
		}
		s.entries[id] = publicIndex(r)
		s.sizes[id] = n
		s.used += n
		if r.Receipt.PublicationState == "published" && r.Receipt.PublishedAt == "" && !r.PublicationTimeMigrated {
			r.PublicationTimeMigrated = true
			r.Attempts = 0
			if err := s.save(r); err != nil {
				return fail(err)
			}
		}
		if r.InFlight {
			r.InFlight = false
			if r.Action == "create" {
				r.CreateUncertain = true
			}
			if r.Action == "comment-create" {
				if c := findContribution(&r, r.ActiveContributionID); c != nil {
					c.CreateUncertain = true
				}
			}
			r.ActiveContributionID = ""
			if r.Receipt.RemovalState != "none" {
				r.Receipt.RemovalState = "pending"
			}
			if err := s.save(r); err != nil {
				return fail(err)
			}
		}
	}
	if err := s.recoverContributions(items); err != nil {
		return fail(err)
	}
	if err := syncDirectory(dir); err != nil {
		return fail(err)
	}
	return s, nil
}
func publicIndex(r PublicRecord) PublicRecord { r.Submission = nil; return r }
func (s *PublicStore) read(id string) (PublicRecord, int64, error) {
	var r PublicRecord
	f, err := os.Open(filepath.Join(s.dir, id+".json"))
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
	if json.Unmarshal(raw, &r) != nil {
		return r, 0, ErrInvalid
	}
	normalizeCaseReceipt(&r.Receipt)
	if !validCaseClosure(r) || r.Receipt.SchemaVersion != 2 || r.Receipt.SubmissionID != id || r.Receipt.Receipt != id || r.Receipt.State != "accepted" || !validHash(r.SecretHash) || !validHash(r.Digest) || !oneOf(r.Receipt.PublicationState, "pending", "stalled", "published", "rejected", "partial") || !oneOf(r.Receipt.RemovalState, "none", "requested", "pending", "stalled", "removed") || r.Attempts < 0 || r.Attempts > 12 || r.Generation < 0 || r.RemovalRepairs < 0 || r.RemovalRepairs > 2 {
		return r, 0, ErrInvalid
	}
	if r.ThreadRevision < 0 || r.InputRevision < 0 || r.CoordinatorExported != (r.CoordinatorBinding != "") || r.CoordinatorBinding != "" && !validHash(r.CoordinatorBinding) || r.RevocationRevision < 0 || r.RevocationAcknowledged && (!r.CoordinatorExported || r.RevocationRevision < 1) || r.CoordinatorExported && r.Receipt.RemovalState != "none" && r.RevocationRevision < 1 || r.Receipt.PublishedAt != "" && !utcTime(r.Receipt.PublishedAt) {
		return r, 0, ErrInvalid
	}
	if !validMulticaDelivery(r) {
		return r, 0, ErrInvalid
	}
	if !utcTime(r.Receipt.AcceptedAt) || !utcTime(r.Receipt.ContentExpiresAt) || !utcTime(r.Receipt.AccessExpiresAt) {
		return r, 0, ErrInvalid
	}
	if r.Submission != nil {
		sub := r.Submission
		if sub.Target.Repository != sub.Manifest.Disclosure.Repository || sub.Target.RepositoryID < 1 || sub.Target.PublisherActorID < 1 || sub.Target.PublicURL == "" || sub.Manifest.SubmissionID != id || sub.Digest != r.Digest || PublicDigest(sub.ManifestBytes) != r.Digest || len(sub.Blobs) != len(sub.Manifest.Attachments) {
			return r, 0, ErrInvalid
		}
		var m PublicManifest
		if decodeClosed(sub.ManifestBytes, &m) != nil {
			return r, 0, ErrInvalid
		}
		a, _ := json.Marshal(m)
		b, _ := json.Marshal(sub.Manifest)
		if string(a) != string(b) {
			return r, 0, ErrInvalid
		}
		for i, b := range sub.Blobs {
			if b.Attachment != sub.Manifest.Attachments[i] || int64(len(b.Bytes)) != b.Attachment.ByteLength || hashBytes(b.Bytes) != b.Attachment.SHA256 {
				return r, 0, ErrInvalid
			}
		}
	} else if r.Receipt.RemovalState != "removed" {
		return r, 0, ErrInvalid
	}
	return r, info.Size(), nil
}
func (s *PublicStore) save(r PublicRecord) error {
	normalizeCaseReceipt(&r.Receipt)
	if s.failed || s.closed {
		return ErrUnavailable
	}
	if s.fault != nil && s.fault("save") != nil {
		s.failed = true
		return ErrUnavailable
	}
	r.ThreadRevision = max(r.ThreadRevision, s.entries[r.Receipt.SubmissionID].ThreadRevision) + 1
	raw, err := json.Marshal(r)
	if err != nil {
		return ErrInvalid
	}
	id := r.Receipt.SubmissionID
	if err = atomicJSON(s.dir, id+".json", r); err != nil {
		s.failed = true
		return ErrUnavailable
	}
	s.used += int64(len(raw)) - s.sizes[id]
	s.sizes[id] = int64(len(raw))
	s.entries[id] = publicIndex(r)
	return nil
}
func (s *PublicStore) Close() error {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.closed {
		return nil
	}
	s.closed = true
	return s.lock.Close()
}
func (s *PublicStore) lookup(id string, secret []byte, digest string) (PublicRecord, error) {
	if s.closed || s.failed {
		return PublicRecord{}, ErrUnavailable
	}
	r, ok := s.entries[id]
	if !ok || subtle.ConstantTimeCompare([]byte(r.SecretHash), []byte(hashBytes(secret))) != 1 {
		return PublicRecord{}, ErrNotFound
	}
	if digest != "" && r.Digest != digest {
		return r, ErrConflict
	}
	return r, nil
}
func (s *PublicStore) Lookup(id string, secret []byte, digest string) (PublicReceipt, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	r, err := s.lookup(id, secret, digest)
	return r.Receipt, err
}
func (s *PublicStore) Accept(secret []byte, sub PublicSubmission) (PublicReceipt, bool, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	id := sub.Manifest.SubmissionID
	if s.closed || s.failed {
		return PublicReceipt{}, false, ErrUnavailable
	}
	if _, ok := s.entries[id]; ok {
		r, err := s.lookup(id, secret, sub.Digest)
		return r.Receipt, false, err
	}
	if sub.Manifest.ParentSubmissionID != "" || sub.Manifest.QuestionID != "" || sub.Manifest.QuestionRevision != 0 || !validID(id) || len(secret) != 32 || PublicDigest(sub.ManifestBytes) != sub.Digest || sub.Target.Repository != sub.Manifest.Disclosure.Repository || sub.Target.RepositoryID < 1 || sub.Target.PublisherActorID < 1 || sub.Target.PublicURL == "" {
		return PublicReceipt{}, false, ErrInvalid
	}
	free, err := freeBytes(s.dir)
	if err != nil {
		return PublicReceipt{}, false, ErrUnavailable
	}
	active := 0
	for _, r := range s.entries {
		if r.Receipt.RemovalState != "removed" {
			active++
		}
	}
	if len(s.entries) >= s.limits.MaxIdentities || active >= s.limits.MaxRecords || s.used+reservationBytes+stateReserve > s.limits.MaxBytes || free-reservationBytes < s.limits.MinFreeBytes {
		return PublicReceipt{}, false, ErrCapacity
	}
	now := s.now().UTC()
	expires := now.Add(365 * 24 * time.Hour).Format(time.RFC3339Nano)
	r := PublicRecord{Receipt: PublicReceipt{SchemaVersion: 2, SubmissionID: id, Receipt: id, AcceptedAt: now.Format(time.RFC3339Nano), ContentExpiresAt: expires, AccessExpiresAt: expires, State: "accepted", PublicationState: "pending", RemovalState: "none", CaseState: "open", ClosurePublicationState: "none"}, SecretHash: hashBytes(secret), Digest: sub.Digest, Submission: &sub}
	if err := s.save(r); err != nil {
		return PublicReceipt{}, false, err
	}
	return r.Receipt, true, nil
}
func (s *PublicStore) Remove(id string, secret []byte) (PublicReceipt, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	r, err := s.lookup(id, secret, "")
	if err != nil {
		return PublicReceipt{}, err
	}
	repair := r.Receipt.RemovalState == "stalled" && r.RemovalRepairs < 2 && !r.StalledAt.IsZero() && !s.now().Before(r.StalledAt.Add(6*time.Hour))
	if r.Receipt.RemovalState != "none" && !repair {
		return r.Receipt, nil
	}
	r, _, err = s.read(id)
	if err != nil {
		return PublicReceipt{}, ErrUnavailable
	}
	if repair {
		r.RemovalRepairs++
	}
	s.startRemoval(&r, "removal_requested")
	if !s.live[id] && !r.CreateUncertain && r.IssueNumber == 0 {
		s.markRemoved(&r)
	}
	if err = s.save(r); err != nil {
		return PublicReceipt{}, err
	}
	if r.Receipt.RemovalState == "removed" {
		if err = s.purgeContributions(r); err != nil {
			return PublicReceipt{}, err
		}
	}
	return r.Receipt, nil
}
func (s *PublicStore) Asset(id, attachmentID, digest string, target PublicTarget) (Blob, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	r, ok := s.entries[id]
	if !ok || s.failed || s.closed || !r.AssetsVisible || r.Receipt.RemovalState != "none" || !s.now().Before(mustTime(r.Receipt.ContentExpiresAt)) {
		return Blob{}, ErrNotFound
	}
	r, _, err := s.read(id)
	if err != nil {
		return Blob{}, ErrUnavailable
	}
	if r.Submission.Target != target {
		return Blob{}, ErrNotFound
	}
	for _, b := range r.Submission.Blobs {
		if b.Attachment.ID == attachmentID && b.Attachment.SHA256 == digest {
			return b, nil
		}
	}
	return Blob{}, ErrNotFound
}
func (s *PublicStore) Claim() (*PublicJob, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.failed || s.closed {
		return nil, ErrUnavailable
	}
	for id, r := range s.entries {
		if r.Receipt.RemovalState == "removed" && !r.RemovedAt.IsZero() && !s.now().Before(maxTime(mustTime(r.Receipt.AccessExpiresAt), r.RemovedAt).Add(120*24*time.Hour)) {
			if err := os.Remove(filepath.Join(s.dir, id+".json")); err != nil {
				s.failed = true
				return nil, ErrUnavailable
			}
			if err := syncDirectory(s.dir); err != nil {
				s.failed = true
				return nil, ErrUnavailable
			}
			s.used -= s.sizes[id]
			delete(s.sizes, id)
			delete(s.entries, id)
		}
	}
	ids := make([]string, 0, len(s.entries))
	for id := range s.entries {
		ids = append(ids, id)
	}
	sort.Slice(ids, func(i, j int) bool {
		a, b := s.entries[ids[i]], s.entries[ids[j]]
		at, bt := mustTime(a.Receipt.AcceptedAt), mustTime(b.Receipt.AcceptedAt)
		if at.Equal(bt) {
			return ids[i] < ids[j]
		}
		return at.Before(bt)
	})
	for _, id := range ids {
		meta := s.entries[id]
		if s.live[id] || meta.Receipt.RemovalState == "removed" || meta.Receipt.RemovalState == "stalled" {
			continue
		}
		expiry := !s.now().Before(mustTime(meta.Receipt.ContentExpiresAt))
		if meta.Receipt.RemovalState == "none" && !expiry && !closurePending(meta) && (oneOf(meta.Receipt.PublicationState, "stalled", "rejected") || meta.Receipt.PublicationState == "published" && len(meta.Contributions) == 0 && meta.Receipt.PublishedAt != "") {
			continue
		}
		if s.now().Before(meta.NextAttempt) && !(closurePending(meta) && oneOf(meta.Receipt.PublicationState, "stalled", "rejected")) {
			continue
		}
		r, _, err := s.read(id)
		if err != nil {
			return nil, ErrUnavailable
		}
		if expiry && r.Receipt.RemovalState == "none" {
			s.startRemoval(&r, "retention_expired")
			if err = s.save(r); err != nil {
				return nil, err
			}
		}

		if r.ExternalRemoved {
			continue
		}
		if r.Receipt.RemovalState == "none" && oneOf(r.Receipt.PublicationState, "stalled", "rejected") {
			job, e := s.closureJob(&r)
			if e != nil || job != nil {
				return job, e
			}
			continue
		}
		if r.Receipt.PublicationState == "published" && r.Receipt.PublishedAt != "" || r.Receipt.RemovalState != "none" && !r.CreateUncertain {
			job, e := s.contributionJob(&r)
			if e != nil {
				return nil, e
			}
			if job != nil {
				return job, nil
			}
			if r.Receipt.RemovalState == "none" {
				job, e := s.closureJob(&r)
				if e != nil || job != nil {
					return job, e
				}
				continue
			}
			blocked := false
			for _, c := range r.Contributions {
				if !c.Removed {
					blocked = true
				}
			}
			if blocked {
				continue
			}
		}
		if r.Attempts >= 12 || r.Receipt.RemovalState == "none" && r.Receipt.PublicationState != "published" && s.now().Sub(mustTime(r.Receipt.AcceptedAt)) >= 7*24*time.Hour {
			if r.Receipt.RemovalState != "none" {
				r.Receipt.RemovalState = "stalled"
				r.StalledAt = s.now()
			} else {
				r.Receipt.PublicationState = "stalled"
			}
			r.Receipt.Reason = "retry_exhausted"
			if err = s.save(r); err != nil {
				return nil, err
			}
			continue
		}
		action := "create"
		if r.CreateUncertain {
			action = "reconcile"
		} else if r.IssueNumber > 0 {
			action = "verify"
		}
		if r.Receipt.RemovalState != "none" {
			r.Receipt.RemovalState = "pending"
			if r.CreateUncertain {
				action = "reconcile"
			} else if r.IssueNumber > 0 {
				action = "remove"
			} else {
				s.markRemoved(&r)
				if err = s.save(r); err != nil {
					return nil, err
				}
				if r.Receipt.RemovalState == "removed" {
					if err = s.purgeContributions(r); err != nil {
						return nil, err
					}
				}
				continue
			}
		}
		if action == "create" {
			r.AssetsVisible = true
			if len(r.Submission.Blobs) > 0 {
				r.Receipt.PublicationState = "partial"
			}
		}
		r.InFlight = true
		r.Action = action
		r.Attempts++
		r.Generation++
		r.NextAttempt = time.Time{}
		if err = s.save(r); err != nil {
			return nil, err
		}
		s.live[id] = true
		return &PublicJob{ID: id, Record: r, Action: action, Generation: r.Generation}, nil
	}
	return nil, nil
}
func (s *PublicStore) Finish(job PublicJob, result PublicResult) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.failed || s.closed {
		return ErrUnavailable
	}
	r, _, err := s.read(job.ID)
	if err != nil {
		return ErrUnavailable
	}
	if !r.InFlight || r.Generation != job.Generation {
		return ErrConflict
	}
	if !oneOf(result.Outcome, "verified", "mapped", "removed", "closed", "uncertain", "retry", "stalled") || !token(result.Code, 64) {
		return ErrInvalid
	}
	defer delete(s.live, job.ID)
	if job.Action == "close" {
		return s.finishClosure(&r, result)
	}
	if job.Contribution != nil {
		return s.finishContribution(&r, job, result)
	}
	r.InFlight = false
	r.Action = ""
	if result.IssueNumber > 0 {
		r.IssueNumber = result.IssueNumber
		r.IssueNodeID = result.IssueNodeID
		r.Receipt.IssueURL = result.IssueURL
		r.CreateUncertain = false
	}
	removal := r.Receipt.RemovalState != "none"
	switch result.Outcome {
	case "verified":
		if !removal {
			if r.Receipt.PublishedAt == "" {
				r.InputRevision++
				r.Receipt.PublishedAt = s.now().UTC().Format(time.RFC3339Nano)
			}
			r.Receipt.PublicationState = "published"
			r.Receipt.Reason = ""
		}
	case "mapped":
		if !removal {
			r.Receipt.PublicationState = "partial"
		}
		r.Receipt.Reason = "verification_pending"
	case "removed":
		if !removal {
			return ErrInvalid
		}
		s.markRemoved(&r)
	case "uncertain":
		r.CreateUncertain = true
		r.Receipt.Reason = result.Code
	case "retry":
		r.Receipt.Reason = result.Code
	case "stalled":
		if removal {
			r.Receipt.RemovalState = "stalled"
			r.StalledAt = s.now()
		} else {
			r.Receipt.PublicationState = "stalled"
		}
		r.Receipt.Reason = result.Code
	default:
		return ErrInvalid
	}
	if !oneOf(result.Outcome, "verified", "mapped", "removed", "stalled") {
		delay := time.Minute * time.Duration(1<<min(r.Attempts, 8))
		r.NextAttempt = s.now().Add(min(max(delay, result.RetryAfter), 6*time.Hour))
	}
	if removal && r.IssueNumber == 0 && !r.CreateUncertain && oneOf(result.Outcome, "retry", "stalled") {
		s.markRemoved(&r)
	}
	if err = s.save(r); err != nil {
		return err
	}
	if r.Receipt.RemovalState == "removed" {
		return s.purgeContributions(r)
	}
	return nil
}

func maxTime(a, b time.Time) time.Time {
	if a.After(b) {
		return a
	}
	return b
}

func (s *PublicStore) Ready() bool { s.mu.Lock(); defer s.mu.Unlock(); return !s.failed && !s.closed }
