// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package feedback

import (
	"context"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

const multicaTestWorkspace = "57cc0f8d-6a38-4981-b5c5-f923b384170a"
const multicaTestAutopilot = "01900000-0001-7000-8000-000000000001"
const multicaTestTrigger = "01900000-0001-7000-8000-000000000002"
const multicaTestDelivery = "01900000-0001-7000-8000-000000000003"
const multicaTestRun = "01900000-0001-7000-8000-000000000004"
const multicaTestToken = "fixture_only_webhook_credential_1234567890"

func multicaHTTPConfig(t *testing.T) MulticaConfig {
	t.Helper()
	c := MulticaConfig{WebhookFile: filepath.Join(t.TempDir(), "webhook"), WorkspaceID: multicaTestWorkspace, AutopilotID: multicaTestAutopilot, ProviderPolicyRevision: "multica-test-v1", Socket: "/tmp/hexproof-multica-test.sock"}
	if err := os.WriteFile(c.WebhookFile, []byte("https://api.multica.ai/api/webhooks/autopilots/"+multicaTestToken+"\n"), 0600); err != nil {
		t.Fatal(err)
	}
	return c
}

func multicaHTTPEvent(p *MulticaWebhook) MulticaEvent {
	return MulticaEvent{SchemaVersion: 1, Event: "hexproof.feedback.changed", CaseID: testID, Binding: p.Binding(), InputRevision: 1}
}

func TestMulticaConfigurationAndPrivateCredential(t *testing.T) {
	c := multicaHTTPConfig(t)
	for name, mutate := range map[string]func(*MulticaConfig){
		"relative credential": func(c *MulticaConfig) { c.WebhookFile = "webhook" },
		"relative socket":     func(c *MulticaConfig) { c.Socket = "native.sock" },
		"long socket":         func(c *MulticaConfig) { c.Socket = "/" + strings.Repeat("x", 100) },
		"nil workspace":       func(c *MulticaConfig) { c.WorkspaceID = "00000000-0000-0000-0000-000000000000" },
		"bad autopilot":       func(c *MulticaConfig) { c.AutopilotID = "not-a-uuid" },
		"no provider consent": func(c *MulticaConfig) { c.ProviderPolicyRevision = "none-v1" },
		"empty policy":        func(c *MulticaConfig) { c.ProviderPolicyRevision = "" },
	} {
		t.Run(name, func(t *testing.T) {
			bad := c
			mutate(&bad)
			if _, err := NewMulticaWebhook(bad); err == nil {
				t.Fatal("invalid configuration accepted")
			}
		})
	}
	for name, value := range map[string]string{
		"http":           "http://api.multica.ai/api/webhooks/autopilots/" + multicaTestToken,
		"userinfo":       "https://user:pass@api.multica.ai/api/webhooks/autopilots/" + multicaTestToken,
		"query":          "https://api.multica.ai/api/webhooks/autopilots/" + multicaTestToken + "?secret=1",
		"empty query":    "https://api.multica.ai/api/webhooks/autopilots/" + multicaTestToken + "?",
		"fragment":       "https://api.multica.ai/api/webhooks/autopilots/" + multicaTestToken + "#part",
		"empty fragment": "https://api.multica.ai/api/webhooks/autopilots/" + multicaTestToken + "#",
		"other route":    "https://api.multica.ai/api/issues/" + multicaTestToken,
		"encoded route":  "https://api.multica.ai/api/%77ebhooks/autopilots/" + multicaTestToken,
		"extra segment":  "https://api.multica.ai/api/webhooks/autopilots/" + multicaTestToken + "/extra",
		"empty token":    "https://api.multica.ai/api/webhooks/autopilots/",
		"invalid port":   "https://api.multica.ai:99999/api/webhooks/autopilots/" + multicaTestToken,
		"oversized":      strings.Repeat("x", 4097),
	} {
		t.Run(name, func(t *testing.T) {
			if err := os.WriteFile(c.WebhookFile, []byte(value), 0600); err != nil {
				t.Fatal(err)
			}
			if _, err := NewMulticaWebhook(c); err == nil || strings.Contains(err.Error(), multicaTestToken) {
				t.Fatal("invalid or exposed webhook credential")
			}
		})
	}
	c = multicaHTTPConfig(t)
	if err := os.Chmod(c.WebhookFile, 0644); err != nil {
		t.Fatal(err)
	}
	if _, err := NewMulticaWebhook(c); err == nil {
		t.Fatal("publicly readable credential accepted")
	}
	if err := os.Chmod(c.WebhookFile, 0600); err != nil {
		t.Fatal(err)
	}
	link := c.WebhookFile + "-link"
	if err := os.Symlink(c.WebhookFile, link); err != nil {
		t.Fatal(err)
	}
	c.WebhookFile = link
	if _, err := NewMulticaWebhook(c); err == nil {
		t.Fatal("symlink credential accepted")
	}
}

func TestMulticaBindingTracksTargetNotPolicy(t *testing.T) {
	c := multicaHTTPConfig(t)
	p, err := NewMulticaWebhook(c)
	if err != nil {
		t.Fatal(err)
	}
	if !validHash(p.Binding()) || p.http.Timeout != 10*time.Second {
		t.Fatal("missing bounded client or target binding")
	}
	c.ProviderPolicyRevision = "multica-test-v2"
	c.Socket = "/tmp/another-multica.sock"
	q, err := NewMulticaWebhook(c)
	if err != nil || q.Binding() != p.Binding() {
		t.Fatal("policy or local socket retargeted existing cases")
	}
	for _, mutate := range []func(*MulticaConfig){
		func(c *MulticaConfig) { c.WorkspaceID = multicaTestRun },
		func(c *MulticaConfig) { c.AutopilotID = multicaTestRun },
		func(c *MulticaConfig) {
			if err := os.WriteFile(c.WebhookFile, []byte("https://api.multica.ai/api/webhooks/autopilots/"+multicaTestToken+"rotated"), 0600); err != nil {
				t.Fatal(err)
			}
		},
	} {
		changed := c
		mutate(&changed)
		q, err := NewMulticaWebhook(changed)
		if err != nil || q.Binding() == p.Binding() {
			t.Fatal("changed native target retained old binding")
		}
	}
}

func TestMulticaWebhookReceiptStates(t *testing.T) {
	for _, tc := range []struct {
		name, body, status string
		wantError          bool
	}{
		{"accepted", `{"status":"accepted","delivery_id":"` + multicaTestDelivery + `","run_id":"` + multicaTestRun + `","autopilot_id":"` + multicaTestAutopilot + `","trigger_id":"` + multicaTestTrigger + `"}`, "accepted", false},
		{"duplicate", `{"status":"duplicate","delivery_id":"` + multicaTestDelivery + `","run_id":"` + multicaTestRun + `"}`, "duplicate", false},
		{"duplicate before admission", `{"status":"duplicate","delivery_id":"` + multicaTestDelivery + `"}`, "duplicate", false},
		{"duplicate with reason", `{"status":"duplicate","delivery_id":"` + multicaTestDelivery + `","run_id":"` + multicaTestRun + `","reason":"replayed"}`, "pending", true},
		{"duplicate with reason code", `{"status":"duplicate","delivery_id":"` + multicaTestDelivery + `","reason_code":"replayed"}`, "pending", true},
		{"skipped", `{"status":"skipped","delivery_id":"` + multicaTestDelivery + `","run_id":"` + multicaTestRun + `","reason":"runtime offline"}`, "skipped", false},
		{"ignored", `{"status":"ignored","delivery_id":"` + multicaTestDelivery + `","reason":"autopilot_paused"}`, "ignored", false},
		{"quota ignored", `{"status":"ignored","delivery_id":"` + multicaTestDelivery + `","reason_code":"quota_exceeded"}`, "ignored", false},
		{"ignored without reason", `{"status":"ignored","delivery_id":"` + multicaTestDelivery + `"}`, "pending", true},
		{"ignored with run", `{"status":"ignored","delivery_id":"` + multicaTestDelivery + `","reason_code":"event_filtered","run_id":"` + multicaTestRun + `"}`, "pending", true},
		{"missing identities", `{"status":"accepted","delivery_id":"` + multicaTestDelivery + `","run_id":"` + multicaTestRun + `"}`, "pending", true},
		{"wrong autopilot", `{"status":"accepted","delivery_id":"` + multicaTestDelivery + `","run_id":"` + multicaTestRun + `","autopilot_id":"` + multicaTestRun + `","trigger_id":"` + multicaTestTrigger + `"}`, "pending", true},
		{"bad UUID", `{"status":"duplicate","delivery_id":"fake","run_id":"` + multicaTestRun + `"}`, "pending", true},
		{"duplicate JSON key", `{"status":"skipped","status":"accepted","delivery_id":"` + multicaTestDelivery + `"}`, "pending", true},
		{"unknown field", `{"status":"duplicate","delivery_id":"` + multicaTestDelivery + `","run_id":"` + multicaTestRun + `","untrusted":true}`, "pending", true},
		{"trailing data", `{"status":"ignored","delivery_id":"` + multicaTestDelivery + `","reason":"paused"} {}`, "pending", true},
		{"oversized response", strings.Repeat("x", (16<<10)+1), "pending", true},
	} {
		t.Run(tc.name, func(t *testing.T) {
			p, err := NewMulticaWebhook(multicaHTTPConfig(t))
			if err != nil {
				t.Fatal(err)
			}
			event := multicaHTTPEvent(p)
			key := MulticaEventKey(event)
			server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				if r.Method != "POST" || r.Header.Get("Idempotency-Key") != key || r.Header.Get("Authorization") != "" {
					t.Error("unexpected request metadata")
				}
				raw, _ := io.ReadAll(r.Body)
				var got MulticaEvent
				if decodeClosed(raw, &got) != nil || got != event {
					t.Error("event metadata changed or extra content sent")
				}
				w.Header().Set("Content-Type", "application/json")
				_, _ = io.WriteString(w, tc.body)
			}))
			defer server.Close()
			p.endpoint = server.URL // Private test-only injection; not a config option.
			result, err := p.Send(context.Background(), event, key)
			if result.Status != tc.status || (err != nil) != tc.wantError {
				t.Fatalf("status=%q error=%v", result.Status, err)
			}
		})
	}
}

