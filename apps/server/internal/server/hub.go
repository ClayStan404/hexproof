// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

// Package server is the WebSocket hub: it owns the room registry, per-connection
// sessions, and the dispatch loop that translates wire commands into room
// reducer calls and fans out the resulting events.
package server

import (
	"context"
	"sort"
	"sync"
	"time"

	"hexproof/server/internal/protocol"
	"hexproof/server/internal/room"
)

// Session is one WebSocket connection's state.
type Session struct {
	ConnectionID string
	DisplayName  string
	ResumeToken  string
	RemoteIP     string
	// Send is buffered; the hub pushes outbound envelopes here, the write pump
	// drains them onto the WebSocket.
	Send chan []byte
	// closeMu guards close state so concurrent fanout writers do not send on a
	// closed channel (race-safe shutdown).
	closeMu sync.Mutex
	closed  bool
	cancel  context.CancelFunc
	// roomMu guards roomRef.
	roomMu  sync.RWMutex
	roomRef *room.Room
	// Tournament membership is independent from a pairing room. A participant
	// remains registered while entering and leaving ordinary room state.
	tournamentMu sync.RWMutex
	tournament   tournamentBinding
	// The read loop is the only writer for these fixed-window rate fields.
	rateWindowStart time.Time
	rateMessages    int
}

type tournamentBinding struct {
	TournamentID  string
	Role          string
	ParticipantID string
}

func (s *Session) allowMessage(now time.Time, limit int) bool {
	if limit <= 0 {
		return true
	}
	if s.rateWindowStart.IsZero() || now.Sub(s.rateWindowStart) >= time.Second {
		s.rateWindowStart = now
		s.rateMessages = 0
	}
	s.rateMessages++
	return s.rateMessages <= limit
}

// Room returns the session's current room (nil if none).
func (s *Session) Room() *room.Room {
	s.roomMu.RLock()
	defer s.roomMu.RUnlock()
	return s.roomRef
}

// setRoom sets the session's current room.
func (s *Session) setRoom(r *room.Room) {
	s.roomMu.Lock()
	defer s.roomMu.Unlock()
	s.roomRef = r
}

func (s *Session) Tournament() tournamentBinding {
	s.tournamentMu.RLock()
	defer s.tournamentMu.RUnlock()
	return s.tournament
}

func (s *Session) setTournament(binding tournamentBinding) {
	s.tournamentMu.Lock()
	defer s.tournamentMu.Unlock()
	s.tournament = binding
}

func (s *Session) clearTournament() tournamentBinding {
	s.tournamentMu.Lock()
	defer s.tournamentMu.Unlock()
	previous := s.tournament
	s.tournament = tournamentBinding{}
	return previous
}

// trySend pushes data onto Send without blocking. A full buffer means this
// client can no longer consume the ordered event stream, so the session is
// closed and its read loop is cancelled instead of silently dropping state.
// It is race-safe against Close: close state and channel sends share closeMu.
func (s *Session) trySend(data []byte) bool {
	s.closeMu.Lock()
	if s.closed {
		s.closeMu.Unlock()
		return false
	}
	select {
	case s.Send <- data:
		s.closeMu.Unlock()
		return true
	default:
		cancel := s.closeLocked()
		s.closeMu.Unlock()
		if cancel != nil {
			cancel()
		}
		return false
	}
}

// Close marks the session closed and closes the Send channel. Safe to call
// once; subsequent trySend calls return false.
func (s *Session) Close() {
	s.closeMu.Lock()
	cancel := s.closeLocked()
	s.closeMu.Unlock()
	if cancel != nil {
		cancel()
	}
}

// closeLocked transitions the session to closed. The caller must hold closeMu
// and invoke the returned cancellation function after releasing the mutex.
func (s *Session) closeLocked() context.CancelFunc {
	if s.closed {
		return nil
	}
	s.closed = true
	close(s.Send)
	return s.cancel
}

// Hub owns the room registry and sessions. It is safe for concurrent use.
type Hub struct {
	mu            sync.Mutex
	rooms         map[string]*roomEntry
	maxRooms      int
	passwordCheck func([]byte, string) bool
	passwordSlots chan struct{}
}

type roomEntry struct {
	room         *room.Room
	passwordHash []byte // immutable bcrypt hash; never enters reducer state
	// opMu preserves reducer/reply/fan-out order across concurrent sessions.
	// Handler operations hold it from before the reducer call until all
	// resulting messages have been queued.
	opMu              sync.Mutex
	mu                sync.Mutex // protects room state during reducer calls and projections
	tournamentID      string
	tournamentPairing string
}

