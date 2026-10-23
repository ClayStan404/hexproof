// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package feedback

// Delivery phases remain part of the public feedback thread contract.
func deliveryState(state string) bool {
	return oneOf(state, "merged-awaiting-release", "source-published-awaiting-release", "released")
}