func TestMulticaWebhookRejectsWrongEventBeforeSending(t *testing.T) {
	p, err := NewMulticaWebhook(multicaHTTPConfig(t))
	if err != nil {
		t.Fatal(err)
	}
	calls := 0
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { calls++ }))
	defer server.Close()
	p.endpoint = server.URL
	valid := multicaHTTPEvent(p)
	for _, mutate := range []func(*MulticaEvent){
		func(e *MulticaEvent) { e.Binding = strings.Repeat("0", 64) },
		func(e *MulticaEvent) { e.InputRevision = 0 },
		func(e *MulticaEvent) { e.Event = "arbitrary.prompt" },
		func(e *MulticaEvent) { e.RevocationRevision = 1 },
		func(e *MulticaEvent) { e.Event = "hexproof.feedback.removed" },
	} {
		event := valid
		mutate(&event)
		if _, err := p.Send(context.Background(), event, MulticaEventKey(event)); err == nil {
			t.Fatal("invalid event sent")
		}
	}
	if _, err := p.Send(context.Background(), valid, strings.Repeat("a", 64)); err == nil {
		t.Fatal("incorrect idempotency key accepted")
	}
	if calls != 0 {
		t.Fatal("invalid events reached transport")
	}
}

func TestMulticaWebhookRetryAndRedirectBoundaries(t *testing.T) {
	p, err := NewMulticaWebhook(multicaHTTPConfig(t))
	if err != nil {
		t.Fatal(err)
	}
	event := multicaHTTPEvent(p)
	redirectCalls := 0
	target := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { redirectCalls++ }))
	defer target.Close()
	status := http.StatusTooManyRequests
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Retry-After", "999999")
		w.Header().Set("Location", target.URL)
		w.WriteHeader(status)
		_, _ = io.WriteString(w, multicaTestToken)
	}))
	defer server.Close()
	p.endpoint = server.URL
	result, err := p.Send(context.Background(), event, MulticaEventKey(event))
	if err == nil || strings.Contains(err.Error(), multicaTestToken) || result.RetryAfter != 6*time.Hour || result.Status != "pending" {
		t.Fatal("rate limit or secret-error boundary failed")
	}
	status = http.StatusTemporaryRedirect
	if _, err := p.Send(context.Background(), event, MulticaEventKey(event)); err == nil || redirectCalls != 0 {
		t.Fatal("webhook redirect was followed")
	}
	p.http.Transport = multicaFailureTransport{}
	if _, err := p.Send(context.Background(), event, MulticaEventKey(event)); err == nil || strings.Contains(err.Error(), multicaTestToken) || strings.Contains(err.Error(), server.URL) {
		t.Fatal("transport error exposed credentials")
	}
	now := time.Now().UTC().Truncate(time.Second)
	if got := multicaRetryAfter(now.Add(2*time.Minute).Format(http.TimeFormat), now); got != 2*time.Minute {
		t.Fatal("HTTP-date retry delay ignored")
	}
	if got := multicaRetryAfter(now.Add(-time.Minute).Format(http.TimeFormat), now); got != time.Second {
		t.Fatal("past retry time was not bounded")
	}
}

