// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package protocol

// AccountCommand is private to the requesting connection. Secrets never appear
// in room/event projections or logs. Resource claims verify legacy credentials.
type AccountCommand struct {
	Operation    string `json:"operation"`
	Name         string `json:"name,omitempty"`
	DeviceName   string `json:"deviceName,omitempty"`
	LoginCode    string `json:"loginCode,omitempty"`
	RecoveryCode string `json:"recoveryCode,omitempty"`
	SessionID    string `json:"sessionId,omitempty"`
	Kind         string `json:"kind,omitempty"`
	ResourceID   string `json:"resourceId,omitempty"`
	Credential   string `json:"credential,omitempty"`
	Offset       int    `json:"offset,omitempty"`
}

type AccountDevice struct {
	ID        string `json:"id"`
	Name      string `json:"name"`
	CreatedAt string `json:"createdAt"`
	ExpiresAt string `json:"expiresAt"`
	Current   bool   `json:"current"`
}

type AccountResource struct {
	NodeName string `json:"nodeName,omitempty"`
	Kind     string `json:"kind"`
	ID       string `json:"id"`
	Name     string `json:"name"`
	Role     string `json:"role"`
}

type AccountState struct {
	Operation    string             `json:"operation"`
	AccountID    string             `json:"accountId"`
	DisplayName  string             `json:"displayName"`
	SessionID    string             `json:"sessionId"`
	SessionToken string             `json:"sessionToken,omitempty"`
	LoginCode    string             `json:"loginCode,omitempty"`
	RecoveryCode string             `json:"recoveryCode,omitempty"`
	Devices      []AccountDevice    `json:"devices"`
	Resources    []AccountResource  `json:"resources"`
	Replays      []ForgeReplayGrant `json:"replays"`
	Offset       int                `json:"offset"`
	HasMore      bool               `json:"hasMore"`
}
