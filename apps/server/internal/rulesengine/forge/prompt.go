// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package forge

import (
	"encoding/json"
	"errors"
	"fmt"
	"strconv"
	"strings"
)

const (
	maxPromptOptions = 512
	maxPromptCards   = 512
	maxPromptText    = 512
)

// PromptOption is a Hexproof-owned presentation choice. ResponseID is stable
// only for the lifetime of one prompt and never contains an upstream action id.
type PromptOption struct {
	ResponseID string
	Kind       string
	Label      string
	CardID     string
}

// PromptChoice is one countable scalar choice. Value is server-private and is
// mapped back to the canonical Forge value only after the current prompt is
// revalidated.
type PromptChoice struct {
	ResponseID string
	Label      string
	Weight     int
	CanRepeat  bool
	Value      string
}

// PromptCard is the smallest card identity needed to present a private Forge
// decision or disclosure. Rules text and other engine-owned state stay behind
// the server.
type PromptCard struct {
	ID              string
	Name            string
	SetCode         string
	CollectorNumber string
	Token           bool
}

// PromptScryPile is one ordered destination pile submitted with opaque card
// ids from the current scry prompt.
type PromptScryPile struct {
	Destination string
	CardIDs     []string
}

// PromptOrderItem is one sortable card or trigger. ID and any upstream item
// description remain server-private; the deciding client receives ResponseID
// plus only the bounded presentation fields Forge supplied for this choice.
type PromptOrderItem struct {
	ResponseID      string
	ID              string
	Name            string
	SetCode         string
	CollectorNumber string
	Token           bool
	Oracle          string
}

// PromptTarget keeps the upstream target id private while assigning a
// short-lived response id for the authenticated Qt client.
type PromptTarget struct {
	ResponseID string
	Kind       string
	ID         string
	Oracle     string
}

// PromptCombatSource is one attacking or blocking permanent. ValidTargetIDs
// contains only prompt-local opaque ids; ID remains server-private so a
// response can be reconstructed against the current upstream prompt.
type PromptCombatSource struct {
	ResponseID       string
	ID               string
	ValidTargetIDs   []string
	MustAssignIfAble bool
}

// PromptCombatTarget is one legal defender or attacker plus the unambiguous
// per-target cardinality constraints. Conditional global requirements remain
// hints so Forge can resolve conflicting requirements.
type PromptCombatTarget struct {
	ResponseID        string
	Kind              string
	ID                string
	Label             string
	Minimum           int
	Maximum           int
	MustReceiveIfAble bool
}

// PromptAssignment is a prompt-local source-to-target choice submitted by the
// authenticated deciding player.
type PromptAssignment struct {
	SourceID string
	TargetID string
}

// PromptDamageSource is the permanent assigning combat damage. ID remains
// private and is joined to the deciding player's current snapshot before the
// public prompt is emitted.
type PromptDamageSource struct {
	ID string
}

// PromptDamageTarget is one permanent or defending player in Forge's required
// assignment order. Defender distinguishes the final trample destination from
// permanents that must receive lethal damage before later entries.
type PromptDamageTarget struct {
	ResponseID string
	Kind       string
	ID         string
	Defender   bool
}

// PromptDamageAssignment is one exact amount assigned to a prompt-local
// damage target.
type PromptDamageAssignment struct {
	TargetID string
	Damage   int
}

// PromptView is the normalized, privacy-safe subset of one Forge prompt.
type PromptView struct {
	PromptID         int64
	PlayerIndex      int
	Kind             string
	Supported        bool
	Title            string
	Detail           string
	Options          []PromptOption
	Choices          []PromptChoice
	Cards            []PromptCard
	ScryDestinations []string
	OrderItems       []PromptOrderItem
	ContextCards     []PromptCard
	ContextTargets   []PromptTarget
	ContextText      string
	Required         int
	CardMinimum      int
	CardMaximum      int
	Targets          []PromptTarget
	CombatSources    []PromptCombatSource
	CombatTargets    []PromptCombatTarget
	DamageSource     *PromptDamageSource
	DamageTargets    []PromptDamageTarget
	TotalDamage      int
	DamageDeathtouch bool
	MinSelected      int
	MaxSelected      int
	Cancellable      bool
	ChoiceMinimum    int
	ChoiceMaximum    int
	NumberMinimum    int
	NumberMaximum    int
}

