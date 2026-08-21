// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package protocol

import (
	"bytes"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"reflect"
	"testing"
)

// fixturePath resolves a path under testdata/protocol/v1 relative to this
// package's source directory (apps/server/internal/protocol). The four-level
// ascent reaches the repo root. This makes the golden fixtures a shared truth
// source exercised by both client and server tests.
const fixtureDir = "../../../../testdata/protocol/v1"

func loadFixture(t *testing.T, name string) []byte {
	t.Helper()
	data, err := os.ReadFile(filepath.Join(fixtureDir, name))
	if err != nil {
		t.Fatalf("read fixture %s: %v", name, err)
	}
	return data
}

// TestAllFixturesParseAndRoundTrip keeps every shared JSON fixture live. This
// intentionally auto-discovers files so adding a fixture cannot silently leave
// the Go side behind the client fixture traversal.
func TestAllFixturesParseAndRoundTrip(t *testing.T) {
	paths, err := filepath.Glob(filepath.Join(fixtureDir, "*.json"))
	if err != nil {
		t.Fatalf("list fixtures: %v", err)
	}
	if len(paths) == 0 {
		t.Fatal("no protocol fixtures found")
	}
	for _, path := range paths {
		path := path
		t.Run(filepath.Base(path), func(t *testing.T) {
			data, err := os.ReadFile(path)
			if err != nil {
				t.Fatalf("read fixture: %v", err)
			}
			env, err := ParseEnvelope(data)
			if err != nil {
				t.Fatalf("parse fixture: %v", err)
			}
			roundTripped, err := env.Marshal()
			if err != nil {
				t.Fatalf("marshal fixture: %v", err)
			}
			var want, got any
			if err := json.Unmarshal(data, &want); err != nil {
				t.Fatalf("decode original fixture: %v", err)
			}
			if err := json.Unmarshal(roundTripped, &got); err != nil {
				t.Fatalf("decode round-tripped fixture: %v", err)
			}
			if !reflect.DeepEqual(got, want) {
				t.Fatalf("round trip changed fixture:\nwant: %s\n got: %s",
					data, roundTripped)
			}
		})
	}
}

func fixturePayloadForType(messageType string) any {
	switch messageType {
	case TypeSessionHello:
		return &SessionHello{}
	case TypeSessionWelcome:
		return &SessionWelcome{}
	case TypeSessionPing, TypeSessionPong:
		return &struct{}{}
	case TypeRoomCreate:
		return &RoomCreate{}
	case TypeRoomCreated:
		return &RoomCreated{}
	case TypeRoomJoin:
		return &RoomJoin{}
	case TypeRoomJoined:
		return &RoomJoined{}
	case TypeRoomLeave, TypeRoomList, TypeRoomDisband:
		return &struct{}{}
	case TypeRoomLeft, TypeRoomKicked, TypeRoomDisbanded:
		return &RoomLeft{}
	case TypeRoomKick:
		return &RoomKick{}
	case TypeRoomSnapshot:
		return &RoomSnapshot{}
	case TypeRoomListed:
		return &RoomListed{}
	case TypeTournamentList, TypeTournamentLeave, TypeTournamentStart,
		TypeTournamentNextRound, TypeTournamentCancel:
		return &EmptyPayload{}
	case TypeTournamentListed:
		return &TournamentListed{}
	case TypeTournamentCreate:
		return &TournamentCreate{}
	case TypeTournamentCreated:
		return &TournamentCreated{}
	case TypeTournamentEnter:
		return &TournamentEnter{}
	case TypeTournamentEntered:
		return &TournamentEntered{}
	case TypeTournamentLeft:
		return &TournamentLeft{}
	case TypeTournamentRegister:
		return &TournamentRegister{}
	case TypeTournamentRegistered:
		return &TournamentRegistered{}
	case TypeTournamentUnregister, TypeTournamentDrop:
		return &TournamentParticipantCommand{}
	case TypeTournamentCheckIn:
		return &TournamentCheckIn{}
	case TypeTournamentUnregistered, TypeTournamentCheckInSet,
		TypeTournamentStarted, TypeTournamentDropped,
		TypeTournamentResultReported, TypeTournamentResultConfirmed,
		TypeTournamentResultRejected, TypeTournamentResultCorrected,
		TypeTournamentRoundStarted, TypeTournamentCancelled:
		return &TournamentChanged{}
	case TypeTournamentReportResult, TypeTournamentCorrectResult:
		return &TournamentResultCommand{}
	case TypeTournamentConfirmResult, TypeTournamentRejectResult,
		TypeTournamentOpenMatch:
		return &TournamentPairingCommand{}
	case TypeTournamentMatchOpened:
		return &TournamentMatchOpened{}
	case TypeTournamentSnapshot:
		return &TournamentSnapshot{}
	case TypeDeckSelect:
		return &DeckSelect{}
	case TypeDeckSelected:
		return &DeckSelected{}
	case TypePlayerReady:
		return &PlayerReady{}
	case TypePlayerReadyChanged:
		return &PlayerReadyChanged{}
	case TypeMatchLoadRequired:
		return &MatchLoadRequired{}
	case TypeClientLoadComplete:
		return &ClientLoadComplete{}
	case TypeClientLoadCompleted:
		return &ClientLoadCompleted{}
	case TypeMatchStarted:
		return &MatchStarted{}
	case TypeGameSnapshot:
		return &GameSnapshot{}
	case TypeGameDraw:
		return &GameDraw{}
	case TypeGameDrawn:
		return &GameDrawn{}
	case TypeGameShuffleLibrary:
		return &GameShuffleLibrary{}
	case TypeGameLibraryShuffled:
		return &GameLibraryShuffled{}
	case TypeGameMulligan:
		return &GameMulligan{}
	case TypeGameMulliganed:
		return &GameMulliganed{}
	case TypeGameDiscardHand:
		return &GameDiscardHand{}
	case TypeGameHandDiscarded:
		return &GameHandDiscarded{}
	case TypeGameMoveCard:
		return &GameMoveCard{}
	case TypeGameCardMoved:
		return &GameCardMoved{}
	case TypeGamePublicZoneMovePending:
		return &GamePublicZoneMovePending{}
	case TypeGamePublicZoneMoveRequested:
		return &GamePublicZoneMoveRequested{}
	case TypeGameRespondPublicZoneMove:
		return &GameRespondPublicZoneMove{}
	case TypeGamePublicZoneMoveResponded:
		return &GamePublicZoneMoveResponded{}
	case TypeGameArrangeBattlefield:
		return &GameArrangeBattlefield{}
	case TypeGameBattlefieldArranged:
		return &GameBattlefieldArranged{}
	case TypeGameSetTapped:
		return &GameSetTapped{}
	case TypeGameTappedSet:
		return &GameTappedSet{}
	case TypeGameSetCardFace:
		return &GameSetCardFace{}
	case TypeGameCardFaceSet:
		return &GameCardFaceSet{}
	case TypeGameSetFaceDown:
		return &GameSetFaceDown{}
	case TypeGameFaceDownSet:
		return &GameFaceDownSet{}
	case TypeGameSetCardCounter:
		return &GameSetCardCounter{}
	case TypeGameCardCounterSet:
		return &GameCardCounterSet{}
	case TypeGameSetPhase:
		return &GameSetPhase{}
	case TypeGamePhaseSet:
		return &GamePhaseSet{}
	case TypeGameSetResponseStatus:
		return &GameSetResponseStatus{}
	case TypeGameResponseStatusSet:
		return &GameResponseStatusSet{}
	case TypeGameNextTurn:
		return &GameNextTurn{}
	case TypeGameTurnAdvanced:
		return &GameTurnAdvanced{}
	case TypeGameReveal:
		return &GameReveal{}
	case TypeGameRevealed:
		return &GameRevealed{}
	case TypeGameRecallRevealed:
		return &GameRecallRevealed{}
	case TypeGameRevealedRecalled:
		return &GameRevealedRecalled{}
	case TypeGameMoveCards:
		return &GameMoveCards{}
	case TypeGameCardsMoved:
		return &GameCardsMoved{}
	case TypeGameMoveLibraryCards:
		return &GameMoveLibraryCards{}
	case TypeGameLibraryCardsMoved:
		return &GameLibraryCardsMoved{}
	case TypeGameDumpZone:
		return &GameDumpZone{}
	case TypeGameZoneDumpPending:
		return &GameZoneDumpPending{}
	case TypeGameZoneDumpRequested:
		return &GameZoneDumpRequested{}
	case TypeGameRespondZoneDump:
		return &GameRespondZoneDump{}
	case TypeGameZoneDumpResponded:
		return &GameZoneDumpResponded{}
	case TypeGameZoneDumped:
		return &GameZoneDumped{}
	case TypeGameSearchLibrary:
		return &GameSearchLibrary{}
	case TypeGameLibrarySearched:
		return &GameLibrarySearched{}
	case TypeGameReorderLibrary:
		return &GameReorderLibrary{}
	case TypeGameLibraryReordered:
		return &GameLibraryReordered{}
	case TypeGameResolveLibraryView:
		return &GameResolveLibraryView{}
	case TypeGameLibraryViewResolved:
		return &GameLibraryViewResolved{}
	case TypeGameSetCounter:
		return &GameSetCounter{}
	case TypeGameCounterSet:
		return &GameCounterSet{}
	case TypeGameSetCounterCount:
		return &GameSetCounterCount{}
	case TypeGameCounterCountSet:
		return &GameCounterCountSet{}
	case TypeGameConcede:
		return &GameConcede{}
	case TypeGameConceded:
		return &GameConceded{}
	case TypeGameDeclareDraw:
		return &GameDeclareDraw{}
	case TypeGameDrawDeclared:
		return &GameDrawDeclared{}
	case TypeGameRestart:
		return &GameRestart{}
	case TypeGameRestarted:
		return &GameRestarted{}
	case TypeGameRoll:
		return &GameRoll{}
	case TypeGameRolled:
		return &GameRolled{}
	case TypeGameFlipCoin:
		return &GameFlipCoin{}
	case TypeGameCoinFlipped:
		return &GameCoinFlipped{}
	case TypeGameRandomSelect:
		return &GameRandomSelect{}
	case TypeGameRandomSelected:
		return &GameRandomSelected{}
	case TypeGameReturnToRoom:
		return &GameReturnToRoom{}
	case TypeGameReturnedToRoom:
		return &GameReturnedToRoom{}
	case TypeGameSay:
		return &GameSay{}
	case TypeGameSaid:
		return &GameSaid{}
	case TypeGameCreateToken:
		return &GameCreateToken{}
	case TypeGameTokenCreated:
		return &GameTokenCreated{}
	case TypeGameAdjustCommanderTax:
		return &GameAdjustCommanderTax{}
	case TypeGameCommanderTaxAdjusted:
		return &GameCommanderTaxAdjusted{}
	case TypeGameCastCommander:
		return &GameCastCommander{}
	case TypeGameCommanderCast:
		return &GameCommanderCast{}
	case TypeGameSetCommanderDamage:
		return &GameSetCommanderDamage{}
	case TypeGameCommanderDamageSet:
		return &GameCommanderDamageSet{}
	case TypeGamePlayLand:
		return &GamePlayLand{}
	case TypeGameLandPlayed:
		return &GameLandPlayed{}
	case TypeGameSetLandPlayCount:
		return &GameSetLandPlayCount{}
	case TypeGameLandPlayCountSet:
		return &GameLandPlayCountSet{}
	case TypeGameSetArrow:
		return &GameSetArrow{}
	case TypeGameArrowSet:
		return &GameArrowSet{}
	case TypeGameSetAttachment:
		return &GameSetAttachment{}
	case TypeGameAttachmentSet:
		return &GameAttachmentSet{}
	case TypeReplayList:
		return &struct{}{}
	case TypeReplayListed:
		return &ReplayListed{}
	case TypeReplayGet:
		return &ReplayGet{}
	case TypeReplayLoaded:
		return &ReplayLoaded{}
	case TypeSideboardMove:
		return &SideboardMove{}
	case TypeSideboardMoved:
		return &SideboardMoved{}
	case TypeSideboardSetCommander:
		return &SideboardSetCommander{}
	case TypeSideboardCommanderSet:
		return &SideboardCommanderSet{}
	case TypeSideboardReady:
		return &SideboardReady{}
	case TypeSideboardReadyChanged:
		return &SideboardReadyChanged{}
	case TypeSideboardCompleted:
		return &SideboardCompleted{}
	case TypeError:
		return &ErrorPayload{}
	default:
		return nil
	}
}

