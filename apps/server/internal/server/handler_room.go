// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package server

import (
	"fmt"
	"hexproof/server/internal/forgehost"
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
	h.evictExpiredTournaments(time.Now().UTC())
	listed, _ := protocol.NewEnvelope(protocol.TypeRoomListed,
		protocol.RoomListed{Rooms: h.listRooms(sess)})
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
	if sess.Room() != nil || h.cubeRoomBlocksNavigation(sess, "") {
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
	if rc.DeckFormat == protocol.DeckFormatCommanderLimited || !protocol.ValidDeckFormat(rc.DeckFormat) ||
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
	if rc.HostingMode != "" && rc.HostingMode != "server" && rc.HostingMode != "player" {
		h.sendError(sess, env.ID, protocol.ErrInvalidMessage, "invalid hosting mode")
		return nil
	}
	if rc.HostingMode == "player" && (rc.RulesMode != protocol.RulesModeForge || rc.Playtest || maxSeats != 2 || !h.config.AllowPlayerHosting) {
		h.sendError(sess, env.ID, protocol.ErrRulesUnavailable, "Player hosting requires an enabled server and a two-player Forge room")
		return nil
	}
	if rc.RulesMode == protocol.RulesModeForge && rc.HostingMode != "player" && !h.forgeRulesAvailable() {
		h.sendError(sess, env.ID, protocol.ErrRulesUnavailable,
			"Forge rules mode is not available on this server")
		return nil
	}
	if rc.AISource == "" && rc.AIDifficulty != "" {
		rc.AISource = protocol.AISourceForge
	}
	if rc.AISource != "" {
		if !protocol.ValidAIConfiguration(rc.AISource, rc.AIDifficulty) || rc.RulesMode != protocol.RulesModeForge ||
			rc.Format != protocol.FormatModern || rc.MatchMode != protocol.MatchBO1 || rc.Playtest ||
			rc.DeckFormat == protocol.DeckFormatCube || rc.DeckFormat == protocol.DeckFormatLimited {
			h.sendError(sess, env.ID, protocol.ErrInvalidMessage, "AI practice requires a two-player constructed Forge BO1 room")
			return nil
		}
		if rc.AISource == protocol.AISourceForge && rc.HostingMode != "player" && !h.forgeAIAvailable() {
			h.sendError(sess, env.ID, protocol.ErrRulesUnavailable, "This runtime does not support Forge AI")
			return nil
		}
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
	r, initialSnapshot, initialSeq, operation, err := h.hub.createRoom(
		rc.Name, rc.Format, rc.DeckFormat, rc.MatchMode, rc.CardLoadMode, rc.RulesMode, rc.HostingMode,
		maxSeats, rc.AllowSpectators, rc.SpectatorsSeeHands, rc.Password, "", "", "", sess, rc.AIDifficulty, rc.AISource)
	if err != nil {
		code, _ := ErrCode(err)
		if code == "" {
			code = protocol.ErrInvalidMessage
		}
		h.sendError(sess, env.ID, code, err.Error())
		return nil
	}
	defer operation.opMu.Unlock()
	var hostLink *forgehost.Link
	if r.HostingMode == "player" {
		hostLink = h.allocatePlayerHost(r)
		if hostLink == nil {
			h.removeRoom(r)
			sess.setRoom(nil)
			h.sendError(sess, env.ID, protocol.ErrServerLimit, "player hosting capacity is full")
			return nil
		}
	}
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
			HostingMode:        r.HostingMode,
			AIDifficulty:       r.AIDifficulty,
			AISource:           r.AISource,
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
	h.grantModelWorker(sess, r)
	if hostLink != nil {
		h.sendPlayerHostGrant(sess, hostLink, "")
	}
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
	if h.isCubeRoom(rj.RoomID) {
		return h.handleCubeRoomJoin(sess, env, rj)
	}
	destinationPodID := h.hub.TournamentForRoom(h.hub.FindRoom(rj.RoomID))
	if h.cubeRoomBlocksNavigation(sess, destinationPodID) {
		h.sendError(sess, env.ID, protocol.ErrAlreadyInRoom, "leave the current Cube room first")
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
	if operation.tournamentID != "" && !rj.AsSpectator {
		h.sendError(sess, env.ID, protocol.ErrTournamentForbidden,
			"paired players must join this match from the tournament")
		return nil
	}
	if operation.room.HostingMode == "player" && !rj.AcceptPlayerHost {
		h.sendError(sess, env.ID, protocol.ErrPlayerHostTrustRequired, "This game runs on the creator's computer. Join only if you trust the host.")
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
	if res.ProjectGame && rj.AsSpectator &&
		r.RulesMode == protocol.RulesModeManual {
		roomSnapshotIndex, seq := lastRoomSnapshotSequence(res.Broadcast)
		if roomSnapshotIndex < 0 || seq <= 0 {
			h.fanout(r, res.Broadcast)
			h.failClosedSession(sess,
				fmt.Errorf("manual spectator join has no sequenced room snapshot"))
			return nil
		}
		h.fanout(r, res.Broadcast[:roomSnapshotIndex+1])
		h.sendGameProjection(r, sess, seq)
		h.fanout(r, res.Broadcast[roomSnapshotIndex+1:])
		return nil
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
		h.refreshTournamentRetention(operation.tournamentID)
	}()
	operation.mu.Lock()
	departingCubePlayer := operation.room == r && operation.tournamentID != "" &&
		(r.DeckFormat != protocol.DeckFormatCommanderLimited || r.Game == nil || r.Game.Result != nil) &&
		r.FindSeatByConnection(sess.ConnectionID) >= 0
	departingForgePlayer := operation.room == r &&
		r.RulesMode == protocol.RulesModeForge &&
		r.Phase == protocol.RoomPhaseStarted &&
		r.FindSeatByConnection(sess.ConnectionID) >= 0
	operation.mu.Unlock()
	departingCubePlayer = departingCubePlayer && h.isCubeRoom(operation.tournamentID)
	res, disbanded, err := h.hub.LeaveRoom(sess.ConnectionID, r)
	if err != nil {
		code, _ := ErrCode(err)
		h.sendError(sess, env.ID, code, err.Error())
		return nil
	}
	h.discardFinishedGameConsent(r)
	if departingCubePlayer && !disbanded {
		// Either player leaving ordinary Cube closes its two-player table.
		// Commander Cube closes only before play or after the result; an active
		// departure forfeits that seat and leaves the other players in the game.
		// Transport disconnects still use the ordinary reconnect hold.
		operation.mu.Lock()
		r.Disbanded = true
		seq := r.AllocSeq()
		operation.mu.Unlock()
		closed, _ := protocol.NewEnvelope(protocol.TypeRoomDisbanded, protocol.RoomLeft{RoomID: r.ID})
		res.Broadcast = []protocol.Envelope{closed.WithSeq(seq)}
		disbanded = true
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
	h.discardFinishedGameConsent(r)
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
	if r.DeckFormat == protocol.DeckFormatLimited || r.DeckFormat == protocol.DeckFormatCommanderLimited {
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
	if request.Ready && h.playerHostPaused(r) {
		h.sendError(sess, env.ID, protocol.ErrRulesActionRejected, "Wait for the creator to connect local Forge")
		return nil
	}
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
			h.fanout(r, rollback.Broadcast)
			h.sendForgeStartFailure(r, sess, env.ID, err)
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
			h.fanout(r, rollback.Broadcast)
			h.sendForgeStartFailure(r, sess, env.ID, err)
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
	entry.mu.Lock()
	casual := entry.event.Coordinator == protocol.LimitedCoordinatorCasual
	entry.mu.Unlock()
	if casual {
		// Closing a free-play table releases its players. Publish immediately
		// so the organizer can choose them without leaving/re-entering the lobby.
		h.fanoutTournament(cleanup.tournamentID)
	} else {
		h.reconcileTournamentRetentionLocked(cleanup.tournamentID, entry, time.Now().UTC(), false)
	}
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
	h.revokeModelWorker(r.ID)
	h.revokePlayerHost(r.ID)
	h.hub.RemoveRoom(r.ID)
	h.abortForgeGame(r.ID)
	h.cancelSideboardExpiration(r.ID)

	h.discardRoomConsentRequests(r.ID)

	h.resumeMu.Lock()
	for token, hold := range h.resumeHolds {
		if hold.room == r || (hold.room != nil && hold.room.ID == r.ID) {
			delete(h.resumeHolds, token)
		}
	}
	h.resumeMu.Unlock()
	return cleanup
}

// fanout sends public broadcasts to every room member. Tournament deck-art
// manifests are player-only because their union of printing identities reveals
// unpublished deck contents. Membership is snapshotted under the room lock.
func (h *Handler) fanout(r *room.Room, envelopes []protocol.Envelope) {
	members, players := h.roomAudiences(r)
	if h.hub.TournamentForRoom(r) == "" {
		h.fanoutTo(members, envelopes)
		return
	}
	for _, envelope := range envelopes {
		targets := members
		if envelope.Type == protocol.TypeMatchLoadRequired {
			targets = players
		}
		h.fanoutTo(targets, []protocol.Envelope{envelope})
	}
}

func (h *Handler) fanoutGameProjections(r *room.Room) {
	if r != nil && r.RulesMode == protocol.RulesModeForge {
		if _, live := h.forgeGame(r.ID); !live && r.Game != nil {
			h.fanoutRulesMetadata(r)
			h.fanoutRulesReview(r)
			return
		}
		h.fanoutRulesProjections(r)
		return
	}
	projections, err := h.hub.GameProjections(r)
	if err != nil {
		h.failClosedGameProjections(r, err)
		return
	}
	h.sendProjectionSet(projections)
}

func (h *Handler) sendGameProjection(r *room.Room, sess *Session, seq int64) {
	projection, err := h.hub.GameProjection(r, sess.ConnectionID, seq)
	if err != nil {
		h.failClosedSession(sess, err)
		return
	}
	h.send(sess, projection)
}

func lastRoomSnapshotSequence(envelopes []protocol.Envelope) (int, int64) {
	for index := len(envelopes) - 1; index >= 0; index-- {
		if envelopes[index].Type == protocol.TypeRoomSnapshot {
			return index, envelopes[index].SeqValue()
		}
	}
	return -1, 0
}

// failClosedGameProjections is used after the reducer has already committed.
// Members receive an unsolicited internal error (no command id, so a prior
// success reply is not rolled back) and are disconnected so reconnect can
// load a fresh role-specific snapshot.
func (h *Handler) failClosedGameProjections(r *room.Room, cause error) {
	if r != nil && r.RulesMode == protocol.RulesModeForge {
		h.failForgeGame(r)
		return
	}
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
	members, _ := h.roomAudiences(r)
	return members
}

// roomAudiences returns all live members plus the player-only subset from one
// room-state read. Tournament pairing rooms use the latter for deck-art load
// manifests, which identify every registered printing and are not public
// spectator data while an event is running.
func (h *Handler) roomAudiences(r *room.Room) ([]*Session, []*Session) {
	h.hub.mu.Lock()
	entry := h.hub.rooms[r.ID]
	h.hub.mu.Unlock()
	if entry == nil {
		return nil, nil
	}
	entry.mu.Lock()
	defer entry.mu.Unlock()

	var members []*Session
	var players []*Session
	for i := range entry.room.Seats {
		if entry.room.Seats[i].Occupied {
			if s := h.sessionByConn(entry.room.Seats[i].ConnectionID); s != nil {
				members = append(members, s)
				players = append(players, s)
			}
		}
	}
	for _, sp := range entry.room.Spectators {
		if s := h.sessionByConn(sp.ConnectionID); s != nil {
			members = append(members, s)
		}
	}
	return members, players
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
