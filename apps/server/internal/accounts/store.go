// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

// Package accounts owns the official service's durable passwordless identities.
// Gameplay state and permissions remain with the hub that owns each resource.
package accounts

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"crypto/subtle"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"sync"
	"time"
	"unicode"
	"unicode/utf8"
)

var (
	ErrInvalid = errors.New("invalid account credential or request")
	ErrLimit   = errors.New("account capacity reached")
)

const (
	MaxAccounts     = 100000
	MaxSessions     = 16
	SessionLifetime = 90 * 24 * time.Hour
	maxRecordBytes  = 32 << 10
)

type Profile struct {
	ID        string `json:"id"`
	Name      string `json:"name"`
	CreatedAt string `json:"createdAt"`
}

type Device struct {
	ID        string `json:"id"`
	Name      string `json:"name"`
	CreatedAt string `json:"createdAt"`
	ExpiresAt string `json:"expiresAt"`
}

// Request is internal to trusted hubs; it is never decoded from a game message.
type Request struct {
	Operation    string `json:"operation"`
	Name         string `json:"name,omitempty"`
	DeviceName   string `json:"deviceName,omitempty"`
	LoginCode    string `json:"loginCode,omitempty"`
	RecoveryCode string `json:"recoveryCode,omitempty"`
	SessionToken string `json:"sessionToken,omitempty"`
	SessionID    string `json:"sessionId,omitempty"`
}

type Result struct {
	Profile      Profile  `json:"profile"`
	SessionID    string   `json:"sessionId,omitempty"`
	SessionToken string   `json:"sessionToken,omitempty"`
	LoginCode    string   `json:"loginCode,omitempty"`
	RecoveryCode string   `json:"recoveryCode,omitempty"`
	Devices      []Device `json:"devices,omitempty"`
}

type Service interface {
	Do(context.Context, Request) (Result, error)
}

type deviceRecord struct {
	Device Device `json:"device"`
	Hash   string `json:"hash"`
}

type record struct {
	Version      int            `json:"version"`
	Profile      Profile        `json:"profile"`
	LoginHash    string         `json:"loginHash"`
	RecoveryHash string         `json:"recoveryHash"`
	Devices      []deviceRecord `json:"devices"`
}

type Store struct {
	mu      sync.Mutex
	dir     string
	lock    *os.File
	records map[string]record
	now     func() time.Time
}

func Open(dir string) (*Store, error) {
	if dir == "" {
		return nil, ErrInvalid
	}
	if err := os.MkdirAll(dir, 0700); err != nil {
		return nil, err
	}
	if err := os.Chmod(dir, 0700); err != nil {
		return nil, err
	}
	lock, err := lockDirectory(dir)
	if err != nil {
		return nil, err
	}
	s := &Store{dir: dir, lock: lock, records: make(map[string]record), now: time.Now}
	entries, err := os.ReadDir(dir)
	if err != nil {
		s.Close()
		return nil, err
	}
	for _, entry := range entries {
		if !strings.HasSuffix(entry.Name(), ".json") {
			continue
		}
		id := strings.TrimSuffix(entry.Name(), ".json")
		info, statErr := entry.Info()
		if !validID(id) || statErr != nil || !info.Mode().IsRegular() || info.Size() > maxRecordBytes {
			s.Close()
			return nil, fmt.Errorf("invalid account record")
		}
		raw, readErr := os.ReadFile(filepath.Join(dir, entry.Name()))
		var r record
		if readErr != nil || json.Unmarshal(raw, &r) != nil || r.Version != 1 || r.Profile.ID != id ||
			!validText(r.Profile.Name, 64) || !validHash(r.LoginHash) || !validHash(r.RecoveryHash) || len(r.Devices) > MaxSessions {
			s.Close()
			return nil, fmt.Errorf("invalid account record")
		}
		for _, d := range r.Devices {
			if !validID(d.Device.ID) || !validHash(d.Hash) {
				s.Close()
				return nil, fmt.Errorf("invalid account session record")
			}
		}
		s.records[id] = r
		if len(s.records) > MaxAccounts {
			s.Close()
			return nil, ErrLimit
		}
	}
	return s, nil
}

func (s *Store) Close() error {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.lock == nil {
		return nil
	}
	err := s.lock.Close()
	s.lock = nil
	return err
}

func validID(value string) bool {
	if len(value) != 32 {
		return false
	}
	_, err := hex.DecodeString(value)
	return err == nil && strings.ToLower(value) == value
}

func validHash(value string) bool {
	if len(value) != sha256.Size*2 {
		return false
	}
	_, err := hex.DecodeString(value)
	return err == nil
}

func validText(value string, limit int) bool {
	if !utf8.ValidString(value) || value == "" || strings.TrimSpace(value) != value || utf8.RuneCountInString(value) > limit {
		return false
	}
	for _, r := range value {
		if unicode.IsControl(r) || unicode.In(r, unicode.Cf, unicode.Zl, unicode.Zp) {
			return false
		}
	}
	return true
}

func randomID() string { var b [16]byte; rand.Read(b[:]); return hex.EncodeToString(b[:]) }
func secret(prefix, id string) string {
	var b [32]byte
	rand.Read(b[:])
	return prefix + "." + id + "." + base64.RawURLEncoding.EncodeToString(b[:])
}
func digest(value string) string { h := sha256.Sum256([]byte(value)); return hex.EncodeToString(h[:]) }
func matches(value, hash string) bool {
	return subtle.ConstantTimeCompare([]byte(digest(value)), []byte(hash)) == 1
}

