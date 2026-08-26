// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package server

import (
	"context"
	"sync/atomic"
	"time"

	"github.com/coder/websocket"

	"hexproof/server/internal/protocol"
)

type commandHandler func(*Handler, *Session, protocol.Envelope) error

type commandSpec struct {
	requiresID bool
	handle     commandHandler
}

func requiredCommand(handle commandHandler) commandSpec {
	return commandSpec{requiresID: true, handle: handle}
}

func optionalCommand(handle commandHandler) commandSpec {
	return commandSpec{handle: handle}
}

var commandRegistry = map[string]commandSpec{
	protocol.TypeSessionHello:              requiredCommand((*Handler).handleHello),
	protocol.TypeSessionPing:               optionalCommand(handleSessionPing),
	protocol.TypeRoomCreate:                requiredCommand((*Handler).handleRoomCreate),
	protocol.TypeRoomList:                  requiredCommand((*Handler).handleRoomList),
	protocol.TypeRoomJoin:                  requiredCommand((*Handler).handleRoomJoin),
	protocol.TypeRoomLeave:                 optionalCommand((*Handler).handleRoomLeave),
	protocol.TypeRoomKick:                  requiredCommand((*Handler).handleRoomKick),
	protocol.TypeRoomDisband:               requiredCommand((*Handler).handleRoomDisband),
	protocol.TypeTournamentList:            requiredCommand((*Handler).handleTournamentList),
	protocol.TypeTournamentCreate:          requiredCommand((*Handler).handleTournamentCreate),
	protocol.TypeTournamentEnter:           requiredCommand((*Handler).handleTournamentEnter),
	protocol.TypeTournamentLeave:           requiredCommand((*Handler).handleTournamentLeave),
	protocol.TypeTournamentRegister:        requiredCommand((*Handler).handleTournamentRegister),
	protocol.TypeTournamentUnregister:      requiredCommand((*Handler).handleTournamentUnregister),
	protocol.TypeTournamentCheckIn:         requiredCommand((*Handler).handleTournamentCheckIn),
	protocol.TypeTournamentStart:           requiredCommand((*Handler).handleTournamentStart),
	protocol.TypeTournamentDrop:            requiredCommand((*Handler).handleTournamentDrop),
	protocol.TypeTournamentReportResult:    requiredCommand((*Handler).handleTournamentReportResult),
	protocol.TypeTournamentConfirmResult:   requiredCommand((*Handler).handleTournamentConfirmResult),
	protocol.TypeTournamentRejectResult:    requiredCommand((*Handler).handleTournamentRejectResult),
	protocol.TypeTournamentCorrectResult:   requiredCommand((*Handler).handleTournamentCorrectResult),
	protocol.TypeTournamentNextRound:       requiredCommand((*Handler).handleTournamentNextRound),
	protocol.TypeTournamentOpenMatch:       requiredCommand((*Handler).handleTournamentOpenMatch),
	protocol.TypeTournamentCancel:          requiredCommand((*Handler).handleTournamentCancel),
	protocol.TypeLimitedCreateCasualMatch:  requiredCommand((*Handler).handleLimitedCreateCasualMatch),
	protocol.TypeLimitedPick:               requiredCommand((*Handler).handleLimitedPick),
	protocol.TypeLimitedSubmitDeck:         requiredCommand((*Handler).handleLimitedSubmitDeck),
	protocol.TypeDeckSelect:                requiredCommand((*Handler).handleDeckSelect),
	protocol.TypePlayerReady:               requiredCommand((*Handler).handlePlayerReady),
	protocol.TypeClientLoadComplete:        requiredCommand((*Handler).handleClientLoadComplete),
	protocol.TypeGameDraw:                  requiredCommand((*Handler).handleGameDraw),
	protocol.TypeGameShuffleLibrary:        requiredCommand((*Handler).handleGameShuffleLibrary),
	protocol.TypeGameMulligan:              requiredCommand((*Handler).handleGameMulligan),
	protocol.TypeGameDiscardHand:           requiredCommand((*Handler).handleGameDiscardHand),
	protocol.TypeGameMoveCard:              requiredCommand((*Handler).handleGameMoveCard),
	protocol.TypeGameArrangeBattlefield:    requiredCommand((*Handler).handleGameArrangeBattlefield),
	protocol.TypeGameMoveCards:             requiredCommand((*Handler).handleGameMoveCards),
	protocol.TypeGameMoveLibraryCards:      requiredCommand((*Handler).handleGameMoveLibraryCards),
	protocol.TypeGameSetTapped:             requiredCommand((*Handler).handleGameSetTapped),
	protocol.TypeGameSetCardFace:           requiredCommand((*Handler).handleGameSetCardFace),
	protocol.TypeGameSetFaceDown:           requiredCommand((*Handler).handleGameSetFaceDown),
	protocol.TypeGameSetCardCounter:        requiredCommand((*Handler).handleGameSetCardCounter),
	protocol.TypeGameSetPhase:              requiredCommand((*Handler).handleGameSetPhase),
	protocol.TypeGameSetResponseStatus:     requiredCommand((*Handler).handleGameSetResponseStatus),
	protocol.TypeGameSetCounter:            requiredCommand((*Handler).handleGameSetCounter),
	protocol.TypeGameSetCounterCount:       requiredCommand((*Handler).handleGameSetCounterCount),
	protocol.TypeGameConcede:               requiredCommand((*Handler).handleGameConcede),
	protocol.TypeGameDeclareDraw:           requiredCommand((*Handler).handleGameDeclareDraw),
	protocol.TypeGameRestart:               requiredCommand((*Handler).handleGameRestart),
	protocol.TypeGameRoll:                  requiredCommand((*Handler).handleGameRoll),
	protocol.TypeGameFlipCoin:              requiredCommand((*Handler).handleGameFlipCoin),
	protocol.TypeGameRandomSelect:          requiredCommand((*Handler).handleGameRandomSelect),
	protocol.TypeGameReturnToRoom:          requiredCommand((*Handler).handleGameReturnToRoom),
	protocol.TypeGameSay:                   requiredCommand((*Handler).handleGameSay),
	protocol.TypeGameCreateToken:           requiredCommand((*Handler).handleGameCreateToken),
	protocol.TypeGamePlayLand:              requiredCommand((*Handler).handleGamePlayLand),
	protocol.TypeGameSetLandPlayCount:      requiredCommand((*Handler).handleGameSetLandPlayCount),
	protocol.TypeGameAdjustCommanderTax:    requiredCommand((*Handler).handleGameAdjustCommanderTax),
	protocol.TypeGameCastCommander:         requiredCommand((*Handler).handleGameCastCommander),
	protocol.TypeGameSetCommanderDamage:    requiredCommand((*Handler).handleGameSetCommanderDamage),
	protocol.TypeGameSetArrow:              requiredCommand((*Handler).handleGameSetArrow),
	protocol.TypeGameSetAttachment:         requiredCommand((*Handler).handleGameSetAttachment),
	protocol.TypeGameNextTurn:              requiredCommand((*Handler).handleGameNextTurn),
	protocol.TypeGameReveal:                requiredCommand((*Handler).handleGameReveal),
	protocol.TypeGameRecallRevealed:        requiredCommand((*Handler).handleGameRecallRevealed),
	protocol.TypeGameDumpZone:              requiredCommand((*Handler).handleGameDumpZone),
	protocol.TypeGameRespondZoneDump:       requiredCommand((*Handler).handleGameRespondZoneDump),
	protocol.TypeGameRespondPublicZoneMove: requiredCommand((*Handler).handleGameRespondPublicZoneMove),
	protocol.TypeGameSearchLibrary:         requiredCommand((*Handler).handleGameSearchLibrary),
	protocol.TypeGameReorderLibrary:        requiredCommand((*Handler).handleGameReorderLibrary),
	protocol.TypeGameResolveLibraryView:    requiredCommand((*Handler).handleGameResolveLibraryView),
	protocol.TypeSideboardMove:             requiredCommand((*Handler).handleSideboardMove),
	protocol.TypeSideboardSetCommander:     requiredCommand((*Handler).handleSideboardSetCommander),
	protocol.TypeSideboardReady:            requiredCommand((*Handler).handleSideboardReady),
	protocol.TypeReplayList:                requiredCommand((*Handler).handleReplayList),
	protocol.TypeReplayGet:                 requiredCommand((*Handler).handleReplayGet),
}

