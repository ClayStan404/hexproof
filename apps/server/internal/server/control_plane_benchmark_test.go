// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package server

import (
	"context"
	"crypto/sha256"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"hexproof/server/internal/accounts"
	"hexproof/server/internal/benchutil"
	"hexproof/server/internal/protocol"
)

type benchmarkAuthority struct {
	stall benchutil.Stall
	slow  string
}

func (s *benchmarkAuthority) Do(ctx context.Context, q accounts.Request) (accounts.Result, error) {
	if q.SessionToken == "" {
		return accounts.Result{}, accounts.ErrInvalid
	}
	if q.SessionToken == s.slow {
		if err := s.stall.Wait(ctx); err != nil {
			return accounts.Result{}, err
		}
	}
	return accounts.Result{Profile: accounts.Profile{ID: q.SessionToken, Name: "Benchmark"}}, nil
}

// Deterministic synthetic identities let the same fixture exercise the old
// 256-bucket collision without changing either revision's admission policy.
func benchmarkAccountIDs(collide bool) []string {
	ids := []string{fmt.Sprintf("%032x", 0)}
	bucket := sha256.Sum256([]byte(ids[0]))[0]
	seen := map[byte]bool{bucket: true}
	for candidate := 1; len(ids) <= benchutil.Workers; candidate++ {
		id := fmt.Sprintf("%032x", candidate)
		key := sha256.Sum256([]byte(id))[0]
		if (collide && key == bucket) || (!collide && !seen[key]) {
			ids = append(ids, id)
			seen[key] = true
		}
	}
	return ids
}

func BenchmarkControlPlaneAccountAdmission(b *testing.B) {
	for _, scenario := range []string{"Independent", "LegacyCollision", "SameAccount"} {
		b.Run(scenario, func(b *testing.B) {
			h := NewHandler()
			b.Cleanup(func() { h.Close() })
			ids := benchmarkAccountIDs(scenario == "LegacyCollision")
			service := &benchmarkAuthority{slow: ids[0]}
			key, realm := strings.Repeat("b", 32), "benchmark"
			api, err := accounts.HTTPHandler(service, key, realm)
			if err != nil {
				b.Fatal(err)
			}
			authority := httptest.NewServer(api)
			b.Cleanup(authority.Close)
			h.accounts, err = accounts.NewRemote(authority.URL, key, realm)
			if err != nil {
				b.Fatal(err)
			}
			sessions := make([]*Session, len(ids))
			for i, id := range ids {
				s := &Session{ConnectionID: id, DisplayName: "Benchmark", Send: make(chan []byte, 32)}
				s.setAccount(accountBinding{ID: id, Token: id})
				h.accountConnections[id] = s
				sessions[i] = s
			}
			ping := func(ctx context.Context, s *Session) error {
				if err := h.dispatch(ctx, nil, s, protocol.Envelope{Type: protocol.TypeSessionPing}); err != nil {
					return err
				}
				// dispatch may return nil after sending an account error. Consume and
				// validate every response so a rejection cannot look like a fast ping.
				select {
				case raw := <-s.Send:
					var out protocol.Envelope
					if json.Unmarshal(raw, &out) != nil || out.Type != protocol.TypeSessionPong {
						return errors.New("account probe did not receive a pong")
					}
					return nil
				case <-ctx.Done():
					return ctx.Err()
				}
			}
			benchutil.Run(b, &service.stall, func(ctx context.Context) error {
				return ping(ctx, sessions[0])
			}, func(ctx context.Context, worker int) error {
				if scenario == "SameAccount" {
					return ping(ctx, sessions[0])
				}
				return ping(ctx, sessions[worker+1])
			})
			reportBenchmarkAdmission(b, h)
		})
	}
}

func reportBenchmarkAdmission(b *testing.B, h *Handler) {
	// A historical revision may predate readiness telemetry. Keep the workload
	// identical there; omit unavailable metrics rather than estimating lock wait.
	provider, ok := any(h).(interface {
		ServeReadiness(http.ResponseWriter, *http.Request)
	})
	if !ok {
		return
	}
	w := httptest.NewRecorder()
	provider.ServeReadiness(w, httptest.NewRequest(http.MethodGet, "/readyz", nil))
	var result struct {
		AccountGate struct {
			Calls   uint64  `json:"calls"`
			TotalMS float64 `json:"totalMs"`
			MaxMS   float64 `json:"maxMs"`
		} `json:"accountGate"`
		SendFailures uint64 `json:"sendFailures"`
	}
	if w.Code != http.StatusOK || json.Unmarshal(w.Body.Bytes(), &result) != nil || result.AccountGate.Calls != uint64(b.N*(benchutil.Workers+1)) {
		b.Fatal("incomplete readiness telemetry")
	}
	b.ReportMetric(result.AccountGate.TotalMS/float64(result.AccountGate.Calls), "gate-mean-ms")
	b.ReportMetric(result.AccountGate.MaxMS, "gate-max-ms")
	if result.SendFailures != 0 {
		b.Fatal("session queue overflow during benchmark")
	}
}
