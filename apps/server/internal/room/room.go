// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

// Package room is a pure game/room state reducer. It holds NO network I/O and
// no wall-clock: callers inject `now` for timestamps. The server package wraps
// it with WebSocket fan-out. This is what makes room state testable.
//
// Current scope: room membership, private deck selection, synchronized ready
// state, asset-load coordination, automatic match start, and the first
// server-authoritative game actions and short session reconnects.
package room

import (
	"errors"
	"fmt"
	"hexproof/server/internal/protocol"
	"time"
)

// Seat is a player slot. Seats are positional (index 0..MaxSeats-1).
type Seat struct {
	Occupied                bool
	DisplayName             string
	ConnectionID            string
	TournamentParticipantID string
	Host                    bool
	// RegisteredDeck is the immutable partition submitted for the next match.
	// Deck is the active match partition and may change between BO3 games.
	RegisteredDeck *protocol.DeckSelect
	Deck           *protocol.DeckSelect
	Ready          bool
	Loaded         bool
}

// Spectator is a non-playing room member.
type Spectator struct {
	DisplayName  string
	ConnectionID string
}

// PlayerGameState is the server-authoritative zone state for one seat.
// Library and Hand are hidden and must only be projected to their owner.
type PlayerGameState struct {
	Seat           int
	DisplayName    string
	Life           int
	Counters       []protocol.GamePlayerCounter
	CounterCount   int
	Library        []protocol.GameCard
	Hand           []protocol.GameCard
	Sideboard      []protocol.GameCard
	MulliganCount  int
	Battlefield    []protocol.GameCard
	Graveyard      []protocol.GameCard
	Exile          []protocol.GameCard
	CommandZone    []protocol.GameCard
	CommanderTax   int
	CommanderTaxes map[string]int
	Eliminated     bool
	ResponseStatus string
}

// SideboardPlayerState keeps one player's private pending deck partition.
// Seat.Deck remains the last committed partition until every player is ready.
type SideboardPlayerState struct {
	Ready      bool
	Mainboard  []protocol.DeckCard
	Sideboard  []protocol.DeckCard
	Commanders []string
}

// SideboardState is the bounded BO3 between-game state. Wall-clock reads stay
// outside the reducer; callers inject times into ConcedeAt / ExpireSideboard.
type SideboardState struct {
	Deadline      time.Time
	PreviousLoser int
	Players       []SideboardPlayerState
}

// GameState holds one server-authoritative game and optional BO3 transition.
type GameState struct {
	Number            int
	StartingSeat      int
	TurnOrder         []int
	ActiveSeat        int
	CurrentPhase      string
	LandPlaysThisTurn int
	Result            *protocol.GameResult
	Seats             []PlayerGameState
	Stack             []protocol.GameSharedCard
	Revealed          []protocol.GameSharedCard
	Arrows            []protocol.GameArrow
	Attachments       []protocol.GameAttachment
	CommanderDamage   map[string]map[int]int
	Log               []protocol.GameLogEntry
	NextLogID         int64
	NextTokenID       int
	NextCardCounterID int
	Sideboard         *SideboardState
}

// Room is the authoritative room state. The server holds one per room id.
// All mutating methods are called under the Hub's per-room lock.
type Room struct {
	ID                 string
	Name               string
	Format             string
	DeckFormat         string
	MaxSeats           int
	Playtest           bool
	AllowSpectators    bool
	SpectatorsSeeHands bool
	MatchMode          string
	CardLoadMode       string
	RulesMode          string
	HasPassword        bool // password hash lives in the server room entry
	HostSeat           int
	Seats              []Seat
	Spectators         []Spectator
	CreatedAt          time.Time
	Phase              string
	LoadID             int64
	Game               *GameState
	Score              []int
	DrawnGames         int // match-level draw count; reset with Score on a new match
	randomIndex        func(int) (int, error)
	// NextSeq is the per-room monotonic seq counter, 1-based. Mutate only via
	// allocSeq / AllocSeq to keep accounting centralized in this package.
	NextSeq   int64
	Disbanded bool
}

