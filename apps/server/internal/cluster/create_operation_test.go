// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package cluster

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"hexproof/server/internal/protocol"
)

func createAllocation(node, generation, operation string) Request {
	q := allocation(node, generation, Demand{Events: 1})
	q.CommandType, q.CreateOperationID = protocol.TypeTournamentCreate, operation
	return q
}

func TestCreateOperationGlobalAcrossEntrancesAndChangedRequests(t *testing.T) {
	c, _ := New(testConfig())
	g1, g2 := register(t, c, "N1", report()), register(t, c, "N2", report())
	var successes, replays atomic.Int64
	var wg sync.WaitGroup
	for _, q := range []Request{createAllocation("N1", g1, "same-operation"), createAllocation("N2", g2, "same-operation")} {
		wg.Add(1)
		go func(q Request) {
			defer wg.Done()
			_, err := c.Do(t.Context(), q)
			if err == nil {
				successes.Add(1)
			} else if err == ErrOperationReplay {
				replays.Add(1)
			} else {
				t.Error(err)
			}
		}(q)
	}
	wg.Wait()
	if successes.Load() != 1 || replays.Load() != 1 || len(c.tickets) != 1 || len(c.createOperations) != 1 {
		t.Fatal("two entrances allocated the same operation")
	}
	q := createAllocation("N2", g2, "same-operation")
	q.Digest, q.AccountID, q.Target = strings.Repeat("b", 64), "another-account", "N2"
	if _, err := c.Do(t.Context(), q); err != ErrOperationReplay {
		t.Fatal("changed digest/account/target bypassed identity", err)
	}
	if len(c.tickets) != 1 {
		t.Fatal("replay allocated another ticket")
	}
}

func TestCreateOperationSurvivesCompletionExpiryAndRegistration(t *testing.T) {
	for _, scenario := range []string{"completion", "expiry", "registration", "allocation-failure"} {
		t.Run(scenario, func(t *testing.T) {
			c, _ := New(testConfig())
			now := time.Now()
			c.now = func() time.Time { return now }
			g1, g2 := register(t, c, "N1", report()), register(t, c, "N2", report())
			q := createAllocation("N1", g1, "persistent-operation")
			q.Target = "N2"
			if scenario == "allocation-failure" {
				q.Target = "unknown"
			}
			out, err := c.Do(t.Context(), q)
			if scenario == "allocation-failure" {
				if err != ErrFull {
					t.Fatal("expected failed allocation", err)
				}
			} else if err != nil || out.Ticket == nil {
				t.Fatal("allocation failed", err)
			}
			switch scenario {
			case "completion":
				_, err = c.Do(t.Context(), Request{RPCVersion: RPCVersion, Operation: "take", NodeID: "N2", Generation: g2, Token: out.Ticket.Token, AccountID: q.AccountID})
				if err != nil {
					t.Fatal(err)
				}
				r := report()
				_, err = c.Do(t.Context(), Request{RPCVersion: RPCVersion, Operation: "report", NodeID: "N2", Generation: g2, ReportSequence: 2, Report: &r, Completed: []string{out.Ticket.Token}})
				if err != nil || len(c.tickets) != 0 {
					t.Fatal("completion failed", err)
				}
			case "expiry":
				now = now.Add(TicketLifetime + time.Second)
				g1, g2 = register(t, c, "N1", report()), register(t, c, "N2", report())
				if len(c.tickets) != 0 {
					t.Fatal("ticket did not expire")
				}
			case "registration":
				g1, g2 = register(t, c, "N1", report()), register(t, c, "N2", report())
			}
			before := len(c.tickets)
			q = createAllocation("N2", g2, "persistent-operation")
			q.Target = "N1"
			if _, err = c.Do(t.Context(), q); err != ErrOperationReplay || len(c.tickets) != before {
				t.Fatal("terminal condition forgot operation", scenario, err)
			}
		})
	}
}

func TestCreateOperationHistoryCapAndProtocolPartition(t *testing.T) {
	c, _ := New(testConfig())
	g1 := register(t, c, "N1", report())
	other := report()
	other.Protocol = "hexproof.v2"
	g2 := register(t, c, "N2", other)
	if _, err := c.Do(t.Context(), createAllocation("N1", g1, "partitioned")); err != nil {
		t.Fatal(err)
	}
	if _, err := c.Do(t.Context(), createAllocation("N2", g2, "partitioned")); err != nil {
		t.Fatal("game protocol was not part of identity", err)
	}
	for i := len(c.createOperations); i < MaxCreateOperations; i++ {
		c.createOperations[fmt.Sprintf("filled:%d", i)] = struct{}{}
	}
	before := len(c.tickets)
	if _, err := c.Do(t.Context(), createAllocation("N1", g1, "overflow")); err != ErrOperationHistoryFull || len(c.tickets) != before {
		t.Fatal("history overflow allocated", err)
	}
	if _, err := c.Do(t.Context(), createAllocation("N1", g1, "partitioned")); err != ErrOperationReplay {
		t.Fatal("history cap evicted old identity", err)
	}
}

