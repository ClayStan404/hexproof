// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package server

import (
	"hexproof/server/internal/protocol"
	"hexproof/server/internal/room"
)

func (h *Handler) handleGameSetPhase(sess *Session, env protocol.Envelope) error {
	var request protocol.GameSetPhase
	return h.handleGameCommand(sess, env, &request,
		func(r *room.Room) (room.Result, error) {
			return h.hub.SetPhase(sess.ConnectionID, request, r)
		}, gameCommandOptions{projectAlways: true})
}

func (h *Handler) handleGameSetResponseStatus(sess *Session,
	env protocol.Envelope) error {
	var request protocol.GameSetResponseStatus
	return h.handleGameCommand(sess, env, &request,
		func(r *room.Room) (room.Result, error) {
			return h.hub.SetResponseStatus(sess.ConnectionID, request, r)
		}, gameCommandOptions{})
}

func (h *Handler) handleGameSetCounter(sess *Session, env protocol.Envelope) error {
	var request protocol.GameSetCounter
	return h.handleGameCommand(sess, env, &request,
		func(r *room.Room) (room.Result, error) {
			return h.hub.SetCounter(sess.ConnectionID, request, r)
		}, gameCommandOptions{})
}

func (h *Handler) handleGameSetCounterCount(sess *Session, env protocol.Envelope) error {
	var request protocol.GameSetCounterCount
	return h.handleGameCommand(sess, env, &request,
		func(r *room.Room) (room.Result, error) {
			return h.hub.SetCounterCount(sess.ConnectionID, request, r)
		}, gameCommandOptions{})
}

func (h *Handler) handleGameNextTurn(sess *Session, env protocol.Envelope) error {
	var request protocol.GameNextTurn
	return h.handleGameCommand(sess, env, &request,
		func(r *room.Room) (room.Result, error) {
			return h.hub.NextTurn(sess.ConnectionID, r)
		}, gameCommandOptions{projectAlways: true})
}

func (h *Handler) handleGameReveal(sess *Session, env protocol.Envelope) error {
	var request protocol.GameReveal
	return h.handleGameCommand(sess, env, &request,
		func(r *room.Room) (room.Result, error) {
			return h.hub.Reveal(sess.ConnectionID, request, r)
		}, gameCommandOptions{projectAlways: true})
}

func (h *Handler) handleGameRecallRevealed(sess *Session,
	env protocol.Envelope) error {
	var request protocol.GameRecallRevealed
	return h.handleGameCommand(sess, env, &request,
		func(r *room.Room) (room.Result, error) {
			return h.hub.RecallRevealed(sess.ConnectionID, r)
		}, gameCommandOptions{projectAlways: true})
}