// PromptResponse is the typed Hexproof-side answer to one current prompt.
// Each prompt family accepts only its corresponding payload field.
type PromptResponse struct {
	ResponseID        string
	CardIDs           []string
	TargetIDs         []string
	Assignments       []PromptAssignment
	ChoiceIDs         []string
	OrderedIDs        []string
	ScryPiles         []PromptScryPile
	DamageOrderIDs    []string
	DamageAssignments []PromptDamageAssignment
	ChosenNumber      *int
}

type promptEnvelope struct {
	PromptID       int64           `json:"promptId"`
	DecidingPlayer string          `json:"decidingPlayerId"`
	SourceCard     *promptCard     `json:"sourceCard"`
	Input          json.RawMessage `json:"input"`
}

type promptInput struct {
	Type                  string                  `json:"type"`
	Actions               []promptAction          `json:"actions"`
	Presentation          promptPresentation      `json:"presentation"`
	CardName              string                  `json:"cardName"`
	ManaCost              string                  `json:"manaCost"`
	CanConfirmFromPool    bool                    `json:"canConfirmFromPool"`
	MulliganCount         int                     `json:"mulliganCount"`
	HandCardIDs           []string                `json:"handCardIds"`
	Cards                 []promptCard            `json:"cards"`
	Zones                 []string                `json:"zones"`
	Items                 []promptOrderItem       `json:"items"`
	Count                 int                     `json:"count"`
	Candidates            []promptTargetRef       `json:"candidates"`
	MinTargets            int                     `json:"minTargets"`
	MaxTargets            int                     `json:"maxTargets"`
	ChosenTargets         int                     `json:"chosenTargets"`
	Cancellable           bool                    `json:"cancellable"`
	Attackers             []promptCombatant       `json:"attackers"`
	AttackTargets         []promptAttackTarget    `json:"attackTargets"`
	AvailableBlockerIDs   []string                `json:"availableBlockerIds"`
	Error                 string                  `json:"error"`
	ConfirmLabel          string                  `json:"confirmLabel"`
	DenyLabel             string                  `json:"denyLabel"`
	Min                   *int                    `json:"min"`
	Max                   *int                    `json:"max"`
	ValidColors           []string                `json:"validColors"`
	Amount                *int                    `json:"amount"`
	RepeatAllowed         bool                    `json:"repeatAllowed"`
	SelectionOptions      []promptSelectionOption `json:"options"`
	MinTotal              *int                    `json:"minTotal"`
	MaxTotal              *int                    `json:"maxTotal"`
	AttackerID            string                  `json:"attackerId"`
	BlockerIDs            []string                `json:"blockerIds"`
	BlockerCards          []promptCard            `json:"blockerCards"`
	DefenderID            string                  `json:"defenderId"`
	TotalDamage           *int                    `json:"totalDamage"`
	AttackerHasDeathtouch bool                    `json:"attackerHasDeathtouch"`
}

type promptSelectionOption struct {
	Label     string `json:"label"`
	Weight    int    `json:"weight"`
	CanRepeat bool   `json:"canRepeat"`
}

type promptPresentation struct {
	Title       string            `json:"title"`
	Description string            `json:"description"`
	Text        string            `json:"text"`
	Targets     []promptTargetRef `json:"targets"`
}

type promptAction struct {
	ID          string `json:"id"`
	Type        string `json:"type"`
	CardID      string `json:"cardId"`
	Label       string `json:"label"`
	ModeLabel   string `json:"modeLabel"`
	Description string `json:"description"`
}

type promptCard struct {
	ID       string             `json:"id"`
	Identity promptCardIdentity `json:"identity"`
}

type promptCardIdentity struct {
	Name       string `json:"name"`
	SetCode    string `json:"setCode"`
	CardNumber string `json:"cardNumber"`
	IsToken    bool   `json:"isToken"`
}

type promptOrderItem struct {
	ID     string     `json:"id"`
	Card   promptCard `json:"card"`
	Oracle string     `json:"oracle"`
}

