// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package server

import (
	"context"
	"crypto/rand"
	"errors"
	"fmt"
	"log"
	"math/big"
	"strings"
	"time"

	"hexproof/server/internal/protocol"
	"hexproof/server/internal/room"
	"hexproof/server/internal/rulesengine/forge"
)

const (
	forgeGameStartTimeout = 45 * time.Second
	forgeCleanupTimeout   = 5 * time.Second
)

// forgeRoomGame is private lifecycle metadata. Decks and private projections
// are never cached here; reconnect always asks Forge for a fresh viewer view.
type forgeRoomGame struct {
	client       *forge.Client
	sessionID    string
	gameID       string
	seatToPlayer map[int]int
	playerToSeat map[int]int
}

type forgeStartState struct {
	projections map[string]protocol.Envelope
	prompts     map[string]protocol.Envelope
}

func (h *Handler) forgeClientForUse(ctx context.Context) (*forge.Client, error) {
	h.forgeMu.Lock()
	defer h.forgeMu.Unlock()
	if h.forgeClosed || h.forgeRuntime == nil {
		return nil, errors.New("Forge rules runtime is unavailable")
	}
	if h.forgeClient != nil {
		return h.forgeClient, nil
	}
	client, err := forge.Start(ctx, *h.forgeRuntime)
	if err != nil {
		return nil, fmt.Errorf("start Forge rules runtime: %w", err)
	}
	h.forgeClient = client
	return client, nil
}

// startForgeGame starts one authoritative engine session and prepares the
// first role-specific projection before match.started is published. Failure
// therefore leaves the handler free to roll the room back to waiting.
func (h *Handler) startForgeGame(r *room.Room) (forgeStartState, error) {
	players, err := h.hub.RulesStartPlayers(r)
	if err != nil {
		return forgeStartState{}, err
	}
	request, seatOrder, err := forgeStartRequest(r, players)
	if err != nil {
		return forgeStartState{}, err
	}
	ctx, cancel := context.WithTimeout(context.Background(), forgeGameStartTimeout)
	defer cancel()
	client, err := h.forgeClientForUse(ctx)
	if err != nil {
		return forgeStartState{}, err
	}
	handle, err := client.StartGame(ctx, request)
	if err != nil {
		return forgeStartState{}, fmt.Errorf("start Forge game: %w", err)
	}
	game, err := forgeRoomGameFromHandle(client, request.GameID, seatOrder, handle)
	if err != nil {
		h.abortUntrackedForgeGame(client, handle.SessionID)
		return forgeStartState{}, err
	}

	h.forgeMu.Lock()
	if h.forgeClosed {
		h.forgeMu.Unlock()
		h.abortUntrackedForgeGame(client, handle.SessionID)
		return forgeStartState{}, errors.New("Forge rules runtime is shutting down")
	}
	if _, exists := h.forgeGames[r.ID]; exists {
		h.forgeMu.Unlock()
		h.abortUntrackedForgeGame(client, handle.SessionID)
		return forgeStartState{}, errors.New("Forge game already exists for room")
	}
	h.forgeGames[r.ID] = game
	h.forgeMu.Unlock()

	if err := waitForInitialForgePrompt(game); err != nil {
		h.abortForgeGame(r.ID)
		return forgeStartState{}, fmt.Errorf("wait for initial Forge prompt: %w", err)
	}
	projections, err := h.rulesProjections(r)
	if err != nil {
		h.abortForgeGame(r.ID)
		return forgeStartState{}, fmt.Errorf("prepare Forge projections: %w", err)
	}
	prompts, err := h.rulesPrompts(r)
	if err != nil {
		h.abortForgeGame(r.ID)
		return forgeStartState{}, fmt.Errorf("prepare Forge prompts: %w", err)
	}
	return forgeStartState{projections: projections, prompts: prompts}, nil
}