func TestCreateOperationValidatesShapeBeforeClaim(t *testing.T) {
	c, _ := New(testConfig())
	g := register(t, c, "N1", report())
	for _, id := range []string{" leading", "trailing ", "control\nvalue", strings.Repeat("x", 129)} {
		if _, err := c.Do(t.Context(), createAllocation("N1", g, id)); err != ErrInvalid {
			t.Fatal("malformed operation accepted", err)
		}
	}
	q := createAllocation("N1", g, "must-not-claim")
	q.CommandType = protocol.TypeRoomCreate
	if _, err := c.Do(t.Context(), q); err != ErrInvalid {
		t.Fatal("identity accepted for another command", err)
	}
	q = createAllocation("N1", "invalid-generation", "must-not-claim")
	if _, err := c.Do(t.Context(), q); err != ErrFenced {
		t.Fatal("stale node admitted", err)
	}
	if len(c.createOperations) != 0 || len(c.tickets) != 0 {
		t.Fatal("invalid request claimed identity")
	}
}

func TestHTTPCreateLostResponseCannotAllocateAgain(t *testing.T) {
	cfg := testConfig()
	c, _ := New(cfg)
	g1, g2 := register(t, c, "N1", report()), register(t, c, "N2", report())
	underlying := HTTPHandler(c, cfg)
	var lost atomic.Bool
	remote := newRemotePeer(t, cfg, http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if !lost.Swap(true) {
			response := httptest.NewRecorder()
			underlying.ServeHTTP(response, r)
			if response.Code != http.StatusOK {
				t.Error("first allocation was not committed", response.Code)
			}
			// The reservation succeeded but its success body never reaches the caller.
			w.WriteHeader(http.StatusServiceUnavailable)
			return
		}
		underlying.ServeHTTP(w, r)
	}))
	if _, err := remote.Do(t.Context(), createAllocation("N1", g1, "lost-response")); err != ErrUnavailable {
		t.Fatal("missing response was not uncertain", err)
	}
	if len(c.tickets) != 1 {
		t.Fatal("first request did not allocate exactly one ticket")
	}
	if _, err := remote.Do(t.Context(), createAllocation("N2", g2, "lost-response")); err != ErrOperationReplay || len(c.tickets) != 1 {
		t.Fatal("lost response caused a new ticket", err)
	}
}

func TestHTTPOperationErrorsDoNotFenceOrReregisterAgent(t *testing.T) {
	cfg := testConfig()
	c, _ := New(cfg)
	remote := newRemotePeer(t, cfg, HTTPHandler(c, cfg))
	agent := Start(remote, "N1", report)
	defer agent.Close()
	agent.mu.Lock()
	generation := agent.generation
	agent.mu.Unlock()
	q := createAllocation("", "", "one-http-operation")
	if _, err := agent.Do(t.Context(), q); err != nil {
		t.Fatal(err)
	}
	if _, err := agent.Do(t.Context(), q); err != ErrOperationReplay {
		t.Fatal("HTTP replay lost error semantics", err)
	}
	c.mu.Lock()
	for i := len(c.createOperations); i < MaxCreateOperations; i++ {
		c.createOperations[fmt.Sprintf("filled:%d", i)] = struct{}{}
	}
	c.mu.Unlock()
	q.CreateOperationID = "history-overflow"
	if _, err := agent.Do(t.Context(), q); err != ErrOperationHistoryFull {
		t.Fatal("HTTP cap lost error semantics", err)
	}
	agent.mu.Lock()
	unchanged := agent.generation == generation && !agent.fenced && agent.reported
	agent.mu.Unlock()
	if !unchanged {
		t.Fatal("operation rejection invalidated registration")
	}
	if err := agent.Publish(t.Context(), ""); err != nil {
		t.Fatal("operation rejection stopped reporting", err)
	}
}

type operationServiceFunc func(context.Context, Request) (Result, error)

func (f operationServiceFunc) Do(ctx context.Context, q Request) (Result, error) { return f(ctx, q) }

func TestRPCSuccessVersionRequiredForLocalAndHTTPPeers(t *testing.T) {
	for _, version := range []string{"", "hexproof.cluster.v1", "hexproof.cluster.v3"} {
		t.Run(version, func(t *testing.T) {
			service := operationServiceFunc(func(context.Context, Request) (Result, error) {
				return Result{RPCVersion: version, Generation: "must-not-be-accepted"}, nil
			})
			agent := Start(service, "N1", report)
			defer agent.Close()
			if agent.Status().Ready {
				t.Fatal("local service accepted another RPC success")
			}
			cfg := testConfig()
			remote := newRemotePeer(t, cfg, http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
				_ = json.NewEncoder(w).Encode(Result{RPCVersion: version, Generation: "must-not-be-accepted"})
			}))
			if out, err := remote.Do(t.Context(), Request{RPCVersion: RPCVersion, Operation: "register", NodeID: "N1"}); err == nil || out.Generation != "" {
				t.Fatal("HTTP accepted another RPC success", out, err)
			}
		})
	}
}

func TestRPCMismatchPrecedesAllCoordinatorMutation(t *testing.T) {
	c, _ := New(testConfig())
	g := register(t, c, "N1", report())
	q := allocation("N1", g, Demand{Rooms: 1})
	allocated, err := c.Do(t.Context(), q)
	if err != nil {
		t.Fatal(err)
	}
	for _, version := range []string{"", "hexproof.cluster.v1", "hexproof.cluster.v3"} {
		for _, operation := range []string{"register", "allocate", "take"} {
			request := q
			request.RPCVersion, request.Operation, request.Token = version, operation, allocated.Ticket.Token
			if _, err := c.Do(t.Context(), request); err != ErrInvalid {
				t.Fatal("RPC mismatch admitted", version, operation, err)
			}
			if c.states["N1"].generation != g || len(c.tickets) != 1 || c.tickets[allocated.Ticket.Token].Taken || len(c.createOperations) != 0 {
				t.Fatal("RPC mismatch changed coordinator state")
			}
		}
	}
}