func credentialID(value, prefix string) string {
	parts := strings.Split(value, ".")
	if len(parts) != 3 || parts[0] != prefix || !validID(parts[1]) || len(parts[2]) != 43 {
		return ""
	}
	b, err := base64.RawURLEncoding.DecodeString(parts[2])
	if err != nil || len(b) != 32 {
		return ""
	}
	return parts[1]
}

func (s *Store) Do(_ context.Context, q Request) (Result, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.lock == nil {
		return Result{}, errors.New("account store closed")
	}
	now := s.now().UTC()
	var r record
	var out Result
	var currentID string
	var ok bool
	switch q.Operation {
	case "create":
		if !validText(q.Name, 64) {
			return out, ErrInvalid
		}
		if len(s.records) >= MaxAccounts {
			return out, ErrLimit
		}
		r = record{Version: 1, Profile: Profile{ID: randomID(), Name: q.Name, CreatedAt: now.Format(time.RFC3339)}}
		out.LoginCode = secret("HP1", r.Profile.ID)
		out.RecoveryCode = secret("HPR1", r.Profile.ID)
		r.LoginHash, r.RecoveryHash = digest(out.LoginCode), digest(out.RecoveryCode)
	case "login":
		r, ok = s.records[credentialID(q.LoginCode, "HP1")]
		if !ok || !matches(q.LoginCode, r.LoginHash) {
			return out, ErrInvalid
		}
	case "recover":
		r, ok = s.records[credentialID(q.RecoveryCode, "HPR1")]
		if !ok || !matches(q.RecoveryCode, r.RecoveryHash) {
			return out, ErrInvalid
		}
		out.LoginCode = secret("HP1", r.Profile.ID)
		out.RecoveryCode = secret("HPR1", r.Profile.ID)
		r.LoginHash, r.RecoveryHash = digest(out.LoginCode), digest(out.RecoveryCode)
		r.Devices = nil
	default:
		r, ok = s.records[credentialID(q.SessionToken, "HPS1")]
		if !ok {
			return out, ErrInvalid
		}
		for _, d := range r.Devices {
			expires, _ := time.Parse(time.RFC3339, d.Device.ExpiresAt)
			if now.Before(expires) && matches(q.SessionToken, d.Hash) {
				currentID = d.Device.ID
				break
			}
		}
		if currentID == "" {
			return out, ErrInvalid
		}
	}
	// Copy slices before a mutation: a failed durable write must not alter memory.
	live := make([]deviceRecord, 0, len(r.Devices))
	for _, d := range r.Devices {
		expires, _ := time.Parse(time.RFC3339, d.Device.ExpiresAt)
		if now.Before(expires) {
			live = append(live, d)
		}
	}
	r.Devices = live
	switch q.Operation {
	case "create", "login", "recover":
		if !validText(q.DeviceName, 80) {
			return Result{}, ErrInvalid
		}
		out.SessionToken = secret("HPS1", r.Profile.ID)
		currentID = randomID()
		if len(r.Devices) >= MaxSessions {
			r.Devices = r.Devices[len(r.Devices)-MaxSessions+1:]
		}
		r.Devices = append(r.Devices, deviceRecord{Device: Device{ID: currentID, Name: q.DeviceName,
			CreatedAt: now.Format(time.RFC3339), ExpiresAt: now.Add(SessionLifetime).Format(time.RFC3339)}, Hash: digest(out.SessionToken)})
	case "check", "status":
	case "rename":
		if !validText(q.Name, 64) {
			return out, ErrInvalid
		}
		r.Profile.Name = q.Name
	case "rotate":
		out.LoginCode = secret("HP1", r.Profile.ID)
		r.LoginHash = digest(out.LoginCode)
		r.Devices = retainDevices(r.Devices, currentID, true)
	case "revoke":
		if !validID(q.SessionID) {
			return out, ErrInvalid
		}
		r.Devices = retainDevices(r.Devices, q.SessionID, false)
	case "revoke_others":
		r.Devices = retainDevices(r.Devices, currentID, true)
	case "logout":
		r.Devices = retainDevices(r.Devices, currentID, false)
	default:
		return out, ErrInvalid
	}
	if q.Operation != "check" && q.Operation != "status" {
		if err := s.save(r); err != nil {
			return Result{}, err
		}
		s.records[r.Profile.ID] = r
	}
	out.Profile, out.SessionID = r.Profile, currentID
	out.Devices = make([]Device, 0, len(r.Devices))
	for _, d := range r.Devices {
		out.Devices = append(out.Devices, d.Device)
	}
	sort.Slice(out.Devices, func(i, j int) bool { return out.Devices[i].CreatedAt > out.Devices[j].CreatedAt })
	return out, nil
}

func retainDevices(devices []deviceRecord, id string, keep bool) []deviceRecord {
	result := make([]deviceRecord, 0, len(devices))
	for _, d := range devices {
		if (d.Device.ID == id) == keep {
			result = append(result, d)
		}
	}
	return result
}

func (s *Store) save(r record) error {
	raw, err := json.Marshal(r)
	if err != nil {
		return err
	}
	file, err := os.CreateTemp(s.dir, ".account-*")
	if err != nil {
		return err
	}
	defer os.Remove(file.Name())
	if _, err = file.Write(raw); err == nil {
		err = file.Sync()
	}
	if closeErr := file.Close(); err == nil {
		err = closeErr
	}
	if err != nil {
		return err
	}
	return os.Rename(file.Name(), filepath.Join(s.dir, r.Profile.ID+".json"))
}
