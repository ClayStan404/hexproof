// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package tournament

import (
	"hexproof/server/internal/protocol"
	"testing"
	"time"
)

func TestAccountClaimsKeepRolesAndRevokeAnonymousCredentials(t *testing.T) {
	now := time.Now()
	event, err := New("ACCOUNT", Config{Name: "Account event", Format: protocol.FormatModern, MatchMode: protocol.MatchBO3, RoundMinutes: 50, MaxPlayers: 16}, "Host", "host", CredentialHash("host-key"), now)
	if err != nil {
		t.Fatal(err)
	}
	a, err := event.Register("Alice", "alice", CredentialHash("a-key"), now)
	if err != nil {
		t.Fatal(err)
	}
	b, err := event.Register("Bob", "bob", CredentialHash("b-key"), now)
	if err != nil {
		t.Fatal(err)
	}
	if !event.ClaimConnectionAccount("alice", "account-a") {
		t.Fatal("current authority not adopted")
	}
	if event.ClaimCredentialAccount(CredentialHash("b-key"), "account-a") {
		t.Fatal("one account claimed two participant seats")
	}
	if _, _, ok := event.BindCredential(CredentialHash("a-key"), "stranger", now); ok {
		t.Fatal("anonymous old credential accepted")
	}
	if _, _, ok := event.BindCredentialForAccount(CredentialHash("a-key"), "wrong-account", "stranger", now); ok {
		t.Fatal("wrong account accepted")
	}
	role, id, ok := event.BindAccount("account-a", "replacement", now)
	if !ok || role != RoleParticipant || id != a.ID || a.ConnectionID != "replacement" || b.ConnectionID != "bob" {
		t.Fatal("account reentry changed participant identity")
	}
	if event.ClaimCredentialAccount(CredentialHash("a-key"), "account-b") {
		t.Fatal("account ownership overwritten")
	}
	if !event.ClaimCredentialAccount(CredentialHash("host-key"), "account-host") {
		t.Fatal("organizer claim failed")
	}
	role, id, ok = event.BindAccount("account-host", "new-host", now)
	if !ok || role != RoleOrganizer || id != "" || len(event.Participants) != 2 {
		t.Fatal("organizer identity invented a player seat")
	}
}
