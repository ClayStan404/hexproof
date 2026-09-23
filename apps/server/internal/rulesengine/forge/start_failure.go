// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package forge

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"strings"
)

const MaxStartIssues = 32

var ErrStartRejected = fmt.Errorf("%w: game setup rejected", ErrRuntime)

// StartIssue references only the original, private start request. A runtime
// cannot supply arbitrary card names, exception text or filesystem paths.
type StartIssue struct {
	PlayerIndex int    `json:"playerIndex"`
	Section     string `json:"section"`
	CardIndex   int    `json:"cardIndex"`
	Code        string `json:"code"`
}

type StartFailure struct {
	Reason    string       `json:"reason"`
	Issues    []StartIssue `json:"issues,omitempty"`
	Truncated bool         `json:"truncated,omitempty"`
}

// DeckIssue contains identities reconstructed from the caller's own request.
// It must only be projected to the owner of that registered deck.
type DeckIssue struct {
	PlayerIndex int
	Section     string
	Code        string
	Card        CardIdentity
}

type StartError struct {
	failure StartFailure
	issues  []DeckIssue
}

func (e *StartError) Error() string       { return "Forge game setup failed" }
func (e *StartError) Unwrap() error       { return ErrStartRejected }
func (e *StartError) Reason() string      { return e.failure.Reason }
func (e *StartError) Truncated() bool     { return e.failure.Truncated }
func (e *StartError) Issues() []DeckIssue { return append([]DeckIssue(nil), e.issues...) }

// rejectedRequest never formats a native error string. Details stay private
// until StartGame validates them against the exact request that failed.
type rejectedRequest struct{ failure json.RawMessage }

func (e *rejectedRequest) Error() string { return "forge runtime: request rejected" }
func (e *rejectedRequest) Unwrap() error { return ErrRuntime }

func startRequestError(err error, request StartGameRequest) error {
	var rejected *rejectedRequest
	if !errors.As(err, &rejected) {
		return err
	}
	if detail := ParseStartFailure(rejected.failure, request); detail != nil {
		return detail
	}
	return ErrStartRejected
}

// ParseStartFailure validates untrusted JSON and all references before
// reconstructing identities. A malformed detail falls back to a generic error.
func ParseStartFailure(raw json.RawMessage, request StartGameRequest) *StartError {
	if len(raw) == 0 || len(raw) > 16<<10 {
		return nil
	}
	var value struct {
		Reason string `json:"reason"`
		Issues []struct {
			PlayerIndex *int   `json:"playerIndex"`
			Section     string `json:"section"`
			CardIndex   *int   `json:"cardIndex"`
			Code        string `json:"code"`
		} `json:"issues"`
		Truncated bool `json:"truncated,omitempty"`
	}
	d := json.NewDecoder(bytes.NewReader(raw))
	d.DisallowUnknownFields()
	if d.Decode(&value) != nil || d.Decode(new(any)) != io.EOF || len(value.Issues) > MaxStartIssues {
		return nil
	}
	if value.Reason != "deck_rejected" {
		switch value.Reason {
		case "runtime_unavailable", "runtime_timeout", "runtime_failed", "start_rejected":
			if len(value.Issues) == 0 && !value.Truncated {
				return &StartError{failure: StartFailure{Reason: value.Reason}}
			}
		}
		return nil
	}
	if len(value.Issues) == 0 {
		return nil
	}
	result := &StartError{failure: StartFailure{Reason: value.Reason, Truncated: value.Truncated}}
	for _, issue := range value.Issues {
		if issue.PlayerIndex == nil || issue.CardIndex == nil || *issue.PlayerIndex < 0 || *issue.PlayerIndex >= len(request.Players) {
			return nil
		}
		player := request.Players[*issue.PlayerIndex]
		index := *issue.CardIndex
		card := CardIdentity{}
		switch issue.Code {
		case "invalid_deck_size":
			if issue.Section != "mainboard" || index != -1 || (len(player.Deck) > 0 && len(player.Deck) <= maxCardsPerPlayer) {
				return nil
			}
		case "invalid_sideboard_size":
			if issue.Section != "sideboard" || index != -1 || len(player.Sideboard) <= maxCardsPerPlayer {
				return nil
			}
		case "commander_missing":
			if issue.Section != "commanders" || index < 0 || index >= len(player.CommanderNames) {
				return nil
			}
			card.Name = player.CommanderNames[index]
		case "printing_unavailable", "card_unavailable":
			var cards []CardIdentity
			switch issue.Section {
			case "mainboard":
				cards = player.Deck
			case "sideboard":
				cards = player.Sideboard
			default:
				return nil
			}
			if index < 0 || index >= len(cards) {
				return nil
			}
			card = cards[index]
		default:
			return nil
		}
		result.failure.Issues = append(result.failure.Issues, StartIssue{*issue.PlayerIndex, issue.Section, index, issue.Code})
		result.issues = append(result.issues, DeckIssue{*issue.PlayerIndex, issue.Section, issue.Code, card})
	}
	return result
}

// StartFailureJSON is used only on the authenticated private helper relay.
// Its fixed reasons and numeric references contain no user or engine text.
func StartFailureJSON(err error) json.RawMessage {
	var detail *StartError
	if errors.As(err, &detail) {
		raw, _ := json.Marshal(detail.failure)
		return raw
	}
	reason := "runtime_failed"
	var process *ProcessError
	if errors.Is(err, context.DeadlineExceeded) {
		reason = "runtime_timeout"
	} else if errors.Is(err, ErrStartRejected) {
		reason = "start_rejected"
	} else if errors.As(err, &process) && (strings.HasPrefix(process.Code, "executable_") || strings.HasPrefix(process.Code, "probe_")) {
		reason = "runtime_unavailable"
	}
	raw, _ := json.Marshal(StartFailure{Reason: reason})
	return raw
}

// startValidationError retains the existing validation rules, with references
// for recognized deck-size failures and a safe rejection for other bad input.
func startValidationError(request StartGameRequest, cause error) error {
	failure := StartFailure{Reason: "deck_rejected"}
	if len(request.Players) >= 2 && len(request.Players) <= maxPlayers {
		for index, player := range request.Players {
			if len(player.Deck) == 0 || len(player.Deck) > maxCardsPerPlayer {
				failure.Issues = append(failure.Issues, StartIssue{index, "mainboard", -1, "invalid_deck_size"})
			}
			if len(player.Sideboard) > maxCardsPerPlayer {
				failure.Issues = append(failure.Issues, StartIssue{index, "sideboard", -1, "invalid_sideboard_size"})
			}
		}
	}
	if len(failure.Issues) > 0 {
		raw, _ := json.Marshal(failure)
		if detail := ParseStartFailure(raw, request); detail != nil {
			return detail
		}
	}
	return fmt.Errorf("%w: %v", ErrStartRejected, cause)
}
