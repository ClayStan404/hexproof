// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package server

import (
	"encoding/binary"
	"fmt"
	"strings"
	"time"

	"hexproof/server/internal/protocol"
	"hexproof/server/internal/room"
	"hexproof/server/internal/tournament"
)

func tournamentActor(sess *Session) tournament.Actor {
	binding := sess.Tournament()
	return tournament.Actor{
		ConnectionID:  sess.ConnectionID,
		Role:          binding.Role,
		ParticipantID: binding.ParticipantID,
	}
}

func sendTournamentError(h *Handler, sess *Session, id string, err error) {
	code := tournament.ErrorCode(err)
	message := err.Error()
	if domainError, ok := err.(*tournament.Error); ok {
		message = domainError.Message
	}
	if code == "" {
		if protocolCode, ok := ErrCode(err); ok {
			code = protocolCode
		}
	}
	if code == "" {
		code = protocol.ErrInternal
	}
	h.sendError(sess, id, code, message)
}

func (h *Handler) handleTournamentList(sess *Session, env protocol.Envelope) error {
	h.evictExpiredTournaments(time.Now().UTC())
	listed, _ := protocol.NewEnvelope(protocol.TypeTournamentListed,
		protocol.TournamentListed{Tournaments: h.tournaments.list()})
	listed.ID = env.ID
	h.send(sess, listed)
	return nil
}

func (h *Handler) handleTournamentCreate(sess *Session, env protocol.Envelope) error {
	if sess.DisplayName == "" {
		h.sendError(sess, env.ID, protocol.ErrNameRequired, "hello first")
		return nil
	}
	if sess.Room() != nil {
		h.sendError(sess, env.ID, protocol.ErrAlreadyInRoom,
			"leave the current room before creating a tournament")
		return nil
	}
	var request protocol.TournamentCreate
	if err := env.DecodePayload(&request); err != nil {
		h.sendError(sess, env.ID, protocol.ErrInvalidMessage, err.Error())
		return nil
	}
	now := time.Now().UTC()
	if !h.allowTournamentCreate(sess.RemoteIP, now) {
		h.sendError(sess, env.ID, protocol.ErrRateLimited,
			"tournament create rate limit exceeded")
		return nil
	}
	h.evictExpiredTournaments(now)
	token, err := genResumeToken()
	if err != nil {
		h.sendError(sess, env.ID, protocol.ErrInternal, "tournament credential unavailable")
		return nil
	}
	var event *tournament.Tournament
	for attempts := 0; attempts < 8; attempts++ {
		id, idErr := genTournamentID()
		if idErr != nil {
			h.sendError(sess, env.ID, protocol.ErrInternal, "tournament id unavailable")
			return nil
		}
		event, err = tournament.New(id, tournament.Config{
			Name: request.Name, Format: request.Format, MatchMode: request.MatchMode,
			RoundMinutes: request.RoundMinutes, MaxPlayers: request.MaxPlayers,
			PlannedRounds: request.PlannedRounds, EventType: request.EventType,
			Coordinator: request.Coordinator, Product: request.Product,
		}, sess.DisplayName, sess.ConnectionID, tournament.CredentialHash(token), now)
		if err != nil {
			sendTournamentError(h, sess, env.ID, err)
			return nil
		}
		if _, err = h.tournaments.create(event); err == nil {
			break
		}
		if code, _ := ErrCode(err); code == protocol.ErrServerLimit {
			h.sendError(sess, env.ID, code, err.Error())
			return nil
		}
		event = nil
	}
	if event == nil {
		h.sendError(sess, env.ID, protocol.ErrInternal, "tournament id allocation failed")
		return nil
	}
	h.detachTournamentSession(sess)
	sess.setTournament(tournamentBinding{
		TournamentID: event.ID, Role: tournament.RoleOrganizer,
	})
	created, _ := protocol.NewEnvelope(protocol.TypeTournamentCreated,
		protocol.TournamentCreated{TournamentID: event.ID, OrganizerToken: token})
	created.ID = env.ID
	h.send(sess, created)
	h.fanoutTournament(event.ID)
	return nil
}

