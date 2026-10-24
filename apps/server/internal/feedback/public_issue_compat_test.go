// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package feedback

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
)

func legacyIssueFixture(t *testing.T) (*GitHubPublisher, PublicRecord, githubIssue) {
	t.Helper()
	config, sub := publicFixture(t)
	p := &GitHubPublisher{config: config, publicURL: config.PublicURL, token: "legacy-fixture-only"}
	r := PublicRecord{Receipt: PublicReceipt{SubmissionID: sub.Manifest.SubmissionID, CaseState: "open", RemovalState: "none"}, Submission: &sub, Digest: sub.Digest, IssueNumber: 42, IssueNodeID: "NODE42"}
	// This is the pre-upgrade projection, independent of both current renderers.
	// Changes must not strand already-published issues or uncertain creations.
	issue := githubIssue{
		Number: 42, NodeID: "NODE42", HTMLURL: "https://github.com/example/project/issues/42", State: "open",
		Title: "[Client feedback: problem] 83bd35d6-dd11-4a73-9f35-4ed43b6ab8b1",
		Body: "Public feedback submitted from Hexproof. Development assessment has not started.\n\n" +
			"Submitted at: 2026-10-22T12:00:00Z\n\n## Description\n\n" +
			"```text\nThe Forge game stopped while resolving a spell.\n```\n\n## Technical context\n\n" +
			"```text\n{\n  \"appVersion\": \"3.0.0\",\n  \"osFamily\": \"linux\",\n" +
			"  \"architecture\": \"x86_64\",\n  \"uiLanguage\": \"zh_CN\",\n" +
			"  \"feature\": \"forge_table\",\n  \"gameMode\": \"forge\",\n  \"format\": \"commander\"\n}\n```\n\n" +
			"## Attachments\n\nNone.\n\nAttachment descriptors:\n\n```text\n[]\n```\n\n" +
			"Disclosure: `public-v1`; provider policy: `none-v1`; disclosure SHA-256: `afde3dd2b1c6a274d7c41a0c869c8f91b21a3c801534a971c7f45f8f065367f4`.\n\n" +
			"<!-- hexproof-public-v2 83bd35d6-dd11-4a73-9f35-4ed43b6ab8b1 9c9c487f6ea2a71bcf9a9d5a68548cd38986cee41d92e661931223863c139801 -->\n",
	}
	issue.User.ID = config.PublisherActorID
	return p, r, issue
}

func TestPublicIssueOwnsOnlyCompleteCurrentOrLegacyProjection(t *testing.T) {
	p, r, legacy := legacyIssueFixture(t)
	if legacyIssueTitle(r) != legacy.Title || p.legacyIssueBody(r) != legacy.Body {
		t.Fatal("legacy projection no longer matches the published bytes")
	}
	current := legacy
	current.Title, current.Body = issueTitle(r), p.issueBody(r)
	if current.Title == legacy.Title || current.Body == legacy.Body {
		t.Fatal("fixture does not distinguish current and legacy projections")
	}
	for _, projection := range []struct {
		name         string
		issue, other githubIssue
	}{
		{"current", current, legacy},
		{"legacy", legacy, current},
	} {
		t.Run(projection.name, func(t *testing.T) {
			if !p.owned(projection.issue, r) {
				t.Fatal("exact authorized projection was rejected")
			}
			for _, test := range []struct {
				name   string
				mutate func(*githubIssue)
			}{
				{"mixed-title", func(issue *githubIssue) { issue.Title = projection.other.Title }},
				{"mixed-body", func(issue *githubIssue) { issue.Body = projection.other.Body }},
				{"edited-title", func(issue *githubIssue) { issue.Title += " edited" }},
				{"edited-body", func(issue *githubIssue) { issue.Body += " edited" }},
				{"copied-marker", func(issue *githubIssue) {
					issue.Body = "Different content.\n<!-- hexproof-public-v2 " + r.Receipt.SubmissionID + " " + r.Digest + " -->\n"
				}},
				{"wrong-author", func(issue *githubIssue) { issue.User.ID++ }},
				{"wrong-url", func(issue *githubIssue) { issue.HTMLURL = "https://github.com/other/project/issues/42" }},
				{"pull-request", func(issue *githubIssue) {
					issue.PullRequest = json.RawMessage(`{"url":"https://api.github.com/repos/example/project/pulls/42"}`)
				}},
			} {
				t.Run(test.name, func(t *testing.T) {
					issue := projection.issue
					test.mutate(&issue)
					if p.owned(issue, r) {
						t.Fatal("changed or unowned projection was accepted")
					}
				})
			}
		})
	}
}

