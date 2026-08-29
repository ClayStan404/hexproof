// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package server

import (
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"testing"
	"time"

	"hexproof/server/internal/protocol"
	"hexproof/server/internal/room"
)

func TestRetentionStoresHiddenStateWithoutCredentialsAndExpires(t *testing.T) {
	now := time.Date(2026, time.July, 26, 12, 0, 0, 0, time.UTC)
	directory := t.TempDir()
	if err := os.Chmod(directory, 0o755); err != nil {
		t.Fatalf("make retention directory permissive: %v", err)
	}
	store, err := newRetentionStore(directory, time.Hour, 512, 512<<20, now)
	if err != nil {
		t.Fatalf("new retention store: %v", err)
	}
	directoryInfo, err := os.Stat(directory)
	if err != nil {
		t.Fatalf("stat retention directory: %v", err)
	}
	if directoryInfo.Mode().Perm() != 0o700 {
		t.Fatalf("retention directory mode = %o, want 700",
			directoryInfo.Mode().Perm())
	}
	r, err := room.New("ABCDEF", "Private match", protocol.FormatModern,
		protocol.MatchBO1, protocol.CardLoadPreload, 2, true, true,
		"Alice", "conn-secret", now)
	if err != nil {
		t.Fatalf("new room: %v", err)
	}
	r.Seats[0].Deck = &protocol.DeckSelect{
		Name: "Burn", Format: protocol.FormatModern,
		Mainboard: []protocol.DeckCard{{
			Name: "Lightning Bolt", Count: 7,
			SetCode: "M11", CollectorNumber: "149",
		}},
	}
	r.Game = &room.GameState{
		Number: 1,
		Seats: []room.PlayerGameState{{
			Seat: 0, DisplayName: "Alice",
			Hand: []protocol.GameCard{{
				ID: "secret-card", Name: "Lightning Bolt",
				SetCode: "M11", CollectorNumber: "149",
			}},
		}},
		Log: []protocol.GameLogEntry{{
			ID: 1, Kind: "opening_hand", Seat: 0,
			Text: "Alice drew an opening hand of 7 cards.",
		}},
	}
	if err := store.save(r, now); err != nil {
		t.Fatalf("save retained room: %v", err)
	}
	entries, err := os.ReadDir(directory)
	if err != nil || len(entries) != 1 {
		t.Fatalf("retained entries=%v err=%v", entries, err)
	}
	path := filepath.Join(directory, entries[0].Name())
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("read retained room: %v", err)
	}
	if !strings.Contains(string(data), "secret-card") ||
		!strings.Contains(string(data), "opening_hand") {
		t.Fatalf("retained record omitted private state: %s", data)
	}
	if strings.Contains(string(data), "conn-secret") ||
		strings.Contains(string(data), "password-hash") ||
		strings.Contains(string(data), "resumeToken") {
		t.Fatalf("retained record leaked credentials: %s", data)
	}
	info, err := os.Stat(path)
	if err != nil {
		t.Fatalf("stat retained room: %v", err)
	}
	if info.Mode().Perm() != 0o600 {
		t.Fatalf("retained mode = %o, want 600", info.Mode().Perm())
	}
	var record retainedRoom
	if err := json.Unmarshal(data, &record); err != nil {
		t.Fatalf("decode retained room: %v", err)
	}
	if !record.ExpiresAt.Equal(now.Add(time.Hour)) {
		t.Fatalf("expiresAt = %v", record.ExpiresAt)
	}
	replays, total, err := store.list(now, 0, 50)
	if err != nil {
		t.Fatalf("list retained replays: %v", err)
	}
	if total != 1 || len(replays) != 1 || replays[0].RoomName != "Private match" ||
		replays[0].LogEntryCount != 1 ||
		len(replays[0].Players) != 1 ||
		replays[0].Players[0] != "Alice" {
		t.Fatalf("public replay summaries = %+v", replays)
	}
	loaded, err := store.load(replays[0].ReplayID, now)
	if err != nil {
		t.Fatalf("load retained replay: %v", err)
	}
	publicData, err := json.Marshal(loaded)
	if err != nil {
		t.Fatalf("encode public replay: %v", err)
	}
	if strings.Contains(string(publicData), "secret-card") ||
		strings.Contains(string(publicData), "Lightning Bolt") ||
		strings.Contains(string(publicData), "mainboard") ||
		!strings.Contains(string(publicData), "opening_hand") {
		t.Fatalf("public replay leaked hidden state or omitted log: %s", publicData)
	}
	if _, err := store.load("../"+replays[0].ReplayID, now); err == nil {
		t.Fatal("path-traversal replay id was accepted")
	}
	if err := store.cleanup(now.Add(time.Hour)); err != nil {
		t.Fatalf("cleanup retained room: %v", err)
	}
	entries, err = os.ReadDir(directory)
	if err != nil || len(entries) != 0 {
		t.Fatalf("entries after cleanup=%v err=%v", entries, err)
	}
}

