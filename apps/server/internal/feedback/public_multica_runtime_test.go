// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package feedback

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"net"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

const nativeRuntimePolicy = "synthetic-multica-v1"

func nativeRuntimeSubmission(t *testing.T) PublicSubmission {
	t.Helper()
	_, sub := publicFixture(t)
	sub.Manifest.Disclosure.ProviderPolicyRevision = nativeRuntimePolicy
	sub.ManifestBytes, _ = json.Marshal(sub.Manifest)
	sub.Digest = PublicDigest(sub.ManifestBytes)
	return sub
}

type nativeRuntimeSender struct {
	events  []MulticaEvent
	keys    []string
	status  string
	runless bool
	err     error
}

func (s *nativeRuntimeSender) Binding() string { return bridgeTestBinding }
func (s *nativeRuntimeSender) Send(_ context.Context, event MulticaEvent, key string) (MulticaDeliveryResult, error) {
	s.events = append(s.events, event)
	s.keys = append(s.keys, key)
	result := MulticaDeliveryResult{Status: s.status, DeliveryID: multicaTestDelivery, RunID: multicaTestRun}
	if s.runless {
		result.RunID = ""
	}
	return result, s.err
}

func nativeRuntimeCall(t *testing.T, h http.Handler, request MulticaNativeRequest) *httptest.ResponseRecorder {
	t.Helper()
	raw, err := json.Marshal(request)
	if err != nil {
		t.Fatal(err)
	}
	w := httptest.NewRecorder()
	h.ServeHTTP(w, httptest.NewRequest("POST", "/public-native", bytes.NewReader(raw)))
	return w
}

