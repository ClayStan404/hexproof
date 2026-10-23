// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package feedback

import (
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"
)

const multicaTestPolicy = "multica-public-v1"

func multicaSubmission(t *testing.T, policy string) PublicSubmission {
	t.Helper()
	_, sub := publicFixture(t)
	sub.Manifest.Disclosure.ProviderPolicyRevision = policy
	sub.ManifestBytes, _ = json.Marshal(sub.Manifest)
	sub.Digest = PublicDigest(sub.ManifestBytes)
	return sub
}

func multicaResult(status string) MulticaDeliveryResult {
	// Native Multica identifiers are UUIDv7, unlike feedback's UUIDv4 case IDs.
	return MulticaDeliveryResult{Status: status, DeliveryID: multicaTestDelivery, RunID: multicaTestRun}
}

func multicaPrepare(t *testing.T, s *PublicStore, id string) *MulticaDelivery {
	t.Helper()
	d, err := s.PrepareMulticaDelivery(id, bridgeTestBinding, multicaTestPolicy)
	if err != nil || d == nil {
		t.Fatalf("prepare: %v, %v", d, err)
	}
	return d
}

func reopenMulticaStore(t *testing.T, s *PublicStore, now *time.Time) *PublicStore {
	t.Helper()
	if err := s.Close(); err != nil {
		t.Fatal(err)
	}
	next, err := openPublicStore(s.dir, Limits{}, func() time.Time { return *now }, nil)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { next.Close() })
	return next
}

func TestMulticaStorePolicyBeforeExport(t *testing.T) {
	for _, policy := range []string{"none-v1", "other-v1"} {
		t.Run(policy, func(t *testing.T) {
			s, _ := publicStoreTest(t)
			sub := multicaSubmission(t, policy)
			finishRoot(t, s, sub)
			id := sub.Manifest.SubmissionID
			if _, err := s.PrepareMulticaDelivery(id, bridgeTestBinding, multicaTestPolicy); !errors.Is(err, ErrInvalid) {
				t.Fatal("unconsented dispatch", err)
			}
			if _, err := s.ExportMulticaCase(id, bridgeTestBinding, multicaTestPolicy); !errors.Is(err, ErrInvalid) {
				t.Fatal("unconsented export", err)
			}
			r := s.entries[id]
			if r.CoordinatorExported || r.CoordinatorBinding != "" || r.MulticaDelivery != nil {
				t.Fatal("rejected policy pinned/exported a case")
			}
		})
	}
	s, _ := publicStoreTest(t)
	sub := multicaSubmission(t, multicaTestPolicy)
	id := sub.Manifest.SubmissionID
	finishRoot(t, s, sub)
	reply := replyFixture(t, sub, replyTestID)
	reply.Manifest.Disclosure.ProviderPolicyRevision = "other-v1"
	reply.ManifestBytes, _ = json.Marshal(reply.Manifest)
	reply.Digest = PublicReplyDigest(reply.ManifestBytes)
	if _, _, err := s.AcceptReply(id, testSecret, reply); err != nil {
		t.Fatal(err)
	}
	snap, err := s.ExportMulticaCase(id, bridgeTestBinding, multicaTestPolicy)
	if err != nil || len(snap.Contributions) != 1 {
		t.Fatal("pending reply blocked public export", snap, err)
	}
	finishChild(t, s, replyTestID)
	if _, err := s.ExportMulticaCase(id, bridgeTestBinding, multicaTestPolicy); !errors.Is(err, ErrInvalid) {
		t.Fatal("published mixed consent exported", err)
	}
	if _, err := s.PrepareMulticaDelivery(id, bridgeTestBinding, multicaTestPolicy); !errors.Is(err, ErrInvalid) {
		t.Fatal("published mixed consent dispatched", err)
	}
}

