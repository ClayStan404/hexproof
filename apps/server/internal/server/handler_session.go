// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package server

import (
	"context"
	"errors"
	"fmt"
	"github.com/coder/websocket"
	"hexproof/server/internal/buildinfo"
	"hexproof/server/internal/protocol"
	"hexproof/server/internal/room"
	"log"
	"net/http"
	"strings"
	"sync/atomic"
	"time"
	"unicode"
	"unicode/utf8"
)

type resumeHold struct {
	token           string
	oldConnectionID string
	displayName     string
	room            *room.Room
	expiresAt       time.Time
}

var errSessionHelloTimeout = errors.New("session.hello timeout")

// ServeHTTP upgrades to WebSocket and runs the connection lifecycle.
func (h *Handler) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	if h.config.MaxConnections > 0 &&
		atomic.AddInt64(&h.activeConnections, 1) > h.config.MaxConnections {
		atomic.AddInt64(&h.activeConnections, -1)
		http.Error(w, "maximum connections reached", http.StatusServiceUnavailable)
		return
	}
	defer atomic.AddInt64(&h.activeConnections, -1)

	conn, err := websocket.Accept(w, r, &websocket.AcceptOptions{
		// Native clients do not require browser-origin authorization. Compression
		// stays disabled to keep bounded public-hub memory use predictable.
		CompressionMode: websocket.CompressionDisabled,
	})
	if err != nil {
		log.Printf("ws accept: %v", err)
		return
	}
	conn.SetReadLimit(h.config.MaxMessageBytes)

	ctx, cancel := context.WithCancel(r.Context())
	defer cancel()
	sess := &Session{
		ConnectionID: fmt.Sprintf("conn-%d", atomic.AddUint64(&h.connSeq, 1)),
		RemoteIP:     clientIP(r, h.trustedProxies),
		Send:         make(chan []byte, 64),
		cancel:       cancel,
	}
	h.registerSession(sess)
	defer h.unregisterSession(sess)

	// writePump drains sess.Send onto the WebSocket; readLoop reads inbound.
	go h.writePump(ctx, conn, sess)
	go websocketHeartbeat(ctx, conn)

	readErr := h.readLoop(ctx, conn, sess)
	if readErr != nil && shouldLogSessionEnd(readErr) {
		log.Printf("session %s ended: %v", sess.ConnectionID, readErr)
	}
	// Explicit room.leave has already cleared the room binding. Any remaining
	// membership is a transport drop and receives the bounded reconnect hold.
	if currentRoom := sess.Room(); currentRoom != nil {
		h.holdForReconnect(sess, currentRoom)
	}
	sess.Close()
	if !errors.Is(readErr, errSessionHelloTimeout) {
		_ = conn.Close(websocket.StatusNormalClosure, "")
	}
}

func websocketHeartbeat(ctx context.Context, conn *websocket.Conn) {
	ticker := time.NewTicker(websocketPingEvery)
	defer ticker.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			pingCtx, cancel := context.WithTimeout(ctx, websocketPingWait)
			err := conn.Ping(pingCtx)
			cancel()
			if err != nil {
				_ = conn.CloseNow()
				return
			}
		}
	}
}

// writePump drains the session's Send channel onto the WebSocket.
func (h *Handler) writePump(ctx context.Context, conn *websocket.Conn, sess *Session) {
	for {
		select {
		case <-ctx.Done():
			return
		case data, ok := <-sess.Send:
			if !ok {
				return
			}
			writeCtx, cancel := context.WithTimeout(ctx, websocketWriteWait)
			err := conn.Write(writeCtx, websocket.MessageText, data)
			cancel()
			if err != nil {
				log.Printf("write %s: %v", sess.ConnectionID, err)
				_ = conn.CloseNow()
				return
			}
		}
	}
}

func shouldLogSessionEnd(err error) bool {
	if err == nil || errors.Is(err, context.Canceled) {
		return false
	}
	switch websocket.CloseStatus(err) {
	case websocket.StatusNormalClosure, websocket.StatusGoingAway:
		return false
	default:
		return true
	}
}

