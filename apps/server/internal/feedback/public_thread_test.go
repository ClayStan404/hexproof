// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package feedback

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"testing"
	"time"
)

const replyTestID = "7db5e5ef-44ed-40d0-9e60-77856d33d006"
const questionTestID = "32248021-a93a-470f-93d4-f35b4dbdc756"
const projectionTestID = "30ab4044-6458-48af-ac9b-015fba88eb32"

var bridgeTestBinding = strings.Repeat("a", 64)

// projectionID gives isolated publication fixtures stable idempotency keys.
func projectionID(binding, id string, revision int64) string {
	d := sha256.Sum256([]byte(binding + "\n" + id + "\n" + strconv.FormatInt(revision, 10)))
	d[6] = (d[6] & 0x0f) | 0x40
	d[8] = (d[8] & 0x3f) | 0x80
	s := hex.EncodeToString(d[:16])
	return s[:8] + "-" + s[8:12] + "-" + s[12:16] + "-" + s[16:20] + "-" + s[20:]
}

func replyFixture(t *testing.T, parent PublicSubmission, id string) PublicSubmission {
	t.Helper()
	s := parent
	s.Manifest.SubmissionID = id
	s.Manifest.ParentSubmissionID = parent.Manifest.SubmissionID
	s.Manifest.Description = "Additional public evidence."
	s.ManifestBytes, _ = json.Marshal(s.Manifest)
	s.Digest = PublicReplyDigest(s.ManifestBytes)
	return s
}
func replyPut(t *testing.T, h http.Handler, sub PublicSubmission, secret []byte) *httptest.ResponseRecorder {
	t.Helper()
	body, kind := multipartBody(t, sub.ManifestBytes, sub.Blobs)
	r := httptest.NewRequest("PUT", "http://localhost/feedback/v2/submissions/"+sub.Manifest.ParentSubmissionID+"/replies/"+sub.Manifest.SubmissionID, bytes.NewReader(body))
	r.Header.Set("Authorization", "Feedback "+base64.RawURLEncoding.EncodeToString(secret))
	r.Header.Set("Content-Type", kind)
	r.Header.Set("X-Feedback-Digest", sub.Digest)
	w := httptest.NewRecorder()
	h.ServeHTTP(w, r)
	return w
}
func finishRoot(t *testing.T, s *PublicStore, sub PublicSubmission) {
	t.Helper()
	if _, _, err := s.Accept(testSecret, sub); err != nil {
		t.Fatal(err)
	}
	j, err := s.Claim()
	if err != nil || j == nil {
		t.Fatal(j, err)
	}
	if err = s.Finish(*j, PublicResult{Outcome: "mapped", IssueNumber: 42, IssueNodeID: "NODE42", IssueURL: "https://github.com/example/project/issues/42"}); err != nil {
		t.Fatal(err)
	}
	j, err = s.Claim()
	if err != nil || j == nil {
		t.Fatal(j, err)
	}
	if err = s.Finish(*j, PublicResult{Outcome: "verified"}); err != nil {
		t.Fatal(err)
	}
}
func finishChild(t *testing.T, s *PublicStore, id string) {
	t.Helper()
	j, err := s.Claim()
	if err != nil || j == nil || j.Contribution == nil || j.Contribution.ID != id {
		t.Fatal(j, err)
	}
	if err = s.Finish(*j, PublicResult{Outcome: "mapped", CommentID: 100 + int64(j.Generation), CommentNodeID: "COMMENT"}); err != nil {
		t.Fatal(err)
	}
	j, err = s.Claim()
	if err != nil || j == nil || j.Action != "comment-verify" {
		t.Fatal(j, err)
	}
	if err = s.Finish(*j, PublicResult{Outcome: "verified"}); err != nil {
		t.Fatal(err)
	}
}
func TestPublicReplyHTTPContractAndCapability(t *testing.T) {
	c, sub := publicFixture(t)
	s, _ := publicStoreTest(t)
	h := NewPublicHandler(s, c, nil, Limits{}, nil)
	defer h.Close()
	if w := publicPut(t, h, sub, testSecret); w.Code != 201 {
		t.Fatal(w.Code)
	}
	reply := replyFixture(t, sub, replyTestID)
	if w := replyPut(t, h, reply, bytes.Repeat([]byte{7}, 32)); w.Code != 404 {
		t.Fatal(w.Code)
	}
	if w := replyPut(t, h, reply, testSecret); w.Code != 201 {
		t.Fatal(w.Code, w.Body.String())
	}
	if w := replyPut(t, h, reply, testSecret); w.Code != 200 {
		t.Fatal(w.Code, w.Body.String())
	}
	changed := reply
	changed.ManifestBytes = append([]byte(" "), reply.ManifestBytes...)
	changed.Digest = PublicReplyDigest(changed.ManifestBytes)
	if w := replyPut(t, h, changed, testSecret); w.Code != 409 {
		t.Fatal(w.Code)
	}
	if w := publicRequest(h, "DELETE", sub.Manifest.SubmissionID+"/replies/"+replyTestID, sub, testSecret); w.Code != 405 {
		t.Fatal(w.Code)
	}
	thread := publicRequest(h, "GET", sub.Manifest.SubmissionID+"/thread?limit=1", sub, testSecret)
	if thread.Code != 200 {
		t.Fatal(thread.Code, thread.Body.String())
	}
	var page PublicThread
	if json.Unmarshal(thread.Body.Bytes(), &page) != nil || len(page.Items) != 1 || page.NextCursor == "" {
		t.Fatal(thread.Body.String())
	}
	next := publicRequest(h, "GET", sub.Manifest.SubmissionID+"/thread?cursor="+page.NextCursor, sub, testSecret)
	if next.Code != 200 || !strings.Contains(next.Body.String(), reply.Manifest.Description) {
		t.Fatal(next.Code, next.Body.String())
	}
	if _, err := s.Remove(sub.Manifest.SubmissionID, testSecret); err != nil {
		t.Fatal(err)
	}
	if w := replyPut(t, h, reply, testSecret); w.Code != 200 || !strings.Contains(w.Body.String(), `"removalState":"removed"`) {
		t.Fatal(w.Code, w.Body.String())
	}
	reply = replyFixture(t, sub, questionTestID)
	if w := replyPut(t, h, reply, testSecret); w.Code != 410 {
		t.Fatal(w.Code)
	}
	if w := publicRequest(h, "GET", sub.Manifest.SubmissionID+"/thread", sub, testSecret); w.Code != 200 || strings.Contains(w.Body.String(), sub.Manifest.Description) {
		t.Fatal("removed payload retained in thread", w.Code, w.Body.String())
	}
}
func TestPublicRootRejectsReplyFieldsEvenEmpty(t *testing.T) {
	c, sub := publicFixture(t)
	for _, field := range []string{"parentSubmissionId", "questionId", "questionRevision"} {
		var m map[string]any
		json.Unmarshal(sub.ManifestBytes, &m)
		m[field] = ""
		if field == "questionRevision" {
			m[field] = 0
		}
		raw, _ := json.Marshal(m)
		if _, err := validatePublicManifest(raw, sub.Manifest.SubmissionID, time.Now(), c); err == nil {
			t.Fatal(field)
		}
	}
}
func TestPublicThreadSnapshotAndPublishedExport(t *testing.T) {
	_, sub := publicFixture(t)
	s, now := publicStoreTest(t)
	finishRoot(t, s, sub)
	snap, err := s.ExportCase(sub.Manifest.SubmissionID, bridgeTestBinding)
	if err != nil || snap.InputRevision != 1 || len(snap.Contributions) != 1 {
		t.Fatal(snap, err)
	}
	p := ProjectionRequest{ID: projectionTestID, WorkflowRevision: 1, ExpectedInputRevision: 1, WorkState: "needs-information", Summary: "More detail is needed.", Question: &ProjectionQuestion{ID: questionTestID, Revision: 1, Code: "reproduction_steps", Description: "Please provide the steps needed to reproduce this behavior.", TimeoutSeconds: 3600}}
	if _, err = s.EnqueueProjection(sub.Manifest.SubmissionID, bridgeTestBinding, p); err != nil {
		t.Fatal(err)
	}
	before, err := s.Thread(sub.Manifest.SubmissionID, testSecret, "", 1)
	if err != nil || before.Question != nil || before.WorkState != "new" || before.ProjectionState != "pending" {
		t.Fatal(before, err)
	}
	reply := replyFixture(t, sub, replyTestID)
	reply.Manifest.QuestionID = questionTestID
	reply.Manifest.QuestionRevision = 1
	reply.ManifestBytes, _ = json.Marshal(reply.Manifest)
	reply.Digest = PublicReplyDigest(reply.ManifestBytes)
	if _, _, err = s.AcceptReply(sub.Manifest.SubmissionID, testSecret, reply); !errors.Is(err, ErrConflict) {
		t.Fatal("accepted unpublished question", err)
	}
	finishChild(t, s, projectionTestID)
	questionAt := *now
	page, err := s.Thread(sub.Manifest.SubmissionID, testSecret, "", 1)
	if err != nil || page.Question == nil || page.Question.AnswerDeadline != now.Add(time.Hour).Format(time.RFC3339Nano) || page.NextCursor == "" {
		t.Fatal(page, err)
	}
	if _, _, err = s.AcceptReply(sub.Manifest.SubmissionID, testSecret, reply); err != nil {
		t.Fatal(err)
	}
	if _, err = s.Thread(sub.Manifest.SubmissionID, testSecret, page.NextCursor, 5); !errors.Is(err, ErrThreadChanged) {
		t.Fatal(err)
	}
	snap, err = s.ExportCase(sub.Manifest.SubmissionID, bridgeTestBinding)
	if err != nil || len(snap.Contributions) != 1 || len(snap.Replies) != 1 || snap.InputRevision != 1 || snap.QuestionPublication == nil || !snap.QuestionPublication.PublishedAt.Equal(questionAt) {
		t.Fatal(snap, err)
	}
	raw, _ := json.Marshal(snap)
	if bytes.Contains(raw, []byte(reply.Manifest.Description)) {
		t.Fatal("unpublished reply exported")
	}
	*now = now.Add(2 * time.Hour)
	finishChild(t, s, replyTestID)
	snap, err = s.ExportCase(sub.Manifest.SubmissionID, bridgeTestBinding)
	if err != nil || snap.InputRevision != 2 || len(snap.Contributions) != 2 || !snap.Replies[0].ReceivedAt.Equal(questionAt) {
		t.Fatal(snap, err)
	}
	p.ID = "4a964a0d-4cb4-498d-82b0-d0c95a5f8e7e"
	p.WorkflowRevision = 2
	p.ExpectedInputRevision = 2
	if _, err = s.EnqueueProjection(sub.Manifest.SubmissionID, bridgeTestBinding, p); err != nil {
		t.Fatal(err)
	}
	finishChild(t, s, p.ID)
	page, err = s.Thread(sub.Manifest.SubmissionID, testSecret, "", 5)
	if err != nil || page.Question.PublishedAt != questionAt.Format(time.RFC3339Nano) || page.Question.AnswerDeadline != questionAt.Add(time.Hour).Format(time.RFC3339Nano) {
		t.Fatal("question deadline reset", page.Question, err)
	}
}
func TestPublicReplyCrashRecoveryAndOrphanCleanup(t *testing.T) {
	_, sub := publicFixture(t)
	s, now := publicStoreTest(t)
	finishRoot(t, s, sub)
	reply := replyFixture(t, sub, replyTestID)
	if _, _, err := s.AcceptReply(sub.Manifest.SubmissionID, testSecret, reply); err != nil {
		t.Fatal(err)
	}
	job, err := s.Claim()
	if err != nil || job.Action != "comment-create" {
		t.Fatal(job, err)
	}
	dir := s.dir
	s.Close()
	s, err = openPublicStore(dir, Limits{}, func() time.Time { return *now }, nil)
	if err != nil {
		t.Fatal(err)
	}
	defer s.Close()
	job, err = s.Claim()
	if err != nil || job.Action != "comment-reconcile" {
		t.Fatal(job, err)
	}
	if err = s.Finish(*job, PublicResult{Outcome: "retry", Code: "comment_creation_uncertain"}); err != nil {
		t.Fatal(err)
	}
	*now = now.Add(time.Hour)
	job, _ = s.Claim()
	if job == nil || job.Action != "comment-reconcile" {
		t.Fatal("blind duplicate", job)
	}
	s.Close()
	orphan := contributionFile(sub.Manifest.SubmissionID, questionTestID)
	if err = os.WriteFile(filepath.Join(dir, orphan), []byte(`{"orphan":true}`), 0600); err != nil {
		t.Fatal(err)
	}
	s, err = openPublicStore(dir, Limits{}, func() time.Time { return *now }, nil)
	if err != nil {
		t.Fatal(err)
	}
	defer s.Close()
	if _, err = os.Stat(filepath.Join(dir, orphan)); !os.IsNotExist(err) {
		t.Fatal("orphan not cleaned", err)
	}
	s.Close()
	os.Remove(filepath.Join(dir, contributionFile(sub.Manifest.SubmissionID, replyTestID)))
	if reopened, err := openPublicStore(dir, Limits{}, func() time.Time { return *now }, nil); err == nil {
		reopened.Close()
		t.Fatal("missing referenced payload accepted")
	}
}
func TestPublicContributionSaveFailureLeavesNoAcceptedOrphan(t *testing.T) {
	_, sub := publicFixture(t)
	s, now := publicStoreTest(t)
	finishRoot(t, s, sub)
	s.fault = func(string) error { return errors.New("disk failed") }
	if _, _, err := s.AcceptReply(sub.Manifest.SubmissionID, testSecret, replyFixture(t, sub, replyTestID)); !errors.Is(err, ErrUnavailable) {
		t.Fatal(err)
	}
	dir := s.dir
	s.Close()
	reopened, err := openPublicStore(dir, Limits{}, func() time.Time { return *now }, nil)
	if err != nil {
		t.Fatal(err)
	}
	defer reopened.Close()
	if _, err = reopened.LookupReply(sub.Manifest.SubmissionID, replyTestID, testSecret, ""); !errors.Is(err, ErrNotFound) {
		t.Fatal(err)
	}
	if _, err = os.Stat(filepath.Join(dir, contributionFile(sub.Manifest.SubmissionID, replyTestID))); !os.IsNotExist(err) {
		t.Fatal(err)
	}
}
func TestPublicRemovalWaitsForBoundCoordinatorPurge(t *testing.T) {
	_, sub := publicFixture(t)
	s, now := publicStoreTest(t)
	finishRoot(t, s, sub)
	if _, err := s.ExportCase(sub.Manifest.SubmissionID, bridgeTestBinding); err != nil {
		t.Fatal(err)
	}
	reply := replyFixture(t, sub, replyTestID)
	if _, _, err := s.AcceptReply(sub.Manifest.SubmissionID, testSecret, reply); err != nil {
		t.Fatal(err)
	}
	job, _ := s.Claim()
	if _, err := s.Remove(sub.Manifest.SubmissionID, testSecret); err != nil {
		t.Fatal(err)
	}
	if err := s.Finish(*job, PublicResult{Outcome: "mapped", CommentID: 77, CommentNodeID: "C77"}); err != nil {
		t.Fatal(err)
	}
	job, _ = s.Claim()
	if job == nil || job.Action != "comment-remove" {
		t.Fatal(job)
	}
	if err := s.Finish(*job, PublicResult{Outcome: "removed"}); err != nil {
		t.Fatal(err)
	}
	job, _ = s.Claim()
	if job == nil || job.Action != "remove" {
		t.Fatal(job)
	}
	if err := s.Finish(*job, PublicResult{Outcome: "removed"}); err != nil {
		t.Fatal(err)
	}
	receipt, _ := s.Lookup(sub.Manifest.SubmissionID, testSecret, "")
	if receipt.RemovalState != "pending" || receipt.Reason != "coordinator_cleanup_pending" {
		t.Fatal(receipt)
	}
	dir := s.dir
	s.Close()
	s, err := openPublicStore(dir, Limits{}, func() time.Time { return *now }, nil)
	if err != nil {
		t.Fatal(err)
	}
	defer s.Close()
	snapshot, err := s.ExportCase(sub.Manifest.SubmissionID, bridgeTestBinding)
	if err != nil || snapshot.State != "removed" || len(snapshot.Contributions) > 0 || len(snapshot.Replies) > 0 || snapshot.RevocationRevision < 1 {
		t.Fatal(snapshot, err)
	}
	if err = s.AcknowledgeRevocation(sub.Manifest.SubmissionID, strings.Repeat("b", 64), snapshot.RevocationRevision); !errors.Is(err, ErrConflict) {
		t.Fatal(err)
	}
	if err = s.AcknowledgeRevocation(sub.Manifest.SubmissionID, bridgeTestBinding, snapshot.RevocationRevision+1); !errors.Is(err, ErrConflict) {
		t.Fatal(err)
	}
	if err = s.AcknowledgeRevocation(sub.Manifest.SubmissionID, bridgeTestBinding, snapshot.RevocationRevision); err != nil {
		t.Fatal(err)
	}
	receipt, _ = s.Lookup(sub.Manifest.SubmissionID, testSecret, "")
	if receipt.RemovalState != "removed" {
		t.Fatal(receipt)
	}
	if _, err = os.Stat(filepath.Join(dir, contributionFile(sub.Manifest.SubmissionID, replyTestID))); !os.IsNotExist(err) {
		t.Fatal("derived payload not purged", err)
	}
	snapshot2, err := s.ExportCase(sub.Manifest.SubmissionID, bridgeTestBinding)
	if err != nil {
		t.Fatal(err)
	}
	if err = s.AcknowledgeRevocation(sub.Manifest.SubmissionID, bridgeTestBinding, snapshot2.RevocationRevision); err != nil {
		t.Fatal(err)
	}
	snapshot3, _ := s.ExportCase(sub.Manifest.SubmissionID, bridgeTestBinding)
	if snapshot3.SourceRevision != snapshot2.SourceRevision {
		t.Fatal("ack was not idempotent")
	}
}