// New creates a Room with the given settings. The creator takes seat 0 as host.
// The server layer owns password credentials; the reducer only records whether
// the room is password protected.
func New(id, name, format, matchMode, cardLoadMode string, maxSeats int, allowSpectators bool,
	hasPassword bool, hostDisplay, hostConnID string, now time.Time) (*Room, error) {
	return NewWithRulesMode(id, name, format, matchMode, cardLoadMode, protocol.RulesModeManual,
		maxSeats, allowSpectators, hasPassword, hostDisplay, hostConnID, now)
}

// NewWithRulesMode creates a room whose gameplay authority is immutable for
// the room lifetime. New remains the compatibility entry point for manual
// rooms and reducer tests.
func NewWithRulesMode(id, name, format, matchMode, cardLoadMode, rulesMode string, maxSeats int,
	allowSpectators bool, hasPassword bool, hostDisplay, hostConnID string,
	now time.Time) (*Room, error) {
	if maxSeats <= 0 {
		return nil, errors.New("room: maxSeats must be > 0")
	}
	if cardLoadMode == "" {
		cardLoadMode = protocol.CardLoadPreload
	}
	if code := ValidateCardLoadMode(cardLoadMode); code != "" {
		return nil, newError(code)
	}
	if code := ValidateRulesMode(rulesMode); code != "" {
		return nil, newError(code)
	}
	if maxSeats == 1 {
		matchMode = protocol.MatchBO1
		allowSpectators = false
	}
	if format == protocol.FormatEDH {
		matchMode = protocol.MatchBO1
	}
	// Multi-game Forge matches need an engine-aware sideboard restart, which is
	// deliberately deferred until the core prompt families are complete. Keep
	// the current integration honest and playable as BO1 in the meantime.
	if rulesMode == protocol.RulesModeForge {
		matchMode = protocol.MatchBO1
	}
	r := &Room{
		ID:              id,
		Name:            name,
		Format:          format,
		DeckFormat:      protocol.DefaultDeckFormatForTableMode(format),
		MaxSeats:        maxSeats,
		Playtest:        maxSeats == 1,
		AllowSpectators: allowSpectators,
		MatchMode:       matchMode,
		CardLoadMode:    cardLoadMode,
		RulesMode:       rulesMode,
		HasPassword:     hasPassword,
		HostSeat:        0,
		Seats:           make([]Seat, maxSeats),
		Spectators:      []Spectator{},
		CreatedAt:       now,
		Phase:           protocol.RoomPhaseWaiting,
		Score:           make([]int, maxSeats),
		randomIndex:     secureRandomIndex,
		NextSeq:         1,
	}
	r.Seats[0] = Seat{Occupied: true, DisplayName: hostDisplay, ConnectionID: hostConnID, Host: true}
	return r, nil
}

// allocSeq returns the next per-room seq and advances the counter. Internal
// use; external callers (server layer) use AllocSeq.
func (r *Room) allocSeq() int64 {
	s := r.NextSeq
	r.NextSeq++
	return s
}

// AllocSeq returns the next per-room seq (1-based, monotonic) and advances the
// counter. Exported so the server layer can stamp seq on snapshots built
// outside the reducer (e.g. the initial create snapshot) without touching
// NextSeq directly - keeping seq accounting inside the room package.
func (r *Room) AllocSeq() int64 {
	return r.allocSeq()
}

// FindSeatByConnection returns the seat index for a connection, or -1.
func (r *Room) FindSeatByConnection(connID string) int {
	for i, s := range r.Seats {
		if s.Occupied && s.ConnectionID == connID {
			return i
		}
	}
	return -1
}

