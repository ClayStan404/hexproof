// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package protocol

func IsModelAISource(source string) bool { return source == AISourceLocal || source == AISourceOnline }

func ValidAIConfiguration(source, difficulty string) bool {
	return source == AISourceForge && ValidAIDifficulty(difficulty) || IsModelAISource(source) && difficulty == ""
}

// RoomAIWorker is a private, revocable capability delivered only to the host.
// It authorizes one model seat, never the Forge hosting or human player roles.
type RoomAIWorker struct {
	RoomID string `json:"roomId"`
	Source string `json:"source"`
	Token  string `json:"token"`
}

type RoomAIStatus struct {
	RoomID string `json:"roomId"`
	State  string `json:"state"`
	Code   string `json:"code,omitempty"`
}

type RoomAIRetry struct{}
type AIAttach struct {
	RoomID string `json:"roomId"`
	Token  string `json:"token"`
}
type AIAttached struct {
	RoomID string `json:"roomId"`
}

// AIDecision contains only the external controller's permitted observation.
// Native actions, host publications, and credentials never enter this payload.
type AIDecision struct {
	RequestID string            `json:"requestId"`
	GameID    string            `json:"gameId"`
	SeatIndex int               `json:"seatIndex"`
	Prompt    RulesPrompt       `json:"prompt"`
	Snapshot  RulesGameSnapshot `json:"snapshot"`
}
type AIAnswer struct {
	RequestID string       `json:"requestId"`
	Response  RulesRespond `json:"response"`
}
type AIFailure struct {
	RequestID string `json:"requestId"`
	Code      string `json:"code"`
}
type AICancel struct {
	RequestID string `json:"requestId"`
}
type AIRejected struct {
	RequestID string `json:"requestId"`
	Code      string `json:"code"`
}
