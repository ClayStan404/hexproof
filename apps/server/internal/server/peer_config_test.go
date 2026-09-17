// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package server

import (
	"slices"
	"testing"
)

func TestPeerSTUNConfiguration(t *testing.T) {
	for _, test := range []struct {
		name       string
		configured []string
		want       []string
	}{
		{"default", nil, DefaultConfig().PeerSTUNServers},
		{"disabled", []string{}, []string{}},
		{"custom", []string{"stun:192.0.2.8:3478"}, []string{"stun:192.0.2.8:3478"}},
	} {
		t.Run(test.name, func(t *testing.T) {
			handler, err := NewHandlerWithConfig(Config{PeerSTUNServers: test.configured})
			if err != nil {
				t.Fatal(err)
			}
			defer handler.Close()
			if len(test.configured) > 0 {
				test.configured[0] = "stun:changed.example"
			}
			if !slices.Equal(handler.config.PeerSTUNServers, test.want) {
				t.Fatalf("configured endpoints = %v, want %v", handler.config.PeerSTUNServers, test.want)
			}
		})
	}
	if _, err := NewHandlerWithConfig(Config{PeerSTUNServers: []string{"turn:example.org"}}); err == nil {
		t.Fatal("invalid discovery configuration accepted at startup")
	}
}
