// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package feedback

import (
	"bytes"
	"context"
	"encoding/base64"
	"encoding/binary"
	"encoding/json"
	"errors"
	"hash/crc32"
	"image"
	"image/png"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"
)

func publicFixture(t *testing.T) (PublicConfig, PublicSubmission) {
	t.Helper()
	raw, err := os.ReadFile("../../../../testdata/feedback/v2/valid-no-attachments.json")
	if err != nil {
		t.Fatal(err)
	}
	var fixture struct{ NoticeText, ManifestDigest, NoticeSHA256 string }
	contract, err := os.ReadFile("../../../../testdata/feedback/v2/contract.json")
	if err != nil {
		t.Fatal(err)
	}
	if err = json.Unmarshal(contract, &fixture); err != nil {
		t.Fatal(err)
	}
	var m PublicManifest
	if err = json.Unmarshal(raw, &m); err != nil {
		t.Fatal(err)
	}
	c := PublicConfig{PublicURL: "https://support.example.invalid/feedback/v2", Repository: m.Disclosure.Repository, RepositoryID: 17, PublisherActorID: 23, NoticeText: fixture.NoticeText, NoticeRevision: m.Disclosure.Revision, ProviderPolicyRevision: m.Disclosure.ProviderPolicyRevision}
	if PublicDigest(raw) != fixture.ManifestDigest || hashBytes([]byte(c.NoticeText)) != fixture.NoticeSHA256 {
		t.Fatal("shared exact-byte digest mismatch")
	}
	now := time.Date(2026, 10, 22, 12, 1, 0, 0, time.UTC)
	if _, err = validatePublicManifest(raw, m.SubmissionID, now, c); err != nil {
		t.Fatal(err)
	}
	return c, PublicSubmission{Target: c.target(), Manifest: m, ManifestBytes: raw, Digest: PublicDigest(raw), Blobs: []Blob{}}
}
func publicStoreTest(t *testing.T) (*PublicStore, *time.Time) {
	t.Helper()
	now := time.Date(2026, 10, 22, 12, 1, 0, 0, time.UTC)
	s, err := openPublicStore(t.TempDir(), Limits{}, func() time.Time { return now }, nil)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { s.Close() })
	return s, &now
}
func publicRequest(h http.Handler, method, id string, sub PublicSubmission, secret []byte) *httptest.ResponseRecorder {
	r := httptest.NewRequest(method, "http://localhost/feedback/v2/submissions/"+id, nil)
	r.Header.Set("Authorization", "Feedback "+base64.RawURLEncoding.EncodeToString(secret))
	w := httptest.NewRecorder()
	h.ServeHTTP(w, r)
	return w
}
func publicPut(t *testing.T, h http.Handler, sub PublicSubmission, secret []byte) *httptest.ResponseRecorder {
	t.Helper()
	body, kind := multipartBody(t, sub.ManifestBytes, sub.Blobs)
	r := httptest.NewRequest("PUT", "http://localhost/feedback/v2/submissions/"+sub.Manifest.SubmissionID, bytes.NewReader(body))
	r.Header.Set("Authorization", "Feedback "+base64.RawURLEncoding.EncodeToString(secret))
	r.Header.Set("Content-Type", kind)
	r.Header.Set("X-Feedback-Digest", sub.Digest)
	w := httptest.NewRecorder()
	h.ServeHTTP(w, r)
	return w
}
func TestPublicAcceptancePrivacyAndRemoval(t *testing.T) {
	c, sub := publicFixture(t)
	s, _ := publicStoreTest(t)
	h := NewPublicHandler(s, c, nil, Limits{}, nil)
	if w := publicPut(t, h, sub, testSecret); w.Code != 201 {
		t.Fatal(w.Code, w.Body.String())
	}
	if w := publicPut(t, h, sub, testSecret); w.Code != 200 {
		t.Fatal(w.Code, w.Body.String())
	}
	wrong := bytes.Repeat([]byte{9}, 32)
	if w := publicPut(t, h, sub, wrong); w.Code != 404 {
		t.Fatal(w.Code)
	}
	r := publicRequest(h, "GET", sub.Manifest.SubmissionID, sub, testSecret)
	if strings.Contains(r.Body.String(), "secret") || strings.Contains(r.Body.String(), sub.Manifest.Description) {
		t.Fatal("receipt leaked private transport metadata or content")
	}
	changed := sub
	changed.ManifestBytes = append([]byte(" "), sub.ManifestBytes...)
	changed.Digest = PublicDigest(changed.ManifestBytes)
	if w := publicPut(t, h, changed, testSecret); w.Code != 409 {
		t.Fatal(w.Code)
	}
	for range 2 {
		w := publicRequest(h, "DELETE", sub.Manifest.SubmissionID, sub, testSecret)
		if w.Code != 200 || !strings.Contains(w.Body.String(), `"removalState":"removed"`) {
			t.Fatal(w.Code, w.Body.String())
		}
	}
	if job, err := s.Claim(); err != nil || job != nil {
		t.Fatal("removed unpublished content was queued", job, err)
	}
	if _, ok, err := s.Accept(testSecret, sub); err != nil || ok {
		t.Fatal("removed identity replay", ok, err)
	}
}
func TestPublicManifestClosedConsentAndSecrets(t *testing.T) {
	c, sub := publicFixture(t)
	s, _ := publicStoreTest(t)
	h := NewPublicHandler(s, c, nil, Limits{PerSourceSubmissions: 100}, nil)
	for _, change := range []func(map[string]any){
		func(m map[string]any) { m["replyEmail"] = "private@example.invalid" },
		func(m map[string]any) { m["disclosure"].(map[string]any)["sha256"] = strings.Repeat("0", 64) },
		func(m map[string]any) { m["disclosure"].(map[string]any)["providerPolicyRevision"] = "other" },
		func(m map[string]any) { m["description"] = "token ghp_" + strings.Repeat("a", 36) },
		func(m map[string]any) { m["context"] = nil },
	} {
		var m map[string]any
		json.Unmarshal(sub.ManifestBytes, &m)
		change(m)
		raw, _ := json.Marshal(m)
		bad := sub
		bad.ManifestBytes = raw
		bad.Digest = PublicDigest(raw)
		if w := publicPut(t, h, bad, testSecret); w.Code != 422 {
			t.Fatal(w.Code, w.Body.String())
		}
	}
}
func addPublicImage(t *testing.T, sub PublicSubmission) PublicSubmission {
	t.Helper()
	var b bytes.Buffer
	if err := png.Encode(&b, image.NewNRGBA(image.Rect(0, 0, 2, 2))); err != nil {
		t.Fatal(err)
	}
	raw := b.Bytes()
	a := Attachment{ID: "screenshot-1", Kind: "screenshot", MediaType: "image/png", ByteLength: int64(len(raw)), SHA256: hashBytes(raw)}
	sub.Manifest.Attachments = []Attachment{a}
	sub.Blobs = []Blob{{Attachment: a, Bytes: raw}}
	sub.ManifestBytes, _ = json.Marshal(sub.Manifest)
	sub.Digest = PublicDigest(sub.ManifestBytes)
	return sub
}
func TestPublicAssetsExactAndRevokedDuringFlight(t *testing.T) {
	c, sub := publicFixture(t)
	sub = addPublicImage(t, sub)
	s, _ := publicStoreTest(t)
	h := NewPublicHandler(s, c, nil, Limits{}, nil)
	if w := publicPut(t, h, sub, testSecret); w.Code != 201 {
		t.Fatal(w.Code, w.Body.String())
	}
	a := sub.Manifest.Attachments[0]
	if _, err := s.Asset(sub.Manifest.SubmissionID, a.ID, a.SHA256, c.target()); !errors.Is(err, ErrNotFound) {
		t.Fatal("assets visible before dispatch")
	}
	job, err := s.Claim()
	if err != nil || job == nil {
		t.Fatal(err)
	}
	blob, err := s.Asset(job.ID, a.ID, a.SHA256, c.target())
	if err != nil || !bytes.Equal(blob.Bytes, sub.Blobs[0].Bytes) {
		t.Fatal("approved bytes changed", err)
	}
	receipt, err := s.Remove(job.ID, testSecret)
	if err != nil || receipt.RemovalState == "removed" {
		t.Fatal("inflight write not settled", receipt, err)
	}
	if _, err = s.Asset(job.ID, a.ID, a.SHA256, c.target()); !errors.Is(err, ErrNotFound) {
		t.Fatal("removal failed to revoke assets")
	}
	if err = s.Finish(*job, PublicResult{Outcome: "mapped", IssueNumber: 8, IssueNodeID: "NODE8", IssueURL: "https://github.com/example/project/issues/8"}); err != nil {
		t.Fatal(err)
	}
	next, err := s.Claim()
	if err != nil || next == nil || next.Action != "remove" {
		t.Fatal("late publisher resurrected content", next, err)
	}
	if err = s.Finish(*next, PublicResult{Outcome: "removed"}); err != nil {
		t.Fatal(err)
	}
	if err = s.Finish(*job, PublicResult{Outcome: "verified"}); !errors.Is(err, ErrConflict) {
		t.Fatal("stale writer accepted", err)
	}
}
func TestPublicCrashRecoveryDoesNotCreateAgain(t *testing.T) {
	_, sub := publicFixture(t)
	now := time.Date(2026, 10, 22, 12, 1, 0, 0, time.UTC)
	dir := t.TempDir()
	s, err := openPublicStore(dir, Limits{}, func() time.Time { return now }, nil)
	if err != nil {
		t.Fatal(err)
	}
	if _, _, err = s.Accept(testSecret, sub); err != nil {
		t.Fatal(err)
	}
	job, err := s.Claim()
	if err != nil || job.Action != "create" {
		t.Fatal(job, err)
	}
	s.Close()
	s, err = openPublicStore(dir, Limits{}, func() time.Time { return now }, nil)
	if err != nil {
		t.Fatal(err)
	}
	defer s.Close()
	next, err := s.Claim()
	if err != nil || next.Action != "reconcile" {
		t.Fatal(next, err)
	}
	for next != nil {
		if err = s.Finish(*next, PublicResult{Outcome: "retry", Code: "creation_uncertain"}); err != nil {
			t.Fatal(err)
		}
		now = now.Add(7 * time.Hour)
		next, err = s.Claim()
		if err != nil {
			t.Fatal(err)
		}
		if next != nil && next.Action != "reconcile" {
			t.Fatal("blind duplicate creation", next.Action)
		}
	}
	receipt, err := s.Lookup(sub.Manifest.SubmissionID, testSecret, "")
	if err != nil || receipt.PublicationState != "stalled" {
		t.Fatal(receipt, err)
	}
}
func TestPublicPersistenceFailureAndConcurrentRemoval(t *testing.T) {
	_, sub := publicFixture(t)
	s, _ := publicStoreTest(t)
	s.fault = func(string) error { return errors.New("disk") }
	if _, _, err := s.Accept(testSecret, sub); err == nil {
		t.Fatal("failed commit acknowledged")
	}
	if s.Ready() {
		t.Fatal("ambiguous persistence remained ready")
	}
	s2, _ := publicStoreTest(t)
	if _, _, err := s2.Accept(testSecret, sub); err != nil {
		t.Fatal(err)
	}
	var wg sync.WaitGroup
	for range 16 {
		wg.Add(1)
		go func() {
			defer wg.Done()
			_, _ = s2.Lookup(sub.Manifest.SubmissionID, testSecret, "")
			_, _ = s2.Remove(sub.Manifest.SubmissionID, testSecret)
		}()
	}
	wg.Wait()
	r, err := s2.Lookup(sub.Manifest.SubmissionID, testSecret, "")
	if err != nil || r.RemovalState != "removed" {
		t.Fatal(r, err)
	}
}
func TestPublicExpiryAndTombstoneRetention(t *testing.T) {
	_, sub := publicFixture(t)
	s, now := publicStoreTest(t)
	if _, _, err := s.Accept(testSecret, sub); err != nil {
		t.Fatal(err)
	}
	*now = now.Add(365 * 24 * time.Hour)
	if job, err := s.Claim(); err != nil || job != nil {
		t.Fatal(job, err)
	}
	r, err := s.Lookup(sub.Manifest.SubmissionID, testSecret, "")
	if err != nil || r.RemovalState != "removed" {
		t.Fatal(r, err)
	}
	*now = now.Add(119 * 24 * time.Hour)
	s.Claim()
	if _, err = s.Lookup(sub.Manifest.SubmissionID, testSecret, ""); err != nil {
		t.Fatal("tombstone lost early", err)
	}
	*now = now.Add(24 * time.Hour)
	s.Claim()
	if _, err = s.Lookup(sub.Manifest.SubmissionID, testSecret, ""); !errors.Is(err, ErrNotFound) {
		t.Fatal(err)
	}
}
func TestPublicModeRetiresV1WithoutRepublishing(t *testing.T) {
	legacy, _ := testStore(t)
	private := NewHandler(legacy, Limits{}, nil)
	raw := rawManifest(t)
	body, kind := multipartBody(t, raw, nil)
	if w := request(private, "PUT", body, kind, Digest(raw), testSecret); w.Code != 201 {
		t.Fatal(w.Code)
	}
	c, _ := publicFixture(t)
	s, _ := publicStoreTest(t)
	h := NewPublicHandler(s, c, legacy, Limits{}, nil)
	if w := request(h, "PUT", body, kind, Digest(raw), testSecret); w.Code != 200 {
		t.Fatal(w.Code)
	}
	raw = bytes.ReplaceAll(raw, []byte(testID), []byte("48f69878-3904-4628-a498-98cc89a6b053"))
	body, kind = multipartBody(t, raw, nil)
	r := httptest.NewRequest("PUT", "http://localhost/feedback/v1/submissions/48f69878-3904-4628-a498-98cc89a6b053", bytes.NewReader(body))
	r.Header.Set("Authorization", "Feedback "+base64.RawURLEncoding.EncodeToString(testSecret))
	r.Header.Set("Content-Type", kind)
	r.Header.Set("X-Feedback-Digest", Digest(raw))
	w := httptest.NewRecorder()
	h.ServeHTTP(w, r)
	if w.Code != 422 {
		t.Fatal(w.Code, w.Body.String())
	}
	if len(s.entries) != 0 {
		t.Fatal("private feedback migrated")
	}
}

