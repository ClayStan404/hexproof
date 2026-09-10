// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package protocol

// ValidCommanderColor accepts one actual Magic color, never colorless or multicolor.
func ValidCommanderColor(color string) bool {
	switch color {
	case "W", "U", "B", "R", "G":
		return true
	default:
		return false
	}
}