func TestMulticaNativeFeedbackRoundTrip(t *testing.T) {
	s, _ := publicStoreTest(t)
	sub := nativeRuntimeSubmission(t)
	id := sub.Manifest.SubmissionID
	finishRoot(t, s, sub)
	sender := &nativeRuntimeSender{status: "accepted"}
	deliverMulticaEvents(context.Background(), s, sender, nativeRuntimePolicy)
	deliverMulticaEvents(context.Background(), s, sender, nativeRuntimePolicy)
	if len(sender.events) != 1 || sender.events[0].InputRevision != 1 {
		t.Fatalf("duplicate or missing native event: %+v", sender.events)
	}
	raw, _ := json.Marshal(sender.events[0])
	if bytes.Contains(raw, []byte(sub.Manifest.Description)) || bytes.Contains(raw, []byte("https:")) || bytes.Contains(raw, testSecret) {
		t.Fatal("notification exported feedback content or credentials")
	}
	h := multicaNativeHandler(s, bridgeTestBinding, nativeRuntimePolicy)
	request := MulticaNativeRequest{Action: "snapshot", CaseID: id, Binding: bridgeTestBinding}
	w := nativeRuntimeCall(t, h, request)
	var result MulticaNativeResult
	if w.Code != 200 || json.Unmarshal(w.Body.Bytes(), &result) != nil || result.Snapshot == nil || len(result.Snapshot.Contributions) != 1 {
		t.Fatal(w.Code, w.Body.String())
	}
	p := ProjectionRequest{ID: projectionTestID, WorkflowRevision: 1, ExpectedInputRevision: 1, WorkState: "needs-information", Summary: "Please provide reproduction details.", Question: &ProjectionQuestion{ID: questionTestID, Revision: 1, Code: "reproduction_steps", Description: "What steps reproduce this problem?", TimeoutSeconds: 3600}}
	request.Action, request.Projection = "project", &p
	w = nativeRuntimeCall(t, h, request)
	if w.Code != 200 {
		t.Fatal(w.Code, w.Body.String())
	}
	if w = nativeRuntimeCall(t, h, request); w.Code != 200 {
		t.Fatal("projection retry not idempotent", w.Code)
	}
	thread, err := s.Thread(id, testSecret, "", 5)
	if err != nil || thread.Question != nil || thread.ProjectionState != "pending" {
		t.Fatal("unverified public question leaked", thread, err)
	}
	finishChild(t, s, p.ID)
	thread, err = s.Thread(id, testSecret, "", 5)
	if err != nil || thread.Question == nil || thread.WorkState != "needs-information" {
		t.Fatal(thread, err)
	}
	deliverMulticaEvents(context.Background(), s, sender, nativeRuntimePolicy)
	if len(sender.events) != 1 {
		t.Fatal("projection publication triggered an AI notification loop")
	}
	reply := replyFixture(t, sub, replyTestID)
	reply.Manifest.QuestionID, reply.Manifest.QuestionRevision = questionTestID, 1
	reply.ManifestBytes, _ = json.Marshal(reply.Manifest)
	reply.Digest = PublicReplyDigest(reply.ManifestBytes)
	if _, _, err = s.AcceptReply(id, testSecret, reply); err != nil {
		t.Fatal(err)
	}
	deliverMulticaEvents(context.Background(), s, sender, nativeRuntimePolicy)
	if len(sender.events) != 1 {
		t.Fatal("unpublished reply notified native AI")
	}
	request.Action, request.Projection = "snapshot", nil
	w = nativeRuntimeCall(t, h, request)
	if w.Code != 200 || bytes.Contains(w.Body.Bytes(), []byte(reply.Manifest.Description)) {
		t.Fatal("unpublished reply exported", w.Code, w.Body.String())
	}
	finishChild(t, s, replyTestID)
	deliverMulticaEvents(context.Background(), s, sender, nativeRuntimePolicy)
	if len(sender.events) != 2 || sender.events[1].InputRevision != 2 || sender.keys[1] == sender.keys[0] {
		t.Fatal(sender.events, sender.keys)
	}
	p.ID, p.WorkflowRevision = "4a964a0d-4cb4-498d-82b0-d0c95a5f8e7e", 2
	request.Action, request.Projection = "project", &p
	if w = nativeRuntimeCall(t, h, request); w.Code == 200 {
		t.Fatal("stale input assessment accepted")
	}
	p.ExpectedInputRevision, p.WorkState, p.Question = 2, "ready", nil
	p.Summary = "The published reproduction details are sufficient for assessment."
	if w = nativeRuntimeCall(t, h, request); w.Code != 200 {
		t.Fatal(w.Code, w.Body.String())
	}
	finishChild(t, s, p.ID)
	if _, err = s.Remove(id, testSecret); err != nil {
		t.Fatal(err)
	}
	deliverMulticaEvents(context.Background(), s, sender, nativeRuntimePolicy)
	if len(sender.events) != 3 || sender.events[2].Event != "hexproof.feedback.removed" {
		t.Fatal(sender.events)
	}
	request.Action, request.Projection = "snapshot", nil
	w = nativeRuntimeCall(t, h, request)
	if w.Code != 200 || !strings.Contains(w.Body.String(), `"State":"removed"`) || bytes.Contains(w.Body.Bytes(), []byte(sub.Manifest.Description)) {
		t.Fatal(w.Code, w.Body.String())
	}
	request.Action, request.Projection = "project", &p
	if w = nativeRuntimeCall(t, h, request); w.Code != 410 {
		t.Fatal("removed case accepted projection", w.Code)
	}
	request.Action, request.Projection = "ack-revocation", nil
	if w = nativeRuntimeCall(t, h, request); w.Code != 400 {
		t.Fatal("unqualified purge acknowledgment exposed", w.Code)
	}
	thread, err = s.Thread(id, testSecret, "", 5)
	if err != nil || thread.RemovalState == "removed" {
		t.Fatal("native notification falsely completed removal", thread, err)
	}
}

