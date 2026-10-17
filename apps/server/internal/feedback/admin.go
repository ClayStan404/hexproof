// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package feedback

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"net"
	"net/http"
	"os"
	"path/filepath"
	"time"
)

type AdminRequest struct {
	Action  string `json:"action"`
	Receipt string `json:"receipt,omitempty"`
}
type AdminItem struct {
	Receipt   Receipt  `json:"receipt"`
	Delivery  Delivery `json:"delivery"`
	Tombstone bool     `json:"tombstone"`
}
type AdminResult struct {
	Stats    *Stats      `json:"stats,omitempty"`
	Items    []AdminItem `json:"items,omitempty"`
	Record   *Record     `json:"record,omitempty"`
	Delivery *Delivery   `json:"delivery,omitempty"`
	OK       bool        `json:"ok,omitempty"`
}

func (s *Store) Admin(ctx context.Context, request AdminRequest) (AdminResult, error) {
	if !s.begin() {
		return AdminResult{}, ErrUnavailable
	}
	defer s.ops.Done()
	if request.Action == "stats" {
		stats, err := s.Stats(ctx)
		return AdminResult{Stats: &stats}, err
	}
	if request.Action == "list" {
		result := AdminResult{Items: []AdminItem{}}
		for _, id := range s.IDs() {
			e := s.get(id)
			if e == nil {
				continue
			}
			if err := acquire(ctx, e); err != nil {
				return AdminResult{}, err
			}
			result.Items = append(result.Items, AdminItem{e.record.Receipt, e.delivery, e.record.Tombstone})
			release(e)
		}
		return result, nil
	}
	if !validID(request.Receipt) {
		return AdminResult{}, ErrInvalid
	}
	e := s.get(request.Receipt)
	if e == nil {
		return AdminResult{}, ErrNotFound
	}
	if err := acquire(ctx, e); err != nil {
		return AdminResult{}, err
	}
	defer release(e)
	if err := s.readyLocked(e, request.Receipt); err != nil {
		return AdminResult{}, err
	}
	if request.Action == "inspect" {
		r, _, err := readRecord(filepath.Join(s.dir, request.Receipt, "record.json"))
		d := e.delivery
		return AdminResult{Record: &r, Delivery: &d}, err
	}
	if !oneOf(request.Action, "confirm", "retry", "discard") {
		return AdminResult{}, ErrInvalid
	}
	if e.live {
		return AdminResult{}, ErrBusy
	}
	if e.record.Tombstone || !s.now().Before(mustTime(e.record.Receipt.ContentExpiresAt)) {
		return AdminResult{}, ErrExpired
	}
	if request.Action == "discard" {
		if err := s.discardLocked(request.Receipt, e, "spam"); err != nil {
			return AdminResult{}, err
		}
	} else {
		d := e.delivery
		if request.Action == "confirm" {
			if !oneOf(d.State, "uncertain", "needs_attention") {
				return AdminResult{}, ErrConflict
			}
			d.State = "handed_off"
			d.Code = "operator_confirmed"
		} else {
			if !oneOf(d.State, "uncertain", "needs_attention", "retry_wait") {
				return AdminResult{}, ErrConflict
			}
			d.State = "pending"
			d.Code = "operator_retry"
			d.NextAttempt = time.Time{}
		}
		d.UpdatedAt = s.now()
		if err := s.saveDeliveryLocked(request.Receipt, e, d); err != nil {
			return AdminResult{}, err
		}
		e.delivery = d
	}
	log.Printf("feedback admin action=%s receipt=%s", request.Action, request.Receipt)
	return AdminResult{OK: true}, nil
}

func StartAdmin(socket string, s *Store) (*http.Server, net.Listener, error) {
	if info, err := os.Lstat(socket); err == nil {
		if info.Mode()&os.ModeSocket == 0 {
			return nil, nil, fmt.Errorf("admin socket path is not a socket")
		}
		if err := os.Remove(socket); err != nil {
			return nil, nil, err
		}
	} else if !os.IsNotExist(err) {
		return nil, nil, err
	}
	listener, err := net.Listen("unix", socket)
	if err != nil {
		return nil, nil, err
	}
	if err := os.Chmod(socket, 0600); err != nil {
		listener.Close()
		return nil, nil, err
	}
	handler := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Cache-Control", "no-store")
		if r.Method != "POST" || r.URL.Path != "/admin" {
			writeError(w, 404, "not_found")
			return
		}
		var request AdminRequest
		raw, err := readBounded(r.Body, 1024)
		if err != nil || decodeClosed(raw, &request) != nil {
			writeError(w, 400, "invalid_request")
			return
		}
		ctx, cancel := context.WithTimeout(r.Context(), 10*time.Second)
		defer cancel()
		result, err := s.Admin(ctx, request)
		if err != nil {
			writeStoreError(w, err)
			return
		}
		w.Header().Set("Content-Type", "application/json")
		// This private capability is deliberately separate from the public API's
		// 8 KiB metadata-only responses. It may inspect one bounded stored body.
		_ = json.NewEncoder(w).Encode(result)
	})
	server := &http.Server{Handler: handler, ReadHeaderTimeout: 3 * time.Second, ReadTimeout: 5 * time.Second, WriteTimeout: 20 * time.Second, IdleTimeout: 10 * time.Second, MaxHeaderBytes: 4096}
	return server, listener, nil
}
