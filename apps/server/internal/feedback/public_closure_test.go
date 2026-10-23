// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package feedback

import (
	"bytes"
	"encoding/base64"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"
)

func closeRequest(h http.Handler, id string, secret []byte, body string) *httptest.ResponseRecorder {
	r := httptest.NewRequest("POST", "http://localhost/feedback/v2/submissions/"+id+"/close", strings.NewReader(body))
	r.Header.Set("Authorization", "Feedback "+base64.RawURLEncoding.EncodeToString(secret))
	w := httptest.NewRecorder()
	h.ServeHTTP(w, r)
	return w
}

func TestPublicCloseHTTPRetainsHistoryAndRejectsNewFollowup(t *testing.T) {
	c, sub := publicFixture(t)
	s, _ := publicStoreTest(t)
	finishRoot(t, s, sub)
	id := sub.Manifest.SubmissionID
	reply := replyFixture(t, sub, replyTestID)
	if _, _, err := s.AcceptReply(id, testSecret, reply); err != nil {
		t.Fatal(err)
	}
	finishChild(t, s, replyTestID)
	h := NewPublicHandler(s, c, nil, Limits{}, nil)
	defer h.Close()
	for _, invalid := range []string{"{}", " ", "untrusted body"} {
		if w := closeRequest(h, id, testSecret, invalid); w.Code != 400 {
			t.Fatal(w.Code, w.Body.String())
		}
	}
	if w := closeRequest(h, id, bytes.Repeat([]byte{9}, 32), ""); w.Code != 404 {
		t.Fatal(w.Code)
	}
	before := s.entries[id].InputRevision
	var closed PublicReceipt
	for range 2 {
		w := closeRequest(h, id, testSecret, "")
		if w.Code != 200 || json.Unmarshal(w.Body.Bytes(), &closed) != nil || closed.CaseState != "closed" || closed.ClosurePublicationState != "pending" || closed.RemovalState != "none" || closed.ClosedAt == "" {
			t.Fatal(w.Code, w.Body.String())
		}
	}
	if s.entries[id].InputRevision != before+1 {
		t.Fatal("idempotent close changed the input revision again")
	}
	thread, err := s.Thread(id, testSecret, "", 5)
	if err != nil || thread.CaseState != "closed" || thread.ClosurePublicationState != "pending" || thread.ClosedAt != closed.ClosedAt || len(thread.Items) != 2 || thread.Items[0].Description != sub.Manifest.Description || thread.Items[1].Description != reply.Manifest.Description || thread.Question != nil {
		t.Fatal(thread, err)
	}
	if w := replyPut(t, h, replyFixture(t, sub, questionTestID), testSecret); w.Code != 410 {
		t.Fatal("closed case accepted a new reply", w.Code, w.Body.String())
	}
	if w := replyPut(t, h, reply, testSecret); w.Code != 200 || !strings.Contains(w.Body.String(), `"caseState":"closed"`) {
		t.Fatal("accepted reply retry lost its receipt", w.Code, w.Body.String())
	}
	if w := publicRequest(h, "GET", id+"/close", sub, testSecret); w.Code != 405 {
		t.Fatal(w.Code)
	}
}

