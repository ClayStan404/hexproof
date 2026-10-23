// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package feedback

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"time"
)

// MulticaConfig selects an existing native webhook. It creates no platform
// resources and never enables a scheduler or an AI runtime.
type MulticaConfig struct {
	WebhookFile            string `json:"webhookFile"`
	WorkspaceID            string `json:"workspaceId"`
	AutopilotID            string `json:"autopilotId"`
	ProviderPolicyRevision string `json:"providerPolicyRevision"`
	Socket                 string `json:"socket"`
}

var multicaUUIDPattern = regexp.MustCompile(`^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$`)
var multicaWebhookTokenPattern = regexp.MustCompile(`^[A-Za-z0-9_-]{16,256}$`)

func multicaUUID(value string) bool {
	return multicaUUIDPattern.MatchString(value) && value != "00000000-0000-0000-0000-000000000000"
}

func (c MulticaConfig) Validate() error {
	if !filepath.IsAbs(c.WebhookFile) || !filepath.IsAbs(c.Socket) || len(c.Socket) > 100 || strings.ContainsRune(c.WebhookFile+c.Socket, '\x00') || !multicaUUID(c.WorkspaceID) || !multicaUUID(c.AutopilotID) || !publicRevisionPattern.MatchString(c.ProviderPolicyRevision) || c.ProviderPolicyRevision == "none-v1" {
		return fmt.Errorf("invalid Multica configuration")
	}
	return nil
}

// MulticaWebhook sends only bounded case/revision metadata. Its URL is a
// credential: errors deliberately omit request URLs, response bodies and the
// underlying HTTP error (which may contain the complete URL).
type MulticaWebhook struct {
	config   MulticaConfig
	endpoint string
	binding  string
	http     *http.Client
}

func NewMulticaWebhook(c MulticaConfig) (*MulticaWebhook, error) {
	if err := c.Validate(); err != nil {
		return nil, err
	}
	info, err := os.Lstat(c.WebhookFile)
	if err != nil || !info.Mode().IsRegular() || info.Mode().Perm()&0077 != 0 || info.Size() < 1 || info.Size() > 4096 {
		return nil, fmt.Errorf("Multica webhook credential unavailable")
	}
	f, err := os.Open(c.WebhookFile)
	if err != nil {
		return nil, fmt.Errorf("Multica webhook credential unavailable")
	}
	defer f.Close()
	opened, err := f.Stat()
	if err != nil || !os.SameFile(info, opened) || !opened.Mode().IsRegular() || opened.Mode().Perm()&0077 != 0 {
		return nil, fmt.Errorf("Multica webhook credential unavailable")
	}
	raw, err := readBounded(f, 4096)
	if err != nil {
		return nil, fmt.Errorf("Multica webhook credential unavailable")
	}
	endpoint := strings.TrimSpace(string(raw))
	u, err := url.Parse(endpoint)
	const prefix = "/api/webhooks/autopilots/"
	if err != nil || u.Scheme != "https" || u.Hostname() == "" || u.User != nil || u.Opaque != "" || u.RawQuery != "" || u.ForceQuery || u.Fragment != "" || u.RawFragment != "" || strings.Contains(endpoint, "#") || u.RawPath != "" || strings.HasSuffix(u.Host, ":") || !strings.HasPrefix(u.Path, prefix) || !multicaWebhookTokenPattern.MatchString(strings.TrimPrefix(u.Path, prefix)) {
		return nil, fmt.Errorf("invalid Multica webhook credential")
	}
	if u.Port() != "" {
		port, err := strconv.Atoi(u.Port())
		if err != nil || port < 1 || port > 65535 {
			return nil, fmt.Errorf("invalid Multica webhook credential")
		}
	}
	u.Host = strings.ToLower(u.Host)
	endpoint = u.String()
	// JSON field order and encoding are fixed. Policy is deliberately excluded:
	// a newly consented provider policy must not retarget an existing case.
	target, _ := json.Marshal(struct {
		SchemaVersion int    `json:"schemaVersion"`
		WebhookURL    string `json:"webhookUrl"`
		WorkspaceID   string `json:"workspaceId"`
		AutopilotID   string `json:"autopilotId"`
	}{1, endpoint, c.WorkspaceID, c.AutopilotID})
	return &MulticaWebhook{
		config: c, endpoint: endpoint, binding: hashBytes(target),
		http: &http.Client{Timeout: 10 * time.Second, CheckRedirect: func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse }},
	}, nil
}

