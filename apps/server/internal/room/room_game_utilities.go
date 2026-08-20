// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package room

import (
	"fmt"
	"strings"
	"time"

	"hexproof/server/internal/protocol"
)

// DeclareDrawAt ends the current game without awarding a win. BO3 continues
// through the ordinary sideboard gate with no previous loser.
func (r *Room) DeclareDrawAt(connID string, now time.Time) (Result, error) {
	if err := r.requireActiveGame(); err != nil {
		return Result{}, err
	}
	seat, err := r.playerSeat(connID, false)
	if err != nil {
		return Result{}, err
	}
	continues := r.MatchMode == protocol.MatchBO3
	if continues && !r.canSideboard() {
		return Result{}, newError(protocol.ErrGameSetupFailed)
	}
	if now.IsZero() {
		return Result{}, newError(protocol.ErrInternal)
	}
	if len(r.Score) != len(r.Game.Seats) {
		r.Score = make([]int, len(r.Game.Seats))
	}
	r.DrawnGames++
	r.Game.ActiveSeat = -1
	r.Game.Result = &protocol.GameResult{
		Reason:        protocol.GameResultDraw,
		WinnerSeat:    -1,
		ConcededSeat:  -1,
		MatchFinished: !continues,
	}
	r.appendGameLog("draw", seat,
		fmt.Sprintf("%s declared Game %d a draw.",
			r.Game.Seats[seat].DisplayName, r.Game.Number))

	result := Result{ProjectGame: true}
	if continues {
		r.beginSideboard(-1, now.Add(sideboardDuration))
		result.SideboardDeadline = r.Game.Sideboard.Deadline
	}
	reply, _ := protocol.NewEnvelope(protocol.TypeGameDrawDeclared,
		protocol.GameDrawDeclared{
			RoomID:        r.ID,
			GameNumber:    r.Game.Number,
			DeclaredSeat:  seat,
			Score:         append([]int{}, r.Score...),
			DrawnGames:    r.DrawnGames,
			MatchFinished: !continues,
		})
	result.Reply = &reply
	return result, nil
}

// RestartGame rebuilds the current game from committed decks while preserving
// its number, match score, and starting player.
func (r *Room) RestartGame(connID string) (Result, error) {
	if err := r.requireActiveGame(); err != nil {
		return Result{}, err
	}
	if !r.IsHost(connID) {
		return Result{}, newError(protocol.ErrNotHost)
	}
	hostSeat := r.FindSeatByConnection(connID)
	gameNumber := r.Game.Number
	startingSeat := r.Game.StartingSeat
	displayName := r.Game.Seats[hostSeat].DisplayName
	if err := r.setupGameNumber(gameNumber, startingSeat); err != nil {
		return Result{}, newError(protocol.ErrGameSetupFailed)
	}
	if len(r.Game.Log) > 0 &&
		(r.Game.Log[0].Kind == "roll" ||
			r.Game.Log[0].Kind == "starting_player") {
		r.Game.Log = r.Game.Log[1:]
	}
	for index := range r.Game.Log {
		r.Game.Log[index].ID = int64(index + 2)
	}
	r.Game.Log = append([]protocol.GameLogEntry{{
		ID: 1, Kind: "restart", Seat: hostSeat,
		Text: fmt.Sprintf("%s restarted Game %d.", displayName, gameNumber),
	}}, r.Game.Log...)
	r.Game.NextLogID = int64(len(r.Game.Log) + 1)

	reply, _ := protocol.NewEnvelope(protocol.TypeGameRestarted,
		protocol.GameRestarted{
			RoomID: r.ID, GameNumber: gameNumber, StartingSeat: startingSeat,
		})
	return Result{Reply: &reply, ProjectGame: true}, nil
}

// RollDice produces public server-generated dice results.
func (r *Room) RollDice(connID string, request protocol.GameRoll) (Result, error) {
	if err := r.requireActiveGame(); err != nil {
		return Result{}, err
	}
	seat, err := r.playerSeat(connID, false)
	if err != nil {
		return Result{}, err
	}
	count := request.Count
	if count == 0 {
		count = 1
	}
	if request.Sides < 2 || request.Sides > protocol.MaxDiceSides ||
		count < 1 || count > protocol.MaxDiceCount {
		return Result{}, newError(protocol.ErrInvalidMessage)
	}
	rolls := make([]int, count)
	total := 0
	for index := range rolls {
		value, randomErr := r.randomIndex(request.Sides)
		if randomErr != nil {
			return Result{}, newError(protocol.ErrGameSetupFailed)
		}
		rolls[index] = value + 1
		total += rolls[index]
	}
	r.appendGameLog("roll", seat,
		fmt.Sprintf("%s rolled %s on %dd%d (total %d).",
			r.Game.Seats[seat].DisplayName, formatIntegerList(rolls),
			count, request.Sides, total))
	reply, _ := protocol.NewEnvelope(protocol.TypeGameRolled,
		protocol.GameRolled{
			RoomID: r.ID, Seat: seat, Sides: request.Sides,
			Rolls: rolls, Total: total,
		})
	return Result{Reply: &reply, ProjectGame: true}, nil
}

