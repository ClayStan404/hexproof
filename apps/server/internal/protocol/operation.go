// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package protocol

import (
	"strings"
	"unicode"
)

// ValidOperationID is the shared bounded identity format for event operations
// and their internal cluster allocation. An operation identity is not authority.
func ValidOperationID(id string) bool {
	if id == "" || len(id) > 128 || strings.TrimSpace(id) != id {
		return false
	}
	for _, r := range id {
		if unicode.IsControl(r) {
			return false
		}
	}
	return true
}