func TestMulticaStoreUnpublishedCaseDoesNotDispatchOrPin(t *testing.T) {
	s, _ := publicStoreTest(t)
	sub := multicaSubmission(t, "none-v1")
	id := sub.Manifest.SubmissionID
	if _, _, err := s.Accept(testSecret, sub); err != nil {
		t.Fatal(err)
	}
	if d, err := s.PrepareMulticaDelivery(id, bridgeTestBinding, multicaTestPolicy); err != nil || d != nil {
		t.Fatal("unpublished input should wait without policy failure", d, err)
	}
	if _, err := s.ExportMulticaCase(id, bridgeTestBinding, multicaTestPolicy); !errors.Is(err, ErrUnavailable) {
		t.Fatal("unpublished export", err)
	}
	if s.entries[id].CoordinatorExported {
		t.Fatal("unpublished case was pinned")
	}
}

func TestMulticaStoreDurableEventAndRetry(t *testing.T) {
	s, now := publicStoreTest(t)
	sub := multicaSubmission(t, multicaTestPolicy)
	id := sub.Manifest.SubmissionID
	finishRoot(t, s, sub)
	d := multicaPrepare(t, s, id)
	key, event := d.Key, d.Event
	if d.Attempts != 1 || d.Status != "pending" || !d.NextAttempt.Equal(now.Add(time.Minute)) || key != MulticaEventKey(event) {
		t.Fatal(d)
	}
	r, _, err := s.read(id)
	if err != nil || !r.CoordinatorExported || r.CoordinatorBinding != bridgeTestBinding || r.MulticaDelivery.Key != key {
		t.Fatal("outbound was not durably pinned", err)
	}
	raw, _ := json.Marshal(event)
	var fields map[string]any
	_ = json.Unmarshal(raw, &fields)
	if len(fields) != 6 || strings.Contains(string(raw), sub.Manifest.Description) || strings.Contains(string(raw), "github") {
		t.Fatal("event contains more than routing metadata", string(raw))
	}
	d.Key, d.Event.Binding = "changed by caller", "changed by caller"
	if s.entries[id].MulticaDelivery.Key != key || s.entries[id].MulticaDelivery.Event != event {
		t.Fatal("returned mutable pointer escaped store")
	}
	s = reopenMulticaStore(t, s, now)
	if d, err := s.PrepareMulticaDelivery(id, bridgeTestBinding, multicaTestPolicy); err != nil || d != nil {
		t.Fatal("restart forgot retry backoff", d, err)
	}
	*now = now.Add(time.Minute)
	d = multicaPrepare(t, s, id)
	if d.Key != key || d.Event != event || d.Attempts != 2 {
		t.Fatal("retry changed identity", d)
	}
	if err := s.RecordMulticaDelivery(id, bridgeTestBinding, key, multicaResult("accepted")); err != nil {
		t.Fatal(err)
	}
	revision := s.entries[id].ThreadRevision
	if err := s.RecordMulticaDelivery(id, bridgeTestBinding, key, multicaResult("accepted")); err != nil || s.entries[id].ThreadRevision != revision {
		t.Fatal("duplicate receipt wrote again", err)
	}
	s = reopenMulticaStore(t, s, now)
	if s.entries[id].MulticaDelivery.Status != "accepted" {
		t.Fatal("accepted receipt was not durable")
	}
	if err := s.MarkAssessmentDelivery(id, bridgeTestBinding, false, "multica_dispatch_unconfirmed"); err != nil {
		t.Fatal(err)
	}
	p := ProjectionRequest{ID: projectionTestID, WorkflowRevision: 1, ExpectedInputRevision: 1, WorkState: "assessing", Summary: "Public assessment in progress."}
	if _, err := s.EnqueueProjection(id, bridgeTestBinding, p); err != nil {
		t.Fatal(err)
	}
	finishChild(t, s, projectionTestID)
	if s.entries[id].ThreadRevision <= revision || s.entries[id].InputRevision != 1 {
		t.Fatal("fixture did not change only publication metadata")
	}
	if d, err := s.PrepareMulticaDelivery(id, bridgeTestBinding, multicaTestPolicy); err != nil || d != nil {
		t.Fatal("thread/projection change redispatched feedback", d, err)
	}
}

