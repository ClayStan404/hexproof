// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package forgehost

import (
	"context"
	"encoding/json"
	"errors"
	"strings"
	"testing"
	"time"

	"hexproof/server/internal/forgediag"
	"hexproof/server/internal/protocol"
	"hexproof/server/internal/rulesengine/forge"
)

type diagnosticRuntime struct{ *fixtureRuntime }

func (r *diagnosticRuntime) GameOver(context.Context, string) (bool, error) {
	r.mu.Lock()
	defer r.mu.Unlock()
	if r.actions > 0 {
		return false, errors.New("private card exception token secret")
	}
	return false, nil
}

func (r *diagnosticRuntime) FailureInfo() forgediag.FailureInfo {
	return forgediag.FailureInfo{ProducerID: "native-run", Native: &forgediag.Capsule{SchemaVersion: 1, ProducerID: "native-session", SessionID: "session", Sequence: 4, Kind: "engine_exception", Boundary: "effect", Attribution: "execution_site", SymbolIndexID: forgediag.SymbolIndexID(), Causes: []forgediag.Cause{{ClassName: "java.lang.IllegalStateException"}}}}
}

func newDiagnosticExecutor(t *testing.T) (*Executor, string, <-chan string) {
	t.Helper()
	notified := make(chan string, 2)
	e := NewExecutor("ROOM", func(context.Context) (forge.Runtime, error) {
		return &diagnosticRuntime{&fixtureRuntime{done: make(chan struct{})}}, nil
	}, func(id string) { notified <- id })
	t.Cleanup(func() { e.Cancel("") })
	engine := NewID()
	response := e.Execute(t.Context(), Request{RoomID: "ROOM", EngineID: engine, ID: 1, Command: "start", Start: &forge.StartGameRequest{GameID: "game", Variant: "Commander", Players: make([]forge.PlayerConfig, 2)}})
	if response.Error != "" {
		t.Fatal(response.Error)
	}
	return e, engine, notified
}

func TestHelperPublicationFailureRetainsEvidenceBeforeCancel(t *testing.T) {
	e, engine, notified := newDiagnosticExecutor(t)
	req := Request{RoomID: "ROOM", EngineID: engine, ID: 2, Command: "action", Action: json.RawMessage(`{"pass":true}`)}
	response := e.Execute(t.Context(), req)
	if response.Error != "failed" || response.FailureInfo == nil || response.FailureInfo.Native == nil {
		t.Fatalf("failure capsule lost on Cancel: %+v", response)
	}
	_, alive := e.State()
	if alive {
		t.Fatal("publication failure left engine alive")
	}
	if repeated := e.Execute(t.Context(), req); repeated.FailureInfo == nil {
		t.Fatal("cached failed response lost capsule")
	}
	select {
	case id := <-notified:
		if id != engine {
			t.Fatal("wrong engine notified")
		}
	case <-time.After(time.Second):
		t.Fatal("cancel suppressed failure notification")
	}
	retained := e.RetainedFailure(engine)
	if retained == nil || retained.ProducerID != engine {
		t.Fatal("dead engine cannot re-envelope retained evidence")
	}
	raw, _ := json.Marshal(Hello{Version: 1, RoomID: "ROOM", Token: strings.Repeat("a", 64), HelperID: strings.Repeat("b", 64), RuntimeID: RuntimeID, EngineID: engine, Alive: false, FailureInfo: retained})
	if len(raw) > MaxHelloBytes || strings.Contains(string(raw), "private card exception") {
		t.Fatal("hello exceeded bound or leaked raw error")
	}
	if e.RetainedFailure(NewID()) != nil {
		t.Fatal("old evidence attached to replacement engine")
	}
}