// NewHub creates an empty Hub.
func NewHub() *Hub {
	defaults := DefaultConfig()
	return NewHubWithLimits(defaults.MaxRooms, defaults.MaxConcurrentPasswordChecks)
}

// NewHubWithLimit creates a hub with a hard room-registry bound.
func NewHubWithLimit(maxRooms int) *Hub {
	return NewHubWithLimits(maxRooms, DefaultConfig().MaxConcurrentPasswordChecks)
}

// NewHubWithLimits creates a hub with room and bcrypt concurrency bounds.
func NewHubWithLimits(maxRooms, maxConcurrentPasswordChecks int) *Hub {
	if maxConcurrentPasswordChecks <= 0 {
		maxConcurrentPasswordChecks = 1
	}
	return &Hub{
		rooms:         make(map[string]*roomEntry),
		maxRooms:      maxRooms,
		passwordCheck: checkPassword,
		passwordSlots: make(chan struct{}, maxConcurrentPasswordChecks),
	}
}

// CreateRoom creates a new room with a generated id and registers it. The
// creator's connection becomes the host (seat 0). Room id generation,
// uniqueness check, and map insertion happen under a single Hub.mu critical
// section to eliminate the TOCTOU window (two concurrent creates could
// otherwise register the same id).
func (h *Hub) CreateRoom(name, format, matchMode, cardLoadMode string, maxSeats int,
	allowSpectators, spectatorsSeeHands bool, password string,
	host *Session) (*room.Room, protocol.RoomSnapshot, int64, *roomEntry, error) {
	return h.CreateRoomWithDeckFormat(name, format,
		protocol.DefaultDeckFormatForTableMode(format), matchMode, cardLoadMode, maxSeats,
		allowSpectators, spectatorsSeeHands, password, host)
}

// CreateRoomWithDeckFormat creates a room with an explicit construction
// policy while keeping tabletop behavior in the legacy format field.
func (h *Hub) CreateRoomWithDeckFormat(name, format, deckFormat, matchMode,
	cardLoadMode string, maxSeats int, allowSpectators, spectatorsSeeHands bool, password string,
	host *Session) (*room.Room, protocol.RoomSnapshot, int64, *roomEntry, error) {
	return h.CreateRoomWithRulesMode(name, format, deckFormat, matchMode, cardLoadMode,
		protocol.RulesModeManual, maxSeats, allowSpectators, spectatorsSeeHands, password, host)
}

// CreateRoomWithRulesMode creates an ordinary room with an immutable gameplay
// authority. Runtime availability is checked by the handler before the room
// is published.
func (h *Hub) CreateRoomWithRulesMode(name, format, deckFormat, matchMode, cardLoadMode,
	rulesMode string, maxSeats int, allowSpectators, spectatorsSeeHands bool, password string,
	host *Session) (*room.Room, protocol.RoomSnapshot, int64, *roomEntry, error) {
	return h.createRoom(name, format, deckFormat, matchMode, cardLoadMode, rulesMode, maxSeats,
		allowSpectators, spectatorsSeeHands, password, "", "", "", host)
}

// createTournamentRoom tags a pairing room before it becomes visible in the
// hub registry, so concurrent room-list requests can never observe it as an
// ordinary public room.
func (h *Hub) createTournamentRoom(name, format, deckFormat, matchMode, cardLoadMode string,
	maxSeats int, tournamentID, tournamentPairing, tournamentParticipantID string,
	host *Session) (*room.Room, protocol.RoomSnapshot, int64, *roomEntry, error) {
	return h.createRoom(name, format, deckFormat, matchMode, cardLoadMode,
		protocol.RulesModeManual, maxSeats, false,
		false, "", tournamentID, tournamentPairing, tournamentParticipantID, host)
}

