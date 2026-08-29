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
	if e.Stage != protocol.LimitedStageDraft {
		return 0, fail(ErrPickUnavailable, "draft is not active")
	}
	player := e.Player(participantID)
	if player == nil {
		return 0, fail(ErrForbidden, "participant does not own a draft seat")
	}
	if len(player.Inbox) == 0 {
		return 0, fail(ErrPickUnavailable, "no pack is available")
	}
	pack := player.Inbox[0]
	cardIndex := -1
	for index, card := range pack.Cards {
		if card.ID == instanceID {
			cardIndex = index
			break
		}
	}
	if cardIndex < 0 {
		return 0, fail(ErrPickUnavailable, "card is not in the current pack")
	}
	player.Pool = append(player.Pool, pack.Cards[cardIndex])
	pack.Cards = append(pack.Cards[:cardIndex], pack.Cards[cardIndex+1:]...)
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

func (e *Event) drainSingletons() error {
	for {
		changed := false
		for _, player := range e.Players {
			for len(player.Inbox) > 0 && len(player.Inbox[0].Cards) == 1 {
				pack := player.Inbox[0]
				player.Pool = append(player.Pool, pack.Cards[0])
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
