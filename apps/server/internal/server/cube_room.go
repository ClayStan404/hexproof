// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package server

import (
	"sort"
	"time"

	"hexproof/server/internal/protocol"
	"hexproof/server/internal/tournament"
)

// Cube pods and gameplay tables share one six-character discovery namespace.
// Reservations are atomic with ordinary room allocation and count toward the
// same room capacity. The event registry separately bounds retained pods.
func (h *Hub) reserveCubeRoomID(id string) error {
	h.mu.Lock()
	defer h.mu.Unlock()
	if h.rooms[id] != nil || h.reservedRoomIDs[id] {
		return &protocolError{code: protocol.ErrInternal, message: "room id collision"}
	}
	if h.maxRooms > 0 && len(h.rooms)+len(h.reservedRoomIDs) >= h.maxRooms {
		return &protocolError{code: protocol.ErrServerLimit, message: "maximum rooms reached"}
	}
	h.reservedRoomIDs[id] = true
	return nil
}

func (h *Hub) releaseCubeRoomID(id string) {
	h.mu.Lock()
	delete(h.reservedRoomIDs, id)
	h.mu.Unlock()
}

func (h *Handler) isCubeRoom(id string) bool {
	entry := h.tournaments.entry(id)
	if entry == nil {
		return false
	}
	entry.mu.Lock()
	defer entry.mu.Unlock()
	return entry.event.IsCubeRoom()
}

// A Cube pod is a room, not a background event subscription. Crossing into
// another room/event must follow an explicit leave so a host cannot silently
// abandon an occupied pod. Table entry within this pod keeps its membership.
func (h *Handler) cubeRoomBlocksNavigation(sess *Session, destinationPodID string) bool {
	binding := sess.Tournament()
	if binding.TournamentID == "" || binding.TournamentID == destinationPodID {
		return false
	}
	entry := h.tournaments.entry(binding.TournamentID)
	if entry == nil {
		return false
	}
	entry.mu.Lock()
	defer entry.mu.Unlock()
	if !entry.event.IsCubeRoom() || entry.event.IsTerminal() {
		return false
	}
	sess.tournamentMu.RLock()
	_, current := tournamentProjectionIdentity(entry.event, sess, binding)
	sess.tournamentMu.RUnlock()
	return current
}

func (h *Handler) cubeViewerCount(id string) int {
	h.sessionsMu.RLock()
	defer h.sessionsMu.RUnlock()
	count := 0
	for _, sess := range h.sessions {
		binding := sess.Tournament()
		if binding.TournamentID == id && binding.Role == tournament.RoleViewer {
			count++
		}
	}
	return count
}

func (h *Handler) listRooms(sess *Session) []protocol.RoomListEntry {
	rooms := h.hub.ListRooms()
	for _, entry := range h.tournaments.snapshot() {
		entry.mu.Lock()
		event := entry.event
		if !event.IsCubeRoom() || event.IsTerminal() {
			entry.mu.Unlock()
			continue
		}
		phase := event.Stage
		if phase == protocol.LimitedStageRegistration {
			phase = protocol.RoomPhaseWaiting
		} else if phase == protocol.LimitedStageCompetition {
			phase = protocol.RoomPhaseFreePlay
		}
		joinable := event.Status == tournament.StatusRegistration && len(event.Participants) < event.MaxPlayers
		for _, participant := range event.Participants {
			if participant.ConnectionID == sess.ConnectionID {
				joinable = true
				break
			}
		}
		spectators := h.cubeViewerCount(event.ID)
		format := protocol.FormatModern
		if event.IsCommanderCube() {
			format = protocol.FormatEDH
		}
		rooms = append(rooms, protocol.RoomListEntry{
			RoomID: event.ID, RoomKind: "cube", Name: event.Name, Format: format,
			DeckFormat: protocol.DeckFormatCube, MatchMode: event.MatchMode,
			CardLoadMode: protocol.CardLoadBackground, RulesMode: event.RulesMode,
			MaxSeats: event.MaxPlayers, PlayerCount: len(event.Participants),
			Phase: phase, PlayerJoinable: joinable, AllowSpectators: true,
			SpectatorCount: spectators, SpectatorJoinable: spectators < protocol.MaxSpectators,
		})
		entry.mu.Unlock()
	}
	sort.Slice(rooms, func(i, j int) bool { return rooms[i].RoomID < rooms[j].RoomID })
	return rooms
}

