// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package server

import (
	"fmt"
	"hexproof/server/internal/protocol"
	"hexproof/server/internal/room"
	"log"
	"net"
	"net/http"
	"strings"
	"time"
	"unicode/utf8"
)

func (h *Handler) handleRoomList(sess *Session, env protocol.Envelope) error {
	if sess.DisplayName == "" {
		h.sendError(sess, env.ID, protocol.ErrNameRequired, "hello first")
		return nil
	}
	listed, _ := protocol.NewEnvelope(protocol.TypeRoomListed,
		protocol.RoomListed{Rooms: h.hub.ListRooms()})
	listed.ID = env.ID
	h.send(sess, listed)
	return nil
}

func (h *Handler) handleRoomCreate(sess *Session, env protocol.Envelope) error {
	if sess.DisplayName == "" {
		h.sendError(sess, env.ID, protocol.ErrNameRequired, "hello first")
		return nil
	}
	// A connection already in a room cannot create another; leave/disband first.
	if sess.Room() != nil {
		h.sendError(sess, env.ID, protocol.ErrAlreadyInRoom, "leave current room first")
		return nil
	}
	var rc protocol.RoomCreate
	if err := env.DecodePayload(&rc); err != nil {
		h.sendError(sess, env.ID, protocol.ErrInvalidMessage, err.Error())
		return nil
	}
	rc.Name = strings.TrimSpace(rc.Name)
	if rc.Name == "" || utf8.RuneCountInString(rc.Name) > protocol.MaxRoomNameRunes ||
		hasControlCharacters(rc.Name) || len(rc.Password) > protocol.MaxPasswordBytes {
		h.sendError(sess, env.ID, protocol.ErrInvalidMessage, "invalid room name or password")
		return nil
	}
	maxSeats, err := room.ValidateFormat(rc.Format)
	if err != nil {
		h.sendError(sess, env.ID, protocol.ErrUnsupportedFormat, err.Error())
		return nil
	}
	if rc.DeckFormat == "" {
		rc.DeckFormat = protocol.DefaultDeckFormatForTableMode(rc.Format)
	}
	if !protocol.ValidDeckFormat(rc.DeckFormat) ||
		protocol.TableModeForDeckFormat(rc.DeckFormat) != rc.Format {
		h.sendError(sess, env.ID, protocol.ErrUnsupportedFormat,
			"deck format does not match table mode")
		return nil
	}
	if rc.Playtest {
		maxSeats = 1
	}
	if code := room.ValidateMatchMode(rc.MatchMode); code != "" {
		h.sendError(sess, env.ID, code, code)
		return nil
	}
	if rc.CardLoadMode == "" {
		rc.CardLoadMode = protocol.CardLoadPreload
	}
	if code := room.ValidateCardLoadMode(rc.CardLoadMode); code != "" {
		h.sendError(sess, env.ID, code, code)
		return nil
	}
	if rc.RulesMode == "" {
		rc.RulesMode = protocol.RulesModeManual
	}
	if code := room.ValidateRulesMode(rc.RulesMode); code != "" {
		h.sendError(sess, env.ID, code, code)
		return nil
	}
	if rc.RulesMode == protocol.RulesModeForge && !h.forgeRulesAvailable() {
		h.sendError(sess, env.ID, protocol.ErrRulesUnavailable,
			"Forge rules mode is not available on this server")
		return nil
	}
	if rc.Playtest && rc.RulesMode == protocol.RulesModeForge {
		h.sendError(sess, env.ID, protocol.ErrInvalidRulesMode,
			"Forge rules mode requires at least two players")
		return nil
	}
	if rc.Format == protocol.FormatEDH || rc.Playtest {
		rc.MatchMode = protocol.MatchBO1
	}
	if rc.Playtest {
		rc.AllowSpectators = false
		rc.SpectatorsSeeHands = false
		rc.Password = ""
	}
	if !rc.AllowSpectators {
		rc.SpectatorsSeeHands = false
	}
	if !h.allowRoomCreate(sess.RemoteIP, time.Now().UTC()) {
		h.sendError(sess, env.ID, protocol.ErrRateLimited, "room create rate limit exceeded")
		return nil
	}
	// Format dictates the multiplayer seat cap (2 or 4); Playtest overrides it
	// with one private seat. Client MaxSeats is ignored (decisions.md).
	r, initialSnapshot, initialSeq, operation, err := h.hub.CreateRoomWithRulesMode(
		rc.Name, rc.Format, rc.DeckFormat, rc.MatchMode, rc.CardLoadMode, rc.RulesMode,
		maxSeats, rc.AllowSpectators, rc.SpectatorsSeeHands, rc.Password, sess)
	if err != nil {
		code, _ := ErrCode(err)
		if code == "" {
			code = protocol.ErrInvalidMessage
		}
		h.sendError(sess, env.ID, code, err.Error())
		return nil
	}
	defer operation.opMu.Unlock()
	created := protocol.RoomCreated{
		RoomID: r.ID,
		Settings: protocol.RoomSettings{
			Name:               r.Name,
			Format:             r.Format,
			DeckFormat:         r.DeckFormat,
			MaxSeats:           r.MaxSeats,
			Playtest:           r.Playtest,
			AllowSpectators:    r.AllowSpectators,
			SpectatorsSeeHands: r.SpectatorsSeeHands,
			MatchMode:          r.MatchMode,
			CardLoadMode:       r.CardLoadMode,
			HasPassword:        r.HasPassword,
			RulesMode:          r.RulesMode,
		},
		HostSeat: r.HostSeat,
	}
	cEnv, _ := protocol.NewEnvelope(protocol.TypeRoomCreated, created)
	cEnv.ID = env.ID
	h.send(sess, cEnv)

	// Initial snapshot to the creator.
	snap, _ := protocol.NewEnvelope(protocol.TypeRoomSnapshot, initialSnapshot)
	snap = snap.WithSeq(initialSeq)
	h.send(sess, snap)
	return nil
}