func (h *Handler) handleTournamentEnter(sess *Session, env protocol.Envelope) error {
	var request protocol.TournamentEnter
	if err := env.DecodePayload(&request); err != nil {
		h.sendError(sess, env.ID, protocol.ErrInvalidMessage, err.Error())
		return nil
	}
	request.TournamentID = strings.ToUpper(strings.TrimSpace(request.TournamentID))
	h.evictExpiredTournaments(time.Now().UTC())
	entry, err := h.tournaments.lockOperation(request.TournamentID)
	if err != nil {
		sendTournamentError(h, sess, env.ID, err)
		return nil
	}
	defer entry.opMu.Unlock()

	previous := sess.Tournament()
	role := tournament.RoleViewer
	participantID := ""
	entry.mu.Lock()
	if request.Credential != "" {
		if len(request.Credential) > protocol.MaxResumeTokenBytes {
			entry.mu.Unlock()
			h.sendError(sess, env.ID, protocol.ErrTournamentForbidden,
				"invalid tournament credential")
			return nil
		}
		var ok bool
		role, participantID, ok = entry.event.BindCredential(
			tournament.CredentialHash(request.Credential), sess.ConnectionID, time.Now().UTC())
		if !ok {
			entry.mu.Unlock()
			h.sendError(sess, env.ID, protocol.ErrTournamentForbidden,
				"invalid tournament credential")
			return nil
		}
	}
	entry.mu.Unlock()
	if previous.TournamentID != "" && previous.TournamentID != request.TournamentID {
		h.detachTournamentSession(sess)
	}
	sess.setTournament(tournamentBinding{
		TournamentID: request.TournamentID, Role: role, ParticipantID: participantID,
	})
	entered, _ := protocol.NewEnvelope(protocol.TypeTournamentEntered,
		protocol.TournamentEntered{
			TournamentID: request.TournamentID, Role: role, ParticipantID: participantID,
		})
	entered.ID = env.ID
	h.send(sess, entered)
	h.fanoutTournament(request.TournamentID)
	return nil
}

func (h *Handler) handleTournamentLeave(sess *Session, env protocol.Envelope) error {
	binding := sess.Tournament()
	if binding.TournamentID == "" {
		h.sendError(sess, env.ID, protocol.ErrTournamentNotFound, "not viewing a tournament")
		return nil
	}
	h.detachTournamentSession(sess)
	left, _ := protocol.NewEnvelope(protocol.TypeTournamentLeft,
		protocol.TournamentLeft{TournamentID: binding.TournamentID})
	left.ID = env.ID
	h.send(sess, left)
	h.fanoutTournament(binding.TournamentID)
	h.evictExpiredTournaments(time.Now().UTC())
	return nil
}

func (h *Handler) handleTournamentRegister(sess *Session, env protocol.Envelope) error {
	var request protocol.TournamentRegister
	if err := env.DecodePayload(&request); err != nil {
		h.sendError(sess, env.ID, protocol.ErrInvalidMessage, err.Error())
		return nil
	}
	binding := sess.Tournament()
	if binding.TournamentID != request.TournamentID ||
		(binding.Role != tournament.RoleViewer && binding.Role != tournament.RoleOrganizer) ||
		binding.ParticipantID != "" {
		h.sendError(sess, env.ID, protocol.ErrTournamentForbidden,
			"enter this tournament before registering")
		return nil
	}
	token, err := genResumeToken()
	if err != nil {
		h.sendError(sess, env.ID, protocol.ErrInternal, "participant credential unavailable")
		return nil
	}
	entry, err := h.tournaments.lockOperation(binding.TournamentID)
	if err != nil {
		sendTournamentError(h, sess, env.ID, err)
		return nil
	}
	defer entry.opMu.Unlock()
	entry.mu.Lock()
	participant, registerErr := entry.event.Register(
		sess.DisplayName, sess.ConnectionID, tournament.CredentialHash(token), time.Now())
	if registerErr == nil && binding.Role == tournament.RoleOrganizer {
		entry.event.OrganizerParticipantID = participant.ID
	}
	entry.mu.Unlock()
	if registerErr != nil {
		sendTournamentError(h, sess, env.ID, registerErr)
		return nil
	}
	binding.ParticipantID = participant.ID
	if binding.Role == tournament.RoleViewer {
		binding.Role = tournament.RoleParticipant
	}
	sess.setTournament(binding)
	registered, _ := protocol.NewEnvelope(protocol.TypeTournamentRegistered,
		protocol.TournamentRegistered{
			TournamentID: binding.TournamentID, ParticipantID: participant.ID,
			ParticipantToken: token,
		})
	registered.ID = env.ID
	h.send(sess, registered)
	h.fanoutTournament(binding.TournamentID)
	return nil
}

