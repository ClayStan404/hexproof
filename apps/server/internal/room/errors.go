// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package room

import "errors"

// protocolError is a reducer error whose code is safe to expose on the wire.
// Keep its field private so callers cannot attach arbitrary server details.
type protocolError struct {
	code string
}

func (e *protocolError) Error() string {
	return e.code
}

func newError(code string) error {
	return &protocolError{code: code}
}

// ErrorCode extracts a reducer protocol code without treating an arbitrary
// error string as trusted wire data.
func ErrorCode(err error) (string, bool) {
	var target *protocolError
	if !errors.As(err, &target) || target == nil {
		return "", false
	}
	return target.code, true
}
