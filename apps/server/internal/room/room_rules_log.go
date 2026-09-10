// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package room

import (
	"fmt"
	"sort"
	"strings"

	"hexproof/server/internal/protocol"
)

// This journal retains only public observations, never engine prompts or a
// player's snapshot. It is not an authoritative copy of the rules game.
type rulesPublicLogState struct {
	gameID  string
	turn    int
	step    string
	active  int
	players map[int]protocol.RulesPlayerState
	cards   map[string]rulesPublicLogCard
	stack   map[string]int
	counts  map[string]int
	over    bool
}

type rulesPublicLogCard struct {
	name   string
	zone   string
	seat   int
	tapped bool
}

// ResetRulesLog starts a new match's bounded public journal. BO3 next-game
// transitions and host restarts deliberately keep the journal and its ids.
func (r *Room) ResetRulesLog() {
	r.RulesLog = []protocol.GameLogEntry{}
	r.RulesNextLogID = 1
	r.rulesPublicLog = nil
}

func (r *Room) AppendRulesLog(kind string, seat int, text string) {
	if r.RulesMode != protocol.RulesModeForge {
		return
	}
	if r.RulesNextLogID < 1 {
		r.RulesNextLogID = 1
	}
	r.RulesLog = append(r.RulesLog, protocol.GameLogEntry{
		ID: r.RulesNextLogID, Kind: kind, Seat: seat, Text: text,
	})
	r.RulesNextLogID++
	if len(r.RulesLog) > protocol.MaxRetainedGameLog {
		r.RulesLog = append([]protocol.GameLogEntry(nil),
			r.RulesLog[len(r.RulesLog)-protocol.MaxRetainedGameLog:]...)
	}
	if r.Game != nil {
		r.Game.Log = append([]protocol.GameLogEntry(nil), r.RulesLog...)
		r.Game.NextLogID = r.RulesNextLogID
	}
}

func (r *Room) RulesLogProjection() ([]protocol.GameLogEntry, int64, bool) {
	next := r.RulesNextLogID
	if next < 1 {
		next = 1
	}
	return projectGameLog(r.RulesLog, next)
}

