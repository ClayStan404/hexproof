//go:build engineintegration

// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package forge

import (
	"context"
	"strconv"
	"strings"
	"testing"
)

// These are narrow, actual-card conformance scenarios, not a full card-pool
// correctness claim. The decks deliberately repeat cards to exercise mechanics.
func liveCardScenarios(t *testing.T, client *Client) {
	t.Helper()
	for _, scenario := range []struct {
		name, land, spell string
		want              []string
	}{
		{"adventure", "Forest", "Lovestruck Beast", []string{
			"seen:token", "seen:exile:Lovestruck Beast", "seen:battlefield:Lovestruck Beast",
			"resolved:adventure_creature_from_exile",
		}},
		{"modal_land", "Bala Ged Recovery", "Grizzly Bears", []string{
			"seen:battlefield:Bala Ged Sanctuary", "cast:Cast Grizzly Bears",
		}},
		{"etb_draw", "Forest", "Elvish Visionary", []string{
			"seen:battlefield:Elvish Visionary", "cast:Cast Elvish Visionary", "library_decrease_outside_draw_step",
		}},
		{"prepare", "Plains", "Emeritus of Truce", []string{
			"seen:token", "seen:battlefield:Emeritus of Truce", "cast:Cast Swords to Plowshares",
			"resolved:prepared_swords_exile_and_life",
		}},
	} {
		t.Run(scenario.name, func(t *testing.T) {
			request := liveStartRequest(scenario.name, 2, "Constructed", 20,
				liveDeck(scenario.land, scenario.spell, 24, 36))
			if scenario.name == "prepare" {
				// A cheaper creature swarm satisfies Emeritus's preparation
				// condition; a mirror would often never offer the alternate spell.
				request.Players[1].Deck = liveDeck("Plains", "Savannah Lions", 24, 36)
			}
			game, err := client.StartGame(context.Background(), request)
			if err != nil {
				t.Fatal(err)
			}
			defer client.AbortGame(context.Background(), game.SessionID)
			evidence := &liveCardEvidence{scenario: scenario.name, adventure: make(map[string]bool)}
			stats := livePlayWithPolicy(t, client, game.SessionID, 2, 0,
				func(prompt PromptView, view GameView, stats map[string]int) PromptResponse {
					if evidence.prepareCasting && prompt.Kind == "chooseBoardTargets" {
						for _, target := range prompt.Targets {
							card, present := liveCardInZone(view, "battlefield", target.ID)
							power, err := strconv.Atoi(card.Power)
							// Tokens cease to exist before the next stable projection.
							// Select a positive-power nontoken so both exact effects
							// of Swords remain observable after it resolves.
							if target.Kind == "card" && present && card.Identity != nil &&
								!card.Identity.Token && err == nil && power > 0 {
								return PromptResponse{ResponseID: "$submit", TargetIDs: []string{target.ResponseID}}
							}
						}
						t.Fatalf("prepared Swords has no observable positive-power nontoken target: targets=%+v zones=%+v",
							prompt.Targets, view.Zones)
					}
					if prompt.Kind == "chooseAction" {
						if evidence.prepareCasting {
							// Resolve one prepared spell at a time, so no second
							// spell or combat damage can explain its life delta.
							return PromptResponse{ResponseID: "$pass"}
						}
						// Prefer the Adventure before its creature half. Choosing
						// the first legal action alone could skip the mechanic.
						for i, option := range prompt.Options {
							if strings.Contains(option.Label, "Heart's Desire") || strings.Contains(option.Label, "Swords to Plowshares") {
								prompt.Options = append([]PromptOption{option}, append(prompt.Options[:i:i], prompt.Options[i+1:]...)...)
								break
							}
						}
					}
					return liveAnswer(t, prompt, stats)
				}, evidence)
			for _, evidence := range scenario.want {
				if stats[evidence] == 0 {
					t.Errorf("scenario did not exercise %s: %v", evidence, stats)
				}
			}
		})
	}
}

// These observations bind submitted decisions to exact backend card ids and
// later stable projections. Merely offering/selecting an action is not proof
// that the requested spell was cast from its special zone or resolved.
type liveCardEvidence struct {
	scenario       string
	adventure      map[string]bool // card id -> observed on the actual stack
	prepareCasting bool
	prepare        *liveSwordsEvidence
}

type liveSwordsEvidence struct {
	targetID, controllerID, stackID string
	initialLife, power              int
}