func TestMulticaStoreNewInputWaitsForPendingEvent(t *testing.T) {
	s, now := publicStoreTest(t)
	sub := multicaSubmission(t, multicaTestPolicy)
	id := sub.Manifest.SubmissionID
	finishRoot(t, s, sub)
	first := multicaPrepare(t, s, id)
	reply := replyFixture(t, sub, replyTestID)
	if _, _, err := s.AcceptReply(id, testSecret, reply); err != nil {
		t.Fatal(err)
	}
	snap, err := s.ExportMulticaCase(id, bridgeTestBinding, multicaTestPolicy)
	if err != nil || snap.InputRevision != 1 || len(snap.Contributions) != 1 {
		t.Fatal("pending reply was exported", snap, err)
	}
	finishChild(t, s, replyTestID)
	*now = now.Add(time.Minute)
	retry := multicaPrepare(t, s, id)
	if retry.Key != first.Key || retry.Event.InputRevision != 1 {
		t.Fatal("uncertain older event was replaced by reply", retry)
	}
	if err := s.RecordMulticaDelivery(id, bridgeTestBinding, retry.Key, multicaResult("accepted")); err != nil {
		t.Fatal(err)
	}
	next := multicaPrepare(t, s, id)
	if next.Key == first.Key || next.Event.InputRevision != 2 || next.Attempts != 1 {
		t.Fatal("new published input did not create one fresh event", next)
	}
	snap, err = s.ExportMulticaCase(id, bridgeTestBinding, multicaTestPolicy)
	if err != nil || snap.InputRevision != 2 || len(snap.Contributions) != 2 {
		t.Fatal(snap, err)
	}
}

func TestMulticaStoreSnapshotProjectionWatermark(t *testing.T) {
	s, _ := publicStoreTest(t)
	sub := multicaSubmission(t, multicaTestPolicy)
	id := sub.Manifest.SubmissionID
	finishRoot(t, s, sub)
	d := multicaPrepare(t, s, id)
	if err := s.RecordMulticaDelivery(id, bridgeTestBinding, d.Key, multicaResult("accepted")); err != nil {
		t.Fatal(err)
	}
	p := ProjectionRequest{ID: projectionTestID, WorkflowRevision: 1, ExpectedInputRevision: 1, WorkState: "assessing", Summary: "Unpublished internal transport text must not be copied."}
	if _, err := s.EnqueueProjection(id, bridgeTestBinding, p); err != nil {
		t.Fatal(err)
	}
	check := func(want ProjectionRequest, state string) {
		t.Helper()
		for _, export := range []func() (CaseSnapshot, error){
			func() (CaseSnapshot, error) { return s.ExportCase(id, bridgeTestBinding) },
			func() (CaseSnapshot, error) { return s.ExportMulticaCase(id, bridgeTestBinding, multicaTestPolicy) },
		} {
			snapshot, err := export()
			if err != nil || snapshot.InputRevision != 1 || snapshot.LatestProjection == nil ||
				*snapshot.LatestProjection != (CaseProjectionObservation{ID: want.ID, WorkflowRevision: want.WorkflowRevision, ExpectedInputRevision: 1, PublicationState: state}) {
				t.Fatal("projection watermark missing or wrong", snapshot, err)
			}
			raw, _ := json.Marshal(snapshot)
			if state != "published" && (strings.Contains(string(raw), want.Summary) || want.Question != nil && strings.Contains(string(raw), want.Question.Description)) {
				t.Fatal("snapshot exposed unpublished projection text")
			}
			if state == "published" && (!strings.Contains(string(raw), want.Summary) || len(snapshot.PublishedProjections) == 0) {
				t.Fatal("snapshot omitted the published public conversation")
			}
		}
		if next, err := s.PrepareMulticaDelivery(id, bridgeTestBinding, multicaTestPolicy); err != nil || next != nil {
			t.Fatal("projection observation triggered native notification", next, err)
		}
	}
	check(p, "pending")
	finishChild(t, s, p.ID)
	check(p, "published")
	p = ProjectionRequest{ID: replyTestID, WorkflowRevision: 2, ExpectedInputRevision: 1, WorkState: "needs-information", Summary: "Please supply a public reproduction.", Question: &ProjectionQuestion{ID: questionTestID, Revision: 1, Code: "reproduction_steps", Description: "Unpublished question text.", TimeoutSeconds: 3600}}
	if _, err := s.EnqueueProjection(id, bridgeTestBinding, p); err != nil {
		t.Fatal(err)
	}
	check(p, "pending")
	finishChild(t, s, p.ID)
	check(p, "published")
	if _, err := s.Remove(id, testSecret); err != nil {
		t.Fatal(err)
	}
	snapshot, err := s.ExportMulticaCase(id, bridgeTestBinding, multicaTestPolicy)
	if err != nil || snapshot.LatestProjection != nil || snapshot.QuestionPublication != nil {
		t.Fatal("removed snapshot retained projection metadata", snapshot, err)
	}
}