type multicaFailureTransport struct{}

func (multicaFailureTransport) RoundTrip(r *http.Request) (*http.Response, error) {
	return nil, fmt.Errorf("transport detail: %s %s", r.URL, multicaTestToken)
}

func TestMulticaWebhookUsesSameKeyAfterLostResponse(t *testing.T) {
	for _, tc := range []struct {
		name, second, wantRun string
	}{
		{"known run", `{"status":"duplicate","delivery_id":"` + multicaTestDelivery + `","run_id":"` + multicaTestRun + `"}`, multicaTestRun},
		{"unconfirmed run", `{"status":"duplicate","delivery_id":"` + multicaTestDelivery + `"}`, ""},
	} {
		t.Run(tc.name, func(t *testing.T) {
			p, err := NewMulticaWebhook(multicaHTTPConfig(t))
			if err != nil {
				t.Fatal(err)
			}
			event := multicaHTTPEvent(p)
			key := MulticaEventKey(event)
			keys := []string{}
			server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				keys = append(keys, r.Header.Get("Idempotency-Key"))
				if len(keys) == 1 {
					conn, _, err := w.(http.Hijacker).Hijack()
					if err != nil {
						t.Error(err)
						return
					}
					_ = conn.Close()
					return
				}
				w.Header().Set("Content-Type", "application/json")
				_, _ = io.WriteString(w, tc.second)
			}))
			defer server.Close()
			p.endpoint = server.URL
			if _, err := p.Send(context.Background(), event, key); err == nil {
				t.Fatal("lost response reported acceptance")
			}
			result, err := p.Send(context.Background(), event, key)
			if err != nil || result.Status != "duplicate" || result.DeliveryID != multicaTestDelivery || result.RunID != tc.wantRun || len(keys) != 2 || keys[0] != key || keys[1] != key {
				t.Fatal("retry lost identity or fabricated successful dispatch", result, err)
			}
		})
	}
}

