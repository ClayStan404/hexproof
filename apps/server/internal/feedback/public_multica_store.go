// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package feedback

import (
	"encoding/json"
	"sort"
	"time"
)

const multicaMaxAttempts = 12

// MulticaEvent wakes the native platform without transmitting feedback content.
type MulticaEvent struct {
	SchemaVersion      int    `json:"schemaVersion"`
	Event              string `json:"event"`
	CaseID             string `json:"caseId"`
	Binding            string `json:"binding"`
	InputRevision      int64  `json:"inputRevision"`
	RevocationRevision int64  `json:"revocationRevision"`
}

// MulticaDelivery is a single receiver outbox record, not a native task record.
type MulticaDelivery struct {
	Event       MulticaEvent `json:"event"`
	Key         string       `json:"key"`
	Attempts    int          `json:"attempts"`
	NextAttempt time.Time    `json:"nextAttempt,omitempty"`
	Status      string       `json:"status"`
	DeliveryID  string       `json:"deliveryId,omitempty"`
	RunID       string       `json:"runId,omitempty"`
}

type MulticaDeliveryResult struct {
	Status     string
	DeliveryID string
	RunID      string
	RetryAfter time.Duration
}

func MulticaEventKey(event MulticaEvent) string {
	raw, _ := json.Marshal(event)
	return hashBytes(append([]byte(event.Binding+"\n"), raw...))
}

func validMulticaEvent(event MulticaEvent) bool {
	return event.SchemaVersion == 1 && validID(event.CaseID) && validHash(event.Binding) && event.InputRevision >= 1 &&
		(event.Event == "hexproof.feedback.changed" && event.RevocationRevision == 0 ||
			event.Event == "hexproof.feedback.removed" && event.RevocationRevision >= 1)
}

func validMulticaDelivery(r PublicRecord) bool {
	d := r.MulticaDelivery
	if d == nil {
		return true
	}
	return validMulticaEvent(d.Event) && d.Event.CaseID == r.Receipt.SubmissionID &&
		r.CoordinatorExported && d.Event.Binding == r.CoordinatorBinding &&
		d.Event.InputRevision <= r.InputRevision && d.Key == MulticaEventKey(d.Event) &&
		d.Attempts >= 1 && d.Attempts <= multicaMaxAttempts && oneOf(d.Status, "pending", "accepted", "skipped", "duplicate", "ignored") &&
		(d.DeliveryID == "" || multicaUUID(d.DeliveryID)) && (d.RunID == "" || multicaUUID(d.RunID)) &&
		(d.Status == "pending" || d.DeliveryID != "") &&
		(oneOf(d.Status, "pending", "duplicate", "ignored") || d.RunID != "") &&
		(d.Status != "ignored" || d.RunID == "") &&
		(d.Status == "pending" || d.NextAttempt.IsZero()) &&
		(d.Event.Event != "hexproof.feedback.removed" || d.Event.RevocationRevision == r.RevocationRevision && r.Receipt.RemovalState != "none")
}

func validMulticaPolicy(policy string) bool {
	return publicRevisionPattern.MatchString(policy) && policy != "none-v1"
}

// Policy is checked against immutable manifests before binding or exporting.
// Pending replies are not exported and cannot authorize or block public input.
func (s *PublicStore) multicaPolicy(r PublicRecord, policy string) error {
	if !validMulticaPolicy(policy) || r.Submission == nil ||
		r.Submission.Manifest.Disclosure.ProviderPolicyRevision != policy {
		return ErrInvalid
	}
	for _, c := range r.Contributions {
		if c.Kind != "reply" || c.Receipt.PublicationState != "published" {
			continue
		}
		p, err := s.payload(r.Receipt.SubmissionID, c)
		if err != nil {
			return err
		}
		if p.Reply.Manifest.Disclosure.ProviderPolicyRevision != policy {
			return ErrInvalid
		}
	}
	return nil
}