func TestRetentionRemovesAbandonedTemporaryFiles(t *testing.T) {
	now := time.Date(2026, time.August, 5, 10, 0, 0, 0, time.UTC)
	directory := t.TempDir()
	temporaryPath := filepath.Join(directory, ".retained-abandoned.tmp")
	if err := os.WriteFile(temporaryPath, []byte("partial"), 0o600); err != nil {
		t.Fatalf("write abandoned temporary file: %v", err)
	}
	if _, err := newRetentionStore(directory, time.Hour, 10, 1<<20, now); err != nil {
		t.Fatalf("new retention store: %v", err)
	}
	if _, err := os.Stat(temporaryPath); !errors.Is(err, os.ErrNotExist) {
		t.Fatalf("abandoned temporary file still exists: %v", err)
	}
}

func TestRetentionEnforcesFileQuotaAndPaginates(t *testing.T) {
	now := time.Date(2026, time.August, 5, 10, 0, 0, 0, time.UTC)
	store, err := newRetentionStore(t.TempDir(), time.Hour, 2, 1<<20, now)
	if err != nil {
		t.Fatalf("new retention store: %v", err)
	}
	for index := 0; index < 3; index++ {
		r, err := room.New(
			"ROOM"+strconv.Itoa(index), "Room "+strconv.Itoa(index), protocol.FormatModern,
			protocol.MatchBO1, protocol.CardLoadPreload, 2, true, false,
			"Alice", "conn", now)
		if err != nil {
			t.Fatalf("new room %d: %v", index, err)
		}
		r.Game = &room.GameState{
			Number: 1,
			Seats:  []room.PlayerGameState{{Seat: 0, DisplayName: "Alice"}},
			Log: []protocol.GameLogEntry{{
				ID: 1, Kind: "test", Seat: 0, Text: "entry " + strconv.Itoa(index),
			}},
		}
		if err := store.save(r, now.Add(time.Duration(index)*time.Second)); err != nil {
			t.Fatalf("save room %d: %v", index, err)
		}
	}
	entries, err := os.ReadDir(store.dir)
	if err != nil {
		t.Fatalf("read retention directory: %v", err)
	}
	if len(entries) != 2 {
		t.Fatalf("retained files = %d, want 2", len(entries))
	}
	first, total, err := store.list(now.Add(3*time.Second), 0, 1)
	if err != nil {
		t.Fatalf("list first page: %v", err)
	}
	if total != 2 || len(first) != 1 || first[0].RoomName != "Room 2" {
		t.Fatalf("first page = %+v total=%d", first, total)
	}
	second, total, err := store.list(now.Add(3*time.Second), 1, 1)
	if err != nil {
		t.Fatalf("list second page: %v", err)
	}
	if total != 2 || len(second) != 1 || second[0].RoomName != "Room 1" {
		t.Fatalf("second page = %+v total=%d", second, total)
	}
}

func TestRetentionEnforcesAggregateByteQuota(t *testing.T) {
	now := time.Date(2026, time.August, 5, 10, 0, 0, 0, time.UTC)
	directory := t.TempDir()
	store, err := newRetentionStore(directory, time.Hour, 10, 1<<20, now)
	if err != nil {
		t.Fatalf("new retention store: %v", err)
	}
	newRecord := func(roomID string, savedAt time.Time) *retainedRoom {
		return &retainedRoom{
			SchemaVersion: 1,
			SavedAt:       savedAt,
			ExpiresAt:     savedAt.Add(time.Hour),
			RoomID:        roomID,
			Name:          "Room " + roomID,
			Format:        protocol.FormatModern,
			MatchMode:     protocol.MatchBO1,
			Seats:         []retainedSeat{{DisplayName: "Alice"}},
			Score:         []int{0, 0},
			Game: &room.GameState{
				Number: 1,
				Seats:  []room.PlayerGameState{{Seat: 0, DisplayName: "Alice"}},
			},
		}
	}
	first := newRecord("FIRST", now)
	second := newRecord("SECOND", now.Add(time.Second))
	firstBytes, err := json.MarshalIndent(first, "", "  ")
	if err != nil {
		t.Fatalf("encode first retained room: %v", err)
	}
	secondBytes, err := json.MarshalIndent(second, "", "  ")
	if err != nil {
		t.Fatalf("encode second retained room: %v", err)
	}
	store.maxBytes = int64(len(firstBytes) + len(secondBytes) + 1)
	if err := store.saveSnapshot(first); err != nil {
		t.Fatalf("save first retained room: %v", err)
	}
	if err := store.saveSnapshot(second); err != nil {
		t.Fatalf("save second retained room: %v", err)
	}
	entries, err := os.ReadDir(directory)
	if err != nil {
		t.Fatalf("read retention directory: %v", err)
	}
	if len(entries) != 1 || !strings.HasPrefix(entries[0].Name(), "SECOND-") {
		t.Fatalf("byte quota retained files = %+v, want only newest", entries)
	}
}

