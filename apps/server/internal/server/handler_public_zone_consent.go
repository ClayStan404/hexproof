// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package server

import (
	"fmt"
	"hexproof/server/internal/protocol"
	"hexproof/server/internal/room"
	"strings"
	"sync/atomic"
	"time"
)

type publicZoneMoveRequest struct {
	approvalID      string
	originalID      string
	roomID          string
	requesterConnID string
	targetConnID    string
	expiresAt       time.Time
	card            *protocol.GameMoveCard
	cards           *protocol.GameMoveCards
}

func cloneMoveCard(move protocol.GameMoveCard) *protocol.GameMoveCard {
	copy := move
	if move.FromSeat != nil {
		value := *move.FromSeat
		copy.FromSeat = &value
	}
	if move.ToSeat != nil {
		value := *move.ToSeat
		copy.ToSeat = &value
	}
	if move.Position != nil {
		value := *move.Position
		copy.Position = &value
	}
	if move.LibraryIndex != nil {
		value := *move.LibraryIndex
		copy.LibraryIndex = &value
	}
	return &copy
}

func cloneMoveCards(move protocol.GameMoveCards) *protocol.GameMoveCards {
	copy := move
	copy.CardIDs = append([]string(nil), move.CardIDs...)
	if move.FromSeat != nil {
		value := *move.FromSeat
		copy.FromSeat = &value
	}
	if move.ToSeat != nil {
		value := *move.ToSeat
		copy.ToSeat = &value
	}
	if move.Position != nil {
		value := *move.Position
		copy.Position = &value
	}
	return &copy
}

func (h *Handler) handlePublicZoneConsentCommand(sess *Session,
	env protocol.Envelope, request any,
	reduce func(*room.Room) (room.Result, error),
	metadata func() (int, string, string, int),
	retained func() publicZoneMoveRequest) error {
	r := sess.Room()
	if r == nil {
		h.sendError(sess, env.ID, protocol.ErrNotInRoom, "not in a room")
		return nil
	}
	if err := env.DecodePayload(request); err != nil {
		h.sendError(sess, env.ID, protocol.ErrInvalidMessage, err.Error())
		return nil
	}
	operation, err := h.hub.lockRoomOperation(r.ID)
	if err != nil {
		code, _ := ErrCode(err)
		h.sendError(sess, env.ID, code, err.Error())
		return nil
	}
	defer operation.opMu.Unlock()
	res, err := reduce(r)
	if err != nil {
		code, _ := ErrCode(err)
		if code != protocol.ErrApprovalRequired {
			if code == "" {
				code = protocol.ErrInvalidMessage
			}
			h.sendError(sess, env.ID, code, err.Error())
			return nil
		}
		sourceSeat, sourceZone, toZone, cardCount := metadata()
		target, targetErr := h.hub.PublicZoneMoveTarget(
			sess.ConnectionID, sourceSeat, sourceZone, toZone, cardCount, r)
		if targetErr != nil {
			targetCode, _ := ErrCode(targetErr)
			h.sendError(sess, env.ID, targetCode, targetErr.Error())
			return nil
		}
		targetSession := h.sessionByConn(target.TargetConnID)
		if targetSession == nil {
			h.sendError(sess, env.ID, protocol.ErrInvalidTarget,
				"source-zone player is disconnected")
			return nil
		}
		pendingRequest := retained()
		pendingRequest.originalID = env.ID
		pendingRequest.roomID = r.ID
		pendingRequest.requesterConnID = sess.ConnectionID
		pendingRequest.targetConnID = target.TargetConnID
		approval, approvalErr := h.createPublicZoneMoveRequest(pendingRequest)
		if approvalErr != nil {
			approvalCode, _ := ErrCode(approvalErr)
			h.sendError(sess, env.ID, approvalCode, approvalErr.Error())
			return nil
		}
		pending, _ := protocol.NewEnvelope(
			protocol.TypeGamePublicZoneMovePending,
			protocol.GamePublicZoneMovePending{
				RoomID: r.ID, ApprovalID: approval.approvalID,
				TargetSeat: target.TargetSeat,
			})
		pending.ID = env.ID
		h.send(sess, pending)
		requested, _ := protocol.NewEnvelope(
			protocol.TypeGamePublicZoneMoveRequested,
			protocol.GamePublicZoneMoveRequested{
				RoomID: r.ID, ApprovalID: approval.approvalID,
				RequesterSeat: target.RequesterSeat,
				RequesterName: target.RequesterName,
				SourceZone:    target.SourceZone, CardCount: target.CardCount,
				ToZone: target.ToZone,
			})
		h.send(targetSession, requested)
		return nil
	}
	if res.Reply != nil {
		res.Reply.ID = env.ID
		h.send(sess, *res.Reply)
	}
	if res.ProjectGame {
		h.fanoutGameProjections(r)
	}
	return nil
}