func TestPublicCloseKeepsApprovedPublicationsAndAssets(t *testing.T) {
	c, sub := publicFixture(t)
	s, _ := publicStoreTest(t)
	attachment := Attachment{ID: "00000000-0000-4000-8000-000000000011", Kind: "log", MediaType: "text/plain", ByteLength: 7, SHA256: hashBytes([]byte("fixture"))}
	sub.Manifest.Attachments = []Attachment{attachment}
	sub.ManifestBytes, _ = json.Marshal(sub.Manifest)
	sub.Digest = PublicDigest(sub.ManifestBytes)
	sub.Blobs = []Blob{{Attachment: attachment, Bytes: []byte("fixture")}}
	if _, _, err := s.Accept(testSecret, sub); err != nil {
		t.Fatal(err)
	}
	id := sub.Manifest.SubmissionID
	if _, err := s.CloseCase(id, testSecret); err != nil {
		t.Fatal(err)
	}
	j, err := s.Claim()
	if err != nil || j == nil || j.Action != "create" {
		t.Fatal("approved root publication was discarded", j, err)
	}
	if err = s.Finish(*j, PublicResult{Outcome: "mapped", IssueNumber: 42, IssueNodeID: "NODE42", IssueURL: "https://github.com/example/project/issues/42"}); err != nil {
		t.Fatal(err)
	}
	j, err = s.Claim()
	if err != nil || j == nil || j.Action != "verify" {
		t.Fatal(j, err)
	}
	if err = s.Finish(*j, PublicResult{Outcome: "verified"}); err != nil {
		t.Fatal(err)
	}
	if blob, err := s.Asset(id, attachment.ID, attachment.SHA256, c.target()); err != nil || string(blob.Bytes) != "fixture" {
		t.Fatal("close hid retained public assets", blob, err)
	}
	reply := replyFixture(t, sub, replyTestID)
	if _, _, err = s.AcceptReply(id, testSecret, reply); !errors.Is(err, ErrExpired) {
		t.Fatal("store admitted a reply after closure", err)
	}
	j, err = s.Claim()
	if err != nil || j == nil || j.Action != "close" {
		t.Fatal(j, err)
	}
	if err = s.Finish(*j, PublicResult{Outcome: "closed"}); err != nil {
		t.Fatal(err)
	}
	r, _, err := s.read(id)
	if err != nil || r.Submission == nil || len(r.Submission.Blobs) != 1 || r.Receipt.RemovalState != "none" || r.Receipt.ClosurePublicationState != "closed" || r.CoordinatorExported || r.RevocationAcknowledged {
		t.Fatal("closure changed content/removal obligations", r, err)
	}
}

func TestPublicCloseReconcilesAcceptedRepliesAndUncertainProjection(t *testing.T) {
	_, sub := publicFixture(t)
	s, _ := publicStoreTest(t)
	finishRoot(t, s, sub)
	id := sub.Manifest.SubmissionID
	snapshot, err := s.ExportCase(id, bridgeTestBinding)
	if err != nil {
		t.Fatal(err)
	}
	p := deliveryProjectionFixture(snapshot, "ready", 1)
	if _, err = s.EnqueueProjection(id, bridgeTestBinding, p); err != nil {
		t.Fatal(err)
	}
	j, err := s.Claim()
	if err != nil || j == nil || j.Action != "comment-create" {
		t.Fatal(j, err)
	}
	reply := replyFixture(t, sub, replyTestID)
	if _, _, err = s.AcceptReply(id, testSecret, reply); err != nil {
		t.Fatal(err)
	}
	if _, err = s.CloseCase(id, testSecret); err != nil {
		t.Fatal(err)
	}
	if err = s.Finish(*j, PublicResult{Outcome: "uncertain", Code: "comment_creation_uncertain"}); err != nil {
		t.Fatal(err)
	}
	// Retry timing belongs to the admitted write; closure does not bypass it.
	s.mu.Lock()
	r, _, _ := s.read(id)
	r.Contributions[0].NextAttempt = time.Time{}
	if err = s.save(r); err != nil {
		t.Fatal(err)
	}
	s.mu.Unlock()
	j, err = s.Claim()
	if err != nil || j == nil || j.Action != "comment-reconcile" || j.Contribution.ID != p.ID {
		t.Fatal("uncertain official write was discarded or recreated", j, err)
	}
	if err = s.Finish(*j, PublicResult{Outcome: "mapped", CommentID: 101, CommentNodeID: "COMMENT101"}); err != nil {
		t.Fatal(err)
	}
	j, err = s.Claim()
	if err != nil || j == nil || j.Action != "comment-verify" {
		t.Fatal(j, err)
	}
	if err = s.Finish(*j, PublicResult{Outcome: "verified"}); err != nil {
		t.Fatal(err)
	}
	finishChild(t, s, replyTestID)
	if _, err = s.EnqueueProjection(id, bridgeTestBinding, p); !errors.Is(err, ErrExpired) {
		t.Fatal("stale projection retry was accepted", err)
	}
	j, err = s.Claim()
	if err != nil || j == nil || j.Action != "close" {
		t.Fatal("closure did not follow accepted publications", j, err)
	}
}

