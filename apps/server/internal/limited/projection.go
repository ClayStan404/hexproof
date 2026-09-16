// SPDX-License-Identifier: GPL-3.0-or-later
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
		CommanderInstanceIDs: []string{}, PicksRequired: e.PicksPerSelection(),
		PacksPerPlayer: e.packCount, PacksThisBatch: e.packsThisBatch,
		MinimumDeckCards:  e.MinimumDeckCards(),
		Participants:      []protocol.LimitedParticipantView{},
		AllDecksSubmitted: e.AllDecksSubmitted(),
	}
	for _, player := range e.Players {
		packCards := 0
		if len(player.Inbox) > 0 {
			packCards = player.Inbox[0].cardCount()
		}
		queuedPacks := 0
		for _, pack := range player.Inbox {
			queuedPacks += len(pack.parts())
		}
		snapshot.Participants = append(snapshot.Participants, protocol.LimitedParticipantView{
			ParticipantID: player.ID, DisplayName: player.DisplayName,
			Picked: len(player.Pool), PackCards: packCards,
			QueuedPacks: queuedPacks, DeckSubmitted: player.Deck != nil,
			AutoDraft: player.AutoDraft, Withdrawn: player.Withdrawn,
		})
		if player.ID == participantID {
			snapshot.Pool = cardViews(player.Pool)
			snapshot.FallbackCommanders = cardViews(e.fallbackCommanders(player.ID))
			snapshot.OptionalCards = cardViews(e.optionalCards(player.ID))
			snapshot.MainboardInstanceIDs = append(
				[]string(nil), player.MainboardInstanceIDs...)
			snapshot.CommanderInstanceIDs = append(
				[]string(nil), player.CommanderInstanceIDs...)
			snapshot.CommanderColors = append(
				[]protocol.LimitedCommanderColor(nil), player.CommanderColors...)
			snapshot.BasicLands = append(
				[]protocol.LimitedBasicLand(nil), player.BasicLands...)
			if len(player.Inbox) > 0 {
				snapshot.PicksRequired = e.picksForPack(player.Inbox[0])
				for _, part := range player.Inbox[0].parts() {
					cards := cardViews(part.Cards)
					snapshot.CurrentPack = append(snapshot.CurrentPack, cards...)
					snapshot.CurrentPacks = append(snapshot.CurrentPacks, protocol.LimitedDraftPackView{
						PackID: part.ID, Cards: cards, PicksRequired: min(e.PicksPerSelection(), len(part.Cards)),
					})
				}
			}
			snapshot.DeckSubmitted = player.Deck != nil
		}
	}
	return snapshot
}
