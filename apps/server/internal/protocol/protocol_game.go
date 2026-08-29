// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package protocol

// GameDraw requests one or more cards from the acting player's library.
// An omitted count preserves the original one-card command semantics.
type GameDraw struct {
	Count *int `json:"count,omitempty"`
}

// GameDrawn acknowledges a draw without echoing the private card identity.
type GameDrawn struct {
	RoomID string `json:"roomId"`
	Seat   int    `json:"seat"`
	Count  int    `json:"count"`
}

// GameShuffleLibrary randomizes the acting player's hidden library without
// revealing any card identity or resulting order.
type GameShuffleLibrary struct{}

type GameLibraryShuffled struct {
	RoomID string `json:"roomId"`
	Seat   int    `json:"seat"`
}

// GameMulligan requests a manual mulligan back to seven cards.
type GameMulligan struct{}

// GameMulliganed acknowledges the resulting hand size and public mulligan count
// without exposing any card identity.
type GameMulliganed struct {
	RoomID        string `json:"roomId"`
	Seat          int    `json:"seat"`
	HandSize      int    `json:"handSize"`
	MulliganCount int    `json:"mulliganCount"`
}

// GameDiscardHand discards either one server-random card or the acting
// player's complete hand into the cards' owner graveyards.
type GameDiscardHand struct {
	All bool `json:"all,omitempty"`
}

// GameHandDiscarded acknowledges the public zone transition without echoing
// any card identity in the correlated response.
type GameHandDiscarded struct {
	RoomID string `json:"roomId"`
	Seat   int    `json:"seat"`
	Count  int    `json:"count"`
}

// GameMoveCard requests an authoritative manual move. FromSeat may identify a
// public graveyard or exile owned by another seat; it is invalid for hidden or
// shared sources, and a remote public source requires that player to approve
// the exact retained request. A library source means the acting player's top
// card and does not require exposing its id before the move. ToSeat selects a
// battlefield, graveyard, or exile destination; it is invalid for hidden/shared
// destinations. LibraryPlacement defaults to top. Index is a zero-based
// insertion position and is required only for the "index" placement.
type GameMoveCard struct {
	CardID           string        `json:"cardId"`
	FromZone         string        `json:"fromZone"`
	FromSeat         *int          `json:"fromSeat,omitempty"`
	ToZone           string        `json:"toZone"`
	ToSeat           *int          `json:"toSeat,omitempty"`
	Position         *CardPosition `json:"position,omitempty"`
	LibraryPlacement string        `json:"libraryPlacement,omitempty"`
	LibraryIndex     *int          `json:"libraryIndex,omitempty"`
	FaceName         string        `json:"faceName,omitempty"`
	FaceDown         bool          `json:"faceDown,omitempty"`
}

// GameCardMoved acknowledges a move without duplicating the card name or
// printing identity. Public identity and battlefield coordinates arrive in
// the following role-specific game.snapshot.
type GameCardMoved struct {
	RoomID   string        `json:"roomId"`
	Seat     int           `json:"seat"`
	CardID   string        `json:"cardId"`
	FromZone string        `json:"fromZone"`
	FromSeat int           `json:"fromSeat"`
	ToZone   string        `json:"toZone"`
	ToSeat   int           `json:"toSeat"`
	Position *CardPosition `json:"position,omitempty"`
	Removed  bool          `json:"removed,omitempty"`
}

// GamePublicZoneMovePending acknowledges that an exact move request is waiting
// for the player who owns the source graveyard or exile to decide.
type GamePublicZoneMovePending struct {
	RoomID     string `json:"roomId"`
	ApprovalID string `json:"approvalId"`
	TargetSeat int    `json:"targetSeat"`
}

// GamePublicZoneMoveRequested asks the source-zone player to approve one exact
// public-zone mutation. Card identities remain in the retained server request.
type GamePublicZoneMoveRequested struct {
	RoomID        string `json:"roomId"`
	ApprovalID    string `json:"approvalId"`
	RequesterSeat int    `json:"requesterSeat"`
	RequesterName string `json:"requesterName"`
	SourceZone    string `json:"sourceZone"`
	CardCount     int    `json:"cardCount"`
	ToZone        string `json:"toZone"`
}

