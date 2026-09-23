// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package limited

import (
	"fmt"
	"testing"

	"hexproof/server/internal/protocol"
)

func TestCommanderDraftPackSettingsAndBatchCompletion(t *testing.T) {
	for _, packs := range []int{3, 4, 5, 6, 8} {
		for _, batch := range []int{1, 2} {
			t.Run(fmt.Sprintf("%d_packs_batch_%d", packs, batch), func(t *testing.T) {
				event, err := New(Config{TournamentID: "paired", EventType: protocol.LimitedEventCommanderCube,
					Product: commanderCubeProduct(4 * packs * 20), Participants: testParticipants(4),
					DraftSettings: &protocol.LimitedDraftSettings{PacksPerPlayer: packs, PacksPerBatch: batch}}, 31)
				if err != nil {
					t.Fatal(err)
				}
				confirmations := map[string]int{}
				for steps := 0; event.Stage == protocol.LimitedStageDraft && steps < 100; steps++ {
					for _, player := range event.Players {
						view := event.Snapshot(player.ID)
						if len(view.CurrentPack) == 0 {
							continue
						}
						wantBatch := batch
						if packs%batch != 0 && event.packRound == packs {
							wantBatch = 1
						}
						if len(view.CurrentPacks) != wantBatch || view.PacksThisBatch != wantBatch || view.PacksPerPlayer != packs {
							t.Fatalf("wrong batch profile: %+v", view)
						}
						wantDirection := 1
						if ((event.packRound+batch-1)/batch)%2 == 0 {
							wantDirection = -1
						}
						if view.Direction != wantDirection {
							t.Fatal("direction did not alternate by batch")
						}
						ids := []string{}
						for _, part := range view.CurrentPacks {
							for _, card := range part.Cards[:part.PicksRequired] {
								ids = append(ids, card.InstanceID)
							}
						}
						if view.PicksRequired != len(ids) {
							t.Fatal("selection total differs from per-pack quotas")
						}
						if _, err := event.PickCards(player.ID, ids); err != nil {
							t.Fatal(err)
						}
						confirmations[player.ID]++
					}
				}
				assertAutoDraftPoolConservation(t, event)
				for _, player := range event.Players {
					if confirmations[player.ID] != ((packs+batch-1)/batch)*10 {
						t.Fatalf("unexpected manual confirmations: %v", confirmations)
					}
				}
			})
		}
	}
}

func TestPairedDraftRejectsCrossPackQuotaAndPreservesPrivateQueue(t *testing.T) {
	event := autoDraftEvent(t, protocol.LimitedEventCommanderCube, 4)
	player := event.Players[0]
	view := event.Snapshot(player.ID)
	a, b := view.CurrentPacks[0], view.CurrentPacks[1]
	valid := []string{a.Cards[0].InstanceID, a.Cards[1].InstanceID, b.Cards[0].InstanceID, b.Cards[1].InstanceID}
	for _, ids := range [][]string{
		valid[:2], {a.Cards[0].InstanceID, a.Cards[1].InstanceID, a.Cards[2].InstanceID, b.Cards[0].InstanceID},
		{valid[0], valid[1], valid[2], valid[2]}, {valid[0], valid[1], valid[2], "foreign"},
	} {
		before := eventStateJSON(t, event)
		if _, err := event.PickCards(player.ID, ids); ErrorCode(err) != ErrPickUnavailable {
			t.Fatal("invalid paired pick accepted")
		}
		if before != eventStateJSON(t, event) {
			t.Fatal("rejected paired pick changed state")
		}
	}
	if _, err := event.PickCards(player.ID, valid); err != nil {
		t.Fatal(err)
	}
	next := event.Players[1]
	if len(next.Inbox) != 2 || next.Inbox[1].cardCount() != 36 || len(next.Inbox[1].Companion.Cards) != 18 {
		t.Fatal("paired remainder was split or passed twice")
	}
	recovered := event.Snapshot(next.ID)
	if recovered.CurrentPacks[0].PackID == a.PackID || recovered.Participants[1].QueuedPacks != 4 {
		t.Fatal("queued private packs were exposed before the current batch was picked")
	}
	recovered.CurrentPacks[0].Cards[0].Name = "Changed snapshot"
	if event.Snapshot(next.ID).CurrentPacks[0].Cards[0].Name == "Changed snapshot" {
		t.Fatal("snapshot aliases authoritative cards")
	}
	public := event.Snapshot("observer")
	if len(public.CurrentPacks) != 0 || len(public.CurrentPack) != 0 || len(public.Pool) != 0 {
		t.Fatal("private batches leaked")
	}
}