func (h *Handler) handleRoomJoin(sess *Session, env protocol.Envelope) error {
	if sess.DisplayName == "" {
		h.sendError(sess, env.ID, protocol.ErrNameRequired, "hello first")
		return nil
	}
	// A connection already in a room cannot join another; leave first.
	if sess.Room() != nil {
		h.sendError(sess, env.ID, protocol.ErrAlreadyInRoom, "leave current room first")
		return nil
	}
	var rj protocol.RoomJoin
	if err := env.DecodePayload(&rj); err != nil {
		h.sendError(sess, env.ID, protocol.ErrInvalidMessage, err.Error())
		return nil
	}
	rj.RoomID = strings.ToUpper(strings.TrimSpace(rj.RoomID))
	if len(rj.RoomID) != 6 || len(rj.Password) > protocol.MaxPasswordBytes {
		h.sendError(sess, env.ID, protocol.ErrInvalidMessage, "invalid room id or password")
		return nil
	}
	if protected, exists := h.hub.RoomRequiresPassword(rj.RoomID); exists && protected &&
		!h.allowPasswordJoin(sess.RemoteIP, time.Now().UTC()) {
		h.sendError(sess, env.ID, protocol.ErrRateLimited,
			"password join rate limit exceeded")
		return nil
	}
	operation, err := h.hub.beginJoin(rj.RoomID, rj.Password)
	if err != nil {
		code, _ := ErrCode(err)
		h.sendError(sess, env.ID, code, err.Error())
		return nil
	}
	defer operation.opMu.Unlock()
	if operation.tournamentID != "" {
		h.sendError(sess, env.ID, protocol.ErrTournamentForbidden,
			"join this match from the tournament")
		return nil
	}
	res, r, err := h.hub.joinRoom(operation, sess, rj.AsSpectator)
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
	h.fanout(r, res.Broadcast)
	if res.ProjectGame {
		h.fanoutGameProjections(r)
	}
	return nil
}

