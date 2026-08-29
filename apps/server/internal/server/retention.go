// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package server

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"sync"
	"time"

	"hexproof/server/internal/protocol"
	"hexproof/server/internal/room"
)

type retainedSeat struct {
	DisplayName string               `json:"displayName"`
	Host        bool                 `json:"host,omitempty"`
	Deck        *protocol.DeckSelect `json:"deck,omitempty"`
	Ready       bool                 `json:"ready,omitempty"`
	Loaded      bool                 `json:"loaded,omitempty"`
}

// retainedRoom is operator-only trust-server storage. It deliberately omits
// passwords, reconnect credentials, and transport connection IDs while
// retaining registered decks plus complete hidden game zones and logs.
type retainedRoom struct {
	SchemaVersion int             `json:"schemaVersion"`
	SavedAt       time.Time       `json:"savedAt"`
	ExpiresAt     time.Time       `json:"expiresAt"`
	RoomID        string          `json:"roomId"`
	Name          string          `json:"name"`
	Format        string          `json:"format"`
	DeckFormat    string          `json:"deckFormat,omitempty"`
	MatchMode     string          `json:"matchMode"`
	Seats         []retainedSeat  `json:"seats"`
	Spectators    []string        `json:"spectators,omitempty"`
	Score         []int           `json:"score"`
	Game          *room.GameState `json:"game"`
}

var errInvalidRetainedRoom = errors.New("invalid retained match")

const retainedRoomSchemaVersion = 1

type retentionStore struct {
	dir      string
	ttl      time.Duration
	maxFiles int
	maxBytes int64
	mu       sync.Mutex
	index    map[string]retainedIndexEntry
}

type retainedIndexEntry struct {
	path      string
	size      int64
	savedAt   time.Time
	expiresAt time.Time
	summary   protocol.ReplaySummary
}

func newRetentionStore(dir string, ttl time.Duration, maxFiles int,
	maxBytes int64, now time.Time) (*retentionStore, error) {
	dir = strings.TrimSpace(dir)
	if dir == "" {
		return nil, nil
	}
	if ttl <= 0 {
		return nil, errors.New("retention TTL must be positive")
	}
	if maxFiles <= 0 || maxBytes <= 0 {
		return nil, errors.New("retention limits must be positive")
	}
	if err := os.MkdirAll(dir, 0o700); err != nil {
		return nil, fmt.Errorf("create retention directory: %w", err)
	}
	if err := os.Chmod(dir, 0o700); err != nil {
		return nil, fmt.Errorf("secure retention directory: %w", err)
	}
	store := &retentionStore{
		dir: dir, ttl: ttl, maxFiles: maxFiles, maxBytes: maxBytes,
		index: make(map[string]retainedIndexEntry),
	}
	if err := store.cleanup(now); err != nil {
		return nil, err
	}
	return store, nil
}

func (s *retentionStore) save(r *room.Room, now time.Time) error {
	return s.saveSnapshot(s.snapshot(r, now))
}

// snapshot copies the complete retained state while the caller holds the room
// state lock. The returned record is independent of live reducer state and can
// therefore be encoded and written after the room operation lock is released.
func (s *retentionStore) snapshot(r *room.Room, now time.Time) *retainedRoom {
	if s == nil || r == nil || r.Game == nil || r.Playtest {
		return nil
	}
	seats := make([]retainedSeat, len(r.Seats))
	for index, seat := range r.Seats {
		seats[index] = retainedSeat{
			DisplayName: seat.DisplayName,
			Host:        seat.Host,
			Deck:        cloneRetainedDeck(seat.Deck),
			Ready:       seat.Ready,
			Loaded:      seat.Loaded,
		}
	}
	spectators := make([]string, len(r.Spectators))
	for index, spectator := range r.Spectators {
		spectators[index] = spectator.DisplayName
	}
	return &retainedRoom{
		SchemaVersion: retainedRoomSchemaVersion,
		SavedAt:       now.UTC(),
		ExpiresAt:     now.UTC().Add(s.ttl),
		RoomID:        r.ID,
		Name:          r.Name,
		Format:        r.Format,
		DeckFormat:    r.DeckFormat,
		MatchMode:     r.MatchMode,
		Seats:         seats,
		Spectators:    spectators,
		Score:         append([]int(nil), r.Score...),
		Game:          cloneRetainedGame(r.Game),
	}
}