// FlipCoin produces one public server-generated heads/tails result.
func (r *Room) FlipCoin(connID string) (Result, error) {
	if err := r.requireActiveGame(); err != nil {
		return Result{}, err
	}
	seat, err := r.playerSeat(connID, false)
	if err != nil {
		return Result{}, err
	}
	value, err := r.randomIndex(2)
	if err != nil {
		return Result{}, newError(protocol.ErrGameSetupFailed)
	}
	coinResult := "heads"
	if value == 1 {
		coinResult = "tails"
	}
	r.appendGameLog("coin", seat,
		fmt.Sprintf("%s flipped %s.",
			r.Game.Seats[seat].DisplayName, coinResult))
	reply, _ := protocol.NewEnvelope(protocol.TypeGameCoinFlipped,
		protocol.GameCoinFlipped{
			RoomID: r.ID, Seat: seat, Result: coinResult,
		})
	return Result{Reply: &reply, ProjectGame: true}, nil
}

// RandomSelect chooses an active player or one explicit public battlefield
// card. Card identity appears in the public log only when already face up.
func (r *Room) RandomSelect(connID string,
	request protocol.GameRandomSelect) (Result, error) {
	if err := r.requireActiveGame(); err != nil {
		return Result{}, err
	}
	seat, err := r.playerSeat(connID, false)
	if err != nil {
		return Result{}, err
	}
	reply := protocol.GameRandomSelected{
		RoomID: r.ID, Seat: seat, Kind: request.Kind, SelectedSeat: -1,
	}
	switch request.Kind {
	case protocol.RandomSelectionPlayer:
		if len(request.CardIDs) != 0 {
			return Result{}, newError(protocol.ErrInvalidTarget)
		}
		candidates := make([]int, 0, len(r.Game.Seats))
		for index := range r.Game.Seats {
			if !r.Game.Seats[index].Eliminated {
				candidates = append(candidates, index)
			}
		}
		if len(candidates) == 0 {
			return Result{}, newError(protocol.ErrInvalidTarget)
		}
		selected, randomErr := r.randomIndex(len(candidates))
		if randomErr != nil {
			return Result{}, newError(protocol.ErrGameSetupFailed)
		}
		reply.SelectedSeat = candidates[selected]
		r.appendGameLog("random_select", seat,
			fmt.Sprintf("%s randomly selected %s.",
				r.Game.Seats[seat].DisplayName,
				r.Game.Seats[reply.SelectedSeat].DisplayName))
	case protocol.RandomSelectionCard:
		if len(request.CardIDs) < 1 ||
			len(request.CardIDs) > protocol.MaxRandomCardCandidates {
			return Result{}, newError(protocol.ErrInvalidTarget)
		}
		cards := make([]protocol.GameCard, 0, len(request.CardIDs))
		seen := make(map[string]struct{}, len(request.CardIDs))
		for _, rawCardID := range request.CardIDs {
			cardID := strings.TrimSpace(rawCardID)
			if cardID == "" {
				return Result{}, newError(protocol.ErrInvalidTarget)
			}
			if _, exists := seen[cardID]; exists {
				return Result{}, newError(protocol.ErrInvalidTarget)
			}
			seen[cardID] = struct{}{}
			cardSeat, cardIndex, found := r.battlefieldCard(cardID)
			if !found {
				return Result{}, newError(protocol.ErrInvalidTarget)
			}
			cards = append(cards, r.Game.Seats[cardSeat].Battlefield[cardIndex])
		}
		selected, randomErr := r.randomIndex(len(cards))
		if randomErr != nil {
			return Result{}, newError(protocol.ErrGameSetupFailed)
		}
		card := cards[selected]
		reply.SelectedCardID = card.ID
		cardDescription := card.Name
		if card.FaceDown {
			cardDescription = "a face-down card"
		}
		r.appendGameLog("random_select", seat,
			fmt.Sprintf("%s randomly selected %s.",
				r.Game.Seats[seat].DisplayName, cardDescription))
	default:
		return Result{}, newError(protocol.ErrInvalidTarget)
	}

	envelope, _ := protocol.NewEnvelope(protocol.TypeGameRandomSelected, reply)
	return Result{Reply: &envelope, ProjectGame: true}, nil
}

func formatIntegerList(values []int) string {
	parts := make([]string, len(values))
	for index, value := range values {
		parts[index] = fmt.Sprintf("%d", value)
	}
	return "[" + strings.Join(parts, ", ") + "]"
}
