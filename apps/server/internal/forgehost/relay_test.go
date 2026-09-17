// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package forgehost

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"github.com/coder/websocket"
	"hexproof/server/internal/rulesengine/forge"
)

type fixtureRuntime struct {
	forge.Runtime
	mu      sync.Mutex
	done    chan struct{}
	once    sync.Once
	gameID  string
	actions int
	entered chan struct{}
	release chan struct{}
}

func fixtureStart(_ context.Context) (forge.Runtime, error) {
	return &fixtureRuntime{done: make(chan struct{})}, nil
}
func (f *fixtureRuntime) StartGame(_ context.Context, req forge.StartGameRequest) (forge.SessionHandle, error) {
	f.gameID = req.GameID
	return forge.SessionHandle{SessionID: "session", PlayerIndexes: []int{0, 1}}, nil
}
func (f *fixtureRuntime) Prompt(context.Context, string, int) (json.RawMessage, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	return json.RawMessage(fmt.Sprintf(`{"promptId":%d,"decidingPlayerId":"player-0","input":{"type":"chooseAction","actions":[]}}`, f.actions+1)), nil
}
func (f *fixtureRuntime) Snapshot(_ context.Context, _ string, viewer int) (json.RawMessage, error) {
	view := forge.GameView{GameID: f.gameID, ActivePlayerID: "player-0", PriorityPlayerID: "player-0",
		Players: []forge.PlayerView{{ID: "player-0", Status: "playing"}, {ID: "player-1", Status: "playing"}}}
	for seat := 0; seat < 2; seat++ {
		zone := forge.ZoneView{Zone: "Hand", OwnerID: fmt.Sprintf("player-%d", seat), Count: 1}
		if viewer == seat {
			zone.Cards = []forge.CardView{{Visibility: "visible", ID: fmt.Sprintf("private-%d", seat), Identity: &forge.CardIdentityView{Name: fmt.Sprintf("Secret %d", seat)}}}
		}
		view.Zones = append(view.Zones, zone)
	}
	return json.Marshal(view)
}
func (f *fixtureRuntime) GameOver(context.Context, string) (bool, error) { return false, nil }
func (f *fixtureRuntime) SubmitAction(ctx context.Context, _ string, _ json.RawMessage) error {
	f.mu.Lock()
	f.actions++
	entered, release := f.entered, f.release
	f.mu.Unlock()
	if entered != nil {
		close(entered)
		select {
		case <-release:
		case <-ctx.Done():
			return ctx.Err()
		}
	}
	return nil
}
func (f *fixtureRuntime) Done() <-chan struct{} { return f.done }
func (f *fixtureRuntime) Healthy() bool {
	select {
	case <-f.done:
		return false
	default:
		return true
	}
}
func (f *fixtureRuntime) Invalidate()  { f.once.Do(func() { close(f.done) }) }
func (f *fixtureRuntime) Close() error { f.Invalidate(); return nil }

func TestExecutorDeduplicatesAndRejectsOldOrChangedOperations(t *testing.T) {
	e := NewExecutor("ROOM", fixtureStart, nil)
	defer e.Cancel("")
	engineID := NewID()
	start := Request{RoomID: "ROOM", EngineID: engineID, ID: 1, Command: "start", Start: &forge.StartGameRequest{GameID: "game", Variant: "Constructed", Players: make([]forge.PlayerConfig, 2)}}
	first := e.Execute(t.Context(), start)
	if first.Error != "" || first.Publication == nil {
		t.Fatalf("start: %+v", first)
	}
	action := Request{RoomID: "ROOM", EngineID: engineID, ID: 2, Command: "action", Action: json.RawMessage(`{"pass":true}`)}
	response := e.Execute(t.Context(), action)
	if response.Error != "" {
		t.Fatal(response.Error)
	}
	repeated := e.Execute(t.Context(), action)
	if repeated.Publication.Revision != response.Publication.Revision {
		t.Fatal("duplicate changed publication")
	}
	f := e.runtime.(*fixtureRuntime)
	if f.actions != 1 {
		t.Fatalf("action executed %d times", f.actions)
	}
	altered := action
	altered.Action = json.RawMessage(`{"pass":false}`)
	if e.Execute(t.Context(), altered).Error == "" {
		t.Fatal("accepted changed duplicate")
	}
	if e.Execute(t.Context(), start).Error == "" {
		t.Fatal("replayed expired start")
	}
	wrong := action
	wrong.ID = 3
	wrong.RoomID = "OTHER"
	if e.Execute(t.Context(), wrong).Error == "" {
		t.Fatal("accepted cross-room request")
	}
	wrong = action
	wrong.ID = 3
	wrong.EngineID = NewID()
	if e.Execute(t.Context(), wrong).Error == "" {
		t.Fatal("accepted cross-game action")
	}
	if f.actions != 1 {
		t.Fatal("invalid request mutated engine")
	}
}

