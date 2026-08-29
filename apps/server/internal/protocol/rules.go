// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package protocol

// RulesCounter is one normalized player, mana-pool, or permanent counter.
type RulesCounter struct {
	Name  string `json:"name"`
	Value int    `json:"value"`
}

// RulesCardIdentity is the visible paper identity of an engine card.
type RulesCardIdentity struct {
	Name            string `json:"name"`
	SetCode         string `json:"setCode"`
	CollectorNumber string `json:"collectorNumber"`
	Token           bool   `json:"token,omitempty"`
}

type RulesPlayerState struct {
	Seat     int            `json:"seat"`
	Name     string         `json:"name"`
	Status   string         `json:"status"`
	Life     int            `json:"life"`
	Counters []RulesCounter `json:"counters"`
	ManaPool []RulesCounter `json:"manaPool"`
}

// RulesCardState never includes Identity when Forge redacted the card for the
// requested viewer.
type RulesCardState struct {
	ID             string             `json:"id"`
	Visible        bool               `json:"visible"`
	Identity       *RulesCardIdentity `json:"identity,omitempty"`
	OwnerSeat      int                `json:"ownerSeat"`
	ControllerSeat int                `json:"controllerSeat"`
	Tapped         bool               `json:"tapped,omitempty"`
	FaceDown       bool               `json:"faceDown,omitempty"`
	Attacking      bool               `json:"attacking,omitempty"`
	Power          string             `json:"power,omitempty"`
	Toughness      string             `json:"toughness,omitempty"`
	Counters       []RulesCounter     `json:"counters"`
	Damage         int                `json:"damage,omitempty"`
	AttachedTo     string             `json:"attachedTo,omitempty"`
}

type RulesZoneState struct {
	Zone      string           `json:"zone"`
	OwnerSeat int              `json:"ownerSeat"`
	Count     int              `json:"count"`
	Cards     []RulesCardState `json:"cards"`
}

type RulesStackObject struct {
	ID             string            `json:"id"`
	SourceID       string            `json:"sourceId"`
	ControllerSeat int               `json:"controllerSeat"`
	OwnerSeat      int               `json:"ownerSeat"`
	Identity       RulesCardIdentity `json:"identity"`
	Text           string            `json:"text"`
}

// RulesPromptOption is a stable, opaque response choice. Forge action ids stay
// behind the server boundary and are revalidated against the current prompt.
type RulesPromptOption struct {
	ResponseID string `json:"responseId"`
	Kind       string `json:"kind"`
	Label      string `json:"label"`
	CardID     string `json:"cardId,omitempty"`
}

// RulesPromptChoice is a countable scalar choice with a prompt-local opaque
// response id. Weight contributes to the prompt's required total.
type RulesPromptChoice struct {
	ResponseID string `json:"responseId"`
	Label      string `json:"label"`
	Weight     int    `json:"weight"`
	CanRepeat  bool   `json:"canRepeat"`
}

// RulesPromptCard is a private selectable card identity projected only to the
// authenticated player who owns the current rules prompt.
type RulesPromptCard struct {
	ID              string `json:"id"`
	Name            string `json:"name"`
	SetCode         string `json:"setCode"`
	CollectorNumber string `json:"collectorNumber"`
	Token           bool   `json:"token,omitempty"`
}

// RulesPromptOrderItem is one prompt-local sortable card or trigger.
type RulesPromptOrderItem struct {
	ResponseID      string `json:"responseId"`
	Name            string `json:"name"`
	SetCode         string `json:"setCode,omitempty"`
	CollectorNumber string `json:"collectorNumber,omitempty"`
	Token           bool   `json:"token,omitempty"`
	Oracle          string `json:"oracle,omitempty"`
}

// RulesPromptTarget is a short-lived target choice. ResponseID is opaque;
// ObjectID is present only when the same card or stack object already exists in
// the deciding player's normalized snapshot. Identity fields remain omitted
// when that object is hidden from the deciding player.
type RulesPromptTarget struct {
	ResponseID      string `json:"responseId"`
	Kind            string `json:"kind"`
	Label           string `json:"label"`
	ObjectID        string `json:"objectId,omitempty"`
	Name            string `json:"name,omitempty"`
	SetCode         string `json:"setCode,omitempty"`
	CollectorNumber string `json:"collectorNumber,omitempty"`
	Token           bool   `json:"token,omitempty"`
}

