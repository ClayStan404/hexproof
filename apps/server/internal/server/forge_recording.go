// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package server

import (
	"compress/gzip"
	"context"
	"crypto/rand"
	"crypto/subtle"
	"encoding/hex"
	"encoding/json"
	"errors"
	"io"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"sync"
	"time"

	"hexproof/server/internal/protocol"
	"hexproof/server/internal/room"
	"hexproof/server/internal/rulesengine/forge"
)

const maxForgeReplayBytes = 128 << 20
const maxForgeReplayFrameBytes = 512 << 10

type forgeRecording struct {
	Grant          protocol.ForgeReplayGrant   `json:"grant"`
	Tokens         [2]string                   `json:"tokens"`
	Owners         [2]string                   `json:"-"`
	Frames         []protocol.ForgeReplayFrame `json:"frames"`
	Bytes          int                         `json:"-"`
	GameID         string                      `json:"-"`
	GameNumber     int                         `json:"-"`
	NativeSequence int64                       `json:"-"`
	LastTime       int64                       `json:"-"`
	TimeOffset     int64                       `json:"-"`
	Granted        map[string]bool             `json:"-"`
}

type forgeReplayStore struct {
	mu        sync.Mutex
	config    Config
	active    map[*room.Room]*forgeRecording
	completed map[string]*forgeRecording
	bytes     int64
}

func newForgeReplayStore(config Config) *forgeReplayStore {
	return &forgeReplayStore{config: config, active: make(map[*room.Room]*forgeRecording), completed: make(map[string]*forgeRecording)}
}

func replaySecret() string {
	var value [32]byte
	if _, err := rand.Read(value[:]); err != nil {
		return ""
	}
	return hex.EncodeToString(value[:])
}

func (h *Handler) collectForgeReplay(r *room.Room, game forgeRoomGame) {
	s := h.forgeReplays
	if s == nil || s.config.RetentionDir == "" || len(r.Seats) != 2 {
		return
	}
	source, ok := game.client.(forge.ReplaySource)
	if !ok {
		return
	}
	s.mu.Lock()
	record := s.active[r]
	if record != nil && record.Grant.Finished && record.GameID != game.gameID {
		delete(s.active, r)
		record = nil
	}
	after := int64(0)
	if record != nil && record.GameID == game.gameID {
		after = record.NativeSequence
	}
	s.mu.Unlock()
	ctx, cancel := context.WithTimeout(context.Background(), runtimeTimeout(game.client, forgeSnapshotTimeout))
	batch, err := source.Replay(ctx, game.sessionID, after)
	cancel()
	if batch == nil && err == nil {
		return
	} // Older runtimes keep ordinary play available.
	s.mu.Lock()
	defer s.mu.Unlock()
	if record == nil {
		record = &forgeRecording{Granted: make(map[string]bool)}
		record.Grant = protocol.ForgeReplayGrant{ReplayID: replaySecret(), RoomName: r.Name, Format: r.Format,
			MatchMode: r.MatchMode, Complete: true, Players: []string{}, ExpiresAt: time.Now().Add(s.config.RetentionTTL).UTC().Format(time.RFC3339)}
		record.Tokens = [2]string{replaySecret(), replaySecret()}
		if record.Grant.ReplayID == "" || record.Tokens[0] == "" || record.Tokens[1] == "" {
			return
		}
		for index, player := range r.Seats {
			record.Grant.Players = append(record.Grant.Players, player.DisplayName)
			if index < 2 {
				record.Owners[index] = player.ConnectionID
			}
		}
		s.active[r] = record
	}
	if err != nil || batch == nil {
		record.Grant.Complete = false
		return
	}
	if record.GameID != game.gameID {
		record.GameID = game.gameID
		record.NativeSequence = 0
		record.TimeOffset = record.LastTime
		record.GameNumber = r.DrawnGames + 1
		for _, wins := range r.Score {
			record.GameNumber += wins
		}
	}
	if !batch.Complete {
		record.Grant.Complete = false
	}
	for _, native := range batch.Frames {
		if native.Sequence <= record.NativeSequence {
			continue
		}
		if native.Sequence != record.NativeSequence+1 {
			record.Grant.Complete = false
		}
		record.NativeSequence = native.Sequence
		view, err := forge.DecodeSnapshotView(native.View)
		if err != nil {
			record.Grant.Complete = false
			continue
		}
		snapshot, err := normalizeForgeSnapshot(r.ID, game, view)
		if err != nil {
			record.Grant.Complete = false
			continue
		}
		actor := -1
		if seat, ok := game.playerToSeat[native.Actor]; ok {
			actor = seat
		}
		elapsed := native.ElapsedMS + record.TimeOffset
		if elapsed < record.LastTime {
			elapsed = record.LastTime
		}
		frame := protocol.ForgeReplayFrame{Sequence: int64(len(record.Frames) + 1), ElapsedMS: elapsed, GameNumber: record.GameNumber,
			Kind: native.Kind, ActorSeat: actor, Text: native.Text, Snapshot: snapshot, Combat: []protocol.ForgeReplayRelation{}}
		for _, relation := range native.Combat {
			if relation.Kind != "attack" && relation.Kind != "block" {
				continue
			}
			entry := protocol.ForgeReplayRelation{Kind: relation.Kind, SourceID: relation.SourceID, TargetID: relation.TargetID}
			if relation.TargetPlayer != nil {
				if seat, ok := game.playerToSeat[*relation.TargetPlayer]; ok {
					entry.TargetSeat = &seat
				}
			}
			frame.Combat = append(frame.Combat, entry)
		}
		encoded, encodeErr := json.Marshal(frame)
		if s.bytes+int64(len(encoded)) > s.config.RetentionMaxBytes {
			// Completed files remain downloadable on disk. Bound in-memory
			// history independently of compression ratios and room lifetime.
			for id, cached := range s.completed {
				for room, active := range s.active {
					if active == cached {
						delete(s.active, room)
					}
				}
				s.bytes -= int64(cached.Bytes)
				delete(s.completed, id)
			}
		}
		if encodeErr != nil || len(encoded) > maxForgeReplayFrameBytes || len(record.Frames) >= 20000 ||
			record.Bytes+len(encoded) > maxForgeReplayBytes-(1<<20) || s.bytes+int64(len(encoded)) > s.config.RetentionMaxBytes {
			record.Grant.Complete = false
			continue
		}
		record.Frames = append(record.Frames, frame)
		record.Bytes += len(encoded)
		s.bytes += int64(len(encoded))
		record.LastTime = elapsed
	}
	if batch.LastSequence > record.NativeSequence {
		record.Grant.Complete = false
		record.NativeSequence = batch.LastSequence
	}
	record.Grant.FrameCount = len(record.Frames)
}