func normalizeGameSnapshotFixture(snapshot *GameSnapshot,
	rawPayload json.RawMessage) {
	if snapshot.Stack == nil {
		snapshot.Stack = []GameSharedCard{}
	}
	if snapshot.Revealed == nil {
		snapshot.Revealed = []GameSharedCard{}
	}
	if snapshot.Arrows == nil {
		snapshot.Arrows = []GameArrow{}
	}
	if snapshot.Attachments == nil {
		snapshot.Attachments = []GameAttachment{}
	}
	if snapshot.Log == nil {
		snapshot.Log = []GameLogEntry{}
	}
	if snapshot.Score == nil {
		snapshot.Score = []int{}
	}

	var raw map[string]any
	_ = json.Unmarshal(rawPayload, &raw)
	rawSeats, _ := raw["seats"].([]any)
	for seatIndex := range snapshot.Seats {
		seat := &snapshot.Seats[seatIndex]
		if len(seat.Counters) == 0 {
			seat.Counters = make([]GamePlayerCounter,
				PlayerCounterSlotCount)
			for counterIndex := range seat.Counters {
				seat.Counters[counterIndex] = GamePlayerCounter{
					Key: fmt.Sprintf("%s%d", PlayerCounterSlotPrefix,
						counterIndex+1),
				}
			}
		}
		if seat.Battlefield == nil {
			seat.Battlefield = []GameCard{}
		}
		if seat.Graveyard == nil {
			seat.Graveyard = []GameCard{}
		}
		if seat.Exile == nil {
			seat.Exile = []GameCard{}
		}
		if seatIndex >= len(rawSeats) {
			continue
		}
		rawSeat, _ := rawSeats[seatIndex].(map[string]any)
		fillMissingOwnerSeats(seat.Hand, rawSeat["hand"], seat.Seat)
		fillMissingOwnerSeats(
			seat.Battlefield, rawSeat["battlefield"], seat.Seat)
		fillMissingOwnerSeats(
			seat.Graveyard, rawSeat["graveyard"], seat.Seat)
		fillMissingOwnerSeats(seat.Exile, rawSeat["exile"], seat.Seat)
		fillMissingOwnerSeats(
			seat.CommandZone, rawSeat["commandZone"], seat.Seat)
	}
}

func fillMissingOwnerSeats(cards []GameCard, rawCards any, seat int) {
	rawList, _ := rawCards.([]any)
	for index := range cards {
		if index >= len(rawList) {
			continue
		}
		rawCard, _ := rawList[index].(map[string]any)
		if _, present := rawCard["ownerSeat"]; !present {
			cards[index].OwnerSeat = seat
		}
	}
}

func TestAllFixturesMatchTypedMarshalShape(t *testing.T) {
	paths, err := filepath.Glob(filepath.Join(fixtureDir, "*.json"))
	if err != nil {
		t.Fatalf("list fixtures: %v", err)
	}
	for _, path := range paths {
		path := path
		t.Run(filepath.Base(path), func(t *testing.T) {
			data, err := os.ReadFile(path)
			if err != nil {
				t.Fatalf("read fixture: %v", err)
			}
			env, err := ParseEnvelope(data)
			if err != nil {
				t.Fatalf("parse fixture: %v", err)
			}
			payload := fixturePayloadForType(env.Type)
			if payload == nil {
				t.Fatalf("fixture type %q has no typed payload mapping", env.Type)
			}
			payloadWasAbsent := len(env.Payload) == 0
			rawPayload := env.Payload
			if len(rawPayload) == 0 {
				rawPayload = json.RawMessage(`{}`)
			}
			if err := json.Unmarshal(rawPayload, payload); err != nil {
				t.Fatalf("decode typed payload: %v", err)
			}
			if snapshot, ok := payload.(*GameSnapshot); ok &&
				os.Getenv("UPDATE_PROTOCOL_FIXTURES") == "1" {
				normalizeGameSnapshotFixture(snapshot, rawPayload)
			}
			typedPayload, err := json.Marshal(payload)
			if err != nil {
				t.Fatalf("marshal typed payload: %v", err)
			}
			if os.Getenv("UPDATE_PROTOCOL_FIXTURES") == "1" {
				if payloadWasAbsent &&
					bytes.Equal(typedPayload, []byte(`{}`)) {
					env.Payload = nil
				} else {
					env.Payload = typedPayload
				}
				updated, err := json.MarshalIndent(env, "", "  ")
				if err != nil {
					t.Fatalf("marshal updated fixture: %v", err)
				}
				updated = append(updated, '\n')
				if err := os.WriteFile(path, updated, 0o644); err != nil {
					t.Fatalf("write updated fixture: %v", err)
				}
				return
			}
			var want, got any
			if err := json.Unmarshal(rawPayload, &want); err != nil {
				t.Fatalf("normalize fixture payload: %v", err)
			}
			if err := json.Unmarshal(typedPayload, &got); err != nil {
				t.Fatalf("normalize typed payload: %v", err)
			}
			if !reflect.DeepEqual(got, want) {
				t.Fatalf("fixture payload differs from typed marshal:\nwant: %s\n got: %s",
					rawPayload, typedPayload)
			}
			if snapshot, ok := payload.(*GameSnapshot); ok {
				for _, seat := range snapshot.Seats {
					if len(seat.Counters) != PlayerCounterSlotCount {
						t.Fatalf("seat %d has %d counters, want %d",
							seat.Seat, len(seat.Counters),
							PlayerCounterSlotCount)
					}
				}
			}
		})
	}
}

// topKeys decodes a JSON object's top-level keys for assertions.
func topKeys(t *testing.T, data []byte) map[string]json.RawMessage {
	t.Helper()
	var m map[string]json.RawMessage
	if err := json.Unmarshal(data, &m); err != nil {
		t.Fatalf("decode top-level: %v", err)
	}
	return m
}

func TestSessionHelloRoundTrip(t *testing.T) {
	env, err := NewEnvelope(TypeSessionHello, SessionHello{
		DisplayName:   "Alice",
		ClientVersion: "0.1.0",
		Protocol:      ProtocolVersion,
	})
	if err != nil {
		t.Fatalf("new envelope: %v", err)
	}
	env.ID = "req-1"

	data, err := env.Marshal()
	if err != nil {
		t.Fatalf("marshal: %v", err)
	}

	got, err := ParseEnvelope(data)
	if err != nil {
		t.Fatalf("parse: %v", err)
	}
	if got.Type != TypeSessionHello {
		t.Fatalf("type = %q, want %q", got.Type, TypeSessionHello)
	}
	if got.ID != "req-1" {
		t.Fatalf("id = %q, want req-1 (correlation echo)", got.ID)
	}

	var h SessionHello
	if err := got.DecodePayload(&h); err != nil {
		t.Fatalf("decode payload: %v", err)
	}
	if h.DisplayName != "Alice" {
		t.Fatalf("displayName = %q", h.DisplayName)
	}
}

// session.hello must NOT carry a top-level `v`; the offer lives in payload.protocol.
func TestSessionHelloHasNoTopLevelV(t *testing.T) {
	env, _ := NewEnvelope(TypeSessionHello, SessionHello{Protocol: ProtocolVersion})
	data, _ := env.Marshal()
	if _, ok := topKeys(t, data)["v"]; ok {
		t.Fatalf("session.hello must not carry top-level v: %s", data)
	}
}

// session.welcome is the ONLY message that authoritatively carries `v`, and it
// does so ONLY inside its payload.
func TestSessionWelcomeCarriesVOnlyInPayload(t *testing.T) {
	env, err := NewEnvelope(TypeSessionWelcome, SessionWelcome{
		V:             ProtocolVersion,
		ConnectionID:  "conn-7F3A",
		ServerVersion: "0.1.0",
	})
	if err != nil {
		t.Fatalf("new envelope: %v", err)
	}
	data, err := env.Marshal()
	if err != nil {
		t.Fatalf("marshal: %v", err)
	}

	keys := topKeys(t, data)
	if _, ok := keys["v"]; ok {
		t.Fatalf("welcome must not carry top-level v: %s", data)
	}

	var w SessionWelcome
	if err := json.Unmarshal(keys["payload"], &w); err != nil {
		t.Fatalf("decode welcome payload: %v", err)
	}
	if w.V != ProtocolVersion {
		t.Fatalf("welcome payload v = %q, want %q", w.V, ProtocolVersion)
	}

	if err := ValidateWelcome(w); err != nil {
		t.Fatalf("validate welcome: %v", err)
	}
}

func TestValidateWelcomeRejectsWrongVersion(t *testing.T) {
	if err := ValidateWelcome(SessionWelcome{V: "bogus.v0"}); err == nil {
		t.Fatal("expected error for wrong protocol version")
	}
}