type githubFixture struct {
	mu            sync.Mutex
	issue         *githubIssue
	creates       int
	deletes       int
	uncertain     bool
	spoof         bool
	comments      int
	commentAtLock bool
}

func fakeGitHub(t *testing.T, p *GitHubPublisher) *githubFixture {
	t.Helper()
	f := &githubFixture{}
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		f.mu.Lock()
		defer f.mu.Unlock()
		if r.URL.Path == "/repos/example/project" {
			writeJSON(w, 200, map[string]any{"id": 17, "full_name": "example/project", "private": false, "has_issues": true})
			return
		}
		if r.Method == "PUT" && strings.HasSuffix(r.URL.Path, "/lock") {
			if f.commentAtLock && f.issue != nil {
				f.issue.Comments++
			}
			w.WriteHeader(204)
			return
		}
		if r.URL.Path == "/graphql" {
			var input struct {
				Variables struct {
					Input struct {
						ClientMutationID string `json:"clientMutationId"`
					} `json:"input"`
				} `json:"variables"`
			}
			json.NewDecoder(r.Body).Decode(&input)
			f.deletes++
			f.issue = nil
			writeJSON(w, 200, map[string]any{"data": map[string]any{"deleteIssue": map[string]string{"clientMutationId": input.Variables.Input.ClientMutationID}}})
			return
		}
		if r.Method == "POST" {
			var input struct{ Title, Body string }
			json.NewDecoder(r.Body).Decode(&input)
			f.creates++
			issue := githubIssue{Number: 42, NodeID: "NODE42", HTMLURL: "https://github.com/example/project/issues/42", Title: input.Title, Body: input.Body, Comments: f.comments}
			issue.User.ID = 23
			f.issue = &issue
			if f.uncertain {
				w.WriteHeader(502)
				return
			}
			writeJSON(w, 201, issue)
			return
		}
		if r.URL.Path == "/repos/example/project/issues" {
			issues := []githubIssue{}
			if f.issue != nil {
				issue := *f.issue
				if f.spoof {
					issue.User.ID = 999
				}
				issues = append(issues, issue)
			}
			writeJSON(w, 200, issues)
			return
		}
		if f.issue == nil {
			w.WriteHeader(404)
			return
		}
		writeJSON(w, 200, f.issue)
	}))
	t.Cleanup(server.Close)
	p.apiBase = server.URL
	p.graphqlURL = server.URL + "/graphql"
	p.http = server.Client()
	return f
}
func TestPublicGitHubEndToEndAndAmbiguousReconcile(t *testing.T) {
	for _, uncertain := range []bool{false, true} {
		t.Run(map[bool]string{false: "success", true: "lost-response"}[uncertain], func(t *testing.T) {
			c, sub := publicFixture(t)
			sub = addPublicImage(t, sub)
			s, now := publicStoreTest(t)
			h := NewPublicHandler(s, c, nil, Limits{}, nil)
			receiver := httptest.NewServer(h)
			defer receiver.Close()
			c.PublicURL = receiver.URL + "/feedback/v2"
			h.config = c
			p := &GitHubPublisher{config: c, publicURL: c.PublicURL, token: "test-private-token"}
			f := fakeGitHub(t, p)
			f.uncertain = uncertain
			if w := publicPut(t, h, sub, testSecret); w.Code != 201 {
				t.Fatal(w.Code, w.Body.String())
			}
			for range 4 {
				job, err := s.Claim()
				if err != nil {
					t.Fatal(err)
				}
				if job == nil {
					break
				}
				result := p.Publish(context.Background(), *job)
				if err = s.Finish(*job, result); err != nil {
					t.Fatal(err)
				}
				*now = now.Add(7 * time.Hour)
			}
			receipt, err := s.Lookup(sub.Manifest.SubmissionID, testSecret, "")
			if err != nil || receipt.PublicationState != "published" || f.creates != 1 {
				t.Fatal(receipt, err, f.creates)
			}
			if strings.Contains(f.issue.Body, p.token) || strings.Contains(f.issue.Body, base64.RawURLEncoding.EncodeToString(testSecret)) {
				t.Fatal("capability or publisher credential leaked")
			}
			if _, err = s.Remove(sub.Manifest.SubmissionID, testSecret); err != nil {
				t.Fatal(err)
			}
			job, err := s.Claim()
			if err != nil || job == nil {
				t.Fatal(job, err)
			}
			result := p.Publish(context.Background(), *job)
			if err = s.Finish(*job, result); err != nil {
				t.Fatal(err)
			}
			receipt, err = s.Lookup(job.ID, testSecret, "")
			if err != nil || receipt.RemovalState != "removed" || f.deletes != 1 {
				t.Fatal(receipt, result, err)
			}
		})
	}
}
func TestPublicGitHubNeverAdoptsSpoofOrDropsComments(t *testing.T) {
	c, sub := publicFixture(t)
	s, now := publicStoreTest(t)
	p := &GitHubPublisher{config: c, publicURL: "https://support.example.invalid/feedback/v2", token: "private"}
	f := fakeGitHub(t, p)
	f.uncertain = true
	f.spoof = true
	s.Accept(testSecret, sub)
	job, _ := s.Claim()
	s.Finish(*job, p.Publish(context.Background(), *job))
	*now = now.Add(time.Hour)
	job, _ = s.Claim()
	result := p.Publish(context.Background(), *job)
	if result.Outcome != "retry" || result.IssueNumber != 0 || f.creates != 1 {
		t.Fatal(result)
	}
	s.Finish(*job, result)
	f.spoof = false
	*now = now.Add(time.Hour)
	job, _ = s.Claim()
	result = p.Publish(context.Background(), *job)
	s.Finish(*job, result)
	s.Remove(job.ID, testSecret)
	f.issue.Comments = 1
	job, _ = s.Claim()
	result = p.Publish(context.Background(), *job)
	if result.Outcome != "stalled" || f.deletes != 0 {
		t.Fatal("removed unrelated comment", result)
	}
}
func TestPublicStoreRejectsSymlinkAndTokenPermissions(t *testing.T) {
	c, _ := publicFixture(t)
	dir := t.TempDir()
	outside := filepath.Join(t.TempDir(), "outside")
	os.WriteFile(outside, []byte("{}"), 0600)
	os.Symlink(outside, filepath.Join(dir, testID+".json"))
	if s, err := OpenPublicStore(dir, Limits{}); err == nil {
		s.Close()
		t.Fatal("symlink accepted")
	}
	c.TokenFile = filepath.Join(t.TempDir(), "token")
	os.WriteFile(c.TokenFile, []byte("private"), 0644)
	if _, err := NewGitHubPublisher(c, "https://support.example.invalid/feedback/v2"); err == nil {
		t.Fatal("publicly readable token accepted")
	}
}