func (h *Handler) handleGameRespondPublicZoneMove(sess *Session,
	env protocol.Envelope) error {
	r := sess.Room()
	if r == nil {
		h.sendError(sess, env.ID, protocol.ErrNotInRoom, "not in a room")
		return nil
	}
	var response protocol.GameRespondPublicZoneMove
	if err := env.DecodePayload(&response); err != nil {
		h.sendError(sess, env.ID, protocol.ErrInvalidMessage, err.Error())
		return nil
	}
	approval, err := h.resolvePublicZoneMoveRequest(
		sess.ConnectionID, r.ID, response.ApprovalID)
	if err != nil {
		code, _ := ErrCode(err)
		h.sendError(sess, env.ID, code, err.Error())
		return nil
	}
	responded, _ := protocol.NewEnvelope(
		protocol.TypeGamePublicZoneMoveResponded,
		protocol.GamePublicZoneMoveResponded{
			RoomID: r.ID, ApprovalID: approval.approvalID,
			Approved: response.Approved,
		})
	responded.ID = env.ID
	h.send(sess, responded)

	requester := h.sessionByConn(approval.requesterConnID)
	if requester == nil {
		return nil
	}
	if !response.Approved {
		h.sendError(requester, approval.originalID,
			protocol.ErrPermissionDenied, "public-zone move was denied")
		return nil
	}
	operation, err := h.hub.lockRoomOperation(r.ID)
	if err != nil {
		code, _ := ErrCode(err)
		h.sendError(requester, approval.originalID, code, err.Error())
		return nil
	}
	defer operation.opMu.Unlock()
	var res room.Result
	if approval.card != nil {
		res, err = h.hub.MoveApprovedCard(
			approval.requesterConnID, *approval.card, r)
	} else if approval.cards != nil {
		res, err = h.hub.MoveApprovedCards(
			approval.requesterConnID, *approval.cards, r)
	} else {
		err = &protocolError{code: protocol.ErrInvalidMessage,
			message: "approved public-zone move is empty"}
	}
	if err != nil {
		code, _ := ErrCode(err)
		if code == "" {
			code = protocol.ErrInvalidMessage
		}
		h.sendError(requester, approval.originalID, code, err.Error())
		return nil
	}
	if res.Reply != nil {
		res.Reply.ID = approval.originalID
		h.send(requester, *res.Reply)
	}
	if res.ProjectGame {
		h.fanoutGameProjections(r)
	}
	return nil
}

func (h *Handler) createPublicZoneMoveRequest(
	request publicZoneMoveRequest) (publicZoneMoveRequest, error) {
	now := time.Now().UTC()
	h.publicZoneMoveMu.Lock()
	defer h.publicZoneMoveMu.Unlock()
	h.prunePublicZoneMoveRequestsLocked(now)
	for _, pending := range h.publicZoneMoveRequests {
		if pending.roomID == request.roomID &&
			pending.targetConnID == request.targetConnID {
			return publicZoneMoveRequest{}, &protocolError{
				code:    protocol.ErrApprovalPending,
				message: "source-zone player already has an approval request",
			}
		}
	}
	request.approvalID = fmt.Sprintf("public-zone-move-%d",
		atomic.AddUint64(&h.publicZoneMoveSeq, 1))
	request.expiresAt = now.Add(zoneDumpDecisionTTL)
	h.publicZoneMoveRequests[request.approvalID] = request
	return request, nil
}

func (h *Handler) resolvePublicZoneMoveRequest(targetConnID, roomID,
	approvalID string) (publicZoneMoveRequest, error) {
	approvalID = strings.TrimSpace(approvalID)
	if approvalID == "" {
		return publicZoneMoveRequest{}, &protocolError{
			code: protocol.ErrInvalidMessage, message: "approvalId required"}
	}
	now := time.Now().UTC()
	h.publicZoneMoveMu.Lock()
	defer h.publicZoneMoveMu.Unlock()
	h.prunePublicZoneMoveRequestsLocked(now)
	request, ok := h.publicZoneMoveRequests[approvalID]
	if !ok || request.targetConnID != targetConnID || request.roomID != roomID {
		return publicZoneMoveRequest{}, &protocolError{
			code:    protocol.ErrApprovalExpired,
			message: "public-zone move request expired"}
	}
	delete(h.publicZoneMoveRequests, approvalID)
	return request, nil
}

func (h *Handler) prunePublicZoneMoveRequestsLocked(now time.Time) {
	for approvalID, request := range h.publicZoneMoveRequests {
		if !request.expiresAt.After(now) {
			delete(h.publicZoneMoveRequests, approvalID)
		}
	}
}

func (h *Handler) discardPublicZoneMoveRequestsForConn(connID string) {
	h.publicZoneMoveMu.Lock()
	defer h.publicZoneMoveMu.Unlock()
	for approvalID, request := range h.publicZoneMoveRequests {
		if request.requesterConnID == connID || request.targetConnID == connID {
			delete(h.publicZoneMoveRequests, approvalID)
		}
	}
}
