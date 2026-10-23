// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package feedback

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestPublicOutcomeAdmissionAndLegacyDigest(t *testing.T) {
	old := ProjectionRequest{ID: projectionTestID, WorkflowRevision: 1, ExpectedInputRevision: 1, WorkState: "ready", Summary: "Public assessment."}
	raw := `{"id":"` + projectionTestID + `","workflowRevision":1,"expectedInputRevision":1,"workState":"ready","summary":"Public assessment."}`
	if got := projectionDigest(old); got != hashBytes([]byte("hexproof-projection-v1\n"+raw)) {
		t.Fatal("old immutable payload digest changed", got)
	}
	legacy := old
	legacy.WorkState = "released"
	if len(appendDeliveryFact(nil, legacy, "2026-10-23T00:00:00Z")) != 0 {
		t.Fatal("legacy prose inferred verified delivery")
	}
	for _, state := range []string{"duplicate", "source-published-awaiting-release", "released"} {
		p := old
		p.WorkState = state
		if validProjectionOutcome(p, "example/project", 42) {
			t.Fatal("bare delivered state accepted", state)
		}
	}
	for _, tc := range []struct {
		name   string
		change func(*PublicOutcome)
	}{
		{"private repository", func(o *PublicOutcome) { o.Repository = "private/project" }},
		{"self duplicate", func(o *PublicOutcome) { o.IssueNumber = 42 }},
		{"mixed fields", func(o *PublicOutcome) { o.Commit = strings.Repeat("a", 40) }},
	} {
		t.Run(tc.name, func(t *testing.T) {
			o := PublicOutcome{Kind: "duplicate", Repository: "example/project", IssueNumber: 43}
			tc.change(&o)
			p := old
			p.WorkState = "duplicate"
			p.Outcome = &o
			if validProjectionOutcome(p, "example/project", 42) {
				t.Fatal("invalid typed outcome admitted")
			}
		})
	}
}

