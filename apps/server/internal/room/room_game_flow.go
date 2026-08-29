// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package room

import (
	"fmt"
	"hexproof/server/internal/protocol"
	"strings"
	"time"
	"unicode"
	"unicode/utf8"
)

func (r *Room) appendGameLog(kind string, seat int, text string) {
	if r.Game == nil {
		return
	}
	// A public table event invalidates previously declared passes. Hold signals
	// remain explicit until their owner clears them or the phase changes.
	if kind != "response" {
		for index := range r.Game.Seats {
			if r.Game.Seats[index].ResponseStatus == protocol.ResponseStatusPass {
				r.Game.Seats[index].ResponseStatus = ""
			}
		}
	}
	r.Game.Log = append(r.Game.Log, protocol.GameLogEntry{
		ID: r.Game.NextLogID, Kind: kind, Seat: seat, Text: text,
	})
	r.Game.NextLogID++
	if len(r.Game.Log) > protocol.MaxRetainedGameLog {
		start := len(r.Game.Log) - protocol.MaxRetainedGameLog
		r.Game.Log = append([]protocol.GameLogEntry(nil), r.Game.Log[start:]...)
	}
}

func (r *Room) requireActiveGame() error {
	if r.Phase != protocol.RoomPhaseStarted || r.Game == nil {
		return newError(protocol.ErrGameNotStarted)
	}
	if r.Game.Result != nil {
		return newError(protocol.ErrGameFinished)
	}
	return nil
}

func (r *Room) requireStartedGame() error {
	if r.Phase != protocol.RoomPhaseStarted || r.Game == nil {
		return newError(protocol.ErrGameNotStarted)
	}
	return nil
}

func (r *Room) playerSeat(connID string, allowEliminated bool) (int, error) {
	seat := r.FindSeatByConnection(connID)
	if seat < 0 {
		if r.IsSpectator(connID) {
			return -1, newError(protocol.ErrNotPlayer)
		}
		return -1, newError(protocol.ErrNotInRoom)
	}
	if !allowEliminated && r.Game != nil && seat < len(r.Game.Seats) &&
		r.Game.Seats[seat].Eliminated {
		return -1, newError(protocol.ErrPlayerEliminated)
	}
	return seat, nil
}

// SetPhase updates the shared coordination marker without performing automatic
// game actions.
func (r *Room) SetPhase(connID string, request protocol.GameSetPhase) (Result, error) {
	if err := r.requireActiveGame(); err != nil {
		return Result{}, err
	}
	seat, err := r.playerSeat(connID, false)
	if err != nil {
		return Result{}, err
	}
	if seat != r.Game.ActiveSeat {
		return Result{}, newError(protocol.ErrNotActivePlayer)
	}
	if !protocol.ValidGamePhase(request.Phase) {
		return Result{}, newError(protocol.ErrInvalidPhase)
	}

	if r.Game.CurrentPhase != request.Phase {
		r.Game.CurrentPhase = request.Phase
		r.retainArrowsForPhase(request.Phase)
		r.clearResponseStatuses()
		r.appendGameLog("phase", seat,
			fmt.Sprintf("%s advanced to the %s step.",
				r.Game.Seats[seat].DisplayName, gamePhaseDisplayName(request.Phase)))
	}
	reply, _ := protocol.NewEnvelope(protocol.TypeGamePhaseSet,
		protocol.GamePhaseSet{RoomID: r.ID, Seat: seat, Phase: request.Phase})
	return Result{Reply: &reply, ProjectGame: true}, nil
}

// SetResponseStatus publishes one player's rules-neutral coordination signal.
// The status communicates intent only; it does not implement priority or stop
// any other tabletop command.
func (r *Room) SetResponseStatus(connID string,
	request protocol.GameSetResponseStatus) (Result, error) {
	if err := r.requireActiveGame(); err != nil {
		return Result{}, err
	}
	seat, err := r.playerSeat(connID, false)
	if err != nil {
		return Result{}, err
	}
	status := strings.TrimSpace(request.Status)
	if !protocol.ValidResponseStatus(status) {
		return Result{}, newError(protocol.ErrInvalidTarget)
	}
	storedStatus := status
	if status == protocol.ResponseStatusClear {
		storedStatus = ""
	}
	reply, _ := protocol.NewEnvelope(protocol.TypeGameResponseStatusSet,
		protocol.GameResponseStatusSet{
			RoomID: r.ID, Seat: seat, Status: status,
		})
	if r.Game.Seats[seat].ResponseStatus == storedStatus {
		return Result{Reply: &reply}, nil
	}
	r.Game.Seats[seat].ResponseStatus = storedStatus
	switch storedStatus {
	case protocol.ResponseStatusPass:
		r.appendGameLog("response", seat,
			fmt.Sprintf("%s has no response.", r.Game.Seats[seat].DisplayName))
	case protocol.ResponseStatusHold:
		r.appendGameLog("response", seat,
			fmt.Sprintf("%s asked the table to wait.",
				r.Game.Seats[seat].DisplayName))
	}
	return Result{Reply: &reply, ProjectGame: true}, nil
}

