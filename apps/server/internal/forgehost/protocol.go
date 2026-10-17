// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

// Package forgehost implements the private, authenticated engine relay. Its
// messages must never be broadcast or exposed to the QML/game protocol.
package forgehost

import (
	"encoding/json"
	"hexproof/server/internal/rulesengine/forge"
)

const (
	Version         = 1
	MaxFrameBytes   = 16 << 20
	MaxRequestBytes = 4 << 20
)

type Hello struct {
	Version   int    `json:"version"`
	RoomID    string `json:"roomId"`
	Token     string `json:"token"`
	HelperID  string `json:"helperId"`
	RuntimeID string `json:"runtimeId"`
	EngineID  string `json:"engineId,omitempty"`
	Alive     bool   `json:"alive"`
}

type Request struct {
	RoomID      string                  `json:"roomId"`
	EngineID    string                  `json:"engineId"`
	ID          uint64                  `json:"id"`
	PeerBinding string                  `json:"peerBinding,omitempty"`
	OperationID string                  `json:"operationId,omitempty"`
	Command     string                  `json:"command"`
	Start       *forge.StartGameRequest `json:"start,omitempty"`
	Action      json.RawMessage         `json:"action,omitempty"`
	Checkpoint  *Checkpoint             `json:"checkpoint,omitempty"`
}

// Publication is an immutable decision boundary. Views are ordered spectator,
// first player, second player; only the hub may distribute individual views.
type Publication struct {
	Replay   *forge.ReplayBatch  `json:"replay,omitempty"`
	Revision uint64              `json:"revision"`
	Handle   forge.SessionHandle `json:"handle"`
	Views    []json.RawMessage   `json:"views"`
	Prompt   json.RawMessage     `json:"prompt"`
	GameOver bool                `json:"gameOver"`
}

type Response struct {
	StartFailure json.RawMessage `json:"startFailure,omitempty"`
	RoomID       string          `json:"roomId"`
	EngineID     string          `json:"engineId"`
	ID           uint64          `json:"id"`
	Publication  *Publication    `json:"publication,omitempty"`
	Error        string          `json:"error,omitempty"`
}

type Frame struct {
	PeerContext *PeerContext `json:"peerContext,omitempty"`
	PeerCommit  *PeerCommit  `json:"peerCommit,omitempty"`
	PeerReply   *PeerReply   `json:"peerReply,omitempty"`
	Type        string       `json:"type"`
	Epoch       uint64       `json:"epoch"`
	Request     *Request     `json:"request,omitempty"`
	Response    *Response    `json:"response,omitempty"`
	EngineID    string       `json:"engineId,omitempty"`
}
