// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package room

import (
	"strings"
	"testing"
	"time"

	"hexproof/server/internal/protocol"
)

func testDeck(format string) protocol.DeckSelect {
	deck := protocol.DeckSelect{
		Name:       "Test deck",
		Format:     format,
		DeckFormat: protocol.DefaultDeckFormatForTableMode(format),
		Mainboard: []protocol.DeckCard{
			{Name: "Sol Ring", Count: protocol.MinMainboardCards, SetCode: "CMM", CollectorNumber: "396"},
		},
		Sideboard: []protocol.DeckCard{},
	}
	if protocol.IsCommanderFormat(format) {
		deck.Commander = "Sol Ring"
	}
	return deck
}

var testNow = time.Date(2026, 7, 22, 12, 0, 0, 0, time.UTC)

func intPointer(value int) *int {
	return &value
}

func stringPointer(value string) *string {
	return &value
}

func TestSeqMonotonicPerRoom(t *testing.T) {
	r := newTestRoom(t, 4, true)
	res1, _ := r.Join("g1", "Guest1", false, "")
	res2, _ := r.Join("g2", "Guest2", false, "")
	s1 := res1.Broadcast[0].SeqValue()
	s2 := res2.Broadcast[0].SeqValue()
	if s2 != s1+1 {
		t.Fatalf("seq not monotonic: %d -> %d", s1, s2)
	}
}

