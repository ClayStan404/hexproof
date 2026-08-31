// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package server

import (
	"hexproof/server/internal/protocol"
	"hexproof/server/internal/room"
	"time"
)

// KickFromRoom host-kicks a member by seat index or spectator index.
func (h *Hub) KickFromRoom(actorConnID string, seat, spectatorIndex *int, r *room.Room) (room.Result, error) {
	return h.reduceRoom(r, func(locked *room.Room) (room.Result, error) {
		return locked.Kick(actorConnID, seat, spectatorIndex)
	})
}

// SelectDeck stores a player's private deck selection under the room lock.
func (h *Hub) SelectDeck(connID string, deck protocol.DeckSelect, r *room.Room) (room.Result, error) {
	return h.reduceRoom(r, func(locked *room.Room) (room.Result, error) {
		return locked.SelectDeck(connID, deck)
	})
}

// SetReady changes a player's ready state under the room lock.
func (h *Hub) SetReady(connID string, ready bool, r *room.Room) (room.Result, error) {
	return h.reduceRoom(r, func(locked *room.Room) (room.Result, error) {
		return locked.SetReady(connID, ready)
	})
}

// CompleteLoad records one client's completion of the active load generation.
func (h *Hub) CompleteLoad(connID string, loadID int64, r *room.Room) (room.Result, error) {
	return h.reduceRoom(r, func(locked *room.Room) (room.Result, error) {
		return locked.CompleteLoad(connID, loadID)
	})
}

// RulesStartPlayers copies private deck inputs for an already-gated Forge
// room under the room state lock.
func (h *Hub) RulesStartPlayers(r *room.Room) ([]room.RulesStartPlayer, error) {
	if r == nil {
		return nil, &protocolError{code: protocol.ErrRoomNotFound, message: "room not found"}
	}
	entry := h.roomEntryFor(r.ID)
	if entry == nil {
		return nil, &protocolError{code: protocol.ErrRoomNotFound, message: "room not found"}
	}
	entry.mu.Lock()
	defer entry.mu.Unlock()
	if entry.room != r {
		return nil, &protocolError{code: protocol.ErrRoomNotFound, message: "room not found"}
	}
	players, err := entry.room.RulesStartPlayers()
	if err != nil {
		return nil, mapRoomError(err)
	}
	return players, nil
}

// ResetRulesStartFailure restores a Forge room after its external engine
// start failed.
func (h *Hub) ResetRulesStartFailure(r *room.Room) (room.Result, error) {
	return h.reduceRoom(r, func(locked *room.Room) (room.Result, error) {
		return locked.ResetRulesStartFailure(), nil
	})
}

// CompleteRulesGame commits the externally authoritative terminal result to
// the ordinary Hexproof match lifecycle without importing Forge card state.
func (h *Hub) CompleteRulesGame(r *room.Room, winnerSeat int) (room.Result, error) {
	return h.reduceRoom(r, func(locked *room.Room) (room.Result, error) {
		return locked.CompleteRulesGame(winnerSeat, time.Now().UTC())
	})
}

// ApplyRulesConcede records Forge's authoritative concession outcome without
// importing any engine card state into the manual reducer.
func (h *Hub) ApplyRulesConcede(r *room.Room, concededSeat, winnerSeat int,
	matchFinished bool) (room.Result, error) {
	return h.reduceRoom(r, func(locked *room.Room) (room.Result, error) {
		return locked.ApplyRulesConcede(
			concededSeat, winnerSeat, matchFinished, time.Now().UTC())
	})
}

// Draw moves one or more cards into the acting player's private hand.
func (h *Hub) Draw(connID string, count int, r *room.Room) (room.Result, error) {
	return h.reduceRoom(r, func(locked *room.Room) (room.Result, error) {
		return locked.Draw(connID, count)
	})
}

