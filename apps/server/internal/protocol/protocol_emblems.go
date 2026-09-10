// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package protocol

// GameEmblem is a public command-zone object, not a card or commander. Its
// owning seat is the enclosing GameSeatProjection; it cannot change zones.
type GameEmblem struct {
	ID              string `json:"id"`
	Name            string `json:"name"`
	SetCode         string `json:"setCode"`
	CollectorNumber string `json:"collectorNumber"`
	TypeLine        string `json:"typeLine,omitempty"`
}

// GameCreateEmblem explicitly chooses the owner, including another active
// player. Seat is required even for seat zero; omitted/null is not a default.
type GameCreateEmblem struct {
	Seat            *int   `json:"seat"`
	Name            string `json:"name"`
	SetCode         string `json:"setCode"`
	CollectorNumber string `json:"collectorNumber"`
	TypeLine        string `json:"typeLine,omitempty"`
}

type GameEmblemCreated struct {
	RoomID   string `json:"roomId"`
	Seat     int    `json:"seat"`
	EmblemID string `json:"emblemId"`
}

// GameRemoveEmblem is an owner's manual correction, not a zone move.
type GameRemoveEmblem struct {
	EmblemID string `json:"emblemId"`
}

type GameEmblemRemoved struct {
	RoomID   string `json:"roomId"`
	Seat     int    `json:"seat"`
	EmblemID string `json:"emblemId"`
}
