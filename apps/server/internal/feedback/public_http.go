// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package feedback

import (
	"context"
	"errors"
	"net/http"
	"strconv"
	"strings"
	"time"
)

type PublicHandler struct {
	store     *PublicStore
	config    PublicConfig
	legacy    *Handler
	controls  *Handler
	downloads chan struct{}
}

func NewPublicHandler(store *PublicStore, c PublicConfig, legacy *Store, limits Limits, proxies []string) *PublicHandler {
	h := &PublicHandler{downloads: make(chan struct{}, 4), store: store, config: c, controls: NewHandler(nil, limits, proxies)}
	if legacy != nil {
		h.legacy = NewHandler(legacy, limits, proxies)
		h.legacy.retired = true
	}
	return h
}
func (h *PublicHandler) Close() {
	h.controls.Close()
	if h.legacy != nil {
		h.legacy.Close()
	}
}
func (h *PublicHandler) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Cache-Control", "no-store")
	w.Header().Set("X-Content-Type-Options", "nosniff")
	if r.URL.Path == "/healthz" || r.URL.Path == "/readyz" {
		if r.Method != "GET" {
			writePublicError(w, 405, "method_not_allowed")
			return
		}
		if r.URL.Path == "/readyz" && (h.controls.closed.Load() || !h.store.Ready()) {
			writePublicError(w, 503, "service_unavailable")
			return
		}
		writeJSON(w, 200, map[string]bool{"ok": true})
		return
	}
	if strings.HasPrefix(r.URL.Path, "/feedback/v1/") && h.legacy != nil {
		h.legacy.ServeHTTP(w, r)
		return
	}
	if h.controls.closed.Load() {
		writePublicError(w, 503, "service_unavailable")
		return
	}
	if r.URL.RawPath != "" || r.URL.RawQuery != "" && !strings.HasSuffix(r.URL.Path, "/thread") {
		writePublicError(w, 404, "not_found")
		return
	}
	source := h.controls.source(r)
	if !h.controls.limiter.allow(source, "requests", 1, 240, 10000, time.Now()) {
		writePublicError(w, 429, "rate_limited")
		return
	}
	if strings.HasPrefix(r.URL.Path, "/feedback/v2/assets/") {
		h.asset(w, r)
		return
	}
	id := strings.TrimPrefix(r.URL.Path, "/feedback/v2/submissions/")
	parts := strings.Split(id, "/")
	caseID, replyID := "", ""
	thread := false
	closing := false
	if len(parts) == 2 && parts[1] == "thread" && validID(parts[0]) {
		id = parts[0]
		thread = true
	} else if len(parts) == 2 && parts[1] == "close" && validID(parts[0]) {
		id = parts[0]
		closing = true
	} else if len(parts) == 3 && parts[1] == "replies" && validID(parts[0]) && validID(parts[2]) {
		caseID = parts[0]
		replyID = parts[2]
		id = replyID
	}
	if id == r.URL.Path || !validID(id) {
		writePublicError(w, 404, "not_found")
		return
	}
	if closing && r.Method != "POST" || !closing && !oneOf(r.Method, "GET", "PUT", "DELETE") {
		writePublicError(w, 405, "method_not_allowed")
		return
	}
	secret, err := parseSecret(r.Header.Values("Authorization"))
	if err != nil {
		writePublicError(w, 404, "not_found")
		return
	}
	if thread {
		h.thread(w, r, id, secret)
		return
	}
	if closing {
		h.closeCase(w, r, id, secret)
		return
	}
	if replyID != "" && r.Method == "DELETE" {
		writePublicError(w, 405, "method_not_allowed")
		return
	}
	digest := ""
	if r.Method == "PUT" {
		digest = r.Header.Get("X-Feedback-Digest")
		if len(r.Header.Values("X-Feedback-Digest")) != 1 || !validHash(digest) {
			writePublicError(w, 400, "invalid_digest")
			return
		}
	}
	var receipt PublicReceipt
	if replyID != "" {
		receipt, err = h.store.LookupReply(caseID, replyID, secret, digest)
	} else {
		receipt, err = h.store.Lookup(id, secret, digest)
	}
	if err == nil {
		if r.Method == "DELETE" {
			receipt, err = h.store.Remove(id, secret)
			if err != nil {
				writePublicStoreError(w, err)
				return
			}
		}
		writeJSON(w, 200, receipt)
		return
	}
	if !errors.Is(err, ErrNotFound) || r.Method != "PUT" {
		writePublicStoreError(w, err)
		return
	}
	if replyID != "" {
		parent, e := h.store.Lookup(caseID, secret, "")
		if e != nil {
			writePublicStoreError(w, e)
			return
		}
		if parent.CaseState == "closed" || parent.RemovalState != "none" || !h.store.now().Before(mustTime(parent.ContentExpiresAt)) {
			writePublicStoreError(w, ErrExpired)
			return
		}
	}
	if r.ContentLength > MaxUpload {
		writePublicError(w, 413, "too_large")
		return
	}
	if r.Header.Get("Content-Encoding") != "" {
		writePublicError(w, 415, "unsupported_encoding")
		return
	}
	select {
	case h.controls.uploads <- struct{}{}:
		defer func() { <-h.controls.uploads }()
	default:
		writePublicError(w, 503, "service_unavailable")
		return
	}
	if !h.controls.limiter.allow(source, "submissions", 1, float64(h.controls.limits.PerSourceSubmissions), float64(h.controls.limits.GlobalSubmissions), time.Now()) {
		writePublicError(w, 429, "rate_limited")
		return
	}
	_ = http.NewResponseController(w).SetReadDeadline(time.Now().Add(45 * time.Second))
	ctx, cancel := context.WithTimeout(r.Context(), 50*time.Second)
	defer cancel()
	body := &meteredReader{reader: http.MaxBytesReader(w, r.Body, MaxUpload), charge: func(n int) bool {
		return h.controls.limiter.allow(source, "bytes", float64(n), float64(h.controls.limits.PerSourceBytes), float64(h.controls.limits.GlobalBytes), time.Now())
	}}
	sub, err := parsePublicSubmissionFor(ctx, body, r.Header.Get("Content-Type"), id, caseID, digest, h.store.now(), h.config, h.controls.decodes)
	if err != nil {
		if body.rateLimited {
			writePublicError(w, 429, "rate_limited")
		} else if body.tooLarge {
			writePublicError(w, 413, "too_large")
		} else {
			writePublicError(w, 422, "invalid_public_content")
		}
		return
	}
	var created bool
	if replyID != "" {
		receipt, created, err = h.store.AcceptReply(caseID, secret, sub)
	} else {
		receipt, created, err = h.store.Accept(secret, sub)
	}
	if err != nil {
		writePublicStoreError(w, err)
		return
	}
	status := 200
	if created {
		status = 201
	}
	writeJSON(w, status, receipt)
}
func (h *PublicHandler) asset(w http.ResponseWriter, r *http.Request) {
	if r.Method != "GET" {
		writePublicError(w, 405, "method_not_allowed")
		return
	}
	parts := strings.Split(strings.TrimPrefix(r.URL.Path, "/feedback/v2/assets/"), "/")
	replyID := ""
	if len(parts) == 5 && parts[1] == "replies" && validID(parts[2]) {
		replyID = parts[2]
		parts = []string{parts[0], parts[3], parts[4]}
	}
	if len(parts) != 3 || !validID(parts[0]) || !attachmentPattern.MatchString(parts[1]) || !validHash(parts[2]) {
		writePublicError(w, 404, "not_found")
		return
	}
	select {
	case h.downloads <- struct{}{}:
		defer func() { <-h.downloads }()
	default:
		writePublicError(w, 503, "service_unavailable")
		return
	}
	var b Blob
	var err error
	if replyID != "" {
		b, err = h.store.ReplyAsset(parts[0], replyID, parts[1], parts[2], h.config.target())
	} else {
		b, err = h.store.Asset(parts[0], parts[1], parts[2], h.config.target())
	}
	if err != nil {
		writePublicStoreError(w, err)
		return
	}
	if !h.controls.limiter.allow(h.controls.source(r), "public_bytes", float64(len(b.Bytes)), float64(h.controls.limits.PerSourceBytes), float64(h.controls.limits.GlobalBytes), time.Now()) {
		writePublicError(w, 429, "rate_limited")
		return
	}
	_ = http.NewResponseController(w).SetWriteDeadline(time.Now().Add(30 * time.Second))
	w.Header().Set("Content-Type", b.Attachment.MediaType)
	w.Header().Set("Content-Length", strconv.Itoa(len(b.Bytes)))
	w.Header().Set("Content-Disposition", `attachment; filename="`+b.Attachment.ID+`"`)
	w.Header().Set("Content-Security-Policy", "default-src 'none'; sandbox")
	w.WriteHeader(200)
	_, _ = w.Write(b.Bytes)
}
func writePublicError(w http.ResponseWriter, status int, code string) {
	if status == 429 || status == 503 {
		w.Header().Set("Retry-After", "120")
	}
	writeJSON(w, status, struct {
		SchemaVersion int    `json:"schemaVersion"`
		Code          string `json:"code"`
	}{2, code})
}
func writePublicStoreError(w http.ResponseWriter, err error) {
	switch {
	case errors.Is(err, ErrNotFound):
		writePublicError(w, 404, "not_found")
	case errors.Is(err, ErrConflict):
		writePublicError(w, 409, "content_conflict")
	case errors.Is(err, ErrExpired):
		writePublicError(w, 410, "content_unavailable")
	case errors.Is(err, ErrInvalid):
		writePublicError(w, 422, "invalid_public_content")
	default:
		writePublicError(w, 503, "service_unavailable")
	}
}
