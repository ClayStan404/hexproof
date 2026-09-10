// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package limited

import "hexproof/server/internal/protocol"

func (e *Event) Direction() int {
	if e.packRound == 0 || e.packRound%2 == 1 {
		return 1
	}
	return -1
}

func (e *Event) startDraftRound() error {
	if e.packRound >= e.packCount {
		e.Stage = protocol.LimitedStageDeckBuilding
		return nil
	}
	e.packRound++
	for _, player := range e.Players {
		cards, err := e.nextPack()
		if err != nil {
			return err
		}
		e.packSeq++
		player.Inbox = append(player.Inbox, &Pack{ID: "pack-" + itoa(e.packSeq), Cards: cards})
	}
	return e.drainSingletons()
}

func (e *Event) targetPlayer(player *PlayerState) *PlayerState {
	index := -1
	for candidateIndex, candidate := range e.Players {
		if candidate == player {
			index = candidateIndex
			break
		}
	}
	if index < 0 {
		return nil
	}
	target := (index + e.Direction() + len(e.Players)) % len(e.Players)
	return e.Players[target]
}

func (e *Event) Pick(participantID, instanceID string) (int, error) {
	return e.PickCards(participantID, []string{instanceID})
}

// PickCards validates the complete selection before moving any physical card.
// A two-card pick passes the remaining pack once, never between selected cards.
func (e *Event) PickCards(participantID string, instanceIDs []string) (int, error) {
	if e.Stage != protocol.LimitedStageDraft {
		return 0, fail(ErrPickUnavailable, "draft is not active")
	}
	player := e.Player(participantID)
	if player == nil {
		return 0, fail(ErrForbidden, "participant does not own a draft seat")
	}
	if player.AutoDraft {
		return 0, fail(ErrPickUnavailable, "reclaim draft control before picking cards")
	}
	if len(player.Inbox) == 0 {
		return 0, fail(ErrPickUnavailable, "no pack is available")
	}
	pack := player.Inbox[0]
	if len(instanceIDs) != min(e.PicksPerSelection(), len(pack.Cards)) {
		return 0, fail(ErrPickUnavailable, "incorrect number of cards selected")
	}
	selected := make(map[string]bool, len(instanceIDs))
	for _, id := range instanceIDs {
		if selected[id] {
			return 0, fail(ErrPickUnavailable, "a physical card cannot be picked twice")
		}
		selected[id] = true
	}
	picked := make([]*CardInstance, 0, len(instanceIDs))
	remainingCards := make([]*CardInstance, 0, len(pack.Cards)-len(instanceIDs))
	for _, card := range pack.Cards {
		if selected[card.ID] {
			picked = append(picked, card)
		} else {
			remainingCards = append(remainingCards, card)
		}
	}
	if len(picked) != len(instanceIDs) {
		return 0, fail(ErrPickUnavailable, "card is not in the current pack")
	}
	player.Pool = append(player.Pool, picked...)
	pack.Cards = remainingCards
	player.Inbox = player.Inbox[1:]
	if len(pack.Cards) > 0 {
		target := e.targetPlayer(player)
		target.Inbox = append(target.Inbox, pack)
	}
	if err := e.drainSingletons(); err != nil {
		return 0, err
	}
	remaining := 0
	if len(player.Inbox) > 0 {
		remaining = len(player.Inbox[0].Cards)
	}
	return remaining, nil
}

// SetAutoDraft is called only after the coordinator authorizes explicit seat
// control. Automatic picks retain the physical seat and never reveal its pool.
func (e *Event) SetAutoDraft(participantID string, automatic bool) error {
	if e.Stage != protocol.LimitedStageDraft || !isCubeEvent(e.EventType) {
		return fail(ErrPickUnavailable, "Cube draft is not active")
	}
	player := e.Player(participantID)
	if player == nil {
		return fail(ErrForbidden, "participant does not own a draft seat")
	}
	player.AutoDraft = automatic
	return e.drainSingletons()
}

func (e *Event) drainSingletons() error {
	// Every successful iteration removes physical cards from a pack. The
	// locked Cube stock and three rounds therefore bound even an all-auto pod.
	for {
		changed := false
		for _, player := range e.Players {
			for len(player.Inbox) > 0 && (player.AutoDraft || len(player.Inbox[0].Cards) <= e.PicksPerSelection()) {
				pack := player.Inbox[0]
				if len(pack.Cards) <= e.PicksPerSelection() {
					player.Pool = append(player.Pool, pack.Cards...)
				} else {
					// Draw without replacement, then pass once for an atomic pick-two.
					for pick := 0; pick < e.PicksPerSelection(); pick++ {
						index := e.random.Intn(len(pack.Cards))
						player.Pool = append(player.Pool, pack.Cards[index])
						pack.Cards = append(pack.Cards[:index], pack.Cards[index+1:]...)
					}
					target := e.targetPlayer(player)
					target.Inbox = append(target.Inbox, pack)
				}
				player.Inbox = player.Inbox[1:]
				changed = true
			}
		}
		if !changed {
			break
		}
	}
	if e.Stage != protocol.LimitedStageDraft {
		return nil
	}
	for _, player := range e.Players {
		if len(player.Inbox) > 0 {
			return nil
		}
	}
	return e.startDraftRound()
}