func (h *Handler) handleCubeRoomJoin(sess *Session, env protocol.Envelope, request protocol.RoomJoin) error {
	if sess.DisplayName == "" {
		h.sendError(sess, env.ID, protocol.ErrNameRequired, "hello first")
		return nil
	}
	if h.cubeRoomBlocksNavigation(sess, request.RoomID) {
		h.sendError(sess, env.ID, protocol.ErrAlreadyInRoom, "leave the current Cube room first")
		return nil
	}
	currentRoom := sess.Room()
	if currentRoom != nil && env.Type != protocol.TypeTournamentEnter {
		h.sendError(sess, env.ID, protocol.ErrAlreadyInRoom, "leave the current table first")
		return nil
	}
	if !request.AsSpectator && len(request.Credential) > protocol.MaxResumeTokenBytes {
		h.sendError(sess, env.ID, protocol.ErrTournamentForbidden, "invalid Cube room credential")
		return nil
	}
	entry, err := h.tournaments.lockOperation(request.RoomID)
	if err != nil {
		sendTournamentError(h, sess, env.ID, err)
		return nil
	}
	previousID := ""
	defer func() {
		entry.opMu.Unlock()
		h.refreshTournament(previousID)
	}()
	var table *roomEntry
	if currentRoom != nil {
		table, err = h.hub.lockRoomOperation(currentRoom.ID)
		if err != nil {
			sendTournamentError(h, sess, env.ID, err)
			return nil
		}
		defer func() {
			if table != nil {
				table.opMu.Unlock()
			}
		}()
	}
	entry.mu.Lock()
	event := entry.event
	if !event.IsCubeRoom() || event.IsTerminal() {
		entry.mu.Unlock()
		h.sendError(sess, env.ID, protocol.ErrRoomNotFound, "Cube room has closed")
		return nil
	}
	role, participantID, token := tournament.RoleParticipant, "", ""
	previous := sess.Tournament()
	tableSpectator := false
	if table != nil {
		table.mu.Lock()
		seat := table.room.FindSeatByConnection(sess.ConnectionID)
		tableSpectator = table.room.IsSpectator(sess.ConnectionID)
		validTable := table.room == currentRoom && table.tournamentID == request.RoomID &&
			!table.room.Disbanded && (seat >= 0 || tableSpectator)
		if validTable && seat >= 0 {
			expectedID := table.room.Seats[seat].TournamentParticipantID
			credentialID := ""
			if request.Credential != "" {
				hash := tournament.CredentialHash(request.Credential)
				if hash == event.OrganizerCredential {
					credentialID = event.OrganizerParticipantID
				} else {
					for _, participant := range event.Participants {
						if participant.CredentialHash == hash {
							credentialID = participant.ID
							break
						}
					}
				}
			} else {
				sess.tournamentMu.RLock()
				privateID, valid := tournamentProjectionIdentity(event, sess, previous)
				sess.tournamentMu.RUnlock()
				if valid {
					credentialID = privateID
				}
			}
			validTable = expectedID != "" && expectedID == credentialID
		}
		table.mu.Unlock()
		if !validTable {
			entry.mu.Unlock()
			h.sendError(sess, env.ID, protocol.ErrTournamentForbidden, "Cube identity does not match the current table seat")
			return nil
		}
	}
	if request.AsSpectator {
		// Explicit viewing never binds a saved credential or consumes a draft
		// seat. The resulting pool and pack projections stay public-only.
		role = tournament.RoleViewer
	} else if request.Credential != "" {
		var ok bool
		role, participantID, ok = event.BindCredential(tournament.CredentialHash(request.Credential),
			sess.ConnectionID, time.Now().UTC())
		if !ok || participantID == "" {
			entry.mu.Unlock()
			h.sendError(sess, env.ID, protocol.ErrTournamentForbidden, "invalid Cube room credential")
			return nil
		}
	} else if previous.TournamentID == event.ID {
		sess.tournamentMu.RLock()
		privateID, valid := tournamentProjectionIdentity(event, sess, previous)
		sess.tournamentMu.RUnlock()
		if valid && privateID != "" {
			role, participantID = previous.Role, privateID
		}
	}
	publicEntry := request.AsSpectator || tableSpectator ||
		(env.Type == protocol.TypeTournamentEnter && request.Credential == "" && participantID == "")
	if publicEntry && !tableSpectator &&
		!(previous.TournamentID == event.ID && previous.Role == tournament.RoleViewer) &&
		h.cubeViewerCount(event.ID) >= protocol.MaxSpectators {
		entry.mu.Unlock()
		h.sendError(sess, env.ID, protocol.ErrSpectatorLimit, "Cube room spectator limit reached")
		return nil
	}
	if publicEntry && participantID == "" {
		role = tournament.RoleViewer
	}
	// Restoring an authenticated participant's own pool does not change the
	// spectator role at the game table or expose either opponent's hand. A
	// spectator without a participant credential receives only public state.
	if participantID == "" && !publicEntry {
		token, err = genResumeToken()
		if err == nil {
			var participant *tournament.Participant
			participant, err = event.Register(sess.DisplayName, sess.ConnectionID,
				tournament.CredentialHash(token), time.Now().UTC())
			if err == nil {
				participantID = participant.ID
			}
		}
		if err != nil {
			entry.mu.Unlock()
			sendTournamentError(h, sess, env.ID, err)
			return nil
		}
	}
	entry.mu.Unlock()
	if previous.TournamentID != "" && previous.TournamentID != request.RoomID {
		previousID = h.detachTournamentSession(sess)
	}
	sess.setTournament(tournamentBinding{TournamentID: request.RoomID, Role: role, ParticipantID: participantID})
	entered, _ := protocol.NewEnvelope(protocol.TypeTournamentEntered, protocol.TournamentEntered{
		TournamentID: request.RoomID, Role: role, ParticipantID: participantID,
	})
	entered.ID = env.ID
	h.send(sess, entered)
	if token != "" {
		registered, _ := protocol.NewEnvelope(protocol.TypeTournamentRegistered, protocol.TournamentRegistered{
			TournamentID: request.RoomID, ParticipantID: participantID, ParticipantToken: token,
		})
		h.send(sess, registered)
	}
	h.sendTournamentChatHistory(sess)
	// Retention reconciliation can lock every table in this pod. Release the
	// validated current table before fanout while retaining the pod operation.
	if table != nil {
		table.opMu.Unlock()
		table = nil
	}
	h.fanoutTournament(request.RoomID)
	return nil
}