func TestMulticaStoreTerminalUnconfirmedDelivery(t *testing.T) {
	for _, tc := range []struct {
		name   string
		result MulticaDeliveryResult
	}{
		{"skipped", multicaResult("skipped")},
		{"duplicate", multicaResult("duplicate")},
		{"duplicate without run", MulticaDeliveryResult{Status: "duplicate", DeliveryID: multicaTestDelivery}},
		{"ignored", MulticaDeliveryResult{Status: "ignored", DeliveryID: multicaTestDelivery}},
	} {
		t.Run(tc.name, func(t *testing.T) {
			s, now := publicStoreTest(t)
			sub := multicaSubmission(t, multicaTestPolicy)
			id := sub.Manifest.SubmissionID
			finishRoot(t, s, sub)
			key := multicaPrepare(t, s, id).Key
			if err := s.RecordMulticaDelivery(id, bridgeTestBinding, key, tc.result); err != nil {
				t.Fatal(err)
			}
			s = reopenMulticaStore(t, s, now)
			persisted := s.entries[id].MulticaDelivery
			if persisted.Status != tc.result.Status || persisted.DeliveryID != multicaTestDelivery || persisted.RunID != tc.result.RunID || !persisted.NextAttempt.IsZero() {
				t.Fatal("terminal receipt was not persisted with its identity", persisted)
			}
			*now = now.Add(24 * time.Hour)
			if d, err := s.PrepareMulticaDelivery(id, bridgeTestBinding, multicaTestPolicy); err != nil || d != nil {
				t.Fatal("terminal unconfirmed event retried", d, err)
			}
			for _, late := range []MulticaDeliveryResult{
				multicaResult("accepted"), multicaResult("pending"),
				multicaResult("duplicate"), multicaResult("skipped"),
				{Status: "ignored", DeliveryID: multicaTestDelivery},
			} {
				if late.Status == tc.result.Status && late.RunID == tc.result.RunID {
					continue
				}
				if err := s.RecordMulticaDelivery(id, bridgeTestBinding, key, late); !errors.Is(err, ErrConflict) {
					t.Fatal("late response rewrote a known terminal status", late.Status, err)
				}
			}
			reply := replyFixture(t, sub, replyTestID)
			if _, _, err := s.AcceptReply(id, testSecret, reply); err != nil {
				t.Fatal(err)
			}
			finishChild(t, s, replyTestID)
			next := multicaPrepare(t, s, id)
			if next.Event.InputRevision != 2 || next.Key == key {
				t.Fatal("terminal status blocked fresh user input")
			}
			if _, err := s.Remove(id, testSecret); err != nil {
				t.Fatal(err)
			}
			removed := multicaPrepare(t, s, id)
			if removed.Event.Event != "hexproof.feedback.removed" || removed.Key == next.Key {
				t.Fatal("removal did not supersede the terminal input event", removed)
			}
			if err := s.RecordMulticaDelivery(id, bridgeTestBinding, next.Key, multicaResult("accepted")); !errors.Is(err, ErrConflict) {
				t.Fatal("stale receipt overwrote the removal event", err)
			}
			if err := s.RecordMulticaDelivery(id, bridgeTestBinding, removed.Key, multicaResult("accepted")); err != nil {
				t.Fatal(err)
			}
			r, _, err := s.read(id)
			if err != nil || r.RevocationAcknowledged {
				t.Fatal("withdrawal was falsely acknowledged", err)
			}
		})
	}
}

