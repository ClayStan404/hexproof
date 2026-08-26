// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

// Package protocol defines the hexproof.v1 wire envelope and message types.
//
// Wire conventions:
//   - Protocol version `v` is negotiated ONCE at handshake. The authoritative
//     value lives ONLY in the session.welcome payload. Subsequent messages
//     carry NO top-level `v`.
//   - Client commands that need a reply include `id`; the server echoes the
//     same `id` on the matching success event or on `error`.
//   - Success types are events, not *.ok: room.create -> room.created.
//   - seq is per-room, 1-based, monotonic; emitted on room.snapshot and
//     game.snapshot. Absent means "no seq yet" (pre-join). seq of 0 is never
//     produced (P1 lock: start at 1). `room.event` is reserved and unused.
package protocol

import (
	"encoding/json"
	"fmt"
)

// SessionHello is the payload of session.hello (C->S). ClientVersion is
// required and must exactly match the server build. The client MAY offer a
// protocol string; the server's session.welcome is authoritative.
type SessionHello struct {
	DisplayName   string `json:"displayName"`
	ClientVersion string `json:"clientVersion"`
	Protocol      string `json:"protocol,omitempty"`
	ResumeToken   string `json:"resumeToken,omitempty"`
	LastSeq       int64  `json:"lastSeq,omitempty"`
}

// SessionWelcome is the payload of session.welcome (S->C). It is the ONLY
// message that authoritatively carries the protocol version `v`. ResumeToken
// is an opaque, client-private credential. A resumed welcome carries enough
// membership metadata for a restarted client to interpret the fresh room and
// role-specific game snapshots that immediately follow.
type SessionWelcome struct {
	V             string `json:"v"`
	ConnectionID  string `json:"connectionId"`
	ServerVersion string `json:"serverVersion"`
	ResumeToken   string `json:"resumeToken"`
	Resumed       bool   `json:"resumed,omitempty"`
	RoomID        string `json:"roomId,omitempty"`
	Role          string `json:"role,omitempty"`
	Seat          *int   `json:"seat,omitempty"`
	Host          bool   `json:"host,omitempty"`
}

// ErrorPayload is the payload of an `error` message.
type ErrorPayload struct {
	Code            string `json:"code"`
	Message         string `json:"message"`
	ClientVersion   string `json:"clientVersion,omitempty"`
	RequiredVersion string `json:"requiredVersion,omitempty"`
}

// RoomCreate is the payload of room.create (C->S).
type RoomCreate struct {
	Name               string `json:"name"`
	Format             string `json:"format"`
	DeckFormat         string `json:"deckFormat"`
	MaxSeats           int    `json:"maxSeats,omitempty"`
	Playtest           bool   `json:"playtest,omitempty"`
	AllowSpectators    bool   `json:"allowSpectators"`
	SpectatorsSeeHands bool   `json:"spectatorsSeeHands"`
	MatchMode          string `json:"matchMode"`
	CardLoadMode       string `json:"cardLoadMode,omitempty"`
	Password           string `json:"password,omitempty"`
}

// RoomCreated is the payload of room.created (S->C).
type RoomCreated struct {
	RoomID   string       `json:"roomId"`
	Settings RoomSettings `json:"settings"`
	HostSeat int          `json:"hostSeat"`
}

// RoomSettings is the room configuration shared in created/snapshot.
type RoomSettings struct {
	Name               string `json:"name"`
	Format             string `json:"format"`
	DeckFormat         string `json:"deckFormat"`
	MaxSeats           int    `json:"maxSeats"`
	Playtest           bool   `json:"playtest,omitempty"`
	AllowSpectators    bool   `json:"allowSpectators"`
	SpectatorsSeeHands bool   `json:"spectatorsSeeHands"`
	MatchMode          string `json:"matchMode"`
	CardLoadMode       string `json:"cardLoadMode"`
	HasPassword        bool   `json:"hasPassword"`
}