func (r *Room) clearResponseStatuses() {
	for index := range r.Game.Seats {
		r.Game.Seats[index].ResponseStatus = ""
	}
}

// retainArrowsForPhase keeps combat declarations visible through combat while
// ensuring a new combat and every noncombat phase start without stale arrows.
func (r *Room) retainArrowsForPhase(phase string) {
	switch phase {
	case protocol.GamePhaseDeclareBlockers:
		next := r.Game.Arrows[:0]
		for _, arrow := range r.Game.Arrows {
			if arrow.Kind == protocol.ArrowKindAttack {
				next = append(next, arrow)
			}
		}
		r.Game.Arrows = next
	case protocol.GamePhaseCombatDamage, protocol.GamePhaseEndCombat:
		next := r.Game.Arrows[:0]
		for _, arrow := range r.Game.Arrows {
			if arrow.Kind == protocol.ArrowKindAttack ||
				arrow.Kind == protocol.ArrowKindBlock {
				next = append(next, arrow)
			}
		}
		r.Game.Arrows = next
	default:
		r.Game.Arrows = []protocol.GameArrow{}
	}
}

// SetCounter changes one public counter owned by the acting player. Values may
// become negative and are not restricted to the active player; the server
// rejects attempts by spectators or against another seat.
func (r *Room) SetCounter(connID string, request protocol.GameSetCounter) (Result, error) {
	if err := r.requireActiveGame(); err != nil {
		return Result{}, err
	}
	seat, err := r.playerSeat(connID, false)
	if err != nil {
		return Result{}, err
	}
	operationCount := 0
	if request.Value != nil {
		operationCount++
	}
	if request.Delta != nil {
		operationCount++
	}
	if request.Label != nil {
		operationCount++
	}
	if operationCount != 1 {
		return Result{}, newError(protocol.ErrInvalidCounter)
	}

	state := &r.Game.Seats[seat]
	if request.Counter == protocol.PlayerCounterLife {
		if request.Value == nil ||
			*request.Value < protocol.MinPlayerCounterValue ||
			*request.Value > protocol.MaxPlayerCounterValue {
			return Result{}, newError(protocol.ErrInvalidCounter)
		}
		oldValue := state.Life
		reply, _ := protocol.NewEnvelope(protocol.TypeGameCounterSet,
			protocol.GameCounterSet{
				RoomID:  r.ID,
				Seat:    seat,
				Counter: request.Counter,
				Value:   *request.Value,
			})
		if *request.Value == oldValue {
			return Result{Reply: &reply}, nil
		}

		state.Life = *request.Value
		delta := int64(*request.Value) - int64(oldValue)
		r.appendGameLog("counter", seat,
			fmt.Sprintf("%s set life to %d (%+d).",
				state.DisplayName, *request.Value, delta))
		return Result{Reply: &reply, ProjectGame: true}, nil
	}

	counterIndex := -1
	for index := range state.Counters {
		if state.Counters[index].Key == request.Counter {
			counterIndex = index
			break
		}
	}
	if counterIndex < 0 {
		return Result{}, newError(protocol.ErrInvalidCounter)
	}

	counter := &state.Counters[counterIndex]
	if request.Label != nil {
		label := strings.TrimSpace(*request.Label)
		if !validPlayerCounterLabel(label) {
			return Result{}, newError(protocol.ErrInvalidCounter)
		}
		reply, _ := protocol.NewEnvelope(protocol.TypeGameCounterSet,
			protocol.GameCounterSet{
				RoomID:  r.ID,
				Seat:    seat,
				Counter: counter.Key,
				Value:   counter.Value,
				Label:   label,
			})
		if label == counter.Label {
			return Result{Reply: &reply}, nil
		}

		oldLabel := playerCounterDisplayName(*counter)
		counter.Label = label
		r.appendGameLog("counter", seat,
			fmt.Sprintf("%s renamed counter %s to %s.",
				state.DisplayName, oldLabel, label))
		return Result{Reply: &reply, ProjectGame: true}, nil
	}

	oldValue := counter.Value
	newValue := oldValue
	if request.Value != nil {
		if *request.Value < protocol.MinPlayerCounterValue ||
			*request.Value > protocol.MaxPlayerCounterValue {
			return Result{}, newError(protocol.ErrInvalidCounter)
		}
		newValue = *request.Value
	} else {
		if request.Delta == nil || (*request.Delta != -1 && *request.Delta != 1) {
			return Result{}, newError(protocol.ErrInvalidCounter)
		}
		nextValue := int64(oldValue) + int64(*request.Delta)
		if nextValue < protocol.MinPlayerCounterValue {
			nextValue = protocol.MinPlayerCounterValue
		}
		if nextValue > protocol.MaxPlayerCounterValue {
			nextValue = protocol.MaxPlayerCounterValue
		}
		newValue = int(nextValue)
	}

	reply, _ := protocol.NewEnvelope(protocol.TypeGameCounterSet,
		protocol.GameCounterSet{
			RoomID:  r.ID,
			Seat:    seat,
			Counter: counter.Key,
			Value:   newValue,
			Label:   counter.Label,
		})
	if newValue == oldValue {
		return Result{Reply: &reply}, nil
	}

	counter.Value = newValue
	delta := int64(newValue) - int64(oldValue)
	r.appendGameLog("counter", seat,
		fmt.Sprintf("%s set %s to %d (%+d).",
			state.DisplayName, playerCounterDisplayName(*counter),
			newValue, delta))
	return Result{Reply: &reply, ProjectGame: true}, nil
}

