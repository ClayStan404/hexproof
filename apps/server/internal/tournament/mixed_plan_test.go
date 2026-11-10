// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package tournament

import (
	"encoding/json"
	"reflect"
	"testing"

	"hexproof/server/internal/protocol"
)

func TestLaterProductFailurePreservesAllRegistrationStateAndLocksAttempt(t *testing.T) {
	good := tournamentLimitedProduct()
	bad := tournamentLimitedProduct()
	bad.ID = "bad"
	bad.SetCode = "BAD"
	bad.CardsPerPack = 2
	card := bad.Sheets[0].Cards[0]
	bad.Sheets = []protocol.LimitedSheetDefinition{
		{Name: "first", WithReplacement: true, Cards: []protocol.LimitedCardDefinition{card}},
		{Name: "later", WithReplacement: true, ExcludePrevious: true, Cards: []protocol.LimitedCardDefinition{card}},
	}
	bad.Variants = []protocol.LimitedPackVariantDefinition{{Weight: 1, Slots: []protocol.LimitedSlotDefinition{{Sheet: "first", Count: 1}, {Sheet: "later", Count: 1}}}}
	for _, mode := range []string{protocol.LimitedEventSetSealed, protocol.LimitedEventSetDraft} {
		t.Run(mode, func(t *testing.T) {
			plan := &protocol.LimitedPackPlanDefinition{Products: []protocol.LimitedProductDefinition{good, bad}, Entries: []protocol.LimitedPackPlanEntry{{ProductID: good.ID, Count: 1}, {ProductID: bad.ID, Count: 1}}}
			if mode == protocol.LimitedEventSetDraft {
				plan.Entries = append(plan.Entries, protocol.LimitedPackPlanEntry{ProductID: good.ID, Count: 1})
			}
			e, err := New("failure", Config{Name: "Atomic", Format: "Limited", EventType: mode, MatchMode: "bo3", MaxPlayers: 2, Plan: plan}, "Judge", "owner", CredentialHash("owner"), testNow)
			if err != nil {
				t.Fatal(err)
			}
			for _, id := range []string{"a", "b"} {
				p, err := e.Register(id, id, CredentialHash(id), testNow)
				if err != nil {
					t.Fatal(err)
				}
				p.CheckedIn = true
				p.Competing = true
				p.InitialOrder = 42
			}
			before, _ := json.Marshal(e)
			actor := Actor{Role: RoleOrganizer, ConnectionID: "owner"}
			first := e.Start(actor, 7, testNow)
			if first == nil {
				t.Fatal("generation should fail only after first product succeeded")
			}
			after, _ := json.Marshal(e)
			if !reflect.DeepEqual(before, after) || e.Limited != nil || e.PlannedRounds != 0 || e.Status != StatusRegistration {
				t.Fatalf("failed start changed registration\nbefore %s\nafter %s", before, after)
			}
			if again := e.Start(actor, 999, testNow); again != first {
				t.Fatal("failed generation chose another attempt/seed")
			}
		})
	}
}

func TestPlanLockedAtCreateAndSwissRoundUsesSubmittedInstances(t *testing.T) {
	p := tournamentLimitedProduct()
	plan := &protocol.LimitedPackPlanDefinition{Products: []protocol.LimitedProductDefinition{p}, Entries: []protocol.LimitedPackPlanEntry{{ProductID: p.ID, Count: 1}}}
	e, err := New("custom", Config{Name: "One pack", Format: "Limited", EventType: protocol.LimitedEventSetSealed, MatchMode: "bo3", MaxPlayers: 2, Plan: plan}, "Judge", "owner", CredentialHash("owner"), testNow)
	if err != nil {
		t.Fatal(err)
	}
	hash := e.LimitedPlanView().PlanHash
	plan.Products[0].Variants[0].Slots[0].Count = 99
	plan.Entries[0].Count = 12
	for _, id := range []string{"a", "b"} {
		p, err := e.Register(id, id, CredentialHash(id), testNow)
		if err != nil {
			t.Fatal(err)
		}
		p.CheckedIn = true
	}
	actor := Actor{Role: RoleOrganizer, ConnectionID: "owner"}
	if err := e.Start(actor, 17, testNow); err != nil {
		t.Fatal(err)
	}
	if e.LimitedPlanView().PlanHash != hash || len(e.Limited.Players[0].Pool) != 15 {
		t.Fatal("caller mutated locked plan")
	}
	for _, p := range e.Participants {
		v := e.Limited.Snapshot(p.ID)
		ids := []string{}
		for _, c := range v.Pool {
			ids = append(ids, c.InstanceID)
		}
		if _, err := e.SubmitLimitedDeck(Actor{Role: RoleParticipant, ConnectionID: p.ConnectionID, ParticipantID: p.ID}, protocol.LimitedSubmitDeck{Name: "Custom", MainboardInstanceIDs: ids, BasicLands: []protocol.LimitedBasicLand{{Name: "Plains", Count: 25}}}); err != nil {
			t.Fatal(err)
		}
	}
	if err := e.Start(actor, 888, testNow); err != nil {
		t.Fatal(err)
	}
	if e.Stage != protocol.LimitedStageCompetition || len(e.CurrentRound().Pairings) != 1 || e.PlannedRounds != 1 {
		t.Fatal("Swiss round one not reached")
	}
	for _, p := range e.Participants {
		if p.Deck == nil || len(p.Deck.Sideboard) != 0 {
			t.Fatal("locked deck lost")
		}
	}
}