// CanReturnToRoom validates a post-match transition under the room lock.
func (h *Hub) CanReturnToRoom(connID string, r *room.Room) error {
	if r == nil {
		return &protocolError{code: protocol.ErrRoomNotFound, message: "room not found"}
	}
	entry := h.roomEntryFor(r.ID)
	if entry == nil {
		return &protocolError{code: protocol.ErrRoomNotFound, message: "room not found"}
	}
	entry.mu.Lock()
	defer entry.mu.Unlock()
	if entry.room != r {
		return &protocolError{code: protocol.ErrRoomNotFound, message: "room not found"}
	}

	if err := entry.room.CanReturnToRoom(connID); err != nil {
		return mapRoomError(err)
	}
	return nil
}

// ReturnToRoom restores the waiting-room flow after a completed match.
func (h *Hub) ReturnToRoom(connID string, r *room.Room) (room.Result, error) {
	return h.reduceRoom(r, func(locked *room.Room) (room.Result, error) {
		return locked.ReturnToRoom(connID)
	})
}

// ShuffleLibrary randomizes the acting player's hidden library.
func (h *Hub) ShuffleLibrary(connID string, r *room.Room) (room.Result, error) {
	return h.reduceRoom(r, func(locked *room.Room) (room.Result, error) {
		return locked.ShuffleLibrary(connID)
	})
}

// SetCardCounter updates one public counter on a controlled permanent.
func (h *Hub) SetCardCounter(connID string, request protocol.GameSetCardCounter,
	r *room.Room) (room.Result, error) {
	return h.reduceRoom(r, func(locked *room.Room) (room.Result, error) {
		return locked.SetCardCounter(connID, request)
	})
}

// SetCardFace updates the visible face of one battlefield permanent.
func (h *Hub) SetCardFace(connID string, request protocol.GameSetCardFace,
	r *room.Room) (room.Result, error) {
	return h.reduceRoom(r, func(locked *room.Room) (room.Result, error) {
		return locked.SetCardFace(connID, request)
	})
}

// SetFaceDown updates persistent hidden identity on one battlefield card.
func (h *Hub) SetFaceDown(connID string, request protocol.GameSetFaceDown,
	r *room.Room) (room.Result, error) {
	return h.reduceRoom(r, func(locked *room.Room) (room.Result, error) {
		return locked.SetFaceDown(connID, request)
	})
}

// Mulligan replaces the acting player's hand with a shuffled hand of seven.
func (h *Hub) Mulligan(connID string, r *room.Room) (room.Result, error) {
	return h.reduceRoom(r, func(locked *room.Room) (room.Result, error) {
		return locked.Mulligan(connID)
	})
}

// DiscardHand moves one server-random card or the complete hand to graveyard.
func (h *Hub) DiscardHand(connID string, all bool, r *room.Room) (room.Result, error) {
	return h.reduceRoom(r, func(locked *room.Room) (room.Result, error) {
		return locked.DiscardHand(connID, all)
	})
}

// MoveLibraryCards moves a private library prefix into a public zone.
func (h *Hub) MoveLibraryCards(connID string, request protocol.GameMoveLibraryCards,
	r *room.Room) (room.Result, error) {
	return h.reduceRoom(r, func(locked *room.Room) (room.Result, error) {
		return locked.MoveLibraryCards(connID, request)
	})
}

// SetTapped updates one battlefield permanent controlled by the acting seat.
func (h *Hub) SetTapped(connID string, request protocol.GameSetTapped, r *room.Room) (room.Result, error) {
	return h.reduceRoom(r, func(locked *room.Room) (room.Result, error) {
		return locked.SetTapped(connID, request)
	})
}

// SetPhase updates the shared phase marker for the active player.
func (h *Hub) SetPhase(connID string, request protocol.GameSetPhase, r *room.Room) (room.Result, error) {
	return h.reduceRoom(r, func(locked *room.Room) (room.Result, error) {
		return locked.SetPhase(connID, request)
	})
}