func TestRetentionRejectsOversizedSnapshot(t *testing.T) {
	now := time.Date(2026, time.August, 5, 10, 0, 0, 0, time.UTC)
	store, err := newRetentionStore(t.TempDir(), time.Hour, 10, 256, now)
	if err != nil {
		t.Fatalf("new retention store: %v", err)
	}
	r, err := room.New(
		"ABCDEF", strings.Repeat("room", 40), protocol.FormatModern,
		protocol.MatchBO1, protocol.CardLoadPreload, 2, true, false,
		"Alice", "conn", now)
	if err != nil {
		t.Fatalf("new room: %v", err)
	}
	r.Game = &room.GameState{
		Number: 1,
		Seats:  []room.PlayerGameState{{Seat: 0, DisplayName: "Alice"}},
		Log: []protocol.GameLogEntry{{
			ID: 1, Kind: "large", Seat: 0, Text: strings.Repeat("x", 512),
		}},
	}
	if err := store.save(r, now); err == nil || !strings.Contains(err.Error(), "byte limit") {
		t.Fatalf("oversized snapshot err = %v", err)
	}
}

func TestRetainedReplayDoesNotLeakFaceDownCounterIdentity(t *testing.T) {
	now := time.Date(2026, time.August, 5, 10, 0, 0, 0, time.UTC)
	store, err := newRetentionStore(t.TempDir(), time.Hour, 10, 1<<20, now)
	if err != nil {
		t.Fatalf("new retention store: %v", err)
	}
	r, err := room.New(
		"ABCDEF", "Private", protocol.FormatModern, protocol.MatchBO1,
		protocol.CardLoadPreload, 2, true, false, "Alice", "host", now)
	if err != nil {
		t.Fatalf("new room: %v", err)
	}
	r.Phase = protocol.RoomPhaseStarted
	r.Game = &room.GameState{
		Number: 1,
		Seats: []room.PlayerGameState{{
			Seat: 0, DisplayName: "Alice",
			Battlefield: []protocol.GameCard{{
				ID: "secret", Name: "Demonic Tutor", OwnerSeat: 0, FaceDown: true,
			}},
		}},
		NextLogID:         1,
		NextCardCounterID: 1,
	}
	value := 1
	if _, err := r.SetCardCounter("host", protocol.GameSetCardCounter{
		CardID: "secret", Kind: protocol.CardCounterKindAbility,
		Label: "Manifest", Value: &value,
	}); err != nil {
		t.Fatalf("set counter: %v", err)
	}
	if err := store.save(r, now); err != nil {
		t.Fatalf("save replay: %v", err)
	}
	replays, _, err := store.list(now, 0, 10)
	if err != nil || len(replays) != 1 {
		t.Fatalf("list replay: %+v err=%v", replays, err)
	}
	loaded, err := store.load(replays[0].ReplayID, now)
	if err != nil {
		t.Fatalf("load replay: %v", err)
	}
	encoded, err := json.Marshal(loaded)
	if err != nil {
		t.Fatalf("marshal replay: %v", err)
	}
	if strings.Contains(string(encoded), "Demonic Tutor") ||
		!strings.Contains(string(encoded), "a face-down card") {
		t.Fatalf("replay leaked face-down identity: %s", encoded)
	}
}

