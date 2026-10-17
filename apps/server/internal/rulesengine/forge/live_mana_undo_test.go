//go:build engineintegration

// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package forge

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

// TestLiveForgeManaUndo uses natural hands and ordinary land drops in a
// synthetic deck. Each cycle traverses the packaged native payment input,
// normalization and canonical response boundary without mutating game state.
func TestLiveForgeManaUndo(t *testing.T) {
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
	request := liveStartRequest("mana-undo", 2, "Constructed", 20,
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
	const cyclesPerPayment = 20
	payments, cycles := 0, 0
	sourceID, paymentID, originalCost := "", "", ""
	cancelled, casting := false, false
	for decisions := 0; decisions < 500; decisions++ {
		prompt, err := NormalizePrompt(raw)
		if err != nil || !prompt.Supported {
			t.Fatalf("invalid native decision %s: %v", raw, err)
		}
		view, err := client.SnapshotView(ctx, game.SessionID, 0)
		if err != nil {
			t.Fatal(err)
		}
		if payments == 2 {
			for _, zone := range view.Zones {
				if zone.Zone == "battlefield" && zone.OwnerID == "player-0" {
					for _, card := range zone.Cards {
						if card.Identity != nil && card.Identity.Name == "Grizzly Bears" {
							if !cancelled || cycles != cyclesPerPayment || !client.Healthy() {
								t.Fatal("undo cycles did not preserve a playable game")
							}
							t.Logf("%d native tap/undo cycles, cancel and resolved re-cast passed", 2*cyclesPerPayment)
							return
						}
					}
				}
			}
		}
		answer := PromptResponse{ResponseID: "$pass"}
		switch prompt.Kind {
		case "chooseAction":
			casting = false
			for _, option := range prompt.Options {
				if prompt.PlayerIndex == 0 && option.Kind == "playLand" {
					answer.ResponseID = option.ResponseID
					break
				}
				if prompt.PlayerIndex == 0 && payments < 2 && option.Kind == "cast" &&
					strings.Contains(option.Label, "Grizzly Bears") && liveAvailableMana(view, 0) >= 2 {
					answer.ResponseID, casting = option.ResponseID, true
					sourceID, originalCost, cycles = "", "", 0
					break
				}
			}
		case "payManaCost":
			if !casting || prompt.PaymentID == "" {
				t.Fatalf("unexpected mana decision: %+v", prompt)
			}
			if originalCost == "" {
				paymentID, originalCost = prompt.PaymentID, prompt.Title
			}
			if prompt.PaymentID != paymentID {
				t.Fatal("undo replaced the ongoing payment identity")
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
								t.Fatal("undo exposed a private card identity")
							}
						}
					}
				}
			}
			if sourceID != "" {
				card, present := liveCardInZone(view, "battlefield", sourceID)
				if !present {
					t.Fatal("mana source disappeared during payment")
				}
				if card.Tapped {
					if cycles == cyclesPerPayment && !cancelled {
						// Cancel a partly paid spell after the undo loop, leaving
						// native cancellation to refund the new activation.
						answer.ResponseID, cancelled = "$cancel", true
						payments++
					} else {
						for _, option := range prompt.Options {
							if option.CardID == sourceID && option.Kind == "undoMana" {
								answer.ResponseID = option.ResponseID
								cycles++
								break
							}
						}
					}
					if answer.ResponseID == "$pass" {
						t.Fatal("the partially paid source cannot be undone")
					}
				} else if prompt.Title != originalCost {
					t.Fatalf("undo did not restore the unpaid cost: %q != %q", prompt.Title, originalCost)
				}
			}
			if answer.ResponseID == "$pass" && cycles == cyclesPerPayment && cancelled {
				answer.ResponseID = "$auto-pay"
				payments++
			} else if answer.ResponseID == "$pass" {
				for _, option := range prompt.Options {
					if option.Kind == "activateAbility" && option.CardID != "" &&
						(sourceID == "" || sourceID == option.CardID) {
						answer.ResponseID, sourceID = option.ResponseID, option.CardID
						break
					}
				}
			}
		default:
			answer = liveAnswer(t, prompt, view, map[string]int{})
		}
		response, err := BuildPromptResponse(raw, prompt.PlayerIndex, prompt.PromptID, answer)
		if err != nil {
			t.Fatal(err)
		}
		if err := client.SubmitAction(ctx, game.SessionID, response); err != nil {
			t.Fatalf("native %s failed at cycle %d: %v", answer.ResponseID, cycles, err)
		}
		var supported bool
		raw, supported, err = client.AwaitPrompt(ctx, game.SessionID, prompt.PromptID)
		if err != nil || !supported || len(raw) == 0 {
			t.Fatalf("native payment did not progress at cycle %d: %v", cycles, err)
		}
	}
	t.Fatalf("payment did not complete: payments=%d cycles=%d", payments, cycles)
}