func (p *MulticaWebhook) Binding() string { return p.binding }

type multicaWebhookResponse struct {
	Status      string `json:"status"`
	DeliveryID  string `json:"delivery_id"`
	RunID       string `json:"run_id,omitempty"`
	AutopilotID string `json:"autopilot_id,omitempty"`
	TriggerID   string `json:"trigger_id,omitempty"`
	Reason      string `json:"reason,omitempty"`
	ReasonCode  string `json:"reason_code,omitempty"`
}

func (p *MulticaWebhook) Send(ctx context.Context, event MulticaEvent, key string) (MulticaDeliveryResult, error) {
	result := MulticaDeliveryResult{Status: "pending"}
	if !validMulticaEvent(event) || event.Binding != p.binding || key != MulticaEventKey(event) {
		return result, fmt.Errorf("invalid Multica event or target binding")
	}
	raw, err := json.Marshal(event)
	if err != nil || len(raw) > 16<<10 {
		return result, fmt.Errorf("invalid Multica event")
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, p.endpoint, bytes.NewReader(raw))
	if err != nil {
		return result, fmt.Errorf("Multica request unavailable")
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Accept", "application/json")
	req.Header.Set("Idempotency-Key", key)
	response, err := p.http.Do(req)
	if err != nil {
		return result, fmt.Errorf("Multica request unavailable")
	}
	defer response.Body.Close()
	raw, err = readBounded(response.Body, 16<<10)
	if response.StatusCode == http.StatusTooManyRequests || response.StatusCode == http.StatusServiceUnavailable {
		result.RetryAfter = multicaRetryAfter(response.Header.Get("Retry-After"), time.Now())
	}
	if err != nil {
		return result, fmt.Errorf("invalid Multica response")
	}
	if response.StatusCode != http.StatusOK {
		return result, fmt.Errorf("Multica webhook HTTP status %d", response.StatusCode)
	}
	var receipt multicaWebhookResponse
	if decodeClosed(raw, &receipt) != nil || !multicaUUID(receipt.DeliveryID) || receipt.RunID != "" && !multicaUUID(receipt.RunID) || receipt.AutopilotID != "" && receipt.AutopilotID != p.config.AutopilotID || receipt.TriggerID != "" && !multicaUUID(receipt.TriggerID) {
		return result, fmt.Errorf("invalid Multica response")
	}
	result.DeliveryID, result.RunID = receipt.DeliveryID, receipt.RunID
	switch receipt.Status {
	case "accepted":
		if receipt.RunID == "" || receipt.AutopilotID != p.config.AutopilotID || receipt.TriggerID == "" || receipt.Reason != "" || receipt.ReasonCode != "" {
			return result, fmt.Errorf("invalid Multica acceptance receipt")
		}
		result.Status = "accepted"
		return result, nil
	case "duplicate":
		if receipt.Reason != "" || receipt.ReasonCode != "" {
			return result, fmt.Errorf("invalid Multica duplicate receipt")
		}
		// Terminal but unconfirmed: the original response may have been lost
		// before this runless duplicate, so never promote it to accepted.
		result.Status = "duplicate"
		return result, nil
	case "skipped":
		if receipt.RunID == "" {
			return result, fmt.Errorf("invalid Multica skipped receipt")
		}
		result.Status = "skipped"
		return result, nil
	case "ignored":
		if receipt.RunID != "" || receipt.Reason == "" && receipt.ReasonCode == "" {
			return result, fmt.Errorf("invalid Multica ignored receipt")
		}
		// A valid ignored decision is terminal: the native configuration
		// rejected this event, so bounded retries cannot recover it. Preserve
		// the validated delivery identity for reconciliation without storing
		// the native reason prose.
		result.Status = "ignored"
		return result, nil
	default:
		return result, fmt.Errorf("invalid Multica response status")
	}
}

func multicaRetryAfter(value string, now time.Time) time.Duration {
	delay := time.Minute
	if seconds, err := strconv.Atoi(value); err == nil && seconds > 0 {
		delay = time.Duration(min(seconds, 21600)) * time.Second
	} else if at, err := http.ParseTime(value); err == nil {
		delay = at.Sub(now)
	}
	return min(max(delay, time.Second), 6*time.Hour)
}