type promptTargetRef struct {
	Kind   string `json:"kind"`
	ID     string `json:"id"`
	Oracle string `json:"oracle,omitempty"`
}

type promptCombatant struct {
	AttackerID      string   `json:"attackerId"`
	ValidTargetIDs  []string `json:"validTargetIds"`
	MustAttack      bool     `json:"mustAttack"`
	ValidBlockerIDs []string `json:"validBlockerIds"`
	MinBlockers     int      `json:"minBlockers"`
	MaxBlockers     *int     `json:"maxBlockers"`
	MustBeBlocked   bool     `json:"mustBeBlocked"`
}

type promptAttackTarget struct {
	ID    string `json:"id"`
	Label string `json:"label"`
	Kind  string `json:"kind"`
}

// NormalizePrompt validates the private upstream envelope and returns only
// fields the deciding player's Qt view needs. Unknown prompt families are a
// supported soft failure: their kind is shown, but no response can be sent.
func NormalizePrompt(raw json.RawMessage) (PromptView, error) {
	envelope, input, playerIndex, err := decodePrompt(raw)
	if err != nil {
		return PromptView{}, err
	}
	view := PromptView{
		PromptID: envelope.PromptID, PlayerIndex: playerIndex, Kind: input.Type,
		Title:            boundedPromptText(input.Presentation.Title),
		Detail:           boundedPromptText(input.Presentation.Description),
		Options:          []PromptOption{},
		Choices:          []PromptChoice{},
		Cards:            []PromptCard{},
		ScryDestinations: []string{},
		OrderItems:       []PromptOrderItem{},
		ContextCards:     []PromptCard{},
		ContextTargets:   []PromptTarget{},
		Targets:          []PromptTarget{},
		CombatSources:    []PromptCombatSource{},
		CombatTargets:    []PromptCombatTarget{},
		DamageTargets:    []PromptDamageTarget{},
	}
	view.ContextCards, view.ContextTargets, view.ContextText, err =
		normalizePromptContext(envelope.SourceCard, input.Presentation)
	if err != nil {
		return PromptView{}, err
	}
	switch input.Type {
	case "diceRolled":
		view.Supported = true
		if view.Title == "" {
			view.Title = "Roll for first player"
		}
		view.Options = []PromptOption{
			{ResponseID: "$ack", Kind: "acknowledge", Label: "Continue"},
		}
	case "chooseAction":
		view.Supported = true
		if view.Title == "" {
			view.Title = "Choose an action"
		}
		if view.Detail == "" {
			view.Detail = "You have priority."
		}
		view.Options, err = normalizeActions(input.Actions)
		if err == nil {
			view.Options = append(view.Options,
				PromptOption{ResponseID: "$pass", Kind: "pass", Label: "Pass priority"},
				PromptOption{ResponseID: "$pass-stack", Kind: "pass", Label: "Resolve current stack"})
		}
	case "mulligan":
		view.Supported = true
		view.Title = "Opening hand"
		view.Detail = fmt.Sprintf("Mulligans taken: %d", input.MulliganCount)
		view.Options = []PromptOption{
			{ResponseID: "$keep", Kind: "keep", Label: "Keep hand"},
			{ResponseID: "$mulligan", Kind: "mulligan", Label: "Take a mulligan"},
		}
	case "mulliganPutBack":
		view.Supported = true
		view.Title = "Choose cards to put back"
		view.Required = input.Count
		view.CardMinimum = input.Count
		view.CardMaximum = input.Count
		view.Detail = fmt.Sprintf("Choose exactly %d card(s) to put on the bottom of your library.",
			input.Count)
		view.Cards, err = normalizePromptCards(input.HandCardIDs, input.Cards, input.Count)
	case "chooseCards":
		view.Supported = true
		view.Title = firstPromptText(view.Title, "Choose cards")
		view.Cards, view.CardMinimum, view.CardMaximum, err = normalizeChooseCards(input)
		if view.Detail == "" && err == nil {
			view.Detail = cardSelectionRangeDetail(view.CardMinimum, view.CardMaximum)
		}
	case "revealCards":
		view.Supported = true
		view.Title = firstPromptText(view.Title, "Look at these cards")
		view.Cards, err = normalizeRevealedCards(input.Cards)
		view.Options = []PromptOption{
			{ResponseID: "$ack", Kind: "acknowledge", Label: "Continue"},
		}
	case "reorder":
		view.Supported = true
		view.Title = firstPromptText(view.Title, "Choose an order")
		view.OrderItems, err = normalizeReorderItems(input.Items)
		if view.Detail == "" {
			view.Detail = "Item 1 goes first; the remaining items follow in order."
		}
	case "scry":
		view.Supported = true
		view.Title = firstPromptText(view.Title, "Sort cards into zones")
		view.Cards, view.ScryDestinations, err = normalizeScry(input)
	case "chooseBoardTargets":
		view.Supported = true
		if view.Title == "" {
			view.Title = "Choose targets"
		}
		view.Targets, view.MinSelected, view.MaxSelected, err = normalizePromptTargets(input)
		view.Cancellable = input.Cancellable
		if view.Detail == "" && err == nil {
			view.Detail = selectionRangeDetail(view.MinSelected, view.MaxSelected)
		}
	case "chooseAttackers":
		view.Supported = true
		view.Title = "Declare attackers"
		view.Detail = "Assign each attacking creature to a legal defender."
		view.CombatSources, view.CombatTargets, err = normalizeAttackers(input)
	case "chooseBlockers":
		view.Supported = true
		view.Title = "Declare blockers"
		view.Detail = firstPromptText(input.Error, "Assign each blocker to at most one attacker.")
		view.CombatSources, view.CombatTargets, err = normalizeBlockers(input)
	case "chooseDamageAssignmentOrder":
		view.Supported = true
		view.Title = firstPromptText(view.Title, "Choose combat damage order")
		view.Detail = firstPromptText(view.Detail,
			"The first permanent must receive lethal damage before the next one.")
		view.DamageSource, view.DamageTargets, err = normalizeDamageOrder(input)
	case "chooseCombatDamageAssignment":
		view.Supported = true
		view.Title = firstPromptText(view.Title, "Assign combat damage")
		view.Detail = firstPromptText(view.Detail,
			"Assign all combat damage in order.")
		view.DamageSource, view.DamageTargets, view.TotalDamage,
			view.DamageDeathtouch, err = normalizeCombatDamage(input)
	case "chooseBoolean":
		view.Supported = true
		view.Title = firstPromptText(view.Title, "Choose yes or no")
		view.Choices, view.ChoiceMinimum, view.ChoiceMaximum, err = normalizeBoolean(input)
	case "chooseNumber":
		view.Supported = true
		view.Title = firstPromptText(view.Title, "Choose a number")
		view.NumberMinimum, view.NumberMaximum, err = normalizeNumber(input)
	case "chooseColor":
		view.Supported = true
		view.Title = firstPromptText(view.Title, "Choose colors")
		view.Choices, view.ChoiceMinimum, view.ChoiceMaximum, err = normalizeColors(input)
	case "chooseFromSelection":
		view.Supported = true
		view.Title = firstPromptText(view.Title, "Choose options")
		view.Choices, view.ChoiceMinimum, view.ChoiceMaximum, err = normalizeSelection(input)
	case "payManaCost":
		view.Supported = true
		if view.Title == "" {
			view.Title = "Pay mana"
		}
		if view.Detail == "" {
			view.Detail = strings.TrimSpace(strings.Join(
				[]string{boundedPromptText(input.CardName), boundedPromptText(input.ManaCost)}, " "))
		}
		view.Options, err = normalizeActions(input.Actions)
		if err == nil {
			if input.CanConfirmFromPool {
				view.Options = append(view.Options,
					PromptOption{ResponseID: "$pay", Kind: "pay", Label: "Confirm payment"})
			}
			view.Options = append(view.Options,
				PromptOption{ResponseID: "$auto-pay", Kind: "pay", Label: "Auto-pay"},
				PromptOption{ResponseID: "$cancel", Kind: "cancel", Label: "Cancel"})
		}
	default:
		if view.Title == "" {
			view.Title = "Forge decision required"
		}
		view.Detail = "This decision type is not supported by this Hexproof build."
	}
	if err != nil {
		return PromptView{}, err
	}
	return view, nil
}

