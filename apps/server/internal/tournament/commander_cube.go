// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package tournament

import (
	"fmt"
	"slices"

	"hexproof/server/internal/protocol"
)

// CasualGroup belongs only to multiplayer free play. Swiss pairings and their
// A/B score records remain strictly two-player objects.
type CasualGroup struct {
	PlayerIDs         []string
	AcceptedPlayerIDs []string
}

func (p Pairing) ParticipantIDs() []string {
	if p.Group != nil {
		return append([]string(nil), p.Group.PlayerIDs...)
	}
	if p.PlayerBID == "" {
		return []string{p.PlayerAID}
	}
	return []string{p.PlayerAID, p.PlayerBID}
}

func (p Pairing) HasParticipant(id string) bool {
	if id == "" {
		return false
	}
	if p.Group != nil {
		return slices.Contains(p.Group.PlayerIDs, id)
	}
	return p.PlayerAID == id || p.PlayerBID == id
}

func (t *Tournament) IsCommanderCube() bool {
	return t.IsCubeRoom() && t.EventType == protocol.LimitedEventCommanderCube
}

// CommanderCubeMatch mutates one bounded invitation. Every named participant
// is reserved from invitation creation until cancellation or table retirement.
func (t *Tournament) CommanderCubeMatch(actor Actor, request protocol.LimitedCreateCasualMatch) error {
	if err := t.cubeMatchActor(actor); err != nil {
		return err
	}
	if !t.IsCommanderCube() || request.PlayerAID != "" || request.PlayerBID != "" {
		return fail(ErrInvalid, "this action requires a Commander Cube group invitation")
	}
	switch request.Action {
	case "invite":
		if request.PairingID != "" || len(request.PlayerIDs) < 2 || len(request.PlayerIDs) > 4 ||
			request.PlayerIDs[0] != actor.ParticipantID {
			return fail(ErrInvalid, "invite yourself and one to three other players")
		}
		seen := make(map[string]bool, len(request.PlayerIDs))
		for _, id := range request.PlayerIDs {
			player := t.Participant(id)
			if seen[id] || player == nil || !player.Competing || player.Dropped ||
				player.Deck == nil || player.ConnectionID == "" || t.CurrentPairing(id) != nil {
				return fail(ErrNotReady, "every invited player must be available with a submitted deck")
			}
			seen[id] = true
		}
		t.nextPairing++
		t.CasualPairings = append(t.CasualPairings, Pairing{
			ID: fmt.Sprintf("casual-%d", t.nextPairing), Table: t.nextPairing,
			PlayerAID: actor.ParticipantID, PlayerBID: request.PlayerIDs[1], Invited: true,
			Group: &CasualGroup{PlayerIDs: append([]string(nil), request.PlayerIDs...),
				AcceptedPlayerIDs: []string{actor.ParticipantID}},
		})
		return nil
	case "accept", "cancel":
		if request.PairingID == "" || len(request.PlayerIDs) != 0 {
			return fail(ErrInvalid, "identify the existing invitation without changing its players")
		}
		pairing := t.CurrentPairing(actor.ParticipantID)
		if pairing == nil || pairing.ID != request.PairingID || pairing.Group == nil || pairing.RoomID != "" {
			return fail(ErrForbidden, "only invited players can change an unopened invitation")
		}
		if request.Action == "cancel" {
			t.clearUnopenedCubeMatches(actor.ParticipantID)
			return nil
		}
		for _, id := range pairing.Group.PlayerIDs {
			player := t.Participant(id)
			if player == nil || player.ConnectionID == "" || player.Deck == nil || player.Dropped {
				return fail(ErrNotReady, "all invited players must be online with submitted decks")
			}
		}
		if !slices.Contains(pairing.Group.AcceptedPlayerIDs, actor.ParticipantID) {
			pairing.Group.AcceptedPlayerIDs = append(pairing.Group.AcceptedPlayerIDs, actor.ParticipantID)
		}
		pairing.Invited = len(pairing.Group.AcceptedPlayerIDs) != len(pairing.Group.PlayerIDs)
		return nil
	default:
		return fail(ErrInvalid, "unsupported Commander Cube invitation action")
	}
}
