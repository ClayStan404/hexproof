// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package feedback

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net"
	"net/http"
	"os"
	"strings"
	"time"
)

type multicaSender interface {
	Binding() string
	Send(context.Context, MulticaEvent, string) (MulticaDeliveryResult, error)
}

// RunMulticaOutbox transports metadata notifications. Multica owns scheduling,
// task creation, delegation and execution; this worker never runs a model.
func RunMulticaOutbox(ctx context.Context, store *PublicStore, sender multicaSender, policy string) {
	ticker := time.NewTicker(15 * time.Second)
	defer ticker.Stop()
	for {
		deliverMulticaEvents(ctx, store, sender, policy)
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
		}
	}
}

func deliverMulticaEvents(ctx context.Context, store *PublicStore, sender multicaSender, policy string) {
	binding := sender.Binding()
	ids, err := store.ListMulticaCandidates(binding, policy, 0)
	if err != nil {
		return
	}
	sent := 0
	for _, id := range ids {
		if ctx.Err() != nil || sent >= 16 {
			return
		}
		delivery, err := store.PrepareMulticaDelivery(id, binding, policy)
		if err != nil {
			reason := "multica_input_unavailable"
			if errors.Is(err, ErrConflict) {
				reason = "assessment_target_changed"
			}
			_ = store.MarkAssessmentDelivery(id, binding, false, reason)
			continue
		}
		if delivery == nil {
			continue
		}
		sent++
		result, sendErr := sender.Send(ctx, delivery.Event, delivery.Key)
		if sendErr != nil {
			result = MulticaDeliveryResult{Status: "pending", RetryAfter: result.RetryAfter}
		}
		if err = store.RecordMulticaDelivery(id, binding, delivery.Key, result); err != nil {
			// A concurrent removal may have replaced the input notification.
			// Never let its late response overwrite the revocation event.
			continue
		}
		available := sendErr == nil && result.Status == "accepted"
		reason := "multica_delivery_unavailable"
		if result.Status == "skipped" {
			reason = "multica_dispatch_skipped"
		} else if result.Status == "duplicate" {
			reason = "multica_dispatch_unconfirmed"
		} else if result.Status == "ignored" {
			reason = "multica_dispatch_ignored"
		}
		_ = store.MarkAssessmentDelivery(id, binding, available, reason)
	}
}

// MulticaNativeRequest is only accepted on the separate owner-restricted Unix
// socket. It is not a public endpoint or a receipt capability.
type MulticaNativeRequest struct {
	Action     string             `json:"action"`
	CaseID     string             `json:"caseId"`
	Binding    string             `json:"binding"`
	Projection *ProjectionRequest `json:"projection,omitempty"`
}

type MulticaNativeResult struct {
	Snapshot   *CaseSnapshot      `json:"snapshot,omitempty"`
	Projection *ProjectionReceipt `json:"projection,omitempty"`
}

func multicaNativeHandler(store *PublicStore, binding, policy string) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Cache-Control", "no-store")
		if r.Method != "POST" || r.URL.Path != "/public-native" || r.URL.RawQuery != "" {
			writeError(w, 404, "not_found")
			return
		}
		var request MulticaNativeRequest
		raw, err := readBounded(r.Body, 16<<10)
		if err != nil || decodeClosed(raw, &request) != nil || request.Binding != binding || !validID(request.CaseID) || !oneOf(request.Action, "snapshot", "project") || (request.Action == "project") != (request.Projection != nil) {
			writeError(w, 400, "invalid_request")
			return
		}
		// Recheck historical consent and removal at fetch/publication time,
		// including when an old native notification is delivered much later.
		snapshot, err := store.ExportMulticaCase(request.CaseID, binding, policy)
		if err != nil {
			writeStoreError(w, err)
			return
		}
		result := MulticaNativeResult{Snapshot: &snapshot}
		if request.Action == "project" {
			if snapshot.State != "active" {
				writeStoreError(w, ErrExpired)
				return
			}
			if !multicaAssessmentProjection(*request.Projection) {
				writeError(w, 400, "invalid_projection")
				return
			}
			receipt, err := store.EnqueueProjection(request.CaseID, binding, *request.Projection)
			if err != nil {
				writeStoreError(w, err)
				return
			}
			result = MulticaNativeResult{Projection: &receipt}
			_ = store.MarkAssessmentDelivery(request.CaseID, binding, true, "")
		}
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(result)
	})
}

func multicaAssessmentProjection(p ProjectionRequest) bool {
	// Milestones are intentional AI reports. Delivered results additionally need
	// typed public evidence, verified by the publisher before any official write.
	if !oneOf(p.WorkState, "assessing", "needs-information", "ready", "implementing", "verifying", "verified-awaiting-review", "reviewing", "verifying-integration", "merge-ready", "merging", "merged-awaiting-release", "source-published-awaiting-release", "released", "duplicate", "declined", "deferred", "blocked") || (p.WorkState == "needs-information") != (p.Question != nil) {
		return false
	}
	text := p.Summary
	if p.Question != nil {
		text += "\n" + p.Question.Description
	}
	// Public prose must not carry links copied from private task/review logs.
	// Only typed references may carry public delivery targets.
	text = strings.ToLower(text)
	for _, marker := range []string{"http:", "https:", "www.", "github.com/", "githubusercontent.com/", "git@", "file:", "]("} {
		if strings.Contains(text, marker) {
			return false
		}
	}
	return true
}

// StartMulticaNative exposes public snapshots and explicit public updates,
// never legacy feedback, receipt secrets or deletion-completion acknowledgments.
func StartMulticaNative(socket string, store *PublicStore, binding, policy string) (*http.Server, net.Listener, error) {
	if !validHash(binding) || !publicRevisionPattern.MatchString(policy) || policy == "none-v1" {
		return nil, nil, ErrInvalid
	}
	if info, err := os.Lstat(socket); err == nil {
		if info.Mode()&os.ModeSocket == 0 {
			return nil, nil, fmt.Errorf("native feedback socket path is not a socket")
		}
		if err = os.Remove(socket); err != nil {
			return nil, nil, fmt.Errorf("native feedback socket unavailable")
		}
	} else if !os.IsNotExist(err) {
		return nil, nil, fmt.Errorf("native feedback socket unavailable")
	}
	listener, err := net.Listen("unix", socket)
	if err != nil {
		return nil, nil, fmt.Errorf("native feedback socket unavailable")
	}
	if err = os.Chmod(socket, 0600); err != nil {
		listener.Close()
		return nil, nil, fmt.Errorf("native feedback socket unavailable")
	}
	server := &http.Server{Handler: multicaNativeHandler(store, binding, policy), ReadHeaderTimeout: 3 * time.Second, ReadTimeout: 5 * time.Second, WriteTimeout: 20 * time.Second, IdleTimeout: 10 * time.Second, MaxHeaderBytes: 4096}
	return server, listener, nil
}
