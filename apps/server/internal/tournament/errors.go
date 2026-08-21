// SPDX-License-Identifier: GPL-2.0-only
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
// envelope without exposing implementation details.
type Error struct {
	Code    string
	Message string
}

func (e *Error) Error() string {
	return fmt.Sprintf("%s: %s", e.Code, e.Message)
}

func fail(code, message string) error {
	return &Error{Code: code, Message: message}
}

// ErrorCode extracts the stable tournament error code.
func ErrorCode(err error) string {
	if typed, ok := err.(*Error); ok {
		return typed.Code
	}
	return ""
}