func forgeStartRequest(r *room.Room, players []room.RulesStartPlayer) (
	forge.StartGameRequest, []int, error) {
	if r == nil || len(players) < 2 {
		return forge.StartGameRequest{}, nil, errors.New("Forge game requires at least two players")
	}
	seedLimit := new(big.Int).SetUint64(^uint64(0) >> 1)
	seedValue, err := rand.Int(rand.Reader, seedLimit)
	if err != nil {
		return forge.StartGameRequest{}, nil, fmt.Errorf("generate Forge game seed: %w", err)
	}
	variant := "Constructed"
	startingLife := 20
	if protocol.IsCommanderFormat(r.Format) {
		variant = "Commander"
	}
	if r.Format == protocol.FormatEDH {
		startingLife = 40
	}
	request := forge.StartGameRequest{
		GameID:       fmt.Sprintf("%s-%d", r.ID, r.LoadID),
		Variant:      variant,
		StartingLife: startingLife,
		Seed:         seedValue.Int64(),
		Players:      make([]forge.PlayerConfig, 0, len(players)),
	}
	seatOrder := make([]int, 0, len(players))
	for _, player := range players {
		cards := make([]forge.CardIdentity, 0)
		for _, entry := range player.Deck.Mainboard {
			if entry.Count <= 0 {
				return forge.StartGameRequest{}, nil,
					fmt.Errorf("seat %d has an invalid card quantity", player.Seat)
			}
			for copyIndex := 0; copyIndex < entry.Count; copyIndex++ {
				cards = append(cards, forge.CardIdentity{
					Name:            entry.Name,
					SetCode:         entry.SetCode,
					CollectorNumber: entry.CollectorNumber,
				})
			}
		}
		request.Players = append(request.Players, forge.PlayerConfig{
			Name:           player.DisplayName,
			Deck:           cards,
			CommanderNames: rulesCommanderNames(player.Deck),
		})
		seatOrder = append(seatOrder, player.Seat)
	}
	return request, seatOrder, nil
}

func rulesCommanderNames(deck protocol.DeckSelect) []string {
	raw := deck.Commanders
	if len(raw) == 0 && strings.TrimSpace(deck.Commander) != "" {
		raw = []string{deck.Commander}
	}
	result := make([]string, 0, len(raw))
	for _, value := range raw {
		name := strings.TrimSpace(value)
		if name == "" {
			continue
		}
		duplicate := false
		for _, existing := range result {
			if strings.EqualFold(existing, name) {
				duplicate = true
				break
			}
		}
		if !duplicate {
			result = append(result, name)
		}
	}
	return result
}

func forgeRoomGameFromHandle(client *forge.Client, gameID string, seatOrder []int,
	handle forge.SessionHandle) (forgeRoomGame, error) {
	if strings.TrimSpace(handle.SessionID) == "" || len(handle.PlayerIndexes) != len(seatOrder) {
		return forgeRoomGame{}, errors.New("Forge returned an invalid session handle")
	}
	game := forgeRoomGame{
		client:       client,
		sessionID:    handle.SessionID,
		gameID:       gameID,
		seatToPlayer: make(map[int]int, len(seatOrder)),
		playerToSeat: make(map[int]int, len(seatOrder)),
	}
	for index, seat := range seatOrder {
		playerIndex := handle.PlayerIndexes[index]
		if playerIndex < 0 || playerIndex >= 8 {
			return forgeRoomGame{}, errors.New("Forge returned an invalid player index")
		}
		if _, duplicate := game.playerToSeat[playerIndex]; duplicate {
			return forgeRoomGame{}, errors.New("Forge returned duplicate player indexes")
		}
		game.seatToPlayer[seat] = playerIndex
		game.playerToSeat[playerIndex] = seat
	}
	return game, nil
}

func (h *Handler) abortUntrackedForgeGame(client *forge.Client, sessionID string) {
	if client == nil || strings.TrimSpace(sessionID) == "" {
		return
	}
	ctx, cancel := context.WithTimeout(context.Background(), forgeCleanupTimeout)
	defer cancel()
	if err := client.AbortGame(ctx, sessionID); err != nil {
		log.Printf("abort untracked Forge game failed: %v", err)
	}
}

func (h *Handler) abortForgeGame(roomID string) {
	h.forgeMu.Lock()
	game, ok := h.forgeGames[roomID]
	if ok {
		delete(h.forgeGames, roomID)
	}
	h.forgeMu.Unlock()
	if ok {
		h.abortUntrackedForgeGame(game.client, game.sessionID)
	}
}

func (h *Handler) finishForgeGame(roomID string, game forgeRoomGame) {
	h.forgeMu.Lock()
	current, ok := h.forgeGames[roomID]
	if ok && current.sessionID == game.sessionID {
		delete(h.forgeGames, roomID)
	} else {
		ok = false
	}
	h.forgeMu.Unlock()
	if !ok {
		return
	}
	ctx, cancel := context.WithTimeout(context.Background(), forgeCleanupTimeout)
	defer cancel()
	if err := game.client.EndGame(ctx, game.sessionID); err != nil {
		log.Printf("end completed Forge game %s: %v", roomID, err)
	}
}

// Close releases the optional long-lived Forge process. HTTP shutdown closes
// WebSocket sessions separately; quit terminates all remaining engine games.
func (h *Handler) Close() error {
	h.forgeMu.Lock()
	if h.forgeClosed {
		h.forgeMu.Unlock()
		return nil
	}
	h.forgeClosed = true
	client := h.forgeClient
	h.forgeClient = nil
	h.forgeGames = make(map[string]forgeRoomGame)
	h.forgeMu.Unlock()
	if client == nil {
		return nil
	}
	return client.Close()
}
