// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package server

import (
	"hexproof/server/internal/limited"
	"hexproof/server/internal/protocol"
	"hexproof/server/internal/tournament"
)

func sendLimitedError(h *Handler, sess *Session, id string, err error) {
	code := limited.ErrorCode(err)
	message := err.Error()
	if domainError, ok := err.(*limited.Error); ok {
		message = domainError.Message
	}
	if code == "" {
		code = protocol.ErrLimitedInvalid
	}
	h.sendError(sess, id, code, message)
}

func (h *Handler) handleLimitedCreateCasualMatch(sess *Session, env protocol.Envelope) error {
	var request protocol.LimitedCreateCasualMatch
	if err := env.DecodePayload(&request); err != nil {
		h.sendError(sess, env.ID, protocol.ErrInvalidMessage, err.Error())
		return nil
	}
	return h.mutateTournament(sess, env, protocol.TypeLimitedCasualMatchCreated,
		func(event *tournament.Tournament, actor tournament.Actor) error {
			_, err := event.CreateCasualMatch(actor, request.PlayerAID, request.PlayerBID)
			return err
		})
}

func (h *Handler) handleLimitedPick(sess *Session, env protocol.Envelope) error {
	var request protocol.LimitedPick
	if err := env.DecodePayload(&request); err != nil {
		h.sendError(sess, env.ID, protocol.ErrInvalidMessage, err.Error())
		return nil
	}
	binding := sess.Tournament()
	if binding.TournamentID == "" || binding.ParticipantID == "" {
		h.sendError(sess, env.ID, protocol.ErrLimitedForbidden,
			"enter the limited event as a participant first")
		return nil
	}
	entry, err := h.tournaments.lockOperation(binding.TournamentID)
	if err != nil {
		sendTournamentError(h, sess, env.ID, err)
		return nil
	}
	defer entry.opMu.Unlock()
	entry.mu.Lock()
	remaining, pickErr := entry.event.PickLimited(tournamentActor(sess), request.InstanceID)
	entry.mu.Unlock()
	if pickErr != nil {
		if limited.ErrorCode(pickErr) != "" {
			sendLimitedError(h, sess, env.ID, pickErr)
		} else {
			sendTournamentError(h, sess, env.ID, pickErr)
		}
		return nil
	}
	reply, _ := protocol.NewEnvelope(protocol.TypeLimitedPicked, protocol.LimitedPicked{
		TournamentID: binding.TournamentID, Remaining: remaining,
	})
	reply.ID = env.ID
	h.send(sess, reply)
	h.fanoutTournament(binding.TournamentID)
	return nil
}

func (h *Handler) handleLimitedSubmitDeck(sess *Session, env protocol.Envelope) error {
	var request protocol.LimitedSubmitDeck
	if err := env.DecodePayload(&request); err != nil {
		h.sendError(sess, env.ID, protocol.ErrInvalidMessage, err.Error())
		return nil
	}
	binding := sess.Tournament()
	if binding.TournamentID == "" || binding.ParticipantID == "" {
		h.sendError(sess, env.ID, protocol.ErrLimitedForbidden,
			"enter the limited event as a participant first")
		return nil
	}
	entry, err := h.tournaments.lockOperation(binding.TournamentID)
	if err != nil {
		sendTournamentError(h, sess, env.ID, err)
		return nil
	}
	defer entry.opMu.Unlock()
	entry.mu.Lock()
	deck, submitErr := entry.event.SubmitLimitedDeck(tournamentActor(sess), request)
	entry.mu.Unlock()
	if submitErr != nil {
		if limited.ErrorCode(submitErr) != "" {
			sendLimitedError(h, sess, env.ID, submitErr)
		} else {
			sendTournamentError(h, sess, env.ID, submitErr)
		}
		return nil
	}
	reply, _ := protocol.NewEnvelope(protocol.TypeLimitedDeckSubmitted,
		protocol.LimitedDeckSubmitted{
			TournamentID:   binding.TournamentID,
			MainboardCount: deckCardCount(deck.Mainboard),
			SideboardCount: deckCardCount(deck.Sideboard),
		})
	reply.ID = env.ID
	h.send(sess, reply)
	h.fanoutTournament(binding.TournamentID)
	return nil
}

func deckCardCount(cards []protocol.DeckCard) int {
	total := 0
	for _, card := range cards {
		total += card.Count
	}
	return total
}
