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
	"strings"
	"sync"
	"testing"
	"time"
)

type multicaLiveAttempt struct {
	At         time.Time `json:"at"`
	Status     string    `json:"status"`
	DeliveryID string    `json:"deliveryId,omitempty"`
	RunID      string    `json:"runId,omitempty"`
	Failed     bool      `json:"failed"`
}

type multicaLiveEventEvidence struct {
	Event    MulticaEvent         `json:"event"`
	Key      string               `json:"key"`
	Attempts []multicaLiveAttempt `json:"attempts"`
}

type multicaLiveSender struct {
	webhook *MulticaWebhook
	events  []*multicaLiveEventEvidence
}

func (s *multicaLiveSender) Binding() string { return s.webhook.Binding() }
func (s *multicaLiveSender) Send(ctx context.Context, event MulticaEvent, key string) (MulticaDeliveryResult, error) {
	result, err := s.webhook.Send(ctx, event, key)
	var evidence *multicaLiveEventEvidence
	for _, existing := range s.events {
		if existing.Key == key {
			evidence = existing
			break
		}
	}
	if evidence == nil {
		evidence = &multicaLiveEventEvidence{Event: event, Key: key}
		s.events = append(s.events, evidence)
	}
	evidence.Attempts = append(evidence.Attempts, multicaLiveAttempt{At: time.Now().UTC(), Status: result.Status, DeliveryID: result.DeliveryID, RunID: result.RunID, Failed: err != nil})
	return result, err
}