// RulesPromptCombatSource is one attacking or blocking permanent. Its legal
// targets use prompt-local ids; ObjectID is the card id from the deciding
// player's already-authorized snapshot, never a response token accepted by the
// server.
type RulesPromptCombatSource struct {
	ResponseID       string   `json:"responseId"`
	ObjectID         string   `json:"objectId"`
	Label            string   `json:"label"`
	Name             string   `json:"name"`
	SetCode          string   `json:"setCode"`
	CollectorNumber  string   `json:"collectorNumber"`
	Token            bool     `json:"token,omitempty"`
	ValidTargetIDs   []string `json:"validTargetIds"`
	MustAssignIfAble bool     `json:"mustAssignIfAble"`
}

// RulesPromptCombatTarget is one defender or attacker plus its unambiguous
// per-target cardinality constraints and conditional requirement hint.
type RulesPromptCombatTarget struct {
	ResponseID        string `json:"responseId"`
	Kind              string `json:"kind"`
	Label             string `json:"label"`
	ObjectID          string `json:"objectId,omitempty"`
	Name              string `json:"name,omitempty"`
	SetCode           string `json:"setCode,omitempty"`
	CollectorNumber   string `json:"collectorNumber,omitempty"`
	Token             bool   `json:"token,omitempty"`
	Minimum           int    `json:"minAssignments"`
	Maximum           int    `json:"maxAssignments"`
	MustReceiveIfAble bool   `json:"mustReceiveIfAble"`
}

// RulesPromptAssignment is one source-to-target combat declaration using only
// ids from the current authenticated prompt.
type RulesPromptAssignment struct {
	SourceID string `json:"sourceId"`
	TargetID string `json:"targetId"`
}

// RulesPrompt is addressed only to its deciding player. Unsupported prompt
// families remain visible as a non-interactive soft error instead of exposing
// raw backend JSON or making the Qt client guess its shape.
type RulesPrompt struct {
	RoomID        string                    `json:"roomId"`
	GameID        string                    `json:"gameId"`
	Pending       bool                      `json:"pending"`
	PromptID      int64                     `json:"promptId"`
	Kind          string                    `json:"kind"`
	Supported     bool                      `json:"supported"`
	Title         string                    `json:"title"`
	Detail        string                    `json:"detail"`
	Options       []RulesPromptOption       `json:"options"`
	Choices       []RulesPromptChoice       `json:"choices"`
	Cards         []RulesPromptCard         `json:"cards"`
	OrderItems    []RulesPromptOrderItem    `json:"orderItems"`
	Required      int                       `json:"requiredSelections"`
	CardMinimum   int                       `json:"minCardSelections"`
	CardMaximum   int                       `json:"maxCardSelections"`
	Targets       []RulesPromptTarget       `json:"targets"`
	CombatSources []RulesPromptCombatSource `json:"combatSources"`
	CombatTargets []RulesPromptCombatTarget `json:"combatTargets"`
	Minimum       int                       `json:"minSelections"`
	Maximum       int                       `json:"maxSelections"`
	Cancellable   bool                      `json:"cancellable"`
	ChoiceMinimum int                       `json:"minChoiceTotal"`
	ChoiceMaximum int                       `json:"maxChoiceTotal"`
	NumberMinimum int                       `json:"minNumber"`
	NumberMaximum int                       `json:"maxNumber"`
}

type RulesRespond struct {
	PromptID     int64                   `json:"promptId"`
	ResponseID   string                  `json:"responseId"`
	CardIDs      []string                `json:"cardIds,omitempty"`
	TargetIDs    []string                `json:"targetIds,omitempty"`
	Assignments  []RulesPromptAssignment `json:"assignments,omitempty"`
	ChoiceIDs    []string                `json:"choiceIds,omitempty"`
	OrderedIDs   []string                `json:"orderedIds,omitempty"`
	ChosenNumber *int                    `json:"chosenNumber,omitempty"`
}

type RulesResponded struct {
	RoomID   string `json:"roomId"`
	PromptID int64  `json:"promptId"`
}

// RulesGameSnapshot is a viewer-specific normalized projection. Raw Forge
// payloads never cross the public protocol boundary.
type RulesGameSnapshot struct {
	RoomID       string             `json:"roomId"`
	GameID       string             `json:"gameId"`
	Turn         int                `json:"turn"`
	Step         string             `json:"step"`
	ActiveSeat   int                `json:"activeSeat"`
	PrioritySeat int                `json:"prioritySeat"`
	Players      []RulesPlayerState `json:"players"`
	Zones        []RulesZoneState   `json:"zones"`
	Stack        []RulesStackObject `json:"stack"`
	GameOver     bool               `json:"gameOver"`
	WinnerSeat   *int               `json:"winnerSeat,omitempty"`
}