func TestPublicDestinationAndDisclosureCannotChangeOnRetry(t *testing.T) {
	c, sub := publicFixture(t)
	sub = addPublicImage(t, sub)
	s, _ := publicStoreTest(t)
	if _, _, err := s.Accept(testSecret, sub); err != nil {
		t.Fatal(err)
	}
	job, err := s.Claim()
	if err != nil {
		t.Fatal(err)
	}
	p := &GitHubPublisher{config: c, publicURL: c.PublicURL, token: "private"}
	f := fakeGitHub(t, p)
	for _, mutate := range []func(*GitHubPublisher){func(p *GitHubPublisher) { p.config.Repository = "another/repository" }, func(p *GitHubPublisher) { p.config.RepositoryID++ }, func(p *GitHubPublisher) { p.config.PublisherActorID++ }, func(p *GitHubPublisher) { p.publicURL = "https://other.example.invalid/feedback/v2" }, func(p *GitHubPublisher) { p.config.NoticeText += " new" }, func(p *GitHubPublisher) { p.config.ProviderPolicyRevision = "new-provider" }} {
		copy := *p
		mutate(&copy)
		result := copy.Publish(context.Background(), *job)
		if result.Outcome != "stalled" || f.creates != 0 {
			t.Fatal("configuration silently changed frozen authorization", result)
		}
	}
	a := sub.Manifest.Attachments[0]
	changed := c
	changed.PublicURL = "https://other.example.invalid/feedback/v2"
	if _, err := s.Asset(job.ID, a.ID, a.SHA256, changed.target()); !errors.Is(err, ErrNotFound) {
		t.Fatal("new public host exposed old consent", err)
	}
}
func TestPublicStaleFinishKeepsNewClaimLive(t *testing.T) {
	_, sub := publicFixture(t)
	s, _ := publicStoreTest(t)
	s.Accept(testSecret, sub)
	old, _ := s.Claim()
	s.Finish(*old, PublicResult{Outcome: "mapped", IssueNumber: 42, IssueNodeID: "NODE42", IssueURL: "https://github.com/example/project/issues/42"})
	current, _ := s.Claim()
	if err := s.Finish(*old, PublicResult{Outcome: "verified"}); !errors.Is(err, ErrConflict) {
		t.Fatal(err)
	}
	if another, err := s.Claim(); err != nil || another != nil {
		t.Fatal("stale completion released active claim", another, err)
	}
	if err := s.Finish(*current, PublicResult{Outcome: "verified"}); err != nil {
		t.Fatal(err)
	}
}
func TestPublicRemovalRepairBudgetSurvivesRestart(t *testing.T) {
	_, sub := publicFixture(t)
	s, now := publicStoreTest(t)
	s.Accept(testSecret, sub)
	job, _ := s.Claim()
	s.Finish(*job, PublicResult{Outcome: "mapped", IssueNumber: 42, IssueNodeID: "NODE42", IssueURL: "https://github.com/example/project/issues/42"})
	s.Remove(job.ID, testSecret)
	for repair := 0; repair <= 2; repair++ {
		job, err := s.Claim()
		if err != nil || job == nil || job.Action != "remove" {
			t.Fatal(repair, job, err)
		}
		if err = s.Finish(*job, PublicResult{Outcome: "stalled", Code: "removal_permission_unavailable"}); err != nil {
			t.Fatal(err)
		}
		for range 3 {
			r, err := s.Remove(job.ID, testSecret)
			if err != nil || r.RemovalState != "stalled" {
				t.Fatal("cooldown bypassed", r, err)
			}
		}
		*now = now.Add(6 * time.Hour)
		r, err := s.Remove(job.ID, testSecret)
		if err != nil {
			t.Fatal(err)
		}
		if repair == 2 && r.RemovalState != "stalled" {
			t.Fatal("lifetime repair budget reset", r)
		}
	}
	if job, err := s.Claim(); err != nil || job != nil {
		t.Fatal(job, err)
	}
	dir := s.dir
	s.Close()
	reopened, err := openPublicStore(dir, Limits{}, func() time.Time { return *now }, nil)
	if err != nil {
		t.Fatal(err)
	}
	defer reopened.Close()
	*now = now.Add(24 * time.Hour)
	r, err := reopened.Remove(sub.Manifest.SubmissionID, testSecret)
	if err != nil || r.RemovalState != "stalled" {
		t.Fatal("restart reset repair budget", r, err)
	}
}
func TestPublicRemovalCanRecoverWithinBudget(t *testing.T) {
	_, sub := publicFixture(t)
	s, now := publicStoreTest(t)
	s.Accept(testSecret, sub)
	job, _ := s.Claim()
	s.Finish(*job, PublicResult{Outcome: "mapped", IssueNumber: 42, IssueNodeID: "NODE42", IssueURL: "https://github.com/example/project/issues/42"})
	s.Remove(job.ID, testSecret)
	job, _ = s.Claim()
	s.Finish(*job, PublicResult{Outcome: "stalled", Code: "removal_permission_unavailable"})
	*now = now.Add(6 * time.Hour)
	s.Remove(job.ID, testSecret)
	job, _ = s.Claim()
	if err := s.Finish(*job, PublicResult{Outcome: "removed"}); err != nil {
		t.Fatal(err)
	}
	r, _ := s.Lookup(job.ID, testSecret, "")
	if r.RemovalState != "removed" {
		t.Fatal(r)
	}
}
func TestPublicPublisherRateLimitHonorsBoundedRetryAfter(t *testing.T) {
	c, sub := publicFixture(t)
	s, now := publicStoreTest(t)
	s.Accept(testSecret, sub)
	job, _ := s.Claim()
	fake := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { w.Header().Set("Retry-After", "900"); w.WriteHeader(429) }))
	defer fake.Close()
	p := &GitHubPublisher{config: c, publicURL: c.PublicURL, apiBase: fake.URL, http: fake.Client()}
	result := p.Publish(context.Background(), *job)
	if result.Outcome != "retry" || result.RetryAfter != 15*time.Minute {
		t.Fatal(result)
	}
	s.Finish(*job, result)
	*now = now.Add(14 * time.Minute)
	if next, err := s.Claim(); err != nil || next != nil {
		t.Fatal("provider retry-after ignored", next, err)
	}
}
func TestPublicDownloadSlotsDoNotBlockReceiptRequests(t *testing.T) {
	c, sub := publicFixture(t)
	sub = addPublicImage(t, sub)
	s, _ := publicStoreTest(t)
	s.Accept(testSecret, sub)
	s.Claim()
	h := NewPublicHandler(s, c, nil, Limits{}, nil)
	for range cap(h.downloads) {
		h.downloads <- struct{}{}
	}
	a := sub.Manifest.Attachments[0]
	r := httptest.NewRequest("GET", "http://localhost/feedback/v2/assets/"+sub.Manifest.SubmissionID+"/"+a.ID+"/"+a.SHA256, nil)
	w := httptest.NewRecorder()
	h.ServeHTTP(w, r)
	if w.Code != 503 {
		t.Fatal("downloads not bounded", w.Code)
	}
	if receipt := publicRequest(h, "GET", sub.Manifest.SubmissionID, sub, testSecret); receipt.Code != 200 {
		t.Fatal("download pressure blocked ownership access", receipt.Code)
	}
}
func TestPublicConfigUsesSeparateStoresAndNoSMTP(t *testing.T) {
	public, _ := publicFixture(t)
	dir := t.TempDir()
	public.DataDir = filepath.Join(dir, "public")
	public.TokenFile = filepath.Join(dir, "token")
	c := Config{SchemaVersion: 2, Listen: "127.0.0.1:57324", PublicURL: "https://support.example.invalid/feedback/v2", DataDir: filepath.Join(dir, "legacy"), OperatorName: "Test", MonitoringConfigured: true, Public: &public}
	if err := c.Validate(); err != nil {
		t.Fatal(err)
	}
	if public.PublicURL != c.PublicURL {
		t.Fatal("target base not frozen")
	}
	public.DataDir = filepath.Join(c.DataDir, "public")
	if err := c.Validate(); err == nil {
		t.Fatal("public store nested in private store")
	}
}

