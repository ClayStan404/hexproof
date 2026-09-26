// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package accounts

import (
	"context"
	"errors"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func TestRecoveryRotationRevocationAndRestart(t *testing.T) {
	dir := t.TempDir()
	s, err := Open(dir)
	if err != nil {
		t.Fatal(err)
	}
	ctx := context.Background()
	first, err := s.Do(ctx, Request{Operation: "create", Name: "Player", DeviceName: "Desktop"})
	if err != nil {
		t.Fatal(err)
	}
	if _, err := Open(dir); err == nil {
		t.Fatal("opened already owned account store")
	}
	second, err := s.Do(ctx, Request{Operation: "login", LoginCode: first.LoginCode, DeviceName: "Laptop"})
	if err != nil {
		t.Fatal(err)
	}
	if second.Profile.ID != first.Profile.ID || second.SessionToken == first.SessionToken {
		t.Fatal("identity or session separation")
	}
	raw, err := os.ReadFile(filepath.Join(dir, first.Profile.ID+".json"))
	if err != nil {
		t.Fatal(err)
	}
	for _, secret := range []string{first.LoginCode, first.RecoveryCode, first.SessionToken, second.SessionToken} {
		if strings.Contains(string(raw), secret) {
			t.Fatal("plaintext credential on disk")
		}
	}
	s.Close()
	s, err = Open(dir)
	if err != nil {
		t.Fatal(err)
	}
	defer s.Close()
	if _, err := s.Do(ctx, Request{Operation: "check", SessionToken: first.SessionToken}); err != nil {
		t.Fatal(err)
	}
	rotated, err := s.Do(ctx, Request{Operation: "rotate", SessionToken: second.SessionToken})
	if err != nil {
		t.Fatal(err)
	}
	if rotated.Profile.ID != first.Profile.ID || rotated.LoginCode == first.LoginCode {
		t.Fatal("rotation changed identity or retained login code")
	}
	for _, q := range []Request{{Operation: "check", SessionToken: first.SessionToken}, {Operation: "login", LoginCode: first.LoginCode, DeviceName: "Stale"}} {
		if _, err := s.Do(ctx, q); !errors.Is(err, ErrInvalid) {
			t.Fatalf("stale credential: %v", err)
		}
	}
	recovered, err := s.Do(ctx, Request{Operation: "recover", RecoveryCode: first.RecoveryCode, DeviceName: "Replacement"})
	if err != nil {
		t.Fatal(err)
	}
	if recovered.Profile.ID != first.Profile.ID || recovered.RecoveryCode == first.RecoveryCode {
		t.Fatal("recovery identity/rotation")
	}
	for _, q := range []Request{{Operation: "check", SessionToken: second.SessionToken}, {Operation: "recover", RecoveryCode: first.RecoveryCode, DeviceName: "Stale"}} {
		if _, err := s.Do(ctx, q); !errors.Is(err, ErrInvalid) {
			t.Fatalf("recovery left old credential valid: %v", err)
		}
	}
	if _, err := s.Do(ctx, Request{Operation: "logout", SessionToken: recovered.SessionToken}); err != nil {
		t.Fatal(err)
	}
	if _, err := s.Do(ctx, Request{Operation: "check", SessionToken: recovered.SessionToken}); !errors.Is(err, ErrInvalid) {
		t.Fatal("logout left token valid")
	}
}

func TestSessionExpiryAndFailedWrites(t *testing.T) {
	s, err := Open(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	defer s.Close()
	ctx := context.Background()
	created, err := s.Do(ctx, Request{Operation: "create", Name: "Player", DeviceName: "Desktop"})
	if err != nil {
		t.Fatal(err)
	}
	original := s.dir
	s.dir = filepath.Join(original, "missing", "directory")
	if _, err := s.Do(ctx, Request{Operation: "rotate", SessionToken: created.SessionToken}); err == nil {
		t.Fatal("expected storage failure")
	}
	s.dir = original
	if _, err := s.Do(ctx, Request{Operation: "login", LoginCode: created.LoginCode, DeviceName: "Still valid"}); err != nil {
		t.Fatal("failed mutation changed credentials", err)
	}
	s.now = func() time.Time { return time.Now().Add(SessionLifetime + time.Hour) }
	if _, err := s.Do(ctx, Request{Operation: "check", SessionToken: created.SessionToken}); !errors.Is(err, ErrInvalid) {
		t.Fatal("expired session accepted")
	}
	if _, err := s.Do(ctx, Request{Operation: "login", LoginCode: created.LoginCode, DeviceName: "Fresh"}); err != nil {
		t.Fatal("login code expired with session", err)
	}
}

func TestSharedAuthorityAndTransportBoundary(t *testing.T) {
	s, err := Open(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	defer s.Close()
	key := strings.Repeat("k", 48)
	handler, err := HTTPHandler(s, key, "official-test")
	if err != nil {
		t.Fatal(err)
	}
	srv := httptest.NewServer(handler)
	defer srv.Close()
	one, err := NewRemote(srv.URL, key, "official-test")
	if err != nil {
		t.Fatal(err)
	}
	two, err := NewRemote(srv.URL, key, "official-test")
	if err != nil {
		t.Fatal(err)
	}
	created, err := one.Do(context.Background(), Request{Operation: "create", Name: "Player", DeviceName: "First hub"})
	if err != nil {
		t.Fatal(err)
	}
	joined, err := two.Do(context.Background(), Request{Operation: "login", LoginCode: created.LoginCode, DeviceName: "Second hub"})
	if err != nil {
		t.Fatal(err)
	}
	if joined.Profile.ID != created.Profile.ID {
		t.Fatal("hubs did not share identity")
	}
	if _, err := one.Do(context.Background(), Request{Operation: "revoke", SessionToken: created.SessionToken, SessionID: joined.SessionID}); err != nil {
		t.Fatal(err)
	}
	if _, err := two.Do(context.Background(), Request{Operation: "check", SessionToken: joined.SessionToken}); !errors.Is(err, ErrInvalid) {
		t.Fatal("cross-hub revocation failed", err)
	}
	badRealm, _ := NewRemote(srv.URL, key, "untrusted-realm")
	if _, err := badRealm.Do(context.Background(), Request{Operation: "check", SessionToken: created.SessionToken}); err == nil {
		t.Fatal("wrong realm accepted")
	}
	for _, endpoint := range []string{"http://example.com/accounts", "https://user:password@example.com/accounts", "https://example.com/accounts?key=x"} {
		if _, err := NewRemote(endpoint, key, "official-test"); err == nil {
			t.Fatal("unsafe authority endpoint accepted")
		}
	}
	redirect := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		http.Redirect(w, r, srv.URL, http.StatusTemporaryRedirect)
	}))
	defer redirect.Close()
	remote, _ := NewRemote(redirect.URL, key, "official-test")
	if _, err := remote.Do(context.Background(), Request{Operation: "create", Name: "Player", DeviceName: "Redirect"}); err == nil {
		t.Fatal("followed credential-bearing redirect")
	}
}