func (h *Handler) handleHello(sess *Session, env protocol.Envelope) error {
	if sess.DisplayName != "" {
		h.sendError(sess, env.ID, protocol.ErrInvalidMessage, "session already welcomed")
		return nil
	}
	var hello protocol.SessionHello
	if err := env.DecodePayload(&hello); err != nil {
		h.sendError(sess, env.ID, protocol.ErrInvalidMessage, err.Error())
		return nil
	}
	displayName := strings.TrimSpace(hello.DisplayName)
	if displayName == "" {
		h.sendError(sess, env.ID, protocol.ErrNameRequired, "displayName required")
		return nil
	}
	if utf8.RuneCountInString(displayName) > protocol.MaxDisplayNameRunes ||
		hasControlCharacters(displayName) {
		h.sendError(sess, env.ID, protocol.ErrInvalidMessage, "invalid displayName")
		return nil
	}
	if hello.Protocol != "" && hello.Protocol != protocol.ProtocolVersion {
		h.sendError(sess, env.ID, protocol.ErrInvalidMessage, "unsupported protocol: "+hello.Protocol)
		return nil
	}
	clientVersion := strings.TrimSpace(hello.ClientVersion)
	if clientVersion != buildinfo.Version {
		h.sendVersionMismatch(sess, env.ID, clientVersion)
		return nil
	}
	if len(hello.ResumeToken) > protocol.MaxResumeTokenBytes || hello.LastSeq < 0 {
		h.sendError(sess, env.ID, protocol.ErrInvalidMessage, "invalid resume metadata")
		return nil
	}
	resumeToken, err := genResumeToken()
	if err != nil {
		h.sendError(sess, env.ID, protocol.ErrInternal,
			"resume credential unavailable")
		return nil
	}
	if hello.ResumeToken != "" {
		if hold, ok := h.takeResumeHold(hello.ResumeToken, time.Now().UTC()); ok {
			operation, err := h.hub.lockRoomOperation(hold.room.ID)
			if err == nil {
				info, envelopes, resumeErr := h.hub.ResumeRoom(
					hold.oldConnectionID, sess, hold.room)
				if resumeErr == nil {
					sess.DisplayName = hold.displayName
					sess.ResumeToken = resumeToken
					welcome := protocol.SessionWelcome{
						V:             protocol.ProtocolVersion,
						ConnectionID:  sess.ConnectionID,
						ServerVersion: buildinfo.Version,
						ResumeToken:   sess.ResumeToken,
						Resumed:       true,
						RoomID:        hold.room.ID,
						Role:          info.Role,
						Seat:          info.Seat,
						Host:          info.Host,
					}
					welcomeEnvelope, _ := protocol.NewEnvelope(
						protocol.TypeSessionWelcome, welcome)
					welcomeEnvelope.ID = env.ID
					h.send(sess, welcomeEnvelope)
					h.fanoutTo([]*Session{sess}, envelopes)
					operation.opMu.Unlock()
					return nil
				}
				operation.mu.Lock()
				retryable := operation.room == hold.room &&
					!hold.room.Disbanded &&
					hold.room.Member(hold.oldConnectionID)
				operation.mu.Unlock()
				expiredHoldRestored := false
				if retryable {
					expiredHoldRestored = h.restoreResumeHold(hold, time.Now().UTC())
				}
				operation.opMu.Unlock()
				if expiredHoldRestored {
					h.expireResumeHold(hold)
				}
			}
		}
	}
	sess.DisplayName = displayName
	sess.ResumeToken = resumeToken
	welcome := protocol.SessionWelcome{
		V:             protocol.ProtocolVersion,
		ConnectionID:  sess.ConnectionID,
		ServerVersion: buildinfo.Version,
		ResumeToken:   sess.ResumeToken,
	}
	wEnv, _ := protocol.NewEnvelope(protocol.TypeSessionWelcome, welcome)
	wEnv.ID = env.ID
	h.send(sess, wEnv)
	return nil
}

func hasControlCharacters(value string) bool {
	for _, char := range value {
		if unicode.IsControl(char) {
			return true
		}
	}
	return false
}

func (h *Handler) holdForReconnect(sess *Session, r *room.Room) {
	if sess.ResumeToken == "" {
		return
	}
	operation, err := h.hub.lockRoomOperation(r.ID)
	if err != nil {
		sess.setRoom(nil)
		return
	}
	defer operation.opMu.Unlock()
	operation.mu.Lock()
	stillMember := operation.room == r && !r.Disbanded &&
		r.Member(sess.ConnectionID)
	operation.mu.Unlock()
	if !stillMember {
		sess.setRoom(nil)
		return
	}
	expiresAt := time.Now().UTC().Add(h.config.ReconnectWindow)
	hold := resumeHold{
		token:           sess.ResumeToken,
		oldConnectionID: sess.ConnectionID,
		displayName:     sess.DisplayName,
		room:            r,
		expiresAt:       expiresAt,
	}
	sess.setRoom(nil)
	h.resumeMu.Lock()
	h.resumeHolds[hold.token] = hold
	h.resumeMu.Unlock()
	time.AfterFunc(time.Until(expiresAt), func() {
		h.expireResumeHold(hold)
	})
}

func (h *Handler) takeResumeHold(token string, now time.Time) (resumeHold, bool) {
	h.resumeMu.Lock()
	hold, ok := h.resumeHolds[token]
	if !ok {
		h.resumeMu.Unlock()
		return resumeHold{}, false
	}
	if !now.Before(hold.expiresAt) {
		h.resumeMu.Unlock()
		h.expireResumeHold(hold)
		return resumeHold{}, false
	}
	delete(h.resumeHolds, token)
	h.resumeMu.Unlock()
	return hold, true
}

