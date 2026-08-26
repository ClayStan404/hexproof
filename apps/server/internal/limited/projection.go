// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package limited

import "hexproof/server/internal/protocol"

func cardView(card *CardInstance) protocol.LimitedCardView {
	return protocol.LimitedCardView{
		InstanceID: card.ID, Name: card.Name, SetCode: card.SetCode,
		CollectorNumber: card.CollectorNumber, TypeLine: card.TypeLine,
		Rarity: card.Rarity, Finish: card.Finish,
	}
}

func cardViews(cards []*CardInstance) []protocol.LimitedCardView {
	result := make([]protocol.LimitedCardView, 0, len(cards))
	for _, card := range cards {
		result = append(result, cardView(card))
	}
	return result
}

func (e *Event) Snapshot(participantID string) protocol.LimitedSnapshot {
	snapshot := protocol.LimitedSnapshot{
		TournamentID: e.TournamentID, EventType: e.EventType, Stage: e.Stage,
		Product: e.Product.View(), PackRound: e.packRound, Direction: e.Direction(),
		CurrentPack: []protocol.LimitedCardView{}, Pool: []protocol.LimitedCardView{},
		MainboardInstanceIDs: []string{}, BasicLands: []protocol.LimitedBasicLand{},
		Participants:      []protocol.LimitedParticipantView{},
		AllDecksSubmitted: e.AllDecksSubmitted(),
	}
	for _, player := range e.Players {
		packCards := 0
		if len(player.Inbox) > 0 {
			packCards = len(player.Inbox[0].Cards)
		}
		snapshot.Participants = append(snapshot.Participants, protocol.LimitedParticipantView{
			ParticipantID: player.ID, DisplayName: player.DisplayName,
			Picked: len(player.Pool), PackCards: packCards,
			QueuedPacks: len(player.Inbox), DeckSubmitted: player.Deck != nil,
		})
		if player.ID == participantID {
			snapshot.Pool = cardViews(player.Pool)
			snapshot.MainboardInstanceIDs = append(
				[]string(nil), player.MainboardInstanceIDs...)
			snapshot.BasicLands = append(
				[]protocol.LimitedBasicLand(nil), player.BasicLands...)
			if len(player.Inbox) > 0 {
				snapshot.CurrentPack = cardViews(player.Inbox[0].Cards)
			}
			snapshot.DeckSubmitted = player.Deck != nil
		}
	}
	return snapshot
}