// readLoop reads envelopes until the connection closes.
func (h *Handler) readLoop(ctx context.Context, conn *websocket.Conn, sess *Session) error {
	var helloTimedOut atomic.Bool
	helloTimer := time.AfterFunc(h.config.HelloTimeout, func() {
		helloTimedOut.Store(true)
		_ = conn.Close(websocket.StatusPolicyViolation, "session.hello timeout")
	})
	defer helloTimer.Stop()

	for {
		_, data, err := conn.Read(ctx)
		if err != nil {
			if helloTimedOut.Load() {
				return errSessionHelloTimeout
			}
			return err
		}
		if !sess.allowMessage(time.Now(), h.config.MessagesPerSecond) {
			h.sendError(sess, "", protocol.ErrRateLimited, "message rate limit exceeded")
			continue
		}
		env, err := protocol.ParseEnvelope(data)
		if err != nil {
			h.sendError(sess, "", protocol.ErrInvalidMessage, err.Error())
			continue
		}
		if err := h.dispatch(ctx, conn, sess, env); err != nil {
			return err
		}
		if sess.DisplayName != "" {
			helloTimer.Stop()
		}
	}
}

// dispatch routes one envelope using the same registry that owns request-id
// policy. Adding a command therefore cannot update routing without also making
// an explicit id-policy choice.
func (h *Handler) dispatch(_ context.Context, _ *websocket.Conn, sess *Session, env protocol.Envelope) error {
	spec, ok := commandRegistry[env.Type]
	if !ok {
		h.sendError(sess, env.ID, protocol.ErrInvalidMessage, "unknown type: "+env.Type)
		return nil
	}
	if spec.requiresID && env.ID == "" {
		h.sendError(sess, "", protocol.ErrInvalidMessage, "id required for "+env.Type)
		return nil
	}
	return spec.handle(h, sess, env)
}

func requiresRequestID(messageType string) bool {
	spec, ok := commandRegistry[messageType]
	return ok && spec.requiresID
}

func handleSessionPing(h *Handler, sess *Session, env protocol.Envelope) error {
	h.sendPong(sess, env.ID)
	return nil
}
