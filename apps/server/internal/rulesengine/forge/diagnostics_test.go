// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package forge

import (
	"bufio"
	"context"
	"encoding/json"
	"fmt"
	"os"
	"strings"
	"testing"
	"time"

	"hexproof/server/internal/forgediag"
)

func nativeDiagnostic(session string) *forgediag.Capsule {
	return &forgediag.Capsule{SchemaVersion: 1, ProducerID: "producer-" + session, SessionID: session, Sequence: 9, Kind: "engine_exception", Boundary: "effect", Attribution: "execution_site", SymbolIndexID: forgediag.SymbolIndexID(), Causes: []forgediag.Cause{{ClassName: "java.lang.IllegalStateException", Frames: []forgediag.Frame{{ClassName: "org.hexproof.forge.NativeSession", MethodName: "fail", Line: 549}}}}, Spans: []forgediag.Span{{ID: 1, Stage: "effect", API: "Draw"}}}
}

func TestDiagnosticDrainResynchronizesAndFencesIncarnations(t *testing.T) {
	value := nativeDiagnostic("game")
	raw, _ := json.Marshal(value)
	input := "untrusted token secret\n" + strings.Repeat("x", 128<<10) + "\n" + forgediag.StreamPrefix + "not JSON\n" + forgediag.StreamPrefix + string(raw) + "\n"
	collector := newDiagnosticCollector()
	collector.bind("game", "producer-game", 31)
	drainDiagnostics(strings.NewReader(input), collector.streamAccept)
	if info := collector.snapshot(); info.Native == nil || len(info.Native.Causes[0].Frames) != 1 {
		t.Fatalf("valid record after oversize was lost: %+v", info)
	}
	fresh := newDiagnosticCollector()
	fresh.bind("game", "replacement-producer", 31)
	drainDiagnostics(strings.NewReader(forgediag.StreamPrefix+string(raw)+"\n"), fresh.streamAccept)
	if fresh.snapshot().Native != nil {
		t.Fatal("old logical session incarnation contaminated replacement")
	}
	fresh.bind("game", "", 30)
	drainDiagnostics(strings.NewReader(forgediag.StreamPrefix+string(raw)+"\n"), fresh.streamAccept)
	if fresh.snapshot().Native != nil {
		t.Fatal("legacy unbound producer accepted asynchronous evidence")
	}
}

func TestSharedExitDoesNotFinishCollectionBeforeStderrDrain(t *testing.T) {
	worker := &sharedWorker{diagnostics: newDiagnosticCollector(), done: make(chan struct{})}
	worker.invalid.Store(true)
	worker.diagnostics.exit(nil)
	client := &Client{diagnostics: newDiagnosticCollector(), done: make(chan struct{}), shared: &sharedLease{worker: worker}}
	close(client.done)
	if client.FailureInfo().CollectionDone {
		t.Fatal("lease Done discarded pending terminal stderr")
	}
	worker.diagnostics.drained()
	if !client.FailureInfo().CollectionDone {
		t.Fatal("reaped and drained worker never finished collection")
	}
}

func crashProcessConfig(mode string) ProcessConfig {
	return ProcessConfig{Command: os.Args[0], Args: []string{"-test.run=^TestDiagnosticProcessHelper$", "--"}, Env: []string{"HEXPROOF_CRASH_HELPER=" + mode, "GORACE=atexit_sleep_ms=0"}, StartTimeout: 3 * time.Second}
}

func TestDedicatedTerminalEvidenceSurvivesKillWithoutStderr(t *testing.T) {
	client, err := Start(t.Context(), crashProcessConfig("fatal"))
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = client.Close() })
	req := validStartRequest()
	req.GameID = "failing"
	handle, err := client.StartGame(t.Context(), req)
	if err != nil {
		t.Fatal(err)
	}
	if err = client.SubmitAction(t.Context(), handle.SessionID, json.RawMessage(`{"type":"pass"}`)); err == nil {
		t.Fatal("fatal action succeeded")
	}
	select {
	case <-client.Done():
	case <-time.After(3 * time.Second):
		t.Fatal("failed JVM not reaped")
	}
	info := client.FailureInfo()
	if info.Native == nil || info.Native.Causes[0].ClassName != "java.lang.IllegalStateException" || info.Boundary == nil || info.Boundary.Code != "native_failure" || info.Exit == nil {
		t.Fatalf("terminal response lost before kill: %+v", info)
	}
	info.Native.Causes[0].ClassName = "changed"
	if client.FailureInfo().Native.Causes[0].ClassName == "changed" {
		t.Fatal("FailureInfo returned mutable evidence")
	}
}

