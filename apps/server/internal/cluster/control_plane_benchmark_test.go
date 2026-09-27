// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package cluster

import (
	"context"
	"errors"
	"net/http/httptest"
	"testing"

	"hexproof/server/internal/benchutil"
)

type benchmarkCoordinator struct {
	Service
	stall     benchutil.Stall
	operation string
}

func (s *benchmarkCoordinator) Do(ctx context.Context, q Request) (Result, error) {
	if q.Operation == s.operation {
		if err := s.stall.Wait(ctx); err != nil {
			return Result{}, err
		}
	}
	return s.Service.Do(ctx, q)
}

func BenchmarkControlPlaneCluster(b *testing.B) {
	for _, scenario := range []string{"CacheDuringReport", "RPCDuringReport", "RPCDuringRPC"} {
		b.Run(scenario, func(b *testing.B) {
			config := testConfig()
			coordinator, err := New(config)
			if err != nil {
				b.Fatal(err)
			}
			service := &benchmarkCoordinator{Service: coordinator, operation: "report"}
			if scenario == "RPCDuringRPC" {
				service.operation = "view"
			}
			endpoint := httptest.NewServer(HTTPHandler(service, config))
			b.Cleanup(endpoint.Close)
			config.Coordinator = endpoint.URL
			remote, err := NewRemote(config)
			if err != nil {
				b.Fatal(err)
			}
			agent := Start(remote, "N1", report)
			b.Cleanup(agent.Close)
			view := func(ctx context.Context) error {
				out, err := agent.Do(ctx, Request{Operation: "view"})
				if err == nil && !out.Forge {
					return errors.New("view lost advertised capability")
				}
				return err
			}
			benchutil.Run(b, &service.stall, func(ctx context.Context) error {
				if service.operation == "report" {
					return agent.Publish(ctx, "")
				}
				return view(ctx)
			}, func(ctx context.Context, _ int) error {
				if scenario == "CacheDuringReport" {
					if !agent.Capabilities().Forge {
						return errors.New("cache lost advertised capability")
					}
					return nil
				}
				return view(ctx)
			})
		})
	}
}
