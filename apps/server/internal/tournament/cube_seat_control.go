// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package tournament

import (
	"time"

	"hexproof/server/internal/protocol"
)

const CubeHostAutoDraftDelay = 3 * time.Minute

// SetCubeDraftControl deliberately has no disconnect-triggered counterpart:
// a disconnected seat keeps waiting unless its owner or eligible host opts in.
func (t *Tournament) SetCubeDraftControl(actor Actor, request protocol.LimitedSetDraftControl, now time.Time) error {
	if !t.actorIsCurrent(actor) {
		return fail(ErrForbidden, "Cube room role is not owned by this session")
	}
	if !t.IsCubeRoom() || t.Status != StatusRunning || t.Stage != protocol.LimitedStageDraft || t.Limited == nil {
		return fail(ErrInvalid, "Cube draft is not active")
	}
	targetID := request.ParticipantID
	if targetID == "" {
		targetID = actor.ParticipantID
	}
	participant := t.Participant(targetID)
	if participant == nil || !participant.Competing || t.Limited.Player(targetID) == nil {
		return fail(ErrForbidden, "participant does not own a Cube draft seat")
	}
	self := targetID == actor.ParticipantID && participant.ConnectionID == actor.ConnectionID
	if !self {
		if actor.Role != RoleOrganizer || !request.Automatic {
			return fail(ErrForbidden, "only the seated player can reclaim draft control")
		}
		if participant.ConnectionID != "" || participant.DisconnectedAt.IsZero() ||
			now.Sub(participant.DisconnectedAt) <= CubeHostAutoDraftDelay {
			return fail(ErrNotReady, "the seat must be continuously offline for more than three minutes")
		}
	}
	if err := t.Limited.SetAutoDraft(targetID, request.Automatic); err != nil {
		return fail(ErrInvalid, err.Error())
	}
	t.Stage = t.Limited.Stage
	return nil
}

// SetCubeParticipation preserves the seat, private pool, and submitted deck.
// A resumed seat never rolls free play back to the construction phase.
func (t *Tournament) SetCubeParticipation(actor Actor, participating bool) error {
	participant := t.Participant(actor.ParticipantID)
	if !t.actorIsCurrent(actor) || participant == nil || participant.ConnectionID != actor.ConnectionID {
		return fail(ErrForbidden, "Cube seat is not owned by this session")
	}
	if !t.IsCubeRoom() || t.Status != StatusRunning || t.Limited == nil ||
		(t.Stage != protocol.LimitedStageDeckBuilding && t.Stage != protocol.LimitedStageCompetition) {
		return fail(ErrInvalid, "Cube deck building or free play is not active")
	}
	player := t.Limited.Player(participant.ID)
	if player == nil || !participant.Competing {
		return fail(ErrForbidden, "participant does not own a Cube pool")
	}
	if t.CurrentPairing(participant.ID) != nil {
		return fail(ErrNotReady, "cancel the invitation or leave the table before changing participation")
	}
	if participating && t.Stage == protocol.LimitedStageCompetition && player.Deck == nil {
		return fail(ErrNotReady, "submit a deck before returning to free play")
	}
	player.Withdrawn = !participating
	participant.Dropped = !participating
	return t.enterCubeFreePlayIfReady()
}
