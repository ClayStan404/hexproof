// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package protocol

import "testing"

func TestCanonicalProtocol(t *testing.T) {
	for _, value := range []string{"hexproof.v1", ProtocolVersion, "hexproof.v2147483647"} {
		if !ValidProtocol(value) {
			t.Errorf("canonical identifier rejected: %q", value)
		}
	}
	for _, value := range []string{"", "hexproof.v0", "hexproof.v02", "hexproof.v-1", "hexproof.v+2", "hexproof.v2.0", "hexproof.v2147483648", "hexproof.v999999999999999", " hexproof.v2", "hexproof.v2\n", "hexproof.v２"} {
		if ValidProtocol(value) {
			t.Errorf("malformed identifier accepted: %q", value)
		}
	}
}
