// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package protocol

type NodeLatency struct {
	URL          string `json:"url"`
	Milliseconds int    `json:"milliseconds"`
}

// SessionRoute responds to one unexecuted create/join/resume request. It never
// redirects an established game or carries the original private command body.
type SessionRoute struct {
	URL    string `json:"url"`
	Realm  string `json:"realm"`
	Ticket string `json:"ticket"`
	NodeID string `json:"nodeId"`
}