// SetResponseStatus updates one public, rules-neutral coordination signal.
func (h *Hub) SetResponseStatus(connID string, request protocol.GameSetResponseStatus,
	r *room.Room) (room.Result, error) {
	return h.reduceRoom(r, func(locked *room.Room) (room.Result, error) {
		return locked.SetResponseStatus(connID, request)
	})
}

// SetCounter updates one public counter owned by the acting player.
func (h *Hub) SetCounter(connID string, request protocol.GameSetCounter, r *room.Room) (room.Result, error) {
	return h.reduceRoom(r, func(locked *room.Room) (room.Result, error) {
		return locked.SetCounter(connID, request)
	})
}

// SetCounterCount updates the acting player's public counter-slot display
// count without changing any counter values.
func (h *Hub) SetCounterCount(connID string, request protocol.GameSetCounterCount,
	r *room.Room) (room.Result, error) {
	return h.reduceRoom(r, func(locked *room.Room) (room.Result, error) {
		return locked.SetCounterCount(connID, request)
	})
}

// Concede records an immutable two-player game result.
func (h *Hub) Concede(connID string, r *room.Room) (room.Result, error) {
	return h.reduceRoom(r, func(locked *room.Room) (room.Result, error) {
		return locked.ConcedeAt(connID, time.Now().UTC())
	})
}

// DeclareDraw records a no-winner result for the current game.
func (h *Hub) DeclareDraw(connID string, r *room.Room) (room.Result, error) {
	return h.reduceRoom(r, func(locked *room.Room) (room.Result, error) {
		return locked.DeclareDrawAt(connID, time.Now().UTC())
	})
}

// RestartGame rebuilds the current game without changing its score.
func (h *Hub) RestartGame(connID string, r *room.Room) (room.Result, error) {
	return h.reduceRoom(r, func(locked *room.Room) (room.Result, error) {
		return locked.RestartGame(connID)
	})
}

// MoveSideboard mutates only the acting player's private pending partition.
func (h *Hub) MoveSideboard(connID string, request protocol.SideboardMove,
	r *room.Room) (room.Result, error) {
	return h.reduceRoom(r, func(locked *room.Room) (room.Result, error) {
		return locked.MoveSideboard(connID, request)
	})
}

// SetSideboardCommander changes a Duel Commander designation for the next game.
func (h *Hub) SetSideboardCommander(connID string,
	request protocol.SideboardSetCommander, r *room.Room) (room.Result, error) {
	return h.reduceRoom(r, func(locked *room.Room) (room.Result, error) {
		return locked.SetSideboardCommander(connID, request)
	})
}

// SetSideboardReady locks one player's partition and may start the next game.
func (h *Hub) SetSideboardReady(connID string, ready bool,
	r *room.Room) (room.Result, error) {
	return h.reduceRoom(r, func(locked *room.Room) (room.Result, error) {
		return locked.SetSideboardReady(connID, ready)
	})
}

// ExpireSideboard applies the timeout fallback using committed decklists.
func (h *Hub) ExpireSideboard(r *room.Room, now time.Time) (room.Result, error) {
	return h.reduceRoom(r, func(locked *room.Room) (room.Result, error) {
		return locked.ExpireSideboard(now)
	})
}

// Say appends one server-authoritative public chat entry.
func (h *Hub) Say(connID string, request protocol.GameSay, r *room.Room) (room.Result, error) {
	return h.reduceRoom(r, func(locked *room.Room) (room.Result, error) {
		return locked.Say(connID, request)
	})
}

// NextTurn advances active-player coordination and resets the phase to untap.
func (h *Hub) NextTurn(connID string, r *room.Room) (room.Result, error) {
	return h.reduceRoom(r, func(locked *room.Room) (room.Result, error) {
		return locked.NextTurn(connID)
	})
}