// RoomListEntry is the public, hub-local discovery projection. It never
// contains password material, member identities, deck selection, connection
// ids, or hidden game state.
type RoomListEntry struct {
	RoomID             string `json:"roomId"`
	Name               string `json:"name"`
	Format             string `json:"format"`
	DeckFormat         string `json:"deckFormat"`
	MatchMode          string `json:"matchMode"`
	CardLoadMode       string `json:"cardLoadMode"`
	MaxSeats           int    `json:"maxSeats"`
	PlayerCount        int    `json:"playerCount"`
	SpectatorCount     int    `json:"spectatorCount"`
	AllowSpectators    bool   `json:"allowSpectators"`
	SpectatorsSeeHands bool   `json:"spectatorsSeeHands"`
	HasPassword        bool   `json:"hasPassword"`
	Phase              string `json:"phase"`
	PlayerJoinable     bool   `json:"playerJoinable"`
	SpectatorJoinable  bool   `json:"spectatorJoinable"`
}

type RoomListed struct {
	Rooms []RoomListEntry `json:"rooms"`
}

// RoomJoin is the payload of room.join (C->S).
type RoomJoin struct {
	RoomID      string `json:"roomId"`
	AsSpectator bool   `json:"asSpectator"`
	Password    string `json:"password,omitempty"`
}

// RoomJoined is the payload of room.joined (S->C).
type RoomJoined struct {
	RoomID string `json:"roomId"`
	Role   string `json:"role"` // "player" | "spectator"
	Seat   *int   `json:"seat,omitempty"`
}

// DeckCard identifies one selected printing and its quantity. The server keeps
// this private deck data for later match setup; room projections never expose
// it to opponents or spectators. A completed tournament may publish the last
// deck registered in one of its private pairing rooms.
type DeckCard struct {
	Name            string `json:"name"`
	Count           int    `json:"count"`
	SetCode         string `json:"setCode"`
	CollectorNumber string `json:"collectorNumber"`
	TypeLine        string `json:"typeLine,omitempty"`
}

// DeckSelect is the payload of deck.select (C->S). It carries the complete
// local deck identity because Hexproof uses a trust-server model.
type DeckSelect struct {
	Name       string     `json:"name"`
	Format     string     `json:"format"`
	DeckFormat string     `json:"deckFormat"`
	Commander  string     `json:"commander,omitempty"`
	Commanders []string   `json:"commanders,omitempty"`
	Mainboard  []DeckCard `json:"mainboard"`
	Sideboard  []DeckCard `json:"sideboard"`
}

// DeckSelected acknowledges a stored deck selection without echoing hidden
// deck identities back onto the wire.
type DeckSelected struct {
	RoomID string `json:"roomId"`
	Seat   int    `json:"seat"`
}

// PlayerReady is the payload of player.ready (C->S).
type PlayerReady struct {
	Ready bool `json:"ready"`
}

// PlayerReadyChanged acknowledges the resulting ready state.
type PlayerReadyChanged struct {
	RoomID string `json:"roomId"`
	Seat   int    `json:"seat"`
	Ready  bool   `json:"ready"`
}

// CardKey is the minimum printing identity clients need to prefetch metadata
// and art before the match starts. Quantities and deck ownership are omitted.
type CardKey struct {
	Name            string `json:"name"`
	SetCode         string `json:"setCode"`
	CollectorNumber string `json:"collectorNumber"`
}

// MatchLoadRequired starts one pre-match asset load generation.
type MatchLoadRequired struct {
	LoadID   int64     `json:"loadId"`
	CardKeys []CardKey `json:"cardKeys"`
}

// ClientLoadComplete reports that one client finished a load generation.
type ClientLoadComplete struct {
	LoadID int64 `json:"loadId"`
}

// ClientLoadCompleted acknowledges a load completion report.
type ClientLoadCompleted struct {
	RoomID string `json:"roomId"`
	LoadID int64  `json:"loadId"`
}

