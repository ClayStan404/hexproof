// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package server

import (
	"crypto/subtle"
	"encoding/hex"
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"time"

	"hexproof/server/internal/protocol"
	"hexproof/server/internal/room"
)

type accountReplayIndex struct {
	Grant      protocol.ForgeReplayGrant `json:"grant"`
	AccountIDs [2]string                 `json:"accountIds"`
	Tokens     [2]string                 `json:"tokens"`
}

func (s *forgeReplayStore) saveAccountIndex(record *forgeRecording) error {
	if !record.Grant.Finished {
		return nil
	}
	raw, err := json.Marshal(accountReplayIndex{Grant: record.Grant, AccountIDs: record.AccountIDs, Tokens: record.Tokens})
	if err != nil {
		return err
	}
	dir := filepath.Join(s.config.RetentionDir, "forge")
	f, err := os.CreateTemp(dir, ".owners-*")
	if err != nil {
		return err
	}
	defer os.Remove(f.Name())
	if _, err = f.Write(raw); err == nil {
		err = f.Sync()
	}
	if closeErr := f.Close(); err == nil {
		err = closeErr
	}
	if err != nil {
		return err
	}
	return os.Rename(f.Name(), filepath.Join(dir, record.Grant.ReplayID+".owners.json"))
}

func (s *forgeReplayStore) readAccountIndex(id string) (accountReplayIndex, error) {
	var result accountReplayIndex
	if len(id) != 64 {
		return result, os.ErrNotExist
	}
	if _, err := hex.DecodeString(id); err != nil {
		return result, os.ErrNotExist
	}
	path := filepath.Join(s.config.RetentionDir, "forge", id+".owners.json")
	info, err := os.Stat(path)
	if err != nil {
		return result, err
	}
	if !info.Mode().IsRegular() || info.Size() > 16384 {
		return result, errors.New("invalid replay ownership index")
	}
	raw, err := os.ReadFile(path)
	if err != nil {
		return result, err
	}
	if json.Unmarshal(raw, &result) != nil || result.Grant.ReplayID != id {
		return accountReplayIndex{}, errors.New("invalid replay ownership index")
	}
	return result, nil
}

func (s *forgeReplayStore) bindAccount(r *room.Room, connectionID, accountID string) {
	if s == nil || accountID == "" {
		return
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	if record := s.active[r]; record != nil {
		for seat, owner := range record.Owners {
			if owner == connectionID && record.AccountIDs[seat] == "" {
				record.AccountIDs[seat] = accountID
				if err := s.saveAccountIndex(record); err != nil {
					record.AccountIDs[seat] = ""
				}
			}
		}
	}
}

func (h *Handler) claimAccountReplay(accountID, id, token string) bool {
	s := h.forgeReplays
	if s == nil || len(token) != 64 {
		return false
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	record, err := s.load(id)
	if err != nil || !record.Grant.Finished {
		return false
	}
	expires, _ := time.Parse(time.RFC3339, record.Grant.ExpiresAt)
	if !time.Now().Before(expires) {
		return false
	}
	for seat, candidate := range record.Tokens {
		if subtle.ConstantTimeCompare([]byte(token), []byte(candidate)) != 1 {
			continue
		}
		if record.AccountIDs[seat] != "" {
			return record.AccountIDs[seat] == accountID
		}
		record.AccountIDs[seat] = accountID
		if err := s.saveAccountIndex(record); err != nil {
			record.AccountIDs[seat] = ""
			return false
		}
		return true
	}
	return false
}

func (h *Handler) accountReplays(accountID string, offset int) ([]protocol.ForgeReplayGrant, bool) {
	result := []protocol.ForgeReplayGrant{}
	s := h.forgeReplays
	if s == nil || s.config.RetentionDir == "" || accountID == "" {
		return result, false
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	dir := filepath.Join(s.config.RetentionDir, "forge")
	entries, err := os.ReadDir(dir)
	if err != nil {
		return result, false
	}
	for _, entry := range entries {
		if !strings.HasSuffix(entry.Name(), ".owners.json") {
			continue
		}
		id := strings.TrimSuffix(entry.Name(), ".owners.json")
		index, err := s.readAccountIndex(id)
		if err != nil || !index.Grant.Finished {
			continue
		}
		expires, _ := time.Parse(time.RFC3339, index.Grant.ExpiresAt)
		if !time.Now().Before(expires) {
			continue
		}
		if _, err := os.Stat(filepath.Join(dir, id+".json.gz")); err != nil {
			continue
		}
		for seat, owner := range index.AccountIDs {
			if owner == accountID {
				grant := index.Grant
				grant.Token = index.Tokens[seat]
				result = append(result, grant)
				break
			}
		}
	}
	sort.Slice(result, func(i, j int) bool { return result[i].ReplayID < result[j].ReplayID })
	if offset > len(result) {
		offset = len(result)
	}
	end := min(offset+32, len(result))
	return result[offset:end], end < len(result)
}