type commentGitHubFixture struct {
	mu                             sync.Mutex
	issue                          *githubIssue
	comments                       map[int64]githubComment
	creates, deletes, issueDeletes int
	uncertain, spoof, external     bool
	locked                         bool
}

func commentGitHub(t *testing.T, p *GitHubPublisher) *commentGitHubFixture {
	t.Helper()
	f := &commentGitHubFixture{comments: map[int64]githubComment{}}
	respond := func(w http.ResponseWriter, status int, v any) {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(status)
		json.NewEncoder(w).Encode(v)
	}
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		f.mu.Lock()
		defer f.mu.Unlock()
		path := r.URL.Path
		if path == "/repos/example/project" {
			respond(w, 200, map[string]any{"id": 17, "full_name": "example/project", "private": false, "has_issues": true})
			return
		}
		if path == "/graphql" {
			if f.issue == nil || !f.locked || len(f.comments) > 0 || f.external {
				t.Error("unsafe issue deletion")
				w.WriteHeader(409)
				return
			}
			f.issue = nil
			f.issueDeletes++
			var in struct {
				Variables struct {
					Input struct {
						ClientMutationID string `json:"clientMutationId"`
					} `json:"input"`
				} `json:"variables"`
			}
			json.NewDecoder(r.Body).Decode(&in)
			respond(w, 200, map[string]any{"data": map[string]any{"deleteIssue": map[string]string{"clientMutationId": in.Variables.Input.ClientMutationID}}})
			return
		}
		if path == "/repos/example/project/issues" && r.Method == "POST" {
			var in struct{ Title, Body string }
			json.NewDecoder(r.Body).Decode(&in)
			f.issue = &githubIssue{Number: 42, NodeID: "NODE42", HTMLURL: "https://github.com/example/project/issues/42", Title: in.Title, Body: in.Body}
			f.issue.User.ID = 23
			respond(w, 201, f.issue)
			return
		}
		if path == "/repos/example/project/issues/42/lock" {
			f.locked = true
			w.WriteHeader(204)
			return
		}
		if path == "/repos/example/project/issues/42/comments" {
			if r.Method == "POST" {
				if f.locked {
					t.Error("created while issue locked")
				}
				var in struct{ Body string }
				json.NewDecoder(r.Body).Decode(&in)
				f.creates++
				id := int64(100 + f.creates)
				c := githubComment{ID: id, NodeID: fmt.Sprint("C", id), HTMLURL: "https://github.com/example/project/issues/42#issuecomment-" + strconv.FormatInt(id, 10), IssueURL: "https://api.github.com/repos/example/project/issues/42", Body: in.Body}
				c.User.ID = 23
				f.comments[id] = c
				if f.uncertain {
					w.WriteHeader(502)
					return
				}
				respond(w, 201, c)
				return
			}
			list := []githubComment{}
			for _, c := range f.comments {
				if f.spoof {
					c.User.ID = 24
				}
				list = append(list, c)
			}
			respond(w, 200, list)
			return
		}
		if strings.HasPrefix(path, "/repos/example/project/issues/comments/") {
			id, _ := strconv.ParseInt(strings.TrimPrefix(path, "/repos/example/project/issues/comments/"), 10, 64)
			c, ok := f.comments[id]
			if !ok {
				w.WriteHeader(404)
				return
			}
			if r.Method == "DELETE" {
				if !f.locked {
					t.Error("comment deleted without lock")
				}
				delete(f.comments, id)
				f.deletes++
				w.WriteHeader(204)
				return
			}
			respond(w, 200, c)
			return
		}
		if path == "/repos/example/project/issues/42" {
			if f.issue == nil {
				w.WriteHeader(404)
				return
			}
			v := *f.issue
			v.Comments = len(f.comments)
			if f.external {
				v.Comments++
			}
			respond(w, 200, v)
			return
		}
		t.Errorf("unexpected fake request %s %s", r.Method, path)
		w.WriteHeader(404)
	}))
	t.Cleanup(server.Close)
	p.apiBase = server.URL
	p.graphqlURL = server.URL + "/graphql"
	p.http = server.Client()
	return f
}
func TestPublicCommentPublisherReconcilesAndRemovesOnlyOwned(t *testing.T) {
	for _, external := range []bool{false, true} {
		t.Run(fmt.Sprint("external=", external), func(t *testing.T) {
			c, sub := publicFixture(t)
			s, now := publicStoreTest(t)
			h := NewPublicHandler(s, c, nil, Limits{}, nil)
			defer h.Close()
			receiver := httptest.NewServer(h)
			defer receiver.Close()
			c.PublicURL = receiver.URL + "/feedback/v2"
			h.config = c
			sub.Target = c.target()
			p := &GitHubPublisher{config: c, publicURL: c.PublicURL, token: "private"}
			f := commentGitHub(t, p)
			s.Accept(testSecret, sub)
			for range 2 {
				j, e := s.Claim()
				if e != nil || j == nil {
					t.Fatal(j, e)
				}
				res := p.Publish(context.Background(), *j)
				if e = s.Finish(*j, res); e != nil {
					t.Fatal(res, e)
				}
			}
			reply := replyFixture(t, addPublicImage(t, sub), replyTestID)
			if _, _, e := s.AcceptReply(sub.Manifest.SubmissionID, testSecret, reply); e != nil {
				t.Fatal(e)
			}
			f.uncertain = true
			j, _ := s.Claim()
			res := p.Publish(context.Background(), *j)
			if res.Outcome != "uncertain" {
				t.Fatal(res)
			}
			s.Finish(*j, res)
			*now = now.Add(time.Hour)
			f.spoof = true
			j, _ = s.Claim()
			res = p.Publish(context.Background(), *j)
			if res.Outcome != "retry" || res.CommentID != 0 {
				t.Fatal("adopted spoof", res)
			}
			s.Finish(*j, res)
			*now = now.Add(time.Hour)
			f.spoof = false
			for range 2 {
				j, e := s.Claim()
				if e != nil || j == nil {
					t.Fatal(j, e)
				}
				res = p.Publish(context.Background(), *j)
				if e = s.Finish(*j, res); e != nil {
					t.Fatal(res, e)
				}
			}
			receipt, e := s.LookupReply(sub.Manifest.SubmissionID, replyTestID, testSecret, "")
			if e != nil || receipt.PublicationState != "published" || f.creates != 1 {
				t.Fatal(receipt, e, f.creates)
			}
			f.external = external
			s.Remove(sub.Manifest.SubmissionID, testSecret)
			j, _ = s.Claim()
			if j.Action != "comment-remove" {
				t.Fatal(j)
			}
			res = p.Publish(context.Background(), *j)
			if res.Outcome != "removed" {
				t.Fatal(res)
			}
			s.Finish(*j, res)
			j, _ = s.Claim()
			res = p.Publish(context.Background(), *j)
			s.Finish(*j, res)
			receipt, _ = s.Lookup(sub.Manifest.SubmissionID, testSecret, "")
			if f.deletes != 1 {
				t.Fatal(f.deletes)
			}
			if external {
				if receipt.RemovalState != "stalled" || f.issueDeletes != 0 {
					t.Fatal(receipt, f.issueDeletes)
				}
			} else if receipt.RemovalState != "removed" || f.issueDeletes != 1 {
				t.Fatal(receipt, f.issueDeletes)
			}
		})
	}
}

