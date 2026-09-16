// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package limited

import (
	"fmt"
	"reflect"
	"testing"

	"hexproof/server/internal/protocol"
)

func autoDraftEvent(t *testing.T, eventType string, players int) *Event {
	t.Helper()
	event, err := New(Config{TournamentID: "auto-draft", EventType: eventType,
		Product:      commanderCubeProduct(CubeDraftCardsRequiredForEvent(eventType, players)),
		Participants: testParticipants(players)}, 92)
	if err != nil {
		t.Fatal(err)
	}
	return event
}

func assertAutoDraftPoolConservation(t *testing.T, event *Event) {
	t.Helper()
	seen := map[string]bool{}
	for _, player := range event.Players {
		want := event.packCount * event.cardsPerPack
		if len(player.Pool) != want || len(player.Inbox) != 0 {
			t.Fatalf("seat %s: pool %d inbox %d, expected %d private picks", player.ID, len(player.Pool), len(player.Inbox), want)
		}
		for _, card := range player.Pool {
			if seen[card.ID] {
				t.Fatalf("physical instance %s duplicated", card.ID)
			}
			seen[card.ID] = true
		}
	}
	public := event.Snapshot("")
	if event.Stage != protocol.LimitedStageDeckBuilding || len(public.Pool) != 0 ||
		len(public.CurrentPack) != 0 || len(public.CurrentPacks) != 0 || len(public.OptionalCards) != 0 ||
		len(public.FallbackCommanders) != 0 || event.packRound != event.packCount {
		t.Fatalf("unexpected terminal stage or public private cards: %+v", public)
	}
}

func TestExplicitAutoDraftAllSeatsTerminatesAndConservesPhysicalCards(t *testing.T) {
	for _, eventType := range []string{protocol.LimitedEventCubeDraft, protocol.LimitedEventCommanderCube} {
		counts := []int{2, 3, 4, 8}
		for _, seats := range counts {
			t.Run(fmt.Sprintf("%s_%d", eventType, seats), func(t *testing.T) {
				event := autoDraftEvent(t, eventType, seats)
				originalOrder := append([]*PlayerState(nil), event.Players...)
				for _, player := range event.Players {
					if err := event.SetAutoDraft(player.ID, true); err != nil {
						t.Fatal(err)
					}
				}
				assertAutoDraftPoolConservation(t, event)
				if !reflect.DeepEqual(event.Players, originalOrder) {
					t.Fatal("automatic drafting changed physical seat order")
				}
			})
		}
	}
}

func TestExplicitAutoDraftReclaimAndManualMix(t *testing.T) {
	for _, eventType := range []string{protocol.LimitedEventCubeDraft, protocol.LimitedEventCommanderCube} {
		t.Run(eventType, func(t *testing.T) {
			event := autoDraftEvent(t, eventType, 4)
			seat := event.Players[1]
			if err := event.SetAutoDraft(seat.ID, true); err != nil {
				t.Fatal(err)
			}
			if len(seat.Pool) != event.PicksPerSelection()*event.packsThisBatch || len(seat.Inbox) != 0 {
				t.Fatal("explicit activation did not consume exactly one atomic selection")
			}
			before := event.Snapshot(seat.ID)
			if _, err := event.PickCards(seat.ID, []string{"stale"}); ErrorCode(err) != ErrPickUnavailable {
				t.Fatal("manual pick accepted under automatic control")
			}
			if !reflect.DeepEqual(before, event.Snapshot(seat.ID)) {
				t.Fatal("rejected manual pick mutated auto-drafted state")
			}
			if err := event.SetAutoDraft(seat.ID, false); err != nil || seat.AutoDraft {
				t.Fatal("could not reclaim control")
			}
			for _, player := range event.Players {
				if player != seat {
					if err := event.SetAutoDraft(player.ID, true); err != nil {
						t.Fatal(err)
					}
				}
			}
			for attempts := 0; event.Stage == protocol.LimitedStageDraft && attempts < 100; attempts++ {
				if len(seat.Inbox) == 0 {
					t.Fatal("automatic seats failed to deliver the next manual pack")
				}
				ids := []string{}
				for _, part := range seat.Inbox[0].parts() {
					for _, card := range part.Cards[:min(event.PicksPerSelection(), len(part.Cards))] {
						ids = append(ids, card.ID)
					}
				}
				if _, err := event.PickCards(seat.ID, ids); err != nil {
					t.Fatal(err)
				}
			}
			assertAutoDraftPoolConservation(t, event)
		})
	}
}

func TestAutoDraftSelectionIsSeededRandomNotFirstCards(t *testing.T) {
	event, identical := autoDraftEvent(t, protocol.LimitedEventCommanderCube, 2), autoDraftEvent(t, protocol.LimitedEventCommanderCube, 2)
	first := event.Players[0]
	initial := []string{first.Inbox[0].Cards[0].ID, first.Inbox[0].Cards[1].ID}
	if err := event.SetAutoDraft(first.ID, true); err != nil {
		t.Fatal(err)
	}
	if err := identical.SetAutoDraft(first.ID, true); err != nil {
		t.Fatal(err)
	}
	if reflect.DeepEqual(initial, []string{first.Pool[0].ID, first.Pool[1].ID}) {
		t.Fatal("automatic choice appears to always take the first cards")
	}
	if !reflect.DeepEqual(event.Snapshot(first.ID), identical.Snapshot(first.ID)) {
		t.Fatal("same random seed did not reproduce automatic selection")
	}
}
