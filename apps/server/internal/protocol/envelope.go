// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package protocol

import "encoding/json"

// Stable wire constants are generated from protocol/v1/wire-schema.json in
// wire_constants_generated.go. Keep operational limits and derived aliases
// here so protocol behavior remains close to the types that consume it.

// Operational input limits keep a single client from forcing unbounded room
// state or game setup work. They are transport safeguards, not MTG deck-building
// rules; the manual-tabletop product deliberately does not enforce format
// legality.
const (
	MaxDisplayNameRunes     = 64
	MaxRoomNameRunes        = 128
	MaxPasswordBytes        = 72 // bcrypt's effective input limit
	MinMainboardCards       = 7  // enough to produce the opening hand
	MaxDeckCards            = 1000
	MaxDeckEntries          = 500
	MaxDeckNameRunes        = 128
	MaxCardNameRunes        = 256
	MaxCommanders           = 2
	MaxSetCodeRunes         = 16
	MaxCollectorNumberRunes = 32
	MaxTypeLineRunes        = 256
	MaxGameSayRunes         = 500
	MaxTokenNameRunes       = 256
	MaxTokensPerSeat        = 256
	MaxResumeTokenBytes     = 128
	MaxDiceSides            = 1000
	MaxDiceCount            = 20
	MaxRandomCardCandidates = 100
	MaxCombatArrowSources   = 100
	MaxRetainedGameLog      = 10000
	MaxProjectedGameLog     = 500
	MaxLimitedProductCards  = 5000
	MaxLimitedProductSheets = 64
	MaxLimitedVariants      = 64
	MaxLimitedSlots         = 64
)

// Player counter identifiers are stable wire names. Life remains separate from
// the seven customizable slots in both state and UI.
const (
	PlayerCounterSlotCount     = 7
	MaxPlayerCounterLabelRunes = 24
	MinPlayerCounterValue      = -1 << 31
	MaxPlayerCounterValue      = 1<<31 - 1
	MaxCardFaceNameRunes       = 200
)

const (
	CardCounterKindNumber    = "number"
	CardCounterKindAbility   = "ability"
	CardNumberCounterID      = "number"
	MaxCardCounterLabelRunes = 24
	MaxCardAbilityCounters   = 32
)

const (
	LibraryPlacementTop    = "top"
	LibraryPlacementIndex  = "index"
	LibraryPlacementBottom = "bottom"
)

// Library search destinations are deliberately narrower than generic move
// zones. Library order remains private and can only be changed through the
// dedicated search command.
const (
	LibraryDestinationHand        = ZoneHand
	LibraryDestinationBattlefield = ZoneBattlefield
	LibraryDestinationGraveyard   = ZoneGraveyard
	LibraryDestinationExile       = ZoneExile
)

// ValidGamePhase reports whether phase is one of the locked 11 phase-bar
// identifiers.
func ValidGamePhase(phase string) bool {
	switch phase {
	case GamePhaseUntap,
		GamePhaseUpkeep,
		GamePhaseDraw,
		GamePhaseFirstMain,
		GamePhaseBeginningCombat,
		GamePhaseDeclareAttackers,
		GamePhaseDeclareBlockers,
		GamePhaseCombatDamage,
		GamePhaseEndCombat,
		GamePhaseSecondMain,
		GamePhaseEnd:
		return true
	default:
		return false
	}
}

// ValidResponseStatus reports whether status is a supported explicit table
// coordination signal. Clear is a command value and is not stored in snapshots.
func ValidResponseStatus(status string) bool {
	return status == ResponseStatusPass || status == ResponseStatusHold ||
		status == ResponseStatusClear
}

// FormatMaxSeats returns the seat cap for a format. Generic 1v1 and Duel
// Commander use two seats; multiplayer Commander uses four.
// Unknown formats return 0 (rejected by callers).
func FormatMaxSeats(format string) int {
	switch format {
	case FormatModern, FormatDuel:
		return 2
	case FormatEDH:
		return 4
	default:
		return 0
	}
}

// IsCommanderFormat reports whether a format uses command zones, commanders,
// and the manual commander-tax counter.
func IsCommanderFormat(format string) bool {
	return format == FormatDuel || format == FormatEDH
}

// IsTwoPlayerFormat reports whether a format uses the ordinary two-player
// match result and departure flow.
func IsTwoPlayerFormat(format string) bool {
	return format == FormatModern || format == FormatDuel
}