func (h *Hub) createRoom(name, format, deckFormat, matchMode, cardLoadMode, rulesMode string,
	maxSeats int, allowSpectators, spectatorsSeeHands bool, password, tournamentID, tournamentPairing,
	tournamentParticipantID string,
	host *Session) (*room.Room, protocol.RoomSnapshot, int64, *roomEntry, error) {
	if !protocol.ValidDeckFormat(deckFormat) ||
		protocol.TableModeForDeckFormat(deckFormat) != format {
		return nil, protocol.RoomSnapshot{}, 0, nil,
			&protocolError{code: protocol.ErrUnsupportedFormat,
				message: "deck format does not match table mode"}
	}
	hash, err := hashPassword(password)
	if err != nil {
		return nil, protocol.RoomSnapshot{}, 0, nil, err
	}

	h.mu.Lock()
	defer h.mu.Unlock()
	if h.maxRooms > 0 && len(h.rooms) >= h.maxRooms {
		return nil, protocol.RoomSnapshot{}, 0, nil,
			&protocolError{code: protocol.ErrServerLimit, message: "maximum rooms reached"}
	}

	// Generate + uniqueness-check + insert atomically.
	var id string
	var r *room.Room
	for {
		id, err = genRoomID()
		if err != nil {
			return nil, protocol.RoomSnapshot{}, 0, nil,
				&protocolError{
					code:    protocol.ErrInternal,
					message: "room id generation unavailable",
				}
		}
		if _, ok := h.rooms[id]; ok {
			continue // collision, retry
		}
		r, err = room.NewWithRulesMode(id, name, format, matchMode, cardLoadMode, rulesMode,
			maxSeats, allowSpectators, len(hash) > 0, host.DisplayName, host.ConnectionID, time.Now())
		if err != nil {
			return nil, protocol.RoomSnapshot{}, 0, nil, err
		}
		r.DeckFormat = deckFormat
		r.SpectatorsSeeHands = allowSpectators && spectatorsSeeHands
		if tournamentParticipantID != "" {
			r.Seats[r.HostSeat].TournamentParticipantID = tournamentParticipantID
		}
		// Build the first snapshot and bind the host before publishing the room.
		// Once the map entry is visible, every state read/write must use entry.mu.
		snapshot := r.Snapshot()
		seq := r.AllocSeq()
		host.setRoom(r)
		entry := &roomEntry{
			room: r, passwordHash: append([]byte(nil), hash...),
			tournamentID: tournamentID, tournamentPairing: tournamentPairing,
		}
		// The entry is new and remains unreachable while h.mu is held, so this
		// opMu acquisition cannot contend with lockRoomOperation. The caller
		// receives opMu locked so no subsequent room operation can mutate the
		// initial state before its reply/projection is queued.
		entry.opMu.Lock()
		h.rooms[id] = entry
		return r, snapshot, seq, entry, nil
	}
}

// ResumeRoom rebinds a held membership and returns only fresh projections for
// that member. Historical per-role envelopes are never replayed.
func (h *Hub) ResumeRoom(oldConnID string, sess *Session,
	r *room.Room) (room.ReconnectInfo, []protocol.Envelope, error) {
	entry := h.roomEntryFor(r.ID)
	if entry == nil {
		return room.ReconnectInfo{}, nil,
			&protocolError{code: protocol.ErrRoomNotFound, message: "room not found"}
	}
	entry.mu.Lock()
	defer entry.mu.Unlock()

	info, err := r.Reconnect(oldConnID, sess.ConnectionID)
	if err != nil {
		return room.ReconnectInfo{}, nil, mapRoomError(err)
	}
	envelopes, err := r.ResumeEnvelopes(sess.ConnectionID)
	if err != nil {
		if _, rollbackErr := r.Reconnect(sess.ConnectionID, oldConnID); rollbackErr != nil {
			return room.ReconnectInfo{}, nil,
				&protocolError{
					code:    protocol.ErrInternal,
					message: "failed to roll back incomplete room resume",
				}
		}
		return room.ReconnectInfo{}, nil, mapRoomError(err)
	}
	sess.setRoom(r)
	return info, envelopes, nil
}

// ExpireDisconnected releases a membership after its reconnect deadline.
func (h *Hub) ExpireDisconnected(connID string,
	r *room.Room) (room.Result, bool, error) {
	entry := h.roomEntryFor(r.ID)
	if entry == nil {
		return room.Result{}, false,
			&protocolError{code: protocol.ErrRoomNotFound, message: "room not found"}
	}
	entry.mu.Lock()
	defer entry.mu.Unlock()
	result, empty, err := r.ExpireDisconnected(connID)
	if err != nil {
		return room.Result{}, false, mapRoomError(err)
	}
	return result, empty, nil
}

