// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package server

import (
	"encoding/json"
	"time"

	"hexproof/server/internal/limited"
	"hexproof/server/internal/protocol"
	"hexproof/server/internal/tournament"
)

// These opt-in commands require a literal boolean; omitted/null values must
// never be interpreted as an instruction to withdraw or reclaim a seat.
func limitedControlBoolean(env protocol.Envelope, field string) bool {
	var payload map[string]json.RawMessage
	if json.Unmarshal(env.Payload, &payload) != nil {
		return false
	}
	return string(payload[field]) == "true" || string(payload[field]) == "false"
}

func (h *Handler) handleLimitedSetDraftControl(sess *Session, env protocol.Envelope) error {
	var request protocol.LimitedSetDraftControl
	if err := env.DecodePayload(&request); err != nil || !limitedControlBoolean(env, "automatic") {
		h.sendError(sess, env.ID, protocol.ErrInvalidMessage, "automatic must be an explicit boolean")
		return nil
	}
	return h.mutateTournament(sess, env, protocol.TypeLimitedDraftControlSet,
		func(event *tournament.Tournament, actor tournament.Actor) error {
			return event.SetCubeDraftControl(actor, request, time.Now())
		})
}

func (h *Handler) handleLimitedSetParticipation(sess *Session, env protocol.Envelope) error {
	var request protocol.LimitedSetParticipation
	if err := env.DecodePayload(&request); err != nil || !limitedControlBoolean(env, "participating") {
		h.sendError(sess, env.ID, protocol.ErrInvalidMessage, "participating must be an explicit boolean")
		return nil
	}
	return h.mutateTournament(sess, env, protocol.TypeLimitedParticipationSet,
		func(event *tournament.Tournament, actor tournament.Actor) error {
			return event.SetCubeParticipation(actor, request.Participating)
		})
}

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
			if event.IsCommanderCube() {
				return event.CommanderCubeMatch(actor, request)
			}
			if len(request.PlayerIDs) != 0 || request.PairingID != "" {
				return &tournament.Error{Code: tournament.ErrInvalid, Message: "group invitations require Commander Cube"}
			}
			if request.Action == "cancel" {
				return event.CancelCubeMatch(actor, request.PlayerAID, request.PlayerBID)
			}
			if request.Action != "" {
				return &tournament.Error{Code: tournament.ErrInvalid, Message: "unsupported casual match action"}
			}
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
	if request.InstanceID != "" && len(request.InstanceIDs) > 0 {
		h.sendError(sess, env.ID, protocol.ErrInvalidMessage, "choose one pick representation")
		return nil
	}
	instanceIDs := request.InstanceIDs
	if request.InstanceID != "" {
		instanceIDs = []string{request.InstanceID}
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
	previous := make(map[string]protocol.LimitedSnapshot)
	if public := entry.event.LimitedSnapshot(""); public != nil {
		previous[""] = *public
		for _, participant := range entry.event.Participants {
			previous[participant.ID] = *entry.event.LimitedSnapshot(participant.ID)
		}
	}
	previousStage := entry.event.Stage
	remaining, pickErr := entry.event.PickLimitedCards(tournamentActor(sess), instanceIDs)
	stageChanged := entry.event.Stage != previousStage
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
	if stageChanged {
		h.fanoutTournament(binding.TournamentID)
	} else {
		h.fanoutTournamentState(binding.TournamentID, previous)
	}
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
