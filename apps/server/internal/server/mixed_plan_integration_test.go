// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package server

import (
	"encoding/json"
	"fmt"
	"os"
	"reflect"
	"testing"

	"hexproof/server/internal/protocol"
)

func mixedWireProducts(t *testing.T) []protocol.LimitedProductDefinition {
	t.Helper()
	if path := os.Getenv("HEXPROOF_TEST_LIMITED_PRODUCTS"); path != "" {
		raw, err := os.ReadFile(path)
		if err != nil {
			t.Fatal(err)
		}
		var products []protocol.LimitedProductDefinition
		if err = json.Unmarshal(raw, &products); err != nil {
			t.Fatal(err)
		}
		byID := map[string]protocol.LimitedProductDefinition{}
		for _, p := range products {
			byID[p.ID] = p
		}
		return []protocol.LimitedProductDefinition{byID["hexproof-trk-play"], byID["mtgjson-som-draft"], byID["mtgjson-nph-draft"]}
	}
	products := []protocol.LimitedProductDefinition{}
	for index, code := range []string{"AAA", "BBB", "CCC"} {
		size := 14
		if index == 1 {
			size = 15
		}
		cards := make([]protocol.LimitedCardDefinition, 60)
		for i := range cards {
			cards[i] = protocol.LimitedCardDefinition{Name: fmt.Sprintf("%s card %d", code, i), SetCode: code, CollectorNumber: fmt.Sprint(i), TypeLine: "Creature", Weight: 1}
		}
		products = append(products, protocol.LimitedProductDefinition{ID: code, Name: code + " Draft", SetCode: code, ProductType: "approximate", CardsPerPack: size,
			Sheets: []protocol.LimitedSheetDefinition{{Name: "cards", Cards: cards}}, Variants: []protocol.LimitedPackVariantDefinition{{Weight: 1, Slots: []protocol.LimitedSlotDefinition{{Sheet: "cards", Count: size}}}}})
	}
	return products
}