func (s *retentionStore) saveSnapshot(record *retainedRoom) error {
	if s == nil || record == nil {
		return nil
	}
	data, err := json.MarshalIndent(*record, "", "  ")
	if err != nil {
		return fmt.Errorf("encode retained match: %w", err)
	}
	data = append(data, '\n')
	if int64(len(data)) > s.maxBytes {
		return fmt.Errorf("retained match exceeds byte limit: %d > %d",
			len(data), s.maxBytes)
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	if err := s.pruneIndexLocked(record.SavedAt); err != nil {
		return err
	}
	file, err := os.CreateTemp(s.dir, ".retained-*.tmp")
	if err != nil {
		return fmt.Errorf("create retained match: %w", err)
	}
	tempName := file.Name()
	removeTemp := true
	defer func() {
		if removeTemp {
			_ = os.Remove(tempName)
		}
	}()
	if err := file.Chmod(0o600); err != nil {
		_ = file.Close()
		return fmt.Errorf("secure retained match: %w", err)
	}
	if _, err := file.Write(data); err != nil {
		_ = file.Close()
		return fmt.Errorf("write retained match: %w", err)
	}
	if err := file.Sync(); err != nil {
		_ = file.Close()
		return fmt.Errorf("sync retained match: %w", err)
	}
	if err := file.Close(); err != nil {
		return fmt.Errorf("close retained match: %w", err)
	}
	name := fmt.Sprintf("%s-%d.json", record.RoomID, record.SavedAt.UnixNano())
	path := filepath.Join(s.dir, name)
	if err := os.Rename(tempName, path); err != nil {
		return fmt.Errorf("publish retained match: %w", err)
	}
	removeTemp = false
	s.index[name] = retainedIndexEntry{
		path:      path,
		size:      int64(len(data)),
		savedAt:   record.SavedAt,
		expiresAt: record.ExpiresAt,
		summary:   replaySummary(name, *record),
	}
	return s.pruneIndexLocked(record.SavedAt)
}

func cloneRetainedDeck(deck *protocol.DeckSelect) *protocol.DeckSelect {
	if deck == nil {
		return nil
	}
	cloned := *deck
	cloned.Commanders = append([]string(nil), deck.Commanders...)
	cloned.Mainboard = append([]protocol.DeckCard(nil), deck.Mainboard...)
	cloned.Sideboard = append([]protocol.DeckCard(nil), deck.Sideboard...)
	return &cloned
}

func cloneRetainedGame(game *room.GameState) *room.GameState {
	if game == nil {
		return nil
	}
	cloned := *game
	if game.Result != nil {
		result := *game.Result
		cloned.Result = &result
	}
	cloned.Seats = make([]room.PlayerGameState, len(game.Seats))
	for index := range game.Seats {
		cloned.Seats[index] = cloneRetainedPlayerState(game.Seats[index])
	}
	cloned.Stack = cloneRetainedSharedCards(game.Stack)
	cloned.Revealed = cloneRetainedSharedCards(game.Revealed)
	cloned.Arrows = append([]protocol.GameArrow(nil), game.Arrows...)
	cloned.Attachments = append([]protocol.GameAttachment(nil), game.Attachments...)
	if game.CommanderDamage != nil {
		cloned.CommanderDamage = make(map[string]map[int]int,
			len(game.CommanderDamage))
		for commanderID, targets := range game.CommanderDamage {
			clonedTargets := make(map[int]int, len(targets))
			for targetSeat, value := range targets {
				clonedTargets[targetSeat] = value
			}
			cloned.CommanderDamage[commanderID] = clonedTargets
		}
	}
	cloned.Log = append([]protocol.GameLogEntry(nil), game.Log...)
	cloned.Sideboard = cloneRetainedSideboard(game.Sideboard)
	return &cloned
}

func cloneRetainedPlayerState(state room.PlayerGameState) room.PlayerGameState {
	cloned := state
	cloned.Counters = append([]protocol.GamePlayerCounter(nil), state.Counters...)
	cloned.Library = cloneRetainedCards(state.Library)
	cloned.Hand = cloneRetainedCards(state.Hand)
	cloned.Sideboard = cloneRetainedCards(state.Sideboard)
	cloned.Battlefield = cloneRetainedCards(state.Battlefield)
	cloned.Graveyard = cloneRetainedCards(state.Graveyard)
	cloned.Exile = cloneRetainedCards(state.Exile)
	cloned.CommandZone = cloneRetainedCards(state.CommandZone)
	if state.CommanderTaxes != nil {
		cloned.CommanderTaxes = make(map[string]int, len(state.CommanderTaxes))
		for commanderID, tax := range state.CommanderTaxes {
			cloned.CommanderTaxes[commanderID] = tax
		}
	}
	return cloned
}

func cloneRetainedCards(cards []protocol.GameCard) []protocol.GameCard {
	cloned := append([]protocol.GameCard(nil), cards...)
	for index := range cloned {
		if cards[index].Position != nil {
			position := *cards[index].Position
			cloned[index].Position = &position
		}
		cloned[index].Counters =
			append([]protocol.GameCardCounter(nil), cards[index].Counters...)
	}
	return cloned
}

func cloneRetainedSharedCards(cards []protocol.GameSharedCard) []protocol.GameSharedCard {
	cloned := append([]protocol.GameSharedCard(nil), cards...)
	for index := range cloned {
		if cards[index].Position != nil {
			position := *cards[index].Position
			cloned[index].Position = &position
		}
		cloned[index].Counters =
			append([]protocol.GameCardCounter(nil), cards[index].Counters...)
	}
	return cloned
}

func cloneRetainedSideboard(sideboard *room.SideboardState) *room.SideboardState {
	if sideboard == nil {
		return nil
	}
	cloned := *sideboard
	cloned.Players = make([]room.SideboardPlayerState, len(sideboard.Players))
	for index, player := range sideboard.Players {
		cloned.Players[index] = player
		cloned.Players[index].Mainboard =
			append([]protocol.DeckCard(nil), player.Mainboard...)
		cloned.Players[index].Sideboard =
			append([]protocol.DeckCard(nil), player.Sideboard...)
		cloned.Players[index].Commanders =
			append([]string(nil), player.Commanders...)
	}
	return &cloned
}

func (s *retentionStore) cleanup(now time.Time) error {
	if s == nil {
		return nil
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.rebuildIndexLocked(now)
}

// rebuildIndexLocked is the only full retained-file scan. It runs at startup
// and during explicit maintenance, not on public replay requests.
func (s *retentionStore) rebuildIndexLocked(now time.Time) error {
	entries, err := os.ReadDir(s.dir)
	if err != nil {
		return fmt.Errorf("read retention directory: %w", err)
	}
	nextIndex := make(map[string]retainedIndexEntry, len(entries))
	for _, entry := range entries {
		if entry.IsDir() {
			continue
		}
		if strings.HasPrefix(entry.Name(), ".retained-") &&
			filepath.Ext(entry.Name()) == ".tmp" {
			if err := os.Remove(filepath.Join(s.dir, entry.Name())); err != nil &&
				!errors.Is(err, os.ErrNotExist) {
				return fmt.Errorf("remove abandoned retained match %s: %w", entry.Name(), err)
			}
			continue
		}
		if filepath.Ext(entry.Name()) != ".json" {
			continue
		}
		path := filepath.Join(s.dir, entry.Name())
		info, err := entry.Info()
		if err != nil {
			return fmt.Errorf("stat retained match %s: %w", entry.Name(), err)
		}
		record, readErr := readRetainedRoom(path, s.maxBytes)
		if readErr != nil {
			if !errors.Is(readErr, errInvalidRetainedRoom) {
				return fmt.Errorf("read retained match %s: %w", entry.Name(), readErr)
			}
			if err := os.Remove(path); err != nil && !errors.Is(err, os.ErrNotExist) {
				return fmt.Errorf("remove invalid retained match %s: %w", entry.Name(), err)
			}
			continue
		}
		if !now.Before(record.ExpiresAt) {
			if err := os.Remove(path); err != nil && !errors.Is(err, os.ErrNotExist) {
				return fmt.Errorf("remove expired retained match %s: %w", entry.Name(), err)
			}
			continue
		}
		nextIndex[entry.Name()] = retainedIndexEntry{
			path:      path,
			size:      info.Size(),
			savedAt:   record.SavedAt,
			expiresAt: record.ExpiresAt,
			summary:   replaySummary(entry.Name(), record),
		}
	}
	s.index = nextIndex
	return s.pruneIndexLocked(now)
}

// pruneIndexLocked applies expiration and quota policy from cached metadata.
// This keeps replay list requests independent of retained file sizes.
func (s *retentionStore) pruneIndexLocked(now time.Time) error {
	files := make([]retainedIndexEntry, 0, len(s.index))
	var totalBytes int64
	for name, entry := range s.index {
		if !now.Before(entry.expiresAt) {
			if err := os.Remove(entry.path); err != nil && !errors.Is(err, os.ErrNotExist) {
				return fmt.Errorf("remove expired retained match %s: %w", name, err)
			}
			delete(s.index, name)
			continue
		}
		files = append(files, entry)
		totalBytes += entry.size
	}
	sort.Slice(files, func(left, right int) bool {
		if files[left].savedAt.Equal(files[right].savedAt) {
			return filepath.Base(files[left].path) < filepath.Base(files[right].path)
		}
		return files[left].savedAt.Before(files[right].savedAt)
	})
	for len(files) > s.maxFiles || totalBytes > s.maxBytes {
		oldest := files[0]
		files = files[1:]
		if err := os.Remove(oldest.path); err != nil && !errors.Is(err, os.ErrNotExist) {
			return fmt.Errorf("remove retained match over quota %s: %w",
				filepath.Base(oldest.path), err)
		}
		delete(s.index, filepath.Base(oldest.path))
		totalBytes -= oldest.size
	}
	return nil
}

// list returns newest-first public replay summaries from the startup index.
// Archive contents are read only when a caller loads one replay.
func (s *retentionStore) list(now time.Time, offset, limit int) (
	[]protocol.ReplaySummary, int, error) {
	if offset < 0 {
		offset = 0
	}
	if limit < 0 {
		limit = 0
	}
	if s == nil {
		return []protocol.ReplaySummary{}, 0, nil
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	if err := s.pruneIndexLocked(now); err != nil {
		return nil, 0, err
	}
	entries := make([]retainedIndexEntry, 0, len(s.index))
	for _, entry := range s.index {
		entries = append(entries, entry)
	}
	sort.Slice(entries, func(left, right int) bool {
		if entries[left].savedAt.Equal(entries[right].savedAt) {
			return entries[left].summary.ReplayID > entries[right].summary.ReplayID
		}
		return entries[left].savedAt.After(entries[right].savedAt)
	})
	total := len(entries)
	if offset > total {
		offset = total
	}
	end := offset + limit
	if end > total {
		end = total
	}
	replays := make([]protocol.ReplaySummary, 0, end-offset)
	for _, entry := range entries[offset:end] {
		replays = append(replays, entry.summary)
	}
	return replays, total, nil
}

// load returns public activity only. The retained record's decks, hands, and
// libraries never cross this boundary.
func (s *retentionStore) load(replayID string,
	now time.Time) (protocol.ReplayLoaded, error) {
	if s == nil {
		return protocol.ReplayLoaded{}, os.ErrNotExist
	}
	replayID = strings.TrimSpace(replayID)
	if replayID == "" || filepath.Base(replayID) != replayID ||
		filepath.Ext(replayID) != ".json" {
		return protocol.ReplayLoaded{}, os.ErrNotExist
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	if err := s.pruneIndexLocked(now); err != nil {
		return protocol.ReplayLoaded{}, err
	}
	entry, exists := s.index[replayID]
	if !exists {
		return protocol.ReplayLoaded{}, os.ErrNotExist
	}
	record, err := readRetainedRoom(entry.path, s.maxBytes)
	if err != nil {
		if errors.Is(err, os.ErrNotExist) || errors.Is(err, errInvalidRetainedRoom) {
			delete(s.index, replayID)
			if errors.Is(err, errInvalidRetainedRoom) {
				_ = os.Remove(entry.path)
			}
			return protocol.ReplayLoaded{}, os.ErrNotExist
		}
		return protocol.ReplayLoaded{}, err
	}
	if record.Game == nil || !now.Before(record.ExpiresAt) {
		delete(s.index, replayID)
		_ = os.Remove(entry.path)
		return protocol.ReplayLoaded{}, os.ErrNotExist
	}
	return protocol.ReplayLoaded{
		Replay: replaySummary(replayID, record),
		Log:    append([]protocol.GameLogEntry{}, record.Game.Log...),
	}, nil
}

func readRetainedRoom(path string, maxBytes int64) (retainedRoom, error) {
	info, err := os.Stat(path)
	if err != nil {
		return retainedRoom{}, err
	}
	if info.Size() < 0 || info.Size() > maxBytes {
		return retainedRoom{}, fmt.Errorf("%w: retained match size %d exceeds limit %d",
			errInvalidRetainedRoom, info.Size(), maxBytes)
	}
	data, err := os.ReadFile(path)
	if err != nil {
		return retainedRoom{}, err
	}
	return decodeRetainedRoom(data)
}

func decodeRetainedRoom(data []byte) (retainedRoom, error) {
	var record retainedRoom
	decoder := json.NewDecoder(bytes.NewReader(data))
	if err := decoder.Decode(&record); err != nil {
		return retainedRoom{}, fmt.Errorf("%w: decode JSON: %v",
			errInvalidRetainedRoom, err)
	}
	if err := decoder.Decode(&struct{}{}); !errors.Is(err, io.EOF) {
		if err == nil {
			err = errors.New("multiple JSON values")
		}
		return retainedRoom{}, fmt.Errorf("%w: trailing data: %v",
			errInvalidRetainedRoom, err)
	}
	if err := validateRetainedRoom(record); err != nil {
		return retainedRoom{}, fmt.Errorf("%w: %v", errInvalidRetainedRoom, err)
	}
	return record, nil
}

func validateRetainedRoom(record retainedRoom) error {
	if record.SchemaVersion != retainedRoomSchemaVersion {
		return fmt.Errorf("unsupported schema version %d", record.SchemaVersion)
	}
	if record.SavedAt.IsZero() || record.ExpiresAt.IsZero() ||
		!record.ExpiresAt.After(record.SavedAt) {
		return errors.New("invalid retention timestamps")
	}
	if strings.TrimSpace(record.RoomID) == "" {
		return errors.New("missing room id")
	}
	if record.Game == nil {
		return errors.New("missing game state")
	}
	if record.DeckFormat != "" &&
		(!protocol.ValidDeckFormat(record.DeckFormat) ||
			protocol.TableModeForDeckFormat(record.DeckFormat) != record.Format) {
		return errors.New("invalid retained deck format")
	}
	return nil
}

func replaySummary(replayID string, record retainedRoom) protocol.ReplaySummary {
	players := []string{}
	gameNumber := 0
	logCount := 0
	if record.Game != nil {
		gameNumber = record.Game.Number
		logCount = len(record.Game.Log)
		players = make([]string, 0, len(record.Game.Seats))
		for _, seat := range record.Game.Seats {
			players = append(players, seat.DisplayName)
		}
	}
	deckFormat := record.DeckFormat
	if deckFormat == "" {
		deckFormat = protocol.DefaultDeckFormatForTableMode(record.Format)
	}
	return protocol.ReplaySummary{
		ReplayID:      replayID,
		SavedAt:       record.SavedAt.UTC().Format(time.RFC3339),
		ExpiresAt:     record.ExpiresAt.UTC().Format(time.RFC3339),
		RoomName:      record.Name,
		Format:        record.Format,
		DeckFormat:    deckFormat,
		MatchMode:     record.MatchMode,
		GameNumber:    gameNumber,
		Players:       players,
		Score:         append([]int{}, record.Score...),
		LogEntryCount: logCount,
	}
}
