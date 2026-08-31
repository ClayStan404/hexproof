// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package server

import (
	"context"
	"errors"
	"fmt"
	"sort"
	"strconv"
	"strings"
	"time"

	"hexproof/server/internal/protocol"
	"hexproof/server/internal/room"
	"hexproof/server/internal/rulesengine/forge"
)

const (
	forgePromptTimeout      = 5 * time.Second
	forgePromptPollInterval = 20 * time.Millisecond
)

func (h *Handler) rulesPrompts(r *room.Room) (map[string]protocol.Envelope, error) {
	game, ok := h.forgeGame(r.ID)
	if !ok {
		return nil, errors.New("Forge game session is unavailable")
	}
	targets, err := h.hub.RulesPlayerTargets(r)
	if err != nil {
		return nil, err
	}
	ctx, cancel := context.WithTimeout(context.Background(), forgePromptTimeout)
	view, err := currentRulesPrompt(ctx, game)
	cancel()
	if err != nil {
		return nil, err
	}
	var promptGameView *forge.GameView
	if view != nil && promptNeedsSnapshot(*view) {
		ctx, cancel = context.WithTimeout(context.Background(), forgeSnapshotTimeout)
		snapshot, snapshotErr := game.client.SnapshotView(ctx, game.sessionID, view.PlayerIndex)
		cancel()
		if snapshotErr != nil {
			return nil, snapshotErr
		}
		promptGameView = &snapshot
	}
	prompts := make(map[string]protocol.Envelope, len(targets))
	for connectionID, seat := range targets {
		playerIndex, exists := game.seatToPlayer[seat]
		if !exists {
			return nil, fmt.Errorf("seat %d has no Forge player", seat)
		}
		prompt := emptyRulesPrompt(r.ID, game.gameID)
		if view != nil && view.PlayerIndex == playerIndex {
			prompt, err = projectedRulesPrompt(r.ID, game.gameID, *view, game, promptGameView)
			if err != nil {
				return nil, err
			}
		}
		envelope, err := protocol.NewEnvelope(protocol.TypeRulesPrompt, prompt)
		if err != nil {
			return nil, err
		}
		prompts[connectionID] = envelope
	}
	return prompts, nil
}

func (h *Handler) clearedRulesPrompts(r *room.Room,
	game forgeRoomGame) (map[string]protocol.Envelope, error) {
	targets, err := h.hub.RulesPlayerTargets(r)
	if err != nil {
		return nil, err
	}
	prompts := make(map[string]protocol.Envelope, len(targets))
	for connectionID := range targets {
		envelope, err := protocol.NewEnvelope(protocol.TypeRulesPrompt,
			emptyRulesPrompt(r.ID, game.gameID))
		if err != nil {
			return nil, err
		}
		prompts[connectionID] = envelope
	}
	return prompts, nil
}

func emptyRulesPrompt(roomID, gameID string) protocol.RulesPrompt {
	return protocol.RulesPrompt{
		RoomID: roomID, GameID: gameID, Options: []protocol.RulesPromptOption{},
		Choices: []protocol.RulesPromptChoice{},
		Cards:   []protocol.RulesPromptCard{}, Targets: []protocol.RulesPromptTarget{},
		ScryDestinations: []string{},
		OrderItems:       []protocol.RulesPromptOrderItem{},
		ContextCards:     []protocol.RulesPromptCard{},
		ContextTargets:   []protocol.RulesPromptTarget{},
		CombatSources:    []protocol.RulesPromptCombatSource{},
		CombatTargets:    []protocol.RulesPromptCombatTarget{},
		DamageTargets:    []protocol.RulesPromptDamageTarget{},
	}
}

func promptNeedsSnapshot(view forge.PromptView) bool {
	return len(view.Targets) > 0 || len(view.CombatSources) > 0 ||
		len(view.CombatTargets) > 0 || view.DamageSource != nil ||
		len(view.DamageTargets) > 0 || len(view.ContextTargets) > 0
}