func TestPublicCredentialScreeningDecodesAllPublicJSONStrings(t *testing.T) {
	c, sub := publicFixture(t)
	s, _ := publicStoreTest(t)
	h := NewPublicHandler(s, c, nil, Limits{}, nil)
	for _, description := range []string{"Authorization: Bearer abcdefghijklmnopqrstuvwxyz123456", "api_key=abcdefghijklmnop", "password: abcdefghijklmnop"} {
		bad := sub
		bad.Manifest.Description = description
		bad.ManifestBytes, _ = json.Marshal(bad.Manifest)
		bad.Digest = PublicDigest(bad.ManifestBytes)
		if w := publicPut(t, h, bad, testSecret); w.Code != 422 {
			t.Fatal("known credential description accepted", w.Code)
		}
	}
	bad := sub
	bad.Manifest.Context.Feature = "ghp_" + strings.Repeat("A", 30)
	bad.ManifestBytes, _ = json.Marshal(bad.Manifest)
	bad.Digest = PublicDigest(bad.ManifestBytes)
	if w := publicPut(t, h, bad, testSecret); w.Code != 422 {
		t.Fatal("known credential context accepted", w.Code)
	}
	raw := []byte(`{"schemaVersion":2,"events":[],"exportedAt":"2026-10-22T12:00:00Z","historyPersistence":"available","state":"\u0067hp_AAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"}`)
	a := Attachment{ID: "hosting", Kind: "hosting_diagnostics", MediaType: "application/json", ByteLength: int64(len(raw)), SHA256: hashBytes(raw)}
	if _, err := normalizeHosting(raw, a); err != nil {
		t.Fatal("test must satisfy ordinary diagnostic schema", err)
	}
	sub.Manifest.Attachments = []Attachment{a}
	sub.Blobs = []Blob{{Attachment: a, Bytes: raw}}
	sub.ManifestBytes, _ = json.Marshal(sub.Manifest)
	sub.Digest = PublicDigest(sub.ManifestBytes)
	if w := publicPut(t, h, sub, testSecret); w.Code != 422 {
		t.Fatal("escaped diagnostic credential accepted", w.Code)
	}
}

