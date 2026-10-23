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

func TestPublicCloseGitHubIdentityMutationAndIndependentReadback(t *testing.T) {
	for _, test := range []struct {
		name, outcome string
		patches       int
	}{
		{"normal", "closed", 1},
		{"already-closed", "closed", 0},
		{"edited-body", "stalled", 0},
		{"wrong-node", "stalled", 0},
		{"wrong-number", "stalled", 0},
		{"wrong-author", "stalled", 0},
		{"permission-denied", "stalled", 1},
		{"uncertain-applied", "closed", 1},
		{"uncertain-not-applied", "retry", 1},
		{"anonymous-still-open", "retry", 1},
		{"anonymous-edited", "stalled", 1},
		{"notice-changed", "closed", 1},
	} {
		t.Run(test.name, func(t *testing.T) {
			config, sub := publicFixture(t)
			r := PublicRecord{Receipt: PublicReceipt{SubmissionID: sub.Manifest.SubmissionID, CaseState: "closed", ClosurePublicationState: "pending", RemovalState: "none"}, Submission: &sub, Digest: sub.Digest, IssueNumber: 42, IssueNodeID: "NODE42"}
			p := &GitHubPublisher{config: config, publicURL: config.PublicURL, token: "closure-fixture-only"}
			issue := githubIssue{Number: 42, NodeID: "NODE42", HTMLURL: "https://github.com/example/project/issues/42", Title: issueTitle(r), Body: p.issueBody(r), State: "open"}
			issue.User.ID = config.PublisherActorID
			switch test.name {
			case "already-closed":
				issue.State = "closed"
			case "edited-body":
				issue.Body += "edited"
			case "wrong-node":
				issue.NodeID = "OTHER"
			case "wrong-number":
				issue.Number = 43
			case "wrong-author":
				issue.User.ID++
			case "notice-changed":
				p.config.NoticeRevision = "later-notice-v2"
			}
			patches, authenticatedReads, publicReads := 0, 0, 0
			server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, request *http.Request) {
				w.Header().Set("Content-Type", "application/json")
				authenticated := request.Header.Get("Authorization") == "Bearer closure-fixture-only"
				if request.URL.Path == "/repos/example/project" && request.Method == "GET" {
					if !authenticated {
						t.Error("repository identity was not authenticated")
					}
					_ = json.NewEncoder(w).Encode(map[string]any{"id": 17, "full_name": "example/project", "private": false, "has_issues": true})
					return
				}
				if request.URL.Path != "/repos/example/project/issues/42" {
					t.Errorf("unexpected closure path %s", request.URL.Path)
					w.WriteHeader(404)
					return
				}
				if request.Method == "PATCH" {
					patches++
					var body map[string]string
					if !authenticated || json.NewDecoder(request.Body).Decode(&body) != nil || len(body) != 2 || body["state"] != "closed" || body["state_reason"] != "not_planned" {
						t.Error("closure changed content or omitted authentication")
						w.WriteHeader(400)
						return
					}
					if test.name == "permission-denied" {
						w.WriteHeader(403)
						return
					}
					if test.name != "uncertain-not-applied" {
						issue.State = "closed"
					}
					if test.name == "uncertain-applied" || test.name == "uncertain-not-applied" {
						w.WriteHeader(502)
						return
					}
					_ = json.NewEncoder(w).Encode(issue)
					return
				}
				if request.Method != "GET" {
					t.Errorf("closure attempted %s", request.Method)
					w.WriteHeader(405)
					return
				}
				current := issue
				if authenticated {
					authenticatedReads++
				} else {
					publicReads++
					if test.name == "anonymous-still-open" {
						current.State = "open"
					}
					if test.name == "anonymous-edited" {
						current.Body += "edited public projection"
					}
				}
				_ = json.NewEncoder(w).Encode(current)
			}))
			defer server.Close()
			p.apiBase, p.http = server.URL, server.Client()
			result := p.Publish(context.Background(), PublicJob{ID: sub.Manifest.SubmissionID, Record: r, Action: "close"})
			if result.Outcome != test.outcome || patches != test.patches {
				t.Fatal(result, patches)
			}
			if result.Outcome == "closed" && (authenticatedReads != 2 || publicReads != 1) {
				t.Fatal("closure claimed without both independent readbacks", authenticatedReads, publicReads)
			}
		})
	}
}
