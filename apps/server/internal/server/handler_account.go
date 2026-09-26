// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package server

import (
	"context"
	"crypto/sha256"
	"errors"
	"net/http"
	"sort"
	"sync"
	"time"

	"hexproof/server/internal/accounts"
	"hexproof/server/internal/protocol"
	"hexproof/server/internal/tournament"
)

func configureAccounts(c Config) (accounts.Service, *accounts.Store, http.Handler, error) {
	if c.AccountDir == "" && c.AccountAuthority == "" {
		return nil, nil, nil, nil
	}
	if !accounts.ValidRealm(c.AccountRealm) || (c.AccountDir != "" && c.AccountAuthority != "") {
		return nil, nil, nil, errors.New("configure one account directory or authority and an account realm")
	}
	if c.AccountAuthority != "" {
		remote, err := accounts.NewRemote(c.AccountAuthority, c.AccountServiceKey, c.AccountRealm)
		return remote, nil, nil, err
	}
	store, err := accounts.Open(c.AccountDir)
	if err != nil {
		return nil, nil, nil, err
	}
	var api http.Handler
	if c.AccountServiceKey != "" {
		api, err = accounts.HTTPHandler(store, c.AccountServiceKey, c.AccountRealm)
		if err != nil {
			store.Close()
			return nil, nil, nil, err
		}
	}
	return store, store, api, nil
}

// ServeAccountAuthority is enabled only on the node that owns the account store.
func (h *Handler) ServeAccountAuthority(w http.ResponseWriter, r *http.Request) {
	if h.accountAPI == nil {
		http.NotFound(w, r)
		return
	}
	h.accountAPI.ServeHTTP(w, r)
}

func (h *Handler) accountLock(id string) *sync.Mutex {
	hash := sha256.Sum256([]byte(id))
	return &h.accountLocks[hash[0]]
}

func (h *Handler) accountRequest(q accounts.Request) (accounts.Result, error) {
	if h.accounts == nil {
		return accounts.Result{}, errors.New("accounts unavailable")
	}
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	return h.accounts.Do(ctx, q)
}

func (h *Handler) accountError(sess *Session, requestID string, err error) {
	code, message := protocol.ErrAccountUnavailable, "Account service is unavailable; retry later"
	if errors.Is(err, accounts.ErrInvalid) {
		code, message = protocol.ErrAccountInvalid, "Account credential is invalid or expired"
	}
	if errors.Is(err, accounts.ErrLimit) {
		code, message = protocol.ErrServerLimit, "Account capacity reached"
	}
	h.sendError(sess, requestID, code, message)
}

// The account gate precedes tournament/room locks. It serializes handover with
// every old connection's mutation; connection id remains the reducer's actor.
func (h *Handler) validateAccountSession(sess *Session, requestID string) bool {
	a := sess.Account()
	if a.ID == "" {
		return true
	}
	h.accountConnectionsMu.Lock()
	current := h.accountConnections[a.ID] == sess
	h.accountConnectionsMu.Unlock()
	if !current {
		h.accountError(sess, requestID, accounts.ErrInvalid)
		return false
	}
	out, err := h.accountRequest(accounts.Request{Operation: "check", SessionToken: a.Token})
	if err != nil || out.Profile.ID != a.ID {
		if err == nil {
			err = accounts.ErrInvalid
		}
		h.accountError(sess, requestID, err)
		return false
	}
	return true
}

func (h *Handler) bindAccountSession(sess *Session, out accounts.Result, token string) bool {
	aid := out.Profile.ID
	h.accountConnectionsMu.Lock()
	old := h.accountConnections[aid]
	h.accountConnectionsMu.Unlock()
	if sess.Room() != nil && ((old != nil && old != sess && old.Room() != nil) || h.accountResumeToken(aid, "") != "") {
		return false
	}
	// Adopt only the current event role. An account that already owns another
	// participant in this event cannot merge the guest seat into its identity.
	if binding := sess.Tournament(); binding.TournamentID != "" && binding.Role != tournament.RoleViewer {
		entry, err := h.tournaments.lockOperation(binding.TournamentID)
		if err != nil {
			return false
		}
		entry.mu.Lock()
		claimed := entry.event.ClaimConnectionAccount(sess.ConnectionID, aid)
		entry.mu.Unlock()
		entry.opMu.Unlock()
		if !claimed {
			return false
		}
	}
	if old != nil && old != sess {
		if r := old.Room(); r != nil {
			h.holdForReconnect(old, r)
		}
		h.sendError(old, "", protocol.ErrAccountReplaced, "This account was opened on another connection to this server")
		old.closeAfterSend()
	}
	sess.setAccount(accountBinding{ID: aid, Token: token, SessionID: out.SessionID})
	sess.DisplayName = out.Profile.Name
	h.accountConnectionsMu.Lock()
	h.accountConnections[aid] = sess
	h.accountConnectionsMu.Unlock()
	h.bindAccountResources(sess)
	return true
}

