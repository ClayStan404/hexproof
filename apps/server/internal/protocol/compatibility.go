// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package protocol

import (
	"strconv"
	"strings"
)

// ValidProtocol validates the canonical identifier, not support for that protocol.
// Each binary admits only ProtocolVersion; other valid generations get a
// structured mismatch instead of being mistaken for malformed input.
func ValidProtocol(value string) bool {
	const prefix = "hexproof.v"
	if !strings.HasPrefix(value, prefix) {
		return false
	}
	number := strings.TrimPrefix(value, prefix)
	if len(number) == 0 || len(number) > 10 || number[0] == '0' {
		return false
	}
	for _, c := range number {
		if c < '0' || c > '9' {
			return false
		}
	}
	generation, err := strconv.ParseInt(number, 10, 32)
	return err == nil && generation > 0
}
