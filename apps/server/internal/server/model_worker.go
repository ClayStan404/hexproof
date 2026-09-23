// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package server

import (
	"context"
	"crypto/subtle"
	"encoding/json"
	"net/http"
	"time"

	"github.com/coder/websocket"
	"hexproof/server/internal/forgehost"
	"hexproof/server/internal/protocol"
	"hexproof/server/internal/room"
)

// modelMu is a leaf lock. Room operations capture state before taking it; no
// path acquires opMu while holding modelMu or waits for provider inference.
type modelWorker struct {
	token       string
	connection  *Session
	pending     *modelRequest
	state, code string
}

type modelRequest struct {
	id                             string
	game                           forgeRoomGame
	player                         int
	enginePromptID, publicPromptID int64
	timer                          *time.Timer
	rejections                     int
}

func (h *Handler) grantModelWorker(sess *Session, r *room.Room) {
	if !protocol.IsModelAISource(r.AISource) || !r.IsHost(sess.ConnectionID) {
		return
	}
	h.revokeModelWorker(r.ID)
	token := forgehost.NewID()
	h.modelMu.Lock()
	h.modelWorkers[r.ID] = &modelWorker{token: token, state: "waiting"}
	h.modelMu.Unlock()
	envelope, _ := protocol.NewEnvelope(protocol.TypeRoomAIWorker, protocol.RoomAIWorker{RoomID: r.ID, Source: r.AISource, Token: token})
	h.send(sess, envelope)
	h.publishModelStatus(r)
}

func (h *Handler) revokeModelWorker(roomID string) {
	h.modelMu.Lock()
	worker := h.modelWorkers[roomID]
	var pending *modelRequest
	var connection *Session
	if worker != nil {
		pending, connection = worker.pending, worker.connection
		worker.pending, worker.connection = nil, nil
	}
	delete(h.modelWorkers, roomID)
	h.modelMu.Unlock()
	if pending != nil && pending.timer != nil {
		pending.timer.Stop()
	}
	if connection != nil {
		connection.Close()
	}
}

func (h *Handler) closeModelWorkers() {
	h.modelMu.Lock()
	var timers []*time.Timer
	var connections []*Session
	for _, worker := range h.modelWorkers {
		if worker.pending != nil && worker.pending.timer != nil {
			timers = append(timers, worker.pending.timer)
		}
		if worker.connection != nil {
			connections = append(connections, worker.connection)
		}
		worker.pending, worker.connection = nil, nil
	}
	h.modelWorkers = make(map[string]*modelWorker)
	h.modelMu.Unlock()
	for _, timer := range timers {
		timer.Stop()
	}
	for _, connection := range connections {
		connection.Close()
	}
}

// Caller holds the room operation lock. Closing the human connection revokes
// the worker connection too; resuming the human session issues a new token.
func (h *Handler) pauseModelWorker(roomID, code string, disconnect bool) {
	h.modelMu.Lock()
	worker := h.modelWorkers[roomID]
	if worker == nil {
		h.modelMu.Unlock()
		return
	}
	pending, connection := worker.pending, worker.connection
	worker.pending = nil
	worker.state, worker.code = "waiting", code
	if code != "" {
		worker.state = "paused"
	}
	if disconnect {
		worker.connection = nil
		worker.token = ""
	}
	h.modelMu.Unlock()
	if pending != nil {
		if pending.timer != nil {
			pending.timer.Stop()
		}
		if connection != nil {
			h.sendModel(connection, protocol.TypeAICancel, protocol.AICancel{RequestID: pending.id})
		}
	}
	if disconnect && connection != nil {
		connection.Close()
	}
	if r := h.hub.FindRoom(roomID); r != nil {
		h.publishModelStatus(r)
	}
}

func (h *Handler) publishModelStatus(r *room.Room) {
	h.modelMu.Lock()
	worker := h.modelWorkers[r.ID]
	if worker == nil {
		h.modelMu.Unlock()
		return
	}
	status := protocol.RoomAIStatus{RoomID: r.ID, State: worker.state, Code: worker.code}
	h.modelMu.Unlock()
	envelope, _ := protocol.NewEnvelope(protocol.TypeRoomAIStatus, status)
	h.fanout(r, []protocol.Envelope{envelope})
}