// restoreResumeHold returns true when the restored hold is already expired.
// The caller must invoke expireResumeHold only after releasing any room opMu.
func (h *Handler) restoreResumeHold(hold resumeHold, now time.Time) bool {
	if hold.token == "" {
		return false
	}
	h.resumeMu.Lock()
	defer h.resumeMu.Unlock()
	if _, exists := h.resumeHolds[hold.token]; exists {
		return false
	}
	h.resumeHolds[hold.token] = hold
	return !now.Before(hold.expiresAt)
}

func (h *Handler) expireResumeHold(expected resumeHold) {
	h.resumeMu.Lock()
	current, ok := h.resumeHolds[expected.token]
	if !ok || current.oldConnectionID != expected.oldConnectionID ||
		current.expiresAt != expected.expiresAt {
		h.resumeMu.Unlock()
		return
	}
	delete(h.resumeHolds, expected.token)
	h.resumeMu.Unlock()

	operation, err := h.hub.lockRoomOperation(expected.room.ID)
	if err != nil {
		return
	}
	var retained *retainedRoom
	var cleanup pairingRoomCleanup
	defer func() {
		operation.opMu.Unlock()
		h.commitPairingRoomCleanup(cleanup)
		h.saveRoomRetention(retained)
	}()
	result, empty, err := h.hub.ExpireDisconnected(
		expected.oldConnectionID, expected.room)
	if err != nil {
		return
	}
	if !empty {
		h.fanout(expected.room, result.Broadcast)
		if result.ProjectGame {
			h.fanoutGameProjections(expected.room)
		}
		return
	}
	retained = h.snapshotRoomRetention(expected.room)
	cleanup = h.removeRoom(expected.room)
}

// sessionByConn looks up a live session by connection id.
func (h *Handler) sessionByConn(connID string) *Session {
	h.sessionsMu.RLock()
	defer h.sessionsMu.RUnlock()
	return h.sessions[connID]
}

// send marshals and queues an envelope to one session (race-safe).
func (h *Handler) send(sess *Session, env protocol.Envelope) {
	data, err := h.sessionEnvelopeBytes(env)
	if err != nil {
		log.Printf("send: marshal %s for %s failed: %v",
			env.Type, sess.ConnectionID, err)
		if env.Type != protocol.TypeError {
			h.failClosedSession(sess, err)
			return
		}
		sess.Close()
		return
	}
	if !sess.trySend(data) {
		log.Printf("fail-closed session %s: send buffer full or already closed",
			sess.ConnectionID)
	}
}

func (h *Handler) sessionEnvelopeBytes(env protocol.Envelope) ([]byte, error) {
	if h.marshalEnvelope != nil {
		return h.marshalEnvelope(env)
	}
	return env.Marshal()
}

func (h *Handler) failClosedSession(sess *Session, cause error) {
	if sess == nil {
		return
	}
	log.Printf("fail-closed session %s: %v", sess.ConnectionID, cause)
	h.sendError(sess, "", protocol.ErrInternal, "internal server error")
	sess.Close()
}

// sendError builds and queues an error envelope (echoes id when present).
func (h *Handler) sendError(sess *Session, id, code, message string) {
	if code != "" {
		message = strings.TrimPrefix(message, code+": ")
	}
	env, _ := protocol.NewEnvelope(protocol.TypeError, protocol.ErrorPayload{Code: code, Message: message})
	env.ID = id
	h.send(sess, env)
}

func (h *Handler) sendVersionMismatch(sess *Session, id, clientVersion string) {
	message := fmt.Sprintf(
		"client version %q does not match server version %q; download and install Hexproof version %s before reconnecting",
		clientVersion, buildinfo.Version, buildinfo.Version)
	if clientVersion == "" {
		message = fmt.Sprintf(
			"clientVersion required; download and install Hexproof version %s before reconnecting",
			buildinfo.Version)
	}
	env, _ := protocol.NewEnvelope(protocol.TypeError, protocol.ErrorPayload{
		Code:            protocol.ErrClientVersionMismatch,
		Message:         message,
		ClientVersion:   clientVersion,
		RequiredVersion: buildinfo.Version,
	})
	env.ID = id
	h.send(sess, env)
}

func (h *Handler) sendPong(sess *Session, id string) {
	env, _ := protocol.NewEnvelope(protocol.TypeSessionPong, map[string]any{})
	env.ID = id
	h.send(sess, env)
}

func (h *Handler) registerSession(s *Session) {
	h.sessionsMu.Lock()
	defer h.sessionsMu.Unlock()
	h.sessions[s.ConnectionID] = s
}

func (h *Handler) unregisterSession(s *Session) {
	h.sessionsMu.Lock()
	delete(h.sessions, s.ConnectionID)
	h.sessionsMu.Unlock()
	h.discardZoneDumpRequestsForConn(s.ConnectionID)
	h.discardPublicZoneMoveRequestsForConn(s.ConnectionID)
	tournamentID := s.Tournament().TournamentID
	h.disconnectTournamentSession(s)
	if tournamentID != "" {
		h.evictExpiredTournaments(time.Now().UTC())
	}
}
