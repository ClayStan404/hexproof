// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package tournament

import (
	"fmt"
	"math/rand"
	"slices"

	"hexproof/server/internal/protocol"
)

// IsCubeRoom distinguishes the room-oriented flow from Swiss tournaments.
// Only the private draft and pool coordinator is shared with tournaments.
func (t *Tournament) IsCubeRoom() bool {
	return protocol.IsCubeEventType(t.EventType) &&
		t.Coordinator == protocol.LimitedCoordinatorCasual
}

func (t *Tournament) cubeMatchActor(actor Actor) error {
	participant := t.Participant(actor.ParticipantID)
	if !t.actorIsCurrent(actor) || participant == nil ||
		participant.ConnectionID != actor.ConnectionID {
		return fail(ErrForbidden, "only the seated player can choose an opponent")
	}
	if !t.IsCubeRoom() || t.Status != StatusRunning || t.Stage != protocol.LimitedStageCompetition {
		return fail(ErrInvalid, "Cube free play is not ready")
	}
	return nil
}

func (t *Tournament) requestCubeMatch(actor Actor, playerAID, playerBID string) (*Pairing, error) {
	if t.EventType == protocol.LimitedEventCommanderCube {
		return nil, fail(ErrInvalid, "use a multiplayer invitation for Commander Cube")
	}
	if err := t.cubeMatchActor(actor); err != nil {
		return nil, err
	}
	if playerAID != actor.ParticipantID || playerBID == "" || playerAID == playerBID {
		return nil, fail(ErrForbidden, "choose yourself and one opponent")
	}
	for _, id := range []string{playerAID, playerBID} {
		participant := t.Participant(id)
		if participant == nil || !participant.Competing || participant.Dropped ||
			participant.Deck == nil || participant.ConnectionID == "" {
			return nil, fail(ErrNotReady, "both players must be online with submitted decks")
		}
	}
	if pairing := t.CurrentPairing(playerAID); pairing != nil {
		if pairing.Invited && pairing.PlayerAID == playerBID && pairing.PlayerBID == playerAID {
			pairing.Invited = false
			return pairing, nil
		}
		return nil, fail(ErrNotReady, "cancel the current invitation or leave the table first")
	}
	if t.CurrentPairing(playerBID) != nil {
		return nil, fail(ErrNotReady, "the opponent already has an invitation or table")
	}
	t.nextPairing++
	t.CasualPairings = append(t.CasualPairings, Pairing{
		ID: fmt.Sprintf("casual-%d", t.nextPairing), Table: t.nextPairing,
		PlayerAID: playerAID, PlayerBID: playerBID, Invited: true,
	})
	return &t.CasualPairings[len(t.CasualPairings)-1], nil
}

// CancelCubeMatch permits both withdrawal and refusal, including an accepted
// invitation whose table has not opened yet. Open tables use room.leave.
func (t *Tournament) CancelCubeMatch(actor Actor, playerAID, playerBID string) error {
	if err := t.cubeMatchActor(actor); err != nil {
		return err
	}
	pairing := t.CurrentPairing(actor.ParticipantID)
	if pairing == nil || pairing.RoomID != "" ||
		!((pairing.PlayerAID == playerAID && pairing.PlayerBID == playerBID) ||
			(pairing.PlayerAID == playerBID && pairing.PlayerBID == playerAID)) {
		return fail(ErrForbidden, "only an unopened invitation involving yourself can be cancelled")
	}
	t.clearUnopenedCubeMatches(actor.ParticipantID)
	return nil
}

func (t *Tournament) clearUnopenedCubeMatches(participantID string) {
	t.CasualPairings = slices.DeleteFunc(t.CasualPairings, func(pairing Pairing) bool {
		return pairing.RoomID == "" &&
			pairing.HasParticipant(participantID)
	})
}

func (t *Tournament) clearDisconnectedCubeMatches(participantID string) {
	t.CasualPairings = slices.DeleteFunc(t.CasualPairings, func(pairing Pairing) bool {
		return !pairing.InitialCubeTable && pairing.RoomID == "" &&
			pairing.HasParticipant(participantID)
	})
}

// Initial Commander tables split the submitted group into balanced pods of at
// most four. Readiness remains an explicit action in each game lobby.
// Later departures and deck updates never recreate this initial assignment.
func (t *Tournament) enterCubeFreePlayIfReady() error {
	if !t.IsCubeRoom() || t.Stage != protocol.LimitedStageDeckBuilding ||
		t.Limited == nil || !t.Limited.AllDecksSubmitted() {
		return nil
	}
	if err := t.Limited.EnterCompetition(); err != nil {
		return fail(ErrNotReady, err.Error())
	}
	t.Stage = protocol.LimitedStageCompetition
	ids := make([]string, 0, len(t.Participants))
	for _, participant := range t.Participants {
		if participant.Competing && !participant.Dropped && participant.Deck != nil {
			ids = append(ids, participant.ID)
		}
	}
	if len(ids) < 2 || (!t.IsCommanderCube() && len(ids) != 2) {
		return nil
	}
	if len(ids) > 4 {
		// Separate from drafting RNG; submissions never change card allocation.
		random := rand.New(rand.NewSource(t.cubeTableSeed ^ 0x43554245)) // #nosec G404 -- server-generated seed.
		random.Shuffle(len(ids), func(i, j int) { ids[i], ids[j] = ids[j], ids[i] })
	}
	groups := (len(ids) + 3) / 4
	for groups > 0 {
		size := (len(ids) + groups - 1) / groups
		group := append([]string(nil), ids[:size]...)
		ids = ids[size:]
		groups--
		t.nextPairing++
		pairing := Pairing{
			ID: fmt.Sprintf("casual-%d", t.nextPairing), Table: t.nextPairing,
			PlayerAID: group[0], PlayerBID: group[1], InitialCubeTable: true,
			AutoEntryPendingIDs: append([]string(nil), group...),
		}
		if t.IsCommanderCube() {
			pairing.Group = &CasualGroup{PlayerIDs: group, AcceptedPlayerIDs: append([]string(nil), group...)}
		}
		t.CasualPairings = append(t.CasualPairings, pairing)
	}
	return nil
}

func (p Pairing) AutoEntryPending(participantID string) bool {
	return participantID != "" && p.InitialCubeTable &&
		slices.Contains(p.AutoEntryPendingIDs, participantID)
}

// Called only after a successful authenticated room entry while the event's
// operation lock is held. Failed entries retain the owner's retry request.
func (t *Tournament) MarkCubeTableEntered(participantID, pairingID string) {
	pairing := t.CurrentPairing(participantID)
	if pairing != nil && pairing.ID == pairingID && pairing.RoomID != "" {
		pairing.AutoEntryPendingIDs = slices.DeleteFunc(pairing.AutoEntryPendingIDs,
			func(id string) bool { return id == participantID })
	}
}