// Each test is an isolated GitHub API. No request reaches GitHub or uses a real
// token; assertions cover public visibility and ancestry before an official POST.
func TestPublicOutcomeGitHubEvidenceBeforeWrite(t *testing.T) {
	for _, tc := range []struct {
		name, kind, fault string
		want              bool
	}{
		{"duplicate", "duplicate", "", true}, {"source", "source", "", true},
		{"release exact", "release", "exact", true}, {"release descendant", "release", "", true},
		{"release annotated tag", "release", "annotated", true},
		{"lost delivery write", "source", "uncertain", true},
		{"private repository", "source", "private", false},
		{"private reference", "source", "anonymous404", false},
		{"wrong source SHA", "source", "commit", false},
		{"PR is not duplicate", "duplicate", "pr", false},
		{"draft release", "release", "draft", false},
		{"prerelease", "release", "prerelease", false},
		{"unpublished release", "release", "unpublished", false},
		{"wrong release tag", "release", "tag", false},
		{"redirect target", "release", "redirect", false},
		{"prefix ref", "release", "prefix", false},
		{"moved tag", "release", "moved", false},
		{"tag loop", "release", "loop", false},
		{"change missing from release", "release", "diverged", false},
		{"wrong merge base", "release", "mergebase", false},
	} {
		t.Run(tc.name, func(t *testing.T) {
			c, sub := publicFixture(t)
			p := &GitHubPublisher{config: c, publicURL: c.PublicURL, token: "fixture-only"}
			r := PublicRecord{Submission: &sub, Receipt: PublicReceipt{SubmissionID: sub.Manifest.SubmissionID, RemovalState: "none"}, IssueNumber: 42, IssueNodeID: "NODE42", InputRevision: 1}
			o := &PublicOutcome{Kind: tc.kind, Repository: c.Repository}
			state := "duplicate"
			if tc.kind == "duplicate" {
				o.IssueNumber = 43
			} else {
				o.Commit = strings.Repeat("a", 40)
				state = "source-published-awaiting-release"
			}
			if tc.kind == "release" {
				o.Tag = "v3.0.1"
				o.Version = "3.0.1"
				state = "released"
			}
			v := ProjectionRequest{ID: projectionTestID, WorkflowRevision: 1, ExpectedInputRevision: 1, WorkState: state, Summary: "AI team public update.", Outcome: o}
			j := PublicJob{ID: sub.Manifest.SubmissionID, Record: r, Action: "comment-create", Contribution: &publicContribution{ID: v.ID, Digest: projectionDigest(v)}, Payload: &publicContributionPayload{Projection: &v}}
			posts := 0
			var storedComment githubComment
			f := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, rq *http.Request) {
				path := strings.TrimPrefix(rq.URL.Path, "/repos/"+c.Repository)
				respond := func(v any) { w.Header().Set("Content-Type", "application/json"); json.NewEncoder(w).Encode(v) }
				if rq.Method == "POST" {
					posts++
					var in struct{ Body string }
					json.NewDecoder(rq.Body).Decode(&in)
					comment := githubComment{ID: 101, NodeID: "C101", HTMLURL: "https://github.com/" + c.Repository + "/issues/42#issuecomment-101", IssueURL: "https://api.github.com/repos/" + c.Repository + "/issues/42", Body: in.Body}
					comment.User.ID = c.PublisherActorID
					storedComment = comment
					if tc.fault == "uncertain" {
						w.WriteHeader(502)
						return
					}
					w.WriteHeader(201)
					respond(comment)
					return
				}
				if tc.fault == "anonymous404" && rq.Header.Get("Authorization") == "" {
					w.WriteHeader(404)
					return
				}
				switch {
				case path == "":
					respond(map[string]any{"id": c.RepositoryID, "full_name": c.Repository, "private": tc.fault == "private", "has_issues": true})
				case path == "/issues/42":
					issue := githubIssue{Number: 42, NodeID: "NODE42", HTMLURL: "https://github.com/" + c.Repository + "/issues/42", Title: issueTitle(r), Body: p.issueBody(r)}
					issue.User.ID = c.PublisherActorID
					respond(issue)
				case path == "/issues/43":
					issue := githubIssue{Number: 43, HTMLURL: "https://github.com/" + c.Repository + "/issues/43"}
					if tc.fault == "pr" {
						issue.PullRequest = json.RawMessage(`{"url":"unused"}`)
					}
					respond(issue)
				case path == "/issues/42/comments":
					respond([]githubComment{storedComment})
				case strings.HasPrefix(path, "/commits/"):
					if tc.fault == "uncertain" && posts > 0 {
						w.WriteHeader(404)
						return
					}
					sha := o.Commit
					if tc.fault == "commit" {
						sha = strings.Repeat("b", 40)
					}
					respond(map[string]any{"sha": sha, "html_url": "https://github.com/" + c.Repository + "/commit/" + sha})
				case path == "/releases/tags/v3.0.1":
					tag := "v3.0.1"
					date := "2026-10-23T00:00:00Z"
					if tc.fault == "tag" {
						tag = "v3.0.0"
					}
					if tc.fault == "unpublished" {
						date = ""
					}
					if tc.fault == "redirect" {
						http.Redirect(w, rq, "https://example.invalid/private", 302)
						return
					}
					respond(map[string]any{"id": 31, "tag_name": tag, "html_url": "https://github.com/" + c.Repository + "/releases/tag/" + tag, "published_at": date, "draft": tc.fault == "draft", "prerelease": tc.fault == "prerelease"})
				case path == "/git/ref/tags/v3.0.1":
					sha := strings.Repeat("b", 40)
					kind := "commit"
					ref := "refs/tags/v3.0.1"
					if tc.fault == "exact" {
						sha = o.Commit
					}
					if tc.fault == "annotated" || tc.fault == "loop" {
						kind = "tag"
					}
					if tc.fault == "prefix" {
						ref += "0"
					}
					if tc.fault == "moved" && rq.Header.Get("Authorization") == "" {
						sha = strings.Repeat("c", 40)
					}
					respond(map[string]any{"ref": ref, "object": githubGitObject{Type: kind, SHA: sha}})
				case strings.HasPrefix(path, "/git/tags/"):
					kind := "commit"
					target := strings.Repeat("c", 40)
					if tc.fault == "loop" {
						kind = "tag"
						target = strings.Repeat("b", 40)
					}
					respond(map[string]any{"sha": strings.Repeat("b", 40), "object": githubGitObject{Type: kind, SHA: target}})
				case strings.HasPrefix(path, "/compare/"):
					status := "ahead"
					base := o.Commit
					if tc.fault == "diverged" {
						status = "diverged"
					}
					if tc.fault == "mergebase" {
						base = strings.Repeat("d", 40)
					}
					respond(map[string]any{"status": status, "base_commit": map[string]string{"sha": o.Commit}, "merge_base_commit": map[string]string{"sha": base}})
				default:
					t.Errorf("unexpected fixture route: %s", rq.URL.Path)
					w.WriteHeader(404)
				}
			}))
			defer f.Close()
			p.apiBase = f.URL
			p.http = &http.Client{CheckRedirect: func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse }}
			result := p.Publish(context.Background(), j)
			if tc.fault == "uncertain" {
				if result.Outcome != "uncertain" || posts != 1 {
					t.Fatal(result, posts)
				}
				j.Action = "comment-reconcile"
				result = p.Publish(context.Background(), j)
				if result.Outcome != "mapped" || posts != 1 {
					t.Fatal("lost write was not reconciled", result, posts)
				}
				j.Action = "comment-verify"
				if result = p.Publish(context.Background(), j); result.Outcome == "verified" || posts != 1 {
					t.Fatal("changed outcome became verified", result, posts)
				}
				return
			}
			if (result.Outcome == "mapped") != tc.want || posts != map[bool]int{true: 1, false: 0}[tc.want] {
				t.Fatal("incorrect evidence/write boundary", result, posts)
			}
		})
	}
}

