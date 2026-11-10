// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package server

import (
	"fmt"
	"sync/atomic"

	"hexproof/server/internal/protocol"
)

var testTournamentOperationSequence atomic.Uint64

func testTournamentOperationID() string {
	return fmt.Sprintf("test-operation-%d", testTournamentOperationSequence.Add(1))
}

func testTournamentStart(stage string) protocol.TournamentStart {
	return protocol.TournamentStart{OperationID: testTournamentOperationID(), ExpectedStage: stage}
}

func testIntPointer(value int) *int {
	return &value
}

func testStringPointer(value string) *string {
	return &value
}