// BuildPromptResponse re-decodes the current Forge prompt and maps one stable
// Hexproof choice back to its exact canonical response. Callers must fetch the
// prompt again immediately before this function so stale and foreign actions
// never cross the engine boundary.
func BuildPromptResponse(raw json.RawMessage, expectedPlayerIndex int,
	promptID int64, answer PromptResponse) (json.RawMessage, error) {
	view, err := NormalizePrompt(raw)
	if err != nil {
		return nil, err
	}
	if view.PlayerIndex != expectedPlayerIndex || view.PromptID != promptID ||
		promptID <= 0 || strings.TrimSpace(answer.ResponseID) == "" || !view.Supported {
		return nil, errors.New("prompt response does not match the current decision")
	}
	if view.Kind != "reorder" && len(answer.OrderedIDs) != 0 {
		return nil, errors.New("prompt response contains an unexpected order")
	}
	if view.Kind != "scry" && len(answer.ScryPiles) != 0 {
		return nil, errors.New("prompt response contains unexpected scry piles")
	}
	if view.Kind != "chooseDamageAssignmentOrder" && len(answer.DamageOrderIDs) != 0 {
		return nil, errors.New("prompt response contains an unexpected damage order")
	}
	if view.Kind != "chooseCombatDamageAssignment" && len(answer.DamageAssignments) != 0 {
		return nil, errors.New("prompt response contains unexpected damage assignments")
	}
	var output any
	switch view.Kind {
	case "diceRolled":
		if answer.ResponseID == "$ack" && answer.emptySelections() {
			output = map[string]any{"type": "diceRolledAcknowledged"}
		} else {
			err = errors.New("unknown dice-roll response")
		}
	case "chooseAction":
		if !answer.emptySelections() {
			err = errors.New("choose-action response contains unexpected selections")
		} else {
			output, err = chooseActionOutput(raw, answer.ResponseID)
		}
	case "mulligan":
		if !answer.emptySelections() {
			err = errors.New("mulligan response contains unexpected selections")
			break
		}
		switch answer.ResponseID {
		case "$keep":
			output = map[string]any{"type": "mulliganDecision", "keep": true}
		case "$mulligan":
			output = map[string]any{"type": "mulliganDecision", "keep": false}
		default:
			err = errors.New("unknown mulligan response")
		}
	case "mulliganPutBack":
		if answer.hasNonCardSelections() {
			err = errors.New("mulligan put-back response contains unexpected selections")
		} else {
			output, err = mulliganPutBackOutput(raw, answer.ResponseID, answer.CardIDs)
		}
	case "chooseCards":
		if answer.hasNonCardSelections() {
			err = errors.New("card response contains unexpected selections")
		} else {
			output, err = chooseCardsOutput(raw, answer.ResponseID, answer.CardIDs)
		}
	case "revealCards":
		if answer.ResponseID == "$ack" && answer.emptySelections() {
			output = map[string]any{"type": "revealCardsAcknowledged"}
		} else {
			err = errors.New("unknown reveal-cards response")
		}
	case "reorder":
		if answer.hasNonOrderSelections() {
			err = errors.New("reorder response contains unexpected selections")
		} else {
			output, err = reorderOutput(raw, answer.ResponseID, answer.OrderedIDs)
		}
	case "scry":
		if answer.hasNonScrySelections() {
			err = errors.New("scry response contains unexpected selections")
		} else {
			output, err = scryOutput(raw, answer.ResponseID, answer.ScryPiles)
		}
	case "chooseBoardTargets":
		if len(answer.CardIDs) != 0 {
			err = errors.New("target response contains unexpected cards")
		} else {
			output, err = boardTargetsOutput(raw, answer.ResponseID, answer.TargetIDs)
		}
	case "chooseAttackers", "chooseBlockers":
		if len(answer.CardIDs) != 0 || len(answer.TargetIDs) != 0 {
			err = errors.New("combat response contains unexpected selections")
		} else {
			output, err = combatAssignmentsOutput(raw, answer.ResponseID, answer.Assignments)
		}
	case "chooseDamageAssignmentOrder":
		if answer.hasNonDamageOrderSelections() {
			err = errors.New("damage-order response contains unexpected selections")
		} else {
			output, err = damageOrderOutput(raw, answer.ResponseID, answer.DamageOrderIDs)
		}
	case "chooseCombatDamageAssignment":
		if answer.hasNonDamageAssignmentSelections() {
			err = errors.New("damage response contains unexpected selections")
		} else {
			output, err = combatDamageOutput(raw, answer.ResponseID, answer.DamageAssignments)
		}
	case "chooseBoolean", "chooseColor", "chooseFromSelection":
		if len(answer.CardIDs) != 0 || len(answer.TargetIDs) != 0 ||
			len(answer.Assignments) != 0 || answer.ChosenNumber != nil {
			err = errors.New("choice response contains unexpected selections")
		} else {
			output, err = scalarChoiceOutput(raw, answer.ResponseID, answer.ChoiceIDs)
		}
	case "chooseNumber":
		if len(answer.CardIDs) != 0 || len(answer.TargetIDs) != 0 ||
			len(answer.Assignments) != 0 || len(answer.ChoiceIDs) != 0 {
			err = errors.New("number response contains unexpected selections")
		} else {
			output, err = numberOutput(raw, answer.ResponseID, answer.ChosenNumber)
		}
	case "payManaCost":
		if !answer.emptySelections() {
			err = errors.New("mana response contains unexpected selections")
		} else {
			output, err = payManaOutput(raw, answer.ResponseID)
		}
	default:
		err = errors.New("unsupported prompt family")
	}
	if err != nil {
		return nil, err
	}
	response, err := json.Marshal(map[string]any{"type": view.Kind, "output": output})
	if err != nil {
		return nil, err
	}
	return response, nil
}

