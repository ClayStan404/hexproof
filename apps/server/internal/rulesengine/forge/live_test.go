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
	"sort"
	"strings"
	"testing"
	"time"
)

// TestLiveForgeRuntime is opt-in and uses synthetic decks, never user data.
// Unlike fake-process tests it crosses the packaged Java engine boundary and
// requires real land/spell/combat or targeted-damage wins.
func TestLiveForgeRuntime(t *testing.T) {
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
	config.Dir = t.TempDir()
	config.Args = append([]string{"-Xmx1536m", "-Djava.awt.headless=true", "-Duser.home=" + config.Dir}, config.Args...)
	diagnostics, err := os.CreateTemp(t.TempDir(), "engine-stderr-*.log")
	if err != nil {
		t.Fatal(err)
	}
	defer diagnostics.Close()
	config.Stderr = diagnostics
	t.Cleanup(func() {
		if t.Failed() {
			data, _ := os.ReadFile(diagnostics.Name())
			t.Logf("synthetic-game diagnostics: %s", data)
		}
	})
	started := time.Now()
	client, err := Start(context.Background(), config)
	if err != nil {
		t.Fatal(err)
	}
	defer client.Close()
	t.Logf("real runtime ready in %s", time.Since(started))
	for _, scenario := range []struct {
		name, land, spell string
		combat            bool
	}{
		{"combat", "Forest", "Grizzly Bears", true},
		{"targeted_damage", "Mountain", "Lightning Bolt", false},
	} {
		t.Run(scenario.name, func(t *testing.T) {
			request := liveStartRequest(scenario.name, 2, "Constructed", 20,
				liveDeck(scenario.land, scenario.spell, 24, 36))
			game, err := client.StartGame(context.Background(), request)
			if err != nil {
				t.Fatal(err)
			}
			defer client.AbortGame(context.Background(), game.SessionID)
			stats := livePlay(t, client, game.SessionID, 2, 0)
			if stats["land"] == 0 || stats["cast"] == 0 || stats["payManaCost"] == 0 {
				t.Fatalf("game bypassed core decisions: %v", stats)
			}
			if scenario.combat && stats["attack"] == 0 || !scenario.combat && stats["chooseBoardTargets"] == 0 {
				t.Fatalf("game bypassed required resolution: %v", stats)
			}
		})
	}
	t.Run("commander_four_players", func(t *testing.T) {
		request := liveStartRequest("commander", 4, "Commander", 40,
			liveDeck("Forest", "Grizzly Bears", 50, 49))
		for i := range request.Players {
			request.Players[i].CommanderNames = []string{"Isamaru, Hound of Konda"}
			request.Players[i].Deck = append(append([]CardIdentity(nil), request.Players[i].Deck...), CardIdentity{Name: "Isamaru, Hound of Konda"})
		}
		game, err := client.StartGame(context.Background(), request)
		if err != nil {
			t.Fatal(err)
		}
		defer client.AbortGame(context.Background(), game.SessionID)
		livePlay(t, client, game.SessionID, 4, 5)
		ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
		defer cancel()
		view, err := client.SnapshotView(ctx, game.SessionID, -1)
		if err != nil {
			t.Fatal(err)
		}
		commanders := 0
		for _, player := range view.Players {
			if player.Life != 40 {
				t.Fatalf("Commander starting life = %d", player.Life)
			}
		}
		for _, zone := range view.Zones {
			if zone.Zone == "command" {
				commanders += len(zone.Cards)
			}
		}
		if commanders != 4 {
			t.Fatalf("visible commanders = %d, want 4", commanders)
		}
		for player := 3; player > 0; player-- {
			if err := client.Concede(ctx, game.SessionID, player); err != nil {
				t.Fatal(err)
			}
			for {
				view, err = client.SnapshotView(ctx, game.SessionID, -1)
				if err != nil {
					t.Fatal(err)
				}
				// The old harness exposes the concession flag before its game
				// thread has committed the terminal result. Do not mistake that
				// intermediate observation for a failed final concession.
				if view.GameOver || player > 1 && view.Players[player].Status != "playing" {
					break
				}
				select {
				case <-ctx.Done():
					t.Fatal("concession did not advance", ctx.Err())
				case <-time.After(10 * time.Millisecond):
				}
			}
			if view.GameOver != (player == 1) {
				t.Fatalf("after conceding player %d gameOver=%v", player, view.GameOver)
			}
		}
		if view.WinnerID != "player-0" {
			t.Fatalf("Commander winner = %q", view.WinnerID)
		}
	})
	t.Run("duel_commander_starting_life", func(t *testing.T) {
		request := liveStartRequest("duel-commander", 2, "Commander", 20,
			liveDeck("Plains", "Savannah Lions", 50, 49))
		for i := range request.Players {
			request.Players[i].CommanderNames = []string{"Isamaru, Hound of Konda"}
			request.Players[i].Deck = append(append([]CardIdentity(nil), request.Players[i].Deck...), CardIdentity{Name: "Isamaru, Hound of Konda"})
		}
		ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
		defer cancel()
		game, err := client.StartGame(ctx, request)
		if err != nil {
			t.Fatal(err)
		}
		defer client.AbortGame(ctx, game.SessionID)
		livePlay(t, client, game.SessionID, 2, 3)
		view, err := client.SnapshotView(ctx, game.SessionID, -1)
		if err != nil {
			t.Fatal(err)
		}
		for _, player := range view.Players {
			if player.Life != 20 {
				t.Fatalf("Duel Commander starting life = %d, want 20", player.Life)
			}
		}
	})
	t.Run("cards", func(t *testing.T) { liveCardScenarios(t, client) })
	t.Run("morph_privacy", func(t *testing.T) { liveMorphPrivacy(t, client) })
}