func TestPublicModeRetainsPrivateCleanupWithoutSMTPSender(t *testing.T) {
	legacy, clock := testStore(t)
	acceptTest(t, legacy)
	clock.Store(testNow.Add(91 * 24 * time.Hour).Unix())
	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan struct{})
	go func() { defer close(done); RunRetention(ctx, legacy) }()
	defer func() { cancel(); <-done }()
	deadline := time.Now().Add(time.Second)
	for {
		stats, err := legacy.Stats(context.Background())
		if err != nil {
			t.Fatal(err)
		}
		if stats.Tombstones == 1 {
			break
		}
		if time.Now().After(deadline) {
			t.Fatal("private raw retention stopped with SMTP")
		}
		time.Sleep(time.Millisecond)
	}
}

func TestPublicRemovalRechecksCommentsAfterLock(t *testing.T) {
	c, sub := publicFixture(t)
	s, _ := publicStoreTest(t)
	s.Accept(testSecret, sub)
	p := &GitHubPublisher{config: c, publicURL: c.PublicURL, token: "private"}
	fake := fakeGitHub(t, p)
	job, _ := s.Claim()
	s.Finish(*job, p.Publish(context.Background(), *job))
	s.Remove(job.ID, testSecret)
	fake.commentAtLock = true
	job, _ = s.Claim()
	result := p.Publish(context.Background(), *job)
	if result.Outcome != "stalled" || result.Code != "removal_requires_moderation" || fake.deletes != 0 {
		t.Fatal("comment arriving before lock was deleted", result)
	}
}
func TestPublicPNGMetadataRejectedWithoutRewriting(t *testing.T) {
	c, sub := publicFixture(t)
	sub = addPublicImage(t, sub)
	raw := sub.Blobs[0].Bytes
	payload := []byte("Comment\x00private metadata")
	chunk := make([]byte, 12+len(payload))
	binary.BigEndian.PutUint32(chunk, uint32(len(payload)))
	copy(chunk[4:], "tEXt")
	copy(chunk[8:], payload)
	binary.BigEndian.PutUint32(chunk[len(chunk)-4:], crc32.ChecksumIEEE(chunk[4:len(chunk)-4]))
	modified := append(append(append([]byte{}, raw[:len(raw)-12]...), chunk...), raw[len(raw)-12:]...)
	if _, err := normalizeImage(modified, "image/png"); err != nil {
		t.Fatal("test PNG should be structurally decodable", err)
	}
	a := sub.Manifest.Attachments[0]
	a.ByteLength = int64(len(modified))
	a.SHA256 = hashBytes(modified)
	sub.Manifest.Attachments = []Attachment{a}
	sub.Blobs = []Blob{{Attachment: a, Bytes: modified}}
	sub.ManifestBytes, _ = json.Marshal(sub.Manifest)
	sub.Digest = PublicDigest(sub.ManifestBytes)
	s, _ := publicStoreTest(t)
	h := NewPublicHandler(s, c, nil, Limits{}, nil)
	if response := publicPut(t, h, sub, testSecret); response.Code != 422 {
		t.Fatal("server silently rewrote post-preview metadata", response.Code)
	}
}