func TestDeadHelloEvidenceArrivesBeforeInvalidationAndWrongHelperCannotAttach(t *testing.T) {
	for _, wrong := range []bool{false, true} {
		t.Run(map[bool]string{false: "authenticated", true: "wrong_helper"}[wrong], func(t *testing.T) {
			link := NewLink("ROOM", time.Second)
			engine := NewID()
			runtime := &Runtime{link: link, engineID: engine, done: make(chan struct{})}
			link.active = runtime
			link.helperID = "trusted"
			hello := Hello{EngineID: engine, HelperID: "trusted", Alive: false, FailureInfo: &forgediag.FailureInfo{ProducerID: engine, Boundary: &forgediag.Boundary{Code: "native_failure"}, Native: (&diagnosticRuntime{}).FailureInfo().Native}}
			if wrong {
				hello.HelperID = "unrelated"
			}
			if link.Serve(t.Context(), nil, hello) == nil {
				t.Fatal("dead or unrelated hello accepted execution")
			}
			if (runtime.FailureInfo().Native != nil) == wrong {
				t.Fatal("diagnostic authentication/invalidation ordering failed")
			}
			if wrong && !runtime.Healthy() {
				t.Fatal("wrong helper invalidated current engine")
			}
			link.Close()
		})
	}
}

func TestDirectPeerFailureUsesSameRetainedCapsule(t *testing.T) {
	e, engine, notified := newDiagnosticExecutor(t)
	binding := PeerContext{BindingID: NewID(), GameID: "game", EngineID: engine, PlayerIndex: 0, PublicPromptID: 91, NativePromptID: 1, Revision: 1}
	e.SetPeerContext(&binding)
	action := PeerAction{BindingID: binding.BindingID, OperationID: "decision", Request: protocol.RulesRespond{PromptID: 91, ResponseID: "$pass", PeerBinding: binding.BindingID}}
	commit, reply := e.ExecutePeer(t.Context(), action)
	if commit != nil || reply == nil || reply.Error != "relay" {
		t.Fatal("failed peer action returned speculative result")
	}
	if info := e.RetainedFailure(engine); info == nil || info.Native == nil {
		t.Fatal("generic peer reply erased failure evidence")
	}
	select {
	case <-notified:
	case <-time.After(time.Second):
		t.Fatal("peer failure was not notified")
	}
}

func TestLargestCapsuleFitsDedicatedHelloBudget(t *testing.T) {
	capsule := (&diagnosticRuntime{}).FailureInfo().Native
	for i := 0; i < 32; i++ {
		capsule.Causes[0].Frames = append(capsule.Causes[0].Frames, forgediag.Frame{ClassName: "org.hexproof.forge.NativeSession", MethodName: "fail", Line: 549})
	}
	for i := 0; i < 8; i++ {
		capsule.Spans = append(capsule.Spans, forgediag.Span{ID: uint64(i + 1), Stage: "effect", API: "Draw", Source: &forgediag.Source{ObjectID: strings.Repeat("a", 128), Incarnation: strings.Repeat("b", 128), ObservationSequence: 1, Zone: "stack", Disclosure: "public_zone", Card: &forgediag.CardReference{Name: "Lightning Bolt"}}})
	}
	for i := 0; i < 128; i++ {
		capsule.Events = append(capsule.Events, forgediag.Event{Sequence: uint64(i + 1), Kind: "effect_enter", SpanID: 1, Stage: "effect", API: "Draw"})
		raw, _ := json.Marshal(capsule)
		if len(raw) > forgediag.MaxCapsuleBytes {
			capsule.Events = capsule.Events[:len(capsule.Events)-1]
			break
		}
	}
	clean := forgediag.SanitizeCapsule(capsule)
	if clean == nil {
		t.Fatal("bounded native capsule rejected")
	}
	info := forgediag.FailureInfo{ProducerID: NewID(), Native: clean, Boundary: &forgediag.Boundary{Code: "native_failure", RequestFamily: "submitAction", Dispatched: true}}
	raw, _ := json.Marshal(Hello{Version: Version, RoomID: strings.Repeat("r", 128), Token: NewID(), HelperID: NewID(), RuntimeID: RuntimeID, EngineID: NewID(), Alive: false, FailureInfo: &info})
	if len(raw) <= 4096 || len(raw) > MaxHelloBytes {
		t.Fatalf("extended hello budget does not cover capsule: %d", len(raw))
	}
}