func TestPublicLegacyIssueReconcilesVerifiesAndRemoves(t *testing.T) {
	for _, test := range []struct {
		action, outcome string
		deletes         int
	}{
		{"reconcile", "mapped", 0},
		{"verify", "verified", 0},
		{"remove", "removed", 1},
	} {
		t.Run(test.action, func(t *testing.T) {
			p, r, issue := legacyIssueFixture(t)
			f := fakeGitHub(t, p)
			f.issue = &issue
			if test.action == "reconcile" {
				r.IssueNumber, r.IssueNodeID = 0, ""
				r.CreateUncertain = true
			}
			if test.action == "remove" {
				r.Receipt.RemovalState = "pending"
			}
			result := p.Publish(context.Background(), PublicJob{ID: r.Receipt.SubmissionID, Record: r, Action: test.action})
			if result.Outcome != test.outcome || f.creates != 0 || f.deletes != test.deletes {
				t.Fatal(result, f.creates, f.deletes)
			}
			if test.action != "remove" && (result.IssueNumber != 42 || result.IssueNodeID != "NODE42" || result.IssueURL != issue.HTMLURL) {
				t.Fatal("legacy issue mapping changed", result)
			}
		})
	}
}

func TestPublicLegacyIssueClosesWithoutRewritingContent(t *testing.T) {
	p, r, issue := legacyIssueFixture(t)
	r.Receipt.CaseState = "closed"
	r.Receipt.ClosurePublicationState = "pending"
	patches, authenticatedReads, publicReads := 0, 0, 0
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, request *http.Request) {
		authenticated := request.Header.Get("Authorization") == "Bearer legacy-fixture-only"
		switch {
		case request.Method == "GET" && request.URL.Path == "/repos/example/project":
			if !authenticated {
				t.Error("repository identity was not authenticated")
			}
			writeJSON(w, 200, map[string]any{"id": 17, "full_name": "example/project", "private": false, "has_issues": true})
		case request.Method == "GET" && request.URL.Path == "/repos/example/project/issues/42":
			if authenticated {
				authenticatedReads++
			} else {
				publicReads++
			}
			writeJSON(w, 200, issue)
		case request.Method == "PATCH" && request.URL.Path == "/repos/example/project/issues/42":
			patches++
			var body map[string]string
			if !authenticated || json.NewDecoder(request.Body).Decode(&body) != nil || len(body) != 2 || body["state"] != "closed" || body["state_reason"] != "not_planned" {
				t.Error("closure attempted to rewrite legacy content or omitted authentication")
				w.WriteHeader(400)
				return
			}
			issue.State = "closed"
			writeJSON(w, 200, issue)
		default:
			t.Errorf("unexpected request: %s %s", request.Method, request.URL.Path)
			w.WriteHeader(404)
		}
	}))
	defer server.Close()
	p.apiBase, p.http = server.URL, server.Client()
	result := p.Publish(context.Background(), PublicJob{ID: r.Receipt.SubmissionID, Record: r, Action: "close"})
	if result.Outcome != "closed" || patches != 1 || authenticatedReads != 2 || publicReads != 1 {
		t.Fatal(result, patches, authenticatedReads, publicReads)
	}
}