// FindRoom returns the room with the given id (nil if none).
func (h *Hub) FindRoom(id string) *room.Room {
	h.mu.Lock()
	defer h.mu.Unlock()
	if e, ok := h.rooms[id]; ok {
		return e.room
	}
	return nil
}

// TournamentForRoom returns the immutable tournament tag of a private pairing
// room. Ordinary rooms return an empty id.
func (h *Hub) TournamentForRoom(r *room.Room) string {
	if r == nil {
		return ""
	}
	entry := h.roomEntryFor(r.ID)
	if entry == nil || entry.room != r {
		return ""
	}
	return entry.tournamentID
}

// tournamentHasOccupiedPairingRoom reports whether any private pairing room
// tagged with tournamentID still has a seated player or spectator. Occupied
// rooms keep a running event alive even if every tournament lobby session has
// disconnected. Callers may hold tournament opMu; this takes Hub.mu then each
// room entry.mu, matching ListRooms.
func (h *Hub) tournamentHasOccupiedPairingRoom(tournamentID string) bool {
	if tournamentID == "" {
		return false
	}
	h.mu.Lock()
	entries := make([]*roomEntry, 0)
	for _, entry := range h.rooms {
		if entry.tournamentID == tournamentID {
			entries = append(entries, entry)
		}
	}
	h.mu.Unlock()

	for _, entry := range entries {
		entry.mu.Lock()
		occupied := pairingRoomOccupied(entry.room)
		entry.mu.Unlock()
		if occupied {
			return true
		}
	}
	return false
}

func pairingRoomOccupied(r *room.Room) bool {
	if r == nil || r.Disbanded {
		return false
	}
	if r.PlayerCount() > 0 {
		return true
	}
	return len(r.Spectators) > 0
}

// ListRooms returns stable, public projections of rooms on this hub only.
// Registry and room locks are never held together, avoiding lock inversion
// with room removal while still taking each projection atomically.
func (h *Hub) ListRooms() []protocol.RoomListEntry {
	h.mu.Lock()
	entries := make([]*roomEntry, 0, len(h.rooms))
	for _, entry := range h.rooms {
		entries = append(entries, entry)
	}
	h.mu.Unlock()

	rooms := make([]protocol.RoomListEntry, 0, len(entries))
	for _, entry := range entries {
		entry.mu.Lock()
		if !entry.room.Disbanded && !entry.room.Playtest && entry.tournamentID == "" {
			rooms = append(rooms, entry.room.ListEntry())
		}
		entry.mu.Unlock()
	}
	sort.Slice(rooms, func(left, right int) bool {
		return rooms[left].RoomID < rooms[right].RoomID
	})
	return rooms
}

// roomEntryFor returns the roomEntry (with its lock) for atomic join/leave.
func (h *Hub) roomEntryFor(id string) *roomEntry {
	h.mu.Lock()
	defer h.mu.Unlock()
	return h.rooms[id]
}

// reduceRoom owns the repeated room lookup, identity check, state lock, and
// reducer-error mapping used by ordinary room.Result operations. Callers still
// hold opMu across their reply and fan-out so command ordering is unchanged.
func (h *Hub) reduceRoom(r *room.Room,
	reducer func(*room.Room) (room.Result, error)) (room.Result, error) {
	if r == nil {
		return room.Result{},
			&protocolError{code: protocol.ErrRoomNotFound, message: "room not found"}
	}
	entry := h.roomEntryFor(r.ID)
	if entry == nil {
		return room.Result{},
			&protocolError{code: protocol.ErrRoomNotFound, message: "room not found"}
	}
	entry.mu.Lock()
	defer entry.mu.Unlock()
	if entry.room != r {
		return room.Result{},
			&protocolError{code: protocol.ErrRoomNotFound, message: "room not found"}
	}
	result, err := reducer(entry.room)
	if err != nil {
		return result, mapRoomError(err)
	}
	return result, nil
}

// lockRoomOperation begins a reducer/reply/fan-out transaction for one room.
// The caller must unlock entry.opMu after all resulting messages are queued.
func (h *Hub) lockRoomOperation(id string) (*roomEntry, error) {
	entry := h.roomEntryFor(id)
	if entry == nil {
		return nil, &protocolError{code: protocol.ErrRoomNotFound, message: "room not found"}
	}
	entry.opMu.Lock()

	// The room may have been removed while this operation waited for opMu.
	h.mu.Lock()
	current := h.rooms[id]
	h.mu.Unlock()
	if current != entry {
		entry.opMu.Unlock()
		return nil, &protocolError{code: protocol.ErrRoomNotFound, message: "room not found"}
	}
	return entry, nil
}