// SetCounterCount changes only the acting seat's public counter-slot display
// count. Counter values remain synchronized even while their slots are hidden.
func (r *Room) SetCounterCount(connID string,
	request protocol.GameSetCounterCount) (Result, error) {
	if err := r.requireActiveGame(); err != nil {
		return Result{}, err
	}
	seat, err := r.playerSeat(connID, false)
	if err != nil {
		return Result{}, err
	}
	if request.Count < 0 || request.Count > protocol.PlayerCounterSlotCount {
		return Result{}, newError(protocol.ErrInvalidCounter)
	}

	reply, _ := protocol.NewEnvelope(protocol.TypeGameCounterCountSet,
		protocol.GameCounterCountSet{
			RoomID: r.ID,
			Seat:   seat,
			Count:  request.Count,
		})
	if r.Game.Seats[seat].CounterCount == request.Count {
		return Result{Reply: &reply}, nil
	}
	r.Game.Seats[seat].CounterCount = request.Count
	return Result{Reply: &reply, ProjectGame: true}, nil
}

func playerCounterDisplayName(counter protocol.GamePlayerCounter) string {
	if counter.Label != "" {
		return counter.Label
	}
	return counter.Key
}

func validPlayerCounterLabel(label string) bool {
	if label == "" || !utf8.ValidString(label) ||
		utf8.RuneCountInString(label) > protocol.MaxPlayerCounterLabelRunes {
		return false
	}
	for _, char := range label {
		if unicode.IsControl(char) {
			return false
		}
	}
	return true
}

// ConcedeAt records a two-player game loss or eliminates one EDH player.
func (r *Room) ConcedeAt(connID string, now time.Time) (Result, error) {
	if err := r.requireActiveGame(); err != nil {
		return Result{}, err
	}
	seat, err := r.playerSeat(connID, false)
	if err != nil {
		return Result{}, err
	}
	if r.Format == protocol.FormatEDH {
		return r.concedeEDH(seat)
	}
	if !protocol.IsTwoPlayerFormat(r.Format) || len(r.Game.Seats) != 2 {
		return Result{}, newError(protocol.ErrUnsupportedFormat)
	}
	if now.IsZero() {
		return Result{}, newError(protocol.ErrInternal)
	}

	winnerSeat := 1 - seat
	if len(r.Score) != len(r.Game.Seats) {
		r.Score = make([]int, len(r.Game.Seats))
	}
	r.Score[winnerSeat]++
	winsRequired := 1
	if r.MatchMode == protocol.MatchBO3 {
		winsRequired = 2
	}
	matchFinished := r.Score[winnerSeat] >= winsRequired
	r.Game.ActiveSeat = -1
	r.Game.Result = &protocol.GameResult{
		Reason:        protocol.GameResultConcede,
		WinnerSeat:    winnerSeat,
		ConcededSeat:  seat,
		MatchFinished: matchFinished,
	}
	r.appendGameLog("concede", seat,
		fmt.Sprintf("%s conceded. %s wins Game %d.",
			r.Game.Seats[seat].DisplayName,
			r.Game.Seats[winnerSeat].DisplayName,
			r.Game.Number))

	result := Result{ProjectGame: true}
	if !matchFinished && r.MatchMode == protocol.MatchBO3 && r.canSideboard() {
		r.beginSideboard(seat, now.Add(sideboardDuration))
		result.SideboardDeadline = r.Game.Sideboard.Deadline
	}
	reply, _ := protocol.NewEnvelope(protocol.TypeGameConceded,
		protocol.GameConceded{
			RoomID:        r.ID,
			GameNumber:    r.Game.Number,
			ConcededSeat:  seat,
			WinnerSeat:    winnerSeat,
			Score:         append([]int{}, r.Score...),
			MatchFinished: matchFinished,
		})
	result.Reply = &reply
	return result, nil
}