func TestMulticaNativeDeliveryHealthIsNotExecution(t *testing.T) {
	for _, tc := range []struct {
		name, status  string
		runless, lost bool
	}{
		{"accepted", "accepted", false, false},
		{"duplicate", "duplicate", false, false},
		{"duplicate without run", "duplicate", true, false},
		{"skipped", "skipped", false, false},
		{"ignored", "ignored", true, false},
		{"pending", "pending", false, true},
	} {
		t.Run(tc.name, func(t *testing.T) {
			s, now := publicStoreTest(t)
			sub := nativeRuntimeSubmission(t)
			finishRoot(t, s, sub)
			sender := &nativeRuntimeSender{status: tc.status, runless: tc.runless}
			if tc.lost {
				sender.err = errors.New("simulated lost response")
			}
			deliverMulticaEvents(context.Background(), s, sender, nativeRuntimePolicy)
			thread, err := s.Thread(sub.Manifest.SubmissionID, testSecret, "", 5)
			if err != nil || (thread.AssessmentDeliveryState == "available") != (tc.status == "accepted") || thread.WorkState != "new" {
				t.Fatal(thread, err)
			}
			if !tc.lost {
				wantRun := multicaTestRun
				if tc.runless {
					wantRun = ""
				}
				r, _, err := s.read(sub.Manifest.SubmissionID)
				if err != nil || r.MulticaDelivery == nil || r.MulticaDelivery.Status != tc.status ||
					r.MulticaDelivery.DeliveryID != multicaTestDelivery || r.MulticaDelivery.RunID != wantRun {
					t.Fatal("terminal receipt was not persisted with its identity", r.MulticaDelivery, err)
				}
			}
			*now = now.Add(24 * time.Hour)
			deliverMulticaEvents(context.Background(), s, sender, nativeRuntimePolicy)
			if !tc.lost && len(sender.events) != 1 {
				t.Fatal("settled event retried", sender.events)
			}
			if tc.lost && (len(sender.events) != 2 || sender.keys[0] != sender.keys[1]) {
				t.Fatal("lost response changed idempotency key", sender.keys)
			}
		})
	}
}

func TestMulticaNativeRejectsUnauthorizedOutputs(t *testing.T) {
	s, _ := publicStoreTest(t)
	sub := nativeRuntimeSubmission(t)
	finishRoot(t, s, sub)
	h := multicaNativeHandler(s, bridgeTestBinding, nativeRuntimePolicy)
	p := ProjectionRequest{ID: projectionTestID, WorkflowRevision: 1, ExpectedInputRevision: 1, WorkState: "ready", Summary: "Public assessment."}
	for _, test := range []struct {
		name   string
		mutate func(*MulticaNativeRequest)
	}{
		{"wrong binding", func(r *MulticaNativeRequest) { r.Binding = strings.Repeat("b", 64) }},
		{"release", func(r *MulticaNativeRequest) { r.Projection.WorkState = "released" }},
		{"source without evidence", func(r *MulticaNativeRequest) { r.Projection.WorkState = "source-published-awaiting-release" }},
		{"private link", func(r *MulticaNativeRequest) { r.Projection.Summary = "See https://github.com/private/project/pull/1" }},
		{"no question", func(r *MulticaNativeRequest) { r.Projection.WorkState = "needs-information" }},
		{"ack", func(r *MulticaNativeRequest) { r.Action = "ack-revocation"; r.Projection = nil }},
	} {
		t.Run(test.name, func(t *testing.T) {
			candidate := p
			r := MulticaNativeRequest{Action: "project", CaseID: sub.Manifest.SubmissionID, Binding: bridgeTestBinding, Projection: &candidate}
			test.mutate(&r)
			if w := nativeRuntimeCall(t, h, r); w.Code == 200 {
				t.Fatal("unsafe native output accepted")
			}
		})
	}
	if w := nativeRuntimeCall(t, multicaNativeHandler(s, bridgeTestBinding, "different-policy"), MulticaNativeRequest{Action: "snapshot", CaseID: sub.Manifest.SubmissionID, Binding: bridgeTestBinding}); w.Code == 200 {
		t.Fatal("historical policy mismatch exported")
	}
}

