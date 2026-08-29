// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

pragma ComponentBehavior: Bound

import QtQuick

QtObject {
    id: root

    required property var tableRoot
    required property var chatInput

    function numberCounterValue(counters) {
        const values = counters ? counters : []
        for (let index = 0; index < values.length; ++index) {
            if (values[index].kind === "number")
                return values[index].value
        }
        return 0
    }

    function abilityCounters(counters) {
        const result = []
        const values = counters ? counters : []
        for (let index = 0; index < values.length; ++index) {
            if (values[index].kind === "ability")
                result.push(values[index])
        }
        return result
    }

    function abilityCounterSummary(counters) {
        const values = abilityCounters(counters)
        const lines = []
        for (let index = 0; index < values.length; ++index)
            lines.push(values[index].label + " · " + values[index].value)
        return lines.join("\n")
    }

    function adjustNumberCounter(delta) {
        if (!tableRoot.canAct
                || tableRoot.selectedBattlefieldOwnerSeat
                   !== tableRoot.roomSession.seatIndex
                || !tableRoot.selectedBattlefieldCardId) {
            return false
        }
        const counters = tableRoot.selectedBattlefieldCard.counters
                         ? tableRoot.selectedBattlefieldCard.counters : []
        if (numberCounterValue(counters) + delta < 0)
            return false
        tableRoot.wsModel.setCardCounter(
                    tableRoot.selectedBattlefieldCardId, {
                        "counterId": "number",
                        "kind": "number",
                        "delta": delta
                    })
        return true
    }

    function addNumberCounter() {
        return adjustNumberCounter(1)
    }

    function createSelectedTokenCopy() {
        const card = tableRoot.selectedBattlefieldCard
        if (!tableRoot.canAct || !card || !card.name)
            return false
        const position = card.position ? card.position : ({})
        tableRoot.wsModel.createToken({
            "name": card.name,
            "setCode": card.setCode ? card.setCode : "",
            "collectorNumber": card.collectorNumber
                               ? card.collectorNumber : "",
            "typeLine": card.typeLine ? card.typeLine : ""
        }, {
            "x": Math.max(0, Math.min(
                              1,
                              (position.x !== undefined
                               ? position.x : 0.5) + 0.04)),
            "y": Math.max(0, Math.min(
                              1,
                              (position.y !== undefined
                               ? position.y : 0.3) + 0.04))
        })
        tableRoot.selection.clear()
        return true
    }

    function submitChatMessage() {
        const message = chatInput.text.trim()
        if (!tableRoot.canChat || message.length === 0)
            return false
        tableRoot.wsModel.sayGameMessage(message)
        chatInput.clear()
        chatInput.forceActiveFocus()
        return true
    }

    function toggleHandReveal() {
        if (tableRoot.zoneState.handRevealTransitionPending())
            return false
        const moves = []
        if (tableRoot.ownRevealedCards.length > 0) {
            for (let index = 0;
                 index < tableRoot.ownRevealedCards.length; ++index) {
                const card = tableRoot.ownRevealedCards[index]
                moves.push({
                    "cardId": card.id,
                    "card": card,
                    "fromZone": "reveal",
                    "fromSeat": -1,
                    "toZone": "hand",
                    "toSeat": tableRoot.roomSession.seatIndex
                })
            }
            tableRoot.optimisticCommands.beginPendingCardMoves(moves)
            tableRoot.wsModel.recallRevealed()
            return true
        }

        for (let index = 0; index < tableRoot.ownHand.length; ++index) {
            const card = tableRoot.ownHand[index]
            if (tableRoot.optimisticCommands.isCardPendingFrom(
                        card.id, "hand", tableRoot.roomSession.seatIndex)) {
                continue
            }
            moves.push({
                "cardId": card.id,
                "card": card,
                "fromZone": "hand",
                "fromSeat": tableRoot.roomSession.seatIndex,
                "toZone": "reveal",
                "toSeat": -1
            })
        }
        if (moves.length === 0)
            return false
        tableRoot.optimisticCommands.beginPendingCardMoves(moves)
        tableRoot.wsModel.revealHand()
        return true
    }
}