// ValidDeckFormat reports whether format is a supported deck-construction
// policy. This is deliberately separate from the three tabletop modes above.
func ValidDeckFormat(format string) bool {
	switch format {
	case DeckFormatCustom, DeckFormatStandard, DeckFormatPioneer, DeckFormatModern,
		DeckFormatLegacy, DeckFormatVintage, DeckFormatPauper, DeckFormatDuel,
		DeckFormatCommander, DeckFormatLimited:
		return true
	default:
		return false
	}
}

// TableModeForDeckFormat maps a construction policy onto table behavior.
func TableModeForDeckFormat(format string) string {
	switch format {
	case DeckFormatDuel:
		return FormatDuel
	case DeckFormatCommander:
		return FormatEDH
	case DeckFormatCustom, DeckFormatStandard, DeckFormatPioneer, DeckFormatModern,
		DeckFormatLegacy, DeckFormatVintage, DeckFormatPauper, DeckFormatLimited:
		return FormatModern
	default:
		return ""
	}
}

// DefaultDeckFormatForTableMode safely migrates legacy values that predate the
// separate deckFormat field. Generic 1v1 cannot be inferred as Modern.
func DefaultDeckFormatForTableMode(format string) string {
	switch format {
	case FormatModern:
		return DeckFormatCustom
	case FormatDuel:
		return DeckFormatDuel
	case FormatEDH:
		return DeckFormatCommander
	default:
		return ""
	}
}

// Sideboard phase constants.
const (
	SideboardEndReady   = "ready"
	SideboardEndTimeout = "timeout"
)

// Public game-result reasons. These values describe why the current game
// ended; later phases may add additional reasons without changing the result
// projection shape.
const (
	GameResultConcede   = "concede"
	GameResultDeparture = "departure"
	GameResultDraw      = "draw"
	GameResultRules     = "rules_engine"
)

// Random selection kinds.
const (
	RandomSelectionPlayer = "player"
	RandomSelectionCard   = "card"
)

// MaxSpectators is the per-room spectator cap (product lock).
const MaxSpectators = 8

// Envelope is the top-level wire object. One per WebSocket message.
// There is NO top-level `v` field by design (see package docs).
type Envelope struct {
	Type string `json:"type"`
	ID   string `json:"id,omitempty"`
	// Seq is a per-room, 1-based monotonic sequence carried on server->client
	// room.snapshot / room.event. Encoded via MarshalJSON so a legitimate
	// value is always emitted when set; absent when SeqPtr is nil.
	SeqPtr  *int64          `json:"-"`
	Payload json.RawMessage `json:"payload,omitempty"`
}

// HasSeq reports whether the envelope carries a seq.
func (e Envelope) HasSeq() bool { return e.SeqPtr != nil }

// SeqValue returns the seq value (0 if absent).
func (e Envelope) SeqValue() int64 {
	if e.SeqPtr == nil {
		return 0
	}
	return *e.SeqPtr
}

// WithSeq sets a seq value on the envelope (builder helper).
func (e Envelope) WithSeq(seq int64) Envelope {
	e.SeqPtr = &seq
	return e
}

// MarshalJSON implements custom marshaling so seq is emitted only when set,
// using an explicit pointer rather than omitempty (which would drop a legit 0).
func (e Envelope) MarshalJSON() ([]byte, error) {
	type alias struct {
		Type    string          `json:"type"`
		ID      string          `json:"id,omitempty"`
		Seq     *int64          `json:"seq,omitempty"`
		Payload json.RawMessage `json:"payload,omitempty"`
	}
	return json.Marshal(alias{
		Type:    e.Type,
		ID:      e.ID,
		Seq:     e.SeqPtr,
		Payload: e.Payload,
	})
}

// UnmarshalJSON decodes into Envelope, populating SeqPtr when seq is present.
func (e *Envelope) UnmarshalJSON(data []byte) error {
	type alias struct {
		Type    string          `json:"type"`
		ID      string          `json:"id,omitempty"`
		Seq     *int64          `json:"seq,omitempty"`
		Payload json.RawMessage `json:"payload,omitempty"`
	}
	var a alias
	if err := json.Unmarshal(data, &a); err != nil {
		return err
	}
	e.Type = a.Type
	e.ID = a.ID
	e.SeqPtr = a.Seq
	e.Payload = a.Payload
	return nil
}