func projectedRulesPrompt(roomID, gameID string,
	view forge.PromptView, game forgeRoomGame,
	gameView *forge.GameView) (protocol.RulesPrompt, error) {
	prompt := emptyRulesPrompt(roomID, gameID)
	prompt.Pending = true
	prompt.PromptID = view.PromptID
	prompt.Kind = view.Kind
	prompt.Supported = view.Supported
	prompt.Title = view.Title
	prompt.Detail = view.Detail
	prompt.Options = make([]protocol.RulesPromptOption, 0, len(view.Options))
	for _, option := range view.Options {
		prompt.Options = append(prompt.Options, protocol.RulesPromptOption{
			ResponseID: option.ResponseID, Kind: option.Kind,
			Label: option.Label, CardID: option.CardID,
		})
	}
	prompt.Choices = make([]protocol.RulesPromptChoice, 0, len(view.Choices))
	for _, choice := range view.Choices {
		prompt.Choices = append(prompt.Choices, protocol.RulesPromptChoice{
			ResponseID: choice.ResponseID, Label: choice.Label,
			Weight: choice.Weight, CanRepeat: choice.CanRepeat,
		})
	}
	prompt.Cards = make([]protocol.RulesPromptCard, 0, len(view.Cards))
	for _, card := range view.Cards {
		prompt.Cards = append(prompt.Cards, protocol.RulesPromptCard{
			ID: card.ID, Name: card.Name, SetCode: card.SetCode,
			CollectorNumber: card.CollectorNumber, Token: card.Token,
		})
	}
	prompt.ScryDestinations = append([]string(nil), view.ScryDestinations...)
	prompt.OrderItems = make([]protocol.RulesPromptOrderItem, 0, len(view.OrderItems))
	for _, item := range view.OrderItems {
		prompt.OrderItems = append(prompt.OrderItems, protocol.RulesPromptOrderItem{
			ResponseID: item.ResponseID, Name: item.Name, SetCode: item.SetCode,
			CollectorNumber: item.CollectorNumber, Token: item.Token, Oracle: item.Oracle,
		})
	}
	prompt.ContextCards = make([]protocol.RulesPromptCard, 0, len(view.ContextCards))
	for _, card := range view.ContextCards {
		prompt.ContextCards = append(prompt.ContextCards, protocol.RulesPromptCard{
			ID: card.ID, Name: card.Name, SetCode: card.SetCode,
			CollectorNumber: card.CollectorNumber, Token: card.Token,
		})
	}
	prompt.ContextText = view.ContextText
	prompt.Required = view.Required
	prompt.CardMinimum = view.CardMinimum
	prompt.CardMaximum = view.CardMaximum
	prompt.Minimum = view.MinSelected
	prompt.Maximum = view.MaxSelected
	prompt.Cancellable = view.Cancellable
	prompt.ChoiceMinimum = view.ChoiceMinimum
	prompt.ChoiceMaximum = view.ChoiceMaximum
	prompt.NumberMinimum = view.NumberMinimum
	prompt.NumberMaximum = view.NumberMaximum
	prompt.TotalDamage = view.TotalDamage
	prompt.DamageDeathtouch = view.DamageDeathtouch
	if len(view.Targets) > 0 {
		if gameView == nil {
			return protocol.RulesPrompt{}, errors.New("Forge target prompt has no viewer snapshot")
		}
		projectedTargets, err := projectedRulesTargets(view.Targets, game, *gameView)
		if err != nil {
			return protocol.RulesPrompt{}, err
		}
		prompt.Targets = projectedTargets
	}
	if len(view.ContextTargets) > 0 {
		if gameView == nil {
			return protocol.RulesPrompt{}, errors.New("Forge prompt context has no viewer snapshot")
		}
		contextTargets, err := projectedRulesTargets(view.ContextTargets, game, *gameView)
		if err != nil {
			return protocol.RulesPrompt{}, err
		}
		prompt.ContextTargets = contextTargets
	}
	if len(view.CombatSources) > 0 || len(view.CombatTargets) > 0 {
		if gameView == nil {
			return protocol.RulesPrompt{}, errors.New("Forge combat prompt has no viewer snapshot")
		}
		combatSources, combatTargets, err := projectedRulesCombat(
			view.CombatSources, view.CombatTargets, game, *gameView)
		if err != nil {
			return protocol.RulesPrompt{}, err
		}
		prompt.CombatSources = combatSources
		prompt.CombatTargets = combatTargets
	}
	if view.DamageSource != nil || len(view.DamageTargets) > 0 {
		if gameView == nil {
			return protocol.RulesPrompt{}, errors.New("Forge damage prompt has no viewer snapshot")
		}
		damageSource, damageTargets, err := projectedRulesDamage(
			view.DamageSource, view.DamageTargets, view.DamageDeathtouch, game, *gameView)
		if err != nil {
			return protocol.RulesPrompt{}, err
		}
		prompt.DamageSource = damageSource
		prompt.DamageTargets = damageTargets
	}
	return prompt, nil
}

