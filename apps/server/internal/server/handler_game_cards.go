// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package server

import (
	"hexproof/server/internal/protocol"
	"hexproof/server/internal/room"
)

func (h *Handler) handleGameDraw(sess *Session, env protocol.Envelope) error {
	var request protocol.GameDraw
	return h.handleGameCommand(sess, env, &request,
		func(r *room.Room) (room.Result, error) {
			count := 1
			if request.Count != nil {
				count = *request.Count
			}
			return h.hub.Draw(sess.ConnectionID, count, r)
		}, gameCommandOptions{})
}

func (h *Handler) handleGameShuffleLibrary(sess *Session, env protocol.Envelope) error {
	var request protocol.GameShuffleLibrary
	return h.handleGameCommand(sess, env, &request,
		func(r *room.Room) (room.Result, error) {
			return h.hub.ShuffleLibrary(sess.ConnectionID, r)
		}, gameCommandOptions{projectAlways: true})
}

func (h *Handler) handleGameMulligan(sess *Session, env protocol.Envelope) error {
	var request protocol.GameMulligan
	return h.handleGameCommand(sess, env, &request,
		func(r *room.Room) (room.Result, error) {
			return h.hub.Mulligan(sess.ConnectionID, r)
		}, gameCommandOptions{projectAlways: true})
}

func (h *Handler) handleGameDiscardHand(sess *Session, env protocol.Envelope) error {
	var request protocol.GameDiscardHand
	return h.handleGameCommand(sess, env, &request,
		func(r *room.Room) (room.Result, error) {
			return h.hub.DiscardHand(sess.ConnectionID, request.All, r)
		}, gameCommandOptions{projectAlways: true})
}

func (h *Handler) handleGameMoveCard(sess *Session, env protocol.Envelope) error {
	var request protocol.GameMoveCard
	return h.handlePublicZoneConsentCommand(sess, env, &request,
		func(r *room.Room) (room.Result, error) {
			return h.hub.MoveCard(sess.ConnectionID, request, r)
		}, func() (int, string, string, int) {
			sourceSeat := -1
			if request.FromSeat != nil {
				sourceSeat = *request.FromSeat
			}
			return sourceSeat, request.FromZone, request.ToZone, 1
		}, func() publicZoneMoveRequest {
			return publicZoneMoveRequest{card: cloneMoveCard(request)}
		})
}

func (h *Handler) handleGameMoveCards(sess *Session, env protocol.Envelope) error {
	var request protocol.GameMoveCards
	return h.handlePublicZoneConsentCommand(sess, env, &request,
		func(r *room.Room) (room.Result, error) {
			return h.hub.MoveCards(sess.ConnectionID, request, r)
		}, func() (int, string, string, int) {
			sourceSeat := -1
			if request.FromSeat != nil {
				sourceSeat = *request.FromSeat
			}
			return sourceSeat, request.FromZone, request.ToZone,
				len(request.CardIDs)
		}, func() publicZoneMoveRequest {
			return publicZoneMoveRequest{cards: cloneMoveCards(request)}
		})
}

func (h *Handler) handleGameMoveLibraryCards(sess *Session, env protocol.Envelope) error {
	var request protocol.GameMoveLibraryCards
	return h.handleGameCommand(sess, env, &request,
		func(r *room.Room) (room.Result, error) {
			return h.hub.MoveLibraryCards(sess.ConnectionID, request, r)
		}, gameCommandOptions{projectAlways: true})
}

func (h *Handler) handleGameSetTapped(sess *Session, env protocol.Envelope) error {
	var request protocol.GameSetTapped
	return h.handleGameCommand(sess, env, &request,
		func(r *room.Room) (room.Result, error) {
			return h.hub.SetTapped(sess.ConnectionID, request, r)
		}, gameCommandOptions{projectAlways: true})
}

func (h *Handler) handleGameSetCardCounter(sess *Session,
	env protocol.Envelope) error {
	var request protocol.GameSetCardCounter
	return h.handleGameCommand(sess, env, &request,
		func(r *room.Room) (room.Result, error) {
			return h.hub.SetCardCounter(sess.ConnectionID, request, r)
		}, gameCommandOptions{projectAlways: true})
}

func (h *Handler) handleGameSetCardFace(sess *Session,
	env protocol.Envelope) error {
	var request protocol.GameSetCardFace
	return h.handleGameCommand(sess, env, &request,
		func(r *room.Room) (room.Result, error) {
			return h.hub.SetCardFace(sess.ConnectionID, request, r)
		}, gameCommandOptions{projectAlways: true})
}

func (h *Handler) handleGameSetFaceDown(sess *Session,
	env protocol.Envelope) error {
	var request protocol.GameSetFaceDown
	return h.handleGameCommand(sess, env, &request,
		func(r *room.Room) (room.Result, error) {
			return h.hub.SetFaceDown(sess.ConnectionID, request, r)
		}, gameCommandOptions{})
}