func TestCommanderDraftSettingsDefaultsAndValidation(t *testing.T) {
	for _, seats := range []int{2, 3, 4, 5, 6, 7, 8} {
		settings, err := ResolveDraftSettings(protocol.LimitedEventCommanderCube, seats, nil)
		if err != nil {
			t.Fatal(err)
		}
		want := protocol.LimitedDraftSettings{PacksPerPlayer: 3, PacksPerBatch: 1, CardsPerPack: 20}
		if seats <= 4 {
			want = protocol.LimitedDraftSettings{PacksPerPlayer: 6, PacksPerBatch: 2, CardsPerPack: 20}
		}
		if settings != want {
			t.Fatalf("%d seats: %+v", seats, settings)
		}
	}
	for _, test := range []struct{ seats, packs, batch int }{{4, 2, 1}, {4, 7, 1}, {4, 6, 0}, {4, 6, 3}, {8, 6, 1}, {8, 3, 2}} {
		if _, err := ResolveDraftSettings(protocol.LimitedEventCommanderCube, test.seats,
			&protocol.LimitedDraftSettings{PacksPerPlayer: test.packs, PacksPerBatch: test.batch}); err == nil {
			t.Fatal("invalid settings accepted", test)
		}
	}
}

func TestCommanderCustomPackSizesConserveCards(t *testing.T) {
	for _, cardsPerPack := range []int{10, 15, 20, 25, 39, 40} {
		for _, batch := range []int{1, 2} {
			t.Run(fmt.Sprintf("%d_cards_batch_%d", cardsPerPack, batch), func(t *testing.T) {
				const packs = 5 // Also exercise an unpaired final pack.
				event, err := New(Config{TournamentID: "pack-size", EventType: protocol.LimitedEventCommanderCube,
					Product: commanderCubeProduct(4*packs*cardsPerPack + 7), Participants: testParticipants(4),
					DraftSettings: &protocol.LimitedDraftSettings{PacksPerPlayer: packs, PacksPerBatch: batch,
						CardsPerPack: cardsPerPack}}, 53)
				if err != nil {
					t.Fatal(err)
				}
				for _, part := range event.Snapshot(event.Players[0].ID).CurrentPacks {
					if len(part.Cards) != cardsPerPack || part.PicksRequired != 2 {
						t.Fatal("opening pack did not use the selected size")
					}
				}
				for steps := 0; event.Stage == protocol.LimitedStageDraft && steps < 200; steps++ {
					for _, player := range event.Players {
						view := event.Snapshot(player.ID)
						if len(view.CurrentPack) == 0 {
							continue
						}
						ids := []string{}
						for _, part := range view.CurrentPacks {
							for _, card := range part.Cards[:part.PicksRequired] {
								ids = append(ids, card.InstanceID)
							}
						}
						if _, err := event.PickCards(player.ID, ids); err != nil {
							t.Fatal(err)
						}
					}
				}
				assertAutoDraftPoolConservation(t, event)
				if len(event.cubeStock) != 7 {
					t.Fatal("draft consumed stock beyond its configured packs")
				}
			})
		}
	}
}

func TestCommanderPackSizeDefaultsBoundsAndStock(t *testing.T) {
	for _, cards := range []int{-1, 0, 9, 10, 21, 40, 41} {
		for _, seats := range []int{4, 8} {
			requested := protocol.LimitedDraftSettings{PacksPerPlayer: 3, PacksPerBatch: 1, CardsPerPack: cards}
			settings, err := ResolveDraftSettings(protocol.LimitedEventCommanderCube, seats, &requested)
			if cards < 0 || cards == 9 || cards == 41 {
				if err == nil {
					t.Fatal("out-of-range pack size accepted", cards)
				}
				continue
			}
			if err != nil {
				t.Fatal(err)
			}
			want := cards
			if want == 0 {
				want = 20
			}
			if settings.CardsPerPack != want {
				t.Fatal("pack size or backward-compatible default lost")
			}
			required := seats * 3 * want
			config := Config{TournamentID: "stock", EventType: protocol.LimitedEventCommanderCube,
				Product: commanderCubeProduct(required - 1), Participants: testParticipants(seats), DraftSettings: &requested}
			if _, err := New(config, 1); err == nil {
				t.Fatal("insufficient custom pack stock accepted")
			}
			config.Product = commanderCubeProduct(required)
			event, err := New(config, 1)
			if err != nil {
				t.Fatal(err)
			}
			for _, player := range event.Players {
				if err := event.SetAutoDraft(player.ID, true); err != nil {
					t.Fatal(err)
				}
			}
			assertAutoDraftPoolConservation(t, event)
		}
	}
	if _, err := ResolveDraftSettings(protocol.LimitedEventCubeDraft, 4,
		&protocol.LimitedDraftSettings{PacksPerPlayer: 3, PacksPerBatch: 1, CardsPerPack: 25}); err == nil {
		t.Fatal("regular Cube accepted custom pack settings")
	}
}