func (h *Handler) handleTournamentUnregister(sess *Session, env protocol.Envelope) error {
	var request protocol.TournamentParticipantCommand
	if err := env.DecodePayload(&request); err != nil {
		h.sendError(sess, env.ID, protocol.ErrInvalidMessage, err.Error())
		return nil
	}
	return h.mutateTournament(sess, env, protocol.TypeTournamentUnregistered,
		func(event *tournament.Tournament, actor tournament.Actor) error {
			participantID := request.ParticipantID
			if participantID == "" {
				participantID = actor.ParticipantID
			}
			actor.ParticipantID = participantID
			if err := event.Unregister(actor); err != nil {
				return err
			}
			h.clearTournamentParticipantBindings(event.ID, participantID)
			if event.OrganizerParticipantID == participantID {
				event.OrganizerParticipantID = ""
			}
			binding := sess.Tournament()
			if binding.ParticipantID == participantID {
				binding.ParticipantID = ""
				if binding.Role == tournament.RoleParticipant {
					binding.Role = tournament.RoleViewer
				}
				sess.setTournament(binding)
			}
			return nil
		})
}

func (h *Handler) handleTournamentCheckIn(sess *Session, env protocol.Envelope) error {
	var request protocol.TournamentCheckIn
	if err := env.DecodePayload(&request); err != nil {
		h.sendError(sess, env.ID, protocol.ErrInvalidMessage, err.Error())
		return nil
	}
	return h.mutateTournament(sess, env, protocol.TypeTournamentCheckInSet,
		func(event *tournament.Tournament, actor tournament.Actor) error {
			if request.ParticipantID != "" {
				actor.ParticipantID = request.ParticipantID
			}
			return event.SetCheckedIn(actor, request.CheckedIn)
		})
}

func (h *Handler) handleTournamentStart(sess *Session, env protocol.Envelope) error {
	var seedBytes [8]byte
	if _, err := secureRandomRead(seedBytes[:]); err != nil {
		h.sendError(sess, env.ID, protocol.ErrInternal, "pairing random source unavailable")
		return nil
	}
	seed := int64(binary.LittleEndian.Uint64(seedBytes[:]))
	return h.mutateTournament(sess, env, protocol.TypeTournamentStarted,
		func(event *tournament.Tournament, actor tournament.Actor) error {
			return event.Start(actor, seed, time.Now())
		})
}

func (h *Handler) handleTournamentDrop(sess *Session, env protocol.Envelope) error {
	var request protocol.TournamentParticipantCommand
	if err := env.DecodePayload(&request); err != nil {
		h.sendError(sess, env.ID, protocol.ErrInvalidMessage, err.Error())
		return nil
	}
	return h.mutateTournament(sess, env, protocol.TypeTournamentDropped,
		func(event *tournament.Tournament, actor tournament.Actor) error {
			return event.Drop(actor, request.ParticipantID)
		})
}

func (h *Handler) handleTournamentReportResult(sess *Session, env protocol.Envelope) error {
	var request protocol.TournamentResultCommand
	if err := env.DecodePayload(&request); err != nil {
		h.sendError(sess, env.ID, protocol.ErrInvalidMessage, err.Error())
		return nil
	}
	return h.mutateTournament(sess, env, protocol.TypeTournamentResultReported,
		func(event *tournament.Tournament, actor tournament.Actor) error {
			return event.Report(actor, request.PairingID, tournament.MatchScore{
				PlayerAWins: request.PlayerAWins, PlayerBWins: request.PlayerBWins,
				DrawnGames: request.DrawnGames,
			}, time.Now())
		})
}