func liveDeck(land, spell string, lands, spells int) []CardIdentity {
	deck := make([]CardIdentity, 0, lands+spells)
	for i := 0; i < lands; i++ {
		deck = append(deck, CardIdentity{Name: land})
	}
	for i := 0; i < spells; i++ {
		deck = append(deck, CardIdentity{Name: spell})
	}
	return deck
}

func liveStartRequest(id string, players int, variant string, life int, deck []CardIdentity) StartGameRequest {
	request := StartGameRequest{GameID: id, Variant: variant, StartingLife: life, Seed: 12345}
	for i := 0; i < players; i++ {
		request.Players = append(request.Players, PlayerConfig{Name: fmt.Sprintf("Synthetic %d", i), Deck: deck})
	}
	return request
}

func livePlay(t *testing.T, client *Client, session string, players, stopAfter int) map[string]int {
	return livePlayWithPolicy(t, client, session, players, stopAfter, nil, nil)
}

func livePlayWithPolicy(t *testing.T, client *Client, session string, players, stopAfter int,
	policy func(PromptView, GameView, map[string]int) PromptResponse,
	evidence *liveCardEvidence) map[string]int {
	t.Helper()
	ctx, cancel := context.WithTimeout(context.Background(), 90*time.Second)
	defer cancel()
	stats := make(map[string]int)
	var lastID int64
	var timings []time.Duration
	var previousPublic GameView
	started := time.Now()
	for decisions := 0; decisions < 3000; {
		terminal, err := client.GameOver(ctx, session)
		if err != nil {
			t.Fatal(err)
		}
		if terminal {
			view, err := client.SnapshotView(ctx, session, -1)
			if err != nil || !view.GameOver || view.WinnerID == "" {
				t.Fatalf("terminal view: %+v %v", view, err)
			}
			for _, player := range view.Players {
				if player.ID != view.WinnerID && (player.Life > 0 || player.Status != "lost") {
					t.Fatalf("natural game did not end with lethal life loss: winner=%s loser=%+v stats=%v",
						view.WinnerID, player, stats)
				}
			}
			if evidence != nil {
				evidence.observe(t, view, stats)
			}
			if len(timings) == 0 {
				t.Fatal("natural game ended without any submitted decisions")
			}
			sort.Slice(timings, func(i, j int) bool { return timings[i] < timings[j] })
			t.Logf("real win: turn=%d winner=%s decisions=%d elapsed=%s submit-RPC-p95=%s stats=%v",
				view.Turn, view.WinnerID, decisions, time.Since(started), timings[len(timings)*95/100], stats)
			return stats
		}
		raw, err := client.Prompt(ctx, session, 0)
		if err != nil {
			t.Fatal(err)
		}
		if len(raw) == 0 {
			time.Sleep(10 * time.Millisecond)
			continue
		}
		prompt, err := NormalizePrompt(raw)
		if err != nil || !prompt.Supported {
			t.Fatalf("unsupported live prompt %s: %v", raw, err)
		}
		if prompt.PromptID == lastID {
			time.Sleep(10 * time.Millisecond)
			continue
		}
		if stopAfter > 0 && decisions >= stopAfter {
			return stats
		}
		for viewer := -1; viewer < players; viewer++ {
			view, err := client.SnapshotView(ctx, session, viewer)
			if err != nil {
				t.Fatalf("snapshot at prompt %s: %v", raw, err)
			}
			if viewer == -1 {
				if view.Turn > 0 && view.Turn == previousPublic.Turn &&
					!strings.Contains(strings.ToLower(view.Step), "draw") &&
					!strings.Contains(strings.ToLower(previousPublic.Step), "draw") {
					for _, zone := range view.Zones {
						for _, before := range previousPublic.Zones {
							if zone.Zone == "library" && before.Zone == "library" &&
								zone.OwnerID == before.OwnerID && before.Count > zone.Count {
								stats["library_decrease_outside_draw_step"] += before.Count - zone.Count
							}
						}
					}
				}
				previousPublic = view
				if evidence != nil {
					evidence.observe(t, view, stats)
				}
			}
			for _, zone := range view.Zones {
				if viewer == -1 {
					for _, card := range zone.Cards {
						if card.Identity != nil {
							stats["seen:"+zone.Zone+":"+card.Identity.Name] = 1
							if card.Identity.Token {
								stats["seen:token"] = 1
							}
						}
					}
				}
				if zone.Zone == "library" || zone.Zone == "hand" && zone.OwnerID != fmt.Sprintf("player-%d", viewer) {
					for _, card := range zone.Cards {
						if card.Identity != nil {
							t.Fatalf("viewer %d received hidden %s identity", viewer, zone.Zone)
						}
					}
				}
			}
		}
		var answer PromptResponse
		if policy == nil {
			answer = liveAnswer(t, prompt, stats)
		} else {
			answer = policy(prompt, previousPublic, stats)
		}
		if decisions < 20 || decisions%500 == 0 {
			t.Logf("decision=%d kind=%s options=%+v answer=%+v", decisions, prompt.Kind, prompt.Options, answer)
		}
		response, err := BuildPromptResponse(raw, prompt.PlayerIndex, prompt.PromptID, answer)
		if err != nil {
			t.Fatalf("encode live answer %+v to %s: %v", answer, raw, err)
		}
		sent := time.Now()
		if err := client.SubmitAction(ctx, session, response); err != nil {
			t.Fatalf("submit live answer %s: %v", response, err)
		}
		if evidence != nil {
			evidence.submitted(t, prompt, answer, previousPublic)
		}
		timings = append(timings, time.Since(sent))
		stats[prompt.Kind]++
		lastID = prompt.PromptID
		decisions++
	}
	t.Fatalf("synthetic game exceeded 3000 decisions: %v", stats)
	return stats
}

