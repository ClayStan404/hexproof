//go:build engineintegration

// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package forge

import (
	"context"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

// TestLiveForgeLotusBloom reaches the mana ability by suspending synthetic
// copies through ordinary native decisions. Its deliberately nonlegal deck
// needs no private game state or engine mutation API.
func TestLiveForgeLotusBloom(t *testing.T) {
	root, err := filepath.Abs(os.Getenv("HEXPROOF_REAL_FORGE_ROOT"))
	if err != nil || os.Getenv("HEXPROOF_REAL_FORGE_ROOT") == "" {
		t.Fatal("HEXPROOF_REAL_FORGE_ROOT must name an extracted pinned runtime")
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
	config.Dir = t.TempDir()
	config.Args = append([]string{"-Xmx1536m", "-Djava.awt.headless=true", "-Duser.home=" + config.Dir}, config.Args...)
	client := liveStartClient(t, config)
	ctx, cancel := context.WithTimeout(context.Background(), 45*time.Second)
	defer cancel()
	deck := liveDeck("Lotus Bloom", "Divination", 30, 30)
	for i := range deck {
		if deck[i].Name == "Lotus Bloom" {
			deck[i].SetCode, deck[i].CollectorNumber = "TSP", "259"
		} else {
			deck[i].SetCode, deck[i].CollectorNumber = "M10", "49"
		}
	}
	request := liveStartRequest("lotus-native-payments", 2, "Constructed", 20, deck)
	request.StartingPlayerIndex = new(int)
	request.Players[1].Deck = liveDeck("Forest", "Forest", 60, 0)
	game, err := client.StartGame(ctx, request)
	if err != nil {
		t.Fatal(err)
	}
	defer client.AbortGame(context.Background(), game.SessionID)

	// The room coordinator can request snapshots while an activation executes.
	// Exercise all viewer projections concurrently with normalized decisions.
	pollCtx, stopPoll := context.WithCancel(ctx)
	pollDone := make(chan error, 1)
	go func() {
		ticker := time.NewTicker(20 * time.Millisecond)
		defer ticker.Stop()
		for {
			select {
			case <-pollCtx.Done():
				pollDone <- nil
				return
			case <-ticker.C:
				for _, viewer := range []int{0, 1, -1} {
					if _, err := client.SnapshotView(pollCtx, game.SessionID, viewer); err != nil {
						if pollCtx.Err() != nil {
							err = nil
						}
						pollDone <- err
						return
					}
				}
			}
		}
	}()
	defer func() {
		stopPoll()
		if err := <-pollDone; err != nil {
			t.Errorf("concurrent viewer projection failed: %v", err)
		}
	}()
	raw, err := client.Prompt(ctx, game.SessionID, 0)
	if err != nil {
		t.Fatal(err)
	}
	autoPaid, manualCasting, manualPaid := false, false, false
	manualActivated, paymentColorChosen, colorChosen := false, false, false
	divinationResolved := false
	for decisions := 0; decisions < 600; decisions++ {
		prompt, err := NormalizePrompt(raw)
		if err != nil || !prompt.Supported {
			t.Fatalf("unsupported Lotus prompt %s: %v", raw, err)
		}
		view, err := client.SnapshotView(ctx, game.SessionID, 0)
		if err != nil {
			t.Fatal(err)
		}
		count := func(zoneName, name string) int {
			found := 0
			for _, zone := range view.Zones {
				if zone.OwnerID != "player-0" || zone.Zone != zoneName {
					continue
				}
				for _, card := range zone.Cards {
					if card.Identity != nil && card.Identity.Name == name {
						found++
					}
				}
			}
			return found
		}
		divinationResolved = divinationResolved || count("graveyard", "Divination") > 0
		if manualPaid && prompt.Kind == "chooseAction" && !paymentColorChosen {
			t.Fatal("manually selecting Lotus Bloom for a colored spell skipped the color decision")
		}
		if colorChosen && prompt.Kind == "chooseAction" {
			for _, player := range view.Players {
				if player.ID == "player-0" && player.ManaPool["U"] == 3 &&
					autoPaid && paymentColorChosen && count("graveyard", "Divination") >= 2 &&
					count("graveyard", "Lotus Bloom") >= 3 {
					t.Logf("natural suspend, automatic and manual Divination, standalone blue mana and concurrent snapshots passed in %d decisions", decisions)
					return
				}
			}
		}
		answer := PromptResponse{ResponseID: "$submit"}
		switch prompt.Kind {
		case "mulligan":
			answer.ResponseID = "$keep"
		case "chooseAction":
			answer.ResponseID = "$pass"
			if prompt.PlayerIndex == 0 {
				for _, option := range prompt.Options {
					if card, present := liveCardInZone(view, "hand", option.CardID); present &&
						card.Identity != nil && card.Identity.Name == "Lotus Bloom" {
						answer.ResponseID = option.ResponseID
						break
					}
					if !autoPaid && count("battlefield", "Lotus Bloom") >= 3 &&
						option.Kind == "cast" && strings.Contains(option.Label, "Divination") {
						answer.ResponseID = option.ResponseID
						break
					}
					if autoPaid && divinationResolved && !manualCasting && option.Kind == "cast" &&
						strings.Contains(option.Label, "Divination") {
						answer.ResponseID = option.ResponseID
						manualCasting = true
						break
					}
					if paymentColorChosen && count("graveyard", "Divination") >= 2 && !manualActivated && option.Kind == "activateAbility" {
						if card, present := liveCardInZone(view, "battlefield", option.CardID); present &&
							card.Identity != nil && card.Identity.Name == "Lotus Bloom" {
							answer.ResponseID = option.ResponseID
							manualActivated = true
							break
						}
					}
				}
			}
		case "payManaCost":
			for _, option := range prompt.Options {
				if manualCasting && option.Kind == "activateAbility" {
					if card, present := liveCardInZone(view, "battlefield", option.CardID); present &&
						card.Identity != nil && card.Identity.Name == "Lotus Bloom" {
						answer.ResponseID = option.ResponseID
						manualPaid = true
						break
					}
				}
				if !manualCasting && option.ResponseID == "$auto-pay" {
					answer.ResponseID = option.ResponseID
					autoPaid = true
					break
				}
			}
			if answer.ResponseID == "$submit" {
				t.Fatalf("Lotus cannot pay the colored Divination cost: %+v", prompt)
			}
		case "chooseBoolean":
			answer.ChoiceIDs = []string{"choice:1"}
		case "chooseFromSelection":
			if prompt.Title != "Select Mana to Produce" {
				t.Fatalf("unexpected Lotus menu: %+v", prompt)
			}
			for _, choice := range prompt.Choices {
				if choice.Label == "BLUE" {
					answer.ChoiceIDs = []string{choice.ResponseID}
					colorChosen = manualActivated
					paymentColorChosen = paymentColorChosen || manualPaid
				}
			}
		default:
			answer = liveAnswer(t, prompt, view, map[string]int{})
		}
		response, err := BuildPromptResponse(raw, prompt.PlayerIndex, prompt.PromptID, answer)
		if err != nil {
			t.Fatal(err)
		}
		if decisions < 15 || prompt.Kind != "chooseAction" {
			t.Logf("turn=%d kind=%s title=%s answer=%+v", view.Turn, prompt.Kind, prompt.Title, answer)
		}
		if err := client.SubmitAction(ctx, game.SessionID, response); err != nil {
			t.Fatal(err)
		}
		var supported bool
		raw, supported, err = client.AwaitPrompt(ctx, game.SessionID, prompt.PromptID)
		if err != nil || !supported || len(raw) == 0 {
			t.Fatalf("Lotus did not progress after %s: %v", response, err)
		}
	}
	t.Fatalf("Lotus did not complete automatic and manual mana paths: auto=%v resolved=%v paid=%v paymentColor=%v activated=%v color=%v",
		autoPaid, divinationResolved, manualPaid, paymentColorChosen, manualActivated, colorChosen)
}
