// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package server

import (
	"bufio"
	"encoding/json"
	"fmt"
	"os"
	"reflect"
	"strconv"
	"testing"

	"hexproof/server/internal/protocol"
	"hexproof/server/internal/rulesengine/forge"
)

// This opt-in integration bridge consumes actual native evidence. It is not a
// production endpoint and never trusts a native response as a client command.
func TestForgeCardCorpus(t *testing.T) {
	inputPath := os.Getenv("HEXPROOF_FORGE_CORPUS_INPUT")
	if inputPath == "" {
		t.Skip("set HEXPROOF_FORGE_CORPUS_INPUT and HEXPROOF_FORGE_CORPUS_OUTPUT for the frozen corpus")
	}
	input, err := os.Open(inputPath)
	if err != nil {
		t.Fatal(err)
	}
	defer input.Close()
	output, err := os.Create(os.Getenv("HEXPROOF_FORGE_CORPUS_OUTPUT"))
	if err != nil {
		t.Fatal(err)
	}
	defer output.Close()
	scanner := bufio.NewScanner(input)
	scanner.Buffer(make([]byte, 65536), 32*1024*1024)
	count := 0
	for scanner.Scan() {
		var record struct {
			Card   string `json:"card"`
			Case   string `json:"case"`
			Status string `json:"status"`
			Frames []struct {
				Actor     int               `json:"actor"`
				Prompt    json.RawMessage   `json:"prompt"`
				Response  json.RawMessage   `json:"response"`
				Snapshots []json.RawMessage `json:"snapshots"`
			} `json:"frames"`
			After []json.RawMessage `json:"after"`
		}
		if err := json.Unmarshal(scanner.Bytes(), &record); err != nil {
			t.Fatal(err)
		}
		count++
		t.Run(record.Card+"/"+record.Case, func(t *testing.T) {
			projected := map[string]any{"card": record.Card, "case": record.Case, "nativeStatus": record.Status}
			frames := []any{}
			game := forgeRoomGame{gameID: "card-corpus", playerToSeat: map[int]int{0: 0, 1: 1}, seatToPlayer: map[int]int{0: 0, 1: 1}}
			project := func(raw json.RawMessage) (forge.GameView, protocol.RulesGameSnapshot) {
				view, err := forge.DecodeSnapshotView(raw)
				if err != nil {
					t.Fatal(err)
				}
				for _, zone := range view.Zones {
					for _, card := range zone.Cards {
						if card.Visibility != "visible" && card.Identity != nil {
							t.Fatalf("private identity exposed in %s", zone.Zone)
						}
					}
				}
				snapshot, err := normalizeForgeSnapshot("CORPUS", game, view)
				if err != nil {
					t.Fatal(err)
				}
				envelope, err := protocol.NewEnvelope(protocol.TypeRulesSnapshot, snapshot)
				if err != nil {
					t.Fatal(err)
				}
				assertNormalizedRulesWireArrays(t, envelope)
				return view, snapshot
			}
			for index, frame := range record.Frames {
				if len(frame.Response) == 0 {
					continue // The native driver stopped before it could answer this frame.
				}
				var view forge.GameView
				var snapshot protocol.RulesGameSnapshot
				for seat, raw := range frame.Snapshots {
					v, s := project(raw)
					if seat == frame.Actor {
						view, snapshot = v, s
					}
				}
				prompt, err := forge.NormalizePrompt(frame.Prompt)
				if err != nil || !prompt.Supported || prompt.PlayerIndex != frame.Actor {
					t.Fatalf("frame %d native prompt cannot be presented: %v", index, err)
				}
				wire, err := projectedRulesPrompt("CORPUS", game.gameID, prompt, game, &view)
				if err != nil {
					t.Fatalf("frame %d projection: %v", index, err)
				}
				envelope, err := protocol.NewEnvelope(protocol.TypeRulesPrompt, wire)
				if err != nil {
					t.Fatal(err)
				}
				assertNormalizedRulesWireArrays(t, envelope)
				answer := corpusResponse(t, prompt, frame.Prompt, frame.Response)
				canonical, err := forge.BuildPromptResponse(frame.Prompt, frame.Actor, prompt.PromptID, answer)
				if err != nil {
					t.Fatalf("frame %d response rejected: %v", index, err)
				}
				var expected, actual any
				if err := json.Unmarshal(frame.Response, &expected); err != nil {
					t.Fatal(err)
				}
				if err := json.Unmarshal(canonical, &actual); err != nil {
					t.Fatal(err)
				}
				if !reflect.DeepEqual(expected, actual) {
					t.Fatalf("frame %d changed the accepted native response: %s != %s", index, canonical, frame.Response)
				}
				frames = append(frames, map[string]any{"actor": frame.Actor, "snapshot": snapshot, "prompt": wire, "answer": answer})
			}
			projected["frames"] = frames
			after := []protocol.RulesGameSnapshot{}
			for _, raw := range record.After {
				_, snapshot := project(raw)
				after = append(after, snapshot)
			}
			projected["after"] = after
			if err := json.NewEncoder(output).Encode(projected); err != nil {
				t.Fatal(err)
			}
		})
	}
	if err := scanner.Err(); err != nil {
		t.Fatal(err)
	}
	if count == 0 {
		t.Fatal("empty native corpus")
	}
}

