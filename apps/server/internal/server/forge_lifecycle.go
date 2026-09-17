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
	"sync"
	"time"

	"hexproof/server/internal/protocol"
	"hexproof/server/internal/room"
	"hexproof/server/internal/rulesengine/forge"
)

const (
	forgeGameStartTimeout = 45 * time.Second
	forgeCleanupTimeout   = 5 * time.Second
)

var errForgeCapacity = errors.New("Forge game capacity is full")

func forgeStartFailure(err error) (string, string) {
	if errors.Is(err, errForgeCapacity) {
		return protocol.ErrServerLimit, "Forge game capacity is full; wait for a game to finish, then ready again. Your seats and decks are kept"
	}
	return protocol.ErrRulesUnavailable, "Forge could not start the game; the room is waiting for players to ready again"
}

// forgeRoomGame is private lifecycle metadata. Decks and private projections
// are never cached here; reconnect always asks Forge for a fresh viewer view.
type forgeRoomGame struct {
	client       forge.Runtime
	sessionID    string
	gameID       string
	seatToPlayer map[int]int
	playerToSeat map[int]int
	promptState  *forgePromptState
}

type forgeStartState struct {
	projections map[string]protocol.Envelope
	prompts     map[string]protocol.Envelope
}

// startForgeRuntime reserves an isolated game lease: a fresh process by
// default, or a slot in an explicitly configured shared worker. Serialize
// admission/cold startups while established games run independently.
func (h *Handler) startForgeRuntime(ctx context.Context, roomID string) (*forge.Client, error) {
	for {
		if err := ctx.Err(); err != nil {
			return nil, err
		}
		h.forgeMu.Lock()
		if h.forgeClosed || h.forgeRuntime == nil || time.Now().Before(h.forgeRetryAfter) {
			h.forgeMu.Unlock()
			return nil, errors.New("Forge rules runtime is unavailable")
		}
		// Reserve capacity before spawning Java. A process remains charged
		// until Wait has reaped it, even if it is unhealthy or closing. Check
		// Done directly so a next game need not wait for its old watcher.
		occupied := len(h.forgeReservations)
		reservedClients := make(map[forge.Runtime]bool, occupied)
		for _, client := range h.forgeReservations {
			reservedClients[client] = true
		}
		for client := range h.forgeClients {
			if _, local := client.(*forge.Client); !local {
				continue
			}
			if reservedClients[client] {
				continue
			}
			select {
			case <-client.Done():
			default:
				occupied++
			}
		}
		if h.forgeStarting != nil {
			occupied++
		}
		if previous, reserved := h.forgeReservations[roomID]; reserved {
			// Keep the same match's slot across sideboarding/restart, but
			// never overlap its previous JVM with the replacement.
			select {
			case <-previous.Done():
				occupied--
			default:
				h.forgeMu.Unlock()
				select {
				case <-previous.Done():
					continue
				case <-ctx.Done():
					return nil, ctx.Err()
				}
			}
		}
		if occupied >= h.config.MaxForgeGames {
			h.forgeMu.Unlock()
			return nil, errForgeCapacity
		}
		if starting := h.forgeStarting; starting != nil {
			h.forgeMu.Unlock()
			select {
			case <-starting:
				continue
			case <-ctx.Done():
				return nil, ctx.Err()
			}
		}
		starting := make(chan struct{})
		delete(h.forgeReservations, roomID)
		h.forgeStarting = starting
		startCtx, cancel := context.WithCancel(ctx)
		h.forgeStartCancel = cancel
		config := *h.forgeRuntime
		h.forgeMu.Unlock()

		var client *forge.Client
		var err error
		if h.forgePool != nil {
			client, err = h.forgePool.Acquire(startCtx)
		} else {
			client, err = forge.Start(startCtx, config)
		}
		cancel()
		h.forgeMu.Lock()
		closed := h.forgeClosed
		if err == nil && !closed && client.Healthy() {
			h.forgeClients[client] = struct{}{}
			go h.watchForgeRuntime(client)
		} else {
			if err == nil {
				err = errors.New("Forge rules runtime is unavailable")
			}
			h.forgeRetryAfter = time.Now().Add(forgeRestartCooldown)
		}
		if err != nil && client != nil {
			// Close must not return while a canceled startup still owns a
			// child. Keep the single-flight notification open until cleanup.
			h.forgeMu.Unlock()
			_ = client.Close()
			h.forgeMu.Lock()
		}
		h.forgeStarting = nil
		h.forgeStartCancel = nil
		close(starting)
		h.forgeMu.Unlock()
		if err != nil {
			return nil, errors.New("Forge rules runtime is unavailable")
		}
		return client, nil
	}
}