func TestFormatCapabilities(t *testing.T) {
	if got := FormatMaxSeats(FormatDuel); got != 2 {
		t.Fatalf("duel max seats = %d, want 2", got)
	}
	if !IsCommanderFormat(FormatDuel) || !IsCommanderFormat(FormatEDH) ||
		IsCommanderFormat(FormatModern) {
		t.Fatal("commander format classification is incorrect")
	}
	if !IsTwoPlayerFormat(FormatModern) || !IsTwoPlayerFormat(FormatDuel) ||
		IsTwoPlayerFormat(FormatEDH) {
		t.Fatal("two-player format classification is incorrect")
	}
	deckFormats := map[string]string{
		DeckFormatCustom: FormatModern, DeckFormatStandard: FormatModern,
		DeckFormatPioneer: FormatModern, DeckFormatModern: FormatModern,
		DeckFormatLegacy: FormatModern, DeckFormatVintage: FormatModern,
		DeckFormatPauper: FormatModern, DeckFormatDuel: FormatDuel,
		DeckFormatCommander: FormatEDH,
	}
	for deckFormat, tableMode := range deckFormats {
		if !ValidDeckFormat(deckFormat) || TableModeForDeckFormat(deckFormat) != tableMode {
			t.Fatalf("deck format %q did not map to %q", deckFormat, tableMode)
		}
	}
	if DefaultDeckFormatForTableMode(FormatModern) != DeckFormatCustom {
		t.Fatal("legacy generic 1v1 must migrate to custom, not Modern")
	}
}

// Post-welcome messages (e.g. room.create) carry no `v` at all and must parse
// without one. This rejects treating post-welcome messages as requiring `v`.
func TestPostWelcomeParsesWithoutV(t *testing.T) {
	raw := []byte(`{"type":"room.create","id":"c1","payload":{"name":"Friday EDH","format":"edh","deckFormat":"commander","maxSeats":4}}`)
	env, err := ParseEnvelope(raw)
	if err != nil {
		t.Fatalf("parse post-welcome message without v: %v", err)
	}
	if env.Type != TypeRoomCreate {
		t.Fatalf("type = %q, want %q", env.Type, TypeRoomCreate)
	}
	if env.ID != "c1" {
		t.Fatalf("id = %q, want c1", env.ID)
	}
}

func TestErrorRoundTrip(t *testing.T) {
	env, err := NewEnvelope(TypeError, ErrorPayload{
		Code:            ErrClientVersionMismatch,
		Message:         "Client update required",
		ClientVersion:   "0.1.0",
		RequiredVersion: "0.2.0",
	})
	if err != nil {
		t.Fatalf("new envelope: %v", err)
	}
	env.ID = "req-9"

	data, _ := env.Marshal()
	got, err := ParseEnvelope(data)
	if err != nil {
		t.Fatalf("parse: %v", err)
	}
	if got.Type != TypeError {
		t.Fatalf("type = %q", got.Type)
	}
	if got.ID != "req-9" {
		t.Fatalf("error must echo correlation id; got %q", got.ID)
	}
	var payload ErrorPayload
	if err := got.DecodePayload(&payload); err != nil {
		t.Fatalf("decode error payload: %v", err)
	}
	if payload.Code != ErrClientVersionMismatch ||
		payload.ClientVersion != "0.1.0" ||
		payload.RequiredVersion != "0.2.0" {
		t.Fatalf("error payload = %+v", payload)
	}
}

func TestParseEnvelopeRejectsGarbage(t *testing.T) {
	if _, err := ParseEnvelope([]byte("{not json")); err == nil {
		t.Fatal("expected error parsing garbage")
	}
}

// An empty `type` is not a valid envelope (P1: ParseEnvelope rejects it so
// inbound dispatch never sees a typeless message).
func TestParseEnvelopeRejectsEmptyType(t *testing.T) {
	if _, err := ParseEnvelope([]byte(`{"id":"x","payload":{}}`)); err == nil {
		t.Fatal("expected error for missing type")
	}
}

// seq is per-room, 1-based. A set seq (even 0, though we never emit 0) must
// survive a round-trip - the old omitempty silently dropped 0.
func TestSeqRoundTrip(t *testing.T) {
	env, _ := NewEnvelope(TypeRoomSnapshot, RoomSnapshot{RoomID: "ABCDEF"})
	seq := int64(1)
	env.SeqPtr = &seq

	data, err := env.Marshal()
	if err != nil {
		t.Fatalf("marshal: %v", err)
	}
	got, err := ParseEnvelope(data)
	if err != nil {
		t.Fatalf("parse: %v", err)
	}
	if !got.HasSeq() {
		t.Fatalf("seq lost in round-trip: %s", data)
	}
	if got.SeqValue() != 1 {
		t.Fatalf("seq = %d, want 1", got.SeqValue())
	}
}

// Absent seq stays absent (no "seq":0 leaked).
func TestSeqAbsentWhenUnset(t *testing.T) {
	env, _ := NewEnvelope(TypeRoomSnapshot, RoomSnapshot{RoomID: "ABCDEF"})
	data, _ := env.Marshal()
	var raw map[string]json.RawMessage
	_ = json.Unmarshal(data, &raw)
	if _, ok := raw["seq"]; ok {
		t.Fatalf("unset seq should be absent: %s", data)
	}
	got, _ := ParseEnvelope(data)
	if got.HasSeq() {
		t.Fatal("unset seq should parse as absent")
	}
}

func TestValidGamePhasePinsElevenCoordinationSteps(t *testing.T) {
	phases := []string{
		GamePhaseUntap,
		GamePhaseUpkeep,
		GamePhaseDraw,
		GamePhaseFirstMain,
		GamePhaseBeginningCombat,
		GamePhaseDeclareAttackers,
		GamePhaseDeclareBlockers,
		GamePhaseCombatDamage,
		GamePhaseEndCombat,
		GamePhaseSecondMain,
		GamePhaseEnd,
	}
	if len(phases) != 11 {
		t.Fatalf("phase count = %d, want 11", len(phases))
	}
	seen := make(map[string]bool, len(phases))
	for _, phase := range phases {
		if !ValidGamePhase(phase) {
			t.Errorf("ValidGamePhase(%q) = false", phase)
		}
		if seen[phase] {
			t.Errorf("duplicate phase identifier %q", phase)
		}
		seen[phase] = true
	}
	for _, invalid := range []string{"", "combat", "pass", "UNTAP"} {
		if ValidGamePhase(invalid) {
			t.Errorf("ValidGamePhase(%q) = true, want false", invalid)
		}
	}
}

func TestP5GoldenFixturesPinTokensEDHAndSideboardPrivacy(t *testing.T) {
	tokenEnvelope, err := ParseEnvelope(loadFixture(t, "game-create-token.json"))
	if err != nil {
		t.Fatalf("parse token command: %v", err)
	}
	var token GameCreateToken
	if err := tokenEnvelope.DecodePayload(&token); err != nil {
		t.Fatalf("decode token command: %v", err)
	}
	if tokenEnvelope.Type != TypeGameCreateToken || tokenEnvelope.ID != "t1" ||
		token.Name != "Goblin" || token.Position == nil ||
		token.Position.X != 0.5 || token.Position.Y != 0.3 {
		t.Fatalf("token fixture = env %+v payload %+v", tokenEnvelope, token)
	}

	taxEnvelope, err := ParseEnvelope(loadFixture(t, "game-adjust-commander-tax.json"))
	if err != nil {
		t.Fatalf("parse commander tax: %v", err)
	}
	var tax GameAdjustCommanderTax
	if err := taxEnvelope.DecodePayload(&tax); err != nil {
		t.Fatalf("decode commander tax: %v", err)
	}
	if taxEnvelope.Type != TypeGameAdjustCommanderTax ||
		tax.CommanderID != "s0-c1" || tax.Delta != 1 {
		t.Fatalf("commander tax fixture = env %+v payload %+v", taxEnvelope, tax)
	}

	edhEnvelope, err := ParseEnvelope(loadFixture(t, "game-snapshot-edh.json"))
	if err != nil {
		t.Fatalf("parse EDH snapshot: %v", err)
	}
	var edh GameSnapshot
	if err := edhEnvelope.DecodePayload(&edh); err != nil {
		t.Fatalf("decode EDH snapshot: %v", err)
	}
	if len(edh.Seats) != 4 || len(edh.Seats[0].CommandZone) != 1 ||
		edh.Seats[0].CommanderTax != 2 || edh.Seats[0].CommanderTaxes["s0-c1"] != 2 ||
		!edh.Seats[1].Eliminated ||
		len(edh.Seats[3].Battlefield) != 1 ||
		!edh.Seats[3].Battlefield[0].Token || edh.Sideboard != nil {
		t.Fatalf("EDH fixture = %+v", edh)
	}

	ownerEnvelope, err := ParseEnvelope(
		loadFixture(t, "game-snapshot-sideboard-owner.json"))
	if err != nil {
		t.Fatalf("parse owner sideboard: %v", err)
	}
	var owner GameSnapshot
	if err := ownerEnvelope.DecodePayload(&owner); err != nil {
		t.Fatalf("decode owner sideboard: %v", err)
	}
	spectatorData := loadFixture(t, "game-snapshot-sideboard-spectator.json")
	spectatorEnvelope, err := ParseEnvelope(spectatorData)
	if err != nil {
		t.Fatalf("parse spectator sideboard: %v", err)
	}
	var spectator GameSnapshot
	if err := spectatorEnvelope.DecodePayload(&spectator); err != nil {
		t.Fatalf("decode spectator sideboard: %v", err)
	}
	if owner.Sideboard == nil || len(owner.Sideboard.Mainboard) != 1 ||
		len(owner.Sideboard.Sideboard) != 1 ||
		owner.Sideboard.Mainboard[0].TypeLine != "Instant" ||
		owner.Sideboard.Sideboard[0].TypeLine != "Instant" ||
		spectator.Sideboard == nil ||
		len(spectator.Sideboard.Mainboard) != 0 ||
		len(spectator.Sideboard.Sideboard) != 0 ||
		len(spectator.Sideboard.Seats) != 2 ||
		bytes.Contains(spectatorData, []byte("Lightning Bolt")) ||
		bytes.Contains(spectatorData, []byte("Wear // Tear")) {
		t.Fatalf("sideboard privacy owner=%+v spectator=%+v",
			owner.Sideboard, spectator.Sideboard)
	}

	moveEnvelope, err := ParseEnvelope(loadFixture(t, "sideboard-move.json"))
	if err != nil {
		t.Fatalf("parse sideboard move: %v", err)
	}
	var move SideboardMove
	if err := moveEnvelope.DecodePayload(&move); err != nil {
		t.Fatalf("decode sideboard move: %v", err)
	}
	if moveEnvelope.Type != TypeSideboardMove ||
		move.FromZone != SideboardZoneSide || move.ToZone != SideboardZoneMain {
		t.Fatalf("sideboard move fixture = env %+v payload %+v",
			moveEnvelope, move)
	}
}

