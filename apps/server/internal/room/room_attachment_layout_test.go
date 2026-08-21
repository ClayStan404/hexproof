// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package room

import (
	"testing"

	"hexproof/server/internal/protocol"
)

func attachmentLayoutRoom(t *testing.T) *Room {
	t.Helper()
	r := newTestRoom(t, 2, true)
	if _, err := r.Join("g1", "Guest1", false, ""); err != nil {
		t.Fatalf("join player: %v", err)
	}
	position := func(x, y float64) *protocol.CardPosition {
		return &protocol.CardPosition{X: x, Y: y}
	}
	r.Phase = protocol.RoomPhaseStarted
	r.Game = &GameState{
		Number: 1, ActiveSeat: 0, CurrentPhase: protocol.GamePhaseFirstMain,
		Seats: []PlayerGameState{
			{
				Seat: 0, DisplayName: "Host", Life: 20,
				Battlefield: []protocol.GameCard{
					{
						ID: "s0-aura", Name: "Pacifism", OwnerSeat: 0,
						Position: position(0.10, 0.20),
					},
					{
						ID: "s0-bear", Name: "Bear", OwnerSeat: 0,
						Position: position(0.50, 0.60),
					},
					{
						ID: "s0-sword", Name: "Sword", OwnerSeat: 0,
						Position: position(0.15, 0.25),
					},
				},
			},
			{
				Seat: 1, DisplayName: "Guest1", Life: 20,
				Battlefield: []protocol.GameCard{
					{
						ID: "s1-dragon", Name: "Dragon", OwnerSeat: 1,
						Position: position(0.80, 0.90),
					},
				},
			},
		},
		Arrows:      []protocol.GameArrow{},
		Attachments: []protocol.GameAttachment{},
		Log:         []protocol.GameLogEntry{},
		NextLogID:   1,
	}
	return r
}

func cardByID(t *testing.T, r *Room, cardID string) protocol.GameCard {
	t.Helper()
	seat, index, found := r.battlefieldCard(cardID)
	if !found {
		t.Fatalf("missing card %s", cardID)
	}
	return r.Game.Seats[seat].Battlefield[index]
}

func TestSameLaneAttachSnapsSourceOntoTarget(t *testing.T) {
	r := attachmentLayoutRoom(t)
	if _, err := r.SetAttachment("host-conn", protocol.GameSetAttachment{
		SourceCardID: "s0-aura", TargetCardID: "s0-bear",
	}); err != nil {
		t.Fatalf("attach: %v", err)
	}
	aura := cardByID(t, r, "s0-aura")
	bear := cardByID(t, r, "s0-bear")
	if bear.Position == nil || aura.Position == nil {
		t.Fatalf("missing positions aura=%+v bear=%+v", aura.Position, bear.Position)
	}
	want := expectedAttachmentStack(*bear.Position, 0)
	if *aura.Position != want {
		t.Fatalf("snapped aura=%+v want %+v", *aura.Position, want)
	}
	if bear.Position.X != 0.50 || bear.Position.Y != 0.60 {
		t.Fatalf("host moved during attach: %+v", bear.Position)
	}
	if len(r.Game.Seats[0].Battlefield) != 3 || len(r.Game.Seats[1].Battlefield) != 1 {
		t.Fatalf("attach changed controllers: %+v %+v",
			r.Game.Seats[0].Battlefield, r.Game.Seats[1].Battlefield)
	}
}

func TestSameLaneAttachStacksMultipleSources(t *testing.T) {
	r := attachmentLayoutRoom(t)
	if _, err := r.SetAttachment("host-conn", protocol.GameSetAttachment{
		SourceCardID: "s0-aura", TargetCardID: "s0-bear",
	}); err != nil {
		t.Fatalf("attach aura: %v", err)
	}
	if _, err := r.SetAttachment("host-conn", protocol.GameSetAttachment{
		SourceCardID: "s0-sword", TargetCardID: "s0-bear",
	}); err != nil {
		t.Fatalf("attach sword: %v", err)
	}
	bear := cardByID(t, r, "s0-bear")
	aura := cardByID(t, r, "s0-aura")
	sword := cardByID(t, r, "s0-sword")
	if *aura.Position != expectedAttachmentStack(*bear.Position, 0) {
		t.Fatalf("first attachment %+v", aura.Position)
	}
	if *sword.Position != expectedAttachmentStack(*bear.Position, 1) {
		t.Fatalf("second attachment %+v", sword.Position)
	}
}

func expectedAttachmentStack(base protocol.CardPosition, index int) protocol.CardPosition {
	step := float64(index + 1)
	x := base.X + 0.04*step
	y := base.Y + 0.05*step
	if x > 1 {
		x = 1
	}
	if y > 1 {
		y = 1
	}
	if x < 0 {
		x = 0
	}
	if y < 0 {
		y = 0
	}
	return protocol.CardPosition{X: x, Y: y}
}