// Reveal publishes cards from the acting player's hidden hand.
func (h *Hub) Reveal(connID string, request protocol.GameReveal, r *room.Room) (room.Result, error) {
	return h.reduceRoom(r, func(locked *room.Room) (room.Result, error) {
		return locked.Reveal(connID, request)
	})
}

// RecallRevealed returns the acting player's shared revealed cards to hand.
func (h *Hub) RecallRevealed(connID string, r *room.Room) (room.Result, error) {
	return h.reduceRoom(r, func(locked *room.Room) (room.Result, error) {
		return locked.RecallRevealed(connID)
	})
}

// DumpZone returns the acting player's private library view.
func (h *Hub) DumpZone(connID string, request protocol.GameDumpZone, r *room.Room) (room.Result, error) {
	return h.reduceRoom(r, func(locked *room.Room) (room.Result, error) {
		return locked.DumpZone(connID, request)
	})
}

// ZoneDumpTarget validates the players involved in an opponent-library access
// request without exposing either connection id to clients.
func (h *Hub) ZoneDumpTarget(connID string, request protocol.GameDumpZone,
	r *room.Room) (room.ZoneDumpTarget, error) {
	entry := h.roomEntryFor(r.ID)
	if entry == nil {
		return room.ZoneDumpTarget{},
			&protocolError{code: protocol.ErrRoomNotFound, message: "room not found"}
	}
	entry.mu.Lock()
	defer entry.mu.Unlock()

	target, err := r.ZoneDumpTarget(connID, request)
	if err != nil {
		return room.ZoneDumpTarget{}, mapRoomError(err)
	}
	return target, nil
}

// DumpApprovedZone returns a target library after the handler validates the
// matching one-use approval.
func (h *Hub) DumpApprovedZone(connID string, targetSeat int,
	approvalID string, topCount int, r *room.Room) (room.Result, error) {
	return h.reduceRoom(r, func(locked *room.Room) (room.Result, error) {
		return locked.DumpApprovedZone(connID, targetSeat, approvalID, topCount)
	})
}

// SearchLibrary moves selected private library cards and records a
// reveal-aware public log entry.
func (h *Hub) SearchLibrary(connID string, request protocol.GameSearchLibrary, r *room.Room) (room.Result, error) {
	return h.reduceRoom(r, func(locked *room.Room) (room.Result, error) {
		return locked.SearchLibrary(connID, request)
	})
}

// SearchApprovedLibrary consumes selected cards from a target library after
// the handler validates and consumes the corresponding approval.
func (h *Hub) SearchApprovedLibrary(connID string,
	request protocol.GameSearchLibrary, r *room.Room) (room.Result, error) {
	return h.reduceRoom(r, func(locked *room.Room) (room.Result, error) {
		return locked.SearchApprovedLibrary(connID, request)
	})
}

// ReorderLibrary applies a private top-prefix order selected by its owner.
func (h *Hub) ReorderLibrary(connID string, request protocol.GameReorderLibrary,
	r *room.Room) (room.Result, error) {
	return h.reduceRoom(r, func(locked *room.Room) (room.Result, error) {
		return locked.ReorderLibrary(connID, request)
	})
}

// ResolveLibraryView atomically resolves one private top-X library view.
func (h *Hub) ResolveLibraryView(connID string,
	request protocol.GameResolveLibraryView, r *room.Room) (room.Result, error) {
	return h.reduceRoom(r, func(locked *room.Room) (room.Result, error) {
		return locked.ResolveLibraryView(connID, request)
	})
}

// ResolveApprovedLibraryView resolves a remote top-X view after the handler
// validates the corresponding one-use approval.
func (h *Hub) ResolveApprovedLibraryView(connID string,
	request protocol.GameResolveLibraryView, r *room.Room) (room.Result, error) {
	return h.reduceRoom(r, func(locked *room.Room) (room.Result, error) {
		return locked.ResolveApprovedLibraryView(connID, request)
	})
}