func projectedRulesDamage(source *forge.PromptDamageSource,
	targets []forge.PromptDamageTarget, deathtouch bool, game forgeRoomGame,
	view forge.GameView) (*protocol.RulesPromptDamageSource,
	[]protocol.RulesPromptDamageTarget, error) {
	if source == nil {
		return nil, nil, errors.New("Forge damage source is missing")
	}
	sourceCard, exists := forgeCardByID(view.Zones, source.ID)
	if !exists || sourceCard.Visibility != "visible" || sourceCard.Identity == nil {
		return nil, nil, errors.New("Forge damage source is missing from the viewer snapshot")
	}
	projectedSource := &protocol.RulesPromptDamageSource{
		ObjectID: sourceCard.ID, Label: sourceCard.Identity.Name,
		Name: sourceCard.Identity.Name, SetCode: sourceCard.Identity.SetCode,
		CollectorNumber: sourceCard.Identity.CardNumber, Token: sourceCard.Identity.Token,
	}
	projectedTargets := make([]protocol.RulesPromptDamageTarget, 0, len(targets))
	for _, target := range targets {
		projected := protocol.RulesPromptDamageTarget{
			ResponseID: target.ResponseID, Kind: target.Kind, LethalDamage: -1,
		}
		switch target.Kind {
		case "player":
			playerIndex, err := forge.PlayerIndexFromID(target.ID)
			if err != nil {
				return nil, nil, err
			}
			seat, exists := game.playerToSeat[playerIndex]
			if !exists {
				return nil, nil, errors.New("Forge damage defender has no room seat")
			}
			player, exists := forgePlayerByID(view.Players, target.ID)
			if !exists {
				return nil, nil, errors.New("Forge damage defender is missing from the viewer snapshot")
			}
			projected.Label = fmt.Sprintf("Seat %d", seat+1)
			if strings.TrimSpace(player.Name) != "" {
				projected.Label = fmt.Sprintf("%s · Seat %d", player.Name, seat+1)
			}
		case "card":
			card, exists := forgeCardByID(view.Zones, target.ID)
			if !exists || card.Visibility != "visible" || card.Identity == nil {
				return nil, nil, errors.New("Forge damage target is missing from the viewer snapshot")
			}
			projected.ObjectID = card.ID
			applyRulesPromptDamageTargetIdentity(&projected, *card.Identity)
			if !target.Defender {
				lethal, err := rulesLethalDamage(card, deathtouch)
				if err != nil {
					return nil, nil, err
				}
				projected.LethalDamage = lethal
			}
		case "defender":
			projected.Label = "Defender"
		default:
			return nil, nil, errors.New("Forge damage target has an unsupported kind")
		}
		projectedTargets = append(projectedTargets, projected)
	}
	return projectedSource, projectedTargets, nil
}

func rulesLethalDamage(card forge.CardView, deathtouch bool) (int, error) {
	if deathtouch {
		return 1, nil
	}
	toughness, err := strconv.Atoi(strings.TrimSpace(card.Toughness))
	if err != nil || toughness < 0 || card.Damage < 0 {
		return 0, errors.New("Forge damage target has invalid toughness or marked damage")
	}
	lethal := toughness - card.Damage
	if lethal < 0 {
		lethal = 0
	}
	return lethal, nil
}