func (h *Handler) handleTournamentConfirmResult(sess *Session, env protocol.Envelope) error {
	var request protocol.TournamentPairingCommand
	if err := env.DecodePayload(&request); err != nil {
		h.sendError(sess, env.ID, protocol.ErrInvalidMessage, err.Error())
		return nil
	}
	return h.mutateTournament(sess, env, protocol.TypeTournamentResultConfirmed,
		func(event *tournament.Tournament, actor tournament.Actor) error {
			return event.Confirm(actor, request.PairingID, time.Now())
		})
}

func (h *Handler) handleTournamentRejectResult(sess *Session, env protocol.Envelope) error {
	var request protocol.TournamentPairingCommand
	if err := env.DecodePayload(&request); err != nil {
		h.sendError(sess, env.ID, protocol.ErrInvalidMessage, err.Error())
		return nil
	}
	return h.mutateTournament(sess, env, protocol.TypeTournamentResultRejected,
		func(event *tournament.Tournament, actor tournament.Actor) error {
			return event.Reject(actor, request.PairingID)
		})
}

func (h *Handler) handleTournamentCorrectResult(sess *Session, env protocol.Envelope) error {
	var request protocol.TournamentResultCommand
	if err := env.DecodePayload(&request); err != nil {
		h.sendError(sess, env.ID, protocol.ErrInvalidMessage, err.Error())
		return nil
	}
	return h.mutateTournament(sess, env, protocol.TypeTournamentResultCorrected,
		func(event *tournament.Tournament, actor tournament.Actor) error {
			return event.Correct(actor, request.PairingID, tournament.MatchScore{
				PlayerAWins: request.PlayerAWins, PlayerBWins: request.PlayerBWins,
				DrawnGames: request.DrawnGames,
			}, time.Now())
		})
}

func (h *Handler) handleTournamentNextRound(sess *Session, env protocol.Envelope) error {
	return h.mutateTournament(sess, env, protocol.TypeTournamentRoundStarted,
		func(event *tournament.Tournament, actor tournament.Actor) error {
			return event.Advance(actor, time.Now())
		})
}

func (h *Handler) handleTournamentCancel(sess *Session, env protocol.Envelope) error {
	return h.mutateTournament(sess, env, protocol.TypeTournamentCancelled,
		func(event *tournament.Tournament, actor tournament.Actor) error {
			return event.Cancel(actor, time.Now())
		})
}

func (h *Handler) mutateTournament(sess *Session, env protocol.Envelope, replyType string,
	mutate func(*tournament.Tournament, tournament.Actor) error) error {
	binding := sess.Tournament()
	if binding.TournamentID == "" {
		h.sendError(sess, env.ID, protocol.ErrTournamentNotFound, "not viewing a tournament")
		return nil
	}
	entry, err := h.tournaments.lockOperation(binding.TournamentID)
	if err != nil {
		sendTournamentError(h, sess, env.ID, err)
		return nil
	}
	defer entry.opMu.Unlock()
	entry.mu.Lock()
	err = mutate(entry.event, tournamentActor(sess))
	entry.mu.Unlock()
	if err != nil {
		sendTournamentError(h, sess, env.ID, err)
		return nil
	}
	reply, _ := protocol.NewEnvelope(replyType,
		protocol.TournamentChanged{TournamentID: binding.TournamentID})
	reply.ID = env.ID
	h.send(sess, reply)
	h.fanoutTournament(binding.TournamentID)
	return nil
}