// IsSpectator reports whether connID is a spectator.
func (r *Room) IsSpectator(connID string) bool {
	for _, sp := range r.Spectators {
		if sp.ConnectionID == connID {
			return true
		}
	}
	return false
}

// IsHost reports whether connID occupies the host seat.
func (r *Room) IsHost(connID string) bool {
	i := r.FindSeatByConnection(connID)
	return i >= 0 && r.Seats[i].Host
}

// Member reports whether connID is in the room (player or spectator).
func (r *Room) Member(connID string) bool {
	return r.FindSeatByConnection(connID) >= 0 || r.IsSpectator(connID)
}

// PlayerCount returns the number of occupied seats.
func (r *Room) PlayerCount() int {
	n := 0
	for _, s := range r.Seats {
		if s.Occupied {
			n++
		}
	}
	return n
}

// Result of a mutating operation: the events to fan out (already seq-stamped
// and ready to send to every member), plus the correlated reply for the
// requesting connection (echoed id set by the server layer).
type Result struct {
	Reply             *protocol.Envelope  // sent to the requesting connection only (success event)
	Broadcast         []protocol.Envelope // sent to all members (snapshot/event)
	TargetConnID      string              // for Kick: the kicked connection's id (handler notifies + unbinds it)
	ProjectGame       bool                // fan out role-specific game.snapshot projections after this result
	StartRulesGame    bool                // server must start the configured rules backend before fan-out
	SideboardDeadline time.Time           // non-zero asks the server layer to schedule expiry
}

// RulesStartPlayer is the private, exact deck input for one occupied rules
// seat. It is copied under the room lock and never projected to clients.
type RulesStartPlayer struct {
	Seat        int
	DisplayName string
	Deck        protocol.DeckSelect
}

// ZoneDumpTarget identifies the two live players involved in a private
// opponent-library access request. Connection ids stay server-internal.
type ZoneDumpTarget struct {
	RequesterSeat int
	RequesterName string
	TargetSeat    int
	TargetConnID  string
	TopCount      int
}

// PublicZoneMoveTarget identifies the two live players involved when one
// player asks to move cards out of another player's graveyard or exile.
// Connection ids remain server-internal.
type PublicZoneMoveTarget struct {
	RequesterSeat int
	RequesterName string
	TargetSeat    int
	TargetConnID  string
	SourceZone    string
	CardCount     int
	ToZone        string
}

// ReconnectInfo identifies the membership rebound from an expired transport
// connection to a new one. It contains no private card state.
type ReconnectInfo struct {
	Role string
	Seat *int
	Host bool
}

// ValidateFormat checks that a format string is supported and returns its seat
// cap. Used by the server layer on room.create.
func ValidateFormat(format string) (int, error) {
	if c := protocol.FormatMaxSeats(format); c > 0 {
		return c, nil
	}
	return 0, fmt.Errorf("room: unsupported format %q", format)
}

// ValidateMatchMode returns an error code (empty string if OK) when matchMode
// is not bo1/bo3. EDH is not force-set to bo1 here (product EDH single-game
// enforcement is a P3 rules concern).
func ValidateMatchMode(matchMode string) string {
	switch matchMode {
	case protocol.MatchBO1, protocol.MatchBO3:
		return ""
	default:
		return protocol.ErrInvalidMatchMode
	}
}

// ValidateCardLoadMode returns an error code when a room requests an unknown
// card image loading policy.
func ValidateCardLoadMode(cardLoadMode string) string {
	switch cardLoadMode {
	case protocol.CardLoadPreload, protocol.CardLoadBackground:
		return ""
	default:
		return protocol.ErrInvalidCardLoadMode
	}
}

// ValidateRulesMode returns an error code when a room requests an unknown
// gameplay authority.
func ValidateRulesMode(rulesMode string) string {
	switch rulesMode {
	case protocol.RulesModeManual, protocol.RulesModeForge:
		return ""
	default:
		return protocol.ErrInvalidRulesMode
	}
}
