// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package cluster

import (
	"bytes"
	"context"
	"crypto/sha256"
	"crypto/subtle"
	"encoding/json"
	"io"
	"net/http"
	"time"
)

const maxMessageBytes = 4 << 20

type Remote struct {
	endpoint, key, realm string
	client               *http.Client
}

func NewRemote(c Config) (*Remote, error) {
	if c.Coordinator == "" || c.Validate() != nil {
		return nil, ErrInvalid
	}
	return &Remote{endpoint: c.Coordinator, key: c.Key, realm: c.Realm, client: &http.Client{Timeout: 3 * time.Second, CheckRedirect: func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse }}}, nil
}

func (r *Remote) Do(ctx context.Context, q Request) (Result, error) {
	raw, err := json.Marshal(q)
	if err != nil || len(raw) > maxMessageBytes {
		return Result{}, ErrInvalid
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, r.endpoint, bytes.NewReader(raw))
	if err != nil {
		return Result{}, ErrUnavailable
	}
	req.Header.Set("Authorization", "Bearer "+r.key)
	req.Header.Set("X-Hexproof-Cluster-Realm", r.realm)
	req.Header.Set("Content-Type", "application/json")
	resp, err := r.client.Do(req)
	if err != nil {
		if ctx.Err() != nil {
			return Result{}, ctx.Err()
		}
		return Result{}, ErrUnavailable
	}
	defer resp.Body.Close()
	switch resp.StatusCode {
	case 409:
		return Result{}, ErrFenced
	case 410:
		return Result{}, ErrRegistration
	case 429:
		return Result{}, ErrFull
	case 400:
		return Result{}, ErrInvalid
	case 200:
	default:
		return Result{}, ErrUnavailable
	}
	raw, err = io.ReadAll(io.LimitReader(resp.Body, maxMessageBytes+1))
	if err != nil && ctx.Err() != nil {
		return Result{}, ctx.Err()
	}
	var out Result
	if err != nil || len(raw) > maxMessageBytes || json.Unmarshal(raw, &out) != nil {
		return Result{}, ErrUnavailable
	}
	return out, nil
}

func HTTPHandler(s Service, c Config) http.Handler {
	expected := sha256.Sum256([]byte("Bearer " + c.Key))
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Cache-Control", "no-store")
		actual := sha256.Sum256([]byte(r.Header.Get("Authorization")))
		if r.Method != http.MethodPost || subtle.ConstantTimeCompare(actual[:], expected[:]) != 1 || r.Header.Get("X-Hexproof-Cluster-Realm") != c.Realm {
			http.Error(w, "unavailable", 403)
			return
		}
		var q Request
		dec := json.NewDecoder(http.MaxBytesReader(w, r.Body, maxMessageBytes))
		dec.DisallowUnknownFields()
		if dec.Decode(&q) != nil || dec.Decode(new(any)) != io.EOF {
			http.Error(w, "invalid request", 400)
			return
		}
		out, err := s.Do(r.Context(), q)
		if err != nil {
			code := 503
			switch err {
			case ErrFenced:
				code = 409
			case ErrRegistration:
				code = 410
			case ErrFull:
				code = 429
			case ErrInvalid:
				code = 400
			}
			http.Error(w, "cluster request failed", code)
			return
		}
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(out)
	})
}