func (answer PromptResponse) emptySelections() bool {
	return len(answer.CardIDs) == 0 && len(answer.TargetIDs) == 0 &&
		len(answer.Assignments) == 0 && len(answer.ChoiceIDs) == 0 &&
		len(answer.OrderedIDs) == 0 && len(answer.ScryPiles) == 0 &&
		len(answer.DamageOrderIDs) == 0 && len(answer.DamageAssignments) == 0 &&
		answer.ChosenNumber == nil
}

func (answer PromptResponse) hasNonCardSelections() bool {
	return len(answer.TargetIDs) != 0 || len(answer.Assignments) != 0 ||
		len(answer.ChoiceIDs) != 0 || len(answer.OrderedIDs) != 0 ||
		len(answer.ScryPiles) != 0 || answer.ChosenNumber != nil
}

func (answer PromptResponse) hasNonDamageOrderSelections() bool {
	return len(answer.CardIDs) != 0 || len(answer.TargetIDs) != 0 ||
		len(answer.Assignments) != 0 || len(answer.ChoiceIDs) != 0 ||
		len(answer.OrderedIDs) != 0 || len(answer.ScryPiles) != 0 ||
		len(answer.DamageAssignments) != 0 || answer.ChosenNumber != nil
}

func (answer PromptResponse) hasNonDamageAssignmentSelections() bool {
	return len(answer.CardIDs) != 0 || len(answer.TargetIDs) != 0 ||
		len(answer.Assignments) != 0 || len(answer.ChoiceIDs) != 0 ||
		len(answer.OrderedIDs) != 0 || len(answer.ScryPiles) != 0 ||
		len(answer.DamageOrderIDs) != 0 || answer.ChosenNumber != nil
}

