// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package server

import (
	"context"
	"encoding/json"
	"errors"
	"net/http/httptest"
	"reflect"
	"strings"
	"testing"
	"time"

	"hexproof/server/internal/accounts"
	"hexproof/server/internal/rulesengine/forge"
)

func TestHealthCapabilitiesSeparateHostingFromLocalForge(t *testing.T) {
	for _, test := range []struct {
		name            string
		local, hosting  bool
		closed, cooling bool
	}{
		{name: "manual"},
		{name: "relay without Java", hosting: true},
		{name: "local only", local: true},
		{name: "both", local: true, hosting: true},
		{name: "local retry cooldown", local: true, hosting: true, cooling: true},
		{name: "closed local engine", local: true, closed: true},
	} {
		t.Run(test.name, func(t *testing.T) {
			h := &Handler{config: Config{AllowPlayerHosting: test.hosting}, forgeClosed: test.closed}
			if test.local {
				h.forgeRuntime = &forge.ProcessConfig{}
			}
			if test.cooling {
				h.forgeRetryAfter = time.Now().Add(time.Minute)
			}
			response := httptest.NewRecorder()
			h.ServeHealth(response, httptest.NewRequest("GET", "/healthz", nil))
			if response.Code != 200 || response.Body.String() != "ok\n" || response.Header().Get("Cache-Control") != "no-store" {
				t.Fatalf("incompatible health response: %v %q", response.Code, response.Body.String())
			}
			var capabilities map[string]bool
			if err := json.Unmarshal([]byte(response.Header().Get("X-Hexproof-Capabilities")), &capabilities); err != nil {
				t.Fatal(err)
			}
			want := map[string]bool{"forge": test.local && !test.closed && !test.cooling,
				"playerHosting": test.hosting, "directPeer": test.hosting, "hostMigration": test.hosting}
			if !reflect.DeepEqual(capabilities, want) {
				t.Fatalf("public capabilities = %v; want %v", capabilities, want)
			}
		})
	}
}

type readinessAuthority struct {
	err   error
	calls int
}

func (a *readinessAuthority) Do(_ context.Context, q accounts.Request) (accounts.Result, error) {
	a.calls++
	if q.Operation != "check" || q.SessionToken != "" {
		panic("readiness must not use player credentials")
	}
	return accounts.Result{}, a.err
}

func TestReadinessSeparatesDependenciesAndBoundsProbeWork(t *testing.T) {
	h := NewHandler()
	defer h.Close()
	authority := &readinessAuthority{err: accounts.ErrInvalid}
	h.accounts = authority
	for range 2 {
		w := httptest.NewRecorder()
		h.ServeReadiness(w, httptest.NewRequest("GET", "/readyz", nil))
		if w.Code != 200 || !strings.Contains(w.Body.String(), `"ready":true`) {
			t.Fatal(w.Code, w.Body.String())
		}
	}
	if authority.calls != 1 {
		t.Fatal("readiness probes were not coalesced", authority.calls)
	}
	authority.err = errors.New("upstream failed: SECRET_TOKEN")
	h.control.lastProbe = time.Time{}
	w := httptest.NewRecorder()
	h.ServeReadiness(w, httptest.NewRequest("GET", "/readyz", nil))
	if w.Code != 503 || !strings.Contains(w.Body.String(), `"error":"unavailable"`) || strings.Contains(w.Body.String(), "SECRET_TOKEN") {
		t.Fatal(w.Code, w.Body.String())
	}
	live := httptest.NewRecorder()
	h.ServeHealth(live, httptest.NewRequest("GET", "/healthz", nil))
	if live.Code != 200 || live.Body.String() != "ok\n" {
		t.Fatal("dependency failure changed liveness")
	}
}

func TestControlMetricsRecordCancellationWithoutPrivateLabels(t *testing.T) {
	var timing operationTiming
	finish := timing.start()
	if timing.snapshot().InFlight != 1 {
		t.Fatal("missing active operation")
	}
	finish(context.Canceled)
	snapshot := timing.snapshot()
	if snapshot.Calls != 1 || snapshot.Cancelled != 1 || snapshot.Failed != 1 || snapshot.InFlight != 0 || snapshot.LastError != "cancelled" {
		t.Fatal(snapshot)
	}
	var total uint64
	for _, count := range snapshot.Buckets {
		total += count
	}
	if total != 1 {
		t.Fatal("latency sample not recorded")
	}
}

func TestModelSendQueueFailuresReachReadinessMetrics(t *testing.T) {
	h := &Handler{}
	sess := &Session{Send: make(chan []byte, 1)}
	h.sendModel(sess, "session.pong", map[string]int{"serverUnixMillis": 1})
	if h.control.sendFailures.Load() != 0 {
		t.Fatal("successful enqueue counted as a failure")
	}
	h.sendModel(sess, "session.pong", map[string]int{"serverUnixMillis": 2})
	if h.control.sendFailures.Load() != 1 || !sess.closed {
		t.Fatal("full model queue did not fail closed and increment diagnostics")
	}
}