// A valid ignored decision and a runless duplicate are terminal: the receiver
// keeps the validated delivery identity for native reconciliation instead of
// degrading the receipt to an anonymous transport retry.
func TestMulticaWebhookTerminalReceiptsPreserveDeliveryIdentity(t *testing.T) {
	for _, tc := range []struct {
		name, body, status string
	}{
		{"ignored reason", `{"status":"ignored","delivery_id":"` + multicaTestDelivery + `","reason":"autopilot_paused"}`, "ignored"},
		{"ignored reason code", `{"status":"ignored","delivery_id":"` + multicaTestDelivery + `","reason_code":"event_filtered"}`, "ignored"},
		{"runless duplicate", `{"status":"duplicate","delivery_id":"` + multicaTestDelivery + `"}`, "duplicate"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			p, err := NewMulticaWebhook(multicaHTTPConfig(t))
			if err != nil {
				t.Fatal(err)
			}
			event := multicaHTTPEvent(p)
			key := MulticaEventKey(event)
			server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				w.Header().Set("Content-Type", "application/json")
				_, _ = io.WriteString(w, tc.body)
			}))
			defer server.Close()
			p.endpoint = server.URL
			result, err := p.Send(context.Background(), event, key)
			if err != nil || result.Status != tc.status || result.DeliveryID != multicaTestDelivery || result.RunID != "" {
				t.Fatalf("status=%q delivery=%q run=%q error=%v", result.Status, result.DeliveryID, result.RunID, err)
			}
		})
	}
}