// GameRespondPublicZoneMove accepts or rejects one retained move request.
type GameRespondPublicZoneMove struct {
	ApprovalID string `json:"approvalId"`
	Approved   bool   `json:"approved"`
}

// GamePublicZoneMoveResponded acknowledges the source-zone player's decision.
type GamePublicZoneMoveResponded struct {
	RoomID     string `json:"roomId"`
	ApprovalID string `json:"approvalId"`
	Approved   bool   `json:"approved"`
}

// GameArrangeBattlefield atomically replaces the normalized positions of the
// acting player's current battlefield permanents without changing card state.
type GameArrangeBattlefield struct {
	Cards []BattlefieldCardPosition `json:"cards"`
}

// GameBattlefieldArranged acknowledges one atomic battlefield layout update.
type GameBattlefieldArranged struct {
	RoomID string `json:"roomId"`
	Seat   int    `json:"seat"`
	Count  int    `json:"count"`
}

// GameSetTapped toggles a permanent controlled by the acting seat. Tapping is
// manual tabletop state and does not trigger rules actions.
type GameSetTapped struct {
	CardID string `json:"cardId"`
	Tapped bool   `json:"tapped"`
}

// GameTappedSet acknowledges the public tapped state. The following snapshot
// remains authoritative for rendering.
type GameTappedSet struct {
	RoomID string `json:"roomId"`
	Seat   int    `json:"seat"`
	CardID string `json:"cardId"`
	Tapped bool   `json:"tapped"`
}

// GameSetCardFace selects the visible face of a battlefield card. An empty
// FaceName selects the front face.
type GameSetCardFace struct {
	CardID   string `json:"cardId"`
	FaceName string `json:"faceName,omitempty"`
}

type GameCardFaceSet struct {
	RoomID   string `json:"roomId"`
	Seat     int    `json:"seat"`
	CardID   string `json:"cardId"`
	FaceName string `json:"faceName,omitempty"`
}

// GameSetFaceDown toggles persistent hidden identity for one battlefield card.
// Only its owner or current battlefield controller may issue the command.
type GameSetFaceDown struct {
	CardID   string `json:"cardId"`
	FaceDown bool   `json:"faceDown"`
}

// GameFaceDownSet acknowledges the state change without echoing card identity.
type GameFaceDownSet struct {
	RoomID   string `json:"roomId"`
	Seat     int    `json:"seat"`
	CardID   string `json:"cardId"`
	FaceDown bool   `json:"faceDown"`
}

// GameSetCardCounter creates, changes, or removes a public counter on a
// permanent controlled by the acting player. Exactly one of Value or Delta is
// required. A missing CounterID creates an ability counter; number counters
// always use the stable "number" id. Setting a counter to zero removes it.
type GameSetCardCounter struct {
	CardID    string `json:"cardId"`
	CounterID string `json:"counterId,omitempty"`
	Kind      string `json:"kind"`
	Label     string `json:"label,omitempty"`
	Value     *int   `json:"value,omitempty"`
	Delta     *int   `json:"delta,omitempty"`
}

type GameCardCounterSet struct {
	RoomID  string          `json:"roomId"`
	Seat    int             `json:"seat"`
	CardID  string          `json:"cardId"`
	Counter GameCardCounter `json:"counter"`
	Removed bool            `json:"removed,omitempty"`
}

// GameSetPhase changes the shared phase marker. Only the active player may
// issue it; it never triggers automatic rules actions.
type GameSetPhase struct {
	Phase string `json:"phase"`
}

// GamePhaseSet acknowledges a phase change. The following game.snapshot is
// the authoritative shared projection.
type GamePhaseSet struct {
	RoomID string `json:"roomId"`
	Seat   int    `json:"seat"`
	Phase  string `json:"phase"`
}

// GameSetResponseStatus publishes a lightweight, rules-neutral coordination
// signal for the acting seat. Signals reset whenever the phase or turn changes.
type GameSetResponseStatus struct {
	Status string `json:"status"`
}

type GameResponseStatusSet struct {
	RoomID string `json:"roomId"`
	Seat   int    `json:"seat"`
	Status string `json:"status"`
}

// GameNextTurn advances active-player coordination to the next seat.
type GameNextTurn struct{}

// GameTurnAdvanced acknowledges the new active seat and the phase reset to
// untap. The following game.snapshot remains authoritative.
type GameTurnAdvanced struct {
	RoomID       string `json:"roomId"`
	ActiveSeat   int    `json:"activeSeat"`
	CurrentPhase string `json:"currentPhase"`
}