func TestMulticaNativeCustomQuestionProgressAndReplay(t *testing.T) {
	s, _ := publicStoreTest(t)
	sub := nativeRuntimeSubmission(t)
	finishRoot(t, s, sub)
	h := multicaNativeHandler(s, bridgeTestBinding, nativeRuntimePolicy)
	p := ProjectionRequest{ID: projectionTestID, WorkflowRevision: 1, ExpectedInputRevision: 1, WorkState: "needs-information", Summary: "请补充具体情况。", Question: &ProjectionQuestion{ID: questionTestID, Revision: 1, Code: "custom", Description: "是哪张卡牌触发了这个问题？", TimeoutSeconds: 86400}}
	r := MulticaNativeRequest{Action: "project", CaseID: sub.Manifest.SubmissionID, Binding: bridgeTestBinding, Projection: &p}
	if w := nativeRuntimeCall(t, h, r); w.Code != 200 {
		t.Fatal(w.Code, w.Body.String())
	}
	finishChild(t, s, p.ID)
	thread, err := s.Thread(sub.Manifest.SubmissionID, testSecret, "", 5)
	if err != nil || thread.Question == nil || thread.Question.Code != "custom" || thread.Question.Description != p.Question.Description {
		t.Fatal(thread, err)
	}
	if _, _, err = s.AcceptReply(sub.Manifest.SubmissionID, testSecret, replyFixture(t, sub, replyTestID)); err != nil {
		t.Fatal(err)
	}
	finishChild(t, s, replyTestID)
	if w := nativeRuntimeCall(t, h, r); w.Code != 200 {
		t.Fatal("accepted operation retry failed after new input", w.Code, w.Body.String())
	}
	for i, state := range []string{"implementing", "reviewing", "merged-awaiting-release"} {
		p = ProjectionRequest{ID: projectionID(bridgeTestBinding, sub.Manifest.SubmissionID, int64(i+2)), WorkflowRevision: int64(i + 2), ExpectedInputRevision: 2, WorkState: state, Summary: fmt.Sprintf("AI team reports %s.", state)}
		if w := nativeRuntimeCall(t, h, r); w.Code != 200 {
			t.Fatal(w.Code, w.Body.String())
		}
		finishChild(t, s, p.ID)
	}
	if _, err = s.Remove(sub.Manifest.SubmissionID, testSecret); err != nil {
		t.Fatal(err)
	}
	thread, err = s.Thread(sub.Manifest.SubmissionID, testSecret, "", 5)
	if err != nil || len(thread.DeliveryHistory) != 0 || thread.Outcome != nil {
		t.Fatal("removed case retained outcomes", thread, err)
	}
}