// MatchStarted transitions all room members from loading to the table shell.
type MatchStarted struct {
	RoomID string `json:"roomId"`
	LoadID int64  `json:"loadId"`
}

// CardPosition is normalized to the battlefield bounds. Normalized
// coordinates keep the server-authoritative layout independent of viewport
// size and UI scale.
type CardPosition struct {
	X float64 `json:"x"`
	Y float64 `json:"y"`
}

// GameCard is a server-assigned card instance. Hidden-zone identities appear
// only in the owning player's projected game snapshot. OwnerSeat remains
// stable when a permanent is moved onto another seat's battlefield. Position
// is present only while the card is on the battlefield.
type GameCard struct {
	ID              string            `json:"id"`
	Name            string            `json:"name,omitempty"`
	SetCode         string            `json:"setCode,omitempty"`
	CollectorNumber string            `json:"collectorNumber,omitempty"`
	TypeLine        string            `json:"typeLine,omitempty"`
	OwnerSeat       int               `json:"ownerSeat"`
	Commander       bool              `json:"commander,omitempty"`
	FaceName        string            `json:"faceName,omitempty"`
	FaceDown        bool              `json:"faceDown,omitempty"`
	Position        *CardPosition     `json:"position,omitempty"`
	Token           bool              `json:"token,omitempty"`
	Tapped          bool              `json:"tapped,omitempty"`
	Counters        []GameCardCounter `json:"counters,omitempty"`
}

// GameCardCounter is public state attached to one battlefield permanent.
// The unnamed number counter uses the stable "number" id; ability counters
// have server-assigned ids and a user-supplied public label.
type GameCardCounter struct {
	ID    string `json:"id"`
	Kind  string `json:"kind"`
	Label string `json:"label,omitempty"`
	Value int    `json:"value"`
}

// BattlefieldCardPosition assigns one normalized position to an existing
// permanent during an atomic manual battlefield arrangement.
type BattlefieldCardPosition struct {
	CardID   string        `json:"cardId"`
	Position *CardPosition `json:"position"`
}

// GameSharedCard is a public card in the room-wide stack or reveal area.
type GameSharedCard struct {
	GameCard
}

// GamePlayerCounter is one of the seven public per-seat counter slots. Key is
// stable for the game; Label and Value may be changed only by that seat.
type GamePlayerCounter struct {
	Key   string `json:"key"`
	Label string `json:"label"`
	Value int    `json:"value"`
}

// GameSeatProjection contains public zone counts and identities plus an
// optional private hand. Hand is populated only for the owning viewer.
type GameSeatProjection struct {
	Seat           int                 `json:"seat"`
	DisplayName    string              `json:"displayName"`
	Life           int                 `json:"life"`
	Counters       []GamePlayerCounter `json:"counters,omitempty"`
	CounterCount   int                 `json:"counterCount,omitempty"`
	LibraryCount   int                 `json:"libraryCount"`
	HandCount      int                 `json:"handCount"`
	MulliganCount  int                 `json:"mulliganCount"`
	Hand           []GameCard          `json:"hand,omitempty"`
	SideboardCount int                 `json:"sideboardCount,omitempty"`
	Sideboard      []GameCard          `json:"sideboard,omitempty"`
	Battlefield    []GameCard          `json:"battlefield"`
	Graveyard      []GameCard          `json:"graveyard"`
	Exile          []GameCard          `json:"exile"`
	CommandZone    []GameCard          `json:"commandZone,omitempty"`
	CommanderTax   int                 `json:"commanderTax,omitempty"`
	CommanderTaxes map[string]int      `json:"commanderTaxes,omitempty"`
	Eliminated     bool                `json:"eliminated,omitempty"`
	ResponseStatus string              `json:"responseStatus,omitempty"`
}