func (h *Handler) handleCubeRoomLeave(sess *Session, env protocol.Envelope) error {
	binding := sess.Tournament()
	entry, err := h.tournaments.lockOperation(binding.TournamentID)
	if err != nil {
		sendTournamentError(h, sess, env.ID, err)
		return nil
	}
	defer entry.opMu.Unlock()
	entry.mu.Lock()
	sess.tournamentMu.RLock()
	_, valid := tournamentProjectionIdentity(entry.event, sess, binding)
	sess.tournamentMu.RUnlock()
	if !valid {
		entry.mu.Unlock()
		h.sendError(sess, env.ID, protocol.ErrTournamentForbidden, "Cube seat is not owned by this session")
		return nil
	}
	host := binding.Role == tournament.RoleOrganizer
	if !host && sess.Room() != nil {
		entry.mu.Unlock()
		h.sendError(sess, env.ID, protocol.ErrAlreadyInRoom, "leave the table before leaving the Cube room")
		return nil
	}
	if host {
		err = entry.event.Cancel(tournamentActor(sess), time.Now().UTC())
	} else if binding.Role != tournament.RoleViewer && entry.event.Status == tournament.StatusRegistration {
		err = entry.event.Unregister(tournamentActor(sess))
	} else if binding.Role != tournament.RoleViewer {
		// Explicit pod departure releases an unopened initial table just like
		// an invitation. Transport loss instead retains its one-shot entry.
		if pairing := entry.event.CurrentPairing(binding.ParticipantID); pairing != nil && pairing.RoomID == "" {
			if entry.event.IsCommanderCube() {
				err = entry.event.CommanderCubeMatch(tournamentActor(sess), protocol.LimitedCreateCasualMatch{
					Action: "cancel", PairingID: pairing.ID,
				})
			} else {
				err = entry.event.CancelCubeMatch(tournamentActor(sess), pairing.PlayerAID, pairing.PlayerBID)
			}
		}
	}
	entry.mu.Unlock()
	if err != nil {
		sendTournamentError(h, sess, env.ID, err)
		return nil
	}
	if host {
		h.closeCubeTables(entry)
		// A Cube room has no tournament history. Deliver its final state before
		// clearing bindings, then free both registry capacity and its room code.
		h.fanoutTournament(binding.TournamentID)
		type memberBinding struct {
			session *Session
			binding tournamentBinding
		}
		members := []memberBinding{{session: sess, binding: binding}}
		h.sessionsMu.RLock()
		for _, member := range h.sessions {
			current := member.Tournament()
			if member != sess && current.TournamentID == binding.TournamentID {
				members = append(members, memberBinding{session: member, binding: current})
			}
		}
		h.sessionsMu.RUnlock()
		for _, member := range members {
			replyID := ""
			if member.session == sess {
				replyID = env.ID
			}
			h.closeTournamentMembership(entry, member.session, member.binding, replyID)
		}
		if h.tournaments.deleteIfSame(binding.TournamentID, entry) {
			h.hub.releaseCubeRoomID(binding.TournamentID)
		}
		return nil
	}
	h.detachTournamentSession(sess)
	left, _ := protocol.NewEnvelope(protocol.TypeTournamentLeft, protocol.TournamentLeft{TournamentID: binding.TournamentID})
	left.ID = env.ID
	h.send(sess, left)
	h.fanoutTournament(binding.TournamentID)
	return nil
}

// Called with the pod operation lock held; room operations follow it in the
// existing tournament-then-room lock order. No game resumes into a closed pod.
func (h *Handler) closeCubeTables(entry *tournamentEntry) {
	entry.mu.Lock()
	pairings := entry.event.VisiblePairings()
	entry.mu.Unlock()
	for _, pairing := range pairings {
		if pairing.RoomID == "" {
			continue
		}
		operation, err := h.hub.lockRoomOperation(pairing.RoomID)
		if err != nil {
			continue
		}
		operation.mu.Lock()
		r := operation.room
		r.Disbanded = true
		seq := r.AllocSeq()
		operation.mu.Unlock()
		disbanded, _ := protocol.NewEnvelope(protocol.TypeRoomDisbanded, protocol.RoomLeft{RoomID: r.ID})
		h.disbandAndFanout(r, []protocol.Envelope{disbanded.WithSeq(seq)})
		_ = h.removeRoom(r)
		operation.opMu.Unlock()
	}
	entry.mu.Lock()
	entry.event.CasualPairings = nil
	entry.mu.Unlock()
}