func (r *Room) canSideboard() bool {
	if r.Format == protocol.FormatEDH || len(r.Seats) != 2 {
		return false
	}
	for _, seat := range r.Seats {
		if seat.Deck == nil {
			return false
		}
	}
	return true
}

func (r *Room) concedeEDH(seat int) (Result, error) {
	if len(r.Score) != len(r.Game.Seats) {
		r.Score = make([]int, len(r.Game.Seats))
	}
	state := &r.Game.Seats[seat]
	state.Eliminated = true
	r.appendGameLog("eliminate", seat,
		fmt.Sprintf("%s conceded and was eliminated.", state.DisplayName))

	remaining := 0
	winnerSeat := -1
	for index := range r.Game.Seats {
		if !r.Game.Seats[index].Eliminated {
			remaining++
			winnerSeat = index
		}
	}
	matchFinished := remaining <= 1
	replyWinnerSeat := -1
	if matchFinished {
		r.Game.ActiveSeat = -1
		if remaining == 1 {
			r.Score[winnerSeat] = 1
			replyWinnerSeat = winnerSeat
		}
		r.Game.Result = &protocol.GameResult{
			Reason:        protocol.GameResultConcede,
			WinnerSeat:    replyWinnerSeat,
			ConcededSeat:  seat,
			MatchFinished: true,
		}
		if remaining == 1 {
			r.appendGameLog("result", winnerSeat,
				fmt.Sprintf("%s wins the Commander game.",
					r.Game.Seats[winnerSeat].DisplayName))
		} else {
			r.appendGameLog("result", -1,
				"The Commander game ended with no remaining players.")
		}
	} else if r.Game.ActiveSeat == seat {
		r.Game.ActiveSeat = r.nextActiveSeat(seat)
		r.Game.CurrentPhase = protocol.GamePhaseUntap
		r.Game.LandPlaysThisTurn = 0
	}

	reply, _ := protocol.NewEnvelope(protocol.TypeGameConceded,
		protocol.GameConceded{
			RoomID:        r.ID,
			GameNumber:    r.Game.Number,
			ConcededSeat:  seat,
			WinnerSeat:    replyWinnerSeat,
			Score:         append([]int{}, r.Score...),
			MatchFinished: matchFinished,
		})
	return Result{Reply: &reply, ProjectGame: true}, nil
}

// CanReturnToRoom validates the post-match transition without mutating state.
func (r *Room) CanReturnToRoom(connID string) error {
	if err := r.requireStartedGame(); err != nil {
		return err
	}
	if !r.Member(connID) {
		return newError(protocol.ErrNotInRoom)
	}
	if r.Game.Result == nil || !r.Game.Result.MatchFinished || r.Game.Sideboard != nil {
		return newError(protocol.ErrMatchNotFinished)
	}
	return nil
}

// ReturnToRoom closes a completed match for the whole room. It restores every
// selected deck's registered partition so BO3 sideboarding cannot leak into a
// later match in the same room. Everyone must ready again for the new match.
func (r *Room) ReturnToRoom(connID string) (Result, error) {
	if err := r.CanReturnToRoom(connID); err != nil {
		return Result{}, err
	}

	r.Phase = protocol.RoomPhaseWaiting
	r.Game = nil
	r.Score = make([]int, len(r.Seats))
	r.DrawnGames = 0
	for index := range r.Seats {
		if r.Seats[index].RegisteredDeck != nil {
			deck := cloneDeck(*r.Seats[index].RegisteredDeck)
			r.Seats[index].Deck = &deck
		}
		r.Seats[index].Ready = false
		r.Seats[index].Loaded = false
	}

	reply, _ := protocol.NewEnvelope(protocol.TypeGameReturnedToRoom,
		protocol.GameReturnedToRoom{RoomID: r.ID})
	return Result{
		Reply:     &reply,
		Broadcast: []protocol.Envelope{r.snapshotEnvelope()},
	}, nil
}