// GameCommanderIdentity keeps each designated commander's public identity
// available even while the physical card is face down or controlled by
// another player. Commander status is public game information.
type GameCommanderIdentity struct {
	CardID    string `json:"cardId"`
	OwnerSeat int    `json:"ownerSeat"`
	Name      string `json:"name"`
}

// GameCommanderDamage is one public commander-to-player damage total. The
// source is the physical commander card rather than only its owner or name.
type GameCommanderDamage struct {
	CommanderID        string `json:"commanderId"`
	CommanderOwnerSeat int    `json:"commanderOwnerSeat"`
	TargetSeat         int    `json:"targetSeat"`
	Value              int    `json:"value"`
}

// GameLogEntry is public table history. Text must never contain hidden card
// identities unless a later explicit reveal action authorizes them.
type GameLogEntry struct {
	ID   int64  `json:"id"`
	Kind string `json:"kind"`
	Seat int    `json:"seat"`
	Text string `json:"text"`
}

// GameResult is the public, immutable outcome of one completed game.
type GameResult struct {
	Reason        string `json:"reason"`
	WinnerSeat    int    `json:"winnerSeat"`
	ConcededSeat  int    `json:"concededSeat"`
	MatchFinished bool   `json:"matchFinished"`
}

// GameSnapshot is projected independently for each room member. All members
// receive identical public counts/logs; only a seated owner receives Hand.
type GameSnapshot struct {
	RoomID            string                  `json:"roomId"`
	GameNumber        int                     `json:"gameNumber"`
	StartingSeat      int                     `json:"startingSeat"`
	ActiveSeat        int                     `json:"activeSeat"`
	CurrentPhase      string                  `json:"currentPhase"`
	LandPlaysThisTurn int                     `json:"landPlaysThisTurn"`
	Seats             []GameSeatProjection    `json:"seats"`
	Stack             []GameSharedCard        `json:"stack"`
	Revealed          []GameSharedCard        `json:"revealed"`
	Arrows            []GameArrow             `json:"arrows"`
	Attachments       []GameAttachment        `json:"attachments"`
	Commanders        []GameCommanderIdentity `json:"commanders,omitempty"`
	CommanderDamage   []GameCommanderDamage   `json:"commanderDamage,omitempty"`
	Log               []GameLogEntry          `json:"log"`
	LogStartID        int64                   `json:"logStartId,omitempty"`
	LogTruncated      bool                    `json:"logTruncated,omitempty"`
	Score             []int                   `json:"score"`
	DrawnGames        int                     `json:"drawnGames,omitempty"`
	Result            *GameResult             `json:"result,omitempty"`
	Sideboard         *SideboardProjection    `json:"sideboard,omitempty"`
}

// GameArrow is a public, temporary combat or targeting relation. Combat sources
// are controlled battlefield cards; ordinary target sources may also be cards
// the acting player owns on the shared stack. A relation points to a seated
// player or a battlefield card, and each source owns at most one relation.
type GameArrow struct {
	Seat         int    `json:"seat"`
	SourceCardID string `json:"sourceCardId"`
	Kind         string `json:"kind"`
	TargetCardID string `json:"targetCardId,omitempty"`
	TargetSeat   *int   `json:"targetSeat,omitempty"`
}

// GameAttachment is a public battlefield relation. SourceCardID belongs to
// OwnerSeat; TargetCardID may belong to any seated player.
type GameAttachment struct {
	OwnerSeat    int    `json:"ownerSeat"`
	SourceCardID string `json:"sourceCardId"`
	TargetCardID string `json:"targetCardId"`
}

// RoomKick is the payload of room.kick (C->S, host only). Exactly one of
// Seat / SpectatorIndex must be set; the host cannot kick their own (host)
// seat - use room.leave or room.disband instead. Display names are not used
// (duplicates are allowed, so name-based kick would be ambiguous).
type RoomKick struct {
	Seat           *int `json:"seat,omitempty"`           // player seat index 0..maxSeats-1
	SpectatorIndex *int `json:"spectatorIndex,omitempty"` // index into spectators slice
}

