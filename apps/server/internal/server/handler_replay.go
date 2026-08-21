// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package server

import (
	"errors"
	"hexproof/server/internal/protocol"
	"os"
	"time"
)

func (h *Handler) handleReplayList(sess *Session,
	env protocol.Envelope) error {
	if sess.DisplayName == "" {
		h.sendError(sess, env.ID, protocol.ErrNameRequired, "hello first")
		return nil
	}
	if !h.allowReplayRequest(sess.RemoteIP, time.Now().UTC()) {
		h.sendError(sess, env.ID, protocol.ErrRateLimited,
			"replay request rate limit exceeded")
		return nil
	}
	var request protocol.ReplayList
	if err := env.DecodePayload(&request); err != nil {
		h.sendError(sess, env.ID, protocol.ErrInvalidMessage, err.Error())
		return nil
	}
	if request.Offset < 0 || request.Limit < 0 {
		h.sendError(sess, env.ID, protocol.ErrInvalidMessage,
			"invalid replay page")
		return nil
	}
	limit := request.Limit
	if limit == 0 || limit > h.config.ReplayPageSize {
		limit = h.config.ReplayPageSize
	}
	replays, total, err := h.retention.list(time.Now().UTC(), request.Offset, limit)
	if err != nil {
		h.sendError(sess, env.ID, protocol.ErrInvalidMessage,
			"retained replay list unavailable")
		return nil
	}
	effectiveOffset := request.Offset
	if effectiveOffset > total {
		effectiveOffset = total
	}
	listed, _ := protocol.NewEnvelope(protocol.TypeReplayListed,
		protocol.ReplayListed{
			Replays: replays,
			Offset:  effectiveOffset,
			Limit:   limit,
			Total:   total,
			HasMore: effectiveOffset+len(replays) < total,
		})
	listed.ID = env.ID
	h.send(sess, listed)
	return nil
}

func (h *Handler) handleReplayGet(sess *Session,
	env protocol.Envelope) error {
	if sess.DisplayName == "" {
		h.sendError(sess, env.ID, protocol.ErrNameRequired, "hello first")
		return nil
	}
	if !h.allowReplayRequest(sess.RemoteIP, time.Now().UTC()) {
		h.sendError(sess, env.ID, protocol.ErrRateLimited,
			"replay request rate limit exceeded")
		return nil
	}
	var request protocol.ReplayGet
	if err := env.DecodePayload(&request); err != nil {
		h.sendError(sess, env.ID, protocol.ErrInvalidMessage, err.Error())
		return nil
	}
	replay, err := h.retention.load(request.ReplayID, time.Now().UTC())
	if err != nil {
		if errors.Is(err, os.ErrNotExist) {
			h.sendError(sess, env.ID, protocol.ErrReplayNotFound,
				"replay not found")
		} else {
			h.sendError(sess, env.ID, protocol.ErrInvalidMessage,
				"retained replay unavailable")
		}
		return nil
	}
	loaded, _ := protocol.NewEnvelope(protocol.TypeReplayLoaded, replay)
	loaded.ID = env.ID
	h.send(sess, loaded)
	return nil
}

func (h *Handler) allowReplayRequest(ip string, now time.Time) bool {
	h.replayRateMu.Lock()
	defer h.replayRateMu.Unlock()
	for key, candidate := range h.replayRates {
		if now.Sub(candidate.start) >= time.Minute {
			delete(h.replayRates, key)
		}
	}
	window := h.replayRates[ip]
	if window.start.IsZero() || now.Sub(window.start) >= time.Minute {
		window = createRateWindow{start: now}
	}
	if window.count >= h.config.ReplayRequestsPerMinute {
		h.replayRates[ip] = window
		return false
	}
	window.count++
	h.replayRates[ip] = window
	return true
}