// An exhausted pending record is unknown, not resolved: newer input waits for
// native reconciliation instead of overwriting its key, association or attempt
// count, across restarts. Removal still supersedes the unknown record.
func TestMulticaStoreExhaustedPendingWaitsForReconciliation(t *testing.T) {
	s, now := publicStoreTest(t)
	sub := multicaSubmission(t, multicaTestPolicy)
	id := sub.Manifest.SubmissionID
	finishRoot(t, s, sub)
	d := multicaPrepare(t, s, id)
	for attempt := 2; attempt <= multicaMaxAttempts; attempt++ {
		*now = d.NextAttempt
		d = multicaPrepare(t, s, id)
		if d.Attempts != attempt {
			t.Fatal("invalid bounded retry", d)
		}
	}
	reply := replyFixture(t, sub, replyTestID)
	if _, _, err := s.AcceptReply(id, testSecret, reply); err != nil {
		t.Fatal(err)
	}
	finishChild(t, s, replyTestID)
	*now = now.Add(24 * time.Hour)
	if next, err := s.PrepareMulticaDelivery(id, bridgeTestBinding, multicaTestPolicy); err != nil || next != nil {
		t.Fatal("newer input retried or overwrote the exhausted unknown record", next, err)
	}
	s = reopenMulticaStore(t, s, now)
	persisted := s.entries[id].MulticaDelivery
	if persisted.Key != d.Key || persisted.Event != d.Event || persisted.Attempts != multicaMaxAttempts || persisted.Status != "pending" {
		t.Fatal("exhausted record lost its key, association or attempts", persisted)
	}
	if _, err := s.Remove(id, testSecret); err != nil {
		t.Fatal(err)
	}
	removed := multicaPrepare(t, s, id)
	if removed.Event.Event != "hexproof.feedback.removed" || removed.Key == d.Key || removed.Attempts != 1 {
		t.Fatal("removal did not supersede the exhausted unknown record", removed)
	}
}

// Invalid or contradictory receipts stay failed closed: none may persist a
// delivery identity or mutate the pending outbox record.
func TestMulticaStoreRejectsInvalidReceiptResults(t *testing.T) {
	s, _ := publicStoreTest(t)
	sub := multicaSubmission(t, multicaTestPolicy)
	id := sub.Manifest.SubmissionID
	finishRoot(t, s, sub)
	key := multicaPrepare(t, s, id).Key
	for name, result := range map[string]MulticaDeliveryResult{
		"unknown status":            {Status: "event_filtered", DeliveryID: multicaTestDelivery},
		"accepted without run":      {Status: "accepted", DeliveryID: multicaTestDelivery},
		"skipped without run":       {Status: "skipped", DeliveryID: multicaTestDelivery},
		"ignored with run":          {Status: "ignored", DeliveryID: multicaTestDelivery, RunID: multicaTestRun},
		"terminal without delivery": {Status: "duplicate", RunID: multicaTestRun},
		"invalid delivery identity": {Status: "duplicate", DeliveryID: "fake", RunID: multicaTestRun},
		"invalid run identity":      {Status: "skipped", DeliveryID: multicaTestDelivery, RunID: "fake"},
		"negative retry delay":      {Status: "pending", RetryAfter: -time.Second},
	} {
		if err := s.RecordMulticaDelivery(id, bridgeTestBinding, key, result); !errors.Is(err, ErrInvalid) {
			t.Fatal(name, err)
		}
	}
	d := s.entries[id].MulticaDelivery
	if d.Status != "pending" || d.DeliveryID != "" || d.RunID != "" || d.Attempts != 1 {
		t.Fatal("invalid receipt mutated the pending event", d)
	}
}