// GameReveal publishes cards from the acting player's private hand into the
// shared reveal area. An empty CardIDs list means the entire hand.
type GameReveal struct {
	Zone    string   `json:"zone"`
	CardIDs []string `json:"cardIds,omitempty"`
}

// GameRevealed acknowledges an explicit reveal without duplicating identities;
// the following public game.snapshot carries the revealed cards.
type GameRevealed struct {
	RoomID string `json:"roomId"`
	Seat   int    `json:"seat"`
	Zone   string `json:"zone"`
	Count  int    `json:"count"`
}

// GameRecallRevealed returns every card the acting player owns in the shared
// reveal area to that player's hidden hand.
type GameRecallRevealed struct{}

type GameRevealedRecalled struct {
	RoomID string `json:"roomId"`
	Seat   int    `json:"seat"`
	Count  int    `json:"count"`
}

// GameMoveCards applies one atomic batch move from a public battlefield,
// graveyard, or exile. Public-zone batches carry explicit source/destination
// seats; battlefield destinations use Position as their layout anchor.
// A remote graveyard or exile source requires the same exact-request approval
// as a single public-zone move.
type GameMoveCards struct {
	CardIDs          []string      `json:"cardIds"`
	FromZone         string        `json:"fromZone"`
	FromSeat         *int          `json:"fromSeat,omitempty"`
	ToZone           string        `json:"toZone"`
	ToSeat           *int          `json:"toSeat,omitempty"`
	Position         *CardPosition `json:"position,omitempty"`
	LibraryPlacement string        `json:"libraryPlacement,omitempty"`
	Randomize        bool          `json:"randomize,omitempty"`
}

type GameCardsMoved struct {
	RoomID string `json:"roomId"`
	Seat   int    `json:"seat"`
	Count  int    `json:"count"`
	ToZone string `json:"toZone"`
}

// GameMoveLibraryCards moves a count-limited prefix from the acting player's
// hidden library to one public zone without revealing identities in the
// command or acknowledgement.
type GameMoveLibraryCards struct {
	Count  int    `json:"count"`
	ToZone string `json:"toZone"`
}

type GameLibraryCardsMoved struct {
	RoomID string `json:"roomId"`
	Seat   int    `json:"seat"`
	Count  int    `json:"count"`
	ToZone string `json:"toZone"`
}

// GameDumpZone requests a private view of one hidden zone. The acting player's
// own library is returned immediately; another player's library requires that
// seat's explicit approval. TopCount limits the private view to the current
// prefix while leaving zero as the full-library search view.
type GameDumpZone struct {
	Zone     string `json:"zone"`
	Seat     *int   `json:"seat,omitempty"`
	TopCount int    `json:"topCount,omitempty"`
}

// GameZoneDumpPending acknowledges that a private library request is waiting
// for the target seat's decision.
type GameZoneDumpPending struct {
	RoomID     string `json:"roomId"`
	ApprovalID string `json:"approvalId"`
	TargetSeat int    `json:"targetSeat"`
}

// GameZoneDumpRequested is sent only to the target player whose library would
// be disclosed.
type GameZoneDumpRequested struct {
	RoomID        string `json:"roomId"`
	ApprovalID    string `json:"approvalId"`
	RequesterSeat int    `json:"requesterSeat"`
	RequesterName string `json:"requesterName"`
	Zone          string `json:"zone"`
	TopCount      int    `json:"topCount,omitempty"`
}

// GameRespondZoneDump accepts or rejects one pending private-library request.
type GameRespondZoneDump struct {
	ApprovalID string `json:"approvalId"`
	Approved   bool   `json:"approved"`
}

// GameZoneDumpResponded acknowledges the target player's decision without
// containing any hidden card identities.
type GameZoneDumpResponded struct {
	RoomID     string `json:"roomId"`
	ApprovalID string `json:"approvalId"`
	Approved   bool   `json:"approved"`
}

// GameZoneDumped is sent only to the requesting player. It must never be
// included in room fan-out because Cards contains the full private library.
type GameZoneDumped struct {
	RoomID     string     `json:"roomId"`
	Zone       string     `json:"zone"`
	SourceSeat int        `json:"sourceSeat"`
	ApprovalID string     `json:"approvalId,omitempty"`
	TopCount   int        `json:"topCount,omitempty"`
	Cards      []GameCard `json:"cards"`
}