func (h *Handler) sendModel(sess *Session, kind string, payload any) {
	envelope, err := protocol.NewEnvelope(kind, payload)
	if err != nil {
		sess.Close()
		return
	}
	raw, err := envelope.Marshal()
	if err != nil || len(raw) > 4<<20 {
		sess.Close()
		return
	}
	sess.trySend(raw)
}

func (h *Handler) serveModelWorker(w http.ResponseWriter, request *http.Request) {
	conn, err := websocket.Accept(w, request, &websocket.AcceptOptions{CompressionMode: websocket.CompressionDisabled})
	if err != nil {
		return
	}
	defer conn.CloseNow()
	conn.SetReadLimit(4096)
	helloCtx, cancel := context.WithTimeout(request.Context(), h.config.HelloTimeout)
	_, raw, err := conn.Read(helloCtx)
	cancel()
	env, parseErr := protocol.ParseEnvelope(raw)
	var attach protocol.AIAttach
	if err != nil || parseErr != nil || env.Type != protocol.TypeAIAttach || env.DecodePayload(&attach) != nil || len(attach.RoomID) != 6 || len(attach.Token) != 64 {
		return
	}
	operation, err := h.hub.lockRoomOperation(attach.RoomID)
	if err != nil {
		return
	}
	r := operation.room
	ctx, stop := context.WithCancel(request.Context())
	defer stop()
	sess := &Session{Send: make(chan []byte, 8), cancel: stop}
	h.modelMu.Lock()
	worker := h.modelWorkers[r.ID]
	valid := worker != nil && protocol.IsModelAISource(r.AISource) && !r.Disbanded && subtle.ConstantTimeCompare([]byte(worker.token), []byte(attach.Token)) == 1
	var previous *Session
	if valid {
		previous = worker.connection
		if worker.pending != nil && worker.pending.timer != nil {
			worker.pending.timer.Stop()
		}
		worker.connection, worker.pending, worker.state, worker.code = sess, nil, "waiting", ""
	}
	h.modelMu.Unlock()
	if !valid {
		operation.opMu.Unlock()
		return
	}
	if previous != nil {
		previous.Close()
	}
	conn.SetReadLimit(1 << 20)
	go h.writePump(ctx, conn, sess)
	go websocketHeartbeat(ctx, conn)
	h.sendModel(sess, protocol.TypeAIAttached, protocol.AIAttached{RoomID: r.ID})
	h.refreshModelDecision(r)
	h.publishModelStatus(r)
	operation.opMu.Unlock()
	defer func() {
		sess.Close()
		operation, err := h.hub.lockRoomOperation(r.ID)
		if err != nil {
			return
		}
		defer operation.opMu.Unlock()
		h.modelMu.Lock()
		current := h.modelWorkers[r.ID]
		same := current != nil && current.connection == sess
		if same {
			current.connection = nil
		}
		h.modelMu.Unlock()
		if same {
			h.pauseModelWorker(r.ID, "worker_disconnected", false)
		}
	}()
	for {
		_, raw, err := conn.Read(ctx)
		if err != nil {
			return
		}
		if !sess.allowMessage(time.Now(), h.config.MessagesPerSecond) {
			return
		}
		env, err := protocol.ParseEnvelope(raw)
		if err != nil {
			return
		}
		switch env.Type {
		case protocol.TypeAIAnswer:
			var answer protocol.AIAnswer
			if json.Unmarshal(env.Payload, &answer) != nil {
				return
			}
			h.handleModelAnswer(r.ID, sess, answer)
		case protocol.TypeAIFailure:
			var failure protocol.AIFailure
			if json.Unmarshal(env.Payload, &failure) != nil {
				return
			}
			h.handleModelFailure(r.ID, sess, failure)
		default:
			return
		}
	}
}