func (h *Handler) handleRoomLeave(sess *Session, env protocol.Envelope) error {
	r := sess.Room()
	if r == nil {
		h.sendError(sess, env.ID, protocol.ErrNotInRoom, "not in a room")
		return nil
	}
	operation, err := h.hub.lockRoomOperation(r.ID)
	if err != nil {
		code, _ := ErrCode(err)
		h.sendError(sess, env.ID, code, err.Error())
		return nil
	}
	var retained *retainedRoom
	var cleanup pairingRoomCleanup
	defer func() {
		operation.opMu.Unlock()
		h.commitPairingRoomCleanup(cleanup)
		h.saveRoomRetention(retained)
	}()
	operation.mu.Lock()
	departingForgePlayer := operation.room == r &&
		r.RulesMode == protocol.RulesModeForge &&
		r.Phase == protocol.RoomPhaseStarted &&
		r.FindSeatByConnection(sess.ConnectionID) >= 0
	operation.mu.Unlock()
	res, disbanded, err := h.hub.LeaveRoom(sess.ConnectionID, r)
	if err != nil {
		code, _ := ErrCode(err)
		h.sendError(sess, env.ID, code, err.Error())
		return nil
	}
	sess.setRoom(nil)
	h.discardZoneDumpRequestsForConn(sess.ConnectionID)
	h.discardPublicZoneMoveRequestsForConn(sess.ConnectionID)
	if res.Reply != nil {
		res.Reply.ID = env.ID
		h.send(sess, *res.Reply)
	}
	var rulesReset *room.Result
	if !disbanded && departingForgePlayer {
		h.abortForgeGame(r.ID)
		reset, resetErr := h.hub.ResetRulesStartFailure(r)
		if resetErr != nil {
			h.failClosedGameProjections(r, resetErr)
			return nil
		}
		rulesReset = &reset
	}
	if disbanded {
		h.disbandAndFanout(r, res.Broadcast)
		retained = h.snapshotRoomRetention(r)
		cleanup = h.removeRoom(r)
	} else {
		if rulesReset != nil {
			h.fanout(r, rulesReset.Broadcast)
		} else {
			h.fanout(r, res.Broadcast)
		}
		if res.ProjectGame && rulesReset == nil {
			h.fanoutGameProjections(r)
		}
		retained, cleanup = h.removeRoomIfEmpty(r)
	}
	return nil
}

