//go:build engineintegration

// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package forge

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"slices"
	"testing"
	"time"
)

// TestLiveForgeSerumPowder crosses the packaged native input boundary. The
// all-Powder deck is intentionally synthetic so every replacement contains
// multiple independently addressable copies without relying on shuffle luck.
func TestLiveForgeSerumPowder(t *testing.T) {
	root := os.Getenv("HEXPROOF_REAL_FORGE_ROOT")
	if root == "" {
		t.Fatal("HEXPROOF_REAL_FORGE_ROOT must name an extracted pinned runtime")
	}
	root, err := filepath.Abs(root)
	if err != nil {
		t.Fatal(err)
	}
	config := JavaProcessConfig(os.Getenv("HEXPROOF_FORGE_JAVA"),
		filepath.Join(root, "forge-harness.jar"), filepath.Join(root, "forge-gui"))
	if overlay := os.Getenv("HEXPROOF_REAL_FORGE_OVERLAY"); overlay != "" {
		overlay, err = filepath.Abs(overlay)
		if err != nil {
			t.Fatal(err)
		}
		config = JavaOverlayProcessConfig(os.Getenv("HEXPROOF_FORGE_JAVA"),
			filepath.Join(root, "forge-harness.jar"), filepath.Join(root, "forge-gui"), overlay)
	}
	for _, scenario := range []struct {
		name             string
		mulligans        int
		bottomUsedPowder bool
	}{
		{"initial_decline_and_repeated_powder", 0, false},
		{"paid_london_powder", 2, false},
		{"bottom_requested_powder_then_choose_another", 2, true},
	} {
		t.Run(scenario.name, func(t *testing.T) {
			local := config
			local.Dir = t.TempDir()
			local.Args = append([]string{"-Xmx1536m", "-Djava.awt.headless=true", "-Duser.home=" + local.Dir}, local.Args...)
			client := liveStartClient(t, local)
			ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
			defer cancel()
			request := liveStartRequest("serum-"+scenario.name, 2, "Constructed", 20,
				liveDeck("Serum Powder", "Serum Powder", 60, 0))
			request.StartingPlayerIndex = new(int)
			for index := range request.Players[0].Deck {
				request.Players[0].Deck[index].SetCode = "IMA"
				request.Players[0].Deck[index].CollectorNumber = "228"
			}
			request.Players[1].Deck = liveDeck("Forest", "Forest", 60, 0)
			game, err := client.StartGame(ctx, request)
			if err != nil {
				t.Fatal(err)
			}
			defer client.AbortGame(context.Background(), game.SessionID)
			driver := liveSerumDriver{t: t, ctx: ctx, client: client, session: game.SessionID}
			driver.read()
			driver.requireMulligan(0, 7, 53, 0)
			for taken := 0; taken < scenario.mulligans; taken++ {
				driver.submit(PromptResponse{ResponseID: "$mulligan"})
				if driver.view.PlayerIndex == 1 {
					driver.requireKind("mulligan", 1)
					driver.submit(PromptResponse{ResponseID: "$keep"})
				}
				driver.requireMulligan(taken+1, 7, 53, 0)
			}
			initial := driver.handIDs()
			driver.activate(0)
			driver.requireKind("chooseBoolean", 0)
			driver.submit(PromptResponse{ResponseID: "$submit", ChoiceIDs: []string{"choice:0"}})
			driver.requireMulligan(scenario.mulligans, 7, 53, 0)
			if !slices.Equal(initial, driver.handIDs()) {
				t.Fatal("declining Serum Powder changed the hand or paid the London bottom count")
			}
			used := driver.view.Options[0].CardID
			oldPrompt := driver.view.PromptID
			driver.activate(0)
			driver.requireKind("chooseBoolean", 0)
			driver.submit(PromptResponse{ResponseID: "$submit", ChoiceIDs: []string{"choice:1"}})
			if scenario.mulligans > 0 {
				driver.requireKind("mulliganPutBack", 0)
				if len(driver.view.Cards) != 7 || driver.view.CardMinimum != scenario.mulligans || driver.view.CardMaximum != scenario.mulligans {
					t.Fatalf("Powder did not collect the owed London bottom: %+v", driver.view)
				}
				bottom := []string{}
				if scenario.bottomUsedPowder {
					bottom = append(bottom, used)
				}
				for _, card := range driver.view.Cards {
					if card.ID != used && len(bottom) < scenario.mulligans {
						bottom = append(bottom, card.ID)
					}
				}
				if _, err := BuildPromptResponse(driver.raw, 0, driver.view.PromptID,
					PromptResponse{ResponseID: "$submit", CardIDs: bottom[:len(bottom)-1]}); err == nil {
					t.Fatal("Powder accepted an incomplete London bottom selection")
				}
				driver.submit(PromptResponse{ResponseID: "$submit", CardIDs: bottom})
				if scenario.bottomUsedPowder {
					driver.requireMulligan(scenario.mulligans, 7-scenario.mulligans, 53+scenario.mulligans, 0)
					for _, option := range driver.view.Options {
						if option.CardID == used {
							t.Fatal("a bottomed Serum Powder remained actionable")
						}
					}
					driver.activate(0)
					driver.requireKind("chooseBoolean", 0)
					driver.submit(PromptResponse{ResponseID: "$submit", ChoiceIDs: []string{"choice:1"}})
				}
			}
			hand := 7 - scenario.mulligans
			library := 53 + scenario.mulligans - hand
			driver.requireMulligan(scenario.mulligans, hand, library, hand)
			if _, err := BuildPromptResponse(driver.raw, 0, oldPrompt,
				PromptResponse{ResponseID: "action:0"}); err == nil {
				t.Fatal("an old Serum Powder prompt remained actionable after exile/redraw")
			}
			if scenario.mulligans == 0 {
				driver.activate(hand - 1)
				driver.requireKind("chooseBoolean", 0)
				driver.submit(PromptResponse{ResponseID: "$submit", ChoiceIDs: []string{"choice:1"}})
				library -= hand
				driver.requireMulligan(0, hand, library, 2*hand)
			}
			driver.submit(PromptResponse{ResponseID: "$keep"})
			if driver.view.PlayerIndex == 1 {
				driver.requireKind("mulligan", 1)
				driver.submit(PromptResponse{ResponseID: "$keep"})
			}
			driver.requireKind("chooseAction", 0)
			if len(driver.handIDs()) != hand {
				t.Fatal("Keep applied the already-paid London bottom count again")
			}
		})
	}
}