func TestArrowsAndAttachmentsArePublicOwnerControlledAndSelfCleaning(t *testing.T) {
	r := newTestRoom(t, 2, true)
	if _, err := r.Join("g1", "Guest1", false, ""); err != nil {
		t.Fatalf("join player: %v", err)
	}
	if _, err := r.Join("s1", "Observer", true, ""); err != nil {
		t.Fatalf("join spectator: %v", err)
	}
	position := &protocol.CardPosition{X: 0.2, Y: 0.3}
	hostAura := protocol.GameCard{
		ID: "s0-aura", Name: "Pacifism", OwnerSeat: 0, Position: position,
	}
	hostCreature := protocol.GameCard{
		ID: "s0-creature", Name: "Bear", OwnerSeat: 0, Position: position,
	}
	guestCreature := protocol.GameCard{
		ID: "s1-creature", Name: "Dragon", OwnerSeat: 1, Position: position,
	}
	r.Phase = protocol.RoomPhaseStarted
	r.Game = &GameState{
		Number: 1, ActiveSeat: 0, CurrentPhase: protocol.GamePhaseDeclareAttackers,
		Seats: []PlayerGameState{
			{
				Seat: 0, DisplayName: "Host", Life: 20,
				Battlefield: []protocol.GameCard{hostAura, hostCreature},
			},
			{
				Seat: 1, DisplayName: "Guest1", Life: 20,
				Battlefield: []protocol.GameCard{guestCreature},
			},
		},
		Arrows:      []protocol.GameArrow{},
		Attachments: []protocol.GameAttachment{},
		Log:         []protocol.GameLogEntry{},
		NextLogID:   1,
	}

	targetSeat := 1
	if _, err := r.SetArrow("host-conn", protocol.GameSetArrow{
		SourceCardIDs:       []string{hostAura.ID, hostCreature.ID},
		TappedSourceCardIDs: []string{hostCreature.ID},
		Kind:                protocol.ArrowKindAttack,
		TargetSeat:          &targetSeat,
	}); err != nil {
		t.Fatalf("declare attacks: %v", err)
	}
	if r.Game.Seats[0].Battlefield[0].Tapped ||
		!r.Game.Seats[0].Battlefield[1].Tapped {
		t.Fatalf("atomic attacker taps = %+v", r.Game.Seats[0].Battlefield)
	}
	spectatorView, _ := r.GameSnapshot("s1")
	if len(spectatorView.Arrows) != 2 ||
		spectatorView.Arrows[0].Kind != protocol.ArrowKindAttack ||
		spectatorView.Arrows[0].TargetSeat == nil ||
		*spectatorView.Arrows[0].TargetSeat != 1 {
		t.Fatalf("spectator arrows=%+v", spectatorView.Arrows)
	}
	if _, err := r.SetArrow("host-conn", protocol.GameSetArrow{
		SourceCardIDs: []string{hostAura.ID},
		Kind:          protocol.ArrowKindAttack,
		TargetCardID:  guestCreature.ID,
	}); err != nil {
		t.Fatalf("declare attack against permanent: %v", err)
	}
	if len(r.Game.Arrows) != 2 ||
		r.Game.Arrows[1].SourceCardID != hostAura.ID ||
		r.Game.Arrows[1].TargetCardID != guestCreature.ID ||
		r.Game.Arrows[1].TargetSeat != nil {
		t.Fatalf("permanent attack arrows=%+v", r.Game.Arrows)
	}
	if log := r.Game.Log[len(r.Game.Log)-1]; !strings.Contains(log.Text, "battlefield permanent controlled by Guest1") {
		t.Fatalf("permanent attack log=%+v", log)
	}
	if _, err := r.SetArrow("host-conn", protocol.GameSetArrow{
		SourceCardIDs:       []string{hostAura.ID},
		TappedSourceCardIDs: []string{hostCreature.ID},
		Kind:                protocol.ArrowKindAttack,
		TargetSeat:          &targetSeat,
	}); err == nil || err.Error() != protocol.ErrInvalidTarget {
		t.Fatalf("tap non-source err=%v, want %q", err, protocol.ErrInvalidTarget)
	}
	if _, err := r.SetArrow("host-conn", protocol.GameSetArrow{
		SourceCardIDs: []string{hostAura.ID},
	}); err != nil {
		t.Fatalf("clear one attack: %v", err)
	}
	if len(r.Game.Arrows) != 1 ||
		r.Game.Arrows[0].SourceCardID != hostCreature.ID {
		t.Fatalf("source clear arrows=%+v", r.Game.Arrows)
	}
	if _, err := r.SetArrow("host-conn", protocol.GameSetArrow{
		SourceCardIDs: []string{hostAura.ID},
		Kind:          protocol.ArrowKindAttack,
		TargetCardID:  guestCreature.ID,
	}); err != nil {
		t.Fatalf("restore attack: %v", err)
	}
	if _, err := r.SetPhase("host-conn", protocol.GameSetPhase{
		Phase: protocol.GamePhaseDeclareBlockers,
	}); err != nil {
		t.Fatalf("advance to blockers: %v", err)
	}
	if _, err := r.SetArrow("g1", protocol.GameSetArrow{
		SourceCardIDs: []string{guestCreature.ID},
		Kind:          protocol.ArrowKindBlock,
		TargetCardID:  hostAura.ID,
	}); err != nil {
		t.Fatalf("block attacker aimed at permanent: %v", err)
	}
	if len(r.Game.Arrows) != 3 ||
		r.Game.Arrows[2].Kind != protocol.ArrowKindBlock {
		t.Fatalf("combat arrows=%+v", r.Game.Arrows)
	}
	if _, err := r.SetAttachment("g1", protocol.GameSetAttachment{
		SourceCardID: hostAura.ID, TargetCardID: guestCreature.ID,
	}); err == nil || err.Error() != protocol.ErrInvalidTarget {
		t.Fatalf("opponent attachment err=%v, want %q",
			err, protocol.ErrInvalidTarget)
	}
	if _, err := r.SetAttachment("host-conn", protocol.GameSetAttachment{
		SourceCardID: hostAura.ID, TargetCardID: guestCreature.ID,
	}); err != nil {
		t.Fatalf("attach: %v", err)
	}
	spectatorView, _ = r.GameSnapshot("s1")
	if len(spectatorView.Attachments) != 1 ||
		spectatorView.Attachments[0].SourceCardID != hostAura.ID {
		t.Fatalf("spectator attachments=%+v", spectatorView.Attachments)
	}
	if _, err := r.MoveCard("host-conn", protocol.GameMoveCard{
		CardID: hostAura.ID, FromZone: protocol.ZoneBattlefield,
		ToZone: protocol.ZoneBattlefield, ToSeat: intPointer(1),
		Position: position,
	}); err != nil {
		t.Fatalf("move owned attachment source across battlefields: %v", err)
	}
	if _, err := r.SetAttachment("g1", protocol.GameSetAttachment{
		SourceCardID: hostAura.ID,
	}); err == nil || err.Error() != protocol.ErrInvalidTarget {
		t.Fatalf("controller detached non-owned source err=%v, want %q",
			err, protocol.ErrInvalidTarget)
	}
	if _, err := r.SetAttachment("host-conn", protocol.GameSetAttachment{
		SourceCardID: hostAura.ID, TargetCardID: guestCreature.ID,
	}); err != nil {
		t.Fatalf("owner reattached cross-controlled source: %v", err)
	}
	if len(r.Game.Attachments) != 1 ||
		r.Game.Attachments[0].OwnerSeat != 0 {
		t.Fatalf("cross-controlled attachment owner=%+v", r.Game.Attachments)
	}

	if _, err := r.SetPhase("host-conn", protocol.GameSetPhase{
		Phase: protocol.GamePhaseBeginningCombat,
	}); err != nil {
		t.Fatalf("set phase: %v", err)
	}
	if len(r.Game.Arrows) != 0 {
		t.Fatalf("phase change retained arrows: %+v", r.Game.Arrows)
	}
	if _, err := r.MoveCard("g1", protocol.GameMoveCard{
		CardID: guestCreature.ID, FromZone: protocol.ZoneBattlefield,
		ToZone: protocol.ZoneGraveyard,
	}); err != nil {
		t.Fatalf("move attachment target: %v", err)
	}
	if len(r.Game.Attachments) != 0 {
		t.Fatalf("target move retained attachments: %+v", r.Game.Attachments)
	}
}

