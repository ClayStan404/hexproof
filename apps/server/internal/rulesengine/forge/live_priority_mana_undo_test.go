//go:build engineintegration

// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package forge

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
	"reflect"
	"testing"
	"time"
)

// TestLiveForgePriorityManaUndo uses natural hands and land drops. Every
// activation and undo crosses the native priority input and normalized response
// boundary; no game state is injected and no unfinished payment is involved.
func TestLiveForgePriorityManaUndo(t *testing.T) {
	root := os.Getenv("HEXPROOF_REAL_FORGE_ROOT")
	if root == "" {
		t.Fatal("HEXPROOF_REAL_FORGE_ROOT must name an extracted pinned runtime")
	}
	config := JavaProcessConfig(os.Getenv("HEXPROOF_FORGE_JAVA"),
		filepath.Join(root, "forge-harness.jar"), filepath.Join(root, "forge-gui"))
	if overlay := os.Getenv("HEXPROOF_REAL_FORGE_OVERLAY"); overlay != "" {
		config = JavaOverlayProcessConfig(os.Getenv("HEXPROOF_FORGE_JAVA"),
			filepath.Join(root, "forge-harness.jar"), filepath.Join(root, "forge-gui"), overlay)
	}
	config.Dir = t.TempDir()
	config.Args = append([]string{"-Xmx768m", "-XX:ActiveProcessorCount=2",
		"-Djava.awt.headless=true", "-Duser.home=" + config.Dir}, config.Args...)
	client := liveStartClient(t, config)
	ctx, cancel := context.WithTimeout(t.Context(), 60*time.Second)
	defer cancel()
	request := liveStartRequest("priority-mana-undo", 2, "Constructed", 20,
		liveDeck("Forest", "Grizzly Bears", 30, 30))
	request.StartingPlayerIndex = new(int)
	request.Players[1].Deck = liveDeck("Forest", "Forest", 60, 0)
	game, err := client.StartGame(ctx, request)
	if err != nil {
		t.Fatal(err)
	}
	defer client.AbortGame(context.Background(), game.SessionID)
	raw, err := client.Prompt(ctx, game.SessionID, 0)
	if err != nil {
		t.Fatal(err)
	}
	var prompt PromptView
	var view GameView
	read := func() {
		t.Helper()
		prompt, err = NormalizePrompt(raw)
		if err != nil || !prompt.Supported {
			t.Fatalf("invalid native decision %s: %v", raw, err)
		}
		view, err = client.SnapshotView(ctx, game.SessionID, 0)
		if err != nil {
			t.Fatal(err)
		}
	}
	submit := func(answer PromptResponse) {
		t.Helper()
		response, err := BuildPromptResponse(raw, prompt.PlayerIndex, prompt.PromptID, answer)
		if err != nil {
			t.Fatal(err)
		}
		if err := client.SubmitAction(ctx, game.SessionID, response); err != nil {
			t.Fatalf("native %s failed: %v", answer.ResponseID, err)
		}
		var supported bool
		raw, supported, err = client.AwaitPrompt(ctx, game.SessionID, prompt.PromptID)
		if err != nil || !supported || len(raw) == 0 {
			t.Fatalf("native priority did not progress after %s: %v", answer.ResponseID, err)
		}
		previousID := prompt.PromptID
		read()
		if prompt.PromptID == previousID {
			t.Fatal("native response did not produce a fresh decision")
		}
	}
	option := func(kind, cardID string) PromptOption {
		t.Helper()
		for _, candidate := range prompt.Options {
			if candidate.Kind == kind && (cardID == "" || candidate.CardID == cardID) {
				return candidate
			}
		}
		return PromptOption{}
	}
	act := func(kind, cardID string) {
		t.Helper()
		candidate := option(kind, cardID)
		if candidate.ResponseID == "" {
			t.Fatalf("missing %s for %s in %+v", kind, cardID, prompt)
		}
		submit(PromptResponse{ResponseID: candidate.ResponseID})
	}
	forests := func() []CardView {
		var cards []CardView
		for _, zone := range view.Zones {
			if zone.Zone == "battlefield" && zone.OwnerID == "player-0" {
				for _, card := range zone.Cards {
					if card.Identity != nil && card.Identity.Name == "Forest" {
						cards = append(cards, card)
					}
				}
			}
		}
		return cards
	}

	// Reach a main phase with an existing source, another legal land drop and
	// a creature in hand, so the same game also exercises the land-play boundary.
	read()
	sourceID, secondID, bearID := "", "", ""
	for decisions := 0; decisions < 500; decisions++ {
		answer := PromptResponse{ResponseID: "$pass"}
		if prompt.Kind == "chooseAction" && prompt.PlayerIndex == 0 {
			land := option("playLand", "")
			for _, zone := range view.Zones {
				if zone.Zone == "hand" && zone.OwnerID == "player-0" {
					for _, card := range zone.Cards {
						if card.Identity != nil && card.Identity.Name == "Grizzly Bears" {
							bearID = card.ID
						}
					}
				}
			}
			if land.ResponseID != "" && bearID != "" {
				for _, card := range forests() {
					if !card.Tapped && option("activateAbility", card.ID).ResponseID != "" {
						sourceID, secondID = card.ID, land.CardID
						break
					}
				}
			}
			if sourceID != "" {
				break
			}
			if land.ResponseID != "" {
				answer.ResponseID = land.ResponseID
			}
		} else if prompt.Kind != "chooseAction" {
			answer = liveAnswer(t, prompt, view, map[string]int{})
		}
		submit(answer)
	}
	if sourceID == "" || secondID == "" || bearID == "" {
		t.Fatal("natural draws did not reach the priority undo fixture")
	}
	baseline := view
	source, _ := liveCardInZone(view, "battlefield", sourceID)
	initialLands := len(forests())
	assertPriority := func(tapped bool, green int) {
		t.Helper()
		if prompt.Kind != "chooseAction" || prompt.PlayerIndex != 0 || prompt.PaymentID != "" ||
			view.GameOver || view.Turn != baseline.Turn || view.Step != baseline.Step ||
			view.ActivePlayerID != baseline.ActivePlayerID || view.PriorityPlayerID != baseline.PriorityPlayerID ||
			view.PriorityPlayerID != "player-0" || len(view.Stack) != 0 {
			t.Fatalf("mana action changed the priority window: prompt=%+v view=%+v", prompt, view)
		}
		current, present := liveCardInZone(view, "battlefield", sourceID)
		expected := source
		expected.Tapped = tapped
		if !present || !reflect.DeepEqual(current, expected) {
			t.Fatalf("mana action changed the source beyond its tapped state: %+v != %+v", current, expected)
		}
		for _, player := range view.Players {
			for color, amount := range player.ManaPool {
				want := 0
				if player.ID == "player-0" && color == "G" {
					want = green
				}
				if amount != want {
					t.Fatalf("unexpected pool for %s %s: %d != %d", player.ID, color, amount, want)
				}
			}
			if player.ID == "player-0" && player.ManaPool["G"] != green {
				t.Fatalf("green mana = %d, want %d", player.ManaPool["G"], green)
			}
		}
		if green > 0 && prompt.AutoPassEligible {
			t.Fatal("floating mana incorrectly allowed native automatic priority passing")
		}
	}
	assertPriority(false, 0)
	const cycles = 20
	for cycle := 0; cycle < cycles; cycle++ {
		act("activateAbility", sourceID)
		assertPriority(true, 1)
		act("undoMana", sourceID)
		assertPriority(false, 0)
		if len(forests()) != initialLands || option("undoMana", "").ResponseID != "" {
			t.Fatalf("cycle %d changed land count or retained an already undone action", cycle)
		}
		for _, viewer := range []int{0, 1, -1} {
			projection, err := client.SnapshotView(ctx, game.SessionID, viewer)
			if err != nil {
				t.Fatal(err)
			}
			for _, zone := range projection.Zones {
				if zone.Zone == "library" || zone.Zone == "hand" && zone.OwnerID != fmt.Sprintf("player-%d", viewer) {
					for _, card := range zone.Cards {
						if card.Identity != nil {
							t.Fatalf("cycle %d exposed a private identity to viewer %d", cycle, viewer)
						}
					}
				}
			}
		}
	}

	// A legal land play does not clear Forge's mana undo stack. Undo only the
	// earlier activation: retain the new land and the consumed land-drop quota.
	act("activateAbility", sourceID)
	assertPriority(true, 1)
	act("playLand", secondID)
	assertPriority(true, 1)
	second, present := liveCardInZone(view, "battlefield", secondID)
	if !present || second.Tapped || len(forests()) != initialLands+1 {
		t.Fatal("the second land did not enter normally")
	}
	act("undoMana", sourceID)
	assertPriority(false, 0)
	secondAfter, present := liveCardInZone(view, "battlefield", secondID)
	if !present || !reflect.DeepEqual(secondAfter, second) || len(forests()) != initialLands+1 ||
		option("playLand", "").ResponseID != "" {
		t.Fatal("mana undo changed the new land or restored the consumed land drop")
	}

	// Spend both floating mana on a real spell and resolve it. Completed payment
	// must not offer either source for undo or return the spell's spent mana.
	act("activateAbility", sourceID)
	assertPriority(true, 1)
	act("activateAbility", secondID)
	assertPriority(true, 2)
	if option("undoMana", secondID).ResponseID == "" || option("undoMana", sourceID).ResponseID != "" {
		t.Fatal("ordinary priority did not offer only the latest reversible source")
	}
	act("cast", bearID)
	for decisions := 0; decisions < 100; decisions++ {
		if prompt.Kind == "chooseAction" {
			for _, candidate := range prompt.Options {
				if candidate.Kind == "undoMana" && (candidate.CardID == sourceID || candidate.CardID == secondID) {
					t.Fatal("completed creature payment exposed spent mana for undo")
				}
			}
			if bear, present := liveCardInZone(view, "battlefield", bearID); present && bear.Identity != nil && bear.Identity.Name == "Grizzly Bears" {
				for _, id := range []string{sourceID, secondID} {
					card, present := liveCardInZone(view, "battlefield", id)
					if !present || !card.Tapped {
						t.Fatal("completed payment restored a spent source")
					}
				}
				for _, player := range view.Players {
					for _, amount := range player.ManaPool {
						if amount != 0 {
							t.Fatal("resolved creature retained mana spent on its cost")
						}
					}
				}
				if !client.Healthy() {
					t.Fatal("priority undo left an unhealthy runtime")
				}
				t.Logf("%d priority tap/undo cycles, preserved land drop and resolved floating-mana cast passed", cycles)
				return
			}
			submit(PromptResponse{ResponseID: "$pass"})
		} else if prompt.Kind == "payManaCost" {
			// The pool already covers {1}{G}; do not tap another source as a
			// generic payment policy might when additional lands are available.
			answer := PromptResponse{}
			for _, candidate := range prompt.Options {
				if candidate.ResponseID == "$pay" || candidate.ResponseID == "$auto-pay" {
					answer.ResponseID = candidate.ResponseID
					break
				}
			}
			if answer.ResponseID == "" {
				t.Fatalf("two floating green mana cannot pay for Grizzly Bears: %+v", prompt)
			}
			submit(answer)
		} else {
			submit(liveAnswer(t, prompt, view, map[string]int{}))
		}
	}
	t.Fatal("creature did not resolve after priority mana undo")
}