func TestPrepareLegacyStoreAppliesRetentionBeforeSMTPDecision(t *testing.T) {
	for _, state := range []string{"pending", "uncertain", "needs_attention"} {
		for _, expired := range []bool{false, true} {
			label := state + "/current"
			if expired {
				label = state + "/expired"
			}
			t.Run(label, func(t *testing.T) {
				legacy, clock := testStore(t)
				acceptTest(t, legacy)
				if state != "pending" {
					job, err := legacy.Claim(context.Background())
					if err != nil || job == nil {
						t.Fatal(job, err)
					}
					if err = legacy.Finish(context.Background(), *job, MailResult{State: state, Code: "fixture"}); err != nil {
						t.Fatal(err)
					}
				}
				if expired {
					clock.Store(testNow.Add(91 * 24 * time.Hour).Unix())
				}
				ctx, cancel := context.WithTimeout(context.Background(), time.Second)
				defer cancel()
				needsSMTP, err := PrepareLegacyStore(ctx, legacy)
				if err != nil || needsSMTP == expired {
					t.Fatal("incorrect startup decision", needsSMTP, err)
				}
				record, _, err := readRecord(filepath.Join(legacy.dir, testID, "record.json"))
				if err != nil {
					t.Fatal(err)
				}
				if expired {
					if !record.Tombstone || record.Submission != nil {
						t.Fatal("startup allowed before private raw content was removed")
					}
				} else if record.Tombstone || record.Submission == nil {
					t.Fatal("unexpired private delivery was discarded")
				}
			})
		}
	}
}
func TestPrepareLegacyStoreRejectsCleanupFailureOrCancellation(t *testing.T) {
	t.Run("storage failure", func(t *testing.T) {
		legacy, clock := testStore(t)
		acceptTest(t, legacy)
		clock.Store(testNow.Add(91 * 24 * time.Hour).Unix())
		entry := legacy.get(testID)
		entry.ready = false
		legacy.fault = func(stage string) error {
			if stage == "reconcile" {
				return errors.New("fixture storage failure")
			}
			return nil
		}
		ctx, cancel := context.WithTimeout(context.Background(), time.Second)
		defer cancel()
		if _, err := PrepareLegacyStore(ctx, legacy); err == nil {
			t.Fatal("failed cleanup permitted startup")
		}
		record, _, err := readRecord(filepath.Join(legacy.dir, testID, "record.json"))
		if err != nil || record.Submission == nil {
			t.Fatal("failure fixture did not retain unresolved raw content", err)
		}
	})
	t.Run("deadline", func(t *testing.T) {
		legacy, _ := testStore(t)
		acceptTest(t, legacy)
		entry := legacy.get(testID)
		if err := acquire(context.Background(), entry); err != nil {
			t.Fatal(err)
		}
		defer release(entry)
		ctx, cancel := context.WithTimeout(context.Background(), 10*time.Millisecond)
		defer cancel()
		if _, err := PrepareLegacyStore(ctx, legacy); err == nil {
			t.Fatal("expired startup deadline permitted startup")
		}
	})
}