func corpusResponse(t *testing.T, view forge.PromptView, promptRaw, raw json.RawMessage) forge.PromptResponse {
	t.Helper()
	var envelope struct {
		Output struct {
			Type          string                      `json:"type"`
			Value         bool                        `json:"value"`
			Name          string                      `json:"name"`
			ChosenNumber  int                         `json:"chosenNumber"`
			ChosenIndices []int                       `json:"chosenIndices"`
			ChosenCardIDs []string                    `json:"chosenCardIds"`
			OrderedIDs    []string                    `json:"orderedIds"`
			ZoneCardIDs   [][]string                  `json:"zoneCardIds"`
			Chosen        []struct{ Kind, ID string } `json:"chosen"`
		} `json:"output"`
	}
	if err := json.Unmarshal(raw, &envelope); err != nil {
		t.Fatal(err)
	}
	output := envelope.Output
	answer := forge.PromptResponse{ResponseID: "$submit", CardIDs: []string{},
		TargetIDs: []string{}, ChoiceIDs: []string{}, OrderedIDs: []string{}, ScryPiles: []forge.PromptScryPile{}}
	switch output.Type {
	case "pay":
		answer.ResponseID = "$auto-pay"
	case "revealCardsAcknowledged":
		answer.ResponseID = "$ack"
	case "decision":
		for _, choice := range view.Choices {
			if choice.Value == strconv.FormatBool(output.Value) {
				answer.ChoiceIDs = append(answer.ChoiceIDs, choice.ResponseID)
			}
		}
	case "selectionDecision":
		for _, index := range output.ChosenIndices {
			for _, choice := range view.Choices {
				if choice.Value == strconv.Itoa(index) {
					answer.ChoiceIDs = append(answer.ChoiceIDs, choice.ResponseID)
				}
			}
		}
	case "boardTargets":
		for _, selected := range output.Chosen {
			for _, target := range view.Targets {
				if target.Kind == selected.Kind && target.ID == selected.ID {
					answer.TargetIDs = append(answer.TargetIDs, target.ResponseID)
				}
			}
		}
	case "chooseCardsDecision":
		answer.CardIDs = output.ChosenCardIDs
	case "cardName":
		answer.Name = output.Name
	case "numberDecision":
		answer.ChosenNumber = &output.ChosenNumber
	case "reorderDecision":
		for _, id := range output.OrderedIDs {
			for _, item := range view.OrderItems {
				if item.ID == id {
					answer.OrderedIDs = append(answer.OrderedIDs, item.ResponseID)
				}
			}
		}
	case "scryDecision":
		var prompt struct {
			Input struct{ Cards []struct{ ID string } } `json:"input"`
		}
		if err := json.Unmarshal(promptRaw, &prompt); err != nil {
			t.Fatal(err)
		}
		for index, ids := range output.ZoneCardIDs {
			mapped := []string{}
			for _, id := range ids {
				for cardIndex, card := range prompt.Input.Cards {
					if card.ID == id {
						mapped = append(mapped, view.Cards[cardIndex].ID)
					}
				}
			}
			answer.ScryPiles = append(answer.ScryPiles, forge.PromptScryPile{Destination: view.ScryDestinations[index], CardIDs: mapped})
		}
	default:
		t.Fatal(fmt.Sprintf("unhandled corpus response %q", output.Type))
	}
	return answer
}
