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

type zoneDumpRequest struct {
	approvalID      string
	originalID      string
	roomID          string
	requesterConnID string
	targetConnID    string
	targetSeat      int
	topCount        int
	expiresAt       time.Time
	approved        bool
	allowedCardIDs  map[string]struct{}
}

func (h *Handler) handleGameDumpZone(sess *Session, env protocol.Envelope) error {
	r := sess.Room()
	if r == nil {
		h.sendError(sess, env.ID, protocol.ErrNotInRoom, "not in a room")
		return nil
	}
	var request protocol.GameDumpZone
	if err := env.DecodePayload(&request); err != nil {
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
	res, err := h.hub.DumpZone(sess.ConnectionID, request, r)
	if err != nil {
		code, _ := ErrCode(err)
		if code == protocol.ErrApprovalRequired {
			target, targetErr := h.hub.ZoneDumpTarget(
				sess.ConnectionID, request, r)
			if targetErr != nil {
				targetCode, _ := ErrCode(targetErr)
				h.sendError(sess, env.ID, targetCode, targetErr.Error())
				return nil
			}
			targetSession := h.sessionByConn(target.TargetConnID)
			if targetSession == nil {
				h.sendError(sess, env.ID, protocol.ErrInvalidTarget,
					"target player is disconnected")
				return nil
			}
			approval, approvalErr := h.createZoneDumpRequest(
				env.ID, r.ID, sess.ConnectionID, target)
			if approvalErr != nil {
				approvalCode, _ := ErrCode(approvalErr)
				h.sendError(sess, env.ID, approvalCode, approvalErr.Error())
				return nil
			}
			pending, _ := protocol.NewEnvelope(
				protocol.TypeGameZoneDumpPending,
				protocol.GameZoneDumpPending{
					RoomID:     r.ID,
					ApprovalID: approval.approvalID,
					TargetSeat: target.TargetSeat,
				})
			pending.ID = env.ID
			h.send(sess, pending)
			requested, _ := protocol.NewEnvelope(
				protocol.TypeGameZoneDumpRequested,
				protocol.GameZoneDumpRequested{
					RoomID:        r.ID,
					ApprovalID:    approval.approvalID,
					RequesterSeat: target.RequesterSeat,
					RequesterName: target.RequesterName,
					Zone:          protocol.ZoneLibrary,
					TopCount:      target.TopCount,
				})
			h.send(targetSession, requested)
			return nil
		}
		if code == "" {
			code = protocol.ErrInvalidMessage
		}
		h.sendError(sess, env.ID, code, err.Error())
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

func (h *Handler) handleGameRespondZoneDump(sess *Session,
	env protocol.Envelope) error {
	r := sess.Room()
	if r == nil {
		h.sendError(sess, env.ID, protocol.ErrNotInRoom, "not in a room")
		return nil
	}
	var response protocol.GameRespondZoneDump
	if err := env.DecodePayload(&response); err != nil {
		h.sendError(sess, env.ID, protocol.ErrInvalidMessage, err.Error())
		return nil
	}
	approval, err := h.resolveZoneDumpRequest(
		sess.ConnectionID, r.ID, response)
	if err != nil {
		code, _ := ErrCode(err)
		h.sendError(sess, env.ID, code, err.Error())
		return nil
	}
	responded, _ := protocol.NewEnvelope(
		protocol.TypeGameZoneDumpResponded,
		protocol.GameZoneDumpResponded{
			RoomID:     r.ID,
			ApprovalID: approval.approvalID,
			Approved:   response.Approved,
		})
	responded.ID = env.ID
	h.send(sess, responded)

	requester := h.sessionByConn(approval.requesterConnID)
	if requester == nil {
		h.discardZoneDumpRequest(approval.approvalID)
		return nil
	}
	if !response.Approved {
		h.sendError(requester, approval.originalID,
			protocol.ErrPermissionDenied, "library access was denied")
		return nil
	}

	operation, err := h.hub.lockRoomOperation(r.ID)
	if err != nil {
		h.discardZoneDumpRequest(approval.approvalID)
		code, _ := ErrCode(err)
		h.sendError(requester, approval.originalID, code, err.Error())
		return nil
	}
	defer operation.opMu.Unlock()
	res, err := h.hub.DumpApprovedZone(
		approval.requesterConnID, approval.targetSeat,
		approval.approvalID, approval.topCount, r)
	if err != nil {
		h.discardZoneDumpRequest(approval.approvalID)
		code, _ := ErrCode(err)
		h.sendError(requester, approval.originalID, code, err.Error())
		return nil
	}
	if res.Reply == nil {
		h.discardZoneDumpRequest(approval.approvalID)
		h.sendError(requester, approval.originalID,
			protocol.ErrApprovalExpired, "library access approval expired")
		return nil
	}
	res.Reply.ID = approval.originalID
	var dumped protocol.GameZoneDumped
	if err := res.Reply.DecodePayload(&dumped); err != nil ||
		!h.bindZoneDumpGrant(approval.approvalID, dumped.Cards) {
		h.discardZoneDumpRequest(approval.approvalID)
		h.sendError(requester, approval.originalID,
			protocol.ErrApprovalExpired, "library access approval expired")
		return nil
	}
	if res.Reply != nil {
		h.send(requester, *res.Reply)
	}
	if res.ProjectGame {
		h.fanoutGameProjections(r)
	}
	return nil
}

func (h *Handler) handleGameSearchLibrary(sess *Session, env protocol.Envelope) error {
	r := sess.Room()
	if r == nil {
		h.sendError(sess, env.ID, protocol.ErrNotInRoom, "not in a room")
		return nil
	}
	var request protocol.GameSearchLibrary
	if err := env.DecodePayload(&request); err != nil {
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
	var res room.Result
	if request.ApprovalID != "" {
		if request.SourceSeat == nil {
			h.sendError(sess, env.ID, protocol.ErrInvalidTarget,
				"sourceSeat required with approvalId")
			return nil
		}
		if err := h.validateZoneDumpGrant(
			request.ApprovalID, sess.ConnectionID, r.ID,
			*request.SourceSeat, request); err != nil {
			code, _ := ErrCode(err)
			h.sendError(sess, env.ID, code, err.Error())
			return nil
		}
		res, err = h.hub.SearchApprovedLibrary(
			sess.ConnectionID, request, r)
	} else {
		res, err = h.hub.SearchLibrary(sess.ConnectionID, request, r)
	}
	if err != nil {
		code, _ := ErrCode(err)
		if code == "" {
			code = protocol.ErrInvalidMessage
		}
		h.sendError(sess, env.ID, code, err.Error())
		return nil
	}
	if request.ApprovalID != "" {
		h.discardZoneDumpRequest(request.ApprovalID)
	}
	if res.Reply != nil {
		res.Reply.ID = env.ID
		h.send(sess, *res.Reply)
	}
	h.fanoutGameProjections(r)
	return nil
}

func (h *Handler) handleGameReorderLibrary(sess *Session,
	env protocol.Envelope) error {
	r := sess.Room()
	if r == nil {
		h.sendError(sess, env.ID, protocol.ErrNotInRoom, "not in a room")
		return nil
	}
	var request protocol.GameReorderLibrary
	if err := env.DecodePayload(&request); err != nil {
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
	res, err := h.hub.ReorderLibrary(sess.ConnectionID, request, r)
	if err != nil {
		code, _ := ErrCode(err)
		if code == "" {
			code = protocol.ErrInvalidMessage
		}
		h.sendError(sess, env.ID, code, err.Error())
		return nil
	}
	if res.Reply != nil {
		res.Reply.ID = env.ID
		h.send(sess, *res.Reply)
	}
	h.fanoutGameProjections(r)
	return nil
}

func (h *Handler) handleGameResolveLibraryView(sess *Session,
	env protocol.Envelope) error {
	r := sess.Room()
	if r == nil {
		h.sendError(sess, env.ID, protocol.ErrNotInRoom, "not in a room")
		return nil
	}
	var request protocol.GameResolveLibraryView
	if err := env.DecodePayload(&request); err != nil {
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
	var res room.Result
	if request.ApprovalID != "" {
		if request.SourceSeat == nil {
			h.sendError(sess, env.ID, protocol.ErrInvalidTarget,
				"sourceSeat required with approvalId")
			return nil
		}
		if err := h.validateZoneDumpResolveGrant(
			request.ApprovalID, sess.ConnectionID, r.ID,
			*request.SourceSeat, request); err != nil {
			code, _ := ErrCode(err)
			h.sendError(sess, env.ID, code, err.Error())
			return nil
		}
		res, err = h.hub.ResolveApprovedLibraryView(
			sess.ConnectionID, request, r)
	} else {
		res, err = h.hub.ResolveLibraryView(sess.ConnectionID, request, r)
	}
	if err != nil {
		code, _ := ErrCode(err)
		if code == "" {
			code = protocol.ErrInvalidMessage
		}
		h.sendError(sess, env.ID, code, err.Error())
		return nil
	}
	if request.ApprovalID != "" {
		h.discardZoneDumpRequest(request.ApprovalID)
	}
	if res.Reply != nil {
		res.Reply.ID = env.ID
		h.send(sess, *res.Reply)
	}
	h.fanoutGameProjections(r)
	return nil
}

func (h *Handler) createZoneDumpRequest(originalID, roomID,
	requesterConnID string, target room.ZoneDumpTarget) (zoneDumpRequest, error) {
	now := time.Now().UTC()
	h.zoneDumpMu.Lock()
	defer h.zoneDumpMu.Unlock()
	h.pruneZoneDumpRequestsLocked(now)
	for _, pending := range h.zoneDumpRequests {
		if pending.roomID == roomID &&
			pending.targetConnID == target.TargetConnID {
			return zoneDumpRequest{},
				&protocolError{code: protocol.ErrApprovalPending,
					message: "target player already has a library access request"}
		}
	}
	approvalID := fmt.Sprintf("zone-dump-%d",
		atomic.AddUint64(&h.zoneDumpSeq, 1))
	request := zoneDumpRequest{
		approvalID:      approvalID,
		originalID:      originalID,
		roomID:          roomID,
		requesterConnID: requesterConnID,
		targetConnID:    target.TargetConnID,
		targetSeat:      target.TargetSeat,
		topCount:        target.TopCount,
		expiresAt:       now.Add(zoneDumpDecisionTTL),
	}
	h.zoneDumpRequests[approvalID] = request
	return request, nil
}

func (h *Handler) resolveZoneDumpRequest(targetConnID, roomID string,
	response protocol.GameRespondZoneDump) (zoneDumpRequest, error) {
	approvalID := strings.TrimSpace(response.ApprovalID)
	if approvalID == "" {
		return zoneDumpRequest{},
			&protocolError{code: protocol.ErrInvalidMessage,
				message: "approvalId required"}
	}
	now := time.Now().UTC()
	h.zoneDumpMu.Lock()
	defer h.zoneDumpMu.Unlock()
	h.pruneZoneDumpRequestsLocked(now)
	request, ok := h.zoneDumpRequests[approvalID]
	if !ok || request.targetConnID != targetConnID ||
		request.roomID != roomID || request.approved {
		return zoneDumpRequest{},
			&protocolError{code: protocol.ErrApprovalExpired,
				message: "library access request expired"}
	}
	if !response.Approved {
		delete(h.zoneDumpRequests, approvalID)
		return request, nil
	}
	request.approved = true
	request.expiresAt = now.Add(zoneDumpGrantTTL)
	h.zoneDumpRequests[approvalID] = request
	return request, nil
}

func (h *Handler) bindZoneDumpGrant(approvalID string,
	cards []protocol.GameCard) bool {
	h.zoneDumpMu.Lock()
	defer h.zoneDumpMu.Unlock()
	request, ok := h.zoneDumpRequests[approvalID]
	if !ok || !request.approved {
		return false
	}
	request.allowedCardIDs = make(map[string]struct{}, len(cards))
	for _, card := range cards {
		request.allowedCardIDs[card.ID] = struct{}{}
	}
	h.zoneDumpRequests[approvalID] = request
	return true
}

func (h *Handler) consumeZoneDumpGrant(approvalID, requesterConnID,
	roomID string, sourceSeat int, search protocol.GameSearchLibrary) error {
	if err := h.validateZoneDumpGrant(
		approvalID, requesterConnID, roomID, sourceSeat, search); err != nil {
		return err
	}
	h.discardZoneDumpRequest(approvalID)
	return nil
}

func (h *Handler) validateZoneDumpGrant(approvalID, requesterConnID,
	roomID string, sourceSeat int, search protocol.GameSearchLibrary) error {
	cardIDs := append([]string(nil), search.CardIDs...)
	if len(cardIDs) == 0 && strings.TrimSpace(search.CardID) != "" {
		cardIDs = append(cardIDs, search.CardID)
	}
	return h.validateZoneDumpGrantCardIDs(
		approvalID, requesterConnID, roomID, sourceSeat, cardIDs, false)
}

func (h *Handler) validateZoneDumpResolveGrant(approvalID, requesterConnID,
	roomID string, sourceSeat int,
	resolve protocol.GameResolveLibraryView) error {
	cardIDs := make([]string, 0, len(resolve.Assignments)+
		len(resolve.SelectedCardIDs)+len(resolve.RemainderCardIDs))
	for _, assignment := range resolve.Assignments {
		cardIDs = append(cardIDs, assignment.CardID)
	}
	cardIDs = append(cardIDs, resolve.SelectedCardIDs...)
	cardIDs = append(cardIDs, resolve.RemainderCardIDs...)
	return h.validateZoneDumpGrantCardIDs(
		approvalID, requesterConnID, roomID, sourceSeat, cardIDs, true)
}

func (h *Handler) validateZoneDumpGrantCardIDs(approvalID,
	requesterConnID, roomID string, sourceSeat int, cardIDs []string,
	requireCompleteScope bool) error {
	approvalID = strings.TrimSpace(approvalID)
	now := time.Now().UTC()
	h.zoneDumpMu.Lock()
	defer h.zoneDumpMu.Unlock()
	h.pruneZoneDumpRequestsLocked(now)
	request, ok := h.zoneDumpRequests[approvalID]
	if !ok || request.requesterConnID != requesterConnID ||
		request.roomID != roomID || request.targetSeat != sourceSeat {
		return &protocolError{code: protocol.ErrApprovalExpired,
			message: "library access approval expired"}
	}
	if !request.approved {
		return &protocolError{code: protocol.ErrApprovalPending,
			message: "library access approval is still pending"}
	}
	if len(cardIDs) == 0 || request.allowedCardIDs == nil {
		return &protocolError{code: protocol.ErrApprovalExpired,
			message: "library access approval expired"}
	}
	for _, cardID := range cardIDs {
		if _, allowed := request.allowedCardIDs[strings.TrimSpace(cardID)]; !allowed {
			return &protocolError{code: protocol.ErrApprovalExpired,
				message: "library access approval expired"}
		}
	}
	if requireCompleteScope {
		unique := make(map[string]struct{}, len(cardIDs))
		for _, cardID := range cardIDs {
			unique[strings.TrimSpace(cardID)] = struct{}{}
		}
		if len(unique) != len(request.allowedCardIDs) {
			return &protocolError{code: protocol.ErrApprovalExpired,
				message: "library access approval expired"}
		}
	}
	return nil
}

func (h *Handler) discardZoneDumpRequest(approvalID string) {
	h.zoneDumpMu.Lock()
	defer h.zoneDumpMu.Unlock()
	delete(h.zoneDumpRequests, approvalID)
}

func (h *Handler) pruneZoneDumpRequestsLocked(now time.Time) {
	for approvalID, request := range h.zoneDumpRequests {
		if !request.expiresAt.After(now) {
			delete(h.zoneDumpRequests, approvalID)
		}
	}
}

func (h *Handler) discardZoneDumpRequestsForConn(connID string) {
	h.zoneDumpMu.Lock()
	defer h.zoneDumpMu.Unlock()
	for approvalID, request := range h.zoneDumpRequests {
		if request.requesterConnID == connID ||
			request.targetConnID == connID {
			delete(h.zoneDumpRequests, approvalID)
		}
	}
}
