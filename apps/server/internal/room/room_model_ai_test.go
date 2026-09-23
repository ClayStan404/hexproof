// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package room

import (
	"hexproof/server/internal/protocol"
	"testing"
)

func TestModelAIPracticeLifecycle(t *testing.T) {
	for _, source := range []string{protocol.AISourceLocal, protocol.AISourceOnline} {
		for _, load := range []string{protocol.CardLoadPreload, protocol.CardLoadBackground} {
			t.Run(source+"/"+load, func(t *testing.T) {
				r, err := NewWithRulesMode("AIMODE", "Model", protocol.FormatModern, protocol.MatchBO1, load, protocol.RulesModeForge, 2, true, false, "Human", "human", testNow)
				if err != nil {
					t.Fatal(err)
				}
				if err := r.AddAI(source, "hard"); err == nil {
					t.Fatal("model accepted native difficulty")
				}
				if err := r.AddAI(source, ""); err != nil {
					t.Fatal(err)
				}
				if r.Seats[1].Controller != protocol.SeatControllerModelAI || r.Snapshot().AISource != source || r.ListEntry().AISource != source {
					t.Fatal("missing model identity")
				}
				deck := testDeck(protocol.FormatModern)
				if _, err := r.ConfigureAI("human", protocol.RoomAIConfigure{Deck: &deck}); err != nil {
					t.Fatal(err)
				}
				if _, err := r.ConfigureAI("human", protocol.RoomAIConfigure{Difficulty: "normal"}); err == nil {
					t.Fatal("model accepted native difficulty update")
				}
				if _, err := r.SelectDeck("human", deck); err != nil {
					t.Fatal(err)
				}
				res, err := r.SetReady("human", true)
				if err != nil {
					t.Fatal(err)
				}
				if load == protocol.CardLoadPreload {
					res, err = r.CompleteLoad("human", r.LoadID)
				}
				if err != nil || !res.StartRulesGame || !r.Seats[1].Loaded {
					t.Fatalf("model blocked start: %+v %v", res, err)
				}
				if _, err := r.CompleteRulesGame(1, testNow); err != nil {
					t.Fatal(err)
				}
				if _, err := r.ReturnToRoom("human"); err != nil {
					t.Fatal(err)
				}
				if !r.Seats[1].Ready || r.Seats[0].Ready {
					t.Fatal("model rematch readiness lost")
				}
				_, empty, err := r.ExpireDisconnected("human")
				if err != nil || !empty || !r.Disbanded {
					t.Fatal("model retained abandoned room")
				}
			})
		}
	}
}
