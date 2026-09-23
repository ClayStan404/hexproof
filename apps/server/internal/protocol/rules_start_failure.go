// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package protocol

// RulesStartFailure explains why a Forge game returned to the waiting room.
// Issues are projected only to the deck owner (the host for an AI deck).
// Neither this payload nor its private issues belong in public game journals.
type RulesStartFailure struct {
	Reason    string           `json:"reason"`
	Issues    []RulesDeckIssue `json:"issues,omitempty"`
	Truncated bool             `json:"truncated,omitempty"`
}

// RulesDeckIssue identifies a rejected part of the recipient's submitted deck.
// Card identity comes from the hub's registered deck, never engine error text.
type RulesDeckIssue struct {
	Deck            string `json:"deck"`
	Section         string `json:"section"`
	Code            string `json:"code"`
	CardName        string `json:"cardName,omitempty"`
	SetCode         string `json:"setCode,omitempty"`
	CollectorNumber string `json:"collectorNumber,omitempty"`
}
