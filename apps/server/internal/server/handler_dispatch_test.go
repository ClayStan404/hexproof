// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package server

import (
	"hexproof/server/internal/protocol"
	"testing"
)

func TestCommandRegistry(t *testing.T) {
	required := []string{
		protocol.TypeSessionHello,
		protocol.TypeRoomCreate,
		protocol.TypeRoomList,
		protocol.TypeRoomJoin,
		protocol.TypeRoomKick,
		protocol.TypeRoomDisband,
		protocol.TypeTournamentList,
		protocol.TypeTournamentCreate,
		protocol.TypeTournamentEnter,
		protocol.TypeTournamentLeave,
		protocol.TypeTournamentRegister,
		protocol.TypeTournamentUnregister,
		protocol.TypeTournamentCheckIn,
		protocol.TypeTournamentStart,
		protocol.TypeTournamentDrop,
		protocol.TypeTournamentReportResult,
		protocol.TypeTournamentConfirmResult,
		protocol.TypeTournamentRejectResult,
		protocol.TypeTournamentCorrectResult,
		protocol.TypeTournamentNextRound,
		protocol.TypeTournamentOpenMatch,
		protocol.TypeTournamentCancel,
		protocol.TypeDeckSelect,
		protocol.TypePlayerReady,
		protocol.TypeClientLoadComplete,
		protocol.TypeGameDraw,
		protocol.TypeGameShuffleLibrary,
		protocol.TypeGameMulligan,
		protocol.TypeGameDiscardHand,
		protocol.TypeGameMoveCard,
		protocol.TypeGameMoveCards,
		protocol.TypeGameMoveLibraryCards,
		protocol.TypeGameSetTapped,
		protocol.TypeGameSetCardFace,
		protocol.TypeGameArrangeBattlefield,
		protocol.TypeGameSetFaceDown,
		protocol.TypeGameSetCardCounter,
		protocol.TypeGameSetPhase,
		protocol.TypeGameSetResponseStatus,
		protocol.TypeGameSetCounter,
		protocol.TypeGameSetCounterCount,
		protocol.TypeGameConcede,
		protocol.TypeGameDeclareDraw,
		protocol.TypeGameRestart,
		protocol.TypeGameRoll,
		protocol.TypeGameFlipCoin,
		protocol.TypeGameRandomSelect,
		protocol.TypeGameReturnToRoom,
		protocol.TypeGameSay,
		protocol.TypeGameCreateToken,
		protocol.TypeGamePlayLand,
		protocol.TypeGameSetLandPlayCount,
		protocol.TypeGameAdjustCommanderTax,
		protocol.TypeGameCastCommander,
		protocol.TypeGameSetCommanderDamage,
		protocol.TypeGameSetArrow,
		protocol.TypeGameSetAttachment,
		protocol.TypeGameNextTurn,
		protocol.TypeGameReveal,
		protocol.TypeGameRecallRevealed,
		protocol.TypeGameDumpZone,
		protocol.TypeGameRespondZoneDump,
		protocol.TypeGameRespondPublicZoneMove,
		protocol.TypeGameSearchLibrary,
		protocol.TypeGameReorderLibrary,
		protocol.TypeGameResolveLibraryView,
		protocol.TypeSideboardMove,
		protocol.TypeSideboardSetCommander,
		protocol.TypeSideboardReady,
		protocol.TypeReplayList,
		protocol.TypeReplayGet,
	}
	optional := []string{protocol.TypeSessionPing, protocol.TypeRoomLeave}
	if got, want := len(commandRegistry), len(required)+len(optional); got != want {
		t.Fatalf("command registry size = %d, want %d", got, want)
	}
	for _, messageType := range required {
		spec, ok := commandRegistry[messageType]
		if !ok {
			t.Errorf("command registry missing required command %q", messageType)
			continue
		}
		if spec.handle == nil {
			t.Errorf("command registry handler for %q is nil", messageType)
		}
		if !spec.requiresID || !requiresRequestID(messageType) {
			t.Errorf("command %q does not require id", messageType)
		}
	}
	for _, messageType := range optional {
		spec, ok := commandRegistry[messageType]
		if !ok {
			t.Errorf("command registry missing optional command %q", messageType)
			continue
		}
		if spec.handle == nil {
			t.Errorf("command registry handler for %q is nil", messageType)
		}
		if spec.requiresID || requiresRequestID(messageType) {
			t.Errorf("command %q unexpectedly requires id", messageType)
		}
	}
	if requiresRequestID("unknown.command") {
		t.Error("unknown command unexpectedly requires id")
	}
}
