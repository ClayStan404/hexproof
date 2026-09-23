// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package room

import (
	"fmt"
	"reflect"
	"testing"

	"hexproof/server/internal/protocol"
)

func TestSideboardMovePreservesCombinedEntryLimit(t *testing.T) {
	for _, fromMain := range []bool{true, false} {
		for _, scenario := range []string{"split", "whole_entry", "merge"} {
			t.Run(fmt.Sprintf("from_main_%t/%s", fromMain, scenario), func(t *testing.T) {
				r := newTestRoom(t, 2, false)
				r.Format = protocol.FormatModern
				r.DeckFormat = protocol.DeckFormatLimited
				player := SideboardPlayerState{Ready: true}
				for index := range protocol.MaxDeckEntries {
					card := protocol.DeckCard{
						Name: fmt.Sprintf("Pool card %d", index), Count: 1,
						SetCode: "TST", CollectorNumber: fmt.Sprint(index),
					}
					if index < protocol.MaxDeckEntries/2 {
						player.Mainboard = append(player.Mainboard, card)
					} else {
						player.Sideboard = append(player.Sideboard, card)
					}
				}
				source, target := &player.Mainboard, &player.Sideboard
				from, to := protocol.SideboardZoneMain, protocol.SideboardZoneSide
				if !fromMain {
					source, target = target, source
					from, to = to, from
				}
				if scenario != "whole_entry" {
					(*source)[0].Count = 2
				}
				if scenario == "merge" {
					(*target)[0] = (*source)[0]
					(*target)[0].Count = 1
				}
				card := (*source)[0]
				before := SideboardPlayerState{
					Mainboard: cloneDeckCards(player.Mainboard),
					Sideboard: cloneDeckCards(player.Sideboard), Ready: true,
				}
				deck := protocol.DeckSelect{Name: "Pool", Format: protocol.FormatModern,
					DeckFormat: protocol.DeckFormatLimited,
					Mainboard:  player.Mainboard, Sideboard: player.Sideboard,
				}
				if _, err := r.SelectDeck("host-conn", deck); err != nil {
					t.Fatalf("select deck at the entry limit: %v", err)
				}
				beforeDeck := cloneDeck(*r.Seats[0].Deck)
				r.Phase = protocol.RoomPhaseStarted
				r.Game = &GameState{Number: 1, Sideboard: &SideboardState{
					Players: []SideboardPlayerState{player},
				}}
				_, err := r.MoveSideboard("host-conn", protocol.SideboardMove{
					Name: card.Name, SetCode: card.SetCode, CollectorNumber: card.CollectorNumber,
					FromZone: from, ToZone: to,
				})
				after := r.Game.Sideboard.Players[0]
				if !reflect.DeepEqual(*r.Seats[0].Deck, beforeDeck) {
					t.Fatal("pending move changed the committed deck")
				}
				if scenario == "split" {
					if code, ok := ErrorCode(err); !ok || code != protocol.ErrInvalidSideboardMove {
						t.Fatalf("split at entry limit error = %v, want invalid_sideboard_move", err)
					}
					if !reflect.DeepEqual(after, before) {
						t.Fatal("rejected move changed the partition or readiness")
					}
					return
				}
				if err != nil {
					t.Fatalf("entry-preserving move: %v", err)
				}
				if after.Ready || len(after.Mainboard)+len(after.Sideboard) != protocol.MaxDeckEntries ||
					deckCardCount(after.Mainboard)+deckCardCount(after.Sideboard) !=
						deckCardCount(before.Mainboard)+deckCardCount(before.Sideboard) {
					t.Fatal("move changed entry/card counts or retained readiness")
				}
				if reflect.DeepEqual(after.Mainboard, before.Mainboard) || reflect.DeepEqual(after.Sideboard, before.Sideboard) {
					t.Fatal("move did not update both partitions")
				}
			})
		}
	}
}
