// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package room

import "hexproof/server/internal/protocol"

// Keep a contiguous chronological window for projections and archives, with
// bounded spare capacity to amortize copying once the retention limit is full.
const gameLogAppendReserve = 1024

// appendRetainedGameLog owns and may mutate log's backing array. Published
// projections and retained snapshots must keep their existing independent copies.
func appendRetainedGameLog(log []protocol.GameLogEntry,
	entry protocol.GameLogEntry) []protocol.GameLogEntry {
	if len(log) >= protocol.MaxRetainedGameLog {
		dropped := len(log) - protocol.MaxRetainedGameLog + 1
		// Release old text references without moving every surviving entry.
		clear(log[:dropped])
		log = log[dropped:]
	}
	if len(log) == cap(log) {
		capacity := min(max(8, 2*len(log)), protocol.MaxRetainedGameLog+gameLogAppendReserve)
		grown := make([]protocol.GameLogEntry, len(log), capacity)
		copy(grown, log)
		log = grown
	}
	return append(log, entry)
}
