// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package feedback

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"errors"
	"io"
	"net"
	"net/http"
	"net/netip"
	"strings"
	"sync"
	"sync/atomic"
	"time"
)

type Handler struct {
	store   *Store
	limits  Limits
	limiter *rateLimiter
	uploads chan struct{}
	queries chan struct{}
	decodes chan struct{}
	proxies []netip.Prefix
	closed  atomic.Bool
}

func NewHandler(store *Store, limits Limits, proxies []string) *Handler {
	h := &Handler{store: store, limits: limits.defaults(), uploads: make(chan struct{}, 4), queries: make(chan struct{}, 8), decodes: make(chan struct{}, 2), limiter: &rateLimiter{sources: map[string]*buckets{}}}
	for _, p := range proxies {
		if prefix, err := netip.ParsePrefix(p); err == nil {
			h.proxies = append(h.proxies, prefix)
		}
	}
	return h
}

func (h *Handler) Close() { h.closed.Store(true) }

func (h *Handler) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Cache-Control", "no-store")
	w.Header().Set("X-Content-Type-Options", "nosniff")
	if r.URL.Path == "/healthz" || r.URL.Path == "/readyz" {
		if r.Method != "GET" {
			writeError(w, 405, "method_not_allowed")
			return
		}
		if r.URL.Path == "/readyz" && h.closed.Load() {
			writeError(w, 503, "service_unavailable")
			return
		}
		writeJSON(w, 200, map[string]bool{"ok": true})
		return
	}
	if h.closed.Load() {
		writeError(w, 503, "service_unavailable")
		return
	}
	id := strings.TrimPrefix(r.URL.Path, "/feedback/v1/submissions/")
	if id == r.URL.Path || !validID(id) || r.URL.RawQuery != "" || r.URL.RawPath != "" {
		writeError(w, 404, "not_found")
		return
	}
	if r.Method != "GET" && r.Method != "PUT" {
		writeError(w, 405, "method_not_allowed")
		return
	}
	source := h.source(r)
	if !h.limiter.allow(source, "requests", 1, 240, 10000, time.Now()) {
		writeError(w, 429, "rate_limited")
		return
	}
	secret, err := parseSecret(r.Header.Values("Authorization"))
	if err != nil {
		writeError(w, 404, "not_found")
		return
	}
	digest := ""
	if r.Method == "PUT" {
		digest = r.Header.Get("X-Feedback-Digest")
		if len(r.Header.Values("X-Feedback-Digest")) != 1 || !validHash(digest) {
			writeError(w, 400, "invalid_digest")
			return
		}
	}
	select {
	case h.queries <- struct{}{}:
	default:
		writeError(w, 503, "service_unavailable")
		return
	}
	ctx, cancel := context.WithTimeout(r.Context(), 5*time.Second)
	receipt, lookupErr := h.store.Lookup(ctx, id, secret, digest)
	cancel()
	<-h.queries
	if lookupErr == nil {
		writeJSON(w, 200, receipt)
		return
	}
	if r.Method == "GET" || !errors.Is(lookupErr, ErrNotFound) {
		writeStoreError(w, lookupErr)
		return
	}
	// An existing ID with another secret is indistinguishable from absence,
	// but is never overwritten by the acceptance transaction below.
	if h.store.get(id) != nil {
		writeError(w, 404, "not_found")
		return
	}
	if r.ContentLength > MaxUpload {
		writeError(w, 413, "too_large")
		return
	}
	if r.Header.Get("Content-Encoding") != "" {
		writeError(w, 415, "unsupported_encoding")
		return
	}
	select {
	case h.uploads <- struct{}{}:
		defer func() { <-h.uploads }()
	default:
		writeError(w, 503, "service_unavailable")
		return
	}
	if !h.limiter.allow(source, "submissions", 1, float64(h.limits.PerSourceSubmissions), float64(h.limits.GlobalSubmissions), time.Now()) {
		writeError(w, 429, "rate_limited")
		return
	}
	reservation, err := h.store.Reserve()
	if err != nil {
		writeStoreError(w, err)
		return
	}
	defer reservation.Release()
	_ = http.NewResponseController(w).SetReadDeadline(time.Now().Add(45 * time.Second))
	ctx, cancel = context.WithTimeout(r.Context(), 50*time.Second)
	defer cancel()
	body := &meteredReader{reader: http.MaxBytesReader(w, r.Body, MaxUpload), charge: func(n int) bool {
		return h.limiter.allow(source, "bytes", float64(n), float64(h.limits.PerSourceBytes), float64(h.limits.GlobalBytes), time.Now())
	}}
	sub, err := parseSubmission(ctx, body, r.Header.Get("Content-Type"), id, digest, h.store.now(), h.decodes)
	if err != nil {
		if body.rateLimited {
			writeError(w, 429, "rate_limited")
		} else if body.tooLarge {
			writeError(w, 413, "too_large")
		} else if ctx.Err() != nil {
			writeError(w, 503, "service_unavailable")
		} else {
			writeError(w, 422, "invalid_content")
		}
		return
	}
	receipt, created, err := h.store.Accept(ctx, reservation, secret, sub)
	if err != nil {
		writeStoreError(w, err)
		return
	}
	status := 200
	if created {
		status = 201
	}
	writeJSON(w, status, receipt)
}

