// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package tournament

import (
	"crypto/sha256"
	"time"
)

func (t *Tournament) AccountRole(id string) (role, participantID string) {
	if id == "" {
		return "", ""
	}
	if t.OrganizerAccountID == id {
		return RoleOrganizer, t.OrganizerParticipantID
	}
	for _, p := range t.Participants {
		if p.AccountID == id {
			return RoleParticipant, p.ID
		}
	}
	return "", ""
}

func (t *Tournament) BindAccount(id, connectionID string, now time.Time) (role, participantID string, ok bool) {
	role, participantID = t.AccountRole(id)
	if role == "" {
		return "", "", false
	}
	if role == RoleOrganizer {
		t.OrganizerConnectionID = connectionID
		t.OrganizerDisconnectedAt = time.Time{}
	}
	if p := t.participantByID[participantID]; p != nil {
		p.ConnectionID = connectionID
		p.DisconnectedAt = time.Time{}
	}
	t.LastActivityAt = now.UTC()
	return role, participantID, true
}

// ClaimConnectionAccount adopts only authority already proved by this transport.
func (t *Tournament) ClaimConnectionAccount(connectionID, accountID string) bool {
	if accountID == "" || connectionID == "" {
		return false
	}
	if t.OrganizerConnectionID == connectionID {
		return t.ClaimCredentialAccount(t.OrganizerCredential, accountID)
	}
	for _, p := range t.Participants {
		if p.ConnectionID == connectionID {
			return t.ClaimCredentialAccount(p.CredentialHash, accountID)
		}
	}
	return false
}

// An account cannot use legacy credentials to collect two participant seats.
func (t *Tournament) ClaimCredentialAccount(credential [sha256.Size]byte, accountID string) bool {
	if accountID == "" {
		return false
	}
	_, existing := t.AccountRole(accountID)
	if credential == t.OrganizerCredential {
		if (t.OrganizerAccountID != "" && t.OrganizerAccountID != accountID) ||
			(existing != "" && existing != t.OrganizerParticipantID) {
			return false
		}
		if p := t.participantByID[t.OrganizerParticipantID]; p != nil {
			if p.AccountID != "" && p.AccountID != accountID {
				return false
			}
			p.AccountID = accountID
		}
		t.OrganizerAccountID = accountID
		return true
	}
	for _, p := range t.Participants {
		if p.CredentialHash == credential {
			if (p.AccountID != "" && p.AccountID != accountID) || (existing != "" && existing != p.ID) {
				return false
			}
			p.AccountID = accountID
			return true
		}
	}
	return false
}