func newRelayFixture(t *testing.T, start StartRuntime) (*Link, context.Context) {
	t.Helper()
	return newRelayFixtureWithTimeout(t, start, 15*time.Second)
}

func newRelayFixtureWithTimeout(t *testing.T, start StartRuntime, timeout time.Duration) (*Link, context.Context) {
	t.Helper()
	ctx, cancel := context.WithTimeout(t.Context(), timeout)
	link := NewLink("ROOM", 3*time.Second)
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		conn, err := websocket.Accept(w, r, nil)
		if err != nil {
			return
		}
		defer conn.CloseNow()
		conn.SetReadLimit(MaxFrameBytes)
		_, data, err := conn.Read(r.Context())
		if err != nil {
			return
		}
		var hello Hello
		if json.Unmarshal(data, &hello) != nil || hello.Token != link.Token {
			return
		}
		_ = link.Serve(r.Context(), conn, hello)
	}))
	finished := make(chan error, 1)
	go func() {
		finished <- Run(ctx, WorkerConfig{ServerURL: "ws" + strings.TrimPrefix(srv.URL, "http"), RoomID: "ROOM", Token: link.Token, GraceSeconds: 3}, start, nil)
	}()
	t.Cleanup(func() {
		cancel()
		link.Close()
		srv.Close()
		select {
		case <-finished:
		case <-time.After(3 * time.Second):
			t.Error("worker did not stop")
		}
	})
	waitUntil(t, func() bool { return link.Ready() })
	return link, ctx
}

func waitUntil(t *testing.T, check func() bool) {
	t.Helper()
	deadline := time.After(5 * time.Second)
	tick := time.NewTicker(time.Millisecond)
	defer tick.Stop()
	for !check() {
		select {
		case <-deadline:
			t.Fatal("condition timed out")
		case <-tick.C:
		}
	}
}

func TestRelayRecoversLostActionReplyWithoutExecutingTwice(t *testing.T) {
	f := &fixtureRuntime{done: make(chan struct{}), entered: make(chan struct{}), release: make(chan struct{})}
	link, ctx := newRelayFixture(t, func(context.Context) (forge.Runtime, error) { return f, nil })
	r, err := link.NewRuntime()
	if err != nil {
		t.Fatal(err)
	}
	handle, err := r.StartGame(ctx, forge.StartGameRequest{GameID: "game", Variant: "Constructed", Players: make([]forge.PlayerConfig, 2)})
	if err != nil {
		t.Fatal(err)
	}
	for viewer := -1; viewer < 2; viewer++ {
		view, err := r.Snapshot(ctx, handle.SessionID, viewer)
		if err != nil {
			t.Fatal(err)
		}
		if viewer != 0 && strings.Contains(string(view), "Secret 0") {
			t.Fatal("owner-zero hand leaked")
		}
		if viewer != 1 && strings.Contains(string(view), "Secret 1") {
			t.Fatal("owner-one hand leaked")
		}
	}
	completed := make(chan error, 1)
	go func() { completed <- r.SubmitAction(ctx, handle.SessionID, json.RawMessage(`{"pass":true}`)) }()
	select {
	case <-f.entered:
	case <-ctx.Done():
		t.Fatal(ctx.Err())
	}
	link.mu.Lock()
	conn := link.conn
	link.mu.Unlock()
	_ = conn.CloseNow()
	waitUntil(t, func() bool { return !link.Ready() })
	close(f.release)
	select {
	case err := <-completed:
		if err != nil {
			t.Fatal(err)
		}
	case <-ctx.Done():
		t.Fatal(ctx.Err())
	}
	f.mu.Lock()
	actions := f.actions
	f.mu.Unlock()
	if actions != 1 {
		t.Fatalf("executed action %d times", actions)
	}
	if !r.Healthy() {
		t.Fatal("recoverable transport loss destroyed engine")
	}
	if err := r.EndGame(ctx, handle.SessionID); err != nil {
		t.Fatal(err)
	}
}