func TestMixedSetLifecycleOverWebSocket(t *testing.T) {
	for _, mode := range []string{protocol.LimitedEventSetSealed, protocol.LimitedEventSetDraft} {
		t.Run(mode, func(t *testing.T) {
			config := DefaultConfig()
			config.MessagesPerSecond = 10000
			srv, _ := newConfiguredTestServer(t, config)
			peers := make([]*casualCubePeer, 4)
			for i, name := range []string{"Judge", "Alice", "Bob", "Viewer"} {
				client := dial(t, srv)
				defer client.close()
				client.hello(name)
				peers[i] = &casualCubePeer{client: client}
			}
			command := func(actor *casualCubePeer, kind string, payload any, want string) protocol.Envelope {
				return casualCubeCommand(t, peers, actor, kind, payload, want)
			}
			products := mixedWireProducts(t)
			plan := &protocol.LimitedPackPlanDefinition{Products: products}
			expected := 0
			for _, p := range products {
				plan.Entries = append(plan.Entries, protocol.LimitedPackPlanEntry{ProductID: p.ID, Count: 2})
				expected += 2 * p.CardsPerPack
			}
			if mode == protocol.LimitedEventSetDraft {
				plan.Products = products[:2]
				plan.Entries = []protocol.LimitedPackPlanEntry{{ProductID: products[0].ID, Count: 1}, {ProductID: products[1].ID, Count: 1}, {ProductID: products[0].ID, Count: 1}}
				expected = 2*products[0].CardsPerPack + products[1].CardsPerPack
			}
			request := protocol.TournamentCreate{OperationID: "mixed-" + mode, Name: "Mixed Set", Format: "Limited", EventType: mode, MatchMode: protocol.MatchBO1, MaxPlayers: 2, Plan: plan}
			env, _ := protocol.NewEnvelope(protocol.TypeTournamentCreate, request)
			raw, _ := env.Marshal()
			if int64(len(raw)) >= config.MaxMessageBytes {
				t.Fatal("target plan exceeds default envelope limit")
			}
			t.Logf("%s create envelope: %d bytes", mode, len(raw))
			command(peers[0], protocol.TypeTournamentCreate, request, protocol.TypeTournamentCreated)
			id := peers[0].event.TournamentID
			for _, p := range peers[1:] {
				command(p, protocol.TypeTournamentEnter, protocol.TournamentEnter{TournamentID: id}, protocol.TypeTournamentEntered)
			}
			for _, p := range peers[1:3] {
				command(p, protocol.TypeTournamentRegister, protocol.TournamentRegister{TournamentID: id}, protocol.TypeTournamentRegistered)
				command(p, protocol.TypeTournamentCheckIn, protocol.TournamentCheckIn{CheckedIn: true}, protocol.TypeTournamentCheckInSet)
			}
			start := testTournamentStart(protocol.LimitedStageRegistration)
			command(peers[0], protocol.TypeTournamentStart, start, protocol.TypeTournamentStarted)
			before := peers[1].pool
			command(peers[0], protocol.TypeTournamentStart, start, protocol.TypeTournamentStarted)
			if !reflect.DeepEqual(before, peers[1].pool) {
				t.Fatal("start replay changed private pool")
			}
			for _, viewer := range []*casualCubePeer{peers[0], peers[3]} {
				if viewer.pool.Plan == nil || len(viewer.pool.Pool)+len(viewer.pool.CurrentPacks)+len(viewer.pool.ReceivedPacks) != 0 {
					t.Fatal("organizer/viewer projection violated")
				}
			}
			if mode == protocol.LimitedEventSetSealed && len(peers[1].pool.ReceivedPacks) != 6 {
				t.Fatal("explicit sealed groups missing")
			}
			// Transfer the private credential to a fresh connection, then downgrade
			// the old owner to a public viewer. Snapshots must replace private fields.
			old := peers[1]
			client := dial(t, srv)
			defer client.close()
			client.hello("Alice restored")
			restored := &casualCubePeer{client: client}
			peers[1] = restored
			peers = append(peers, old)
			command(restored, protocol.TypeTournamentEnter, protocol.TournamentEnter{TournamentID: id, Credential: old.credential}, protocol.TypeTournamentEntered)
			if !reflect.DeepEqual(restored.pool.Pool, before.Pool) || !reflect.DeepEqual(restored.pool.ReceivedPacks, before.ReceivedPacks) || !reflect.DeepEqual(restored.pool.CurrentPacks, before.CurrentPacks) {
				t.Fatal("credential transfer regenerated cards")
			}
			command(old, protocol.TypeTournamentEnter, protocol.TournamentEnter{TournamentID: id}, protocol.TypeTournamentEntered)
			if len(old.pool.Pool)+len(old.pool.CurrentPacks)+len(old.pool.ReceivedPacks) != 0 {
				t.Fatal("old owner retained private data")
			}
			for steps := 0; mode == protocol.LimitedEventSetDraft && peers[1].pool.Stage == protocol.LimitedStageDraft && steps < 100; steps++ {
				for _, p := range peers[1:3] {
					if len(p.pool.CurrentPack) == 0 {
						continue
					}
					round := p.pool.PackRound
					product := products[0]
					if round == 2 {
						product = products[1]
					}
					if len(p.pool.CurrentPacks) != 1 || p.pool.CurrentPacks[0].ProductID != product.ID || len(p.pool.CurrentPack) > product.CardsPerPack {
						t.Fatal("wrong round product/pack")
					}
					pick := protocol.LimitedPick{InstanceID: p.pool.CurrentPack[0].InstanceID}
					command(p, protocol.TypeLimitedPick, pick, protocol.TypeLimitedPicked)
					poolCount := len(p.pool.Pool)
					command(p, protocol.TypeLimitedPick, pick, protocol.TypeError)
					if len(p.pool.Pool) != poolCount {
						t.Fatal("retried pick duplicated a physical card")
					}
				}
			}
			seen := map[string]bool{}
			for _, p := range peers[1:3] {
				if p.pool.Stage != protocol.LimitedStageDeckBuilding || len(p.pool.Pool) != expected {
					t.Fatalf("wrong constructed pool: %s %d", p.pool.Stage, len(p.pool.Pool))
				}
				for _, c := range p.pool.Pool {
					if seen[c.InstanceID] {
						t.Fatal("instance shared between players")
					}
					seen[c.InstanceID] = true
				}
				ids := []string{}
				for _, c := range p.pool.Pool[:23] {
					ids = append(ids, c.InstanceID)
				}
				command(p, protocol.TypeLimitedSubmitDeck, protocol.LimitedSubmitDeck{Name: "Mixed deck", MainboardInstanceIDs: ids, BasicLands: []protocol.LimitedBasicLand{{Name: "Island", Count: 17}}}, protocol.TypeLimitedDeckSubmitted)
			}
			command(peers[0], protocol.TypeTournamentStart, start, protocol.TypeTournamentStarted)
			if peers[0].event.Stage != protocol.LimitedStageDeckBuilding {
				t.Fatal("old start replay advanced construction")
			}
			command(peers[0], protocol.TypeTournamentStart, testTournamentStart(protocol.LimitedStageDeckBuilding), protocol.TypeTournamentStarted)
			if peers[0].event.CurrentRound != 1 || len(peers[0].event.Pairings) != 1 {
				t.Fatal("Swiss first round absent")
			}
			pairing := peers[0].event.Pairings[0]
			command(peers[1], protocol.TypeTournamentOpenMatch, protocol.TournamentPairingCommand{PairingID: pairing.PairingID}, protocol.TypeTournamentMatchOpened)
			command(peers[2], protocol.TypeTournamentOpenMatch, protocol.TournamentPairingCommand{PairingID: pairing.PairingID}, protocol.TypeTournamentMatchOpened)
			for _, p := range peers[1:3] {
				if p.room.DeckFormat != protocol.DeckFormatLimited {
					t.Fatal("wrong match deck policy")
				}
				selected := 0
				for _, seat := range p.room.Seats {
					if seat.DeckSelected {
						selected++
					}
				}
				if selected != 2 {
					t.Fatal("match did not receive locked decks")
				}
			}
		})
	}
}
