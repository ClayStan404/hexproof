// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package accounts

import (
	"bytes"
	"context"
	"crypto/sha256"
	"crypto/subtle"
	"encoding/json"
	"errors"
	"io"
	"net"
	"net/http"
	"net/url"
	"strings"
	"time"
)

// Remote lets every official hub use one authority without sharing a filesystem.
// The service key is an operator credential, not a player credential.
type Remote struct {
	endpoint, key, realm string
	client               *http.Client
}

func ValidRealm(realm string) bool {
	if len(realm) == 0 || len(realm) > 64 {
		return false
	}
	for _, c := range realm {
		if !(c >= 'a' && c <= 'z') && !(c >= '0' && c <= '9') && c != '.' && c != '-' {
			return false
		}
	}
	return true
}

func NewRemote(endpoint, key, realm string) (*Remote, error) {
	u, err := url.Parse(endpoint)
	if err != nil || u.Host == "" || u.User != nil || u.RawQuery != "" || u.Fragment != "" ||
		(u.Scheme != "https" && !(u.Scheme == "http" && net.ParseIP(u.Hostname()).IsLoopback())) ||
		len(key) < 32 || strings.ContainsAny(key, "\r\n") || !ValidRealm(realm) {
		return nil, ErrInvalid
	}
	return &Remote{endpoint: endpoint, key: key, realm: realm, client: &http.Client{
		Timeout:       5 * time.Second,
		CheckRedirect: func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse },
	}}, nil
}

func (r *Remote) Do(ctx context.Context, q Request) (Result, error) {
	raw, err := json.Marshal(q)
	if err != nil {
		return Result{}, err
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, r.endpoint, bytes.NewReader(raw))
	if err != nil {
		return Result{}, errors.New("account authority unavailable")
	}
	req.Header.Set("Authorization", "Bearer "+r.key)
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("X-Hexproof-Account-Realm", r.realm)
	resp, err := r.client.Do(req)
	if err != nil {
		return Result{}, errors.New("account authority unavailable")
	}
	defer resp.Body.Close()
	if resp.StatusCode == http.StatusUnauthorized {
		return Result{}, ErrInvalid
	}
	if resp.StatusCode == http.StatusTooManyRequests {
		return Result{}, ErrLimit
	}
	if resp.StatusCode != http.StatusOK {
		return Result{}, errors.New("account authority unavailable")
	}
	raw, err = io.ReadAll(io.LimitReader(resp.Body, maxRecordBytes+1))
	var out Result
	if err != nil || len(raw) > maxRecordBytes || json.Unmarshal(raw, &out) != nil || !validID(out.Profile.ID) || !validText(out.Profile.Name, 64) {
		return Result{}, errors.New("invalid account authority response")
	}
	return out, nil
}

func HTTPHandler(service Service, key, realm string) (http.Handler, error) {
	if service == nil || len(key) < 32 || strings.ContainsAny(key, "\r\n") || !ValidRealm(realm) {
		return nil, ErrInvalid
	}
	expected := sha256.Sum256([]byte("Bearer " + key))
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Cache-Control", "no-store")
		actual := sha256.Sum256([]byte(r.Header.Get("Authorization")))
		if r.Method != http.MethodPost || subtle.ConstantTimeCompare(actual[:], expected[:]) != 1 || r.Header.Get("X-Hexproof-Account-Realm") != realm {
			http.Error(w, "unavailable", http.StatusForbidden)
			return
		}
		var q Request
		decoder := json.NewDecoder(http.MaxBytesReader(w, r.Body, 4096))
		decoder.DisallowUnknownFields()
		if decoder.Decode(&q) != nil || decoder.Decode(new(any)) != io.EOF {
			http.Error(w, "invalid request", http.StatusBadRequest)
			return
		}
		out, err := service.Do(r.Context(), q)
		if err != nil {
			status := http.StatusServiceUnavailable
			if errors.Is(err, ErrInvalid) {
				status = http.StatusUnauthorized
			}
			if errors.Is(err, ErrLimit) {
				status = http.StatusTooManyRequests
			}
			http.Error(w, "account request failed", status)
			return
		}
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(out)
	}), nil
}