func TestP7GoldenFixturesPinDiscoveryUndoRelationsAndReplayPrivacy(t *testing.T) {
	listEnvelope, err := ParseEnvelope(loadFixture(t, "room-listed.json"))
	if err != nil {
		t.Fatalf("parse room list: %v", err)
	}
	var listed RoomListed
	if err := listEnvelope.DecodePayload(&listed); err != nil {
		t.Fatalf("decode room list: %v", err)
	}
	if len(listed.Rooms) != 1 || !listed.Rooms[0].HasPassword ||
		!listed.Rooms[0].PlayerJoinable ||
		listed.Rooms[0].PlayerCount != 1 ||
		listed.Rooms[0].CardLoadMode != CardLoadPreload {
		t.Fatalf("room list fixture = %+v", listed)
	}

	ownerEnvelope, err := ParseEnvelope(
		loadFixture(t, "game-snapshot-p7-owner.json"))
	if err != nil {
		t.Fatalf("parse owner P7 snapshot: %v", err)
	}
	spectatorBytes := loadFixture(t, "game-snapshot-p7-spectator.json")
	spectatorEnvelope, err := ParseEnvelope(spectatorBytes)
	if err != nil {
		t.Fatalf("parse spectator P7 snapshot: %v", err)
	}
	var owner, spectator GameSnapshot
	if err := ownerEnvelope.DecodePayload(&owner); err != nil {
		t.Fatalf("decode owner P7 snapshot: %v", err)
	}
	if err := spectatorEnvelope.DecodePayload(&spectator); err != nil {
		t.Fatalf("decode spectator P7 snapshot: %v", err)
	}
	if len(owner.Seats[0].Hand) != 1 {
		t.Fatalf("owner private projection = %+v", owner.Seats[0])
	}
	if len(spectator.Seats[0].Hand) != 0 ||
		bytes.Contains(spectatorBytes, []byte("s0-secret")) ||
		bytes.Contains(spectatorBytes, []byte("Demonic Tutor")) {
		t.Fatalf("spectator projection leaked private draw: %s",
			spectatorBytes)
	}
	if len(spectator.Arrows) != 1 || len(spectator.Attachments) != 1 {
		t.Fatalf("public relations missing: %+v %+v",
			spectator.Arrows, spectator.Attachments)
	}

	replayBytes := loadFixture(t, "replay-loaded.json")
	var replay ReplayLoaded
	replayEnvelope, err := ParseEnvelope(replayBytes)
	if err != nil {
		t.Fatalf("parse replay: %v", err)
	}
	if err := replayEnvelope.DecodePayload(&replay); err != nil {
		t.Fatalf("decode replay: %v", err)
	}
	if len(replay.Log) != 2 || replay.Replay.LogEntryCount != 12 ||
		bytes.Contains(replayBytes, []byte(`"hand"`)) ||
		bytes.Contains(replayBytes, []byte(`"library"`)) ||
		bytes.Contains(replayBytes, []byte(`"deck"`)) {
		t.Fatalf("public replay fixture = %s", replayBytes)
	}
}

