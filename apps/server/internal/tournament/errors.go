// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package tournament

import "fmt"

const (
	ErrInvalid            = "tournament_invalid"
	ErrForbidden          = "tournament_forbidden"
	ErrNotFound           = "tournament_not_found"
	ErrFull               = "tournament_full"
	ErrAlreadyRegistered  = "tournament_already_registered"
	ErrRegistrationClosed = "tournament_registration_closed"
	ErrNotReady           = "tournament_not_ready"
	ErrRoundIncomplete    = "tournament_round_incomplete"
	ErrResultInvalid      = "tournament_result_invalid"
)

// Error is a stable domain error that the server maps onto the wire error
// envelope without exposing implementation details. MinimumPlayers is a
// structured detail carried on not-ready start failures: the checked-in count
// the tournament needs before it can start.
type Error struct {
	Code           string
	Message        string
	MinimumPlayers int
}

func (e *Error) Error() string {
	return fmt.Sprintf("%s: %s", e.Code, e.Message)
}

func fail(code, message string) error {
	return &Error{Code: code, Message: message}
}

func failMinimumPlayers(count int) error {
	return &Error{
		Code:           ErrNotReady,
		Message:        fmt.Sprintf("at least %d checked-in players are required", count),
		MinimumPlayers: count,
	}
}

// ErrorCode extracts the stable tournament error code.
func ErrorCode(err error) string {
	if typed, ok := err.(*Error); ok {
		return typed.Code
	}
	return ""
}