func TestRelayFreshGameAndIdleCrash(t *testing.T) {
	var starts atomic.Int32
	var activeMu sync.Mutex
	var active *fixtureRuntime
	link, ctx := newRelayFixture(t, func(context.Context) (forge.Runtime, error) {
		f := &fixtureRuntime{done: make(chan struct{})}
		activeMu.Lock()
		active = f
		activeMu.Unlock()
		starts.Add(1)
		return f, nil
	})
	for round := 0; round < 2; round++ {
		r, err := link.NewRuntime()
		if err != nil {
			t.Fatal(err)
		}
		handle, err := r.StartGame(ctx, forge.StartGameRequest{GameID: fmt.Sprintf("game-%d", round), Variant: "Constructed", Players: make([]forge.PlayerConfig, 2)})
		if err != nil {
			t.Fatal(err)
		}
		if round == 0 {
			if err := r.AbortGame(ctx, handle.SessionID); err != nil {
				t.Fatal(err)
			}
		} else {
			activeMu.Lock()
			f := active
			activeMu.Unlock()
			f.Invalidate()
			select {
			case <-r.Done():
			case <-ctx.Done():
				t.Fatal("idle crash not delivered")
			}
		}
	}
	if starts.Load() != 2 {
		t.Fatal("a game reused the previous JVM")
	}
}

func TestTerminalPublicationPreservesEmptyPromptAcrossJSON(t *testing.T) {
	raw, err := json.Marshal(Publication{GameOver: true, Handle: forge.SessionHandle{SessionID: "finished"}})
	if err != nil {
		t.Fatal(err)
	}
	var p Publication
	if err := json.Unmarshal(raw, &p); err != nil {
		t.Fatal(err)
	}
	r := &Runtime{done: make(chan struct{}), publication: &p}
	prompt, err := r.Prompt(t.Context(), "finished", 0)
	if err != nil || len(prompt) != 0 {
		t.Fatalf("terminal decision is not empty: %q %v", prompt, err)
	}
}

func TestExecutorCancellationReapsLateStartupAndFencesOldEngine(t *testing.T) {
	entered, release := make(chan struct{}), make(chan struct{})
	f := &fixtureRuntime{done: make(chan struct{})}
	e := NewExecutor("ROOM", func(context.Context) (forge.Runtime, error) { close(entered); <-release; return f, nil }, nil)
	defer e.Cancel("")
	id := NewID()
	finished := make(chan Response, 1)
	go func() {
		finished <- e.Execute(t.Context(), Request{RoomID: "ROOM", EngineID: id, ID: 1, Command: "start", Start: &forge.StartGameRequest{GameID: "one", Variant: "Constructed", Players: make([]forge.PlayerConfig, 2)}})
	}()
	<-entered
	e.Cancel(id)
	close(release)
	if response := <-finished; response.Error == "" {
		t.Fatal("cancelled startup succeeded")
	}
	if f.Healthy() {
		t.Fatal("late startup leaked a runtime")
	}
	e.start = fixtureStart
	newID := NewID()
	response := e.Execute(t.Context(), Request{RoomID: "ROOM", EngineID: newID, ID: 2, Command: "start", Start: &forge.StartGameRequest{GameID: "two", Variant: "Constructed", Players: make([]forge.PlayerConfig, 2)}})
	if response.Error != "" {
		t.Fatal(response.Error)
	}
	e.Cancel(id)
	if engine, alive := e.State(); engine != newID || !alive {
		t.Fatal("stale cancellation killed the new game")
	}
}