// startForgeGame starts one authoritative engine session and prepares the
// first role-specific projection before match.started is published. Failure
// therefore leaves the handler free to roll the room back to waiting.
func (h *Handler) startForgeGame(r *room.Room) (forgeStartState, error) {
	defer h.refreshPlayerHostStatus(r)
	players, err := h.hub.RulesStartPlayers(r)
	if err != nil {
		return forgeStartState{}, err
	}
	request, seatOrder, err := forgeStartRequest(r, players)
	if err != nil {
		return forgeStartState{}, err
	}
	startTimeout := forgeGameStartTimeout
	if r.HostingMode == "player" {
		startTimeout += h.config.ReconnectWindow
	}
	ctx, cancel := context.WithTimeout(context.Background(), startTimeout)
	defer cancel()
	client, err := h.startRoomForgeRuntime(ctx, r)
	if err != nil {
		h.forgeMu.Lock()
		delete(h.forgeReservations, r.ID)
		h.forgeMu.Unlock()
		return forgeStartState{}, err
	}
	handle, err := client.StartGame(ctx, request)
	if err != nil {
		_ = client.Close()
		return forgeStartState{}, fmt.Errorf("start Forge game: %w", err)
	}
	game, err := forgeRoomGameFromHandle(client, request.GameID, seatOrder, handle)
	if err != nil {
		h.abortUntrackedForgeGame(client, handle.SessionID)
		return forgeStartState{}, err
	}

	h.forgeMu.Lock()
	_, tracked := h.forgeClients[client]
	if h.forgeClosed || !tracked || !client.Healthy() {
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
		if r.RulesStartingSeat != nil && player.Seat == *r.RulesStartingSeat {
			index := len(request.Players)
			request.StartingPlayerIndex = &index
		}
		expand := func(entries []protocol.DeckCard) ([]forge.CardIdentity, error) {
			cards := make([]forge.CardIdentity, 0)
			for _, entry := range entries {
				if entry.Count <= 0 {
					return nil, fmt.Errorf("seat %d has an invalid card quantity", player.Seat)
				}
				for copyIndex := 0; copyIndex < entry.Count; copyIndex++ {
					cards = append(cards, forge.CardIdentity{
						Name: entry.Name, SetCode: entry.SetCode, CollectorNumber: entry.CollectorNumber,
					})
				}
			}
			return cards, nil
		}
		cards, err := expand(player.Deck.Mainboard)
		if err != nil {
			return forge.StartGameRequest{}, nil, err
		}
		sideboard, err := expand(player.Deck.Sideboard)
		if err != nil {
			return forge.StartGameRequest{}, nil, err
		}
		request.Players = append(request.Players, forge.PlayerConfig{
			Name:           player.DisplayName,
			Deck:           cards,
			Sideboard:      sideboard,
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

func forgeRoomGameFromHandle(client forge.Runtime, gameID string, seatOrder []int,
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
		promptState:  &forgePromptState{},
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

func (h *Handler) abortUntrackedForgeGame(client forge.Runtime, sessionID string) {
	if client == nil {
		return
	}
	defer client.Close()
	if strings.TrimSpace(sessionID) == "" {
		return
	}
	ctx, cancel := context.WithTimeout(context.Background(), forgeCleanupTimeout)
	defer cancel()
	if err := client.AbortGame(ctx, sessionID); err != nil {
		log.Print("abort untracked Forge game failed")
	}
}

func (h *Handler) abortForgeGame(roomID string) {
	h.closeForgeGame(roomID, false)
}

func (h *Handler) closeForgeGame(roomID string, keepSlot bool) {
	h.cancelPlayerHostMigration(roomID)
	h.forgeMu.Lock()
	game, ok := h.forgeGames[roomID]
	if ok {
		delete(h.forgeGames, roomID)
	}
	_, localProcess := game.client.(*forge.Client)
	if keepSlot && ok && localProcess {
		h.forgeReservations[roomID] = game.client
	} else if !keepSlot {
		delete(h.forgeReservations, roomID)
	}
	h.forgeMu.Unlock()
	if ok {
		h.abortUntrackedForgeGame(game.client, game.sessionID)
	}
}

func (h *Handler) finishForgeGame(roomID string, game forgeRoomGame, keepSlot bool) {
	h.forgeMu.Lock()
	current, ok := h.forgeGames[roomID]
	if ok && current.sessionID == game.sessionID {
		delete(h.forgeGames, roomID)
		if _, local := game.client.(*forge.Client); keepSlot && local {
			h.forgeReservations[roomID] = game.client
		}
	} else {
		ok = false
	}
	h.forgeMu.Unlock()
	if !ok {
		return
	}
	defer game.client.Close()
	ctx, cancel := context.WithTimeout(context.Background(), forgeCleanupTimeout)
	defer cancel()
	if err := game.client.EndGame(ctx, game.sessionID); err != nil {
		log.Printf("end completed Forge game %s failed", roomID)
	}
}

// Close stops tournament cleanup timers and reaps every owned Forge process,
// including processes reserved by a startGame call. HTTP shutdown closes
// WebSocket sessions separately.
func (h *Handler) Close() error {
	h.forgeCloseOnce.Do(func() {
		h.tournaments.close()
		h.forgeMu.Lock()
		h.forgeClosed = true
		if h.forgeStartCancel != nil {
			h.forgeStartCancel()
		}
		starting := h.forgeStarting
		links := h.playerHosts
		h.playerHosts = nil
		peers := h.playerPeers
		h.playerPeers = nil
		backups := h.playerBackups
		h.playerBackups = nil
		clients := h.forgeClients
		h.forgeClients = make(map[forge.Runtime]struct{})
		h.forgeReservations = make(map[string]forge.Runtime)
		h.forgeGames = make(map[string]forgeRoomGame)
		h.forgeMu.Unlock()
		for _, peer := range peers {
			if peer.binding != nil {
				peer.binding.cancel()
			}
		}
		for _, link := range links {
			link.Close()
		}
		for _, backup := range backups {
			if backup.cancel != nil {
				backup.cancel()
			}
			backup.link.Close()
		}
		if starting != nil {
			<-starting
		}
		var children sync.WaitGroup
		results := make(chan error, len(clients))
		for client := range clients {
			children.Add(1)
			go func() {
				defer children.Done()
				results <- client.Close()
			}()
		}
		children.Wait()
		close(results)
		for err := range results {
			h.forgeCloseErr = errors.Join(h.forgeCloseErr, err)
		}
		if h.forgePool != nil {
			h.forgeCloseErr = errors.Join(h.forgeCloseErr, h.forgePool.Close())
		}
	})
	return h.forgeCloseErr
}