func (s *PublicStore) multicaRecord(id, binding, policy string) (PublicRecord, error) {
	if !validMulticaPolicy(policy) {
		return PublicRecord{}, ErrInvalid
	}
	r, err := s.loadBridgeCase(id, binding)
	if err != nil {
		return r, err
	}
	if !validMulticaDelivery(r) {
		return r, ErrInvalid
	}
	// Revocation sends only metadata and exports an empty tombstone. Historical
	// consent must never prevent cleanup at the already pinned destination.
	if r.Receipt.RemovalState != "none" || r.Receipt.CaseState == "closed" {
		return r, nil
	}
	if r.Receipt.PublicationState != "published" || r.Receipt.PublishedAt == "" {
		return r, nil
	}
	if err := s.multicaPolicy(r, policy); err != nil {
		return r, err
	}
	return r, nil
}

func (s *PublicStore) multicaEvent(r PublicRecord, binding string) (*MulticaEvent, error) {
	if r.Receipt.RemovalState != "none" {
		if !r.CoordinatorExported || r.RevocationAcknowledged {
			return nil, nil
		}
		if r.RevocationRevision < 1 || r.InputRevision < 1 {
			return nil, ErrInvalid
		}
		return &MulticaEvent{SchemaVersion: 1, Event: "hexproof.feedback.removed", CaseID: r.Receipt.SubmissionID, Binding: binding, InputRevision: r.InputRevision, RevocationRevision: r.RevocationRevision}, nil
	}
	if r.Receipt.CaseState == "closed" {
		if !r.CoordinatorExported {
			return nil, nil
		}
		return &MulticaEvent{SchemaVersion: 1, Event: "hexproof.feedback.changed", CaseID: r.Receipt.SubmissionID, Binding: binding, InputRevision: r.InputRevision}, nil
	}
	if r.Receipt.PublicationState != "published" || r.Receipt.PublishedAt == "" {
		return nil, nil
	}
	if !s.now().Before(mustTime(r.Receipt.ContentExpiresAt)) {
		return nil, ErrExpired
	}
	if r.InputRevision < 1 {
		return nil, ErrInvalid
	}
	return &MulticaEvent{SchemaVersion: 1, Event: "hexproof.feedback.changed", CaseID: r.Receipt.SubmissionID, Binding: binding, InputRevision: r.InputRevision}, nil
}

func (s *PublicStore) multicaDue(r PublicRecord, desired *MulticaEvent) bool {
	if desired == nil {
		return false
	}
	d := r.MulticaDelivery
	if d == nil || desired.Event == "hexproof.feedback.removed" && d.Event.Event != desired.Event ||
		r.Receipt.CaseState == "closed" && d.Event.InputRevision < desired.InputRevision {
		return true
	}
	if d.Status == "pending" {
		return d.Attempts < multicaMaxAttempts && !s.now().Before(d.NextAttempt)
	}
	return d.Event != *desired
}

// A zero limit returns the bounded case index so a caller can report rejected
// policies or changed targets without starving later eligible cases. A positive
// limit is applied only after eligibility and due-time filtering.
func (s *PublicStore) ListMulticaCandidates(binding, policy string, limit int) ([]string, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.failed || s.closed {
		return nil, ErrUnavailable
	}
	if !validHash(binding) || !validMulticaPolicy(policy) || limit < 0 || limit > 128 {
		return nil, ErrInvalid
	}
	ids := make([]string, 0, len(s.entries))
	for id := range s.entries {
		ids = append(ids, id)
	}
	sort.Strings(ids)
	if limit == 0 {
		return ids, nil
	}
	out := make([]string, 0, limit)
	for _, id := range ids {
		r, err := s.multicaRecord(id, binding, policy)
		if err != nil {
			continue
		}
		event, err := s.multicaEvent(r, binding)
		if err != nil || !s.multicaDue(r, event) {
			continue
		}
		out = append(out, id)
		if len(out) == limit {
			break
		}
	}
	return out, nil
}

func multicaRetryDelay(attempt int) time.Duration {
	return min(time.Minute*time.Duration(1<<min(max(attempt-1, 0), 9)), 6*time.Hour)
}