// TestMulticaLiveHarness requires an owner-created native webhook configuration.
// Only the explicitly synthetic case reaches Multica. GitHub publication and
// removal are simulated locally; this fixture never creates a GitHub issue.
func TestMulticaLiveHarness(t *testing.T) {
	dir := os.Getenv("HEXPROOF_MULTICA_LIVE_DIR")
	if dir == "" {
		t.Skip("requires an explicit isolated live Multica output directory")
	}
	build, err := filepath.Abs("../../../../build")
	if err != nil || !filepath.IsAbs(dir) || !strings.HasPrefix(filepath.Clean(dir)+string(os.PathSeparator), build+string(os.PathSeparator)) {
		t.Fatal("live Multica fixture requires an absolute build subdirectory")
	}
	if err := os.MkdirAll(dir, 0700); err != nil {
		t.Fatal("live fixture directory unavailable")
	}
	realBuild, err := filepath.EvalSymlinks(build)
	realDir, dirErr := filepath.EvalSymlinks(dir)
	if err != nil || dirErr != nil || !strings.HasPrefix(realDir+string(os.PathSeparator), realBuild+string(os.PathSeparator)) {
		t.Fatal("live fixture directory resolves outside build")
	}
	if err := os.Chmod(dir, 0700); err != nil {
		t.Fatal("live fixture directory permissions unavailable")
	}
	for _, name := range []string{"ready.json", "public", "qualified.json", "stop"} {
		if _, err := os.Lstat(filepath.Join(dir, name)); !os.IsNotExist(err) {
			t.Fatal("live fixture output directory has already been used")
		}
	}
	claim, err := os.OpenFile(filepath.Join(dir, ".live-claim"), os.O_CREATE|os.O_EXCL|os.O_WRONLY, 0600)
	if err != nil {
		t.Fatal("live fixture output directory is already claimed")
	}
	claim.Close()
	raw, err := os.ReadFile(filepath.Join(dir, "multica-config.json"))
	var config MulticaConfig
	if err != nil || len(raw) > 16<<10 || decodeClosed(raw, &config) != nil || config.ProviderPolicyRevision != nativeRuntimePolicy || config.Socket != filepath.Join(dir, "native.sock") {
		t.Fatal("invalid isolated live Multica configuration")
	}
	webhook, err := NewMulticaWebhook(config)
	if err != nil {
		t.Fatal("live Multica webhook configuration unavailable")
	}
	store, err := OpenPublicStore(filepath.Join(dir, "public"), Limits{})
	if err != nil {
		t.Fatal(err)
	}
	defer store.Close()
	sub := nativeRuntimeSubmission(t)
	sub.Manifest.SubmissionID = projectionID(dir, "synthetic-multica-live-case", time.Now().UnixNano())
	sub.Manifest.CreatedAt = time.Now().UTC().Format(time.RFC3339Nano)
	sub.Manifest.Description = "SYNTHETIC INTEGRATION TEST ONLY. No real user report or product defect. This local fixture simulates a public feedback conversation: initially the fictional reproduction is missing; a synthetic follow-up will provide it. Do not modify source, create GitHub issues, or claim a real bug."
	sub.Manifest.Context = Context{}
	sub.Manifest.Attachments, sub.Blobs = []Attachment{}, []Blob{}
	sub.ManifestBytes, _ = json.Marshal(sub.Manifest)
	sub.Digest = PublicDigest(sub.ManifestBytes)
	finishRoot(t, store, sub)
	id, binding := sub.Manifest.SubmissionID, webhook.Binding()
	server, listener, err := StartMulticaNative(config.Socket, store, binding, nativeRuntimePolicy)
	if err != nil {
		t.Fatal(err)
	}
	var observations struct {
		sync.Mutex
		removedAt time.Time
	}
	nativeHandler := server.Handler
	server.Handler = http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		recorder := httptest.NewRecorder()
		nativeHandler.ServeHTTP(recorder, r)
		if recorder.Code == http.StatusOK {
			var result MulticaNativeResult
			if json.Unmarshal(recorder.Body.Bytes(), &result) == nil && result.Snapshot != nil && result.Snapshot.CaseID == id && result.Snapshot.State == "removed" {
				observations.Lock()
				if observations.removedAt.IsZero() {
					observations.removedAt = time.Now().UTC()
				}
				observations.Unlock()
			}
		}
		for key, values := range recorder.Header() {
			for _, value := range values {
				w.Header().Add(key, value)
			}
		}
		w.WriteHeader(recorder.Code)
		_, _ = w.Write(recorder.Body.Bytes())
	})
	serverDone := make(chan error, 1)
	go func() { serverDone <- server.Serve(listener) }()
	defer func() {
		ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
		defer cancel()
		_ = server.Shutdown(ctx)
		listener.Close()
	}()
	write := func(name string, value any) {
		t.Helper()
		if err := atomicJSON(dir, name, value); err != nil {
			t.Fatal("live fixture evidence write failed")
		}
	}
	read := func() PublicRecord {
		t.Helper()
		store.mu.Lock()
		defer store.mu.Unlock()
		r, _, err := store.read(id)
		if err != nil {
			t.Fatal("live fixture record unavailable")
		}
		return r
	}
	// This is the same local mapped/verified transition as finishChild. It also
	// settles synthetic deletion jobs without making external GitHub requests.
	settlePublic := func() {
		t.Helper()
		for i := 0; i < 128; i++ {
			job, err := store.Claim()
			if err != nil {
				t.Fatal(err)
			}
			if job == nil {
				return
			}
			result := PublicResult{}
			switch job.Action {
			case "comment-create":
				result = PublicResult{Outcome: "mapped", CommentID: 100 + int64(job.Generation), CommentNodeID: "SYNTHETIC_COMMENT"}
			case "comment-verify":
				result.Outcome = "verified"
			case "comment-remove", "remove":
				result.Outcome = "removed"
			default:
				t.Fatal("unexpected synthetic publication action", job.Action)
			}
			if err := store.Finish(*job, result); err != nil {
				t.Fatal(err)
			}
		}
		t.Fatal("synthetic publication did not settle")
	}
	sender := &multicaLiveSender{webhook: webhook}
	started := time.Now().UTC()
	phase := "awaiting-question"
	replied, ready, removedObservedWritten, qualified := false, false, false, false
	threads := map[string]PublicThread{}
	persist := func(outcome string) {
		r := read()
		observations.Lock()
		removedAt := observations.removedAt
		observations.Unlock()
		write("evidence.json", map[string]any{
			"synthetic": true, "githubMode": "local-simulation", "nativeMode": "run_only", "startedAt": started, "updatedAt": time.Now().UTC(),
			"caseId": id, "binding": binding, "phase": phase, "outcome": outcome, "passed": qualified,
			"events": sender.events, "questionAnswered": replied, "readinessObserved": ready, "removedSnapshotObservedAt": removedAt,
			"inputRevision": r.InputRevision, "removalState": r.Receipt.RemovalState, "revocationRevision": r.RevocationRevision,
			"externalRemovalSimulated": r.ExternalRemoved, "revocationAcknowledged": r.RevocationAcknowledged, "purgeComplete": false,
		})
	}
	defer func() {
		if t.Failed() {
			persist("partial-failure")
		}
	}()
	write("ready.json", map[string]string{"caseId": id, "binding": binding, "socket": config.Socket})
	ctx, cancel := context.WithTimeout(context.Background(), 12*time.Minute)
	defer cancel()
	ticker := time.NewTicker(time.Second)
	defer ticker.Stop()
	for {
		if _, err := os.Stat(filepath.Join(dir, "stop")); err == nil {
			persist("owner-stopped")
			if !qualified {
				t.Fatal("live fixture stopped before all three phases were observed")
			}
			return
		} else if !os.IsNotExist(err) {
			t.Fatal("live fixture stop marker unavailable")
		}
		settlePublic()
		r := read()
		thread, err := store.Thread(id, testSecret, "", 5)
		if err != nil {
			t.Fatal(err)
		}
		threads[phase] = thread
		write("thread-phase.json", threads)
		if !replied && r.InputRevision == 1 && thread.WorkState == "needs-information" && thread.Question != nil {
			write("thread-needs-information.json", thread)
			reply := replyFixture(t, sub, replyTestID)
			reply.Manifest.CreatedAt = time.Now().UTC().Format(time.RFC3339Nano)
			reply.Manifest.Description = "SYNTHETIC FOLLOW-UP ONLY. Fictional reproduction: open the imaginary test panel, select the blue test square, and press the synthetic confirm button. Expected: the square stays blue. Observed in this invented scenario: it turns green. This is fabricated integration-test data, not a real product defect; no source change is requested."
			reply.Manifest.QuestionID, reply.Manifest.QuestionRevision = thread.Question.ID, thread.Question.Revision
			reply.ManifestBytes, _ = json.Marshal(reply.Manifest)
			reply.Digest = PublicReplyDigest(reply.ManifestBytes)
			if _, _, err := store.AcceptReply(id, testSecret, reply); err != nil {
				t.Fatal(err)
			}
			replied, phase = true, "awaiting-readiness"
			settlePublic()
		}
		if replied && !ready && r.InputRevision == 2 && thread.WorkState == "ready" {
			write("thread-ready.json", thread)
			ready, phase = true, "awaiting-removed-snapshot"
			if _, err := store.Remove(id, testSecret); err != nil {
				t.Fatal(err)
			}
			settlePublic()
		}
		deliverMulticaEvents(ctx, store, sender, nativeRuntimePolicy)
		observations.Lock()
		removedAt := observations.removedAt
		observations.Unlock()
		if !removedAt.IsZero() && !removedObservedWritten {
			write("removed-observed.json", map[string]any{"caseId": id, "binding": binding, "observedAt": removedAt, "purgeComplete": false})
			removedObservedWritten = true
		}
		if replied && ready && !removedAt.IsZero() && !qualified {
			r = read()
			if r.RevocationAcknowledged || r.Receipt.RemovalState == "removed" {
				t.Fatal("live fixture incorrectly acknowledged native purge")
			}
			qualified, phase = true, "qualified-awaiting-owner-stop"
			write("qualified.json", map[string]any{"caseId": id, "binding": binding, "passed": true, "purgeComplete": false, "listenerRetained": true})
		}
		persist("running")
		select {
		case <-ctx.Done():
			persist("watchdog-expired")
			t.Fatal("live fixture watchdog expired before owner stop")
		case err := <-serverDone:
			if !errors.Is(err, http.ErrServerClosed) {
				t.Fatal("live native server stopped unexpectedly")
			}
			t.Fatal("live native server closed before owner stop")
		case <-ticker.C:
		}
	}
}