func projectedRulesCombat(sources []forge.PromptCombatSource,
	targets []forge.PromptCombatTarget, game forgeRoomGame,
	view forge.GameView) ([]protocol.RulesPromptCombatSource,
	[]protocol.RulesPromptCombatTarget, error) {
	projectedSources := make([]protocol.RulesPromptCombatSource, 0, len(sources))
	for _, source := range sources {
		card, exists := forgeCardByID(view.Zones, source.ID)
		if !exists || card.Visibility != "visible" || card.Identity == nil {
			return nil, nil, errors.New("Forge combat source is missing from the viewer snapshot")
		}
		projected := protocol.RulesPromptCombatSource{
			ResponseID: source.ResponseID, ObjectID: card.ID,
			ValidTargetIDs:   append([]string(nil), source.ValidTargetIDs...),
			MustAssignIfAble: source.MustAssignIfAble,
		}
		applyRulesPromptCombatSourceIdentity(&projected, *card.Identity)
		projectedSources = append(projectedSources, projected)
	}
	projectedTargets := make([]protocol.RulesPromptCombatTarget, 0, len(targets))
	for _, target := range targets {
		projected := protocol.RulesPromptCombatTarget{
			ResponseID: target.ResponseID, Kind: target.Kind, Label: target.Label,
			Minimum: target.Minimum, Maximum: target.Maximum,
			MustReceiveIfAble: target.MustReceiveIfAble,
		}
		switch target.Kind {
		case "player":
			playerIndex, err := forge.PlayerIndexFromID(target.ID)
			if err != nil {
				return nil, nil, err
			}
			seat, exists := game.playerToSeat[playerIndex]
			if !exists {
				return nil, nil, errors.New("Forge combat defender has no room seat")
			}
			player, exists := forgePlayerByID(view.Players, target.ID)
			if !exists {
				return nil, nil, errors.New("Forge combat defender is missing from the viewer snapshot")
			}
			projected.Label = fmt.Sprintf("Seat %d", seat+1)
			if strings.TrimSpace(player.Name) != "" {
				projected.Label = fmt.Sprintf("%s · Seat %d", player.Name, seat+1)
			}
		case "planeswalker", "battle", "attacker":
			card, exists := forgeCardByID(view.Zones, target.ID)
			if !exists || card.Visibility != "visible" || card.Identity == nil {
				return nil, nil, errors.New("Forge combat target is missing from the viewer snapshot")
			}
			projected.ObjectID = card.ID
			applyRulesPromptCombatTargetIdentity(&projected, *card.Identity)
		default:
			return nil, nil, errors.New("Forge combat target has an unsupported kind")
		}
		projectedTargets = append(projectedTargets, projected)
	}
	return projectedSources, projectedTargets, nil
}

func projectedRulesTargets(targets []forge.PromptTarget, game forgeRoomGame,
	view forge.GameView) ([]protocol.RulesPromptTarget, error) {
	result := make([]protocol.RulesPromptTarget, 0, len(targets))
	for _, target := range targets {
		projected := protocol.RulesPromptTarget{
			ResponseID: target.ResponseID, Kind: target.Kind,
		}
		switch target.Kind {
		case "player":
			playerIndex, err := forge.PlayerIndexFromID(target.ID)
			if err != nil {
				return nil, err
			}
			seat, exists := game.playerToSeat[playerIndex]
			if !exists {
				return nil, errors.New("Forge target player has no room seat")
			}
			player, exists := forgePlayerByID(view.Players, target.ID)
			if !exists {
				return nil, errors.New("Forge target player is missing from the viewer snapshot")
			}
			projected.Label = fmt.Sprintf("Seat %d", seat+1)
			if strings.TrimSpace(player.Name) != "" {
				projected.Label = fmt.Sprintf("%s · Seat %d", player.Name, seat+1)
			}
		case "card":
			card, exists := forgeCardByID(view.Zones, target.ID)
			if !exists {
				return nil, errors.New("Forge target card is missing from the viewer snapshot")
			}
			projected.ObjectID = card.ID
			projected.Label = "Face-down card"
			if card.Visibility == "visible" && card.Identity != nil {
				applyRulesPromptTargetIdentity(&projected, *card.Identity)
			}
		case "spell":
			stackObject, exists := forgeStackObjectByID(view.Stack, target.ID)
			if !exists {
				return nil, errors.New("Forge target spell is missing from the viewer snapshot")
			}
			projected.ObjectID = stackObject.ID
			projected.Label = "Spell on stack"
			applyRulesPromptTargetIdentity(&projected, stackObject.Identity)
		default:
			return nil, errors.New("Forge target has an unsupported kind")
		}
		result = append(result, projected)
	}
	return result, nil
}

func forgePlayerByID(players []forge.PlayerView, id string) (forge.PlayerView, bool) {
	for _, player := range players {
		if player.ID == id {
			return player, true
		}
	}
	return forge.PlayerView{}, false
}