func TestPublicAssessmentDeliveryHealthIsDurableAndIndependent(t *testing.T) {
	_, sub := publicFixture(t)
	s, now := publicStoreTest(t)
	finishRoot(t, s, sub)
	if _, err := s.ExportCase(sub.Manifest.SubmissionID, bridgeTestBinding); err != nil {
		t.Fatal(err)
	}
	if err := s.MarkAssessmentDelivery(sub.Manifest.SubmissionID, bridgeTestBinding, false, "coordinator_unavailable"); err != nil {
		t.Fatal(err)
	}
	first := s.entries[sub.Manifest.SubmissionID]
	for range 20 {
		if err := s.MarkAssessmentDelivery(sub.Manifest.SubmissionID, bridgeTestBinding, false, "coordinator_unavailable"); err != nil {
			t.Fatal(err)
		}
	}
	if s.entries[sub.Manifest.SubmissionID].ThreadRevision != first.ThreadRevision {
		t.Fatal("repeated failure generated unbounded writes")
	}
	dir := s.dir
	s.Close()
	s, err := openPublicStore(dir, Limits{}, func() time.Time { return *now }, nil)
	if err != nil {
		t.Fatal(err)
	}
	defer s.Close()
	thread, err := s.Thread(sub.Manifest.SubmissionID, testSecret, "", 5)
	if err != nil || thread.AssessmentDeliveryState != "unavailable" || thread.WorkState != "new" {
		t.Fatal(thread, err)
	}
	if err = s.MarkAssessmentDelivery(sub.Manifest.SubmissionID, strings.Repeat("b", 64), true, ""); !errors.Is(err, ErrConflict) {
		t.Fatal(err)
	}
	if err = s.MarkAssessmentDelivery(sub.Manifest.SubmissionID, bridgeTestBinding, true, ""); err != nil {
		t.Fatal(err)
	}
	thread, err = s.Thread(sub.Manifest.SubmissionID, testSecret, "", 5)
	if err != nil || thread.AssessmentDeliveryState != "available" || thread.AssessmentDeliveryReason != "" {
		t.Fatal(thread, err)
	}
}
func TestPublicReplyBoundedAdmissionsAndRecoveryAttempts(t *testing.T) {
	_, sub := publicFixture(t)
	s, now := publicStoreTest(t)
	finishRoot(t, s, sub)
	for i := 0; i < maxReplies; i++ {
		id := fmt.Sprintf("c5bbee60-4236-47f6-8c53-%012d", i)
		reply := replyFixture(t, sub, id)
		if _, _, err := s.AcceptReply(sub.Manifest.SubmissionID, testSecret, reply); err != nil {
			t.Fatal(i, err)
		}
	}
	if _, _, err := s.AcceptReply(sub.Manifest.SubmissionID, testSecret, replyFixture(t, sub, replyTestID)); !errors.Is(err, ErrCapacity) {
		t.Fatal(err)
	}
	firstID := "c5bbee60-4236-47f6-8c53-000000000000"
	for i := 0; i < 12; i++ {
		j, err := s.Claim()
		if err != nil || j == nil || j.Contribution.ID != firstID {
			t.Fatal(i, j, err)
		}
		outcome := "retry"
		if i == 0 {
			outcome = "uncertain"
		}
		if err = s.Finish(*j, PublicResult{Outcome: outcome, Code: "comment_creation_uncertain"}); err != nil {
			t.Fatal(err)
		}
		*now = now.Add(7 * time.Hour)
	}
	if job, err := s.Claim(); err != nil || job != nil {
		t.Fatal("exhaustion transition should not dispatch", job, err)
	}
	receipt, err := s.LookupReply(sub.Manifest.SubmissionID, firstID, testSecret, "")
	if err != nil || receipt.PublicationState != "stalled" {
		t.Fatal(receipt, err)
	}
	dir := s.dir
	s.Close()
	s, err = openPublicStore(dir, Limits{}, func() time.Time { return *now }, nil)
	if err != nil {
		t.Fatal(err)
	}
	defer s.Close()
	j, err := s.Claim()
	if err != nil || j == nil || j.Contribution.ID == firstID {
		t.Fatal("restart reset exhausted reply budget", j, err)
	}
}
func TestPublicReplyAssetsTargetRemovalAndStaleProjection(t *testing.T) {
	c, sub := publicFixture(t)
	s, _ := publicStoreTest(t)
	finishRoot(t, s, sub)
	reply := replyFixture(t, addPublicImage(t, sub), replyTestID)
	if _, _, err := s.AcceptReply(sub.Manifest.SubmissionID, testSecret, reply); err != nil {
		t.Fatal(err)
	}
	snap, err := s.ExportCase(sub.Manifest.SubmissionID, bridgeTestBinding)
	if err != nil {
		t.Fatal(err)
	}
	projection := ProjectionRequest{ID: projectionTestID, WorkflowRevision: 1, ExpectedInputRevision: snap.InputRevision, WorkState: "assessing"}
	if _, err = s.EnqueueProjection(sub.Manifest.SubmissionID, bridgeTestBinding, projection); err != nil {
		t.Fatal(err)
	}
	job, err := s.Claim()
	if err != nil || job == nil {
		t.Fatal(job, err)
	}
	a := reply.Manifest.Attachments[0]
	if b, err := s.ReplyAsset(sub.Manifest.SubmissionID, replyTestID, a.ID, a.SHA256, c.target()); err != nil || !bytes.Equal(b.Bytes, reply.Blobs[0].Bytes) {
		t.Fatal(err)
	}
	other := c.target()
	other.PublicURL = "https://changed.invalid/feedback/v2"
	if _, err = s.ReplyAsset(sub.Manifest.SubmissionID, replyTestID, a.ID, a.SHA256, other); !errors.Is(err, ErrNotFound) {
		t.Fatal("target changed asset published", err)
	}
	s.Finish(*job, PublicResult{Outcome: "mapped", CommentID: 101, CommentNodeID: "C101"})
	job, _ = s.Claim()
	s.Finish(*job, PublicResult{Outcome: "verified"})
	job, _ = s.Claim()
	if job == nil || job.Payload.Projection == nil {
		t.Fatal(job)
	}
	p := &GitHubPublisher{config: c, publicURL: c.PublicURL, token: "private"}
	f := commentGitHub(t, p)
	res := p.Publish(context.Background(), *job)
	if res.Outcome != "stalled" || res.Code != "assessment_context_changed" || f.creates != 0 {
		t.Fatal(res, f.creates)
	}
	s.Finish(*job, res)
	s.Remove(sub.Manifest.SubmissionID, testSecret)
	if _, err = s.ReplyAsset(sub.Manifest.SubmissionID, replyTestID, a.ID, a.SHA256, c.target()); !errors.Is(err, ErrNotFound) {
		t.Fatal(err)
	}
}

