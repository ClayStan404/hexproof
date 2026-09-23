// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package protocol

// ForgeReplayGrant contains a recipient-specific capability, never public room metadata.
type ForgeReplayGrant struct {
	ReplayID   string   `json:"replayId"`
	Token      string   `json:"token"`
	RoomName   string   `json:"roomName"`
	Format     string   `json:"format"`
	MatchMode  string   `json:"matchMode"`
	Players    []string `json:"players"`
	Finished   bool     `json:"finished"`
	Complete   bool     `json:"complete"`
	FrameCount int      `json:"frameCount"`
	ExpiresAt  string   `json:"expiresAt"`
}

type ForgeReplayGet struct {
	ReplayID string `json:"replayId"`
	Token    string `json:"token"`
	Offset   int    `json:"offset"`
}

type ForgeReplayRelation struct {
	Kind       string `json:"kind"`
	SourceID   string `json:"sourceId"`
	TargetID   string `json:"targetId,omitempty"`
	TargetSeat *int   `json:"targetSeat,omitempty"`
}

type ForgeReplayFrame struct {
	Sequence   int64                 `json:"sequence"`
	ElapsedMS  int64                 `json:"elapsedMs"`
	GameNumber int                   `json:"gameNumber"`
	Kind       string                `json:"kind"`
	ActorSeat  int                   `json:"actorSeat"`
	Text       string                `json:"text"`
	Snapshot   RulesGameSnapshot     `json:"snapshot"`
	Combat     []ForgeReplayRelation `json:"combat"`
}

type ForgeReplayPage struct {
	ReplayID      string             `json:"replayId"`
	SchemaVersion int                `json:"schemaVersion"`
	Offset        int                `json:"offset"`
	Total         int                `json:"total"`
	Complete      bool               `json:"complete"`
	Frames        []ForgeReplayFrame `json:"frames"`
}
