// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package protocol

// ReplaySummary and ReplayLoaded expose retained public activity only. The
// operator archive may contain hidden trust-server state, but replay messages
// deliberately cannot carry decks, hands, or libraries.
type ReplaySummary struct {
	ReplayID      string   `json:"replayId"`
	SavedAt       string   `json:"savedAt"`
	ExpiresAt     string   `json:"expiresAt"`
	RoomName      string   `json:"roomName"`
	Format        string   `json:"format"`
	DeckFormat    string   `json:"deckFormat"`
	MatchMode     string   `json:"matchMode"`
	GameNumber    int      `json:"gameNumber"`
	Players       []string `json:"players"`
	Score         []int    `json:"score"`
	LogEntryCount int      `json:"logEntryCount"`
}

type ReplayList struct {
	Offset int `json:"offset,omitempty"`
	Limit  int `json:"limit,omitempty"`
}

type ReplayListed struct {
	Replays []ReplaySummary `json:"replays"`
	Offset  int             `json:"offset,omitempty"`
	Limit   int             `json:"limit,omitempty"`
	Total   int             `json:"total,omitempty"`
	HasMore bool            `json:"hasMore,omitempty"`
}

type ReplayGet struct {
	ReplayID string `json:"replayId"`
}

type ReplayLoaded struct {
	Replay ReplaySummary  `json:"replay"`
	Log    []GameLogEntry `json:"log"`
}

// SideboardSeatProjection exposes only public readiness and aggregate counts.
type SideboardSeatProjection struct {
	Seat           int  `json:"seat"`
	Ready          bool `json:"ready"`
	MainboardCount int  `json:"mainboardCount"`
	SideboardCount int  `json:"sideboardCount"`
}

// SideboardProjection is role-specific. Mainboard and Sideboard are present
// only for the owning seated player; spectators and opponents receive counts.
type SideboardProjection struct {
	CanChooseStartingPlayer bool                      `json:"canChooseStartingPlayer,omitempty"`
	ChosenStartingSeat      *int                      `json:"chosenStartingSeat,omitempty"`
	DeadlineUnixMS          int64                     `json:"deadlineUnixMs"`
	Seats                   []SideboardSeatProjection `json:"seats"`
	Mainboard               []DeckCard                `json:"mainboard,omitempty"`
	Sideboard               []DeckCard                `json:"sideboard,omitempty"`
	Commanders              []string                  `json:"commanders,omitempty"`
}

// SideboardMove moves one copy of one already-registered printing between the
// current match mainboard and sideboard. Limited pairings also use the virtual
// basic_lands supply for the five unlimited ordinary basic lands.
type SideboardMove struct {
	ClearMainboard  bool   `json:"clearMainboard,omitempty"`
	Name            string `json:"name"`
	SetCode         string `json:"setCode"`
	CollectorNumber string `json:"collectorNumber"`
	FromZone        string `json:"fromZone"`
	ToZone          string `json:"toZone"`
}

type SideboardMoved struct {
	RoomID string `json:"roomId"`
	Seat   int    `json:"seat"`
}

// SideboardSetCommander toggles one mainboard card name as a Duel Commander
// commander for the next game. The registered card partition is unchanged.
type SideboardSetCommander struct {
	Name       string `json:"name"`
	Designated bool   `json:"designated"`
}

type SideboardCommanderSet struct {
	RoomID string `json:"roomId"`
	Seat   int    `json:"seat"`
}

type SideboardReady struct {
	Ready bool `json:"ready"`
}

type SideboardReadyChanged struct {
	RoomID          string `json:"roomId"`
	Seat            int    `json:"seat"`
	Ready           bool   `json:"ready"`
	NextGameStarted bool   `json:"nextGameStarted"`
}

// SideboardCompleted is an authoritative room event sent for both the
// all-ready path and the five-minute timeout path.
type SideboardCompleted struct {
	RoomID     string `json:"roomId"`
	GameNumber int    `json:"gameNumber"`
	Reason     string `json:"reason"`
}

// SideboardChooseStartingPlayer records the previous loser's play/draw choice.
type SideboardChooseStartingPlayer struct {
	StartingSeat int `json:"startingSeat"`
}
type SideboardStartingPlayerChosen struct {
	RoomID       string `json:"roomId"`
	StartingSeat int    `json:"startingSeat"`
}
