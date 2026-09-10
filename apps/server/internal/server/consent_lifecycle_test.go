// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package server

import (
	"testing"
	"time"

	"hexproof/server/internal/protocol"
	"hexproof/server/internal/room"
)

func TestMembershipFinishingEDHExpiresOtherSeatsConsent(t *testing.T) {
	for _, transition := range []string{"leave", "kick", "expiry"} {
		t.Run(transition, func(t *testing.T) {
			setup := newPrivateZoneConsentSetup(t)
			h, r := setup.handler, setup.room
			// Reuse the third connected peer as the third player of this fixture.
			r.Format, r.MaxSeats = protocol.FormatEDH, 3
			r.Spectators = nil
			r.Seats = append(r.Seats, room.Seat{Occupied: true, DisplayName: "Charlie",
				ConnectionID: setup.spectator.ConnectionID})
			r.Score = append(r.Score, 0)
			r.Game.Seats = append(r.Game.Seats, room.PlayerGameState{Seat: 2, DisplayName: "Charlie", Life: 40})
			grant, err := h.createZoneDumpRequest("library-grant", r.ID, setup.guest.ConnectionID,
				room.ZoneDumpTarget{TargetSeat: 0, TargetConnID: setup.host.ConnectionID})
			if err != nil {
				t.Fatal(err)
			}
			if _, err := h.resolveZoneDumpRequest(setup.host.ConnectionID, r.ID,
				protocol.GameRespondZoneDump{ApprovalID: grant.approvalID, Approved: true}); err != nil {
				t.Fatal(err)
			}
			if !h.bindZoneDumpGrant(grant.approvalID, r.Game.Seats[0].Library) {
				t.Fatal("could not bind grant")
			}
			pending, err := h.createPublicZoneMoveRequest(publicZoneMoveRequest{
				originalID: "pending-public", roomID: r.ID, requesterConnID: setup.guest.ConnectionID,
				targetConnID: setup.host.ConnectionID,
				card: &protocol.GameMoveCard{CardID: "s0-c8", FromZone: protocol.ZoneGraveyard,
					ToZone: protocol.ZoneBattlefield}})
			if err != nil {
				t.Fatal(err)
			}
			concede, _ := protocol.NewEnvelope(protocol.TypeGameConcede, nil)
			if err := h.handleGameConcede(setup.guest, concede); err != nil {
				t.Fatal(err)
			}
			if r.Game.Result != nil {
				t.Fatal("first elimination unexpectedly ended the three-player game")
			}
			switch transition {
			case "leave":
				command, _ := protocol.NewEnvelope(protocol.TypeRoomLeave, nil)
				err = h.handleRoomLeave(setup.spectator, command)
			case "kick":
				seat := 2
				command, _ := protocol.NewEnvelope(protocol.TypeRoomKick, protocol.RoomKick{Seat: &seat})
				err = h.handleRoomKick(setup.host, command)
			case "expiry":
				hold := resumeHold{token: "expired-third", oldConnectionID: setup.spectator.ConnectionID,
					room: r, expiresAt: time.Now().Add(-time.Minute)}
				installResumeHold(h, hold)
				h.expireResumeHold(hold)
			}
			if err != nil {
				t.Fatal(err)
			}
			if r.Game.Result == nil || r.Game.Result.WinnerSeat != 0 {
				t.Fatal("last opponent departure did not end the game")
			}
			if _, exists := h.zoneDumpRequests[grant.approvalID]; exists {
				t.Error("other seats' library grant survived terminal membership transition")
			}
			if _, exists := h.publicZoneMoveRequests[pending.approvalID]; exists {
				t.Error("other seats' pending consent survived terminal membership transition")
			}
		})
	}
}