func TestPublicCloseSuppressesUnadmittedProjectionAndPreservesRemoval(t *testing.T) {
	_, sub := publicFixture(t)
	s, _ := publicStoreTest(t)
	finishRoot(t, s, sub)
	id := sub.Manifest.SubmissionID
	snapshot, _ := s.ExportCase(id, bridgeTestBinding)
	p := deliveryProjectionFixture(snapshot, "ready", 1)
	if _, err := s.EnqueueProjection(id, bridgeTestBinding, p); err != nil {
		t.Fatal(err)
	}
	if _, err := s.CloseCase(id, testSecret); err != nil {
		t.Fatal(err)
	}
	r, _, _ := s.read(id)
	if r.Contributions[0].Receipt.PublicationState != "rejected" || r.Contributions[0].Receipt.Reason != "case_closed" {
		t.Fatal("unadmitted official work was left publishable", r.Contributions)
	}
	snapshot, err := s.ExportCase(id, bridgeTestBinding)
	if err != nil || snapshot.State != "closed" || snapshot.IssueURL != "" || len(snapshot.Contributions) != 0 || len(snapshot.Replies) != 0 || snapshot.LatestProjection != nil || snapshot.QuestionPublication != nil {
		t.Fatal("closed snapshot exposed retained content", snapshot, err)
	}
	if err := s.AcknowledgeRevocation(id, bridgeTestBinding, 1); !errors.Is(err, ErrConflict) {
		t.Fatal("close enabled purge acknowledgment", err)
	}
	j, err := s.Claim()
	if err != nil || j == nil || j.Action != "close" {
		t.Fatal("normal closure waited for native purge", j, err)
	}
	if err = s.Finish(*j, PublicResult{Outcome: "closed"}); err != nil {
		t.Fatal(err)
	}
	r, _, _ = s.read(id)
	if r.Receipt.ClosurePublicationState != "closed" || r.Receipt.RemovalState != "none" || r.RevocationAcknowledged || !r.CoordinatorExported || r.Submission == nil {
		t.Fatal("normal closure asserted content removal", r)
	}
	if _, err := s.Remove(id, testSecret); err != nil {
		t.Fatal(err)
	}
	for range 3 {
		j, err := s.Claim()
		if err != nil {
			t.Fatal(err)
		}
		if j == nil {
			break
		}
		if j.Action == "close" {
			t.Fatal("closure outranked content removal")
		}
		if err = s.Finish(*j, PublicResult{Outcome: "removed"}); err != nil {
			t.Fatal(err)
		}
	}
	r, _, _ = s.read(id)
	if r.Receipt.RemovalState != "pending" || r.Receipt.Reason != "coordinator_cleanup_pending" || r.RevocationAcknowledged || r.CoordinatorBinding != bridgeTestBinding || r.RevocationRevision < 1 {
		t.Fatal("close discharged existing purge obligation", r)
	}
}

func TestPublicCloseLoadRejectsInvalidState(t *testing.T) {
	for _, corrupt := range []string{"unknown-case", "open-closed-time", "unknown-publication", "closed-without-time", "negative-attempts"} {
		t.Run(corrupt, func(t *testing.T) {
			_, sub := publicFixture(t)
			s, now := publicStoreTest(t)
			if _, _, err := s.Accept(testSecret, sub); err != nil {
				t.Fatal(err)
			}
			r, _, _ := s.read(sub.Manifest.SubmissionID)
			switch corrupt {
			case "unknown-case":
				r.Receipt.CaseState = "unknown"
			case "open-closed-time":
				r.Receipt.ClosedAt = now.UTC().Format(time.RFC3339Nano)
			case "unknown-publication":
				r.Receipt.ClosurePublicationState = "unknown"
			case "closed-without-time":
				r.Receipt.CaseState, r.Receipt.ClosurePublicationState = "closed", "pending"
			case "negative-attempts":
				r.CloseAttempts = -1
			}
			if err := atomicJSON(s.dir, sub.Manifest.SubmissionID+".json", r); err != nil {
				t.Fatal(err)
			}
			if err := s.Close(); err != nil {
				t.Fatal(err)
			}
			opened, err := openPublicStore(s.dir, Limits{}, func() time.Time { return *now }, nil)
			if err == nil {
				opened.Close()
				t.Fatal("invalid closure metadata was accepted")
			}
		})
	}
}