type liveSerumDriver struct {
	t       *testing.T
	ctx     context.Context
	client  *Client
	session string
	raw     json.RawMessage
	view    PromptView
}

func (d *liveSerumDriver) read() {
	d.t.Helper()
	raw, err := d.client.Prompt(d.ctx, d.session, 0)
	if err != nil {
		d.t.Fatal(err)
	}
	d.accept(raw)
}

func (d *liveSerumDriver) accept(raw json.RawMessage) {
	d.t.Helper()
	view, err := NormalizePrompt(raw)
	if err != nil || !view.Supported {
		d.t.Fatalf("unsupported Serum Powder prompt %s: %v", raw, err)
	}
	d.raw, d.view = raw, view
}

func (d *liveSerumDriver) submit(answer PromptResponse) {
	d.t.Helper()
	old := d.view.PromptID
	response, err := BuildPromptResponse(d.raw, d.view.PlayerIndex, old, answer)
	if err != nil {
		d.t.Fatal(err)
	}
	if err := d.client.SubmitAction(d.ctx, d.session, response); err != nil {
		d.t.Fatal(err)
	}
	raw, supported, err := d.client.AwaitPrompt(d.ctx, d.session, old)
	if err != nil || !supported || len(raw) == 0 {
		d.t.Fatalf("Serum Powder did not publish a new input: supported=%v, %v", supported, err)
	}
	d.accept(raw)
	if d.view.PromptID == old {
		d.t.Fatal("Serum Powder retained the consumed prompt identifier")
	}
}

func (d *liveSerumDriver) activate(index int) {
	d.t.Helper()
	if index >= len(d.view.Options) || d.view.Options[index].Kind != "activateAbility" ||
		d.view.Options[index].CardID == "" {
		d.t.Fatalf("Serum Powder copy %d is not available: %+v", index, d.view.Options)
	}
	d.submit(PromptResponse{ResponseID: d.view.Options[index].ResponseID})
}

func (d *liveSerumDriver) requireKind(kind string, player int) {
	d.t.Helper()
	if d.view.Kind != kind || d.view.PlayerIndex != player {
		d.t.Fatalf("wanted %s for player %d, got %+v", kind, player, d.view)
	}
}

func (d *liveSerumDriver) requireMulligan(count, hand, library, exile int) {
	d.t.Helper()
	d.requireKind("mulligan", 0)
	_, input, _, err := decodePrompt(d.raw)
	if err != nil || input.MulliganCount != count || len(d.view.Options) != hand+2 {
		d.t.Fatalf("Powder changed the mulligan count or available hand actions: %s, %v", d.raw, err)
	}
	for viewer := -1; viewer < 2; viewer++ {
		view, err := d.client.SnapshotView(d.ctx, d.session, viewer)
		if err != nil {
			d.t.Fatal(err)
		}
		for _, zone := range view.Zones {
			if zone.OwnerID == "player-0" {
				want, checked := map[string]int{"hand": hand, "library": library, "exile": exile}[zone.Zone]
				if checked && zone.Count != want {
					d.t.Fatalf("viewer %d %s count=%d, wanted %d", viewer, zone.Zone, zone.Count, want)
				}
			}
			if zone.Zone == "library" || zone.Zone == "hand" && zone.OwnerID != fmt.Sprintf("player-%d", viewer) {
				for _, card := range zone.Cards {
					if card.Identity != nil {
						d.t.Fatalf("viewer %d received a hidden %s identity", viewer, zone.Zone)
					}
				}
			}
		}
	}
}

func (d *liveSerumDriver) handIDs() []string {
	d.t.Helper()
	view, err := d.client.SnapshotView(d.ctx, d.session, 0)
	if err != nil {
		d.t.Fatal(err)
	}
	ids := []string{}
	for _, zone := range view.Zones {
		if zone.Zone == "hand" && zone.OwnerID == "player-0" {
			for _, card := range zone.Cards {
				ids = append(ids, card.ID)
			}
		}
	}
	slices.Sort(ids)
	return ids
}
