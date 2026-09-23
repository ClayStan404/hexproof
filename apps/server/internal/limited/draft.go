// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package limited

import "hexproof/server/internal/protocol"

func (e *Event) Direction() int {
	batch := (e.packRound + max(1, e.packsPerBatch) - 1) / max(1, e.packsPerBatch)
	if batch == 0 || batch%2 == 1 {
		return 1
	}
	return -1
}

func (e *Event) startDraftRound() error {
	if e.packRound >= e.packCount {
		e.Stage = protocol.LimitedStageDeckBuilding
		return nil
	}
	e.packsThisBatch = min(max(1, e.packsPerBatch), e.packCount-e.packRound)
	e.packRound += e.packsThisBatch
	for _, player := range e.Players {
		var batch *Pack
		for index := 0; index < e.packsThisBatch; index++ {
			cards, err := e.nextPack()
			if err != nil {
				return err
			}
			e.packSeq++
			pack := &Pack{ID: "pack-" + itoa(e.packSeq), Cards: cards}
			if batch == nil {
				batch = pack
			} else {
				batch.Companion = pack
			}
		}
		player.Inbox = append(player.Inbox, batch)
	}
	return e.advanceDraft()
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
	if len(instanceIDs) != e.picksForPack(pack) {
		return 0, fail(ErrPickUnavailable, "incorrect number of cards selected")
	}
	selected := make(map[string]bool, len(instanceIDs))
	for _, id := range instanceIDs {
		if selected[id] {
			return 0, fail(ErrPickUnavailable, "a physical card cannot be picked twice")
		}
		selected[id] = true
	}
	// Validate every physical pack before moving any card or either pack.
	for _, part := range pack.parts() {
		found := 0
		for _, card := range part.Cards {
			if selected[card.ID] {
				found++
			}
		}
		if found != min(e.PicksPerSelection(), len(part.Cards)) {
			return 0, fail(ErrPickUnavailable, "select the required cards from each current pack")
		}
	}
	for _, part := range pack.parts() {
		remainingCards := make([]*CardInstance, 0, len(part.Cards))
		for _, card := range part.Cards {
			if selected[card.ID] {
				player.Pool = append(player.Pool, card)
			} else {
				remainingCards = append(remainingCards, card)
			}
		}
		part.Cards = remainingCards
	}
	player.Inbox = player.Inbox[1:]
	if pack.cardCount() > 0 {
		target := e.targetPlayer(player)
		target.Inbox = append(target.Inbox, pack)
	}
	if err := e.advanceDraft(); err != nil {
		return 0, err
	}
	remaining := 0
	if len(player.Inbox) > 0 {
		remaining = player.Inbox[0].cardCount()
	}
	return remaining, nil
}

func (e *Event) picksForPack(pack *Pack) int {
	count := 0
	for _, part := range pack.parts() {
		count += min(e.PicksPerSelection(), len(part.Cards))
	}
	return count
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
	return e.advanceDraft()
}

// advanceDraft drains explicitly automated seats, then opens the next batch
// only when every manual seat has confirmed its final selection.
func (e *Event) advanceDraft() error {
	// Every successful iteration removes physical cards from a pack. The
	// Locked stock and the configured pack count bound even an all-auto pod.
	for {
		changed := false
		for _, player := range e.Players {
			for len(player.Inbox) > 0 && player.AutoDraft {
				pack := player.Inbox[0]
				for _, part := range pack.parts() {
					if len(part.Cards) <= e.PicksPerSelection() {
						player.Pool = append(player.Pool, part.Cards...)
						part.Cards = nil
					} else {
						// Random picks obey each pack's quota without replacement.
						for pick := 0; pick < e.PicksPerSelection(); pick++ {
							index := e.random.Intn(len(part.Cards))
							player.Pool = append(player.Pool, part.Cards[index])
							part.Cards = append(part.Cards[:index], part.Cards[index+1:]...)
						}
					}
				}
				if pack.cardCount() > 0 {
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
