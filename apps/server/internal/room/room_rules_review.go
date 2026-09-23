// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package room

import "hexproof/server/internal/protocol"

// RecordRulesReview accepts only the normalized spectator publication, before
// any opt-in hand overlay. The encoded copy remains independent of the engine
// and all later viewer projections. It is presentation data, never game state.
func (r *Room) RecordRulesReview(snapshot protocol.RulesGameSnapshot) {
	if r.RulesMode != protocol.RulesModeForge || r.Phase != protocol.RoomPhaseStarted ||
		snapshot.RoomID != r.ID || snapshot.GameID == "" {
		return
	}
	if !snapshot.GameOver {
		r.rulesReview = nil
		return
	}
	envelope, err := protocol.NewEnvelope(protocol.TypeRulesSnapshot, snapshot)
	if err == nil {
		r.rulesReview = &envelope
	}
}

// RulesReviewProjection is a read-only public board for the completed game.
// It never grants private hands, prompts, or engine actions to a reconnecting
// player, and it is unavailable while a new game is active.
func (r *Room) RulesReviewProjection(seq int64) (protocol.Envelope, bool) {
	if r.RulesMode != protocol.RulesModeForge || r.Phase != protocol.RoomPhaseStarted ||
		r.Game == nil || r.Game.Result == nil || r.rulesReview == nil {
		return protocol.Envelope{}, false
	}
	return r.rulesReview.WithSeq(seq), true
}
