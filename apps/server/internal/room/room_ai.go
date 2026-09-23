// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package room

import "hexproof/server/internal/protocol"

// AddForgeAI reserves a room-owned controller before publication. Controller
// identity is independent of transport membership and leaves room for future
// separately authorized decision providers.
func (r *Room) AddForgeAI(difficulty string) error {
	return r.AddAI(protocol.AISourceForge, difficulty)
}

// AddAI keeps provider identity separate from the native decision controller.
func (r *Room) AddAI(source, difficulty string) error {
	if !protocol.ValidAIConfiguration(source, difficulty) || r.RulesMode != protocol.RulesModeForge ||
		r.Format != protocol.FormatModern || r.MatchMode != protocol.MatchBO1 || r.MaxSeats != 2 ||
		r.LimitedDeckLocked || r.DeckFormat == protocol.DeckFormatLimited ||
		r.DeckFormat == protocol.DeckFormatCube || r.Phase != protocol.RoomPhaseWaiting || r.Seats[1].Occupied {
		return newError(protocol.ErrInvalidMessage)
	}
	r.AISource, r.AIDifficulty = source, difficulty
	name, controller := "Forge AI", protocol.SeatControllerForgeAI
	if protocol.IsModelAISource(source) {
		name, controller = "Model AI", protocol.SeatControllerModelAI
	}
	r.Seats[1] = Seat{Occupied: true, DisplayName: name, Controller: controller, AIDifficulty: difficulty}
	return nil
}

// ConfigureAI never returns the private deck and never changes a live game.
func (r *Room) ConfigureAI(connID string, request protocol.RoomAIConfigure) (Result, error) {
	if !r.IsHost(connID) {
		return Result{}, newError(protocol.ErrNotHost)
	}
	if r.Phase != protocol.RoomPhaseWaiting {
		return Result{}, newError(protocol.ErrMatchStarted)
	}
	if !r.HasAI() || !protocol.ValidAIConfiguration(r.AISource, request.Difficulty) || len(r.Seats) != 2 {
		return Result{}, newError(protocol.ErrInvalidMessage)
	}
	if request.Deck != nil {
		if err := r.validateDeck(*request.Deck); err != nil {
			return Result{}, err
		}
		registered, active := cloneDeck(*request.Deck), cloneDeck(*request.Deck)
		r.Seats[1].RegisteredDeck, r.Seats[1].Deck = &registered, &active
	}
	r.AIDifficulty, r.Seats[1].AIDifficulty = request.Difficulty, request.Difficulty
	r.Seats[0].Ready, r.Seats[0].Loaded = false, false
	r.Seats[1].Ready = r.Seats[1].Deck != nil
	r.Seats[1].Loaded = false
	snapshot := r.snapshotEnvelope()
	return Result{Reply: &snapshot, Broadcast: []protocol.Envelope{snapshot}}, nil
}

func (r *Room) HumanPlayerCount() int {
	count := 0
	for _, seat := range r.Seats {
		if seat.Occupied && seat.Controller == "" {
			count++
		}
	}
	return count
}

// HasAI includes native and externally controlled practice seats.
func (r *Room) HasAI() bool {
	return r.AISource != "" || r.AIDifficulty != ""
}