// beginJoin validates the immutable room password before acquiring opMu, then
// verifies that the same room entry is still registered. bcrypt comparison is
// intentionally outside the room operation transaction so failed joins cannot
// stall legitimate gameplay in that room.
func (h *Hub) beginJoin(roomID, password string) (*roomEntry, error) {
	entry := h.roomEntryFor(roomID)
	if entry == nil {
		return nil, &protocolError{code: protocol.ErrRoomNotFound, message: "room not found"}
	}
	hasPassword := len(entry.passwordHash) > 0
	passwordHash := append([]byte(nil), entry.passwordHash...)
	if hasPassword {
		select {
		case h.passwordSlots <- struct{}{}:
			defer func() { <-h.passwordSlots }()
		default:
			return nil, &protocolError{
				code: protocol.ErrRateLimited, message: "password checks are busy",
			}
		}
		if !h.passwordCheck(passwordHash, password) {
			return nil, &protocolError{code: protocol.ErrWrongPassword, message: "wrong password"}
		}
	}

	entry.opMu.Lock()
	h.mu.Lock()
	current := h.rooms[roomID]
	h.mu.Unlock()
	if current != entry {
		entry.opMu.Unlock()
		return nil, &protocolError{code: protocol.ErrRoomNotFound, message: "room not found"}
	}
	return entry, nil
}

// RoomRequiresPassword reports immutable password presence without exposing a
// hash. The bool result is false when the room no longer exists.
func (h *Hub) RoomRequiresPassword(roomID string) (bool, bool) {
	entry := h.roomEntryFor(roomID)
	if entry == nil {
		return false, false
	}
	return len(entry.passwordHash) > 0, true
}

// removeRoom drops a disbanded room from the registry.
func (h *Hub) removeRoom(id string) {
	h.mu.Lock()
	defer h.mu.Unlock()
	delete(h.rooms, id)
}

// joinRoom attempts to join through an entry returned by beginJoin. On
// success the session is bound to the room. The caller holds entry.opMu until
// all resulting messages have been queued.
func (h *Hub) joinRoom(entry *roomEntry, sess *Session, asSpectator bool) (room.Result, *room.Room, error) {
	entry.mu.Lock()
	defer entry.mu.Unlock()

	res, err := entry.room.Join(sess.ConnectionID, sess.DisplayName, asSpectator, "")
	if err != nil {
		return room.Result{}, nil, mapRoomError(err)
	}
	// Bind the session before releasing the room lock. This prevents a host
	// kick/disband from racing between reducer membership and Session.roomRef.
	sess.setRoom(entry.room)
	return res, entry.room, nil
}

// joinTournamentRoom binds a current tournament participant to exactly one
// player seat in a pairing room.
func (h *Hub) joinTournamentRoom(entry *roomEntry, sess *Session,
	participantID string) (room.Result, *room.Room, error) {
	entry.mu.Lock()
	defer entry.mu.Unlock()

	res, err := entry.room.JoinTournamentParticipant(
		sess.ConnectionID, sess.DisplayName, participantID)
	if err != nil {
		return room.Result{}, nil, mapRoomError(err)
	}
	sess.setRoom(entry.room)
	return res, entry.room, nil
}

// LeaveRoom removes a connection from its room. If the host leaves, the room
// is marked disbanded (but NOT removed from the registry yet - the caller must
// fanout the disband event first, then call RemoveRoom). Returns the reducer
// result. The returned bool is true if the room disbanded.
func (h *Hub) LeaveRoom(connID string, r *room.Room) (room.Result, bool, error) {
	entry := h.roomEntryFor(r.ID)
	if entry == nil {
		return room.Result{}, false, &protocolError{code: protocol.ErrRoomNotFound, message: "room not found"}
	}
	entry.mu.Lock()
	defer entry.mu.Unlock()

	res, err := r.Leave(connID)
	if err != nil {
		return room.Result{}, false, mapRoomError(err)
	}
	return res, r.Disbanded, nil
}

// RemoveRoom drops a room from the registry. Called by the handler AFTER the
// disband event has been fanned out to remaining members.
func (h *Hub) RemoveRoom(id string) {
	h.removeRoom(id)
}

