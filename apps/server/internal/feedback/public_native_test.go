// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package feedback

import (
	"context"
	"encoding/json"
	"errors"
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

// TestPublicNativeHarness is an explicitly opted-in local integration fixture.
// It runs the real receiver/publisher against a fake GitHub HTTP API. Production
// binaries have neither the injected endpoints nor this environment interface.
func TestPublicNativeHarness(t *testing.T) {
	dir := os.Getenv("HEXPROOF_FEEDBACK_NATIVE_OUTPUT")
	if dir == "" {
		t.Skip("requires an explicit isolated native verification output directory")
	}
	root, err := filepath.Abs("../../../../build")
	if err != nil || !filepath.IsAbs(dir) || !strings.HasPrefix(filepath.Clean(dir)+string(os.PathSeparator), root+string(os.PathSeparator)) {
		t.Fatal("native fixture output must be an absolute build subdirectory")
	}
	if err := os.MkdirAll(dir, 0700); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(filepath.Join(dir, "ready.json")); !os.IsNotExist(err) {
		t.Fatal("native fixture output has already been used")
	}
	var contract struct {
		NoticeText string `json:"noticeText"`
	}
	raw, err := os.ReadFile("../../../../testdata/feedback/v2/contract.json")
	if err != nil || json.Unmarshal(raw, &contract) != nil {
		t.Fatal("shared public fixture unavailable")
	}
	c := PublicConfig{DataDir: filepath.Join(dir, "public"), Repository: "example/project", RepositoryID: 123,
		PublisherActorID: 456, NoticeRevision: "public-v1", NoticeText: contract.NoticeText, ProviderPolicyRevision: "none-v1"}
	aiFlow := os.Getenv("HEXPROOF_FEEDBACK_NATIVE_AI_FLOW") == "1"
	if aiFlow {
		c.ProviderPolicyRevision = nativeRuntimePolicy
	}
	store, err := OpenPublicStore(c.DataDir, Limits{})
	if err != nil {
		t.Fatal(err)
	}
	defer store.Close()
	receiver := httptest.NewUnstartedServer(nil)
	c.PublicURL = "http://" + receiver.Listener.Addr().String() + "/feedback/v2"
	handler := NewPublicHandler(store, c, nil, Limits{}, nil)
	defer handler.Close()
	receiver.Config.Handler = handler
	receiver.Start()
	defer receiver.Close()
	threadMode := os.Getenv("HEXPROOF_FEEDBACK_NATIVE_THREAD") == "1" || aiFlow
	var mu sync.Mutex
	issues := map[int]map[string]any{}
	locked := map[int]bool{}
	comments := map[int64]map[string]any{}
	commentIssues := map[int64]int{}
	commentCreates, commentDeletes := 0, 0
	creates, deletes, reads := 0, 0, 0
	fake := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		mu.Lock()
		defer mu.Unlock()
		w.Header().Set("Content-Type", "application/json")
		if r.Header.Get("Authorization") != "" && r.Header.Get("Authorization") != "Bearer native-fixture-only" {
			http.Error(w, "unexpected credential", http.StatusForbidden)
			return
		}
		if r.Method != "GET" && r.Header.Get("Authorization") != "Bearer native-fixture-only" {
			http.Error(w, "mutation requires fixture credential", http.StatusUnauthorized)
			return
		}
		respond := func(status int, body any) { w.WriteHeader(status); _ = json.NewEncoder(w).Encode(body) }
		switch {
		case r.Method == "GET" && r.URL.Path == "/repos/example/project":
			respond(200, map[string]any{"id": 123, "full_name": "example/project", "private": false, "has_issues": true})
		case aiFlow && r.Method == "GET" && r.URL.Path == "/repos/example/project/commits/"+strings.Repeat("a", 40):
			respond(200, map[string]any{"sha": strings.Repeat("a", 40), "html_url": "https://github.com/example/project/commit/" + strings.Repeat("a", 40)})
		case aiFlow && r.Method == "GET" && r.URL.Path == "/repos/example/project/releases/tags/v3.0.1":
			respond(200, map[string]any{"id": 31, "tag_name": "v3.0.1", "html_url": "https://github.com/example/project/releases/tag/v3.0.1", "draft": false, "prerelease": false, "published_at": "2026-10-23T00:00:00Z"})
		case aiFlow && r.Method == "GET" && r.URL.Path == "/repos/example/project/git/ref/tags/v3.0.1":
			respond(200, map[string]any{"ref": "refs/tags/v3.0.1", "object": map[string]string{"type": "commit", "sha": strings.Repeat("a", 40)}})
		case r.Method == "POST" && r.URL.Path == "/repos/example/project/issues":
			var body map[string]string
			if json.NewDecoder(http.MaxBytesReader(w, r.Body, 128<<10)).Decode(&body) != nil {
				respond(400, map[string]string{"message": "invalid fixture request"})
				return
			}
			creates++
			n := creates
			issue := map[string]any{"number": n, "node_id": "I_native_" + strconv.Itoa(n),
				"html_url": "https://github.com/example/project/issues/" + strconv.Itoa(n),
				"body":     body["body"], "title": body["title"], "comments": 0, "state": "open",
				"user": map[string]int{"id": 456}}
			issues[n] = issue
			respond(201, issue)
		case r.Method == "GET" && r.URL.Path == "/repos/example/project/issues":
			all := []map[string]any{}
			for _, issue := range issues {
				all = append(all, issue)
			}
			respond(200, all)
		case r.Method == "PATCH" && strings.HasPrefix(r.URL.Path, "/repos/example/project/issues/"):
			n, _ := strconv.Atoi(strings.TrimPrefix(r.URL.Path, "/repos/example/project/issues/"))
			var body map[string]string
			if issues[n] == nil {
				respond(404, map[string]string{"message": "Not Found"})
				return
			}
			if json.NewDecoder(http.MaxBytesReader(w, r.Body, 128<<10)).Decode(&body) != nil || len(body) != 2 || body["state"] != "closed" || body["state_reason"] != "not_planned" {
				respond(400, map[string]string{"message": "invalid closure request"})
				return
			}
			issues[n]["state"] = "closed"
			respond(200, issues[n])
		case r.Method == "PUT" && strings.HasPrefix(r.URL.Path, "/repos/example/project/issues/") && strings.HasSuffix(r.URL.Path, "/lock"):
			n, _ := strconv.Atoi(strings.TrimSuffix(strings.TrimPrefix(r.URL.Path, "/repos/example/project/issues/"), "/lock"))
			if issues[n] == nil {
				respond(404, map[string]string{"message": "Not Found"})
				return
			}
			locked[n] = true
			w.WriteHeader(http.StatusNoContent)

		case threadMode && strings.HasSuffix(r.URL.Path, "/comments") && strings.HasPrefix(r.URL.Path, "/repos/example/project/issues/"):
			n, _ := strconv.Atoi(strings.TrimSuffix(strings.TrimPrefix(r.URL.Path, "/repos/example/project/issues/"), "/comments"))
			if issues[n] == nil {
				respond(404, map[string]string{"message": "Not Found"})
				return
			}
			if r.Method == "GET" {
				list := []map[string]any{}
				for id, c := range comments {
					if commentIssues[id] == n {
						list = append(list, c)
					}
				}
				respond(200, list)
				return
			}
			if r.Method != "POST" || locked[n] {
				respond(409, map[string]string{"message": "locked or invalid comment request"})
				return
			}
			var body map[string]string
			if json.NewDecoder(http.MaxBytesReader(w, r.Body, 128<<10)).Decode(&body) != nil {
				respond(400, map[string]string{"message": "invalid request"})
				return
			}
			commentCreates++
			id := int64(commentCreates)
			c := map[string]any{"id": id, "node_id": "C_native_" + strconv.FormatInt(id, 10), "html_url": "https://github.com/example/project/issues/" + strconv.Itoa(n) + "#issuecomment-" + strconv.FormatInt(id, 10), "issue_url": "https://api.github.com/repos/example/project/issues/" + strconv.Itoa(n), "body": body["body"], "user": map[string]int{"id": 456}}
			comments[id] = c
			commentIssues[id] = n
			issues[n]["comments"] = issues[n]["comments"].(int) + 1
			respond(201, c)
		case threadMode && strings.HasPrefix(r.URL.Path, "/repos/example/project/issues/comments/"):
			id, _ := strconv.ParseInt(strings.TrimPrefix(r.URL.Path, "/repos/example/project/issues/comments/"), 10, 64)
			c, ok := comments[id]
			if !ok {
				respond(404, map[string]string{"message": "Not Found"})
				return
			}
			if r.Method == "GET" {
				respond(200, c)
				return
			}
			n := commentIssues[id]
			if r.Method != "DELETE" || !locked[n] {
				respond(409, map[string]string{"message": "comment removal requires locked parent"})
				return
			}
			delete(comments, id)
			delete(commentIssues, id)
			commentDeletes++
			issues[n]["comments"] = issues[n]["comments"].(int) - 1
			w.WriteHeader(204)
		case r.Method == "GET" && strings.HasPrefix(r.URL.Path, "/repos/example/project/issues/"):
			reads++
			n, _ := strconv.Atoi(strings.TrimPrefix(r.URL.Path, "/repos/example/project/issues/"))
			if issue, ok := issues[n]; ok {
				respond(200, issue)
			} else {
				respond(404, map[string]string{"message": "Not Found"})
			}
		case r.Method == "POST" && r.URL.Path == "/graphql":
			var body struct {
				Query     string `json:"query"`
				Variables struct {
					Input map[string]string `json:"input"`
				} `json:"variables"`
			}
			if json.NewDecoder(http.MaxBytesReader(w, r.Body, 16<<10)).Decode(&body) != nil || !strings.Contains(body.Query, "deleteIssue") {
				respond(400, map[string]string{"message": "unsupported fixture operation"})
				return
			}
			for n, issue := range issues {
				if body.Variables.Input["issueId"] == issue["node_id"] && locked[n] && issue["comments"].(int) == 0 {
					delete(issues, n)
					deletes++
					respond(200, map[string]any{"data": map[string]any{"deleteIssue": map[string]any{"clientMutationId": body.Variables.Input["clientMutationId"]}}})
					return
				}
			}
			respond(200, map[string]any{"errors": []map[string]string{{"message": "unknown or unlocked fixture issue"}}})
		default:
			respond(404, map[string]string{"message": "unknown local fixture route"})
		}
	}))
	defer fake.Close()
	publisher := &GitHubPublisher{config: c, publicURL: receiver.URL + "/feedback/v2", apiBase: fake.URL,
		graphqlURL: fake.URL + "/graphql", token: "native-fixture-only",
		http: &http.Client{Timeout: 5 * time.Second, CheckRedirect: func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse }}}
	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan struct{})
	go func() { defer close(done); RunPublicOutbox(ctx, store, publisher) }()
	defer func() { cancel(); <-done }()
	write := func(name string, value any) {
		raw, err := json.MarshalIndent(value, "", "  ")
		if err != nil || os.WriteFile(filepath.Join(dir, name), append(raw, '\n'), 0600) != nil {
			t.Fatal("fixture artifact write failed")
		}
	}
	write("client-config.json", map[string]any{"schemaVersion": 2, "enabled": true, "apiBase": publisher.publicURL,
		"supportLabel": "Local public feedback verification", "privacyUrl": receiver.URL + "/privacy",
		"receiptOnlyApiBases": []string{}, "publicRepository": c.Repository, "noticeRevision": c.NoticeRevision,
		"noticeText": c.NoticeText, "providerPolicyRevision": c.ProviderPolicyRevision})
	write("ready.json", map[string]any{"localOnly": true, "apiBase": publisher.publicURL, "threadMode": threadMode, "aiFlow": aiFlow})
	deadline := time.NewTimer(8 * time.Minute)
	defer deadline.Stop()
	ticker := time.NewTicker(100 * time.Millisecond)
	defer ticker.Stop()
	for {
		select {
		case <-deadline.C:
			t.Fatal("native fixture watchdog expired")
		case <-ticker.C:
			if threadMode {
				binding := hashBytes([]byte("native-coordinator-fixture-only"))
				for _, id := range store.ListCaseIDs() {
					snapshot, e := store.ExportCase(id, binding)
					if e != nil {
						continue
					}
					if snapshot.State == "removed" {
						if e = store.AcknowledgeRevocation(id, binding, snapshot.RevocationRevision); e != nil {
							t.Fatal(e)
						}
						continue
					}
					p := ProjectionRequest{ID: projectionID(binding, id, 1), WorkflowRevision: 1, ExpectedInputRevision: 1, WorkState: "needs-information", Summary: "The local fixture requests reproduction details.", Question: &ProjectionQuestion{ID: projectionID(binding, id, 1001), Revision: 1, Code: "reproduction_steps", Description: "Please provide the steps needed to reproduce this behavior.", TimeoutSeconds: 86400}}
					if snapshot.InputRevision >= 2 {
						p = ProjectionRequest{ID: projectionID(binding, id, 2), WorkflowRevision: 2, ExpectedInputRevision: snapshot.InputRevision, WorkState: "ready", Summary: "The local fixture received the published reply and completed its simulated assessment."}
					}
					if aiFlow {
						if snapshot.State != "active" {
							continue
						}
						h := multicaNativeHandler(store, binding, nativeRuntimePolicy)
						if w := nativeRuntimeCall(t, h, MulticaNativeRequest{Action: "snapshot", CaseID: id, Binding: binding}); w.Code != 200 {
							t.Fatal(w.Code, w.Body.String())
						}
						p.Summary = "请补充触发问题时的具体操作，AI 团队将据此核实。"
						if snapshot.InputRevision == 1 {
							p.Question.Code, p.Question.Description = "custom", "这次问题发生在手动模式还是 Forge 规则模式？请告诉我们涉及的卡牌名称，以及点击了哪个按钮。"
						} else if snapshot.InputRevision == 2 {
							p = deliveryProjectionFixture(snapshot, "source-published-awaiting-release", 2)
							p.ID = projectionID(binding, id, 2)
							p.Summary = "AI 团队已完成修复并同步公开源码，正在等待发版。"
							if snapshot.LatestProjection != nil && snapshot.LatestProjection.WorkflowRevision >= 2 && snapshot.LatestProjection.PublicationState == "published" {
								p = deliveryProjectionFixture(snapshot, "released", 3)
								p.ID = projectionID(binding, id, 3)
								p.Summary = "修复已随 3.0.1 正式发布。请更新后确认问题是否解决。"
							}
						} else {
							p = ProjectionRequest{ID: projectionID(binding, id, snapshot.InputRevision+1), WorkflowRevision: snapshot.InputRevision + 1, ExpectedInputRevision: snapshot.InputRevision, WorkState: "assessing", Summary: "已收到更新后的情况。AI 团队正在重新核实；之前的版本交付记录仍然保留。"}
						}
						w := nativeRuntimeCall(t, h, MulticaNativeRequest{Action: "project", CaseID: id, Binding: binding, Projection: &p})
						if w.Code != 200 && w.Code != 409 && w.Code != 410 {
							t.Fatal(w.Code, w.Body.String())
						}
						continue
					}
					if _, e = store.EnqueueProjection(id, binding, p); e != nil && !errors.Is(e, ErrConflict) && !errors.Is(e, ErrExpired) {
						t.Fatal(e)
					}
				}
			}
			if _, err := os.Stat(filepath.Join(dir, "stop")); err == nil {
				cancel()
				<-done
				mu.Lock()
				counts := map[string]any{"issueCreates": creates, "issueDeletes": deletes, "issueReads": reads, "remainingIssues": len(issues), "externalRequests": false, "commentCreates": commentCreates, "commentDeletes": commentDeletes, "remainingComments": len(comments), "simulatedCoordinator": threadMode}
				mu.Unlock()
				write("github-evidence.json", counts)
				return
			}
		}
	}
}