func (h *Handler) handleAccountCommand(sess *Session, env protocol.Envelope) error {
	if sess.DisplayName == "" || h.accounts == nil {
		h.accountError(sess, env.ID, errors.New("accounts unavailable"))
		return nil
	}
	var q protocol.AccountCommand
	if env.DecodePayload(&q) != nil || len(q.LoginCode) > 128 || len(q.RecoveryCode) > 128 ||
		len(q.Credential) > protocol.MaxResumeTokenBytes || len(q.Name) > 256 || len(q.DeviceName) > 320 ||
		len(q.ResourceID) > 128 || len(q.SessionID) > 64 || q.Offset < 0 || q.Offset > h.config.RetentionMaxFiles {
		h.accountError(sess, env.ID, accounts.ErrInvalid)
		return nil
	}
	a := sess.Account()
	var out accounts.Result
	var err error
	login := q.Operation == "create" || q.Operation == "login" || q.Operation == "recover" || q.Operation == "attach"
	if login {
		if a.ID != "" {
			h.sendError(sess, env.ID, protocol.ErrAccountConflict, "Sign out before changing accounts")
			return nil
		}
		// Recovery replaces both secrets and revokes every device. Reject a
		// possible guest-seat conflict before consuming that recovery code.
		binding := sess.Tournament()
		if q.Operation == "recover" && (sess.Room() != nil ||
			(binding.TournamentID != "" && binding.Role != tournament.RoleViewer)) {
			h.sendError(sess, env.ID, protocol.ErrAccountConflict, "Leave the current room or event before recovering an account")
			return nil
		}
		if !h.accountLimiter.allow(sess.RemoteIP, time.Now(), 12) ||
			(q.Operation == "create" && !h.accountCreateLimiter.allow(sess.RemoteIP, time.Now(), 5)) {
			h.sendError(sess, env.ID, protocol.ErrRateLimited, "Account request rate limit exceeded")
			return nil
		}
		if q.Operation == "attach" {
			out, err = h.accountRequest(accounts.Request{Operation: "check", SessionToken: q.Credential})
			out.SessionToken = q.Credential
		} else {
			out, err = h.accountRequest(accounts.Request{Operation: q.Operation, Name: q.Name, DeviceName: q.DeviceName,
				LoginCode: q.LoginCode, RecoveryCode: q.RecoveryCode})
		}
		if err != nil {
			h.accountError(sess, env.ID, err)
			return nil
		}
		gate := h.accountLock(out.Profile.ID)
		gate.Lock()
		defer gate.Unlock()
		if !h.bindAccountSession(sess, out, out.SessionToken) {
			if q.Operation != "attach" {
				_, _ = h.accountRequest(accounts.Request{Operation: "logout", SessionToken: out.SessionToken})
			}
			h.sendError(sess, env.ID, protocol.ErrAccountConflict, "Leave the current room before taking over another account seat")
			return nil
		}
	} else {
		if a.ID == "" {
			h.accountError(sess, env.ID, accounts.ErrInvalid)
			return nil
		}
		if (q.Operation == "replays" || (q.Operation == "claim" && q.Kind == "replay")) && !h.allowReplayRequest(sess.RemoteIP, time.Now().UTC()) {
			h.sendError(sess, env.ID, protocol.ErrRateLimited, "Replay request rate limit exceeded")
			return nil
		}
		switch q.Operation {
		case "status", "rotate", "rename", "revoke", "revoke_others", "logout":
			out, err = h.accountRequest(accounts.Request{Operation: q.Operation, Name: q.Name, SessionToken: a.Token, SessionID: q.SessionID})
		case "resume":
			if !h.resumeAccountRoom(sess, q.ResourceID) {
				h.sendError(sess, env.ID, protocol.ErrRoomNotFound, "No recoverable account seat")
				return nil
			}
			out, err = h.accountRequest(accounts.Request{Operation: "status", SessionToken: a.Token})
		case "claim":
			if !h.claimAccountResource(sess, q) {
				h.sendError(sess, env.ID, protocol.ErrAccountConflict, "The saved resource credential is unavailable or belongs to another account")
				return nil
			}
			out, err = h.accountRequest(accounts.Request{Operation: "status", SessionToken: a.Token})
		case "replays":
			out, err = h.accountRequest(accounts.Request{Operation: "status", SessionToken: a.Token})
		default:
			h.accountError(sess, env.ID, accounts.ErrInvalid)
			return nil
		}
		if err != nil {
			h.accountError(sess, env.ID, err)
			return nil
		}
	}
	state := protocol.AccountState{Operation: q.Operation, AccountID: out.Profile.ID, DisplayName: out.Profile.Name,
		SessionID: out.SessionID, SessionToken: out.SessionToken, LoginCode: out.LoginCode, RecoveryCode: out.RecoveryCode,
		Devices: []protocol.AccountDevice{}, Resources: h.accountVisibleResources(sess), Replays: []protocol.ForgeReplayGrant{}, Offset: q.Offset}
	for _, d := range out.Devices {
		state.Devices = append(state.Devices, protocol.AccountDevice{ID: d.ID, Name: d.Name,
			CreatedAt: d.CreatedAt, ExpiresAt: d.ExpiresAt, Current: d.ID == out.SessionID})
	}
	if q.Operation == "rename" {
		sess.DisplayName = out.Profile.Name
	}
	if q.Operation == "replays" {
		state.Replays, state.HasMore = h.accountReplays(sess.Account().ID, q.Offset)
	}
	response, _ := protocol.NewEnvelope(protocol.TypeAccountState, state)
	response.ID = env.ID
	h.send(sess, response)
	if q.Operation == "logout" || (q.Operation == "revoke" && q.SessionID == a.SessionID) {
		if r := sess.Room(); r != nil {
			h.holdForReconnect(sess, r)
		}
		h.accountConnectionsMu.Lock()
		if h.accountConnections[a.ID] == sess {
			delete(h.accountConnections, a.ID)
		}
		h.accountConnectionsMu.Unlock()
	}
	return nil
}