func (answer PromptResponse) hasNonOrderSelections() bool {
	return len(answer.CardIDs) != 0 || len(answer.TargetIDs) != 0 ||
		len(answer.Assignments) != 0 || len(answer.ChoiceIDs) != 0 ||
		len(answer.ScryPiles) != 0 || answer.ChosenNumber != nil
}

func (answer PromptResponse) hasNonScrySelections() bool {
	return len(answer.CardIDs) != 0 || len(answer.TargetIDs) != 0 ||
		len(answer.Assignments) != 0 || len(answer.ChoiceIDs) != 0 ||
		len(answer.OrderedIDs) != 0 || answer.ChosenNumber != nil
}

func decodePrompt(raw json.RawMessage) (promptEnvelope, promptInput, int, error) {
	if len(raw) == 0 || !json.Valid(raw) {
		return promptEnvelope{}, promptInput{}, 0, errors.New("Forge prompt is missing or invalid")
	}
	var envelope promptEnvelope
	if err := json.Unmarshal(raw, &envelope); err != nil {
		return promptEnvelope{}, promptInput{}, 0, err
	}
	if envelope.PromptID <= 0 || len(envelope.Input) == 0 {
		return promptEnvelope{}, promptInput{}, 0, errors.New("Forge prompt has an invalid id or input")
	}
	playerIndex, err := PlayerIndexFromID(envelope.DecidingPlayer)
	if err != nil {
		return promptEnvelope{}, promptInput{}, 0, err
	}
	var input promptInput
	if err := json.Unmarshal(envelope.Input, &input); err != nil || strings.TrimSpace(input.Type) == "" {
		return promptEnvelope{}, promptInput{}, 0, errors.New("Forge prompt has an invalid input family")
	}
	return envelope, input, playerIndex, nil
}

