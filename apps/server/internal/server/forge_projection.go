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
	// Build the public journal only from an explicit spectator view. Reuse that
	// same envelope for every spectator rather than repeating engine RPCs.
	ctx, cancel := context.WithTimeout(context.Background(), forgeSnapshotTimeout)
	publicView, err := game.client.SnapshotView(ctx, game.sessionID, -1)
	cancel()
	if err != nil {
		return nil, err
	}
	publicSnapshot, err := normalizeForgeSnapshot(r.ID, game, publicView)
	if err != nil {
		return nil, err
	}
	h.hub.UpdateRulesPublicLog(r, publicSnapshot)
	h.hub.RecordRulesStartingSeat(r, game, publicView)
	targets, seq, err := h.hub.RulesProjectionTargets(r)
	if err != nil {
		return nil, err
	}
	projections := make(map[string]protocol.Envelope, len(targets))
	ownerSnapshots := make(map[int]protocol.RulesGameSnapshot, len(game.seatToPlayer))
	for connectionID, seat := range targets {
		if seat < 0 {
			continue
		}
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
		ownerSnapshots[seat] = snapshot
		envelope, err := protocol.NewEnvelope(protocol.TypeRulesSnapshot, snapshot)
		if err != nil {
			return nil, err
		}
		projections[connectionID] = envelope.WithSeq(seq)
	}
	spectatorSnapshot := rulesSpectatorSnapshot(publicSnapshot, ownerSnapshots, r.SpectatorsSeeHands)
	publicEnvelope, err := protocol.NewEnvelope(protocol.TypeRulesSnapshot, spectatorSnapshot)
	if err != nil {
		return nil, err
	}
	for connectionID, seat := range targets {
		if seat < 0 {
			projections[connectionID] = publicEnvelope.WithSeq(seq)
		}
	}
	return projections, nil
}

// The room's existing opt-in permits current hands only. The base remains the
// explicit spectator view, and the unmodified base alone feeds public logs.
func rulesSpectatorSnapshot(public protocol.RulesGameSnapshot,
	owners map[int]protocol.RulesGameSnapshot, showHands bool) protocol.RulesGameSnapshot {
	if !showHands {
		return public
	}
	result := public
	result.Zones = append([]protocol.RulesZoneState(nil), public.Zones...)
	for index, zone := range result.Zones {
		if zone.Zone != "hand" {
			continue
		}
		owner, found := owners[zone.OwnerSeat]
		if !found || owner.GameID != public.GameID || owner.RoomID != public.RoomID {
			continue
		}
		for _, privateZone := range owner.Zones {
			if privateZone.Zone == "hand" && privateZone.OwnerSeat == zone.OwnerSeat {
				result.Zones[index].Cards = append([]protocol.RulesCardState{}, privateZone.Cards...)
				break
			}
		}
	}
	return result
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
		Step:         normalizedRulesStep(view.Step),
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
			Counters:   sortedRulesCounters(player.Counters),
			ManaPool:   sortedRulesCounters(player.ManaPool),
			Commanders: projectedRulesCommanders(player.Commanders, view),
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
			Targets: projectedRulesStackTargets(stackObject.Targets, view, seatForID),
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

func projectedRulesStackTargets(targets []forge.StackTargetView, view forge.GameView,
	seatForID func(string) (int, error)) []protocol.RulesStackTarget {
	result := make([]protocol.RulesStackTarget, 0, len(targets))
	seen := make(map[string]bool)
	for _, target := range targets {
		key := target.Kind + ":" + target.ID
		if target.ID == "" || seen[key] {
			continue
		}
		entry := protocol.RulesStackTarget{Kind: target.Kind}
		switch target.Kind {
		case "player":
			for _, player := range view.Players {
				if player.ID == target.ID {
					if seat, err := seatForID(player.ID); err == nil {
						entry.Seat, entry.Label = &seat, player.Name
					}
				}
			}
		case "card":
			for _, zone := range view.Zones {
				for _, card := range zone.Cards {
					if card.ID == target.ID {
						entry.ObjectID = card.ID
						if card.Visibility == "visible" && card.Identity != nil {
							entry.Label = card.Identity.Name
						}
					}
				}
			}
		case "spell":
			for _, object := range view.Stack {
				if object.ID == target.ID {
					entry.ObjectID, entry.Label = object.ID, object.Identity.Name
				}
			}
		}
		if entry.Seat != nil || entry.ObjectID != "" {
			result = append(result, entry)
			seen[key] = true
		}
	}
	return result
}

func projectedRulesCommanders(commanders []forge.CommanderView, view forge.GameView) []protocol.RulesCommanderState {
	result := make([]protocol.RulesCommanderState, 0, len(commanders))
	for _, commander := range commanders {
		if strings.TrimSpace(commander.Name) == "" || commander.Casts < 0 || commander.Tax < 0 {
			continue
		}
		entry := protocol.RulesCommanderState{Name: commander.Name, Casts: commander.Casts, Tax: commander.Tax, Zone: "hidden"}
		for _, zone := range view.Zones {
			for _, card := range zone.Cards {
				if commander.ObjectID != "" && card.ID == commander.ObjectID && card.Visibility == "visible" && card.Identity != nil && strings.TrimSpace(card.Identity.Name) != "" && zone.Zone == commander.Zone {
					entry.ObjectID, entry.Zone = card.ID, zone.Zone
				}
			}
		}
		for _, object := range view.Stack {
			if commander.Zone == "stack" && commander.ObjectID != "" && object.SourceID == commander.ObjectID && strings.TrimSpace(object.Identity.Name) != "" {
				entry.ObjectID, entry.Zone = object.SourceID, "stack"
			}
		}
		result = append(result, entry)
	}
	return result
}

// normalizedRulesStep adapts the pinned harness names to the existing rules
// table's display keys. Both damage steps highlight the same rail category;
// Forge still owns and resolves the distinct first-strike and normal steps.
func normalizedRulesStep(step string) string {
	switch step {
	case "combatBegin":
		return protocol.GamePhaseBeginningCombat
	case "combatDeclareAttackers":
		return protocol.GamePhaseDeclareAttackers
	case "combatDeclareBlockers":
		return protocol.GamePhaseDeclareBlockers
	case "combatFirstStrikeDamage", "combatDamage":
		return protocol.GamePhaseCombatDamage
	case "combatEnd":
		return protocol.GamePhaseEndCombat
	case "endOfTurn":
		return protocol.GamePhaseEnd
	default:
		// Untap, upkeep, draw, main1, main2, and cleanup already match the
		// rules UI. Its main-phase keys intentionally differ from manual DTOs.
		return step
	}
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
	roomID := ""
	for _, envelope := range projections {
		if roomID == "" {
			var snapshot protocol.RulesGameSnapshot
			if envelope.DecodePayload(&snapshot) == nil {
				roomID = snapshot.RoomID
			}
		}
	}
	h.sendProjectionSet(projections)
	if r := h.hub.FindRoom(roomID); r != nil {
		h.fanoutRulesMetadata(r)
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