func (h *Handler) bindAccountResources(sess *Session) {
	aid := sess.Account().ID
	if aid == "" {
		return
	}
	if r := sess.Room(); r != nil {
		if entry, err := h.hub.lockRoomOperation(r.ID); err == nil {
			entry.mu.Lock()
			seat := r.FindSeatByConnection(sess.ConnectionID)
			if seat >= 0 && (r.Seats[seat].AccountID == "" || r.Seats[seat].AccountID == aid) {
				r.Seats[seat].AccountID = aid
			}
			entry.mu.Unlock()
			h.forgeReplays.bindAccount(r, sess.ConnectionID, aid)
			entry.opMu.Unlock()
		}
	}
	binding := sess.Tournament()
	if binding.TournamentID != "" {
		if entry, err := h.tournaments.lockOperation(binding.TournamentID); err == nil {
			entry.mu.Lock()
			entry.event.ClaimConnectionAccount(sess.ConnectionID, aid)
			entry.mu.Unlock()
			entry.opMu.Unlock()
		}
	}
}

func (h *Handler) accountResources(sess *Session) []protocol.AccountResource {
	aid := sess.Account().ID
	result := []protocol.AccountResource{}
	if aid == "" {
		return result
	}
	if r := sess.Room(); r != nil {
		if entry, err := h.hub.lockRoomOperation(r.ID); err == nil {
			entry.mu.Lock()
			seat := r.FindSeatByConnection(sess.ConnectionID)
			if seat >= 0 && r.Seats[seat].AccountID == aid {
				result = append(result, protocol.AccountResource{Kind: "room", ID: r.ID, Name: r.Name, Role: "player"})
			}
			entry.mu.Unlock()
			entry.opMu.Unlock()
		}
	}
	h.resumeMu.Lock()
	for _, hold := range h.resumeHolds {
		if hold.accountID == aid && time.Now().Before(hold.expiresAt) {
			// Room identifiers/names are immutable for a room's lifetime.
			result = append(result, protocol.AccountResource{Kind: "room", ID: hold.room.ID, Name: hold.room.Name, Role: "player"})
		}
	}
	h.resumeMu.Unlock()
	h.evictExpiredTournaments(time.Now().UTC())
	for id, entry := range h.tournaments.snapshot() {
		entry.mu.Lock()
		role, _ := entry.event.AccountRole(aid)
		if role != "" {
			kind := "tournament"
			if entry.event.IsCubeRoom() {
				kind = "cube"
			}
			result = append(result, protocol.AccountResource{Kind: kind, ID: id, Name: entry.event.Name, Role: role})
		}
		entry.mu.Unlock()
	}
	sort.Slice(result, func(i, j int) bool { return result[i].Kind+result[i].ID < result[j].Kind+result[j].ID })
	return result
}

func (h *Handler) claimAccountResource(sess *Session, q protocol.AccountCommand) bool {
	if q.Credential == "" {
		return false
	}
	if q.Kind == "replay" {
		return h.claimAccountReplay(sess.Account().ID, q.ResourceID, q.Credential)
	}
	if q.Kind != "tournament" && q.Kind != "cube" {
		return false
	}
	h.evictExpiredTournaments(time.Now().UTC())
	entry, err := h.tournaments.lockOperation(q.ResourceID)
	if err != nil {
		return false
	}
	defer entry.opMu.Unlock()
	entry.mu.Lock()
	defer entry.mu.Unlock()
	return entry.event.ClaimCredentialAccount(tournament.CredentialHash(q.Credential), sess.Account().ID)
}

// Each connection has one watcher. Revocation on another official hub also
// closes idle connections; every incoming mutation validates immediately.
func (h *Handler) watchAccountSession(ctx context.Context, sess *Session) {
	ticker := time.NewTicker(2 * time.Second)
	defer ticker.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			a := sess.Account()
			if a.ID == "" {
				continue
			}
			out, err := h.accountRequest(accounts.Request{Operation: "check", SessionToken: a.Token})
			if err != nil || out.Profile.ID != a.ID {
				sess.Close()
				return
			}
		}
	}
}

func (h *Handler) accountRealm() string {
	if h.accounts == nil {
		return ""
	}
	return h.config.AccountRealm
}
