// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package server

import (
	"context"
	"errors"
	"fmt"
	"sort"
	"strings"
	"time"

	"hexproof/server/internal/protocol"
	"hexproof/server/internal/room"
	"hexproof/server/internal/rulesengine/forge"
)

const forgeSnapshotTimeout = 5 * time.Second

func (h *Handler) forgeGame(roomID string) (forgeRoomGame, bool) {
	h.forgeMu.Lock()
	defer h.forgeMu.Unlock()
	game, ok := h.forgeGames[roomID]
	return game, ok
}

func (h *Handler) rulesProjections(r *room.Room) (map[string]protocol.Envelope, error) {
	game, ok := h.forgeGame(r.ID)
	if !ok {
		return nil, errors.New("Forge game session is unavailable")
	}
	targets, seq, err := h.hub.RulesProjectionTargets(r)
	if err != nil {
		return nil, err
	}
	projections := make(map[string]protocol.Envelope, len(targets))
	for connectionID, seat := range targets {
		viewer := -1
		if seat >= 0 {
			mapped, exists := game.seatToPlayer[seat]
			if !exists {
				return nil, fmt.Errorf("seat %d has no Forge player", seat)
			}
			viewer = mapped
		}
		ctx, cancel := context.WithTimeout(context.Background(), forgeSnapshotTimeout)
		view, snapshotErr := game.client.SnapshotView(ctx, game.sessionID, viewer)
		cancel()
		if snapshotErr != nil {
			return nil, snapshotErr
		}
		snapshot, err := normalizeForgeSnapshot(r.ID, game, view)
		if err != nil {
			return nil, err
		}
		envelope, err := protocol.NewEnvelope(protocol.TypeRulesSnapshot, snapshot)
		if err != nil {
			return nil, err
		}
		projections[connectionID] = envelope.WithSeq(seq)
	}
	return projections, nil
}

func normalizeForgeSnapshot(roomID string, game forgeRoomGame,
	view forge.GameView) (protocol.RulesGameSnapshot, error) {
	if view.GameID != game.gameID {
		return protocol.RulesGameSnapshot{}, errors.New("Forge snapshot game id does not match room")
	}
	seatForID := func(playerID string) (int, error) {
		playerIndex, err := forge.PlayerIndexFromID(playerID)
		if err != nil {
			return 0, err
		}
		seat, ok := game.playerToSeat[playerIndex]
		if !ok {
			return 0, fmt.Errorf("Forge player %d has no room seat", playerIndex)
		}
		return seat, nil
	}
	activeSeat, err := seatForID(view.ActivePlayerID)
	if err != nil {
		return protocol.RulesGameSnapshot{}, err
	}
	prioritySeat, err := seatForID(view.PriorityPlayerID)
	if err != nil {
		return protocol.RulesGameSnapshot{}, err
	}
	snapshot := protocol.RulesGameSnapshot{
		RoomID:       roomID,
		GameID:       view.GameID,
		Turn:         view.Turn,
		Step:         view.Step,
		ActiveSeat:   activeSeat,
		PrioritySeat: prioritySeat,
		Players:      make([]protocol.RulesPlayerState, 0, len(view.Players)),
		Zones:        make([]protocol.RulesZoneState, 0, len(view.Zones)),
		Stack:        make([]protocol.RulesStackObject, 0, len(view.Stack)),
		GameOver:     view.GameOver,
	}
	for _, player := range view.Players {
		seat, err := seatForID(player.ID)
		if err != nil {
			return protocol.RulesGameSnapshot{}, err
		}
		snapshot.Players = append(snapshot.Players, protocol.RulesPlayerState{
			Seat: seat, Name: player.Name, Status: player.Status, Life: player.Life,
			Counters: sortedRulesCounters(player.Counters),
			ManaPool: sortedRulesCounters(player.ManaPool),
		})
	}
	sort.Slice(snapshot.Players, func(i, j int) bool {
		return snapshot.Players[i].Seat < snapshot.Players[j].Seat
	})
	for _, zone := range view.Zones {
		ownerSeat, err := seatForID(zone.OwnerID)
		if err != nil {
			return protocol.RulesGameSnapshot{}, err
		}
		projected := protocol.RulesZoneState{
			Zone: zone.Zone, OwnerSeat: ownerSeat, Count: zone.Count,
			Cards: make([]protocol.RulesCardState, 0, len(zone.Cards)),
		}
		for _, card := range zone.Cards {
			cardOwnerSeat, err := optionalForgeSeat(card.OwnerID, ownerSeat, seatForID)
			if err != nil {
				return protocol.RulesGameSnapshot{}, err
			}
			controllerSeat, err := optionalForgeSeat(card.ControllerID, ownerSeat, seatForID)
			if err != nil {
				return protocol.RulesGameSnapshot{}, err
			}
			visible := card.Visibility == "visible" && card.Identity != nil &&
				strings.TrimSpace(card.Identity.Name) != ""
			projectedCard := protocol.RulesCardState{
				ID: card.ID, Visible: visible, OwnerSeat: cardOwnerSeat,
				ControllerSeat: controllerSeat, Tapped: card.Tapped,
				FaceDown: card.FaceDown, Attacking: card.Attacking,
				Power: card.Power, Toughness: card.Toughness,
				Counters: sortedRulesCounters(card.Counters), Damage: card.Damage,
				AttachedTo: card.AttachedTo,
			}
			if visible {
				identity := rulesIdentity(*card.Identity)
				projectedCard.Identity = &identity
			}
			projected.Cards = append(projected.Cards, projectedCard)
		}
		snapshot.Zones = append(snapshot.Zones, projected)
	}
	for _, stackObject := range view.Stack {
		controllerSeat, err := seatForID(stackObject.ControllerID)
		if err != nil {
			return protocol.RulesGameSnapshot{}, err
		}
		ownerSeat := -1
		if stackObject.OwnerID != "" {
			ownerSeat, err = seatForID(stackObject.OwnerID)
			if err != nil {
				return protocol.RulesGameSnapshot{}, err
			}
		}
		snapshot.Stack = append(snapshot.Stack, protocol.RulesStackObject{
			ID: stackObject.ID, SourceID: stackObject.SourceID,
			ControllerSeat: controllerSeat, OwnerSeat: ownerSeat,
			Identity: rulesIdentity(stackObject.Identity), Text: stackObject.Text,
		})
	}
	if view.WinnerID != "" {
		winnerSeat, err := seatForID(view.WinnerID)
		if err != nil {
			return protocol.RulesGameSnapshot{}, err
		}
		snapshot.WinnerSeat = &winnerSeat
	}
	return snapshot, nil
}