// GameSearchLibrary moves selected cards from a private library. A remote
// source seat requires the one-use approval id issued with game.zone_dumped.
// ToSeat may choose the requester or source player's hand/battlefield/public
// zones for an approved remote search. Position is a normalized anchor used
// to lay out one or more battlefield cards.
type GameSearchLibrary struct {
	CardID     string        `json:"cardId,omitempty"`
	CardIDs    []string      `json:"cardIds,omitempty"`
	ToZone     string        `json:"toZone"`
	ToSeat     *int          `json:"toSeat,omitempty"`
	Reveal     bool          `json:"reveal"`
	Randomize  bool          `json:"randomize,omitempty"`
	Position   *CardPosition `json:"position,omitempty"`
	SourceSeat *int          `json:"sourceSeat,omitempty"`
	ApprovalID string        `json:"approvalId,omitempty"`
	FaceDown   bool          `json:"faceDown,omitempty"`
}

// GameLibrarySearched acknowledges the authoritative mutation without
// repeating the selected private card identity.
type GameLibrarySearched struct {
	RoomID     string `json:"roomId"`
	Seat       int    `json:"seat"`
	SourceSeat int    `json:"sourceSeat"`
	ToSeat     int    `json:"toSeat"`
	ToZone     string `json:"toZone"`
	Revealed   bool   `json:"revealed"`
	Count      int    `json:"count"`
}

// GameReorderLibrary replaces the current top prefix with the same card ids in
// a player-selected order. It never reveals identities in the acknowledgement
// or public log.
type GameReorderLibrary struct {
	CardIDs []string `json:"cardIds"`
}

type GameLibraryReordered struct {
	RoomID string `json:"roomId"`
	Seat   int    `json:"seat"`
	Count  int    `json:"count"`
}

// LibraryViewAssignment gives one viewed card its destination. Hand and
// battlefield mean the acting player's zones; graveyard, exile, and both
// library ends mean the source player's zones. FaceDown is valid only for the
// battlefield.
type LibraryViewAssignment struct {
	CardID   string `json:"cardId"`
	ToZone   string `json:"toZone"`
	FaceDown bool   `json:"faceDown,omitempty"`
}

// GameResolveLibraryView atomically resolves the currently viewed top prefix.
// New clients submit one Assignment for every viewed card. The legacy
// selected/remainder representation remains accepted for protocol-compatible
// clients. A remote source requires the one-use approval id issued with the
// private dump.
type GameResolveLibraryView struct {
	Assignments        []LibraryViewAssignment `json:"assignments,omitempty"`
	SelectedCardIDs    []string                `json:"selectedCardIds,omitempty"`
	RemainderCardIDs   []string                `json:"remainderCardIds"`
	ToZone             string                  `json:"toZone,omitempty"`
	Position           *CardPosition           `json:"position,omitempty"`
	FaceDown           bool                    `json:"faceDown,omitempty"`
	SourceSeat         *int                    `json:"sourceSeat,omitempty"`
	ApprovalID         string                  `json:"approvalId,omitempty"`
	RemainderPlacement string                  `json:"remainderPlacement"`
	RandomizeRemainder bool                    `json:"randomizeRemainder,omitempty"`
	RandomizeTop       bool                    `json:"randomizeTop,omitempty"`
	RandomizeBottom    bool                    `json:"randomizeBottom,omitempty"`
}

type GameLibraryViewResolved struct {
	RoomID         string `json:"roomId"`
	Seat           int    `json:"seat"`
	MovedCount     int    `json:"movedCount"`
	RemainderCount int    `json:"remainderCount"`
}

// GameSetCounter changes one of the acting player's public counters. Exactly
// one of Value, Delta, or Label must be present. Life accepts only Value; the
// seven customizable slots accept an exact Value, a +/-1 Delta, or a Label.
type GameSetCounter struct {
	Counter string  `json:"counter"`
	Value   *int    `json:"value,omitempty"`
	Delta   *int    `json:"delta,omitempty"`
	Label   *string `json:"label,omitempty"`
}