func forgeCardByID(zones []forge.ZoneView, id string) (forge.CardView, bool) {
	for _, zone := range zones {
		for _, card := range zone.Cards {
			if card.ID == id {
				return card, true
			}
		}
	}
	return forge.CardView{}, false
}

func forgeStackObjectByID(stack []forge.StackObjectView,
	id string) (forge.StackObjectView, bool) {
	for _, object := range stack {
		if object.ID == id {
			return object, true
		}
	}
	return forge.StackObjectView{}, false
}

func applyRulesPromptTargetIdentity(target *protocol.RulesPromptTarget,
	identity forge.CardIdentityView) {
	if strings.TrimSpace(identity.Name) != "" {
		target.Label = identity.Name
	}
	target.Name = identity.Name
	target.SetCode = identity.SetCode
	target.CollectorNumber = identity.CardNumber
	target.Token = identity.Token
}

func applyRulesPromptCombatSourceIdentity(target *protocol.RulesPromptCombatSource,
	identity forge.CardIdentityView) {
	target.Label = identity.Name
	target.Name = identity.Name
	target.SetCode = identity.SetCode
	target.CollectorNumber = identity.CardNumber
	target.Token = identity.Token
}

func applyRulesPromptCombatTargetIdentity(target *protocol.RulesPromptCombatTarget,
	identity forge.CardIdentityView) {
	if strings.TrimSpace(identity.Name) != "" {
		target.Label = identity.Name
	}
	target.Name = identity.Name
	target.SetCode = identity.SetCode
	target.CollectorNumber = identity.CardNumber
	target.Token = identity.Token
}

func applyRulesPromptDamageTargetIdentity(target *protocol.RulesPromptDamageTarget,
	identity forge.CardIdentityView) {
	target.Label = identity.Name
	target.Name = identity.Name
	target.SetCode = identity.SetCode
	target.CollectorNumber = identity.CardNumber
	target.Token = identity.Token
}

// currentRulesPrompt tolerates both the pinned harness, whose getPrompt is
// session-global, and a future runtime that filters by playerIndex. The raw
// prompt stays server-private; only its authenticated owner receives a public
// projection.
func currentRulesPrompt(ctx context.Context,
	game forgeRoomGame) (*forge.PromptView, error) {
	playerIndexes := make([]int, 0, len(game.playerToSeat))
	for playerIndex := range game.playerToSeat {
		playerIndexes = append(playerIndexes, playerIndex)
	}
	sort.Ints(playerIndexes)
	for _, playerIndex := range playerIndexes {
		raw, err := game.client.Prompt(ctx, game.sessionID, playerIndex)
		if err != nil {
			return nil, err
		}
		if len(raw) == 0 {
			continue
		}
		view, err := forge.NormalizePrompt(raw)
		if err != nil {
			return nil, err
		}
		if _, exists := game.playerToSeat[view.PlayerIndex]; !exists {
			return nil, errors.New("Forge prompt owner is not a room player")
		}
		return &view, nil
	}
	return nil, nil
}

func waitForInitialForgePrompt(game forgeRoomGame) error {
	return waitForForgePromptChange(game, 0)
}

func waitForForgePromptChange(game forgeRoomGame, previousPromptID int64) error {
	ctx, cancel := context.WithTimeout(context.Background(), forgePromptTimeout)
	defer cancel()
	ticker := time.NewTicker(forgePromptPollInterval)
	defer ticker.Stop()
	for {
		view, err := currentRulesPrompt(ctx, game)
		if err != nil {
			return err
		}
		if view != nil && (previousPromptID == 0 || view.PromptID != previousPromptID) {
			return nil
		}
		gameOver, err := game.client.GameOver(ctx, game.sessionID)
		if err != nil {
			return err
		}
		if gameOver {
			return nil
		}
		select {
		case <-ctx.Done():
			return fmt.Errorf("Forge did not advance to a new prompt: %w", ctx.Err())
		case <-ticker.C:
		}
	}
}

func (h *Handler) sendRulesPrompts(prompts map[string]protocol.Envelope) {
	for connectionID, envelope := range prompts {
		if session := h.sessionByConn(connectionID); session != nil {
			h.send(session, envelope)
		}
	}
}

func (h *Handler) fanoutRulesPrompts(r *room.Room) {
	prompts, err := h.rulesPrompts(r)
	if err != nil {
		h.failClosedGameProjections(r, err)
		return
	}
	h.sendRulesPrompts(prompts)
}