func (h *Handler) handleTournamentOpenMatch(sess *Session, env protocol.Envelope) error {
	if sess.Room() != nil {
		h.sendError(sess, env.ID, protocol.ErrAlreadyInRoom, "already in a room")
		return nil
	}
	var request protocol.TournamentPairingCommand
	if err := env.DecodePayload(&request); err != nil {
		h.sendError(sess, env.ID, protocol.ErrInvalidMessage, err.Error())
		return nil
	}
	binding := sess.Tournament()
	if binding.TournamentID == "" || binding.ParticipantID == "" {
		h.sendError(sess, env.ID, protocol.ErrTournamentForbidden,
			"only paired participants can open a match")
		return nil
	}
	entry, err := h.tournaments.lockOperation(binding.TournamentID)
	if err != nil {
		sendTournamentError(h, sess, env.ID, err)
		return nil
	}
	defer entry.opMu.Unlock()

	entry.mu.Lock()
	event := entry.event
	pairing := event.CurrentPairing(binding.ParticipantID)
	if event.Status != tournament.StatusRunning ||
		event.Stage != protocol.LimitedStageCompetition || pairing == nil ||
		pairing.ID != request.PairingID || pairing.Result != nil || pairing.Bye() {
		entry.mu.Unlock()
		h.sendError(sess, env.ID, protocol.ErrTournamentForbidden,
			"pairing is not an open current match")
		return nil
	}
	roomID := pairing.RoomID
	format := protocol.FormatModern
	deckFormat := strings.ToLower(event.Format)
	if event.EventType != protocol.LimitedEventConstructed {
		deckFormat = protocol.DeckFormatLimited
	}
	if event.Format == protocol.FormatDuel || strings.EqualFold(event.Format, "duel commander") {
		format = protocol.FormatDuel
		deckFormat = protocol.DeckFormatDuel
	}
	if !protocol.ValidDeckFormat(deckFormat) {
		entry.mu.Unlock()
		h.sendError(sess, env.ID, protocol.ErrUnsupportedFormat,
			"tournament deck format is unsupported")
		return nil
	}
	matchMode := event.MatchMode
	roundNumber := 0
	if round := event.CurrentRound(); round != nil {
		roundNumber = round.Number
	}
	coordinator := event.Coordinator
	table := pairing.Table
	leftName := event.Participant(pairing.PlayerAID).DisplayName
	rightName := event.Participant(pairing.PlayerBID).DisplayName
	var lockedDeck *protocol.DeckSelect
	participant := event.Participant(binding.ParticipantID)
	if event.EventType != protocol.LimitedEventConstructed &&
		(participant == nil || participant.Deck == nil) {
		entry.mu.Unlock()
		h.sendError(sess, env.ID, protocol.ErrTournamentNotReady,
			"limited pairing deck is unavailable")
		return nil
	}
	if participant != nil && participant.Deck != nil &&
		event.EventType != protocol.LimitedEventConstructed {
		deckCopy := *participant.Deck
		deckCopy.Commanders = append([]string(nil), participant.Deck.Commanders...)
		deckCopy.Mainboard = append([]protocol.DeckCard(nil), participant.Deck.Mainboard...)
		deckCopy.Sideboard = append([]protocol.DeckCard(nil), participant.Deck.Sideboard...)
		lockedDeck = &deckCopy
	}
	entry.mu.Unlock()

	if roomID != "" && h.hub.FindRoom(roomID) == nil {
		entry.mu.Lock()
		event.ClearRoom(roomID)
		entry.mu.Unlock()
		roomID = ""
	}
	if roomID == "" {
		roomName := fmt.Sprintf("R%d T%d · %s vs %s", roundNumber, table, leftName, rightName)
		if coordinator == protocol.LimitedCoordinatorCasual {
			roomName = fmt.Sprintf("Casual T%d · %s vs %s", table, leftName, rightName)
		}
		runes := []rune(roomName)
		if len(runes) > protocol.MaxRoomNameRunes {
			roomName = string(runes[:protocol.MaxRoomNameRunes])
		}
		r, snapshot, seq, roomOperation, createErr := h.hub.createTournamentRoom(
			roomName, format, deckFormat, matchMode, protocol.CardLoadBackground, 2,
			binding.TournamentID, request.PairingID, binding.ParticipantID, sess)
		if createErr != nil {
			sendTournamentError(h, sess, env.ID, createErr)
			return nil
		}
		var selected room.Result
		if lockedDeck != nil {
			roomOperation.mu.Lock()
			selected, createErr = roomOperation.room.SelectDeck(sess.ConnectionID, *lockedDeck)
			roomOperation.mu.Unlock()
			if createErr != nil {
				sess.setRoom(nil)
				_ = h.removeRoom(r)
				roomOperation.opMu.Unlock()
				sendTournamentError(h, sess, env.ID, createErr)
				return nil
			}
		}
		entry.mu.Lock()
		setErr := event.SetPairingRoom(tournamentActor(sess), request.PairingID, r.ID)
		entry.mu.Unlock()
		if setErr != nil {
			// The room is already registered and bound to the host, but no
			// pairing references it. Discard it before reporting the failure so
			// the hub cannot retain a room the tournament cannot reach.
			// Tournament opMu is already held, so skip commitPairingRoomCleanup.
			sess.setRoom(nil)
			_ = h.removeRoom(r)
			roomOperation.opMu.Unlock()
			sendTournamentError(h, sess, env.ID, setErr)
			return nil
		}
		opened, _ := protocol.NewEnvelope(protocol.TypeTournamentMatchOpened,
			protocol.TournamentMatchOpened{
				TournamentID: binding.TournamentID, PairingID: request.PairingID, RoomID: r.ID,
			})
		opened.ID = env.ID
		h.send(sess, opened)
		created, _ := protocol.NewEnvelope(protocol.TypeRoomCreated, protocol.RoomCreated{
			RoomID: r.ID,
			Settings: protocol.RoomSettings{
				Name: r.Name, Format: r.Format, DeckFormat: r.DeckFormat,
				MaxSeats:        r.MaxSeats,
				AllowSpectators: false, MatchMode: r.MatchMode,
				CardLoadMode: r.CardLoadMode, HasPassword: false,
			},
			HostSeat: r.HostSeat,
		})
		h.send(sess, created)
		snapshotEnvelope, _ := protocol.NewEnvelope(protocol.TypeRoomSnapshot, snapshot)
		h.send(sess, snapshotEnvelope.WithSeq(seq))
		if lockedDeck != nil {
			h.fanout(r, selected.Broadcast)
		}
		roomOperation.opMu.Unlock()
		h.fanoutTournament(binding.TournamentID)
		return nil
	}

	roomOperation, joinErr := h.hub.beginJoin(roomID, "")
	if joinErr != nil {
		sendTournamentError(h, sess, env.ID, joinErr)
		return nil
	}
	result, r, joinErr := h.hub.joinTournamentRoom(
		roomOperation, sess, binding.ParticipantID)
	if joinErr != nil {
		roomOperation.opMu.Unlock()
		sendTournamentError(h, sess, env.ID, joinErr)
		return nil
	}
	if lockedDeck != nil {
		roomOperation.mu.Lock()
		selected, selectErr := roomOperation.room.SelectDeck(sess.ConnectionID, *lockedDeck)
		roomOperation.mu.Unlock()
		if selectErr != nil {
			roomOperation.mu.Lock()
			_, _ = roomOperation.room.Leave(sess.ConnectionID)
			roomOperation.mu.Unlock()
			sess.setRoom(nil)
			roomOperation.opMu.Unlock()
			sendTournamentError(h, sess, env.ID, selectErr)
			return nil
		}
		result.Broadcast = append(result.Broadcast, selected.Broadcast...)
	}
	opened, _ := protocol.NewEnvelope(protocol.TypeTournamentMatchOpened,
		protocol.TournamentMatchOpened{
			TournamentID: binding.TournamentID, PairingID: request.PairingID, RoomID: roomID,
		})
	opened.ID = env.ID
	h.send(sess, opened)
	if result.Reply != nil {
		result.Reply.ID = ""
		h.send(sess, *result.Reply)
	}
	h.fanout(r, result.Broadcast)
	roomOperation.opMu.Unlock()
	h.fanoutTournament(binding.TournamentID)
	return nil
}