func TestGameTransitionExpiresLibraryAndPublicZoneConsent(t *testing.T) {
	for _, transition := range []string{"restart", "concede", "draw", "return"} {
		t.Run(transition, func(t *testing.T) {
			setup := newPrivateZoneConsentSetup(t)
			h, r := setup.handler, setup.room
			for index := range r.Seats {
				deck := modernTestDeck("Restart deck")
				r.Seats[index].Deck = &deck
			}
			pending, err := h.createZoneDumpRequest("library-request", r.ID, setup.host.ConnectionID,
				room.ZoneDumpTarget{TargetSeat: 1, TargetConnID: setup.guest.ConnectionID})
			if err != nil {
				t.Fatal(err)
			}
			approved, err := h.createZoneDumpRequest("approved-library", r.ID, setup.guest.ConnectionID,
				room.ZoneDumpTarget{TargetSeat: 0, TargetConnID: setup.host.ConnectionID})
			if err != nil {
				t.Fatal(err)
			}
			if _, err := h.resolveZoneDumpRequest(setup.host.ConnectionID, r.ID,
				protocol.GameRespondZoneDump{ApprovalID: approved.approvalID, Approved: true}); err != nil {
				t.Fatal(err)
			}
			if !h.bindZoneDumpGrant(approved.approvalID, r.Game.Seats[0].Library) {
				t.Fatal("could not bind library grant")
			}
			public, err := h.createPublicZoneMoveRequest(publicZoneMoveRequest{
				originalID: "public-request", roomID: r.ID,
				requesterConnID: setup.host.ConnectionID, targetConnID: setup.guest.ConnectionID,
				card: &protocol.GameMoveCard{CardID: "s1-c8", FromZone: protocol.ZoneGraveyard,
					ToZone: protocol.ZoneBattlefield},
			})
			if err != nil {
				t.Fatal(err)
			}
			// An unrelated table's request must survive this table's transition.
			other, err := h.createZoneDumpRequest("unrelated", "OTHER1", "other-requester",
				room.ZoneDumpTarget{TargetSeat: 1, TargetConnID: "other-target"})
			if err != nil {
				t.Fatal(err)
			}
			command, _ := protocol.NewEnvelope(protocol.TypeGameRestart, protocol.GameRestart{})
			switch transition {
			case "restart":
				err = h.handleGameRestart(setup.host, command)
			case "concede":
				err = h.handleGameConcede(setup.host, command)
			case "draw":
				err = h.handleGameDeclareDraw(setup.host, command)
			case "return":
				r.Game.Result = &protocol.GameResult{MatchFinished: true}
				err = h.handleGameReturnToRoom(setup.host, command)
			}
			if err != nil {
				t.Fatal(err)
			}
			if _, exists := h.zoneDumpRequests[pending.approvalID]; exists {
				t.Error("pending library approval survived a game transition")
			}
			if _, exists := h.zoneDumpRequests[approved.approvalID]; exists {
				t.Error("approved library grant survived a game transition with reusable card IDs")
			}
			if _, exists := h.publicZoneMoveRequests[public.approvalID]; exists {
				t.Error("pending public-zone move survived a game transition")
			}
			if _, exists := h.zoneDumpRequests[other.approvalID]; !exists {
				t.Error("unrelated table's consent was discarded")
			}
		})
	}
}

func TestFailedRestartAndOrdinaryActionsPreserveConsent(t *testing.T) {
	setup := newPrivateZoneConsentSetup(t)
	h, r := setup.handler, setup.room
	pending, err := h.createZoneDumpRequest("library-request", r.ID, setup.host.ConnectionID,
		room.ZoneDumpTarget{TargetSeat: 1, TargetConnID: setup.guest.ConnectionID})
	if err != nil {
		t.Fatal(err)
	}
	restart, _ := protocol.NewEnvelope(protocol.TypeGameRestart, protocol.GameRestart{})
	if err := h.handleGameRestart(setup.guest, restart); err != nil {
		t.Fatal(err)
	}
	if _, exists := h.zoneDumpRequests[pending.approvalID]; !exists {
		t.Fatal("a rejected non-host restart invalidated consent")
	}
	phase, _ := protocol.NewEnvelope(protocol.TypeGameSetPhase,
		protocol.GameSetPhase{Phase: protocol.GamePhaseEnd})
	if err := h.handleGameSetPhase(setup.host, phase); err != nil {
		t.Fatal(err)
	}
	if _, exists := h.zoneDumpRequests[pending.approvalID]; !exists {
		t.Fatal("an ordinary in-game action invalidated consent")
	}
}

func TestSameNumberRestartAnnouncesLifecycleBeforePrivateSnapshots(t *testing.T) {
	setup := newPrivateZoneConsentSetup(t)
	for index := range setup.room.Seats {
		deck := modernTestDeck("Restart deck")
		setup.room.Seats[index].Deck = &deck
	}
	request, _ := protocol.NewEnvelope(protocol.TypeGameRestart, protocol.GameRestart{})
	request.ID = "restart-same-number"
	if err := setup.handler.handleGameRestart(setup.host, request); err != nil {
		t.Fatal(err)
	}
	acknowledgment := receivePrivateZoneEnvelope(t, setup.host)
	if acknowledgment.Type != protocol.TypeGameRestarted || acknowledgment.ID != request.ID {
		t.Fatalf("restart reply = %+v", acknowledgment)
	}
	var broadcastSeq int64
	for _, session := range []*Session{setup.host, setup.guest, setup.spectator} {
		announcement := receivePrivateZoneEnvelope(t, session)
		var restarted protocol.GameRestarted
		if announcement.Type != protocol.TypeGameRestarted || announcement.ID != "" ||
			announcement.DecodePayload(&restarted) != nil || restarted.GameNumber != 1 ||
			restarted.RoomID != setup.room.ID || announcement.SeqValue() <= 0 {
			t.Fatalf("missing same-number lifecycle announcement for %s: %+v", session.ConnectionID, announcement)
		}
		if broadcastSeq != 0 && announcement.SeqValue() != broadcastSeq {
			t.Fatal("restart audiences received different lifecycle sequences")
		}
		broadcastSeq = announcement.SeqValue()
		snapshot := receivePrivateZoneEnvelope(t, session)
		if snapshot.Type != protocol.TypeGameSnapshot || snapshot.SeqValue() <= broadcastSeq {
			t.Fatalf("fresh projection preceded lifecycle announcement: %+v", snapshot)
		}
	}
}