func TestMulticaStoreDeletionSupersedesAndBypassesHistoricalPolicy(t *testing.T) {
	s, now := publicStoreTest(t)
	sub := multicaSubmission(t, multicaTestPolicy)
	id := sub.Manifest.SubmissionID
	finishRoot(t, s, sub)
	old := multicaPrepare(t, s, id)
	if _, err := s.Remove(id, testSecret); err != nil {
		t.Fatal(err)
	}
	if err := s.RecordMulticaDelivery(id, bridgeTestBinding, old.Key, multicaResult("accepted")); !errors.Is(err, ErrConflict) {
		t.Fatal("late ack crossed removal before event replacement", err)
	}
	d, err := s.PrepareMulticaDelivery(id, bridgeTestBinding, "new-policy-v2")
	if err != nil || d == nil || d.Key == old.Key || d.Event.Event != "hexproof.feedback.removed" || d.Event.RevocationRevision < 1 || d.Attempts != 1 {
		t.Fatal("removal waited for old backoff or historical policy", d, err)
	}
	if err := s.RecordMulticaDelivery(id, bridgeTestBinding, old.Key, multicaResult("accepted")); !errors.Is(err, ErrConflict) {
		t.Fatal("late ack overwrote removal", err)
	}
	snap, err := s.ExportMulticaCase(id, bridgeTestBinding, "new-policy-v2")
	if err != nil || snap.State != "removed" || len(snap.Contributions) != 0 || len(snap.Replies) != 0 || snap.IssueURL != "" || snap.RevocationRevision != d.Event.RevocationRevision {
		t.Fatal("removed snapshot leaked content or was policy blocked", snap, err)
	}
	if err := s.RecordMulticaDelivery(id, bridgeTestBinding, d.Key, multicaResult("accepted")); err != nil {
		t.Fatal(err)
	}
	s = reopenMulticaStore(t, s, now)
	r, _, err := s.read(id)
	if err != nil || r.RevocationAcknowledged || !r.CoordinatorExported || r.Submission == nil || r.Receipt.RemovalState == "removed" {
		t.Fatal("dispatch receipt incorrectly proved purge", err)
	}
	if d, err := s.PrepareMulticaDelivery(id, bridgeTestBinding, "new-policy-v2"); err != nil || d != nil {
		t.Fatal("accepted removal redispatched", d, err)
	}
}

func TestMulticaStorePinnedTargetCannotChange(t *testing.T) {
	s, _ := publicStoreTest(t)
	sub := multicaSubmission(t, multicaTestPolicy)
	id := sub.Manifest.SubmissionID
	finishRoot(t, s, sub)
	d := multicaPrepare(t, s, id)
	other := strings.Repeat("b", 64)
	if _, err := s.PrepareMulticaDelivery(id, other, multicaTestPolicy); !errors.Is(err, ErrConflict) {
		t.Fatal(err)
	}
	if _, err := s.ExportMulticaCase(id, other, multicaTestPolicy); !errors.Is(err, ErrConflict) {
		t.Fatal(err)
	}
	if err := s.RecordMulticaDelivery(id, other, d.Key, multicaResult("accepted")); !errors.Is(err, ErrConflict) {
		t.Fatal(err)
	}
	if s.entries[id].CoordinatorBinding != bridgeTestBinding || s.entries[id].MulticaDelivery.Key != d.Key {
		t.Fatal("target mismatch modified destination")
	}
}