// itoa avoids importing strconv just for test labels.
func itoa(i int) string {
	if i == 0 {
		return "0"
	}
	neg := i < 0
	if neg {
		i = -i
	}
	var b [20]byte
	pos := len(b)
	for i > 0 {
		pos--
		b[pos] = byte('0' + i%10)
		i /= 10
	}
	if neg {
		pos--
		b[pos] = '-'
	}
	return string(b[pos:])
}

func TestTokenAndAbilityCounterLimits(t *testing.T) {
	r := newTestRoom(t, 2, true)
	r.Phase = protocol.RoomPhaseStarted
	battlefield := make([]protocol.GameCard, 0, protocol.MaxTokensPerSeat+1)
	for index := 0; index < protocol.MaxTokensPerSeat; index++ {
		battlefield = append(battlefield, protocol.GameCard{
			ID: "token-" + itoa(index), Name: "Token", OwnerSeat: 0, Token: true,
		})
	}
	battlefield = append(battlefield, protocol.GameCard{
		ID: "permanent", Name: "Permanent", OwnerSeat: 0,
	})
	r.Game = &GameState{
		Number: 1,
		Seats: []PlayerGameState{
			{Seat: 0, DisplayName: "Host", Battlefield: battlefield},
			{Seat: 1},
		},
		NextTokenID:       1,
		NextCardCounterID: 1,
	}
	position := &protocol.CardPosition{X: 0.5, Y: 0.5}
	if _, err := r.CreateToken("host-conn", protocol.GameCreateToken{
		Name: "Goblin", SetCode: "TKN", CollectorNumber: "1", Position: position,
	}); err == nil || err.Error() != protocol.ErrInvalidToken {
		t.Fatalf("token over limit err = %v, want %q", err, protocol.ErrInvalidToken)
	}

	for index := 0; index < protocol.MaxCardAbilityCounters; index++ {
		value := 1
		if _, err := r.SetCardCounter("host-conn", protocol.GameSetCardCounter{
			CardID: "permanent", Kind: protocol.CardCounterKindAbility,
			Label: "Ability " + itoa(index), Value: &value,
		}); err != nil {
			t.Fatalf("ability counter %d: %v", index, err)
		}
	}
	value := 1
	if _, err := r.SetCardCounter("host-conn", protocol.GameSetCardCounter{
		CardID: "permanent", Kind: protocol.CardCounterKindAbility,
		Label: "Too many", Value: &value,
	}); err == nil || err.Error() != protocol.ErrInvalidCounter {
		t.Fatalf("ability counter over limit err = %v, want %q",
			err, protocol.ErrInvalidCounter)
	}
}

func TestNextPlayerBecomesHostAfterSpectatorOnlyInterval(t *testing.T) {
	r := newTestRoom(t, 2, true)
	if _, err := r.Join("spectator", "Watcher", true, ""); err != nil {
		t.Fatalf("join spectator: %v", err)
	}
	if _, empty, err := r.ExpireDisconnected("host-conn"); err != nil || empty {
		t.Fatalf("expire host: empty=%v err=%v", empty, err)
	}
	if r.HostSeat != -1 || r.PlayerCount() != 0 || len(r.Spectators) != 1 {
		t.Fatalf("spectator-only room state: host=%d players=%d spectators=%d",
			r.HostSeat, r.PlayerCount(), len(r.Spectators))
	}
	result, err := r.Join("next-player", "Next", false, "")
	if err != nil {
		t.Fatalf("join next player: %v", err)
	}
	if r.HostSeat != 0 || !r.Seats[0].Host || !r.IsHost("next-player") {
		t.Fatalf("next player did not become host: result=%+v room=%+v", result, r)
	}
}
