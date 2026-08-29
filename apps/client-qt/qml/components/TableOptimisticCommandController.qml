// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

pragma ComponentBehavior: Bound

import QtQuick

QtObject {
    id: root

    required property var model
    required property var wsModel

    readonly property var pendingCardMoves:
        model ? model.cardMoves : ({})
    property string counterCountRequestId: ""
    property int counterCountRequestGame: -1
    property int counterCountRequestValue: -1

    function isCardPendingFrom(cardId, zone, seat) {
        if (!cardId || !Object.prototype.hasOwnProperty.call(
                    pendingCardMoves, cardId)) {
            return false
        }
        const move = pendingCardMoves[cardId]
        return move.fromZone === zone
                && (move.fromSeat === seat || move.fromSeat < 0 || seat < 0)
    }

    function beginPendingCardMove(cardId, card, fromZone, fromSeat,
                                  toZone, toSeat) {
        beginPendingCardMoves([{
            "cardId": cardId,
            "card": card,
            "fromZone": fromZone,
            "fromSeat": fromSeat,
            "toZone": toZone,
            "toSeat": toSeat
        }])
    }

    function beginPendingCardMoves(moves) {
        model.beginCardMoves(moves ? moves : [])
    }

    function removePendingCardMove(cardId) {
        model.removeValue("move", cardId)
    }

    function clearPendingCardMoves() {
        model.clearCardMoves()
    }

    function bindPendingCardMoveRequest(cardId, requestId) {
        model.bindRequest("move", cardId, requestId)
    }

    function rollbackPendingCardMove(cardId, requestId) {
        model.rollback("move", cardId, requestId)
    }

    function bindOptimisticValueRequest(kind, key, requestId) {
        model.bindRequest(kind, key, requestId)
    }

    function rollbackOptimisticValue(kind, key, requestId) {
        model.rollback(kind, key, requestId)
    }

    function clearOptimisticPhase() {
        model.clearPhase()
    }

    function beginLandPlayCount(value) {
        model.beginLandPlayCount(value)
    }

    function displayedLandPlayCount(authoritativeValue) {
        return model.landPlayCount >= 0
                ? model.landPlayCount : authoritativeValue
    }

    function reconcileLandPlayCount(authoritativeValue) {
        if (model.landPlayCount < 0)
            return
        if (model.landPlayCount === authoritativeValue) {
            model.clearLandPlayCount()
        }
    }

    function trackQueuedCommand(requestId, commandType, payload) {
        if (!requestId || !commandType)
            return
        const commandPayload = payload ? payload : ({})
        if (commandType === "game.move_card") {
            bindPendingCardMoveRequest(commandPayload.cardId, requestId)
        } else if (commandType === "game.move_cards") {
            const cardIds = commandPayload.cardIds
                            ? commandPayload.cardIds : []
            for (let index = 0; index < cardIds.length; ++index)
                bindPendingCardMoveRequest(cardIds[index], requestId)
        } else if (commandType === "game.set_tapped") {
            bindOptimisticValueRequest(
                        "tapped", commandPayload.cardId, requestId)
        } else if (commandType === "game.set_arrow") {
            const tappedCardIds = commandPayload.tappedSourceCardIds
                                  ? commandPayload.tappedSourceCardIds : []
            for (let index = 0; index < tappedCardIds.length; ++index) {
                bindOptimisticValueRequest(
                            "tapped", tappedCardIds[index], requestId)
            }
        } else if (commandType === "game.set_counter") {
            const counter = commandPayload.counter
            if (counter === "life") {
                bindOptimisticValueRequest(
                            "life", String(wsModel.roomSession.seatIndex), requestId)
            } else {
                bindOptimisticValueRequest(
                            "counter",
                            String(wsModel.roomSession.seatIndex) + ":" + counter,
                            requestId)
            }
        } else if (commandType === "game.adjust_commander_tax") {
            bindOptimisticValueRequest(
                        "tax", String(wsModel.roomSession.seatIndex) + ":"
                               + commandPayload.commanderId, requestId)
        } else if (commandType === "game.set_phase"
                   || commandType === "game.next_turn") {
            model.bindPhaseRequest(requestId)
        } else if (commandType === "game.set_counter_count") {
            counterCountRequestId = requestId
        } else if (commandType === "game.play_land") {
            bindPendingCardMoveRequest(commandPayload.cardId, requestId)
            model.bindLandPlayCountRequest(requestId)
        } else if (commandType === "game.set_land_play_count") {
            model.bindLandPlayCountRequest(requestId)
        }
    }

    function rollbackFailedCommand(requestId, commandType, payload) {
        if (!commandType)
            return
        const commandPayload = payload ? payload : ({})
        if (commandType === "game.move_card") {
            rollbackPendingCardMove(commandPayload.cardId, requestId)
        } else if (commandType === "game.move_cards") {
            const cardIds = commandPayload.cardIds
                            ? commandPayload.cardIds : []
            for (let index = 0; index < cardIds.length; ++index)
                rollbackPendingCardMove(cardIds[index], requestId)
        } else if (commandType === "game.set_tapped") {
            rollbackOptimisticValue(
                        "tapped", commandPayload.cardId, requestId)
        } else if (commandType === "game.set_arrow") {
            const tappedCardIds = commandPayload.tappedSourceCardIds
                                  ? commandPayload.tappedSourceCardIds : []
            for (let index = 0; index < tappedCardIds.length; ++index) {
                rollbackOptimisticValue(
                            "tapped", tappedCardIds[index], requestId)
            }
        } else if (commandType === "game.set_counter") {
            const counter = commandPayload.counter
            if (counter === "life") {
                rollbackOptimisticValue(
                            "life", String(wsModel.roomSession.seatIndex), requestId)
            } else {
                rollbackOptimisticValue(
                            "counter",
                            String(wsModel.roomSession.seatIndex) + ":" + counter,
                            requestId)
            }
        } else if (commandType === "game.adjust_commander_tax") {
            rollbackOptimisticValue(
                        "tax", String(wsModel.roomSession.seatIndex) + ":"
                               + commandPayload.commanderId, requestId)
        } else if (commandType === "game.set_phase"
                   || commandType === "game.next_turn") {
            model.rollbackPhase(requestId)
        } else if (commandType === "game.set_counter_count"
                   && (!requestId
                       || counterCountRequestId === requestId)) {
            resetCounterCountRequest()
        } else if (commandType === "game.play_land") {
            rollbackPendingCardMove(commandPayload.cardId, requestId)
            model.rollbackLandPlayCount(requestId)
        } else if (commandType === "game.set_land_play_count") {
            model.rollbackLandPlayCount(requestId)
        }
    }

    function trackOptimisticValues(kind, keys) {
        model.trackValues(kind, keys ? keys : [])
    }

    function resetCounterCountRequest() {
        counterCountRequestGame = -1
        counterCountRequestValue = -1
        counterCountRequestId = ""
    }
}