// Validate reports an error code (empty string if OK) if the kick target is
// not exactly one of Seat / SpectatorIndex.
func (k RoomKick) Validate() string {
	seatSet := k.Seat != nil
	specSet := k.SpectatorIndex != nil
	if seatSet == specSet { // both or neither
		return ErrInvalidTarget
	}
	return ""
}

// RoomLeft is the payload of room.left (S->C, ack for leave).
type RoomLeft struct {
	RoomID string `json:"roomId"`
}

// Seat is a player seat projection in a snapshot.
type Seat struct {
	Occupied     bool   `json:"occupied"`
	DisplayName  string `json:"displayName,omitempty"`
	Host         bool   `json:"host,omitempty"`
	DeckSelected bool   `json:"deckSelected,omitempty"`
	Ready        bool   `json:"ready,omitempty"`
	Loaded       bool   `json:"loaded,omitempty"`
	// ConnectionID is omitted in projections (never sent to clients).
}

// SpectatorProjection is a spectator entry in a snapshot.
type SpectatorProjection struct {
	DisplayName string `json:"displayName"`
}

// RoomSnapshot is the payload of room.snapshot (S->C). It carries public room
// structure and the immutable policy used by later role-specific game
// projections; it never embeds deck or zone identities itself.
type RoomSnapshot struct {
	RoomID             string                `json:"roomId"`
	Name               string                `json:"name"`
	Format             string                `json:"format"`
	DeckFormat         string                `json:"deckFormat"`
	MaxSeats           int                   `json:"maxSeats"`
	Playtest           bool                  `json:"playtest,omitempty"`
	MatchMode          string                `json:"matchMode"`
	CardLoadMode       string                `json:"cardLoadMode"`
	HostSeat           int                   `json:"hostSeat"`
	HasPassword        bool                  `json:"hasPassword"`
	Seats              []Seat                `json:"seats"`
	Spectators         []SpectatorProjection `json:"spectators"`
	AllowSpectators    bool                  `json:"allowSpectators"`
	SpectatorsSeeHands bool                  `json:"spectatorsSeeHands"`
	Phase              string                `json:"phase"`
	LoadID             int64                 `json:"loadId,omitempty"`
}

// NewEnvelope builds an Envelope with the given type and JSON-marshaled payload.
func NewEnvelope(typ string, payload any) (Envelope, error) {
	raw, err := json.Marshal(payload)
	if err != nil {
		return Envelope{}, err
	}
	return Envelope{Type: typ, Payload: raw}, nil
}

// Marshal serializes an Envelope to JSON.
func (e Envelope) Marshal() ([]byte, error) {
	return json.Marshal(e)
}

// ParseEnvelope decodes a JSON byte slice into an Envelope. It does NOT require
// a top-level `v`: only session.welcome carries `v`, and only in its payload.
// It rejects messages with an empty `type` (invalid envelope).
func ParseEnvelope(data []byte) (Envelope, error) {
	var env Envelope
	if err := json.Unmarshal(data, &env); err != nil {
		return Envelope{}, err
	}
	if env.Type == "" {
		return Envelope{}, fmt.Errorf("protocol: envelope missing type")
	}
	return env, nil
}

// DecodePayload unmarshals the envelope payload into dst.
func (e Envelope) DecodePayload(dst any) error {
	if len(e.Payload) == 0 {
		return nil
	}
	return json.Unmarshal(e.Payload, dst)
}

// ValidateWelcome returns an error if a session.welcome payload does not carry
// the expected protocol version. Enforces the handshake-only `v` rule.
func ValidateWelcome(w SessionWelcome) error {
	if w.V != ProtocolVersion {
		return fmt.Errorf("protocol: welcome version %q != %q", w.V, ProtocolVersion)
	}
	return nil
}
