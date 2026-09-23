// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package server

import (
	"fmt"
	"testing"
	"time"

	"hexproof/server/internal/protocol"
	"hexproof/server/internal/room"
)

func BenchmarkForgeMetadataProjection(b *testing.B) {
	for _, stage := range []string{"live", "sideboard", "completed"} {
		b.Run(stage, func(b *testing.B) {
			now := time.Unix(1, 0)
			r, err := room.NewWithRulesMode("BENCH1", "Forge", protocol.FormatModern,
				protocol.MatchBO3, protocol.CardLoadBackground, protocol.RulesModeForge,
				2, true, false, "Host", "host", now)
			if err != nil {
				b.Fatal(err)
			}
			if _, err := r.Join("guest", "Guest", false, ""); err != nil {
				b.Fatal(err)
			}
			for _, connection := range []string{"host", "guest"} {
				deck := protocol.DeckSelect{Name: "Deck", Format: protocol.FormatModern}
				for index := range 45 {
					card := protocol.DeckCard{Name: fmt.Sprintf("Card %d", index), Count: 2,
						SetCode: "TST", CollectorNumber: fmt.Sprint(index)}
					if index < 30 {
						deck.Mainboard = append(deck.Mainboard, card)
					} else {
						card.Count = 1
						deck.Sideboard = append(deck.Sideboard, card)
					}
				}
				if _, err := r.SelectDeck(connection, deck); err != nil {
					b.Fatal(err)
				}
			}
			for index := range 32 {
				r.RulesLog = append(r.RulesLog, protocol.GameLogEntry{
					ID: int64(index + 1), Kind: "rules", Text: "Host cast a spell.",
				})
			}
			r.RulesNextLogID = int64(len(r.RulesLog) + 1)
			r.Phase = protocol.RoomPhaseStarted
			if stage != "live" {
				if stage == "completed" {
					r.Score = []int{1, 0}
				}
				if _, err := r.CompleteRulesGame(0, now); err != nil {
					b.Fatal(err)
				}
			}
			b.ReportAllocs()
			b.ResetTimer()
			for index := 0; index < b.N; index++ {
				if _, err := gameProjectionEnvelope(r, "host", 1); err != nil {
					b.Fatal(err)
				}
			}
		})
	}
}