func TestCrossLaneAttachKeepsSourceOnControllerLane(t *testing.T) {
	r := attachmentLayoutRoom(t)
	before := *cardByID(t, r, "s0-aura").Position
	if _, err := r.SetAttachment("host-conn", protocol.GameSetAttachment{
		SourceCardID: "s0-aura", TargetCardID: "s1-dragon",
	}); err != nil {
		t.Fatalf("attach: %v", err)
	}
	aura := cardByID(t, r, "s0-aura")
	seat, _, found := r.battlefieldCard("s0-aura")
	if !found || seat != 0 {
		t.Fatalf("cross-lane attach moved source to seat %d", seat)
	}
	if aura.Position == nil || *aura.Position != before {
		t.Fatalf("cross-lane attach rewrote source position %+v want %+v",
			aura.Position, before)
	}
	dragon := cardByID(t, r, "s1-dragon")
	if dragon.Position.X != 0.80 || dragon.Position.Y != 0.90 {
		t.Fatalf("target moved: %+v", dragon.Position)
	}
}

func TestCrossLaneAttachmentDoesNotOffsetSameLaneStack(t *testing.T) {
	r := attachmentLayoutRoom(t)
	if _, err := r.SetAttachment("g1", protocol.GameSetAttachment{
		SourceCardID: "s1-dragon", TargetCardID: "s0-bear",
	}); err != nil {
		t.Fatalf("attach cross-lane source: %v", err)
	}
	if _, err := r.SetAttachment("host-conn", protocol.GameSetAttachment{
		SourceCardID: "s0-aura", TargetCardID: "s0-bear",
	}); err != nil {
		t.Fatalf("attach same-lane source: %v", err)
	}

	bear := cardByID(t, r, "s0-bear")
	aura := cardByID(t, r, "s0-aura")
	if aura.Position == nil || bear.Position == nil {
		t.Fatalf("missing positions aura=%+v bear=%+v", aura.Position, bear.Position)
	}
	// Cross-lane attachments render in a separate overlay stack. They must not
	// consume an index in the authoritative same-lane tabletop stack.
	want := expectedAttachmentStack(*bear.Position, 0)
	if *aura.Position != want {
		t.Fatalf("same-lane attachment position=%+v want %+v", *aura.Position, want)
	}
}

func TestSameLaneHostMoveMovesAttachedSources(t *testing.T) {
	r := attachmentLayoutRoom(t)
	if _, err := r.SetAttachment("host-conn", protocol.GameSetAttachment{
		SourceCardID: "s0-aura", TargetCardID: "s0-bear",
	}); err != nil {
		t.Fatalf("attach: %v", err)
	}
	auraBefore := *cardByID(t, r, "s0-aura").Position
	bearBefore := *cardByID(t, r, "s0-bear").Position
	newPos := &protocol.CardPosition{X: 0.70, Y: 0.40}
	if _, err := r.MoveCard("host-conn", protocol.GameMoveCard{
		CardID: "s0-bear", FromZone: protocol.ZoneBattlefield,
		ToZone: protocol.ZoneBattlefield, Position: newPos,
	}); err != nil {
		t.Fatalf("move host: %v", err)
	}
	bear := cardByID(t, r, "s0-bear")
	aura := cardByID(t, r, "s0-aura")
	if bear.Position == nil || *bear.Position != *newPos {
		t.Fatalf("host position %+v", bear.Position)
	}
	want := protocol.CardPosition{
		X: auraBefore.X + (newPos.X - bearBefore.X),
		Y: auraBefore.Y + (newPos.Y - bearBefore.Y),
	}
	if aura.Position == nil || *aura.Position != want {
		t.Fatalf("followed aura %+v want %+v", aura.Position, want)
	}
	seat, _, _ := r.battlefieldCard("s0-aura")
	if seat != 0 {
		t.Fatalf("follow changed controller to %d", seat)
	}
}

func TestMovingAttachedSourceDoesNotMoveHost(t *testing.T) {
	r := attachmentLayoutRoom(t)
	if _, err := r.SetAttachment("host-conn", protocol.GameSetAttachment{
		SourceCardID: "s0-aura", TargetCardID: "s0-bear",
	}); err != nil {
		t.Fatalf("attach: %v", err)
	}
	bearBefore := *cardByID(t, r, "s0-bear").Position
	newPos := &protocol.CardPosition{X: 0.22, Y: 0.33}
	if _, err := r.MoveCard("host-conn", protocol.GameMoveCard{
		CardID: "s0-aura", FromZone: protocol.ZoneBattlefield,
		ToZone: protocol.ZoneBattlefield, Position: newPos,
	}); err != nil {
		t.Fatalf("move source: %v", err)
	}
	if *cardByID(t, r, "s0-bear").Position != bearBefore {
		t.Fatalf("host moved when source was dragged")
	}
	if *cardByID(t, r, "s0-aura").Position != *newPos {
		t.Fatalf("source position %+v", cardByID(t, r, "s0-aura").Position)
	}
	if len(r.Game.Attachments) != 1 {
		t.Fatalf("independent source move detached: %+v", r.Game.Attachments)
	}
}