// GameCounterSet acknowledges the public counter mutation. The following
// game.snapshot remains authoritative for every viewer.
type GameCounterSet struct {
	RoomID  string `json:"roomId"`
	Seat    int    `json:"seat"`
	Counter string `json:"counter"`
	Value   int    `json:"value"`
	Label   string `json:"label,omitempty"`
}

// GameSetCounterCount changes how many of the acting player's public counter
// slots are shown by every client.
type GameSetCounterCount struct {
	Count int `json:"count"`
}

// GameCounterCountSet acknowledges the acting seat's public display choice.
// The following game.snapshot remains authoritative for every viewer.
type GameCounterCountSet struct {
	RoomID string `json:"roomId"`
	Seat   int    `json:"seat"`
	Count  int    `json:"count"`
}

// GameConcede requests that the acting seated player concede the current game.
type GameConcede struct{}

// GameConceded acknowledges the immutable game result. The following
// game.snapshot is the authoritative projection for every room member.
type GameConceded struct {
	RoomID        string `json:"roomId"`
	GameNumber    int    `json:"gameNumber"`
	ConcededSeat  int    `json:"concededSeat"`
	WinnerSeat    int    `json:"winnerSeat"`
	Score         []int  `json:"score"`
	MatchFinished bool   `json:"matchFinished"`
}

// GameDeclareDraw requests a no-winner result for the current game.
type GameDeclareDraw struct{}

// GameDrawDeclared acknowledges the immutable draw result.
type GameDrawDeclared struct {
	RoomID        string `json:"roomId"`
	GameNumber    int    `json:"gameNumber"`
	DeclaredSeat  int    `json:"declaredSeat"`
	Score         []int  `json:"score"`
	DrawnGames    int    `json:"drawnGames,omitempty"`
	MatchFinished bool   `json:"matchFinished"`
}

// GameRestart requests that the host rebuild the current game from committed
// registered decks without changing match score or the starting seat.
type GameRestart struct{}

type GameRestarted struct {
	RoomID       string `json:"roomId"`
	GameNumber   int    `json:"gameNumber"`
	StartingSeat int    `json:"startingSeat"`
}

// GameRoll requests public server-generated dice.
type GameRoll struct {
	Sides int `json:"sides"`
	Count int `json:"count,omitempty"`
}

type GameRolled struct {
	RoomID string `json:"roomId"`
	Seat   int    `json:"seat"`
	Sides  int    `json:"sides"`
	Rolls  []int  `json:"rolls"`
	Total  int    `json:"total"`
}

type GameFlipCoin struct{}

type GameCoinFlipped struct {
	RoomID string `json:"roomId"`
	Seat   int    `json:"seat"`
	Result string `json:"result"`
}

// GameRandomSelect chooses either an active player or one of an explicit set
// of public battlefield card ids.
type GameRandomSelect struct {
	Kind    string   `json:"kind"`
	CardIDs []string `json:"cardIds,omitempty"`
}

type GameRandomSelected struct {
	RoomID         string `json:"roomId"`
	Seat           int    `json:"seat"`
	Kind           string `json:"kind"`
	SelectedSeat   int    `json:"selectedSeat"`
	SelectedCardID string `json:"selectedCardId,omitempty"`
}

// GameReturnToRoom ends post-match review for every room member and restores
// the waiting-room ready flow. It is valid only after the match is complete.
type GameReturnToRoom struct{}

type GameReturnedToRoom struct {
	RoomID string `json:"roomId"`
}

// GameSay appends one explicitly public message to the shared game log.
type GameSay struct {
	Message string `json:"message"`
}

// GameSaid acknowledges the server-assigned public log entry. The following
// game.snapshot carries the authoritative sender name and message.
type GameSaid struct {
	RoomID string `json:"roomId"`
	LogID  int64  `json:"logId"`
}

// GameCreateToken creates one public, battlefield-only token using an English
// token-catalog printing selected by the client. The server validates bounded
// identity fields and remains authoritative for the instance id and position.
type GameCreateToken struct {
	Name            string        `json:"name"`
	SetCode         string        `json:"setCode"`
	CollectorNumber string        `json:"collectorNumber"`
	TypeLine        string        `json:"typeLine,omitempty"`
	Position        *CardPosition `json:"position"`
}

// GameTokenCreated acknowledges creation without duplicating the full public
// identity carried by the following role-specific game.snapshot.
type GameTokenCreated struct {
	RoomID string `json:"roomId"`
	Seat   int    `json:"seat"`
	CardID string `json:"cardId"`
}