func TestPublicQuestionRevisionCannotChangePublishedPromise(t *testing.T) {
	_, sub := publicFixture(t)
	s, _ := publicStoreTest(t)
	finishRoot(t, s, sub)
	snapshot, err := s.ExportCase(sub.Manifest.SubmissionID, bridgeTestBinding)
	if err != nil {
		t.Fatal(err)
	}
	p := ProjectionRequest{ID: projectionTestID, WorkflowRevision: 1, ExpectedInputRevision: snapshot.InputRevision, WorkState: "needs-information", Question: &ProjectionQuestion{ID: questionTestID, Revision: 1, Code: "reproduction_steps", Description: "Please provide the steps needed to reproduce this behavior.", TimeoutSeconds: 3600}}
	if _, err = s.EnqueueProjection(sub.Manifest.SubmissionID, bridgeTestBinding, p); err != nil {
		t.Fatal(err)
	}
	finishChild(t, s, p.ID)
	p.ID = replyTestID
	p.WorkflowRevision = 2
	p.Question.TimeoutSeconds = 7200
	if _, err = s.EnqueueProjection(sub.Manifest.SubmissionID, bridgeTestBinding, p); !errors.Is(err, ErrConflict) {
		t.Fatal("question promise changed under same revision", err)
	}
}

func TestPublicThreadDoesNotTreatOldAssessmentAsCurrent(t *testing.T) {
	_, sub := publicFixture(t)
	s, _ := publicStoreTest(t)
	finishRoot(t, s, sub)
	snapshot, err := s.ExportCase(sub.Manifest.SubmissionID, bridgeTestBinding)
	if err != nil {
		t.Fatal(err)
	}
	p := ProjectionRequest{ID: projectionTestID, WorkflowRevision: 1, ExpectedInputRevision: snapshot.InputRevision, WorkState: "ready", Summary: "Old assessment"}
	if _, err = s.EnqueueProjection(sub.Manifest.SubmissionID, bridgeTestBinding, p); err != nil {
		t.Fatal(err)
	}
	finishChild(t, s, projectionTestID)
	if _, _, err = s.AcceptReply(sub.Manifest.SubmissionID, testSecret, replyFixture(t, sub, replyTestID)); err != nil {
		t.Fatal(err)
	}
	finishChild(t, s, replyTestID)
	thread, err := s.Thread(sub.Manifest.SubmissionID, testSecret, "", 5)
	if err != nil || thread.WorkState != "new" || thread.Summary != "" || thread.WorkflowRevision != 0 || thread.Question != nil {
		t.Fatal(thread, err)
	}
	found := false
	for _, item := range thread.Items {
		if item.SubmissionID == projectionTestID && item.Description == "Old assessment" {
			found = true
		}
	}
	if !found {
		t.Fatal("historical assessment disappeared")
	}
}
func TestPublicSharedReplyFixture(t *testing.T) {
	c, _ := publicFixture(t)
	raw, err := os.ReadFile("../../../../testdata/feedback/v2/reply-valid.json")
	if err != nil {
		t.Fatal(err)
	}
	var contract struct{ ManifestDigest, NoticeText, NoticeSHA256 string }
	contractRaw, err := os.ReadFile("../../../../testdata/feedback/v2/reply-contract.json")
	if err != nil || json.Unmarshal(contractRaw, &contract) != nil {
		t.Fatal("reply contract unavailable", err)
	}
	if PublicReplyDigest(raw) != contract.ManifestDigest || hashBytes([]byte(contract.NoticeText)) != contract.NoticeSHA256 {
		t.Fatal("shared exact-byte reply hash mismatch")
	}
	id := "94ce46e7-ee22-4b84-af46-5fe54c7bc9c2"
	parent := "83bd35d6-dd11-4a73-9f35-4ed43b6ab8b1"
	now := time.Date(2026, 10, 22, 12, 6, 0, 0, time.UTC)
	m, err := validatePublicManifestFor(raw, id, parent, now, c)
	if err != nil || m.QuestionID != "a5df57f8-ff33-4c95-bf57-60f65d8cdae3" || m.QuestionRevision != 7 {
		t.Fatal(m, err)
	}
	if _, err = validatePublicManifest(raw, id, now, c); err == nil {
		t.Fatal("reply fixture accepted as root")
	}
	if _, err = validatePublicManifestFor(raw, id, replyTestID, now, c); err == nil {
		t.Fatal("wrong parent accepted")
	}
	if PublicDigest(raw) == contract.ManifestDigest {
		t.Fatal("reply digest lacked domain separation")
	}
	body, kind := multipartBody(t, raw, nil)
	parsed, err := parsePublicSubmissionFor(context.Background(), bytes.NewReader(body), kind, id, parent, contract.ManifestDigest, now, c, make(chan struct{}, 1))
	if err != nil || !bytes.Equal(parsed.ManifestBytes, raw) {
		t.Fatal("shared wire bytes changed", err)
	}
}