func TestRelayOfflineInputPausesThenExpiresWithoutInventingResult(t *testing.T) {
	f := &fixtureRuntime{done: make(chan struct{})}
	link, ctx := newRelayFixture(t, func(context.Context) (forge.Runtime, error) { return f, nil })
	link.mu.Lock()
	link.Grace = 100 * time.Millisecond
	link.mu.Unlock()
	r, err := link.NewRuntime()
	if err != nil {
		t.Fatal(err)
	}
	handle, err := r.StartGame(ctx, forge.StartGameRequest{GameID: "game", Variant: "Constructed", Players: make([]forge.PlayerConfig, 2)})
	if err != nil {
		t.Fatal(err)
	}
	link.mu.Lock()
	conn, sequence := link.conn, link.sequence
	link.mu.Unlock()
	conn.CloseNow()
	waitUntil(t, func() bool { return !link.Ready() })
	err = r.SubmitAction(ctx, handle.SessionID, json.RawMessage(`{"pass":true}`))
	if !errors.Is(err, ErrPaused) || !r.Healthy() {
		t.Fatalf("offline input destroyed resumable game: %v", err)
	}
	link.mu.Lock()
	unchanged := link.sequence == sequence && link.pending == nil
	link.mu.Unlock()
	if !unchanged || f.actions != 0 {
		t.Fatal("offline input was queued or executed")
	}
	waitUntil(t, func() bool { return !r.Healthy() })
	if _, err := r.GameOver(ctx, handle.SessionID); err == nil {
		t.Fatal("expired engine retained a fabricated outcome")
	}
	// The helper still has its JVM while offline; on reattach the remembered
	// cancellation closes it instead of attaching it to a replacement game.
	waitUntil(t, func() bool { return !f.Healthy() })
}

func TestReplacedConnectionCannotPublishOldEpoch(t *testing.T) {
	link := NewLink("ROOM", 100*time.Millisecond)
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		conn, err := websocket.Accept(w, r, nil)
		if err != nil {
			return
		}
		defer conn.CloseNow()
		_, raw, err := conn.Read(r.Context())
		if err != nil {
			return
		}
		var hello Hello
		if json.Unmarshal(raw, &hello) != nil {
			return
		}
		_ = link.Serve(r.Context(), conn, hello)
	}))
	defer srv.Close()
	defer link.Close()
	ctx, cancel := context.WithTimeout(t.Context(), 5*time.Second)
	defer cancel()
	helper := NewID()
	dial := func() (*websocket.Conn, uint64) {
		conn, _, err := websocket.Dial(ctx, "ws"+strings.TrimPrefix(srv.URL, "http"), nil)
		if err != nil {
			t.Fatal(err)
		}
		raw, _ := json.Marshal(Hello{HelperID: helper})
		if err := conn.Write(ctx, websocket.MessageText, raw); err != nil {
			t.Fatal(err)
		}
		_, raw, err = conn.Read(ctx)
		if err != nil {
			t.Fatal(err)
		}
		var bound Frame
		if json.Unmarshal(raw, &bound) != nil || bound.Type != "bound" {
			t.Fatal("missing bind")
		}
		return conn, bound.Epoch
	}
	old, oldEpoch := dial()
	defer old.CloseNow()
	current, newEpoch := dial()
	defer current.CloseNow()
	if newEpoch <= oldEpoch {
		t.Fatal("replacement reused epoch")
	}
	waitUntil(t, link.Ready)
	engine, err := link.NewRuntime()
	if err != nil {
		t.Fatal(err)
	}
	finished := make(chan error, 1)
	go func() {
		_, err := engine.StartGame(ctx, forge.StartGameRequest{GameID: "game", Variant: "Constructed", Players: make([]forge.PlayerConfig, 2)})
		finished <- err
	}()
	_, raw, err := current.Read(ctx)
	if err != nil {
		t.Fatal(err)
	}
	var request Frame
	if json.Unmarshal(raw, &request) != nil || request.Request == nil {
		t.Fatal("no operation")
	}
	executor := NewExecutor("ROOM", fixtureStart, nil)
	defer executor.Cancel("")
	response := executor.Execute(ctx, *request.Request)
	if err := writeFrame(ctx, current, Frame{Type: "response", Epoch: oldEpoch, Response: &response}); err != nil {
		t.Fatal(err)
	}
	if err := <-finished; err == nil {
		t.Fatal("old epoch committed a result")
	}
	if engine.Healthy() {
		t.Fatal("unknown outcome survived grace expiry")
	}
}