func TestMulticaNativeSocketIsSeparateAndSurvivesStoreRecovery(t *testing.T) {
	legacyDir := t.TempDir()
	legacy, err := OpenStore(legacyDir, Limits{})
	if err != nil {
		t.Fatal(err)
	}
	legacy.Close()
	s, _ := publicStoreTest(t)
	socket := filepath.Join(legacyDir, "native.sock")
	server, listener, err := StartMulticaNative(socket, s, bridgeTestBinding, nativeRuntimePolicy)
	if err != nil {
		t.Fatal(err)
	}
	defer server.Close()
	defer listener.Close()
	go server.Serve(listener)
	info, err := os.Stat(socket)
	if err != nil || info.Mode().Perm() != 0600 {
		t.Fatal("socket permissions", info, err)
	}
	legacy, err = OpenStore(legacyDir, Limits{})
	if err != nil {
		t.Fatal("native socket broke legacy store restart", err)
	}
	defer legacy.Close()
	transport := &http.Transport{DialContext: func(ctx context.Context, _, _ string) (net.Conn, error) {
		return (&net.Dialer{}).DialContext(ctx, "unix", socket)
	}}
	defer transport.CloseIdleConnections()
	client := &http.Client{Transport: transport, Timeout: time.Second}
	resp, err := client.Post("http://localhost/admin", "application/json", strings.NewReader(`{"action":"list"}`))
	if err != nil {
		t.Fatal(err)
	}
	resp.Body.Close()
	if resp.StatusCode != 404 {
		t.Fatal("legacy administrative access exposed", resp.StatusCode)
	}
}

func TestMulticaNativeHTTPStoreLostResponseRecovery(t *testing.T) {
	c := multicaHTTPConfig(t)
	publisher, err := NewMulticaWebhook(c)
	if err != nil {
		t.Fatal(err)
	}
	s, now := publicStoreTest(t)
	sub := nativeRuntimeSubmission(t)
	finishRoot(t, s, sub)
	var first []byte
	var key string
	calls := 0
	remote := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		calls++
		raw, err := readBounded(r.Body, 4096)
		if err != nil {
			t.Error(err)
			w.WriteHeader(400)
			return
		}
		if calls == 1 {
			first = raw
			key = r.Header.Get("Idempotency-Key")
			// Native dispatch persisted, but its acknowledgement is lost.
			w.WriteHeader(503)
			return
		}
		if !bytes.Equal(first, raw) || key != r.Header.Get("Idempotency-Key") {
			t.Error("restart changed native event or request key")
		}
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(map[string]string{"status": "duplicate", "delivery_id": multicaTestDelivery, "run_id": multicaTestRun})
	}))
	defer remote.Close()
	publisher.endpoint = remote.URL
	deliverMulticaEvents(context.Background(), s, publisher, nativeRuntimePolicy)
	dir := s.dir
	s.Close()
	s, err = openPublicStore(dir, Limits{}, func() time.Time { return *now }, nil)
	if err != nil {
		t.Fatal(err)
	}
	defer s.Close()
	*now = now.Add(time.Hour)
	deliverMulticaEvents(context.Background(), s, publisher, nativeRuntimePolicy)
	deliverMulticaEvents(context.Background(), s, publisher, nativeRuntimePolicy)
	if calls != 2 {
		t.Fatal("duplicate native run was retried", calls)
	}
	r, _, err := s.read(sub.Manifest.SubmissionID)
	if err != nil || r.MulticaDelivery == nil || r.MulticaDelivery.Status != "duplicate" || r.MulticaDelivery.RunID != multicaTestRun || r.AssessmentDeliveryState != "unavailable" {
		t.Fatal("native UUIDv7 association or uncertain dispatch lost", r.MulticaDelivery, err)
	}
	if bytes.Contains(first, []byte(sub.Manifest.Description)) {
		t.Fatal("private notification included feedback content")
	}
}

