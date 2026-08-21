// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package server

import (
	"strings"
	"testing"

	"hexproof/server/internal/protocol"
)

func TestOpponentPublicZoneMoveRequiresOneUseApproval(t *testing.T) {
	setup := newPrivateZoneConsentSetup(t)
	setup.room.Game.Seats[1].Graveyard = []protocol.GameCard{{
		ID: "s1-grave", Name: "Remote Card", OwnerSeat: 1,
	}}
	sourceSeat, targetSeat := 1, 0
	move, err := protocol.NewEnvelope(protocol.TypeGameMoveCard,
		protocol.GameMoveCard{
			CardID: "s1-grave", FromZone: protocol.ZoneGraveyard,
			FromSeat: &sourceSeat, ToZone: protocol.ZoneBattlefield,
			ToSeat:   &targetSeat,
			Position: &protocol.CardPosition{X: 0.5, Y: 0.5},
		})
	if err != nil {
		t.Fatalf("build public-zone move: %v", err)
	}
	move.ID = "move-remote-1"
	if err := setup.handler.handleGameMoveCard(setup.host, move); err != nil {
		t.Fatalf("request public-zone move: %v", err)
	}
	pending := receivePrivateZoneEnvelope(t, setup.host)
	requested := receivePrivateZoneEnvelope(t, setup.guest)
	var pendingPayload protocol.GamePublicZoneMovePending
	var requestedPayload protocol.GamePublicZoneMoveRequested
	if pending.Type != protocol.TypeGamePublicZoneMovePending ||
		pending.ID != move.ID || pending.DecodePayload(&pendingPayload) != nil {
		t.Fatalf("pending public-zone move = %+v", pending)
	}
	if requested.Type != protocol.TypeGamePublicZoneMoveRequested ||
		requested.DecodePayload(&requestedPayload) != nil {
		t.Fatalf("requested public-zone move = %+v", requested)
	}
	if requestedPayload.ApprovalID != pendingPayload.ApprovalID ||
		requestedPayload.RequesterName != "Alice" ||
		requestedPayload.SourceZone != protocol.ZoneGraveyard ||
		requestedPayload.CardCount != 1 ||
		requestedPayload.ToZone != protocol.ZoneBattlefield {
		t.Fatalf("public-zone request payload = %+v", requestedPayload)
	}
	if len(setup.room.Game.Seats[1].Graveyard) != 1 ||
		len(setup.room.Game.Seats[0].Battlefield) != 0 ||
		len(setup.room.Game.Log) != 0 {
		t.Fatalf("pending request mutated game: %+v", setup.room.Game)
	}
	assertNoPrivateZoneEnvelope(t, setup.spectator)

	unauthorized, _ := protocol.NewEnvelope(
		protocol.TypeGameRespondPublicZoneMove,
		protocol.GameRespondPublicZoneMove{
			ApprovalID: requestedPayload.ApprovalID, Approved: true,
		})
	unauthorized.ID = "spectator-approve"
	if err := setup.handler.handleGameRespondPublicZoneMove(
		setup.spectator, unauthorized); err != nil {
		t.Fatalf("unauthorized response handler: %v", err)
	}
	assertPrivateZoneError(t, receivePrivateZoneEnvelope(t, setup.spectator),
		unauthorized.ID, protocol.ErrApprovalExpired,
		"public-zone move request expired")

	approve := unauthorized
	approve.ID = "approve-public-zone"
	if err := setup.handler.handleGameRespondPublicZoneMove(
		setup.guest, approve); err != nil {
		t.Fatalf("approve public-zone move: %v", err)
	}
	responded := receivePrivateZoneEnvelope(t, setup.guest)
	if responded.Type != protocol.TypeGamePublicZoneMoveResponded ||
		responded.ID != approve.ID {
		t.Fatalf("public-zone response ack = %+v", responded)
	}
	moved := receivePrivateZoneEnvelope(t, setup.host)
	if moved.Type != protocol.TypeGameCardMoved || moved.ID != move.ID {
		t.Fatalf("approved move reply = %+v", moved)
	}
	for _, sess := range []*Session{setup.host, setup.guest, setup.spectator} {
		if snapshot := receivePrivateZoneEnvelope(t, sess); snapshot.Type != protocol.TypeGameSnapshot {
			t.Fatalf("approved move projection = %+v", snapshot)
		}
	}
	if len(setup.room.Game.Seats[1].Graveyard) != 0 ||
		len(setup.room.Game.Seats[0].Battlefield) != 1 ||
		setup.room.Game.Seats[0].Battlefield[0].ID != "s1-grave" {
		t.Fatalf("approved public-zone state = %+v", setup.room.Game.Seats)
	}
	if len(setup.room.Game.Log) != 1 ||
		!strings.Contains(setup.room.Game.Log[0].Text,
			"Alice moved Remote Card from Bob's graveyard to battlefield") {
		t.Fatalf("approved public-zone log = %+v", setup.room.Game.Log)
	}

	approve.ID = "reuse-public-zone-approval"
	if err := setup.handler.handleGameRespondPublicZoneMove(
		setup.guest, approve); err != nil {
		t.Fatalf("reuse approval handler: %v", err)
	}
	assertPrivateZoneError(t, receivePrivateZoneEnvelope(t, setup.guest),
		approve.ID, protocol.ErrApprovalExpired,
		"public-zone move request expired")
}