func parseSecret(values []string) ([]byte, error) {
	if len(values) != 1 || !strings.HasPrefix(values[0], "Feedback ") {
		return nil, ErrNotFound
	}
	text := strings.TrimPrefix(values[0], "Feedback ")
	if len(text) != 43 {
		return nil, ErrNotFound
	}
	raw, err := base64.RawURLEncoding.Strict().DecodeString(text)
	if err != nil || len(raw) != 32 {
		return nil, ErrNotFound
	}
	return raw, nil
}

func writeStoreError(w http.ResponseWriter, err error) {
	switch {
	case errors.Is(err, ErrNotFound):
		writeError(w, 404, "not_found")
	case errors.Is(err, ErrConflict):
		writeError(w, 409, "content_conflict")
	case errors.Is(err, ErrExpired):
		writeError(w, 410, "content_unavailable")
	case errors.Is(err, ErrInvalid):
		writeError(w, 422, "invalid_content")
	default:
		writeError(w, 503, "service_unavailable")
	}
}
func writeError(w http.ResponseWriter, status int, code string) {
	if status == 429 || status == 503 {
		w.Header().Set("Retry-After", "120")
	}
	writeJSON(w, status, struct {
		SchemaVersion int    `json:"schemaVersion"`
		Code          string `json:"code"`
	}{1, code})
}
func writeJSON(w http.ResponseWriter, status int, value any) {
	raw, err := json.Marshal(value)
	if err != nil || len(raw) > 8192 {
		status = 500
		raw = []byte(`{"schemaVersion":1,"code":"service_unavailable"}`)
	}
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_, _ = w.Write(raw)
}

type meteredReader struct {
	reader      io.Reader
	charge      func(int) bool
	rateLimited bool
	tooLarge    bool
}

func (r *meteredReader) Read(p []byte) (int, error) {
	n, err := r.reader.Read(p)
	if n > 0 && !r.charge(n) {
		r.rateLimited = true
		return 0, ErrCapacity
	}
	var large *http.MaxBytesError
	if errors.As(err, &large) {
		r.tooLarge = true
	}
	return n, err
}

func (h *Handler) trusted(addr netip.Addr) bool {
	for _, p := range h.proxies {
		if p.Contains(addr) {
			return true
		}
	}
	return false
}
func (h *Handler) source(r *http.Request) string {
	host, _, err := net.SplitHostPort(r.RemoteAddr)
	if err != nil {
		host = r.RemoteAddr
	}
	addr, err := netip.ParseAddr(host)
	if err != nil {
		return "unknown"
	}
	addr = addr.Unmap()
	if h.trusted(addr) {
		forwarded := r.Header.Get("X-Forwarded-For")
		if len(forwarded) <= 2048 {
			parts := strings.Split(forwarded, ",")
			if len(parts) <= 16 {
				for i := len(parts) - 1; i >= 0 && h.trusted(addr); i-- {
					next, err := netip.ParseAddr(strings.TrimSpace(parts[i]))
					if err != nil {
						break
					}
					addr = next.Unmap()
				}
			}
		}
	}
	if addr.Is6() {
		return netip.PrefixFrom(addr, 64).Masked().String()
	}
	return addr.String()
}

type bucket struct {
	tokens float64
	at     time.Time
}
type buckets struct {
	byKind map[string]bucket
	last   time.Time
}
type rateLimiter struct {
	mu        sync.Mutex
	sources   map[string]*buckets
	global    buckets
	lastPrune time.Time
}

func refill(b bucket, capacity float64, now time.Time) bucket {
	if b.at.IsZero() {
		return bucket{capacity, now}
	}
	elapsed := now.Sub(b.at).Seconds()
	if elapsed < 0 {
		elapsed = 0
	}
	b.tokens += elapsed * capacity / 3600
	if b.tokens > capacity {
		b.tokens = capacity
	}
	b.at = now
	return b
}
func (l *rateLimiter) allow(source, kind string, cost, perSource, global float64, now time.Time) bool {
	l.mu.Lock()
	defer l.mu.Unlock()
	if l.global.byKind == nil {
		l.global.byKind = map[string]bucket{}
	}
	s := l.sources[source]
	if s == nil {
		if len(l.sources) >= 4096 && now.Sub(l.lastPrune) >= time.Minute {
			l.lastPrune = now
			for k, v := range l.sources {
				if now.Sub(v.last) > time.Hour {
					delete(l.sources, k)
				}
			}
		}
		if len(l.sources) >= 4096 {
			return false
		}
		s = &buckets{byKind: map[string]bucket{}}
		l.sources[source] = s
	}
	s.last = now
	a := refill(s.byKind[kind], perSource, now)
	b := refill(l.global.byKind[kind], global, now)
	allowed := a.tokens >= cost && b.tokens >= cost
	if allowed {
		a.tokens -= cost
		b.tokens -= cost
	}
	s.byKind[kind] = a
	l.global.byKind[kind] = b
	return allowed
}