func (r *Room) nextActiveSeat(current int) int {
	if r.Game == nil || len(r.Game.Seats) == 0 {
		return -1
	}
	currentIndex := -1
	for index, seat := range r.Game.TurnOrder {
		if seat == current {
			currentIndex = index
			break
		}
	}
	if currentIndex >= 0 {
		for offset := 1; offset <= len(r.Game.TurnOrder); offset++ {
			candidate := r.Game.TurnOrder[(currentIndex+offset)%len(r.Game.TurnOrder)]
			if candidate >= 0 && candidate < len(r.Game.Seats) &&
				!r.Game.Seats[candidate].Eliminated {
				return candidate
			}
		}
		return -1
	}
	for offset := 1; offset <= len(r.Game.Seats); offset++ {
		candidate := (current + offset) % len(r.Game.Seats)
		if !r.Game.Seats[candidate].Eliminated {
			return candidate
		}
	}
	return -1
}

// Say appends one explicit player or spectator message to the public game log.
// Chat remains available after a game result so room members can discuss the
// finished game; unlike gameplay mutations it does not alter game state.
func (r *Room) Say(connID string, request protocol.GameSay) (Result, error) {
	if err := r.requireStartedGame(); err != nil {
		return Result{}, err
	}

	seat := r.FindSeatByConnection(connID)
	displayName := ""
	if seat >= 0 {
		displayName = r.Seats[seat].DisplayName
	} else {
		seat = -1
		for _, spectator := range r.Spectators {
			if spectator.ConnectionID == connID {
				displayName = spectator.DisplayName
				break
			}
		}
		if displayName == "" {
			return Result{}, newError(protocol.ErrNotInRoom)
		}
	}

	message := strings.TrimSpace(request.Message)
	if !validGameChatMessage(message) {
		return Result{}, newError(protocol.ErrInvalidChat)
	}
	logID := r.Game.NextLogID
	r.appendGameLog("chat", seat, fmt.Sprintf("%s: %s", displayName, message))
	reply, _ := protocol.NewEnvelope(protocol.TypeGameSaid,
		protocol.GameSaid{RoomID: r.ID, LogID: logID})
	return Result{Reply: &reply, ProjectGame: true}, nil
}

func validGameChatMessage(message string) bool {
	if message == "" || !utf8.ValidString(message) ||
		utf8.RuneCountInString(message) > protocol.MaxGameSayRunes {
		return false
	}
	for _, char := range message {
		if unicode.IsControl(char) {
			return false
		}
	}
	return true
}

// NextTurn advances the active seat in table order and resets the phase marker
// to untap. It does not untap permanents, draw cards, or apply rules actions.
func (r *Room) NextTurn(connID string) (Result, error) {
	if err := r.requireActiveGame(); err != nil {
		return Result{}, err
	}
	seat, err := r.playerSeat(connID, false)
	if err != nil {
		return Result{}, err
	}
	if seat != r.Game.ActiveSeat {
		return Result{}, newError(protocol.ErrNotActivePlayer)
	}

	r.Game.ActiveSeat = r.nextActiveSeat(r.Game.ActiveSeat)
	r.Game.CurrentPhase = protocol.GamePhaseUntap
	r.Game.LandPlaysThisTurn = 0
	r.Game.Arrows = []protocol.GameArrow{}
	r.clearResponseStatuses()
	if r.Game.ActiveSeat >= 0 && r.Game.ActiveSeat < len(r.Game.Seats) {
		r.appendGameLog("turn", r.Game.ActiveSeat,
			fmt.Sprintf("%s began their turn.",
				r.Game.Seats[r.Game.ActiveSeat].DisplayName))
	}
	reply, _ := protocol.NewEnvelope(protocol.TypeGameTurnAdvanced,
		protocol.GameTurnAdvanced{
			RoomID:       r.ID,
			ActiveSeat:   r.Game.ActiveSeat,
			CurrentPhase: r.Game.CurrentPhase,
		})
	return Result{Reply: &reply, ProjectGame: true}, nil
}

