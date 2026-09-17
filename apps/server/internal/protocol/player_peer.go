// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package protocol

type ForgePeerRequest struct {
	Enabled bool `json:"enabled"`
	Retry   bool `json:"retry,omitempty"`
}

type ForgePeerGrant struct {
	RoomID    string   `json:"roomId"`
	GameID    string   `json:"gameId"`
	BindingID string   `json:"bindingId"`
	Token     string   `json:"token"`
	HostSeat  int      `json:"hostSeat"`
	Offerer   bool     `json:"offerer"`
	STUN      []string `json:"stun"`
}

// Signaling is opaque to the public schema but bounded/parsed by the handler.
// It is private to the two consenting seats, never spectators or diagnostics.
type ForgePeerSignal struct {
	RoomID    string `json:"roomId"`
	BindingID string `json:"bindingId"`
	Data      string `json:"data"`
}

type ForgePeerStatus struct {
	BindingID    string `json:"bindingId"`
	RoomID       string `json:"roomId"`
	Enabled      bool   `json:"enabled"`
	OtherEnabled bool   `json:"otherEnabled"`
	Available    bool   `json:"available"`
}