// GameAdjustCommanderTax applies a manual +/-1 adjustment to the acting EDH
// player's dedicated commander-tax control.
type GameAdjustCommanderTax struct {
	CommanderID string `json:"commanderId"`
	Delta       int    `json:"delta"`
}

// GameCommanderTaxAdjusted acknowledges the public EDH tax value.
type GameCommanderTaxAdjusted struct {
	RoomID      string `json:"roomId"`
	Seat        int    `json:"seat"`
	CommanderID string `json:"commanderId"`
	Value       int    `json:"value"`
}

// GameCastCommander explicitly casts one owned commander from the command
// zone. It is distinct from a manual move so commander tax can be updated in
// the same authoritative operation.
type GameCastCommander struct {
	CommanderID string `json:"commanderId"`
}

// GameCommanderCast acknowledges the public command-zone-to-stack move and
// the resulting per-commander tax value.
type GameCommanderCast struct {
	RoomID      string `json:"roomId"`
	Seat        int    `json:"seat"`
	CommanderID string `json:"commanderId"`
	Tax         int    `json:"tax"`
}

// GameSetCommanderDamage changes one public commander-damage total. Exactly
// one of Value or Delta must be present. ApplyToLife is valid only for a
// positive delta and makes the life/damage update one reducer transaction.
type GameSetCommanderDamage struct {
	CommanderID string `json:"commanderId"`
	TargetSeat  int    `json:"targetSeat"`
	Value       *int   `json:"value,omitempty"`
	Delta       *int   `json:"delta,omitempty"`
	ApplyToLife bool   `json:"applyToLife,omitempty"`
}

// GameCommanderDamageSet acknowledges the authoritative public total and the
// target's resulting life total.
type GameCommanderDamageSet struct {
	RoomID        string `json:"roomId"`
	CommanderID   string `json:"commanderId"`
	TargetSeat    int    `json:"targetSeat"`
	Value         int    `json:"value"`
	TargetLife    int    `json:"targetLife"`
	AppliedToLife bool   `json:"appliedToLife"`
}

// GamePlayLand explicitly records a normal land play from the active player's
// hand. Printed type and ordinary timing remain advisory client checks.
type GamePlayLand struct {
	CardID   string        `json:"cardId"`
	Position *CardPosition `json:"position"`
	FaceName string        `json:"faceName,omitempty"`
}

// GameLandPlayed acknowledges the atomic public move and recorded count
// without echoing the former private hand-card name.
type GameLandPlayed struct {
	RoomID string `json:"roomId"`
	Seat   int    `json:"seat"`
	CardID string `json:"cardId"`
	Count  int    `json:"count"`
}

// GameSetLandPlayCount manually corrects the active turn's public recorded
// count. It does not move a card or claim to enforce a land-play allowance.
type GameSetLandPlayCount struct {
	Value int `json:"value"`
}

// GameLandPlayCountSet acknowledges the corrected public count.
type GameLandPlayCountSet struct {
	RoomID string `json:"roomId"`
	Seat   int    `json:"seat"`
	Value  int    `json:"value"`
}

type GameSetArrow struct {
	SourceCardIDs       []string `json:"sourceCardIds,omitempty"`
	TappedSourceCardIDs []string `json:"tappedSourceCardIds,omitempty"`
	Kind                string   `json:"kind,omitempty"`
	TargetCardID        string   `json:"targetCardId,omitempty"`
	TargetSeat          *int     `json:"targetSeat,omitempty"`
}

type GameArrowSet struct {
	RoomID        string   `json:"roomId"`
	Seat          int      `json:"seat"`
	SourceCardIDs []string `json:"sourceCardIds,omitempty"`
	Kind          string   `json:"kind,omitempty"`
	Clear         bool     `json:"clear,omitempty"`
}

type GameSetAttachment struct {
	SourceCardID string `json:"sourceCardId"`
	TargetCardID string `json:"targetCardId,omitempty"`
}

type GameAttachmentSet struct {
	RoomID       string `json:"roomId"`
	OwnerSeat    int    `json:"ownerSeat"`
	SourceCardID string `json:"sourceCardId"`
	Detached     bool   `json:"detached,omitempty"`
}
