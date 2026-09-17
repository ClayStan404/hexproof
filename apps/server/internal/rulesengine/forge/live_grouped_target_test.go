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
)

func TestLiveNativeGroupedCardTargets(t *testing.T) {
	root, overlay := os.Getenv("HEXPROOF_REAL_FORGE_ROOT"), os.Getenv("HEXPROOF_TEST_FORGE_OVERLAY")
	if root == "" || overlay == "" {
		t.Fatal("HEXPROOF_REAL_FORGE_ROOT and HEXPROOF_TEST_FORGE_OVERLAY are required")
	}
	config := JavaOverlayProcessConfig(os.Getenv("HEXPROOF_FORGE_JAVA"), filepath.Join(root, "forge-harness.jar"), filepath.Join(root, "forge-gui"), overlay)
	config.Args = append([]string{"-Xmx768m", "-XX:+UseSerialGC", "-XX:ActiveProcessorCount=2", "-Djava.awt.headless=true"}, config.Args...)
	client := liveStartClient(t, config)
	request := liveStartRequest("grouped-card-targets", 2, "Constructed", 20, liveDeck("Island", "Sink into Stupor", 30, 30))
	request.Players[1].Deck = liveDeck("Forest", "Grizzly Bears", 30, 30)
	handle, err := client.StartGame(t.Context(), request)
	if err != nil {
		t.Fatal(err)
	}
	defer client.AbortGame(context.Background(), handle.SessionID)
	cast, returned := false, false
	var targetID string
	stats := livePlayWithPolicy(t, client, handle.SessionID, 2, 0,
		func(prompt PromptView, view GameView, stats map[string]int) PromptResponse {
			for _, choice := range prompt.Choices {
				if strings.HasPrefix(choice.Label, "--CARDS ") {
					t.Fatalf("native target section heading became selectable: %+v", prompt.Choices)
				}
			}
			if targetID != "" && !returned {
				ownerView, err := client.SnapshotView(t.Context(), handle.SessionID, 1)
				if err != nil {
					t.Fatal(err)
				}
				if card, found := liveCardInZone(ownerView, "hand", targetID); found {
					if card.Identity == nil || card.Identity.Name != "Grizzly Bears" {
						t.Fatal("the selected target changed identity")
					}
					if _, stillOnBoard := liveCardInZone(view, "battlefield", targetID); stillOnBoard {
						t.Fatal("returned target still exists on the battlefield")
					}
					returned = true
				}
			}
			if prompt.Kind == "chooseAction" && prompt.PlayerIndex == 0 && !cast && liveAvailableMana(view, 0) >= 3 {
				for _, zone := range view.Zones {
					if zone.Zone != "battlefield" {
						continue
					}
					for _, card := range zone.Cards {
						if card.ControllerID != "player-1" || card.Identity == nil || card.Identity.Name != "Grizzly Bears" {
							continue
						}
						for _, option := range prompt.Options {
							if option.Kind == "cast" && strings.Contains(option.Label, "Sink into Stupor") {
								cast = true
								return PromptResponse{ResponseID: option.ResponseID}
							}
						}
					}
				}
			}
			if prompt.Kind == "chooseCards" && strings.Contains(prompt.Title, "Select target") {
				if len(prompt.Cards) == 0 || prompt.CardMaximum != 1 {
					t.Fatalf("grouped target has no bounded card picker: %+v", prompt)
				}
				targetID = prompt.Cards[0].ID
				return PromptResponse{ResponseID: "$submit", CardIDs: []string{targetID}}
			}
			return liveAnswer(t, prompt, view, stats)
		}, nil)
	if !cast || targetID == "" || !returned || stats["cast:Cast Sink into Stupor"] == 0 {
		t.Fatalf("grouped target did not resolve the exact bounce: cast=%t target=%s returned=%t stats=%v", cast, targetID, returned, stats)
	}
}