// Caller holds the room operation lock; the result gate is the whole match.
func (h *Handler) publishForgeReplay(r *room.Room) {
	s := h.forgeReplays
	if s == nil {
		return
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	record := s.active[r]
	if record == nil {
		return
	}
	finished := r.Game != nil && r.Game.Result != nil && r.Game.Result.MatchFinished
	newlyFinished := finished && !record.Grant.Finished
	if newlyFinished {
		record.Grant.Finished = true
		record.Grant.ExpiresAt = time.Now().Add(s.config.RetentionTTL).UTC().Format(time.RFC3339)
		if err := s.save(record); err != nil {
			record.Grant.Complete = false
		}
		s.completed[record.Grant.ReplayID] = record
	}
	for _, sess := range h.sessionsForRoomPointer(r) {
		seat := r.FindSeatByConnection(sess.ConnectionID)
		if seat < 0 || seat >= len(record.Tokens) {
			continue
		}
		if record.Owners[seat] != sess.ConnectionID {
			continue
		}
		if record.Granted[sess.ConnectionID] && !newlyFinished {
			continue
		}
		grant := record.Grant
		grant.Token = record.Tokens[seat]
		envelope, _ := protocol.NewEnvelope(protocol.TypeForgeReplayGrant, grant)
		h.send(sess, envelope)
		record.Granted[sess.ConnectionID] = true
	}
}

func (s *forgeReplayStore) discard(roomID string) {
	if s == nil {
		return
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	for r, record := range s.active {
		if r.ID == roomID {
			delete(s.active, r)
			s.bytes -= int64(record.Bytes)
			delete(s.completed, record.Grant.ReplayID)
		}
	}
}

func (s *forgeReplayStore) rebind(r *room.Room, previous, current string) {
	if s == nil {
		return
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	if record := s.active[r]; record != nil {
		for seat, owner := range record.Owners {
			if owner == previous {
				record.Owners[seat] = current
			}
		}
	}
}

func (s *forgeReplayStore) save(record *forgeRecording) error {
	dir := filepath.Join(s.config.RetentionDir, "forge")
	if err := os.MkdirAll(dir, 0700); err != nil {
		return err
	}
	file, err := os.CreateTemp(dir, ".recording-*")
	if err != nil {
		return err
	}
	defer os.Remove(file.Name())
	zip := gzip.NewWriter(file)
	err = json.NewEncoder(zip).Encode(record)
	if closeErr := zip.Close(); err == nil {
		err = closeErr
	}
	if syncErr := file.Sync(); err == nil {
		err = syncErr
	}
	if closeErr := file.Close(); err == nil {
		err = closeErr
	}
	if err != nil {
		return err
	}
	if err := os.Rename(file.Name(), filepath.Join(dir, record.Grant.ReplayID+".json.gz")); err != nil {
		return err
	}
	return s.prune(dir)
}

func (s *forgeReplayStore) prune(dir string) error {
	files, err := os.ReadDir(dir)
	if err != nil {
		return err
	}
	type entry struct {
		path, id string
		size     int64
		modified time.Time
	}
	var entries []entry
	var total int64
	for _, file := range files {
		if file.IsDir() || !strings.HasSuffix(file.Name(), ".json.gz") {
			continue
		}
		info, err := file.Info()
		if err != nil {
			continue
		}
		entries = append(entries, entry{filepath.Join(dir, file.Name()), strings.TrimSuffix(file.Name(), ".json.gz"), info.Size(), info.ModTime()})
		total += info.Size()
	}
	sort.Slice(entries, func(i, j int) bool { return entries[i].modified.Before(entries[j].modified) })
	for index, file := range entries {
		if time.Since(file.modified) < s.config.RetentionTTL && len(entries)-index <= s.config.RetentionMaxFiles && total <= s.config.RetentionMaxBytes {
			break
		}
		if err := os.Remove(file.path); err != nil {
			return err
		}
		total -= file.size
		if cached := s.completed[file.id]; cached != nil {
			for r, active := range s.active {
				if active == cached {
					delete(s.active, r)
				}
			}
			s.bytes -= int64(cached.Bytes)
			delete(s.completed, file.id)
		}
	}
	return nil
}

func (s *forgeReplayStore) load(id string) (*forgeRecording, error) {
	if len(id) != 64 {
		return nil, os.ErrNotExist
	}
	if _, err := hex.DecodeString(id); err != nil {
		return nil, os.ErrNotExist
	}
	if record := s.completed[id]; record != nil {
		return record, nil
	}
	file, err := os.Open(filepath.Join(s.config.RetentionDir, "forge", id+".json.gz"))
	if err != nil {
		return nil, err
	}
	defer file.Close()
	zip, err := gzip.NewReader(file)
	if err != nil {
		return nil, err
	}
	defer zip.Close()
	var record forgeRecording
	raw, err := io.ReadAll(io.LimitReader(zip, maxForgeReplayBytes+1))
	if err != nil || len(raw) > maxForgeReplayBytes {
		return nil, errors.New("invalid Forge replay size")
	}
	err = json.Unmarshal(raw, &record)
	if err != nil || record.Grant.ReplayID != id || len(record.Frames) > 20000 {
		return nil, errors.New("invalid Forge replay")
	}
	record.Bytes = len(raw)
	if s.bytes+int64(record.Bytes) <= s.config.RetentionMaxBytes {
		s.completed[id] = &record
		s.bytes += int64(record.Bytes)
	}
	return &record, nil
}

func (h *Handler) handleForgeReplayGet(sess *Session, env protocol.Envelope) error {
	var request protocol.ForgeReplayGet
	if sess.DisplayName == "" || env.DecodePayload(&request) != nil || request.Offset < 0 || len(request.Token) != 64 || h.forgeReplays == nil {
		h.sendError(sess, env.ID, protocol.ErrReplayNotFound, "Replay is unavailable")
		return nil
	}
	s := h.forgeReplays
	s.mu.Lock()
	// Charge new downloads and uncached disk reads, while allowing a bounded
	// recording to stream through multiple pages without the public-list quota.
	if (request.Offset == 0 || s.completed[request.ReplayID] == nil) && !h.allowReplayRequest(sess.RemoteIP, time.Now().UTC()) {
		s.mu.Unlock()
		h.sendError(sess, env.ID, protocol.ErrRateLimited, "Replay request rate limit exceeded")
		return nil
	}
	record, err := s.load(request.ReplayID)
	if err != nil || record == nil || !record.Grant.Finished {
		s.mu.Unlock()
		h.sendError(sess, env.ID, protocol.ErrReplayNotFound, "Replay is unavailable until the match finishes")
		return nil
	}
	expires, _ := time.Parse(time.RFC3339, record.Grant.ExpiresAt)
	authorized := subtle.ConstantTimeCompare([]byte(request.Token), []byte(record.Tokens[0])) | subtle.ConstantTimeCompare([]byte(request.Token), []byte(record.Tokens[1]))
	if authorized != 1 || !time.Now().Before(expires) || request.Offset > len(record.Frames) {
		s.mu.Unlock()
		h.sendError(sess, env.ID, protocol.ErrReplayNotFound, "Replay is unavailable")
		return nil
	}
	page := protocol.ForgeReplayPage{ReplayID: request.ReplayID, SchemaVersion: 1, Offset: request.Offset,
		Total: len(record.Frames), Complete: record.Grant.Complete, Frames: []protocol.ForgeReplayFrame{}}
	bytes := 0
	for index := request.Offset; index < len(record.Frames) && len(page.Frames) < 64; index++ {
		frame := record.Frames[index]
		raw, _ := json.Marshal(frame)
		if bytes+len(raw) > 768<<10 && len(page.Frames) > 0 {
			break
		}
		page.Frames = append(page.Frames, frame)
		bytes += len(raw)
	}
	s.mu.Unlock()
	reply, _ := protocol.NewEnvelope(protocol.TypeForgeReplayPage, page)
	reply.ID = env.ID
	h.send(sess, reply)
	return nil
}
