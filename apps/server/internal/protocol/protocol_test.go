// SPDX-License-Identifier: GPL-3.0-or-later
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
	case TypeLimitedCreateCasualMatch:
		return &LimitedCreateCasualMatch{}
	case TypeLimitedCasualMatchCreated:
		return &TournamentChanged{}
	case TypeLimitedPick:
		return &LimitedPick{}
	case TypeLimitedPicked:
		return &LimitedPicked{}
	case TypeLimitedSubmitDeck:
		return &LimitedSubmitDeck{}
	case TypeLimitedDeckSubmitted:
		return &LimitedDeckSubmitted{}
	case TypeLimitedSnapshot:
		return &LimitedSnapshot{}
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
	case TypeRulesSnapshot:
		return &RulesGameSnapshot{}
	case TypeRulesPrompt:
		return &RulesPrompt{}
	case TypeRulesRespond:
		return &RulesRespond{}
	case TypeRulesResponded:
		return &RulesResponded{}
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
	if len(edh.Seats) != 4 ||
		!reflect.DeepEqual(edh.TurnOrder, []int{2, 3, 0, 1}) ||
		len(edh.Seats[0].CommandZone) != 1 ||
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