func (h *Handler) handleRoomKick(sess *Session, env protocol.Envelope) error {
	r := sess.Room()
	if r == nil {
		h.sendError(sess, env.ID, protocol.ErrNotInRoom, "not in a room")
		return nil
	}
	var rk protocol.RoomKick
	if err := env.DecodePayload(&rk); err != nil {
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
	if code := rk.Validate(); code != "" {
		h.sendError(sess, env.ID, code, code)
		return nil
	}
	res, err := h.hub.KickFromRoom(sess.ConnectionID, rk.Seat, rk.SpectatorIndex, r)
	if err != nil {
		code, _ := ErrCode(err)
		h.sendError(sess, env.ID, code, err.Error())
		return nil
	}
	var rulesReset *room.Result
	if rk.Seat != nil && r.RulesMode == protocol.RulesModeForge &&
		r.Phase == protocol.RoomPhaseStarted {
		h.abortForgeGame(r.ID)
		reset, resetErr := h.hub.ResetRulesStartFailure(r)
		if resetErr != nil {
			h.failClosedGameProjections(r, resetErr)
			return nil
		}
		rulesReset = &reset
	}

	// Notify the kicked target FIRST: a server-push room.kicked (no echo of the
	// host's request id) + unbind its room so subsequent commands fail with
	// not_in_room instead of treating it as still seated. This must happen
	// before fanout, since membersOf no longer includes the target.
	if res.TargetConnID != "" {
		h.discardZoneDumpRequestsForConn(res.TargetConnID)
		h.discardPublicZoneMoveRequestsForConn(res.TargetConnID)
		if target := h.sessionByConn(res.TargetConnID); target != nil {
			target.setRoom(nil)
			push, _ := protocol.NewEnvelope(protocol.TypeRoomKicked, map[string]any{"roomId": r.ID})
			h.send(target, push)
		}
	}

	// Reply to the host with echo of its request id.
	if res.Reply != nil {
		res.Reply.ID = env.ID
		h.send(sess, *res.Reply)
	}
	// Fanout snapshot to remaining members (target already excluded).
	if rulesReset != nil {
		h.fanout(r, rulesReset.Broadcast)
	} else {
		h.fanout(r, res.Broadcast)
	}
	if res.ProjectGame && rulesReset == nil {
		h.fanoutGameProjections(r)
	}
	return nil
}

func (h *Handler) handleRoomDisband(sess *Session, env protocol.Envelope) error {
	r := sess.Room()
	if r == nil {
		h.sendError(sess, env.ID, protocol.ErrNotInRoom, "not in a room")
		return nil
	}
	operation, err := h.hub.lockRoomOperation(r.ID)
	if err != nil {
		code, _ := ErrCode(err)
		h.sendError(sess, env.ID, code, err.Error())
		return nil
	}
	var retained *retainedRoom
	var cleanup pairingRoomCleanup
	defer func() {
		operation.opMu.Unlock()
		h.commitPairingRoomCleanup(cleanup)
		h.saveRoomRetention(retained)
	}()
	res, err := h.hub.DisbandRoom(sess.ConnectionID, r)
	if err != nil {
		code, _ := ErrCode(err)
		if code == "" {
			code = protocol.ErrInvalidMessage
		}
		h.sendError(sess, env.ID, code, err.Error())
		return nil
	}
	sess.setRoom(nil)
	if res.Reply != nil {
		res.Reply.ID = env.ID
		h.send(sess, *res.Reply)
	}
	h.disbandAndFanout(r, res.Broadcast)
	retained = h.snapshotRoomRetention(r)
	cleanup = h.removeRoom(r)
	return nil
}

func (h *Handler) handleDeckSelect(sess *Session, env protocol.Envelope) error {
	r := sess.Room()
	if r == nil {
		h.sendError(sess, env.ID, protocol.ErrNotInRoom, "not in a room")
		return nil
	}
	var deck protocol.DeckSelect
	if err := env.DecodePayload(&deck); err != nil {
		h.sendError(sess, env.ID, protocol.ErrInvalidMessage, err.Error())
		return nil
	}
	if r.DeckFormat == protocol.DeckFormatLimited {
		h.sendError(sess, env.ID, protocol.ErrTournamentForbidden,
			"limited tournament decks are locked by the event")
		return nil
	}
	operation, err := h.hub.lockRoomOperation(r.ID)
	if err != nil {
		code, _ := ErrCode(err)
		h.sendError(sess, env.ID, code, err.Error())
		return nil
	}
	defer operation.opMu.Unlock()
	res, err := h.hub.SelectDeck(sess.ConnectionID, deck, r)
	if err != nil {
		code, _ := ErrCode(err)
		if code == "" {
			code = protocol.ErrInvalidMessage
		}
		h.sendError(sess, env.ID, code, err.Error())
		return nil
	}
	h.recordTournamentDeck(sess, r, deck)
	res.Reply.ID = env.ID
	h.send(sess, *res.Reply)
	h.fanout(r, res.Broadcast)
	return nil
}

func (h *Handler) handlePlayerReady(sess *Session, env protocol.Envelope) error {
	r := sess.Room()
	if r == nil {
		h.sendError(sess, env.ID, protocol.ErrNotInRoom, "not in a room")
		return nil
	}
	var request protocol.PlayerReady
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
	res, err := h.hub.SetReady(sess.ConnectionID, request.Ready, r)
	if err != nil {
		code, _ := ErrCode(err)
		if code == "" {
			code = protocol.ErrInvalidMessage
		}
		h.sendError(sess, env.ID, code, err.Error())
		h.fanout(r, res.Broadcast)
		return nil
	}
	var rulesState forgeStartState
	if res.StartRulesGame {
		rulesState, err = h.startForgeGame(r)
		if err != nil {
			rollback, rollbackErr := h.hub.ResetRulesStartFailure(r)
			if rollbackErr != nil {
				h.failClosedGameProjections(r, rollbackErr)
				return nil
			}
			h.sendError(sess, env.ID, protocol.ErrRulesUnavailable,
				"Forge could not start this match")
			h.fanout(r, rollback.Broadcast)
			return nil
		}
	}
	res.Reply.ID = env.ID
	h.send(sess, *res.Reply)
	h.fanout(r, res.Broadcast)
	if res.ProjectGame {
		h.fanoutGameProjections(r)
	}
	if res.StartRulesGame {
		h.sendRulesProjections(rulesState.projections)
		h.sendRulesPrompts(rulesState.prompts)
	}
	return nil
}

func (h *Handler) handleClientLoadComplete(sess *Session, env protocol.Envelope) error {
	r := sess.Room()
	if r == nil {
		h.sendError(sess, env.ID, protocol.ErrNotInRoom, "not in a room")
		return nil
	}
	var request protocol.ClientLoadComplete
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
	res, err := h.hub.CompleteLoad(sess.ConnectionID, request.LoadID, r)
	if err != nil {
		code, _ := ErrCode(err)
		if code == "" {
			code = protocol.ErrInvalidMessage
		}
		h.sendError(sess, env.ID, code, err.Error())
		h.fanout(r, res.Broadcast)
		return nil
	}
	var rulesState forgeStartState
	if res.StartRulesGame {
		rulesState, err = h.startForgeGame(r)
		if err != nil {
			rollback, rollbackErr := h.hub.ResetRulesStartFailure(r)
			if rollbackErr != nil {
				h.failClosedGameProjections(r, rollbackErr)
				return nil
			}
			h.sendError(sess, env.ID, protocol.ErrRulesUnavailable,
				"Forge could not start this match")
			h.fanout(r, rollback.Broadcast)
			return nil
		}
	}
	if res.Reply != nil {
		res.Reply.ID = env.ID
		h.send(sess, *res.Reply)
	}
	h.fanout(r, res.Broadcast)
	if res.ProjectGame {
		h.fanoutGameProjections(r)
	}
	if res.StartRulesGame {
		h.sendRulesProjections(rulesState.projections)
		h.sendRulesPrompts(rulesState.prompts)
	}
	return nil
}

func (h *Handler) snapshotRoomRetention(r *room.Room) *retainedRoom {
	// Every caller holds the room operation lock. Take the state lock as well so
	// retention does not depend on the implicit invariant that all future room
	// writers will also participate in operation ordering.
	entry := h.hub.roomEntryFor(r.ID)
	if entry == nil || entry.room != r {
		return nil
	}
	entry.mu.Lock()
	defer entry.mu.Unlock()
	return h.retention.snapshot(r, time.Now().UTC())
}

func (h *Handler) saveRoomRetention(record *retainedRoom) {
	if record == nil {
		return
	}
	if err := h.retention.saveSnapshot(record); err != nil {
		log.Printf("retention %s: %v", record.RoomID, err)
	}
}

func (h *Handler) removeRoomIfEmpty(r *room.Room) (*retainedRoom, pairingRoomCleanup) {
	entry := h.hub.roomEntryFor(r.ID)
	if entry == nil || entry.room != r {
		return nil, pairingRoomCleanup{}
	}
	entry.mu.Lock()
	if r.PlayerCount() != 0 || len(r.Spectators) != 0 {
		entry.mu.Unlock()
		return nil, pairingRoomCleanup{}
	}
	record := h.retention.snapshot(r, time.Now().UTC())
	entry.mu.Unlock()
	return record, h.removeRoom(r)
}

type pairingRoomCleanup struct {
	tournamentID string
	roomID       string
}

func (c pairingRoomCleanup) pending() bool {
	return c.tournamentID != "" && c.roomID != ""
}

// commitPairingRoomCleanup records that a deleted pairing room is gone. The
// caller must not hold room opMu: this takes tournament opMu first.
func (h *Handler) commitPairingRoomCleanup(cleanup pairingRoomCleanup) {
	if !cleanup.pending() {
		return
	}
	entry, err := h.tournaments.lockOperation(cleanup.tournamentID)
	if err != nil {
		return
	}
	defer entry.opMu.Unlock()
	h.tournaments.clearRoomLocked(entry, cleanup.roomID)
}

// removeRoom drops the authoritative room and clears every room-scoped
// transient. Their timer callbacks may already be running, but the registry
// removal makes those callbacks fail closed at lockRoomOperation.
// Pairing RoomID updates are returned for commitPairingRoomCleanup after
// room opMu is released.
func (h *Handler) removeRoom(r *room.Room) pairingRoomCleanup {
	if r == nil {
		return pairingRoomCleanup{}
	}
	cleanup := pairingRoomCleanup{
		tournamentID: h.hub.TournamentForRoom(r),
		roomID:       r.ID,
	}
	h.hub.RemoveRoom(r.ID)
	h.abortForgeGame(r.ID)

	h.sideboardTimerMu.Lock()
	timer := h.sideboardTimers[r.ID]
	delete(h.sideboardTimers, r.ID)
	h.sideboardTimerMu.Unlock()
	if timer != nil {
		timer.Stop()
	}

	h.zoneDumpMu.Lock()
	for approvalID, request := range h.zoneDumpRequests {
		if request.roomID == r.ID {
			delete(h.zoneDumpRequests, approvalID)
		}
	}
	h.zoneDumpMu.Unlock()

	h.publicZoneMoveMu.Lock()
	for approvalID, request := range h.publicZoneMoveRequests {
		if request.roomID == r.ID {
			delete(h.publicZoneMoveRequests, approvalID)
		}
	}
	h.publicZoneMoveMu.Unlock()

	h.resumeMu.Lock()
	for token, hold := range h.resumeHolds {
		if hold.room == r || (hold.room != nil && hold.room.ID == r.ID) {
			delete(h.resumeHolds, token)
		}
	}
	h.resumeMu.Unlock()
	return cleanup
}

// fanout sends each broadcast envelope to every member of the room. Membership
// is snapshotted under the hub's room entry lock via the room state.
func (h *Handler) fanout(r *room.Room, envelopes []protocol.Envelope) {
	h.fanoutTo(h.membersOf(r), envelopes)
}

func (h *Handler) fanoutGameProjections(r *room.Room) {
	if r != nil && r.RulesMode == protocol.RulesModeForge {
		h.fanoutRulesProjections(r)
		return
	}
	projections, err := h.hub.GameProjections(r)
	if err != nil {
		h.failClosedGameProjections(r, err)
		return
	}
	for connID, envelope := range projections {
		if session := h.sessionByConn(connID); session != nil {
			h.send(session, envelope)
		}
	}
}

// failClosedGameProjections is used after the reducer has already committed.
// Members receive an unsolicited internal error (no command id, so a prior
// success reply is not rolled back) and are disconnected so reconnect can
// load a fresh role-specific snapshot.
func (h *Handler) failClosedGameProjections(r *room.Room, cause error) {
	if r == nil {
		log.Printf("game projections failed: %v", cause)
		return
	}
	log.Printf("game projections failed for room %s: %v", r.ID, cause)
	for _, sess := range h.sessionsForRoomPointer(r) {
		h.failClosedSession(sess, cause)
	}
}

// sessionsForRoomPointer resolves members from the room pointer rather than a
// registry lookup, so a room that was already removed still yields the members
// that must be failed closed. Membership is read under the room state lock when
// the registry still holds this exact room, matching membersOf.
func (h *Handler) sessionsForRoomPointer(r *room.Room) []*Session {
	if r == nil {
		return nil
	}
	entry := h.hub.roomEntryFor(r.ID)
	if entry != nil && entry.room == r {
		entry.mu.Lock()
		defer entry.mu.Unlock()
	}
	seen := make(map[string]struct{})
	var out []*Session
	add := func(connID string) {
		if connID == "" {
			return
		}
		if _, ok := seen[connID]; ok {
			return
		}
		seen[connID] = struct{}{}
		if sess := h.sessionByConn(connID); sess != nil {
			out = append(out, sess)
		}
	}
	for _, seat := range r.Seats {
		if seat.Occupied {
			add(seat.ConnectionID)
		}
	}
	for _, spectator := range r.Spectators {
		add(spectator.ConnectionID)
	}
	return out
}

// disbandAndFanout clears every remaining member's server-side room binding
// before delivering the terminal event. Clients may then immediately create or
// join another room after processing room.disbanded.
func (h *Handler) disbandAndFanout(r *room.Room, envelopes []protocol.Envelope) {
	members := h.membersOf(r)
	for _, member := range members {
		member.setRoom(nil)
	}
	h.fanoutTo(members, envelopes)
}

func (h *Handler) fanoutTo(members []*Session, envelopes []protocol.Envelope) {
	if len(envelopes) == 0 {
		return
	}
	for _, env := range envelopes {
		data, err := h.sessionEnvelopeBytes(env)
		if err != nil {
			// The reducer transition is already committed, so a dropped
			// broadcast desyncs every member. Disconnect so reconnect can
			// load a fresh projection.
			log.Printf("fanout: marshal %s failed: %v", env.Type, err)
			for _, member := range members {
				h.failClosedSession(member, err)
			}
			return
		}
		for _, m := range members {
			if !m.trySend(data) {
				log.Printf("fail-closed session %s: send buffer full or already closed",
					m.ConnectionID)
			}
		}
	}
}

// membersOf returns live sessions occupying seats or spectator slots. It
// queries the hub's session registry; at P1 sessions are tracked via the room
// state's ConnectionIDs, so we map back through the hub.
func (h *Handler) membersOf(r *room.Room) []*Session {
	h.hub.mu.Lock()
	entry := h.hub.rooms[r.ID]
	h.hub.mu.Unlock()
	if entry == nil {
		return nil
	}
	entry.mu.Lock()
	defer entry.mu.Unlock()

	var out []*Session
	for i := range entry.room.Seats {
		if entry.room.Seats[i].Occupied {
			if s := h.sessionByConn(entry.room.Seats[i].ConnectionID); s != nil {
				out = append(out, s)
			}
		}
	}
	for _, sp := range entry.room.Spectators {
		if s := h.sessionByConn(sp.ConnectionID); s != nil {
			out = append(out, s)
		}
	}
	return out
}

func remoteIP(remoteAddress string) string {
	host, _, err := net.SplitHostPort(remoteAddress)
	if err == nil {
		return host
	}
	return remoteAddress
}

func parseTrustedProxies(cidrs []string) ([]*net.IPNet, error) {
	proxies := make([]*net.IPNet, 0, len(cidrs))
	for _, raw := range cidrs {
		trimmed := strings.TrimSpace(raw)
		if trimmed == "" {
			continue
		}
		_, network, err := net.ParseCIDR(trimmed)
		if err != nil {
			return nil, fmt.Errorf("invalid trusted proxy CIDR %q: %w", trimmed, err)
		}
		proxies = append(proxies, network)
	}
	return proxies, nil
}

func clientIP(request *http.Request, trustedProxies []*net.IPNet) string {
	peer := remoteIP(request.RemoteAddr)
	peerIP := net.ParseIP(peer)
	if !isTrustedProxy(peerIP, trustedProxies) {
		return peer
	}

	// Walk the append-mode forwarding chain from the trusted connection
	// backwards. The first untrusted hop is the client address supplied by the
	// nearest trusted proxy; a client-controlled leftmost value cannot override
	// it.
	forwarded := strings.Split(request.Header.Get("X-Forwarded-For"), ",")
	client := peer
	for index := len(forwarded) - 1; index >= 0; index-- {
		candidate := net.ParseIP(strings.TrimSpace(forwarded[index]))
		if candidate == nil {
			return peer
		}
		client = candidate.String()
		if !isTrustedProxy(candidate, trustedProxies) {
			return client
		}
	}
	return client
}

func isTrustedProxy(ip net.IP, trustedProxies []*net.IPNet) bool {
	for _, network := range trustedProxies {
		if ip != nil && network.Contains(ip) {
			return true
		}
	}
	return false
}

func (h *Handler) allowRoomCreate(ip string, now time.Time) bool {
	return h.roomCreateLimiter.allow(ip, now, h.config.RoomCreatesPerMinute)
}

func (h *Handler) allowPasswordJoin(ip string, now time.Time) bool {
	return h.passwordJoinLimiter.allow(ip, now, h.config.PasswordJoinsPerMinute)
}