// ObserveRulesPublicState accepts only the explicit spectator projection.
// Hidden-zone identities, face-down names, stack text and private decisions
// are excluded even if a malformed input accidentally includes them.
func (r *Room) ObserveRulesPublicState(snapshot protocol.RulesGameSnapshot) {
	if r.RulesMode != protocol.RulesModeForge || r.Phase != protocol.RoomPhaseStarted ||
		snapshot.RoomID != r.ID || snapshot.GameID == "" {
		return
	}
	next := &rulesPublicLogState{
		gameID: snapshot.GameID, turn: snapshot.Turn, step: snapshot.Step,
		active: snapshot.ActiveSeat, over: snapshot.GameOver,
		players: make(map[int]protocol.RulesPlayerState),
		cards:   make(map[string]rulesPublicLogCard),
		stack:   make(map[string]int), counts: make(map[string]int),
	}
	for _, player := range snapshot.Players {
		// Only copy public scalars used by the log, not arbitrary DTO fields.
		next.players[player.Seat] = protocol.RulesPlayerState{
			Seat: player.Seat, Life: player.Life, Status: player.Status,
		}
	}
	for _, zone := range snapshot.Zones {
		if zone.Zone == "hand" || zone.Zone == "library" {
			next.counts[fmt.Sprintf("%d:%s", zone.OwnerSeat, zone.Zone)] = zone.Count
			continue
		}
		switch zone.Zone {
		case "battlefield", "graveyard", "exile", "command":
		default:
			continue
		}
		for _, card := range zone.Cards {
			name := "a face-down card"
			if card.Visible && !card.FaceDown && card.Identity != nil &&
				strings.TrimSpace(card.Identity.Name) != "" {
				name = card.Identity.Name
			}
			next.cards[card.ID] = rulesPublicLogCard{
				name: name, zone: zone.Zone, seat: card.ControllerSeat, tapped: card.Tapped,
			}
		}
	}
	for _, item := range snapshot.Stack {
		// Face-down spell identity is not needed to describe stack activity.
		next.stack[item.ID] = item.ControllerSeat
	}
	previous := r.rulesPublicLog
	r.rulesPublicLog = next
	if previous == nil || previous.gameID != next.gameID {
		r.AppendRulesLog("rules_start", -1,
			fmt.Sprintf("Game %d started (Forge rules).", r.rulesGameNumber()))
		previous = &rulesPublicLogState{}
	}
	if previous.turn != next.turn || previous.step != next.step || previous.active != next.active {
		r.AppendRulesLog("rules_phase", next.active,
			fmt.Sprintf("Turn %d: %s (%s).", next.turn, r.rulesLogSeatName(next.active), next.step))
	}
	for _, player := range snapshot.Players {
		if old, ok := previous.players[player.Seat]; ok {
			if player.Life != old.Life {
				r.AppendRulesLog("rules_life", player.Seat, fmt.Sprintf("%s: life %d → %d.",
					r.rulesLogSeatName(player.Seat), old.Life, player.Life))
			}
			if player.Status != old.Status {
				r.AppendRulesLog("rules_status", player.Seat, fmt.Sprintf("%s: %s.",
					r.rulesLogSeatName(player.Seat), player.Status))
			}
		}
	}
	for _, key := range sortedRulesLogKeys(next.counts) {
		if old, ok := previous.counts[key]; ok && old != next.counts[key] {
			var seat int
			var zone string
			_, _ = fmt.Sscanf(key, "%d:%s", &seat, &zone)
			r.AppendRulesLog("rules_zone_count", seat, fmt.Sprintf("%s: %s count %d → %d.",
				r.rulesLogSeatName(seat), zone, old, next.counts[key]))
		}
	}
	for _, id := range sortedRulesLogKeys(next.cards) {
		card := next.cards[id]
		old, existed := previous.cards[id]
		if !existed || old.zone != card.zone || old.seat != card.seat || old.name != card.name {
			r.AppendRulesLog("rules_card", card.seat, fmt.Sprintf("%s: %s in %s.",
				r.rulesLogSeatName(card.seat), card.name, card.zone))
		} else if card.tapped != old.tapped {
			state := "untapped"
			if card.tapped {
				state = "tapped"
			}
			r.AppendRulesLog("rules_tap", card.seat, fmt.Sprintf("%s: %s %s.",
				r.rulesLogSeatName(card.seat), card.name, state))
		}
	}
	for _, id := range sortedRulesLogKeys(previous.cards) {
		if _, exists := next.cards[id]; !exists {
			old := previous.cards[id]
			r.AppendRulesLog("rules_card", old.seat, fmt.Sprintf("%s: %s left %s.",
				r.rulesLogSeatName(old.seat), old.name, old.zone))
		}
	}
	for _, id := range sortedRulesLogKeys(next.stack) {
		if _, exists := previous.stack[id]; !exists {
			seat := next.stack[id]
			r.AppendRulesLog("rules_stack", seat,
				fmt.Sprintf("%s put a spell or ability on the stack.", r.rulesLogSeatName(seat)))
		}
	}
	for _, id := range sortedRulesLogKeys(previous.stack) {
		if _, exists := next.stack[id]; !exists {
			seat := previous.stack[id]
			r.AppendRulesLog("rules_stack", seat,
				fmt.Sprintf("A spell or ability controlled by %s left the stack.", r.rulesLogSeatName(seat)))
		}
	}
	if next.over && !previous.over {
		seat := -1
		text := "Game ended without a winner."
		if snapshot.WinnerSeat != nil {
			seat = *snapshot.WinnerSeat
			text = fmt.Sprintf("%s won the game.", r.rulesLogSeatName(seat))
		}
		r.AppendRulesLog("rules_result", seat, text)
	}
}

func sortedRulesLogKeys[T any](values map[string]T) []string {
	keys := make([]string, 0, len(values))
	for key := range values {
		keys = append(keys, key)
	}
	sort.Strings(keys)
	return keys
}

func (r *Room) rulesLogSeatName(seat int) string {
	if seat >= 0 && seat < len(r.Seats) && r.Seats[seat].DisplayName != "" {
		return r.Seats[seat].DisplayName
	}
	return fmt.Sprintf("Seat %d", seat+1)
}

func (r *Room) SayRules(connID string, request protocol.GameSay) (Result, error) {
	if r.RulesMode != protocol.RulesModeForge || r.Phase != protocol.RoomPhaseStarted || r.Disbanded {
		return Result{}, newError(protocol.ErrGameNotStarted)
	}
	seat := r.FindSeatByConnection(connID)
	name := ""
	if seat >= 0 {
		name = r.Seats[seat].DisplayName
	} else {
		for _, spectator := range r.Spectators {
			if spectator.ConnectionID == connID {
				name = spectator.DisplayName
				break
			}
		}
	}
	if name == "" {
		return Result{}, newError(protocol.ErrNotInRoom)
	}
	message := strings.TrimSpace(request.Message)
	if !validGameChatMessage(message) {
		return Result{}, newError(protocol.ErrInvalidChat)
	}
	r.AppendRulesLog("chat", seat, fmt.Sprintf("%s: %s", name, message))
	reply, _ := protocol.NewEnvelope(protocol.TypeGameSaid,
		protocol.GameSaid{RoomID: r.ID, LogID: r.RulesNextLogID - 1})
	return Result{Reply: &reply, ProjectGame: true}, nil
}