func TestDecodeRetainedRoomRejectsTrailingDataAndInvalidSchema(t *testing.T) {
	now := time.Date(2026, time.August, 5, 12, 0, 0, 0, time.UTC)
	record := retainedRoomForValidationTest(now)
	encoded, err := json.Marshal(record)
	if err != nil {
		t.Fatalf("marshal retained room: %v", err)
	}
	for name, suffix := range map[string][]byte{
		"second JSON value": []byte("\n{}"),
		"trailing garbage":  []byte("\nnot-json"),
	} {
		t.Run(name, func(t *testing.T) {
			_, err := decodeRetainedRoom(append(append([]byte{}, encoded...), suffix...))
			if !errors.Is(err, errInvalidRetainedRoom) ||
				!strings.Contains(err.Error(), "trailing data") {
				t.Fatalf("decode error = %v", err)
			}
		})
	}

	record.SchemaVersion++
	encoded, err = json.Marshal(record)
	if err != nil {
		t.Fatalf("marshal unsupported retained room: %v", err)
	}
	if _, err := decodeRetainedRoom(encoded); !errors.Is(err, errInvalidRetainedRoom) ||
		!strings.Contains(err.Error(), "unsupported schema version") {
		t.Fatalf("unsupported schema error = %v", err)
	}
}

func TestRetentionRemovesInvalidFilesBeforeQuotaAccounting(t *testing.T) {
	now := time.Date(2026, time.August, 5, 12, 0, 0, 0, time.UTC)
	directory := t.TempDir()
	invalidPath := filepath.Join(directory, "broken.json")
	if err := os.WriteFile(invalidPath, []byte("{\"schemaVersion\":1"), 0o600); err != nil {
		t.Fatalf("write invalid retained room: %v", err)
	}

	store, err := newRetentionStore(directory, time.Hour, 1, 1<<20, now)
	if err != nil {
		t.Fatalf("new retention store: %v", err)
	}
	if _, err := os.Stat(invalidPath); !errors.Is(err, os.ErrNotExist) {
		t.Fatalf("invalid retained room still exists: %v", err)
	}

	record := retainedRoomForValidationTest(now)
	if err := store.saveSnapshot(&record); err != nil {
		t.Fatalf("save valid retained room: %v", err)
	}
	entries, err := os.ReadDir(directory)
	if err != nil {
		t.Fatalf("read retention directory: %v", err)
	}
	if len(entries) != 1 || filepath.Ext(entries[0].Name()) != ".json" {
		t.Fatalf("retained entries = %+v, want one valid JSON replay", entries)
	}
	replays, total, err := store.list(now, 0, 10)
	if err != nil || total != 1 || len(replays) != 1 ||
		replays[0].RoomName != record.Name {
		t.Fatalf("replays = %+v total=%d err=%v", replays, total, err)
	}
}

func TestRetentionListsCachedSummariesWithoutReadingArchives(t *testing.T) {
	now := time.Date(2026, time.August, 5, 12, 0, 0, 0, time.UTC)
	store, err := newRetentionStore(t.TempDir(), time.Hour, 10, 1<<20, now)
	if err != nil {
		t.Fatalf("new retention store: %v", err)
	}
	record := retainedRoomForValidationTest(now)
	if err := store.saveSnapshot(&record); err != nil {
		t.Fatalf("save retained room: %v", err)
	}
	replays, total, err := store.list(now, 0, 10)
	if err != nil || total != 1 || len(replays) != 1 {
		t.Fatalf("initial replays = %+v total=%d err=%v", replays, total, err)
	}
	replayID := replays[0].ReplayID
	if err := os.WriteFile(filepath.Join(store.dir, replayID), []byte("{broken"), 0o600); err != nil {
		t.Fatalf("corrupt retained archive: %v", err)
	}

	replays, total, err = store.list(now, 0, 10)
	if err != nil || total != 1 || len(replays) != 1 ||
		replays[0].ReplayID != replayID {
		t.Fatalf("cached replays = %+v total=%d err=%v", replays, total, err)
	}
	if _, err := store.load(replayID, now); !errors.Is(err, os.ErrNotExist) {
		t.Fatalf("load corrupt replay err = %v, want not exist", err)
	}
	replays, total, err = store.list(now, 0, 10)
	if err != nil || total != 0 || len(replays) != 0 {
		t.Fatalf("replays after invalid load = %+v total=%d err=%v", replays, total, err)
	}
}

func retainedRoomForValidationTest(now time.Time) retainedRoom {
	return retainedRoom{
		SchemaVersion: retainedRoomSchemaVersion,
		SavedAt:       now,
		ExpiresAt:     now.Add(time.Hour),
		RoomID:        "VALID1",
		Name:          "Valid replay",
		Format:        protocol.FormatModern,
		MatchMode:     protocol.MatchBO1,
		Seats:         []retainedSeat{{DisplayName: "Alice"}},
		Score:         []int{0},
		Game: &room.GameState{
			Number: 1,
			Seats:  []room.PlayerGameState{{Seat: 0, DisplayName: "Alice"}},
		},
	}
}