// A valid ignored receipt is terminal: actual HTTP parsing must persist the
// validated delivery identity through close/reopen without redispatching the
// same input under a new key.
func TestMulticaNativeHTTPStoreIgnoredReceiptIsTerminal(t *testing.T) {
	c := multicaHTTPConfig(t)
	publisher, err := NewMulticaWebhook(c)
	if err != nil {
		t.Fatal(err)
	}
	s, now := publicStoreTest(t)
	sub := nativeRuntimeSubmission(t)
	id := sub.Manifest.SubmissionID
	finishRoot(t, s, sub)
	calls := 0
	remote := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		calls++
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(map[string]string{"status": "ignored", "delivery_id": multicaTestDelivery, "reason_code": "event_filtered"})
	}))
	defer remote.Close()
	publisher.endpoint = remote.URL
	deliverMulticaEvents(context.Background(), s, publisher, nativeRuntimePolicy)
	r, _, err := s.read(id)
	if err != nil || r.MulticaDelivery == nil || r.MulticaDelivery.Status != "ignored" ||
		r.MulticaDelivery.DeliveryID != multicaTestDelivery || r.MulticaDelivery.RunID != "" || r.MulticaDelivery.Attempts != 1 {
		t.Fatal("ignored receipt was not persisted terminally with its identity", r.MulticaDelivery, err)
	}
	key := r.MulticaDelivery.Key
	dir := s.dir
	s.Close()
	s, err = openPublicStore(dir, Limits{}, func() time.Time { return *now }, nil)
	if err != nil {
		t.Fatal(err)
	}
	defer s.Close()
	*now = now.Add(24 * time.Hour)
	deliverMulticaEvents(context.Background(), s, publisher, nativeRuntimePolicy)
	deliverMulticaEvents(context.Background(), s, publisher, nativeRuntimePolicy)
	if calls != 1 {
		t.Fatal("terminal ignored receipt was retried", calls)
	}
	r, _, err = s.read(id)
	if err != nil || r.MulticaDelivery == nil || r.MulticaDelivery.Status != "ignored" ||
		r.MulticaDelivery.DeliveryID != multicaTestDelivery || r.MulticaDelivery.Key != key {
		t.Fatal("restart lost the terminal ignored receipt", r.MulticaDelivery, err)
	}
	thread, err := s.Thread(id, testSecret, "", 5)
	if err != nil || thread.AssessmentDeliveryState != "unavailable" || thread.AssessmentDeliveryReason != "multica_dispatch_ignored" || thread.WorkState != "new" {
		t.Fatal("ignored delivery changed the public work state", thread, err)
	}
}

// A lost first response followed by a runless duplicate converges on the same
// idempotency key; the unconfirmed delivery is terminal and never redispatched.
func TestMulticaNativeHTTPStoreRunlessDuplicateConvergence(t *testing.T) {
	c := multicaHTTPConfig(t)
	publisher, err := NewMulticaWebhook(c)
	if err != nil {
		t.Fatal(err)
	}
	s, now := publicStoreTest(t)
	sub := nativeRuntimeSubmission(t)
	id := sub.Manifest.SubmissionID
	finishRoot(t, s, sub)
	calls := 0
	var keys []string
	remote := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		calls++
		keys = append(keys, r.Header.Get("Idempotency-Key"))
		if calls == 1 {
			// Native dispatch persisted, but its acknowledgement is lost.
			w.WriteHeader(503)
			return
		}
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(map[string]string{"status": "duplicate", "delivery_id": multicaTestDelivery})
	}))
	defer remote.Close()
	publisher.endpoint = remote.URL
	deliverMulticaEvents(context.Background(), s, publisher, nativeRuntimePolicy)
	dir := s.dir
	s.Close()
	s, err = openPublicStore(dir, Limits{}, func() time.Time { return *now }, nil)
	if err != nil {
		t.Fatal(err)
	}
	defer s.Close()
	*now = now.Add(time.Hour)
	deliverMulticaEvents(context.Background(), s, publisher, nativeRuntimePolicy)
	deliverMulticaEvents(context.Background(), s, publisher, nativeRuntimePolicy)
	if calls != 2 || keys[0] != keys[1] {
		t.Fatal("unconfirmed duplicate was redispatched under a new key", calls, keys)
	}
	r, _, err := s.read(id)
	if err != nil || r.MulticaDelivery == nil || r.MulticaDelivery.Status != "duplicate" ||
		r.MulticaDelivery.DeliveryID != multicaTestDelivery || r.MulticaDelivery.RunID != "" || r.MulticaDelivery.Attempts != 2 {
		t.Fatal("runless duplicate did not converge terminally", r.MulticaDelivery, err)
	}
	thread, err := s.Thread(id, testSecret, "", 5)
	if err != nil || thread.AssessmentDeliveryState != "unavailable" || thread.WorkState != "new" {
		t.Fatal("unconfirmed duplicate changed the public work state", thread, err)
	}
}