func normalizeActions(actions []promptAction) ([]PromptOption, error) {
	if len(actions) > maxPromptOptions {
		return nil, errors.New("Forge prompt has too many actions")
	}
	result := make([]PromptOption, 0, len(actions))
	for index, action := range actions {
		if strings.TrimSpace(action.ID) == "" {
			return nil, errors.New("Forge prompt action is missing an id")
		}
		label := firstPromptText(action.Label, action.ModeLabel, action.Description)
		if label == "" {
			switch action.Type {
			case "cast":
				label = "Cast card"
			case "activateAbility":
				label = "Activate ability"
			case "undoMana":
				label = "Undo mana payment"
			default:
				label = "Choose action"
			}
		}
		result = append(result, PromptOption{
			ResponseID: "action:" + strconv.Itoa(index), Kind: boundedPromptText(action.Type),
			Label: label, CardID: boundedPromptText(action.CardID),
		})
	}
	return result, nil
}

func chooseActionOutput(raw json.RawMessage, responseID string) (any, error) {
	switch responseID {
	case "$pass":
		return map[string]any{"type": "pass", "exhaustStack": false}, nil
	case "$pass-stack":
		return map[string]any{"type": "pass", "exhaustStack": true}, nil
	default:
		actionID, err := upstreamActionID(raw, responseID)
		if err != nil {
			return nil, err
		}
		return map[string]any{"type": "act", "actionId": actionID}, nil
	}
}

func payManaOutput(raw json.RawMessage, responseID string) (any, error) {
	switch responseID {
	case "$pay":
		_, input, _, err := decodePrompt(raw)
		if err != nil || !input.CanConfirmFromPool {
			return nil, errors.New("mana payment cannot be confirmed from the pool")
		}
		return map[string]any{"type": "pay", "auto": false}, nil
	case "$auto-pay":
		return map[string]any{"type": "pay", "auto": true}, nil
	case "$cancel":
		return map[string]any{"type": "cancel"}, nil
	default:
		actionID, err := upstreamActionID(raw, responseID)
		if err != nil {
			return nil, err
		}
		return map[string]any{"type": "act", "actionId": actionID}, nil
	}
}

func upstreamActionID(raw json.RawMessage, responseID string) (string, error) {
	if !strings.HasPrefix(responseID, "action:") {
		return "", errors.New("unknown prompt response")
	}
	index, err := strconv.Atoi(strings.TrimPrefix(responseID, "action:"))
	if err != nil {
		return "", errors.New("invalid prompt action response")
	}
	_, input, _, err := decodePrompt(raw)
	if err != nil || index < 0 || index >= len(input.Actions) || input.Actions[index].ID == "" {
		return "", errors.New("prompt action is no longer available")
	}
	return input.Actions[index].ID, nil
}

func firstPromptText(values ...string) string {
	for _, value := range values {
		if trimmed := boundedPromptText(value); trimmed != "" {
			return trimmed
		}
	}
	return ""
}

func boundedPromptText(value string) string {
	value = strings.TrimSpace(value)
	runes := []rune(value)
	if len(runes) <= maxPromptText {
		return value
	}
	return string(runes[:maxPromptText])
}