func (evidence *liveCardEvidence) submitted(t *testing.T, prompt PromptView,
	answer PromptResponse, view GameView) {
	t.Helper()
	if prompt.Kind == "chooseAction" {
		for _, option := range prompt.Options {
			if option.ResponseID != answer.ResponseID || option.Kind != "cast" {
				continue
			}
			if evidence.scenario == "adventure" && option.Label == "Cast Lovestruck Beast" {
				card, present := liveCardInZone(view, "exile", option.CardID)
				if present && card.Identity != nil && card.Identity.Name == "Lovestruck Beast" {
					evidence.adventure[option.CardID] = false
					t.Logf("Adventure selected creature cast from exile: card=%s", option.CardID)
				}
			}
			if evidence.scenario == "prepare" && option.Label == "Cast Swords to Plowshares" {
				if evidence.prepareCasting {
					t.Fatal("second prepared spell selected before the first was verified")
				}
				evidence.prepareCasting = true
			}
		}
	}
	if evidence.scenario != "prepare" || !evidence.prepareCasting || prompt.Kind != "chooseBoardTargets" {
		return
	}
	if len(answer.TargetIDs) != 1 || evidence.prepare != nil {
		t.Fatal("target decision was not associated with exactly one prepared Swords cast")
	}
	for _, target := range prompt.Targets {
		if target.ResponseID != answer.TargetIDs[0] {
			continue
		}
		card, present := liveCardInZone(view, "battlefield", target.ID)
		power, err := strconv.Atoi(card.Power)
		life, hasController := livePlayerLife(view, card.ControllerID)
		if !present || card.Identity == nil || card.Identity.Token || err != nil || power <= 0 || !hasController {
			t.Fatalf("prepared Swords target is not observable: target=%+v card=%+v", target, card)
		}
		evidence.prepare = &liveSwordsEvidence{
			targetID: card.ID, controllerID: card.ControllerID, initialLife: life, power: power,
		}
		t.Logf("Prepare selected Swords target: card=%s controller=%s power=%d life=%d",
			card.ID, card.ControllerID, power, life)
		return
	}
	t.Fatal("prepared Swords submitted an unrecognized target")
}

func (evidence *liveCardEvidence) observe(t *testing.T, view GameView, stats map[string]int) {
	t.Helper()
	for cardID, onStack := range evidence.adventure {
		for _, object := range view.Stack {
			if object.SourceID == cardID && object.Identity.Name == "Lovestruck Beast" &&
				!strings.HasPrefix(object.ID, "casting-") {
				onStack = true
				evidence.adventure[cardID] = true
			}
		}
		card, present := liveCardInZone(view, "battlefield", cardID)
		if onStack && present && card.Identity != nil && card.Identity.Name == "Lovestruck Beast" {
			if _, stillExiled := liveCardInZone(view, "exile", cardID); stillExiled {
				t.Fatalf("Adventure card %s exists in both exile and battlefield", cardID)
			}
			stats["resolved:adventure_creature_from_exile"]++
			t.Logf("Adventure same-card exile -> stack -> battlefield verified: card=%s", cardID)
			delete(evidence.adventure, cardID)
		}
	}
	prepared := evidence.prepare
	if prepared == nil {
		return
	}
	onStack := false
	for _, object := range view.Stack {
		if object.Identity.Name == "Swords to Plowshares" && !strings.HasPrefix(object.ID, "casting-") {
			if prepared.stackID != "" && prepared.stackID != object.ID {
				t.Fatal("multiple Swords stack objects obscure the prepared spell's resolution")
			}
			prepared.stackID = object.ID
			onStack = true
		}
	}
	if prepared.stackID == "" || onStack {
		return
	}
	_, exiled := liveCardInZone(view, "exile", prepared.targetID)
	_, onBattlefield := liveCardInZone(view, "battlefield", prepared.targetID)
	life, hasController := livePlayerLife(view, prepared.controllerID)
	if !exiled || onBattlefield || !hasController || life != prepared.initialLife+prepared.power {
		t.Fatalf("prepared Swords left the stack without both exact effects: target=%s exile=%v battlefield=%v controller=%s life=%d want=%d",
			prepared.targetID, exiled, onBattlefield, prepared.controllerID, life, prepared.initialLife+prepared.power)
	}
	stats["resolved:prepared_swords_exile_and_life"]++
	t.Logf("Prepare Swords resolution verified: stack=%s target=%s exiled; controller=%s life=%d->%d",
		prepared.stackID, prepared.targetID, prepared.controllerID, prepared.initialLife, life)
	evidence.prepare = nil
	evidence.prepareCasting = false
}

func liveCardInZone(view GameView, zoneName, cardID string) (CardView, bool) {
	for _, zone := range view.Zones {
		if zone.Zone == zoneName {
			for _, card := range zone.Cards {
				if card.ID == cardID {
					return card, true
				}
			}
		}
	}
	return CardView{}, false
}

func livePlayerLife(view GameView, playerID string) (int, bool) {
	for _, player := range view.Players {
		if player.ID == playerID {
			return player.Life, true
		}
	}
	return 0, false
}