func TestMulticaStoreFiniteRetryAndCandidateFairness(t *testing.T) {
	s, now := publicStoreTest(t)
	sub := multicaSubmission(t, multicaTestPolicy)
	id := sub.Manifest.SubmissionID
	finishRoot(t, s, sub)
	d := multicaPrepare(t, s, id)
	for attempt := 2; attempt <= multicaMaxAttempts; attempt++ {
		*now = d.NextAttempt
		next := multicaPrepare(t, s, id)
		if next.Attempts != attempt || next.Key != d.Key || next.NextAttempt.Sub(*now) > 6*time.Hour {
			t.Fatal("invalid bounded retry", next)
		}
		d = next
	}
	s = reopenMulticaStore(t, s, now)
	*now = now.Add(24 * time.Hour)
	if d, err := s.PrepareMulticaDelivery(id, bridgeTestBinding, multicaTestPolicy); err != nil || d != nil {
		t.Fatal("exhausted retry budget reset", d, err)
	}
	// Earlier unconsented and exhausted cases must not occupy the result limit.
	for i, policy := range []string{"none-v1", multicaTestPolicy} {
		next := multicaSubmission(t, policy)
		next.Manifest.SubmissionID = fmt.Sprintf("00000000-0000-4000-8000-%012d", i+1)
		next.ManifestBytes, _ = json.Marshal(next.Manifest)
		next.Digest = PublicDigest(next.ManifestBytes)
		finishRoot(t, s, next)
	}
	ids, err := s.ListMulticaCandidates(bridgeTestBinding, multicaTestPolicy, 1)
	if err != nil || len(ids) != 1 || ids[0] != "00000000-0000-4000-8000-000000000002" {
		t.Fatal("blocked earlier case starved later input", ids, err)
	}
	ids, err = s.ListMulticaCandidates(bridgeTestBinding, multicaTestPolicy, 0)
	if err != nil || len(ids) != 3 {
		t.Fatal("zero limit should expose bounded index for health checks", ids, err)
	}
	if _, err := s.Remove(id, testSecret); err != nil {
		t.Fatal(err)
	}
	removed := multicaPrepare(t, s, id)
	if removed.Attempts != 1 || removed.Event.Event != "hexproof.feedback.removed" {
		t.Fatal("exhausted changed event blocked removal", removed)
	}
}

func TestMulticaStoreConcurrentPreparationAndPersistenceFailure(t *testing.T) {
	s, now := publicStoreTest(t)
	sub := multicaSubmission(t, multicaTestPolicy)
	id := sub.Manifest.SubmissionID
	finishRoot(t, s, sub)
	var wg sync.WaitGroup
	results := make(chan *MulticaDelivery, 12)
	errs := make(chan error, 12)
	for i := 0; i < 12; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			d, err := s.PrepareMulticaDelivery(id, bridgeTestBinding, multicaTestPolicy)
			results <- d
			errs <- err
		}()
	}
	wg.Wait()
	close(results)
	close(errs)
	count := 0
	for d := range results {
		if d != nil {
			count++
		}
	}
	for err := range errs {
		if err != nil {
			t.Fatal(err)
		}
	}
	if count != 1 || s.entries[id].MulticaDelivery.Attempts != 1 {
		t.Fatal("concurrent preparation dispatched twice", count)
	}
	*now = now.Add(time.Minute)
	s.fault = func(string) error { return errors.New("simulated disk failure") }
	if d, err := s.PrepareMulticaDelivery(id, bridgeTestBinding, multicaTestPolicy); !errors.Is(err, ErrUnavailable) || d != nil {
		t.Fatal("failed persistence allowed network dispatch", d, err)
	}
	s = reopenMulticaStore(t, s, now)
	if s.entries[id].MulticaDelivery.Attempts != 1 {
		t.Fatal("failed attempt mutated durable state")
	}
}

func TestMulticaStoreRejectsCorruptPersistedDelivery(t *testing.T) {
	s, now := publicStoreTest(t)
	sub := multicaSubmission(t, multicaTestPolicy)
	id := sub.Manifest.SubmissionID
	finishRoot(t, s, sub)
	multicaPrepare(t, s, id)
	r, _, err := s.read(id)
	if err != nil {
		t.Fatal(err)
	}
	r.MulticaDelivery.Key = strings.Repeat("f", 64)
	raw, _ := json.Marshal(r)
	if err := s.Close(); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(s.dir, id+".json"), raw, 0600); err != nil {
		t.Fatal(err)
	}
	if reopened, err := openPublicStore(s.dir, Limits{}, func() time.Time { return *now }, nil); !errors.Is(err, ErrInvalid) {
		if reopened != nil {
			reopened.Close()
		}
		t.Fatal("corrupt persisted idempotency key accepted", err)
	}
}