func TestPublicCloseRestartReconcilesCloseAndOldRecordDefaults(t *testing.T) {
	_, sub := publicFixture(t)
	s, now := publicStoreTest(t)
	finishRoot(t, s, sub)
	id := sub.Manifest.SubmissionID
	// Simulate a record written before closure fields existed.
	r, _, _ := s.read(id)
	r.Receipt.CaseState, r.Receipt.ClosurePublicationState = "", ""
	if err := atomicJSON(s.dir, id+".json", r); err != nil {
		t.Fatal(err)
	}
	s = reopenMulticaStore(t, s, now)
	old, _ := s.Lookup(id, testSecret, "")
	if old.CaseState != "open" || old.ClosurePublicationState != "none" {
		t.Fatal(old)
	}
	if _, err := s.CloseCase(id, testSecret); err != nil {
		t.Fatal(err)
	}
	j, err := s.Claim()
	if err != nil || j == nil || j.Action != "close" {
		t.Fatal(j, err)
	}
	s = reopenMulticaStore(t, s, now)
	j, err = s.Claim()
	if err != nil || j == nil || j.Action != "close" || j.Record.CreateUncertain {
		t.Fatal("close restart became a create or false completion", j, err)
	}
	if err = s.Finish(*j, PublicResult{Outcome: "closed"}); err != nil {
		t.Fatal(err)
	}
	s = reopenMulticaStore(t, s, now)
	closed, _ := s.Lookup(id, testSecret, "")
	if closed.CaseState != "closed" || closed.ClosurePublicationState != "closed" || closed.RemovalState != "none" {
		t.Fatal(closed)
	}
	if _, err := os.Stat(filepath.Join(s.dir, id+".json")); err != nil {
		t.Fatal("close removed retained record", err)
	}
}

func TestPublicCloseRetryBudgetAndRetentionAreIndependent(t *testing.T) {
	_, sub := publicFixture(t)
	s, now := publicStoreTest(t)
	finishRoot(t, s, sub)
	id := sub.Manifest.SubmissionID
	if _, err := s.CloseCase(id, testSecret); err != nil {
		t.Fatal(err)
	}
	for range 12 {
		j, err := s.Claim()
		if err != nil || j == nil || j.Action != "close" {
			t.Fatal(j, err)
		}
		if err = s.Finish(*j, PublicResult{Outcome: "retry", Code: "closure_verification_unavailable"}); err != nil {
			t.Fatal(err)
		}
		*now = now.Add(6 * time.Hour)
		if _, err = s.CloseCase(id, testSecret); err != nil {
			t.Fatal(err)
		}
	}
	if j, err := s.Claim(); err != nil || j != nil {
		t.Fatal(j, err)
	}
	r, _, _ := s.read(id)
	if r.CloseAttempts != 12 || r.Receipt.ClosurePublicationState != "stalled" || r.Receipt.ClosureReason != "closure_retry_exhausted" || r.Submission == nil || r.Receipt.RemovalState != "none" {
		t.Fatal(r)
	}
	*now = mustTime(r.Receipt.ContentExpiresAt)
	j, err := s.Claim()
	if err != nil || j == nil || j.Action != "remove" {
		t.Fatal("closed case escaped ordinary content expiry", j, err)
	}
}

func TestPublicCloseConcurrentAdmissionCannotResume(t *testing.T) {
	_, sub := publicFixture(t)
	s, _ := publicStoreTest(t)
	finishRoot(t, s, sub)
	id := sub.Manifest.SubmissionID
	snapshot, _ := s.ExportCase(id, bridgeTestBinding)
	var group sync.WaitGroup
	for i := range 24 {
		group.Add(1)
		go func(i int) {
			defer group.Done()
			if i%2 == 0 {
				if _, err := s.CloseCase(id, testSecret); err != nil {
					t.Error(err)
				}
				return
			}
			p := deliveryProjectionFixture(snapshot, "ready", int64(i+1))
			if _, err := s.EnqueueProjection(id, bridgeTestBinding, p); err != nil && !errors.Is(err, ErrExpired) && !errors.Is(err, ErrConflict) {
				t.Error(err)
			}
		}(i)
	}
	group.Wait()
	r, _, _ := s.read(id)
	if r.InputRevision != snapshot.InputRevision+1 || r.Receipt.CaseState != "closed" {
		t.Fatal(r.Receipt, r.InputRevision)
	}
	if _, err := s.EnqueueProjection(id, bridgeTestBinding, deliveryProjectionFixture(snapshot, "ready", 100)); !errors.Is(err, ErrExpired) {
		t.Fatal(err)
	}
	j, err := s.Claim()
	if err != nil || j == nil || j.Action != "close" {
		t.Fatal("closed concurrent projection remained publishable", j, err)
	}
}