func gamePhaseDisplayName(phase string) string {
	switch phase {
	case protocol.GamePhaseUntap:
		return "Untap"
	case protocol.GamePhaseUpkeep:
		return "Upkeep"
	case protocol.GamePhaseDraw:
		return "Draw"
	case protocol.GamePhaseFirstMain:
		return "Main 1"
	case protocol.GamePhaseBeginningCombat:
		return "Begin combat"
	case protocol.GamePhaseDeclareAttackers:
		return "Attackers"
	case protocol.GamePhaseDeclareBlockers:
		return "Blockers"
	case protocol.GamePhaseCombatDamage:
		return "Damage"
	case protocol.GamePhaseEndCombat:
		return "End combat"
	case protocol.GamePhaseSecondMain:
		return "Main 2"
	case protocol.GamePhaseEnd:
		return "End"
	default:
		return phase
	}
}

// Mulligan returns the acting player's hand to their library, shuffles the
// full library, draws a replacement hand of up to seven cards, and records
// how many manual mulligans that player has taken this game.
func (r *Room) Mulligan(connID string) (Result, error) {
	if err := r.requireActiveGame(); err != nil {
		return Result{}, err
	}
	seat, err := r.playerSeat(connID, false)
	if err != nil {
		return Result{}, err
	}
	state := &r.Game.Seats[seat]
	replacementLibrary := append(append([]protocol.GameCard{}, state.Library...), state.Hand...)
	if err := r.shuffle(replacementLibrary); err != nil {
		return Result{}, newError(protocol.ErrGameSetupFailed)
	}
	state.Library = replacementLibrary
	state.Hand = []protocol.GameCard{}
	drawCards(state, 7)
	state.MulliganCount++
	r.appendGameLog("mulligan", seat,
		fmt.Sprintf("%s took mulligan %d and drew %d cards.",
			state.DisplayName, state.MulliganCount, len(state.Hand)))
	reply, _ := protocol.NewEnvelope(protocol.TypeGameMulliganed,
		protocol.GameMulliganed{
			RoomID:        r.ID,
			Seat:          seat,
			HandSize:      len(state.Hand),
			MulliganCount: state.MulliganCount,
		})
	return Result{Reply: &reply, ProjectGame: true}, nil
}

// DiscardHand moves either one server-random card or the acting player's
// complete hand to the cards' immutable-owner graveyards in one operation.
func (r *Room) DiscardHand(connID string, all bool) (Result, error) {
	if err := r.requireActiveGame(); err != nil {
		return Result{}, err
	}
	seat, err := r.playerSeat(connID, false)
	if err != nil {
		return Result{}, err
	}
	state := &r.Game.Seats[seat]
	if len(state.Hand) == 0 {
		return Result{}, newError(protocol.ErrInvalidMove)
	}

	discarded := []protocol.GameCard{}
	if all {
		discarded = append(discarded, state.Hand...)
		state.Hand = nil
	} else {
		index, randomErr := r.randomIndex(len(state.Hand))
		if randomErr != nil {
			return Result{}, newError(protocol.ErrGameSetupFailed)
		}
		discarded = append(discarded, state.Hand[index])
		state.Hand = append(state.Hand[:index], state.Hand[index+1:]...)
	}

	for _, card := range discarded {
		ownerSeat := card.OwnerSeat
		if ownerSeat < 0 || ownerSeat >= len(r.Game.Seats) {
			ownerSeat = seat
		}
		if card.Token {
			continue
		}
		card.Position = nil
		card.Tapped = false
		card.Counters = nil
		card.FaceName = ""
		card.FaceDown = false
		r.putOwnedCard(&r.Game.Seats[ownerSeat], ownerSeat,
			protocol.ZoneGraveyard, card)
	}
	if all {
		r.appendGameLog("discard_hand", seat,
			fmt.Sprintf("%s discarded their hand (%d cards).",
				state.DisplayName, len(discarded)))
	} else {
		cardName := discarded[0].Name
		if cardName == "" {
			cardName = "a card"
		}
		r.appendGameLog("discard_random", seat,
			fmt.Sprintf("%s randomly discarded %s.", state.DisplayName, cardName))
	}
	reply, _ := protocol.NewEnvelope(protocol.TypeGameHandDiscarded,
		protocol.GameHandDiscarded{
			RoomID: r.ID,
			Seat:   seat,
			Count:  len(discarded),
		})
	return Result{Reply: &reply, ProjectGame: true}, nil
}