func liveAnswer(t *testing.T, prompt PromptView, stats map[string]int) PromptResponse {
	t.Helper()
	answer := PromptResponse{ResponseID: "$submit"}
	switch prompt.Kind {
	case "diceRolled", "revealCards":
		answer.ResponseID = "$ack"
	case "mulligan":
		answer.ResponseID = "$keep"
	case "chooseAction":
		answer.ResponseID = "$pass"
		for _, option := range prompt.Options {
			if option.Kind == "playLand" || option.Kind == "cast" {
				answer.ResponseID = option.ResponseID
				if option.Kind == "playLand" || strings.HasPrefix(option.Label, "Play ") {
					stats["land"]++
				} else {
					stats["cast"]++
					stats["cast:"+option.Label]++
				}
				break
			}
		}
	case "payManaCost":
		answer.ResponseID = "$auto-pay"
		for _, option := range prompt.Options {
			if option.ResponseID == "$pay" {
				answer.ResponseID = "$pay"
				break
			}
		}
	case "chooseAttackers":
		for _, source := range prompt.CombatSources {
			if len(source.ValidTargetIDs) > 0 {
				answer.Assignments = append(answer.Assignments, PromptAssignment{SourceID: source.ResponseID, TargetID: source.ValidTargetIDs[0]})
				stats["attack"]++
			}
		}
	case "chooseBlockers":
		// These conformance decks intentionally take damage to finish a game.
	case "chooseCards", "mulliganPutBack":
		for i := 0; i < prompt.CardMinimum; i++ {
			answer.CardIDs = append(answer.CardIDs, prompt.Cards[i].ID)
		}
	case "chooseBoardTargets":
		for _, target := range prompt.Targets {
			if target.Kind == "player" && target.ID != fmt.Sprintf("player-%d", prompt.PlayerIndex) {
				answer.TargetIDs = append(answer.TargetIDs, target.ResponseID)
				break
			}
		}
		if len(answer.TargetIDs) == 0 {
			t.Fatalf("synthetic burn spell has no opponent target: %+v", prompt)
		}
	case "chooseBoolean", "chooseColor", "chooseFromSelection":
		total := 0
		for _, choice := range prompt.Choices {
			if total >= prompt.ChoiceMinimum {
				break
			}
			answer.ChoiceIDs = append(answer.ChoiceIDs, choice.ResponseID)
			total += choice.Weight
		}
	case "chooseNumber":
		value := prompt.NumberMinimum
		answer.ChosenNumber = &value
	case "reorder":
		for _, item := range prompt.OrderItems {
			answer.OrderedIDs = append(answer.OrderedIDs, item.ResponseID)
		}
	case "scry":
		for i, destination := range prompt.ScryDestinations {
			pile := PromptScryPile{Destination: destination}
			if i == 0 {
				for _, card := range prompt.Cards {
					pile.CardIDs = append(pile.CardIDs, card.ID)
				}
			}
			answer.ScryPiles = append(answer.ScryPiles, pile)
		}
	default:
		encoded, _ := json.Marshal(prompt)
		t.Fatalf("scenario needs explicit policy for %s: %s", strings.TrimSpace(prompt.Kind), encoded)
	}
	return answer
}
