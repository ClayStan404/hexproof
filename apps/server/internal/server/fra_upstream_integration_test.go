// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package server

import (
	"encoding/json"
	"os"
	"reflect"
	"testing"

	"hexproof/server/internal/protocol"
)

func fraWireProduct(t *testing.T, legacy bool) protocol.LimitedProductDefinition {
	t.Helper()
	raw, err := os.ReadFile("../../../../testdata/limited/fra-upstream-product.json")
	if err != nil {
		t.Fatal(err)
	}
	var product protocol.LimitedProductDefinition
	if err := json.Unmarshal(raw, &product); err != nil {
		t.Fatal(err)
	}
	if legacy {
		seen := map[string]bool{}
		for i := range product.Sheets {
			sheet := &product.Sheets[i]
			for _, ref := range sheet.CardRefs {
				card := product.CardPool[ref.CardIndex-1]
				card.Weight = ref.Weight
				key := card.SetCode + "/" + card.CollectorNumber
				if seen[key] {
					card.TypeLine = ""
				}
				seen[key] = true
				sheet.Cards = append(sheet.Cards, card)
			}
			sheet.CardRefs = nil
		}
		product.CardPool = nil
	}
	return product
}

func TestFRAUpstreamSealedAndDraftOverWebSocket(t *testing.T) {
	for _, encoding := range []string{"pooled", "legacy"} {
		for _, kind := range []string{protocol.LimitedEventSetSealed, protocol.LimitedEventSetDraft} {
			t.Run(encoding+"/"+kind, func(t *testing.T) {
				config := DefaultConfig()
				// Pings below are deterministic projection barriers, not
				// human input. Keep the default message byte limit intact.
				config.MessagesPerSecond = 10000
				server, _ := newConfiguredTestServer(t, config)
				peers := make([]*casualCubePeer, 3)
				for i, name := range []string{"Judge", "Alice", "Bob"} {
					client := dial(t, server)
					defer client.close()
					client.hello(name)
					peers[i] = &casualCubePeer{client: client}
				}
				command := func(actor *casualCubePeer, kind string, payload any, want string) protocol.Envelope {
					return casualCubeCommand(t, peers, actor, kind, payload, want)
				}
				product := fraWireProduct(t, encoding == "legacy")
				create := protocol.TournamentCreate{Name: "FRA upstream", Format: "Limited", EventType: kind, MatchMode: protocol.MatchBO3, RoundMinutes: 50, MaxPlayers: 2, Product: &product}
				envelope, _ := protocol.NewEnvelope(protocol.TypeTournamentCreate, create)
				encoded, _ := envelope.Marshal()
				if int64(len(encoded)) >= config.MaxMessageBytes {
					t.Fatal("FRA command exceeds default WebSocket bound")
				}
				if encoding == "legacy" && len(encoded) < 780*1024 {
					t.Fatal("legacy fixture no longer exercises a large command")
				}
				createdEnvelope := command(peers[0], protocol.TypeTournamentCreate, create, protocol.TypeTournamentCreated)
				var created protocol.TournamentCreated
				if err := createdEnvelope.DecodePayload(&created); err != nil {
					t.Fatal(err)
				}
				for _, peer := range peers[1:] {
					command(peer, protocol.TypeTournamentEnter, protocol.TournamentEnter{TournamentID: created.TournamentID}, protocol.TypeTournamentEntered)
					command(peer, protocol.TypeTournamentRegister, protocol.TournamentRegister{TournamentID: created.TournamentID}, protocol.TypeTournamentRegistered)
					command(peer, protocol.TypeTournamentCheckIn, protocol.TournamentCheckIn{CheckedIn: true}, protocol.TypeTournamentCheckInSet)
				}
				command(peers[0], protocol.TypeTournamentStart, protocol.EmptyPayload{}, protocol.TypeTournamentStarted)
				for _, peer := range peers[1:] {
					if kind == protocol.LimitedEventSetSealed && len(peer.pool.Pool) != 84 {
						t.Fatal("wrong sealed pool size")
					}
					if kind == protocol.LimitedEventSetDraft && len(peer.pool.CurrentPack) != 14 {
						t.Fatal("wrong draft pack size")
					}
				}
				if kind == protocol.LimitedEventSetDraft {
					command(peers[1], protocol.TypeLimitedPick, protocol.LimitedPick{InstanceID: peers[1].pool.CurrentPack[0].InstanceID}, protocol.TypeLimitedPicked)
				}
				before := peers[1].pool
				credential := peers[1].credential
				peers[1].client.close()
				replacement := dial(t, server)
				defer replacement.close()
				replacement.hello("Alice reconnect")
				peers[1] = &casualCubePeer{client: replacement}
				command(peers[1], protocol.TypeTournamentEnter, protocol.TournamentEnter{TournamentID: created.TournamentID, Credential: credential}, protocol.TypeTournamentEntered)
				if !reflect.DeepEqual(peers[1].pool.Pool, before.Pool) || !reflect.DeepEqual(peers[1].pool.CurrentPack, before.CurrentPack) {
					t.Fatal("reconnect changed private pool/pack identities")
				}
				for step := 0; kind == protocol.LimitedEventSetDraft && peers[1].pool.Stage == protocol.LimitedStageDraft && step < 100; step++ {
					for _, peer := range peers[1:] {
						if len(peer.pool.CurrentPack) > 0 {
							command(peer, protocol.TypeLimitedPick, protocol.LimitedPick{InstanceID: peer.pool.CurrentPack[0].InstanceID}, protocol.TypeLimitedPicked)
						}
					}
				}
				expected := 84
				if kind == protocol.LimitedEventSetDraft {
					expected = 42
				}
				for _, peer := range peers[1:] {
					if peer.pool.Stage != protocol.LimitedStageDeckBuilding || len(peer.pool.Pool) != expected {
						t.Fatal("limited event did not reach correct deck-building pool")
					}
					for _, card := range peer.pool.Pool {
						if card.TypeLine == "" || card.Name == "" || card.InstanceID == "" {
							t.Fatal("lost resolved card metadata")
						}
					}
				}
				if len(peers[0].pool.Pool) != 0 || len(peers[0].pool.CurrentPack) != 0 {
					t.Fatal("organizer received private cards")
				}
			})
		}
	}
}
