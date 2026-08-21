// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package server

import "golang.org/x/crypto/bcrypt"

// hashPassword returns a bcrypt hash of the password, or nil if empty (no
// password set). bcrypt is pure Go (cgo-free), satisfying CGO_ENABLED=0.
func hashPassword(password string) ([]byte, error) {
	if password == "" {
		return nil, nil
	}
	h, err := bcrypt.GenerateFromPassword([]byte(password), bcrypt.DefaultCost)
	if err != nil {
		return nil, err
	}
	return h, nil
}

// checkPassword compares a plaintext password against a bcrypt hash using
// bcrypt's constant-time comparison.
func checkPassword(hash []byte, password string) bool {
	return bcrypt.CompareHashAndPassword(hash, []byte(password)) == nil
}
