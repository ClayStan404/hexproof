// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package protocol

type ForgeHostRequest struct {
	Action string `json:"action,omitempty"`
}

// ForgeHostGrant is a consenting host-private capability. It must never be included in
// a room snapshot, replay, public diagnostics, or another member's messages.
type ForgeHostGrant struct {
	RoomID       string `json:"roomId"`
	Token        string `json:"token"`
	RuntimeID    string `json:"runtimeId"`
	GraceSeconds int    `json:"graceSeconds"`
	Standby      bool   `json:"standby,omitempty"`
}

type ForgeHostStatus struct {
	RoomID             string `json:"roomId"`
	Connected          bool   `json:"connected"`
	GraceSeconds       int    `json:"graceSeconds"`
	HostSeat           int    `json:"hostSeat"`
	BackupSeat         *int   `json:"backupSeat,omitempty"`
	BackupConnected    bool   `json:"backupConnected,omitempty"`
	BackupApproved     bool   `json:"backupApproved,omitempty"`
	Migrating          bool   `json:"migrating,omitempty"`
	MigrationAvailable bool   `json:"migrationAvailable,omitempty"`
	MigrationError     string `json:"migrationError,omitempty"`
}
