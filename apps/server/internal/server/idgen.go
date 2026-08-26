// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package server

import (
	"crypto/rand"
	"encoding/base64"
)

// roomIDAlphabet excludes ambiguous chars (O/0/I/1) so codes are unambiguous
// when read aloud or retyped.
const roomIDAlphabet = "23456789ABCDEFGHJKLMNPQRSTUVWXYZ"

const roomIDLen = 6
const tournamentIDLen = 8

var secureRandomRead = rand.Read

// genRoomID generates one 6-char room id using crypto/rand so codes are not
// predictable/enumerable on a public hub. Uniqueness is enforced by the hub
// (allocRoomID retries on collision).
func genRoomID() (string, error) {
	return genReadableID(roomIDLen)
}

func genTournamentID() (string, error) {
	return genReadableID(tournamentIDLen)
}

func genReadableID(length int) (string, error) {
	b := make([]byte, length)
	if _, err := secureRandomRead(b); err != nil {
		return "", err
	}
	for i := range b {
		b[i] = roomIDAlphabet[int(b[i])%len(roomIDAlphabet)]
	}
	return string(b), nil
}

// genResumeToken returns an opaque 256-bit bearer credential suitable for a
// short reconnect window. It is never written to room projections or retained
// match archives.
func genResumeToken() (string, error) {
	bytes := make([]byte, 32)
	if _, err := secureRandomRead(bytes); err != nil {
		return "", err
	}
	return base64.RawURLEncoding.EncodeToString(bytes), nil
}