// Prepare persists the export obligation and the attempt before network I/O.
// New input waits behind an uncertain event; deletion supersedes that event.
func (s *PublicStore) PrepareMulticaDelivery(id, binding, policy string) (*MulticaDelivery, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	r, err := s.multicaRecord(id, binding, policy)
	if err != nil {
		return nil, err
	}
	event, err := s.multicaEvent(r, binding)
	if err != nil || !s.multicaDue(r, event) {
		return nil, err
	}
	var d MulticaDelivery
	if r.MulticaDelivery != nil && r.MulticaDelivery.Status == "pending" &&
		!(event.Event == "hexproof.feedback.removed" && r.MulticaDelivery.Event.Event != event.Event) &&
		!(r.Receipt.CaseState == "closed" && r.MulticaDelivery.Event.InputRevision < event.InputRevision) {
		d = *r.MulticaDelivery
	} else {
		d = MulticaDelivery{Event: *event, Key: MulticaEventKey(*event), Status: "pending"}
	}
	d.Attempts++
	d.NextAttempt = s.now().UTC().Add(multicaRetryDelay(d.Attempts))
	r.CoordinatorBinding, r.CoordinatorExported = binding, true
	r.MulticaDelivery = &d
	if err := s.save(r); err != nil {
		return nil, err
	}
	copy := d
	return &copy, nil
}

// A late response must never acknowledge a replaced deletion event. A skipped
// native run remains skipped even if a later duplicate response names that run.
func (s *PublicStore) RecordMulticaDelivery(id, binding, key string, result MulticaDeliveryResult) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	r, err := s.loadBridgeCase(id, binding)
	if err != nil {
		return err
	}
	if !validMulticaDelivery(r) {
		return ErrInvalid
	}
	if r.MulticaDelivery == nil || r.MulticaDelivery.Key != key ||
		r.Receipt.RemovalState != "none" && r.MulticaDelivery.Event.Event == "hexproof.feedback.changed" ||
		r.Receipt.CaseState == "closed" && r.MulticaDelivery.Event.InputRevision < r.InputRevision {
		return ErrConflict
	}
	if !oneOf(result.Status, "pending", "accepted", "skipped", "duplicate", "ignored") || result.RetryAfter < 0 ||
		(result.DeliveryID != "" && !multicaUUID(result.DeliveryID)) || (result.RunID != "" && !multicaUUID(result.RunID)) ||
		(result.Status != "pending" && result.DeliveryID == "") ||
		(oneOf(result.Status, "accepted", "skipped") && result.RunID == "") ||
		(result.Status == "ignored" && result.RunID != "") {
		return ErrInvalid
	}
	d := *r.MulticaDelivery
	if d.Status != "pending" {
		if d.Status == result.Status && d.DeliveryID == result.DeliveryID && d.RunID == result.RunID {
			return nil
		}
		return ErrConflict
	}
	if d.DeliveryID != "" && result.DeliveryID != "" && d.DeliveryID != result.DeliveryID ||
		d.RunID != "" && result.RunID != "" && d.RunID != result.RunID {
		return ErrConflict
	}
	d.Status = result.Status
	if result.DeliveryID != "" {
		d.DeliveryID = result.DeliveryID
	}
	if result.RunID != "" {
		d.RunID = result.RunID
	}
	if result.Status == "pending" {
		d.NextAttempt = maxTime(d.NextAttempt, s.now().UTC().Add(min(result.RetryAfter, 6*time.Hour)))
	} else {
		d.NextAttempt = time.Time{}
	}
	if d == *r.MulticaDelivery {
		return nil
	}
	r.MulticaDelivery = &d
	return s.save(r)
}

// ExportMulticaCase checks all published manifests under the same store lock
// used to pin the destination and construct the public-only snapshot.
func (s *PublicStore) ExportMulticaCase(id, binding, policy string) (CaseSnapshot, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	r, err := s.multicaRecord(id, binding, policy)
	if err != nil {
		return CaseSnapshot{}, err
	}
	if r.Receipt.RemovalState != "none" {
		if !r.CoordinatorExported {
			return CaseSnapshot{}, ErrExpired
		}
		return s.caseSnapshotForRecord(r)
	}
	if r.Receipt.CaseState == "closed" {
		return s.caseSnapshotForRecord(r)
	}
	if r.Receipt.PublicationState != "published" || r.Receipt.PublishedAt == "" || !s.now().Before(mustTime(r.Receipt.ContentExpiresAt)) {
		return CaseSnapshot{}, ErrUnavailable
	}
	if r.CoordinatorBinding == "" {
		r.CoordinatorBinding, r.CoordinatorExported = binding, true
		if err := s.save(r); err != nil {
			return CaseSnapshot{}, err
		}
		r.ThreadRevision = s.entries[id].ThreadRevision
	}
	return s.caseSnapshotForRecord(r)
}