func optionalForgeSeat(playerID string, fallback int,
	seatForID func(string) (int, error)) (int, error) {
	if playerID == "" {
		return fallback, nil
	}
	return seatForID(playerID)
}

func rulesIdentity(identity forge.CardIdentityView) protocol.RulesCardIdentity {
	return protocol.RulesCardIdentity{
		Name: identity.Name, SetCode: identity.SetCode,
		CollectorNumber: identity.CardNumber, Token: identity.Token,
	}
}

func sortedRulesCounters(values map[string]int) []protocol.RulesCounter {
	keys := make([]string, 0, len(values))
	for name := range values {
		keys = append(keys, name)
	}
	sort.Strings(keys)
	result := make([]protocol.RulesCounter, 0, len(keys))
	for _, name := range keys {
		result = append(result, protocol.RulesCounter{Name: name, Value: values[name]})
	}
	return result
}

func rulesProjectionResult(projections map[string]protocol.Envelope) (bool, int, error) {
	gameOver := false
	winnerSeat := -1
	initialized := false
	for _, envelope := range projections {
		var snapshot protocol.RulesGameSnapshot
		if err := envelope.DecodePayload(&snapshot); err != nil {
			return false, -1, err
		}
		projectedWinner := -1
		if snapshot.WinnerSeat != nil {
			projectedWinner = *snapshot.WinnerSeat
		}
		if initialized && (snapshot.GameOver != gameOver || projectedWinner != winnerSeat) {
			return false, -1, errors.New("Forge terminal projections disagree")
		}
		gameOver = snapshot.GameOver
		winnerSeat = projectedWinner
		initialized = true
	}
	if !initialized {
		return false, -1, errors.New("Forge produced no room projections")
	}
	return gameOver, winnerSeat, nil
}

func (h *Handler) sendRulesProjections(projections map[string]protocol.Envelope) {
	for connectionID, envelope := range projections {
		if session := h.sessionByConn(connectionID); session != nil {
			h.send(session, envelope)
		}
	}
}

func (h *Handler) fanoutRulesProjections(r *room.Room) {
	projections, err := h.rulesProjections(r)
	if err != nil {
		h.failClosedGameProjections(r, err)
		return
	}
	h.sendRulesProjections(projections)
}
