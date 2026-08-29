// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package limited

import "fmt"

const (
	ErrInvalid         = "limited_invalid"
	ErrForbidden       = "limited_forbidden"
	ErrNotReady        = "limited_not_ready"
	ErrPickUnavailable = "limited_pick_unavailable"
	ErrDeckInvalid     = "limited_deck_invalid"
)

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

func ErrorCode(err error) string {
	if typed, ok := err.(*Error); ok {
		return typed.Code
	}
	return ""
}
