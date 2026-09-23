// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package server

import (
	"context"
	"errors"
	"strings"

	"hexproof/server/internal/forgehost"
	"hexproof/server/internal/protocol"
	"hexproof/server/internal/room"
	"hexproof/server/internal/rulesengine/forge"
)

var errForgeRuntimeUnavailable = errors.New("Forge rules runtime is unavailable")

// The engine numbers players by the start request, not by occupied room seat.
// Retain that mapping under the room operation lock until private projection.
type roomForgeStartFailure struct {
	cause error
	seats []int
}

func (e *roomForgeStartFailure) Error() string { return "Forge game setup failed" }
func (e *roomForgeStartFailure) Unwrap() error { return e.cause }

func forgeStartFailureReason(err error) string {
	var detail *forge.StartError
	var process *forge.ProcessError
	switch {
	case errors.As(err, &detail):
		return detail.Reason()
	case errors.Is(err, errForgeCapacity):
		return "capacity"
	case errors.Is(err, context.DeadlineExceeded):
		return "runtime_timeout"
	case errors.Is(err, forge.ErrStartRejected):
		return "start_rejected"
	case errors.As(err, &process):
		if strings.HasPrefix(process.Code, "executable_") || strings.HasPrefix(process.Code, "probe_") {
			return "runtime_unavailable"
		}
		return "runtime_failed"
	case errors.Is(err, forge.ErrRuntime), errors.Is(err, forge.ErrClosed):
		return "runtime_failed"
	case errors.Is(err, errForgeRuntimeUnavailable), errors.Is(err, forgehost.ErrUnavailable), errors.Is(err, forgehost.ErrPaused):
		return "runtime_unavailable"
	default:
		return "runtime_failed"
	}
}

func forgeStartFailure(err error) (string, string) {
	switch forgeStartFailureReason(err) {
	case "capacity":
		return protocol.ErrServerLimit, "Forge game capacity is full; wait for a game to finish, then ready again. Your seats and decks are kept"
	case "deck_rejected":
		return protocol.ErrRulesUnavailable, "Forge could not load a registered deck; its owner can review the affected cards"
	case "runtime_timeout":
		return protocol.ErrRulesUnavailable, "Forge took too long to start the game; your seats and decks are kept"
	case "runtime_unavailable":
		return protocol.ErrRulesUnavailable, "The Forge runtime is unavailable; your seats and decks are kept"
	case "start_rejected":
		return protocol.ErrRulesUnavailable, "Forge rejected the game setup without further details; your seats and decks are kept"
	default:
		return protocol.ErrRulesUnavailable, "Forge failed while starting the game; your seats and decks are kept"
	}
}

// sendForgeStartFailure follows the waiting-room snapshot. Every member gets a
// stable reason; only each registered deck's owner receives its private details.
// This also covers spectators and a triggering player whose deck was valid.
func (h *Handler) sendForgeStartFailure(r *room.Room, actor *Session, requestID string, err error) {
	code, message := forgeStartFailure(err)
	var scoped *roomForgeStartFailure
	var detail *forge.StartError
	hasDetails := errors.As(err, &scoped) && errors.As(err, &detail)
	type deckOwner struct{ connectionID, deck string }
	owners := make(map[int]deckOwner)
	if entry := h.hub.roomEntryFor(r.ID); entry != nil {
		entry.mu.Lock()
		if entry.room == r {
			for index, seat := range r.Seats {
				owner := deckOwner{seat.ConnectionID, "player"}
				if seat.Controller != "" {
					owner.deck = "ai"
					owner.connectionID = ""
					if r.HostSeat >= 0 && r.HostSeat < len(r.Seats) {
						owner.connectionID = r.Seats[r.HostSeat].ConnectionID
					}
				}
				owners[index] = owner
			}
		}
		entry.mu.Unlock()
	}

	for _, member := range h.sessionsForRoomPointer(r) {
		failure := &protocol.RulesStartFailure{Reason: forgeStartFailureReason(err)}
		if hasDetails {
			seen := make(map[protocol.RulesDeckIssue]bool)
			for _, issue := range detail.Issues() {
				if issue.PlayerIndex < 0 || issue.PlayerIndex >= len(scoped.seats) {
					continue
				}
				owner := owners[scoped.seats[issue.PlayerIndex]]
				if owner.connectionID == "" || owner.connectionID != member.ConnectionID {
					continue
				}
				projected := protocol.RulesDeckIssue{Deck: owner.deck, Section: issue.Section, Code: issue.Code,
					CardName: issue.Card.Name, SetCode: issue.Card.SetCode, CollectorNumber: issue.Card.CollectorNumber}
				if !seen[projected] {
					failure.Issues = append(failure.Issues, projected)
					seen[projected] = true
				}
			}
			failure.Truncated = len(failure.Issues) > 0 && detail.Truncated()
		}
		envelope, _ := protocol.NewEnvelope(protocol.TypeError, protocol.ErrorPayload{Code: code, Message: message, RulesStartFailure: failure})
		if member == actor {
			envelope.ID = requestID
		}
		h.send(member, envelope)
	}
}