func TestSharedTerminalFailureKeepsNeighborAndDoesNotRepeatCleanup(t *testing.T) {
	pool, err := NewPool(crashProcessConfig("shared"), 2)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = pool.Close() })
	first := poolGame(t, pool, "failing")
	second := poolGame(t, pool, "survivor")
	if err = first.SubmitAction(t.Context(), "failing", json.RawMessage(`{"type":"pass"}`)); err == nil {
		t.Fatal("fatal shared action succeeded")
	}
	select {
	case <-first.Done():
	case <-time.After(3 * time.Second):
		t.Fatal("terminal lease not released")
	}
	if first.FailureInfo().Native == nil {
		t.Fatal("shared terminal capsule lost")
	}
	if !second.Healthy() || second.FailureInfo().Native != nil {
		t.Fatal("another session inherited failure or worker was killed")
	}
	if err = second.SubmitAction(t.Context(), "survivor", json.RawMessage(`{"type":"pass"}`)); err != nil {
		t.Fatalf("surviving lease unusable: %v", err)
	}
}

func TestNaturalExitAndDeadlineRemainDifferent(t *testing.T) {
	for _, mode := range []string{"exit", "timeout"} {
		t.Run(mode, func(t *testing.T) {
			client, err := Start(t.Context(), crashProcessConfig(mode))
			if err != nil {
				t.Fatal(err)
			}
			t.Cleanup(func() { _ = client.Close() })
			req := validStartRequest()
			req.GameID = "failing"
			handle, err := client.StartGame(t.Context(), req)
			if err != nil {
				t.Fatal(err)
			}
			ctx, cancel := context.WithTimeout(t.Context(), 100*time.Millisecond)
			defer cancel()
			if client.SubmitAction(ctx, handle.SessionID, json.RawMessage(`{"type":"pass"}`)) == nil {
				t.Fatal("failed action succeeded")
			}
			<-client.Done()
			info := client.FailureInfo()
			if info.Native != nil {
				t.Fatal("exit or hang invented native exception")
			}
			if mode == "exit" && (info.Exit == nil || info.Exit.Code == nil || *info.Exit.Code != 23 || info.Exit.SupervisorKilled) {
				t.Fatalf("natural exit lost: %+v", info)
			}
			if mode == "timeout" && (info.Boundary == nil || info.Boundary.Code != "execution_timeout") {
				t.Fatalf("deadline not recorded: %+v", info)
			}
		})
	}
}

func TestDiagnosticProcessHelper(t *testing.T) {
	mode := os.Getenv("HEXPROOF_CRASH_HELPER")
	if mode == "" {
		return
	}
	scanner := bufio.NewScanner(os.Stdin)
	for scanner.Scan() {
		var req sharedRequest
		if json.Unmarshal(scanner.Bytes(), &req) != nil {
			os.Exit(2)
		}
		response := sharedResponse{RequestID: req.RequestID, rpcResponse: rpcResponse{OK: true, Result: `{}`}}
		switch req.Command {
		case "reset":
			response.Result = `{"adapterRevision":31,"sharedVersion":1,"capacity":2}`
		case "startGame":
			var request StartGameRequest
			_ = json.Unmarshal([]byte(req.Payload), &request)
			handle, _ := json.Marshal(SessionHandle{SessionID: request.GameID, DiagnosticProducerID: "producer-" + request.GameID, PlayerIndexes: []int{0, 1}})
			response.Result = string(handle)
		case "submitAction":
			if mode == "exit" {
				os.Exit(23)
			}
			if mode == "timeout" {
				time.Sleep(time.Minute)
			}
			if req.SessionID == "failing" {
				response.OK = false
				response.Fatal = true
				response.FailureInfo, _ = json.Marshal(nativeDiagnostic(req.SessionID))
			}
		case "abortGame":
			if mode == "shared" && req.SessionID == "failing" {
				os.Exit(99)
			}
		case "shutdown":
			os.Exit(0)
		}
		raw, _ := json.Marshal(response)
		fmt.Println(string(raw))
	}
	os.Exit(0)
}
