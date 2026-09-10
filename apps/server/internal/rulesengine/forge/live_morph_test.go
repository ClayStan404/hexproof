//go:build engineintegration

// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package forge

import (
	"context"
	"strings"
	"testing"
	"time"
)

// Exercise a real Morph spell through casting, the actual stack, a face-down
// permanent and turning it face up. The name alone is insufficient redaction:
// set/collector metadata would also identify the hidden physical printing.
func liveMorphPrivacy(t *testing.T, client *Client) {
	t.Helper()
	ctx, cancel := context.WithTimeout(context.Background(), 45*time.Second)
	defer cancel()
	request := liveStartRequest("morph-privacy", 2, "Constructed", 20,
		liveDeck("Island", "Willbender", 30, 30))
	request.Players[1].Deck = liveDeck("Island", "Island", 60, 0)
	game, err := client.StartGame(ctx, request)
	if err != nil {
		t.Fatal(err)
	}
	defer client.AbortGame(context.Background(), game.SessionID)
	lastID := int64(0)
	cardID := ""
	onCasting, onStack, onBattlefield, turnedUp := false, false, false, false
	stats := make(map[string]int)
	for decision := 0; decision < 900; {
		if ctx.Err() != nil {
			t.Fatal(ctx.Err())
		}
		raw, err := client.Prompt(ctx, game.SessionID, 0)
		if err != nil {
			t.Fatal(err)
		}
		if len(raw) == 0 {
			time.Sleep(5 * time.Millisecond)
			continue
		}
		prompt, err := NormalizePrompt(raw)
		if err != nil || !prompt.Supported {
			t.Fatalf("morph prompt: %s %v", raw, err)
		}
		if prompt.PromptID == lastID {
			time.Sleep(5 * time.Millisecond)
			continue
		}
		for viewer := -1; viewer <= 1; viewer++ {
			view, err := client.SnapshotView(ctx, game.SessionID, viewer)
			if err != nil {
				t.Fatal(err)
			}
			for _, object := range view.Stack {
				if object.SourceID != cardID || cardID == "" {
					continue
				}
				// The flip ability itself is public after its source turns up.
				if onBattlefield {
					continue
				}
				if object.Identity.Name != "" || object.Identity.SetCode != "" ||
					object.Identity.CardNumber != "" || strings.Contains(object.Text, "Willbender") {
					t.Fatalf("viewer %d received face-down spell printing/text: %+v", viewer, object)
				}
				if strings.HasPrefix(object.ID, "casting-") {
					onCasting = true
				} else {
					onStack = true
				}
			}
			card, found := liveCardInZone(view, "battlefield", cardID)
			if found && cardID != "" {
				if card.FaceDown {
					onBattlefield = true
					if viewer != 0 && card.Identity != nil &&
						(card.Identity.Name != "" || card.Identity.SetCode != "" || card.Identity.CardNumber != "") {
						t.Fatalf("viewer %d received face-down permanent printing: %+v", viewer, card)
					}
				} else if card.Identity != nil && card.Identity.Name == "Willbender" {
					turnedUp = true
				}
			}
		}
		if onStack && onBattlefield && turnedUp {
			t.Logf("same Morph card %s verified: casting=%v actual stack=true hidden battlefield=true face-up=true; decisions=%d",
				cardID, onCasting, decision)
			return
		}
		answer := PromptResponse{ResponseID: "$pass"}
		if prompt.Kind != "chooseAction" {
			answer = liveAnswer(t, prompt, stats)
		} else {
			for _, option := range prompt.Options {
				if prompt.PlayerIndex == 0 && option.Kind == "cast" && !strings.HasPrefix(option.Label, "Play ") && stats["option:"+option.Label] == 0 {
					t.Logf("morph cast option: %s", option.Label)
					stats["option:"+option.Label] = 1
				}
				if option.Kind == "playLand" || strings.HasPrefix(option.Label, "Play ") {
					answer.ResponseID = option.ResponseID
					break
				}
				label := strings.ToLower(option.Label)
				if prompt.PlayerIndex == 0 && cardID == "" && option.Kind == "cast" &&
					(strings.Contains(label, "morph") || strings.Contains(label, "face down") || strings.Contains(label, "face-down")) {
					cardID, answer.ResponseID = option.CardID, option.ResponseID
					t.Logf("selected actual Morph cast: %+v", option)
					break
				}
				if prompt.PlayerIndex == 0 && onBattlefield && option.CardID == cardID &&
					option.Kind != "cast" && (strings.Contains(label, "face up") || strings.Contains(label, "morph") || strings.HasPrefix(label, "activate ")) {
					answer.ResponseID = option.ResponseID
					t.Logf("selected turn-face-up action: %+v", option)
					break
				}
			}
			if decision > 200 && cardID == "" && prompt.PlayerIndex == 0 {
				t.Fatalf("no Morph action exercised: %+v", prompt.Options)
			}
		}
		response, err := BuildPromptResponse(raw, prompt.PlayerIndex, prompt.PromptID, answer)
		if err != nil {
			t.Fatalf("morph answer %+v: %v", answer, err)
		}
		if err := client.SubmitAction(ctx, game.SessionID, response); err != nil {
			t.Fatal(err)
		}
		lastID = prompt.PromptID
		decision++
	}
	t.Fatalf("Morph evidence incomplete: card=%s casting=%v stack=%v battlefield=%v turnedUp=%v",
		cardID, onCasting, onStack, onBattlefield, turnedUp)
}
