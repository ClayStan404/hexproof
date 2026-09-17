// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package peerlink

import (
	"strings"
	"testing"
)

func TestValidateSTUNServers(t *testing.T) {
	for _, endpoints := range [][]string{
		nil, {}, {"stun:stun.example.org"},
		{"stun:192.0.2.1:3478", "stun:[2001:db8::1]:3478"},
	} {
		if err := ValidateSTUNServers(endpoints); err != nil {
			t.Errorf("valid endpoints %v: %v", endpoints, err)
		}
	}
	for _, endpoints := range [][]string{
		{""}, {"stun:"}, {"stun::3478"}, {"stun://example.org:3478"},
		{"stun:example.org:0"}, {"stun:example.org:65536"}, {"stun:example.org:-1"},
		{"stun:example.org:not-a-port"}, {"stun:example.org?transport=tcp"},
		{"turn:example.org:3478"}, {"stuns:example.org:5349"},
		{"stun:user@example.org"}, {"stun:example.org/path"}, {"stun:example.org#fragment"},
		{"stun:exa\tmple.org"}, {"stun:" + strings.Repeat("a", 256)},
		{"stun:one.example", "stun:two.example", "stun:three.example"},
	} {
		if err := ValidateSTUNServers(endpoints); err == nil {
			t.Errorf("accepted invalid endpoints %v", endpoints)
		}
	}
}