// GameProjections builds one role-specific game.snapshot per current member.
// Every projection shares one room sequence number while hidden hands differ.
func (h *Hub) GameProjections(r *room.Room) (map[string]protocol.Envelope, error) {
	if r == nil {
		return nil, &protocolError{code: protocol.ErrRoomNotFound, message: "room not found"}
	}
	entry := h.roomEntryFor(r.ID)
	if entry == nil {
		return nil, &protocolError{code: protocol.ErrRoomNotFound, message: "room not found"}
	}
	entry.mu.Lock()
	defer entry.mu.Unlock()
	if entry.room != r {
		return nil, &protocolError{code: protocol.ErrRoomNotFound, message: "room not found"}
	}
	locked := entry.room

	connectionIDs := make([]string, 0, len(locked.Seats)+len(locked.Spectators))
	for _, seat := range locked.Seats {
		if seat.Occupied {
			connectionIDs = append(connectionIDs, seat.ConnectionID)
		}
	}
	for _, spectator := range locked.Spectators {
		connectionIDs = append(connectionIDs, spectator.ConnectionID)
	}
	seq := locked.AllocSeq()
	projections := make(map[string]protocol.Envelope, len(connectionIDs))
	for _, connID := range connectionIDs {
		snapshot, err := locked.GameSnapshot(connID)
		if err != nil {
			return nil, mapRoomError(err)
		}
		envelope, err := protocol.NewEnvelope(protocol.TypeGameSnapshot, snapshot)
		if err != nil {
			return nil, &protocolError{
				code:    protocol.ErrInternal,
				message: "internal server error",
			}
		}
		projections[connID] = envelope.WithSeq(seq)
	}
	return projections, nil
}

// RulesProjectionTargets snapshots the authenticated viewer seat for each
// current room member and allocates one shared room sequence number. A seat of
// -1 denotes the explicit spectator projection.
func (h *Hub) RulesProjectionTargets(r *room.Room) (map[string]int, int64, error) {
	if r == nil {
		return nil, 0, &protocolError{code: protocol.ErrRoomNotFound, message: "room not found"}
	}
	entry := h.roomEntryFor(r.ID)
	if entry == nil {
		return nil, 0, &protocolError{code: protocol.ErrRoomNotFound, message: "room not found"}
	}
	entry.mu.Lock()
	defer entry.mu.Unlock()
	if entry.room != r || r.RulesMode != protocol.RulesModeForge ||
		r.Phase != protocol.RoomPhaseStarted {
		return nil, 0, &protocolError{code: protocol.ErrGameNotStarted, message: "game not started"}
	}
	targets := make(map[string]int, r.PlayerCount()+len(r.Spectators))
	for seatIndex, seat := range r.Seats {
		if seat.Occupied {
			targets[seat.ConnectionID] = seatIndex
		}
	}
	for _, spectator := range r.Spectators {
		targets[spectator.ConnectionID] = -1
	}
	return targets, r.AllocSeq(), nil
}

// DisbandRoom validates that actorConnID is the host and disbands the room in
// one per-room critical section.
func (h *Hub) DisbandRoom(actorConnID string, r *room.Room) (room.Result, error) {
	entry := h.roomEntryFor(r.ID)
	if entry == nil {
		return room.Result{}, &protocolError{code: protocol.ErrRoomNotFound, message: "room not found"}
	}
	entry.mu.Lock()
	defer entry.mu.Unlock()

	if !r.IsHost(actorConnID) {
		return room.Result{}, &protocolError{code: protocol.ErrNotHost, message: "host only"}
	}
	res, err := r.Leave(actorConnID)
	if err != nil {
		return room.Result{}, mapRoomError(err)
	}
	return res, nil
}

// protocolError carries a wire error code.
type protocolError struct {
	code    string
	message string
}

func (e *protocolError) Error() string { return e.code + ": " + e.message }

// mapRoomError translates a typed room-package error into a wire error.
// Arbitrary reducer failures remain private server details.
func mapRoomError(err error) error {
	if err == nil {
		return nil
	}
	if code, ok := room.ErrorCode(err); ok {
		return &protocolError{code: code, message: code}
	}
	return &protocolError{
		code:    protocol.ErrInternal,
		message: "internal server error",
	}
}

// ErrCode extracts the wire code from an error returned by hub methods.
func ErrCode(err error) (string, bool) {
	if pe, ok := err.(*protocolError); ok {
		return pe.code, true
	}
	return "", false
}