// TestGoldenFixtures pins the JSON files under testdata/protocol/v1 to the
// shapes this package produces/consumes. If a fixture drifts from the wire
// rules (top-level `v` where forbidden, missing `v` in welcome payload, etc.)
// or from the Envelope round-trip, this test fails - so the fixtures are a
// live golden source shared by client and server, not orphaned samples.
func TestGoldenFixtures(t *testing.T) {
	t.Run("session-hello.json", func(t *testing.T) {
		data := loadFixture(t, "session-hello.json")
		top := topKeys(t, data)
		if _, ok := top["v"]; ok {
			t.Fatalf("session.hello fixture must not carry top-level v: %s", data)
		}
		env, err := ParseEnvelope(data)
		if err != nil {
			t.Fatalf("parse hello fixture: %v", err)
		}
		if env.Type != TypeSessionHello {
			t.Fatalf("type = %q, want %q", env.Type, TypeSessionHello)
		}
		if env.ID != "req-1" {
			t.Fatalf("id = %q, want req-1", env.ID)
		}
		var h SessionHello
		if err := env.DecodePayload(&h); err != nil {
			t.Fatalf("decode hello payload: %v", err)
		}
		if h.Protocol != ProtocolVersion {
			t.Fatalf("offered protocol = %q, want %q", h.Protocol, ProtocolVersion)
		}
	})

	t.Run("session-welcome.json", func(t *testing.T) {
		data := loadFixture(t, "session-welcome.json")
		top := topKeys(t, data)
		if _, ok := top["v"]; ok {
			t.Fatalf("welcome fixture must not carry top-level v: %s", data)
		}
		env, err := ParseEnvelope(data)
		if err != nil {
			t.Fatalf("parse welcome fixture: %v", err)
		}
		if env.Type != TypeSessionWelcome {
			t.Fatalf("type = %q, want %q", env.Type, TypeSessionWelcome)
		}
		// seq is per-room and lives only on room.snapshot/room.event (plan §2).
		// session.welcome is session-level and must NOT carry seq. The handler
		// (handleHello) does not stamp seq on welcome; the fixture must match.
		if env.HasSeq() {
			t.Fatalf("welcome fixture must not carry seq: %s", data)
		}
		var w SessionWelcome
		if err := env.DecodePayload(&w); err != nil {
			t.Fatalf("decode welcome payload: %v", err)
		}
		if err := ValidateWelcome(w); err != nil {
			t.Fatalf("welcome fixture v invalid: %v", err)
		}
		if w.ResumeToken == "" {
			t.Fatal("welcome fixture must carry a resume credential")
		}
	})

	t.Run("session-resume-hello.json", func(t *testing.T) {
		env, err := ParseEnvelope(loadFixture(t, "session-resume-hello.json"))
		if err != nil {
			t.Fatalf("parse resume hello fixture: %v", err)
		}
		var hello SessionHello
		if err := env.DecodePayload(&hello); err != nil {
			t.Fatalf("decode resume hello payload: %v", err)
		}
		if env.Type != TypeSessionHello || hello.ResumeToken == "" ||
			hello.LastSeq != 41 {
			t.Fatalf("resume hello fixture = env %+v payload %+v", env, hello)
		}
	})

	t.Run("session-resumed.json", func(t *testing.T) {
		data := loadFixture(t, "session-resumed.json")
		top := topKeys(t, data)
		if _, ok := top["v"]; ok {
			t.Fatalf("resumed welcome must not carry top-level v: %s", data)
		}
		env, err := ParseEnvelope(data)
		if err != nil {
			t.Fatalf("parse resumed welcome fixture: %v", err)
		}
		var welcome SessionWelcome
		if err := env.DecodePayload(&welcome); err != nil {
			t.Fatalf("decode resumed welcome payload: %v", err)
		}
		if !welcome.Resumed || welcome.RoomID != "ABCDEF" ||
			welcome.Role != RolePlayer || welcome.Seat == nil ||
			*welcome.Seat != 0 || !welcome.Host ||
			welcome.ResumeToken == "" {
			t.Fatalf("resumed welcome fixture = %+v", welcome)
		}
	})

	t.Run("error.json", func(t *testing.T) {
		data := loadFixture(t, "error.json")
		env, err := ParseEnvelope(data)
		if err != nil {
			t.Fatalf("parse error fixture: %v", err)
		}
		if env.Type != TypeError {
			t.Fatalf("type = %q, want %q", env.Type, TypeError)
		}
		if env.ID != "req-9" {
			t.Fatalf("error fixture must echo correlation id; got %q", env.ID)
		}
		var ep ErrorPayload
		if err := env.DecodePayload(&ep); err != nil {
			t.Fatalf("decode error payload: %v", err)
		}
		if ep.Code != "room_full" {
			t.Fatalf("code = %q, want room_full", ep.Code)
		}
	})

	t.Run("room-create.json", func(t *testing.T) {
		env, err := ParseEnvelope(loadFixture(t, "room-create.json"))
		if err != nil {
			t.Fatalf("parse: %v", err)
		}
		if env.Type != TypeRoomCreate || env.ID != "c1" {
			t.Fatalf("type/id = %q/%q", env.Type, env.ID)
		}
		var rc RoomCreate
		if err := env.DecodePayload(&rc); err != nil {
			t.Fatalf("decode: %v", err)
		}
		if rc.Format != FormatEDH || rc.MaxSeats != 4 || rc.MatchMode != MatchBO3 ||
			rc.CardLoadMode != CardLoadPreload {
			t.Fatalf("room.create = %+v", rc)
		}
	})

	t.Run("room-created.json", func(t *testing.T) {
		env, err := ParseEnvelope(loadFixture(t, "room-created.json"))
		if err != nil {
			t.Fatalf("parse: %v", err)
		}
		if env.Type != TypeRoomCreated {
			t.Fatalf("type = %q", env.Type)
		}
		if env.HasSeq() {
			t.Fatalf("room.created must not carry seq")
		}
		var rc RoomCreated
		if err := env.DecodePayload(&rc); err != nil {
			t.Fatalf("decode: %v", err)
		}
		if rc.RoomID != "ABCDEF" || rc.HostSeat != 0 {
			t.Fatalf("room.created = %+v", rc)
		}
		if rc.Settings.HasPassword {
			t.Fatal("hasPassword should be false")
		}
		if rc.Settings.CardLoadMode != CardLoadPreload {
			t.Fatalf("cardLoadMode = %q", rc.Settings.CardLoadMode)
		}
	})

	t.Run("room-join-player.json", func(t *testing.T) {
		env, err := ParseEnvelope(loadFixture(t, "room-join-player.json"))
		if err != nil {
			t.Fatalf("parse: %v", err)
		}
		var rj RoomJoin
		if err := env.DecodePayload(&rj); err != nil {
			t.Fatalf("decode: %v", err)
		}
		if rj.AsSpectator {
			t.Fatal("player join should have asSpectator=false")
		}
	})

	t.Run("room-join-spectator.json", func(t *testing.T) {
		env, err := ParseEnvelope(loadFixture(t, "room-join-spectator.json"))
		if err != nil {
			t.Fatalf("parse: %v", err)
		}
		var rj RoomJoin
		if err := env.DecodePayload(&rj); err != nil {
			t.Fatalf("decode: %v", err)
		}
		if !rj.AsSpectator {
			t.Fatal("spectator join should have asSpectator=true")
		}
	})

	t.Run("room-snapshot-owner.json", func(t *testing.T) {
		env, err := ParseEnvelope(loadFixture(t, "room-snapshot-owner.json"))
		if err != nil {
			t.Fatalf("parse: %v", err)
		}
		if env.Type != TypeRoomSnapshot {
			t.Fatalf("type = %q", env.Type)
		}
		if !env.HasSeq() || env.SeqValue() != 1 {
			t.Fatalf("snapshot seq = %v, want 1", env.SeqValue())
		}
		var snap RoomSnapshot
		if err := env.DecodePayload(&snap); err != nil {
			t.Fatalf("decode: %v", err)
		}
		if len(snap.Seats) != 4 || !snap.Seats[0].Host || snap.Seats[0].DisplayName != "Alice" {
			t.Fatalf("seats = %+v", snap.Seats)
		}
	})

	t.Run("room-snapshot-opponent.json", func(t *testing.T) {
		// Oppponent-view fixture. In P1 owner and opponent snapshots have the
		// same public shape (no hidden zones yet); P3 will diverge them with
		// redaction. Pin the seat-occupancy difference vs the owner fixture so
		// this file is a live golden source, not an orphan.
		env, err := ParseEnvelope(loadFixture(t, "room-snapshot-opponent.json"))
		if err != nil {
			t.Fatalf("parse: %v", err)
		}
		if env.Type != TypeRoomSnapshot {
			t.Fatalf("type = %q", env.Type)
		}
		if !env.HasSeq() || env.SeqValue() != 2 {
			t.Fatalf("snapshot seq = %v, want 2", env.SeqValue())
		}
		var snap RoomSnapshot
		if err := env.DecodePayload(&snap); err != nil {
			t.Fatalf("decode: %v", err)
		}
		// Two seats occupied (Alice host + Bob), vs owner fixture's one.
		occupied := 0
		for _, s := range snap.Seats {
			if s.Occupied {
				occupied++
			}
		}
		if occupied != 2 {
			t.Fatalf("occupied seats = %d, want 2", occupied)
		}
		if !snap.Seats[0].Host || snap.Seats[1].DisplayName != "Bob" {
			t.Fatalf("seats = %+v", snap.Seats)
		}
	})

	t.Run("deck-select.json", func(t *testing.T) {
		env, err := ParseEnvelope(loadFixture(t, "deck-select.json"))
		if err != nil {
			t.Fatalf("parse: %v", err)
		}
		var deck DeckSelect
		if err := env.DecodePayload(&deck); err != nil {
			t.Fatalf("decode: %v", err)
		}
		if env.Type != TypeDeckSelect || env.ID != "d1" || deck.Format != FormatModern {
			t.Fatalf("deck.select = type %q id %q payload %+v", env.Type, env.ID, deck)
		}
		if len(deck.Mainboard) != 1 || deck.Mainboard[0].Name != "Lightning Bolt" ||
			deck.Mainboard[0].Count != MinMainboardCards ||
			deck.Mainboard[0].TypeLine != "Instant" {
			t.Fatalf("mainboard = %+v", deck.Mainboard)
		}
	})

	t.Run("deck-selected.json", func(t *testing.T) {
		env, err := ParseEnvelope(loadFixture(t, "deck-selected.json"))
		if err != nil {
			t.Fatalf("parse: %v", err)
		}
		var selected DeckSelected
		if err := env.DecodePayload(&selected); err != nil {
			t.Fatalf("decode: %v", err)
		}
		if env.Type != TypeDeckSelected || env.ID != "d1" || selected.Seat != 0 {
			t.Fatalf("deck.selected = type %q id %q payload %+v", env.Type, env.ID, selected)
		}
	})

	t.Run("player-ready.json", func(t *testing.T) {
		env, err := ParseEnvelope(loadFixture(t, "player-ready.json"))
		if err != nil {
			t.Fatalf("parse: %v", err)
		}
		var ready PlayerReady
		if err := env.DecodePayload(&ready); err != nil {
			t.Fatalf("decode: %v", err)
		}
		if env.Type != TypePlayerReady || env.ID != "r1" || !ready.Ready {
			t.Fatalf("player.ready = type %q id %q payload %+v", env.Type, env.ID, ready)
		}
	})

	t.Run("player-ready-changed.json", func(t *testing.T) {
		env, err := ParseEnvelope(loadFixture(t, "player-ready-changed.json"))
		if err != nil {
			t.Fatalf("parse: %v", err)
		}
		var ready PlayerReadyChanged
		if err := env.DecodePayload(&ready); err != nil {
			t.Fatalf("decode: %v", err)
		}
		if env.Type != TypePlayerReadyChanged || env.ID != "r1" || !ready.Ready {
			t.Fatalf("player.ready_changed = type %q id %q payload %+v", env.Type, env.ID, ready)
		}
	})

	t.Run("room-snapshot-ready.json", func(t *testing.T) {
		data := loadFixture(t, "room-snapshot-ready.json")
		env, err := ParseEnvelope(data)
		if err != nil {
			t.Fatalf("parse: %v", err)
		}
		var snapshot RoomSnapshot
		if err := env.DecodePayload(&snapshot); err != nil {
			t.Fatalf("decode: %v", err)
		}
		if !env.HasSeq() || env.SeqValue() != 7 || !snapshot.Seats[0].DeckSelected || !snapshot.Seats[0].Ready {
			t.Fatalf("ready snapshot = seq %d seats %+v", env.SeqValue(), snapshot.Seats)
		}
		for _, hidden := range []string{"Lightning Bolt", "M11", "149"} {
			if bytes.Contains(data, []byte(hidden)) {
				t.Fatalf("ready snapshot leaked %q: %s", hidden, data)
			}
		}
	})

	t.Run("match-load-required.json", func(t *testing.T) {
		data := loadFixture(t, "match-load-required.json")
		env, err := ParseEnvelope(data)
		if err != nil {
			t.Fatalf("parse: %v", err)
		}
		var required MatchLoadRequired
		if err := env.DecodePayload(&required); err != nil {
			t.Fatalf("decode: %v", err)
		}
		if env.Type != TypeMatchLoadRequired || !env.HasSeq() || required.LoadID != 1 || len(required.CardKeys) != 2 {
			t.Fatalf("match.load_required = env %+v payload %+v", env, required)
		}
		for _, forbidden := range []string{"count", "seat", "sideboard", "deckName"} {
			if bytes.Contains(data, []byte(`"`+forbidden+`"`)) {
				t.Fatalf("load keys leaked %q grouping: %s", forbidden, data)
			}
		}
	})

	t.Run("client-load-complete.json", func(t *testing.T) {
		env, err := ParseEnvelope(loadFixture(t, "client-load-complete.json"))
		if err != nil {
			t.Fatalf("parse: %v", err)
		}
		var complete ClientLoadComplete
		if err := env.DecodePayload(&complete); err != nil {
			t.Fatalf("decode: %v", err)
		}
		if env.Type != TypeClientLoadComplete || env.ID != "l1" || complete.LoadID != 1 {
			t.Fatalf("client.load_complete = env %+v payload %+v", env, complete)
		}
	})

	t.Run("client-load-completed.json", func(t *testing.T) {
		env, err := ParseEnvelope(loadFixture(t, "client-load-completed.json"))
		if err != nil {
			t.Fatalf("parse: %v", err)
		}
		var completed ClientLoadCompleted
		if err := env.DecodePayload(&completed); err != nil {
			t.Fatalf("decode: %v", err)
		}
		if env.Type != TypeClientLoadCompleted || env.ID != "l1" || completed.RoomID != "ABCDEF" {
			t.Fatalf("client.load_completed = env %+v payload %+v", env, completed)
		}
	})

	t.Run("room-snapshot-loading.json", func(t *testing.T) {
		env, err := ParseEnvelope(loadFixture(t, "room-snapshot-loading.json"))
		if err != nil {
			t.Fatalf("parse: %v", err)
		}
		var snapshot RoomSnapshot
		if err := env.DecodePayload(&snapshot); err != nil {
			t.Fatalf("decode: %v", err)
		}
		if snapshot.Phase != RoomPhaseLoading || snapshot.LoadID != 1 ||
			snapshot.CardLoadMode != CardLoadPreload || !snapshot.Seats[0].Loaded {
			t.Fatalf("loading snapshot = %+v", snapshot)
		}
	})

	t.Run("match-started.json", func(t *testing.T) {
		env, err := ParseEnvelope(loadFixture(t, "match-started.json"))
		if err != nil {
			t.Fatalf("parse: %v", err)
		}
		var started MatchStarted
		if err := env.DecodePayload(&started); err != nil {
			t.Fatalf("decode: %v", err)
		}
		if env.Type != TypeMatchStarted || !env.HasSeq() || started.RoomID != "ABCDEF" || started.LoadID != 1 {
			t.Fatalf("match.started = env %+v payload %+v", env, started)
		}
	})

	t.Run("game-snapshot-owner.json", func(t *testing.T) {
		env, err := ParseEnvelope(loadFixture(t, "game-snapshot-owner.json"))
		if err != nil {
			t.Fatalf("parse: %v", err)
		}
		var snapshot GameSnapshot
		if err := env.DecodePayload(&snapshot); err != nil {
			t.Fatalf("decode: %v", err)
		}
		if env.Type != TypeGameSnapshot || env.SeqValue() != 12 || snapshot.StartingSeat != 1 {
			t.Fatalf("owner game snapshot = env %+v payload %+v", env, snapshot)
		}
		if len(snapshot.Seats) != 2 || len(snapshot.Seats[0].Hand) != 7 || len(snapshot.Seats[1].Hand) != 0 {
			t.Fatalf("owner projected hands = %+v", snapshot.Seats)
		}
		if len(snapshot.Seats[0].Counters) != PlayerCounterSlotCount ||
			snapshot.Seats[0].Counters[0].Key != "counter-1" ||
			snapshot.Seats[0].Counters[6].Label != "" ||
			snapshot.Seats[0].CounterCount != 3 ||
			snapshot.Seats[1].CounterCount != 1 {
			t.Fatalf("owner projected counters = %+v", snapshot.Seats[0].Counters)
		}
	})

	t.Run("game-snapshot-opponent.json", func(t *testing.T) {
		data := loadFixture(t, "game-snapshot-opponent.json")
		env, err := ParseEnvelope(data)
		if err != nil {
			t.Fatalf("parse: %v", err)
		}
		var snapshot GameSnapshot
		if err := env.DecodePayload(&snapshot); err != nil {
			t.Fatalf("decode: %v", err)
		}
		if len(snapshot.Seats[0].Hand) != 0 || len(snapshot.Seats[1].Hand) != 7 {
			t.Fatalf("opponent projected hands = %+v", snapshot.Seats)
		}
		if len(snapshot.Seats[0].Counters) != PlayerCounterSlotCount ||
			len(snapshot.Seats[1].Counters) != PlayerCounterSlotCount ||
			snapshot.Seats[0].CounterCount != 3 ||
			snapshot.Seats[1].CounterCount != 1 {
			t.Fatalf("opponent projected counters = %+v", snapshot.Seats)
		}
		for _, hidden := range []string{"Lightning Bolt", "Mountain", "s0-c1"} {
			if bytes.Contains(data, []byte(hidden)) {
				t.Fatalf("opponent snapshot leaked %q: %s", hidden, data)
			}
		}
	})

	t.Run("game-draw.json", func(t *testing.T) {
		env, err := ParseEnvelope(loadFixture(t, "game-draw.json"))
		if err != nil {
			t.Fatalf("parse: %v", err)
		}
		if env.Type != TypeGameDraw || env.ID != "g1" {
			t.Fatalf("game.draw = %+v", env)
		}
		var draw GameDraw
		if err := env.DecodePayload(&draw); err != nil ||
			draw.Count == nil || *draw.Count != 3 {
			t.Fatalf("game.draw payload = %+v err=%v", draw, err)
		}
	})

	t.Run("game-drawn.json", func(t *testing.T) {
		env, err := ParseEnvelope(loadFixture(t, "game-drawn.json"))
		if err != nil {
			t.Fatalf("parse: %v", err)
		}
		var drawn GameDrawn
		if err := env.DecodePayload(&drawn); err != nil {
			t.Fatalf("decode: %v", err)
		}
		if env.Type != TypeGameDrawn || drawn.Seat != 0 || drawn.Count != 3 {
			t.Fatalf("game.drawn = env %+v payload %+v", env, drawn)
		}
	})

	t.Run("game-shuffle-library.json", func(t *testing.T) {
		env, err := ParseEnvelope(loadFixture(t, "game-shuffle-library.json"))
		if err != nil {
			t.Fatalf("parse: %v", err)
		}
		if env.Type != TypeGameShuffleLibrary || env.ID != "shuffle-1" {
			t.Fatalf("game.shuffle_library = %+v", env)
		}
	})

	t.Run("game-library-shuffled.json", func(t *testing.T) {
		env, err := ParseEnvelope(loadFixture(t, "game-library-shuffled.json"))
		if err != nil {
			t.Fatalf("parse: %v", err)
		}
		var shuffled GameLibraryShuffled
		if err := env.DecodePayload(&shuffled); err != nil {
			t.Fatalf("decode: %v", err)
		}
		if env.Type != TypeGameLibraryShuffled ||
			shuffled.RoomID != "room-1" || shuffled.Seat != 0 {
			t.Fatalf("game.library_shuffled = env %+v payload %+v",
				env, shuffled)
		}
	})

	t.Run("game-mulligan.json", func(t *testing.T) {
		env, err := ParseEnvelope(loadFixture(t, "game-mulligan.json"))
		if err != nil {
			t.Fatalf("parse: %v", err)
		}
		if env.Type != TypeGameMulligan || env.ID != "g2" {
			t.Fatalf("game.mulligan = %+v", env)
		}
	})

	t.Run("game-mulliganed.json", func(t *testing.T) {
		env, err := ParseEnvelope(loadFixture(t, "game-mulliganed.json"))
		if err != nil {
			t.Fatalf("parse: %v", err)
		}
		var mulliganed GameMulliganed
		if err := env.DecodePayload(&mulliganed); err != nil {
			t.Fatalf("decode: %v", err)
		}
		if env.Type != TypeGameMulliganed || mulliganed.HandSize != 7 ||
			mulliganed.MulliganCount != 1 {
			t.Fatalf("game.mulliganed = env %+v payload %+v", env, mulliganed)
		}
	})

	t.Run("game-discard-hand.json", func(t *testing.T) {
		env, err := ParseEnvelope(loadFixture(t, "game-discard-hand.json"))
		var discard GameDiscardHand
		if err != nil || env.DecodePayload(&discard) != nil ||
			env.Type != TypeGameDiscardHand || env.ID != "discard-hand-1" ||
			discard.All {
			t.Fatalf("game.discard_hand = env %+v payload %+v err %v",
				env, discard, err)
		}
	})

	t.Run("game-hand-discarded.json", func(t *testing.T) {
		env, err := ParseEnvelope(loadFixture(t, "game-hand-discarded.json"))
		var discarded GameHandDiscarded
		if err != nil || env.DecodePayload(&discarded) != nil ||
			env.Type != TypeGameHandDiscarded || env.ID != "discard-hand-1" ||
			discarded.RoomID != "room-1" || discarded.Seat != 0 ||
			discarded.Count != 1 {
			t.Fatalf("game.hand_discarded = env %+v payload %+v err %v",
				env, discarded, err)
		}
	})

	t.Run("game-move-card.json", func(t *testing.T) {
		env, err := ParseEnvelope(loadFixture(t, "game-move-card.json"))
		if err != nil {
			t.Fatalf("parse: %v", err)
		}
		var move GameMoveCard
		if err := env.DecodePayload(&move); err != nil {
			t.Fatalf("decode: %v", err)
		}
		if env.Type != TypeGameMoveCard || env.ID != "g3" ||
			move.CardID != "s1-gy1" || move.FromZone != ZoneGraveyard ||
			move.ToZone != ZoneBattlefield || move.Position == nil ||
			move.FromSeat == nil || *move.FromSeat != 1 ||
			move.ToSeat == nil || *move.ToSeat != 0 ||
			move.Position.X != 0.25 || move.Position.Y != 0.6 {
			t.Fatalf("game.move_card = env %+v payload %+v", env, move)
		}
	})

	t.Run("game-card-moved.json", func(t *testing.T) {
		env, err := ParseEnvelope(loadFixture(t, "game-card-moved.json"))
		if err != nil {
			t.Fatalf("parse: %v", err)
		}
		var moved GameCardMoved
		if err := env.DecodePayload(&moved); err != nil {
			t.Fatalf("decode: %v", err)
		}
		if env.Type != TypeGameCardMoved || env.ID != "g3" ||
			moved.CardID != "s1-gy1" || moved.Seat != 0 ||
			moved.FromSeat != 1 || moved.ToSeat != 0 ||
			moved.Position == nil ||
			moved.Position.X != 0.25 {
			t.Fatalf("game.card_moved = env %+v payload %+v", env, moved)
		}
	})

	t.Run("game-set-tapped.json", func(t *testing.T) {
		env, err := ParseEnvelope(loadFixture(t, "game-set-tapped.json"))
		if err != nil {
			t.Fatalf("parse: %v", err)
		}
		var request GameSetTapped
		if err := env.DecodePayload(&request); err != nil {
			t.Fatalf("decode: %v", err)
		}
		if env.Type != TypeGameSetTapped || env.ID != "g3-tap" ||
			request.CardID != "s0-c1" || !request.Tapped {
			t.Fatalf("game.set_tapped = env %+v payload %+v", env, request)
		}
	})

	t.Run("game-set-card-counter.json", func(t *testing.T) {
		env, err := ParseEnvelope(loadFixture(t, "game-set-card-counter.json"))
		if err != nil {
			t.Fatalf("parse: %v", err)
		}
		var request GameSetCardCounter
		if err := env.DecodePayload(&request); err != nil {
			t.Fatalf("decode: %v", err)
		}
		if env.Type != TypeGameSetCardCounter ||
			request.CardID != "s0-c1" ||
			request.Kind != CardCounterKindAbility ||
			request.Label != "Flying" || request.Value == nil ||
			*request.Value != 1 {
			t.Fatalf("game.set_card_counter = env %+v payload %+v",
				env, request)
		}
	})

	t.Run("game-card-counter-set.json", func(t *testing.T) {
		env, err := ParseEnvelope(loadFixture(t, "game-card-counter-set.json"))
		if err != nil {
			t.Fatalf("parse: %v", err)
		}
		var reply GameCardCounterSet
		if err := env.DecodePayload(&reply); err != nil {
			t.Fatalf("decode: %v", err)
		}
		if env.Type != TypeGameCardCounterSet ||
			reply.Counter.ID != "ability-1" ||
			reply.Counter.Label != "Flying" || reply.Counter.Value != 1 {
			t.Fatalf("game.card_counter_set = env %+v payload %+v",
				env, reply)
		}
	})

	t.Run("game-tapped-set.json", func(t *testing.T) {
		env, err := ParseEnvelope(loadFixture(t, "game-tapped-set.json"))
		if err != nil {
			t.Fatalf("parse: %v", err)
		}
		var reply GameTappedSet
		if err := env.DecodePayload(&reply); err != nil {
			t.Fatalf("decode: %v", err)
		}
		if env.Type != TypeGameTappedSet || reply.Seat != 1 ||
			reply.CardID != "s0-c1" || !reply.Tapped {
			t.Fatalf("game.tapped_set = env %+v payload %+v", env, reply)
		}
	})

	t.Run("game-reveal.json", func(t *testing.T) {
		env, err := ParseEnvelope(loadFixture(t, "game-reveal.json"))
		if err != nil {
			t.Fatalf("parse: %v", err)
		}
		var reveal GameReveal
		if err := env.DecodePayload(&reveal); err != nil {
			t.Fatalf("decode: %v", err)
		}
		if env.Type != TypeGameReveal || env.ID != "reveal-17" ||
			reveal.Zone != ZoneHand || len(reveal.CardIDs) != 0 {
			t.Fatalf("game.reveal = env %+v payload %+v", env, reveal)
		}
	})

	t.Run("game-revealed.json", func(t *testing.T) {
		env, err := ParseEnvelope(loadFixture(t, "game-revealed.json"))
		if err != nil {
			t.Fatalf("parse: %v", err)
		}
		var revealed GameRevealed
		if err := env.DecodePayload(&revealed); err != nil {
			t.Fatalf("decode: %v", err)
		}
		if env.Type != TypeGameRevealed || env.ID != "reveal-17" ||
			revealed.RoomID != "ABCDEF" || revealed.Seat != 0 ||
			revealed.Zone != ZoneHand || revealed.Count != 2 {
			t.Fatalf("game.revealed = env %+v payload %+v", env, revealed)
		}
	})

	t.Run("game-dump-zone.json", func(t *testing.T) {
		env, err := ParseEnvelope(loadFixture(t, "game-dump-zone.json"))
		if err != nil {
			t.Fatalf("parse: %v", err)
		}
		var dump GameDumpZone
		if err := env.DecodePayload(&dump); err != nil {
			t.Fatalf("decode: %v", err)
		}
		if env.Type != TypeGameDumpZone || env.ID != "dump-18" ||
			dump.Zone != "library" || dump.TopCount != 3 {
			t.Fatalf("game.dump_zone = env %+v payload %+v", env, dump)
		}
	})

	t.Run("game-zone-dumped.json", func(t *testing.T) {
		env, err := ParseEnvelope(loadFixture(t, "game-zone-dumped.json"))
		if err != nil {
			t.Fatalf("parse: %v", err)
		}
		var dump GameZoneDumped
		if err := env.DecodePayload(&dump); err != nil {
			t.Fatalf("decode: %v", err)
		}
		if env.Type != TypeGameZoneDumped || env.ID != "dump-18" ||
			dump.RoomID != "ABCDEF" || dump.Zone != "library" ||
			dump.TopCount != 3 ||
			len(dump.Cards) != 2 || dump.Cards[1].Name != "Demonic Tutor" {
			t.Fatalf("game.zone_dumped = env %+v payload %+v", env, dump)
		}
	})

	t.Run("game-search-library.json", func(t *testing.T) {
		env, err := ParseEnvelope(loadFixture(t, "game-search-library.json"))
		if err != nil {
			t.Fatalf("parse: %v", err)
		}
		var search GameSearchLibrary
		if err := env.DecodePayload(&search); err != nil {
			t.Fatalf("decode: %v", err)
		}
		if env.Type != TypeGameSearchLibrary || env.ID != "search-19" ||
			len(search.CardIDs) != 2 || search.CardIDs[0] != "s0-c8" ||
			search.ToZone != LibraryDestinationGraveyard ||
			search.ToSeat == nil || *search.ToSeat != 0 ||
			search.Reveal || !search.Randomize || search.Position != nil {
			t.Fatalf("game.search_library = env %+v payload %+v", env, search)
		}
	})

	t.Run("game-library-searched.json", func(t *testing.T) {
		env, err := ParseEnvelope(loadFixture(t, "game-library-searched.json"))
		if err != nil {
			t.Fatalf("parse: %v", err)
		}
		var searched GameLibrarySearched
		if err := env.DecodePayload(&searched); err != nil {
			t.Fatalf("decode: %v", err)
		}
		if env.Type != TypeGameLibrarySearched || env.ID != "search-19" ||
			searched.RoomID != "ABCDEF" || searched.Seat != 0 ||
			searched.ToSeat != 0 ||
			searched.ToZone != LibraryDestinationGraveyard ||
			searched.Revealed || searched.Count != 2 {
			t.Fatalf("game.library_searched = env %+v payload %+v", env, searched)
		}
	})

	t.Run("game-recall-revealed.json", func(t *testing.T) {
		env, err := ParseEnvelope(loadFixture(t, "game-recall-revealed.json"))
		if err != nil {
			t.Fatalf("parse: %v", err)
		}
		var recall GameRecallRevealed
		if err := env.DecodePayload(&recall); err != nil ||
			env.Type != TypeGameRecallRevealed || env.ID != "recall-20" {
			t.Fatalf("game.recall_revealed = env %+v payload %+v err %v",
				env, recall, err)
		}
	})

	t.Run("game-revealed-recalled.json", func(t *testing.T) {
		env, err := ParseEnvelope(loadFixture(t, "game-revealed-recalled.json"))
		if err != nil {
			t.Fatalf("parse: %v", err)
		}
		var recalled GameRevealedRecalled
		if err := env.DecodePayload(&recalled); err != nil ||
			env.Type != TypeGameRevealedRecalled || env.ID != "recall-20" ||
			recalled.RoomID != "ABCDEF" || recalled.Seat != 0 ||
			recalled.Count != 2 {
			t.Fatalf("game.revealed_recalled = env %+v payload %+v err %v",
				env, recalled, err)
		}
	})

	t.Run("game-move-cards.json", func(t *testing.T) {
		env, err := ParseEnvelope(loadFixture(t, "game-move-cards.json"))
		if err != nil {
			t.Fatalf("parse: %v", err)
		}
		var move GameMoveCards
		if err := env.DecodePayload(&move); err != nil ||
			env.Type != TypeGameMoveCards || env.ID != "move-cards-21" ||
			len(move.CardIDs) != 2 || move.ToZone != ZoneLibrary ||
			move.LibraryPlacement != LibraryPlacementBottom || move.Randomize {
			t.Fatalf("game.move_cards = env %+v payload %+v err %v",
				env, move, err)
		}
	})

	t.Run("game-cards-moved.json", func(t *testing.T) {
		env, err := ParseEnvelope(loadFixture(t, "game-cards-moved.json"))
		if err != nil {
			t.Fatalf("parse: %v", err)
		}
		var moved GameCardsMoved
		if err := env.DecodePayload(&moved); err != nil ||
			env.Type != TypeGameCardsMoved || env.ID != "move-cards-21" ||
			moved.RoomID != "ABCDEF" || moved.Seat != 0 ||
			moved.Count != 2 || moved.ToZone != ZoneLibrary {
			t.Fatalf("game.cards_moved = env %+v payload %+v err %v",
				env, moved, err)
		}
	})

	t.Run("game-move-library-cards.json", func(t *testing.T) {
		env, err := ParseEnvelope(loadFixture(t, "game-move-library-cards.json"))
		var move GameMoveLibraryCards
		if err != nil || env.DecodePayload(&move) != nil ||
			env.Type != TypeGameMoveLibraryCards ||
			env.ID != "move-library-cards-23" || move.Count != 3 ||
			move.ToZone != ZoneGraveyard {
			t.Fatalf("game.move_library_cards = env %+v payload %+v err %v",
				env, move, err)
		}
	})

	t.Run("game-library-cards-moved.json", func(t *testing.T) {
		env, err := ParseEnvelope(loadFixture(t, "game-library-cards-moved.json"))
		var moved GameLibraryCardsMoved
		if err != nil || env.DecodePayload(&moved) != nil ||
			env.Type != TypeGameLibraryCardsMoved ||
			env.ID != "move-library-cards-23" ||
			moved.RoomID != "ABCDEF" || moved.Seat != 0 ||
			moved.Count != 3 || moved.ToZone != ZoneGraveyard {
			t.Fatalf("game.library_cards_moved = env %+v payload %+v err %v",
				env, moved, err)
		}
	})

	t.Run("game-reorder-library.json", func(t *testing.T) {
		env, err := ParseEnvelope(loadFixture(t, "game-reorder-library.json"))
		if err != nil {
			t.Fatalf("parse: %v", err)
		}
		var reorder GameReorderLibrary
		if err := env.DecodePayload(&reorder); err != nil ||
			env.Type != TypeGameReorderLibrary || env.ID != "reorder-22" ||
			len(reorder.CardIDs) != 2 || reorder.CardIDs[0] != "s0-c9" {
			t.Fatalf("game.reorder_library = env %+v payload %+v err %v",
				env, reorder, err)
		}
	})

	t.Run("game-library-reordered.json", func(t *testing.T) {
		env, err := ParseEnvelope(loadFixture(t, "game-library-reordered.json"))
		if err != nil {
			t.Fatalf("parse: %v", err)
		}
		var reordered GameLibraryReordered
		if err := env.DecodePayload(&reordered); err != nil ||
			env.Type != TypeGameLibraryReordered || env.ID != "reorder-22" ||
			reordered.RoomID != "ABCDEF" || reordered.Seat != 0 ||
			reordered.Count != 2 {
			t.Fatalf("game.library_reordered = env %+v payload %+v err %v",
				env, reordered, err)
		}
	})

	t.Run("game-snapshot-shared.json", func(t *testing.T) {
		env, err := ParseEnvelope(loadFixture(t, "game-snapshot-shared.json"))
		if err != nil {
			t.Fatalf("parse: %v", err)
		}
		var snapshot GameSnapshot
		if err := env.DecodePayload(&snapshot); err != nil {
			t.Fatalf("decode: %v", err)
		}
		if env.Type != TypeGameSnapshot || env.SeqValue() != 18 ||
			len(snapshot.Stack) != 1 || len(snapshot.Revealed) != 1 ||
			snapshot.Stack[0].OwnerSeat != 0 ||
			snapshot.Stack[0].Name != "Lightning Bolt" ||
			snapshot.Revealed[0].Name != "Mountain" {
			t.Fatalf("shared game snapshot = env %+v payload %+v", env, snapshot)
		}
	})

	t.Run("game-snapshot-move-owner.json", func(t *testing.T) {
		env, err := ParseEnvelope(loadFixture(t, "game-snapshot-move-owner.json"))
		if err != nil {
			t.Fatalf("parse: %v", err)
		}
		var snapshot GameSnapshot
		if err := env.DecodePayload(&snapshot); err != nil {
			t.Fatalf("decode: %v", err)
		}
		if len(snapshot.Seats) != 2 || len(snapshot.Seats[0].Hand) != 1 ||
			len(snapshot.Seats[0].Battlefield) != 1 ||
			snapshot.Seats[0].Battlefield[0].Position == nil ||
			snapshot.ActiveSeat != 1 || snapshot.CurrentPhase != GamePhaseUntap {
			t.Fatalf("owner move snapshot = %+v", snapshot.Seats)
		}
	})

	t.Run("game-snapshot-move-opponent.json", func(t *testing.T) {
		data := loadFixture(t, "game-snapshot-move-opponent.json")
		env, err := ParseEnvelope(data)
		if err != nil {
			t.Fatalf("parse: %v", err)
		}
		var snapshot GameSnapshot
		if err := env.DecodePayload(&snapshot); err != nil {
			t.Fatalf("decode: %v", err)
		}
		if len(snapshot.Seats) != 2 || len(snapshot.Seats[0].Hand) != 0 ||
			snapshot.Seats[0].HandCount != 1 ||
			len(snapshot.Seats[0].Battlefield) != 1 ||
			snapshot.Seats[0].Battlefield[0].Name != "Lightning Bolt" {
			t.Fatalf("opponent move snapshot = %+v", snapshot.Seats)
		}
		for _, hidden := range []string{"Mountain", "s0-c2"} {
			if bytes.Contains(data, []byte(hidden)) {
				t.Fatalf("opponent move snapshot leaked %q: %s", hidden, data)
			}
		}
	})

	t.Run("game-set-phase.json", func(t *testing.T) {
		env, err := ParseEnvelope(loadFixture(t, "game-set-phase.json"))
		if err != nil {
			t.Fatalf("parse: %v", err)
		}
		var request GameSetPhase
		if err := env.DecodePayload(&request); err != nil {
			t.Fatalf("decode: %v", err)
		}
		if env.Type != TypeGameSetPhase || env.ID != "phase-15" ||
			request.Phase != GamePhaseDeclareAttackers {
			t.Fatalf("game.set_phase = env %+v payload %+v", env, request)
		}
	})

	t.Run("game-phase-set.json", func(t *testing.T) {
		env, err := ParseEnvelope(loadFixture(t, "game-phase-set.json"))
		if err != nil {
			t.Fatalf("parse: %v", err)
		}
		var reply GamePhaseSet
		if err := env.DecodePayload(&reply); err != nil {
			t.Fatalf("decode: %v", err)
		}
		if env.Type != TypeGamePhaseSet || env.ID != "phase-15" ||
			reply.RoomID != "ABCDEF" || reply.Seat != 1 ||
			reply.Phase != GamePhaseDeclareAttackers {
			t.Fatalf("game.phase_set = env %+v payload %+v", env, reply)
		}
	})

	t.Run("game-set-counter.json", func(t *testing.T) {
		env, err := ParseEnvelope(loadFixture(t, "game-set-counter.json"))
		if err != nil {
			t.Fatalf("parse: %v", err)
		}
		var request GameSetCounter
		if err := env.DecodePayload(&request); err != nil {
			t.Fatalf("decode: %v", err)
		}
		if env.Type != TypeGameSetCounter || env.ID != "counter-1" ||
			request.Counter != PlayerCounterLife || request.Value == nil ||
			*request.Value != 19 || request.Delta != nil || request.Label != nil {
			t.Fatalf("game.set_counter = env %+v payload %+v", env, request)
		}
	})

	t.Run("game-adjust-counter.json", func(t *testing.T) {
		env, err := ParseEnvelope(loadFixture(t, "game-adjust-counter.json"))
		if err != nil {
			t.Fatalf("parse: %v", err)
		}
		var request GameSetCounter
		if err := env.DecodePayload(&request); err != nil {
			t.Fatalf("decode: %v", err)
		}
		if request.Counter != "counter-1" || request.Delta == nil ||
			*request.Delta != 1 || request.Value != nil || request.Label != nil {
			t.Fatalf("adjust counter payload = %+v", request)
		}
	})

	t.Run("game-rename-counter.json", func(t *testing.T) {
		env, err := ParseEnvelope(loadFixture(t, "game-rename-counter.json"))
		if err != nil {
			t.Fatalf("parse: %v", err)
		}
		var request GameSetCounter
		if err := env.DecodePayload(&request); err != nil {
			t.Fatalf("decode: %v", err)
		}
		if request.Counter != "counter-1" || request.Label == nil ||
			*request.Label != "Energy" || request.Value != nil ||
			request.Delta != nil {
			t.Fatalf("rename counter payload = %+v", request)
		}
	})

	t.Run("game-counter-set.json", func(t *testing.T) {
		env, err := ParseEnvelope(loadFixture(t, "game-counter-set.json"))
		if err != nil {
			t.Fatalf("parse: %v", err)
		}
		var reply GameCounterSet
		if err := env.DecodePayload(&reply); err != nil {
			t.Fatalf("decode: %v", err)
		}
		if env.Type != TypeGameCounterSet || env.ID != "counter-1" ||
			reply.RoomID != "ABCDEF" || reply.Seat != 0 ||
			reply.Counter != PlayerCounterLife || reply.Value != 19 {
			t.Fatalf("game.counter_set = env %+v payload %+v", env, reply)
		}
	})

	t.Run("game-counter-set-pip.json", func(t *testing.T) {
		env, err := ParseEnvelope(loadFixture(t, "game-counter-set-pip.json"))
		if err != nil {
			t.Fatalf("parse: %v", err)
		}
		var reply GameCounterSet
		if err := env.DecodePayload(&reply); err != nil {
			t.Fatalf("decode: %v", err)
		}
		if reply.Counter != "counter-1" || reply.Value != 1 ||
			reply.Label != "Energy" {
			t.Fatalf("pip game.counter_set = %+v", reply)
		}
	})

	t.Run("game-set-counter-count.json", func(t *testing.T) {
		env, err := ParseEnvelope(loadFixture(t, "game-set-counter-count.json"))
		if err != nil {
			t.Fatalf("parse: %v", err)
		}
		var request GameSetCounterCount
		if err := env.DecodePayload(&request); err != nil {
			t.Fatalf("decode: %v", err)
		}
		if env.Type != TypeGameSetCounterCount ||
			env.ID != "counter-count-1" || request.Count != 3 {
			t.Fatalf("game.set_counter_count = env %+v payload %+v",
				env, request)
		}
	})

	t.Run("game-counter-count-set.json", func(t *testing.T) {
		env, err := ParseEnvelope(loadFixture(t, "game-counter-count-set.json"))
		if err != nil {
			t.Fatalf("parse: %v", err)
		}
		var reply GameCounterCountSet
		if err := env.DecodePayload(&reply); err != nil {
			t.Fatalf("decode: %v", err)
		}
		if env.Type != TypeGameCounterCountSet ||
			env.ID != "counter-count-1" || reply.RoomID != "ABCDEF" ||
			reply.Seat != 0 || reply.Count != 3 {
			t.Fatalf("game.counter_count_set = env %+v payload %+v",
				env, reply)
		}
	})

	t.Run("game-concede.json", func(t *testing.T) {
		env, err := ParseEnvelope(loadFixture(t, "game-concede.json"))
		if err != nil {
			t.Fatalf("parse: %v", err)
		}
		var request GameConcede
		if err := env.DecodePayload(&request); err != nil {
			t.Fatalf("decode: %v", err)
		}
		if env.Type != TypeGameConcede || env.ID != "concede-17" ||
			len(env.Payload) != 0 {
			t.Fatalf("game.concede = %+v", env)
		}
	})

	t.Run("game-conceded.json", func(t *testing.T) {
		env, err := ParseEnvelope(loadFixture(t, "game-conceded.json"))
		if err != nil {
			t.Fatalf("parse: %v", err)
		}
		var reply GameConceded
		if err := env.DecodePayload(&reply); err != nil {
			t.Fatalf("decode: %v", err)
		}
		if env.Type != TypeGameConceded || env.ID != "concede-17" ||
			reply.RoomID != "ABCDEF" || reply.GameNumber != 1 ||
			reply.ConcededSeat != 0 || reply.WinnerSeat != 1 ||
			reply.MatchFinished || len(reply.Score) != 2 ||
			reply.Score[1] != 1 {
			t.Fatalf("game.conceded = env %+v payload %+v", env, reply)
		}
	})

	t.Run("game-say.json", func(t *testing.T) {
		env, err := ParseEnvelope(loadFixture(t, "game-say.json"))
		if err != nil {
			t.Fatalf("parse: %v", err)
		}
		var request GameSay
		if err := env.DecodePayload(&request); err != nil {
			t.Fatalf("decode: %v", err)
		}
		if env.Type != TypeGameSay || env.ID != "say-20" ||
			request.Message != "Good luck!" {
			t.Fatalf("game.say = env %+v payload %+v", env, request)
		}
	})

	t.Run("game-said.json", func(t *testing.T) {
		env, err := ParseEnvelope(loadFixture(t, "game-said.json"))
		if err != nil {
			t.Fatalf("parse: %v", err)
		}
		var reply GameSaid
		if err := env.DecodePayload(&reply); err != nil {
			t.Fatalf("decode: %v", err)
		}
		if env.Type != TypeGameSaid || env.ID != "say-20" ||
			reply.RoomID != "ABCDEF" || reply.LogID != 42 {
			t.Fatalf("game.said = env %+v payload %+v", env, reply)
		}
	})

	t.Run("game-return-to-room.json", func(t *testing.T) {
		env, err := ParseEnvelope(loadFixture(t, "game-return-to-room.json"))
		if err != nil {
			t.Fatalf("parse: %v", err)
		}
		var request GameReturnToRoom
		if err := env.DecodePayload(&request); err != nil {
			t.Fatalf("decode: %v", err)
		}
		if env.Type != TypeGameReturnToRoom || env.ID != "return-18" {
			t.Fatalf("game.return_to_room = %+v", env)
		}
	})

	t.Run("game-returned-to-room.json", func(t *testing.T) {
		env, err := ParseEnvelope(loadFixture(t, "game-returned-to-room.json"))
		if err != nil {
			t.Fatalf("parse: %v", err)
		}
		var reply GameReturnedToRoom
		if err := env.DecodePayload(&reply); err != nil {
			t.Fatalf("decode: %v", err)
		}
		if env.Type != TypeGameReturnedToRoom || env.ID != "return-18" ||
			reply.RoomID != "ABCDEF" {
			t.Fatalf("game.returned_to_room = env %+v payload %+v", env, reply)
		}
	})

	t.Run("game-snapshot-finished.json", func(t *testing.T) {
		data := loadFixture(t, "game-snapshot-finished.json")
		env, err := ParseEnvelope(data)
		if err != nil {
			t.Fatalf("parse: %v", err)
		}
		var snapshot GameSnapshot
		if err := env.DecodePayload(&snapshot); err != nil {
			t.Fatalf("decode: %v", err)
		}
		if env.Type != TypeGameSnapshot || env.SeqValue() != 24 ||
			snapshot.ActiveSeat != -1 || snapshot.Result == nil ||
			snapshot.Result.Reason != GameResultConcede ||
			snapshot.Result.WinnerSeat != 1 ||
			snapshot.Result.ConcededSeat != 0 ||
			snapshot.Result.MatchFinished ||
			len(snapshot.Score) != 2 || snapshot.Score[1] != 1 ||
			len(snapshot.Log) != 1 || snapshot.Log[0].Kind != "concede" {
			t.Fatalf("finished game snapshot = env %+v payload %+v",
				env, snapshot)
		}
		for _, hidden := range []string{"Lightning Bolt", "s0-c1", `"hand"`} {
			if bytes.Contains(data, []byte(hidden)) {
				t.Fatalf("finished snapshot leaked %q: %s", hidden, data)
			}
		}
	})

	t.Run("game-snapshot-departure.json", func(t *testing.T) {
		data := loadFixture(t, "game-snapshot-departure.json")
		env, err := ParseEnvelope(data)
		if err != nil {
			t.Fatalf("parse: %v", err)
		}
		var snapshot GameSnapshot
		if err := env.DecodePayload(&snapshot); err != nil {
			t.Fatalf("decode: %v", err)
		}
		if env.Type != TypeGameSnapshot || env.SeqValue() != 25 ||
			snapshot.ActiveSeat != -1 || snapshot.Result == nil ||
			snapshot.Result.Reason != GameResultDeparture ||
			snapshot.Result.WinnerSeat != 0 ||
			snapshot.Result.ConcededSeat != 1 ||
			!snapshot.Result.MatchFinished ||
			len(snapshot.Score) != 2 || snapshot.Score[0] != 2 ||
			len(snapshot.Log) != 1 || snapshot.Log[0].Kind != "departure" {
			t.Fatalf("departure game snapshot = env %+v payload %+v",
				env, snapshot)
		}
	})

	t.Run("game-next-turn.json", func(t *testing.T) {
		env, err := ParseEnvelope(loadFixture(t, "game-next-turn.json"))
		if err != nil {
			t.Fatalf("parse: %v", err)
		}
		if env.Type != TypeGameNextTurn || env.ID != "turn-16" ||
			len(env.Payload) != 0 {
			t.Fatalf("game.next_turn = %+v", env)
		}
	})

	t.Run("game-turn-advanced.json", func(t *testing.T) {
		env, err := ParseEnvelope(loadFixture(t, "game-turn-advanced.json"))
		if err != nil {
			t.Fatalf("parse: %v", err)
		}
		var reply GameTurnAdvanced
		if err := env.DecodePayload(&reply); err != nil {
			t.Fatalf("decode: %v", err)
		}
		if env.Type != TypeGameTurnAdvanced || env.ID != "turn-16" ||
			reply.RoomID != "ABCDEF" || reply.ActiveSeat != 0 ||
			reply.CurrentPhase != GamePhaseUntap {
			t.Fatalf("game.turn_advanced = env %+v payload %+v", env, reply)
		}
	})

	t.Run("room-full-error.json", func(t *testing.T) {
		env, err := ParseEnvelope(loadFixture(t, "room-full-error.json"))
		if err != nil {
			t.Fatalf("parse: %v", err)
		}
		var ep ErrorPayload
		if err := env.DecodePayload(&ep); err != nil {
			t.Fatalf("decode: %v", err)
		}
		if ep.Code != ErrRoomFull {
			t.Fatalf("code = %q, want %q", ep.Code, ErrRoomFull)
		}
	})

	t.Run("wrong-password-error.json", func(t *testing.T) {
		env, err := ParseEnvelope(loadFixture(t, "wrong-password-error.json"))
		if err != nil {
			t.Fatalf("parse: %v", err)
		}
		var ep ErrorPayload
		if err := env.DecodePayload(&ep); err != nil {
			t.Fatalf("decode: %v", err)
		}
		if ep.Code != ErrWrongPassword {
			t.Fatalf("code = %q, want %q", ep.Code, ErrWrongPassword)
		}
	})
}
