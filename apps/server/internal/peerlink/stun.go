// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package peerlink

import (
	"fmt"
	"strings"

	"github.com/pion/stun/v4"
)

// ValidateSTUNServers enforces the same discovery-only contract at hub startup
// and in the player helper. An empty list permits LAN/direct-address ICE only.
func ValidateSTUNServers(endpoints []string) error {
	if len(endpoints) > 2 {
		return fmt.Errorf("at most two STUN servers are supported")
	}
	for _, endpoint := range endpoints {
		if len(endpoint) > 256 || !strings.HasPrefix(endpoint, "stun:") || strings.ContainsAny(endpoint, "@/?#\\ \r\n\t") {
			return fmt.Errorf("STUN servers must be stun:host[:port] URLs without credentials or query parameters")
		}
		uri, err := stun.ParseURI(endpoint)
		if err != nil || uri.Port < 1 || uri.Port > 65535 {
			return fmt.Errorf("invalid STUN server host or port")
		}
	}
	return nil
}
