//go:build engineintegration

// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package peerlink

import "github.com/pion/webrtc/v4"

// QualificationPair is available only in explicit engine-integration builds.
// Public diagnostics must not export candidate addresses or SDP credentials.
func (c *Connection) QualificationPair() (*webrtc.ICECandidatePair, error) {
	return c.pc.SCTP().Transport().ICETransport().GetSelectedCandidatePair()
}
