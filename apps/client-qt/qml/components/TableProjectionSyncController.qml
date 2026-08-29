// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

pragma ComponentBehavior: Bound

import QtQuick

QtObject {
    id: root

    required property var tableRoot
    required property var seatStateComponent
    required property var gameLogModel

    property var ownHand: []
    property string ownHandModelSignature: ""
    property var handOrderIds: []
    property string activeHandDragCardId: ""
    property bool handModelSyncDeferred: false

    property var battlefieldSeats: []
    property string battlefieldSeatOrderSignature: ""
    property string activeBattlefieldDragCardId: ""
    property bool battlefieldSeatSyncDeferred: false

    function finishHandDrag() {
        activeHandDragCardId = ""
        if (!handModelSyncDeferred)
            return
        handModelSyncDeferred = false
        syncDisplayedOwnHand()
    }

    function finishBattlefieldDrag() {
        activeBattlefieldDragCardId = ""
        if (!battlefieldSeatSyncDeferred)
            return
        battlefieldSeatSyncDeferred = false
        syncBattlefieldSeats()
    }

    function handSignature(cards) {
        const signatureParts = []
        for (let index = 0; index < cards.length; ++index) {
            const card = cards[index]
            signatureParts.push(
                        String(card.id ? card.id : "") + "\u001e"
                        + String(card.name ? card.name : "") + "\u001e"
                        + String(card.setCode ? card.setCode : "") + "\u001e"
                        + String(card.collectorNumber
                                 ? card.collectorNumber : "") + "\u001e"
                        + (card.pending === true ? "1" : "0"))
        }
        return signatureParts.join("\u001f")
    }

    function orderedOwnHand(cards) {
        const cardsById = ({})
        for (let index = 0; index < cards.length; ++index)
            cardsById[cards[index].id] = cards[index]

        const ordered = []
        const included = ({})
        for (let index = 0; index < handOrderIds.length; ++index) {
            const cardId = handOrderIds[index]
            if (!cardsById[cardId])
                continue
            ordered.push(cardsById[cardId])
            included[cardId] = true
        }
        for (let index = 0; index < cards.length; ++index) {
            const card = cards[index]
            if (included[card.id])
                continue
            ordered.push(card)
            included[card.id] = true
        }
        handOrderIds = ordered.map(card => card.id)
        return ordered
    }

    function reorderDisplayedHandCard(cardId, targetIndex) {
        const cards = ownHand.slice()
        let sourceIndex = -1
        for (let index = 0; index < cards.length; ++index) {
            if (cards[index].id === cardId) {
                sourceIndex = index
                break
            }
        }
        if (sourceIndex < 0 || cards.length < 2)
            return false

        const boundedTarget = Math.max(
                    0, Math.min(cards.length - 1, targetIndex))
        if (boundedTarget === sourceIndex)
            return false
        const moved = cards.splice(sourceIndex, 1)[0]
        cards.splice(boundedTarget, 0, moved)
        handOrderIds = cards.map(card => card.id)
        ownHandModelSignature = handSignature(cards)
        ownHand = cards
        return true
    }

    function syncDisplayedOwnHand() {
        if (activeHandDragCardId.length > 0) {
            handModelSyncDeferred = true
            return
        }
        handModelSyncDeferred = false
        const pendingCards = []
        const included = ({})
        const authoritative = tableRoot.authoritativeOwnHand
                              ? tableRoot.authoritativeOwnHand : []
        for (let index = 0; index < authoritative.length; ++index) {
            const card = authoritative[index]
            included[card.id] = true
        }
        const pendingMoves = tableRoot.pendingCardMoves
                             ? tableRoot.pendingCardMoves : ({})
        const moveIds = Object.keys(pendingMoves)
        for (let index = 0; index < moveIds.length; ++index) {
            const move = pendingMoves[moveIds[index]]
            if (move.toZone === "hand"
                    && move.toSeat === tableRoot.roomSession.seatIndex
                    && move.card && move.card.id
                    && !included[move.card.id]) {
                pendingCards.push(move.card)
                included[move.card.id] = true
            }
        }
        const cards = orderedOwnHand(
                        authoritative.slice().concat(pendingCards))
        const signature = handSignature(cards)
        if (signature === ownHandModelSignature)
            return
        ownHandModelSignature = signature
        ownHand = cards
    }

    function syncGameLog() {
        const entries = tableRoot.tableGameLog ? tableRoot.tableGameLog : []
        let prefixMatches = gameLogModel.count <= entries.length
        if (prefixMatches) {
            for (let index = 0; index < gameLogModel.count; ++index) {
                const existing = gameLogModel.get(index)
                const incoming = entries[index]
                if (existing.entryId
                        !== (incoming.id !== undefined ? incoming.id : index)
                        || existing.entryKind
                           !== (incoming.kind ? incoming.kind : "")
                        || existing.entryText
                           !== (incoming.text ? incoming.text : "")) {
                    prefixMatches = false
                    break
                }
            }
        }
        if (!prefixMatches)
            gameLogModel.clear()
        for (let index = gameLogModel.count;
             index < entries.length; ++index) {
            const entry = entries[index]
            gameLogModel.append({
                "entryId": entry.id !== undefined ? entry.id : index,
                "entryKind": entry.kind ? entry.kind : "",
                "entrySeat": entry.seat !== undefined ? entry.seat : -1,
                "entryText": entry.text ? entry.text : ""
            })
        }
    }

    function visibleOwnHandCount() {
        let count = 0
        for (let index = 0; index < ownHand.length; ++index) {
            if (!tableRoot.optimisticCommands.isCardPendingFrom(
                        ownHand[index].id, "hand",
                        tableRoot.roomSession.seatIndex)) {
                ++count
            }
        }
        return count
    }

    function orderedBattlefieldSeatSnapshots() {
        const authoritative = tableRoot.authoritativeSeats
                              ? tableRoot.authoritativeSeats : []
        if (tableRoot.isEDH && authoritative.length >= 3) {
            const bySeat = ({})
            for (let index = 0; index < authoritative.length; ++index)
                bySeat[String(authoritative[index].seat)] = authoritative[index]

            const seatOrder = []
            const included = ({})
            const authoritativeOrder = tableRoot.turnOrder
                                       ? tableRoot.turnOrder : []
            for (let index = 0; index < authoritativeOrder.length; ++index) {
                const seat = Number(authoritativeOrder[index])
                if (!bySeat[String(seat)] || included[String(seat)])
                    continue
                seatOrder.push(seat)
                included[String(seat)] = true
            }
            for (let index = 0; index < authoritative.length; ++index) {
                const seat = authoritative[index].seat
                if (included[String(seat)])
                    continue
                seatOrder.push(seat)
                included[String(seat)] = true
            }

            let anchorSeat = seatOrder[0]
            if (tableRoot.roomSession.role === "player"
                    && bySeat[String(tableRoot.roomSession.seatIndex)]) {
                anchorSeat = tableRoot.roomSession.seatIndex
            }
            const anchorIndex = seatOrder.indexOf(anchorSeat)
            const clockwise = seatOrder.slice(anchorIndex)
                    .concat(seatOrder.slice(0, anchorIndex))
            if (clockwise.length === 3) {
                return [bySeat[String(clockwise[1])],
                        bySeat[String(clockwise[2])],
                        bySeat[String(clockwise[0])]]
            }
            return [bySeat[String(clockwise[1])],
                    bySeat[String(clockwise[2])],
                    bySeat[String(clockwise[0])],
                    bySeat[String(clockwise[clockwise.length - 1])]]
        }
        const otherSeats = []
        let ownSeat = null
        for (let seatIndex = 0;
             seatIndex < authoritative.length; ++seatIndex) {
            const seat = authoritative[seatIndex]
            if (seat.seat === tableRoot.roomSession.seatIndex)
                ownSeat = seat
            else
                otherSeats.push(seat)
        }
        if (ownSeat)
            otherSeats.push(ownSeat)
        return otherSeats
    }

    function destroySeatStates(states) {
        for (let index = 0; index < states.length; ++index) {
            if (states[index])
                states[index].destroy()
        }
    }

    function syncBattlefieldSeats() {
        if (activeBattlefieldDragCardId.length > 0) {
            battlefieldSeatSyncDeferred = true
            return
        }
        battlefieldSeatSyncDeferred = false
        const snapshots = orderedBattlefieldSeatSnapshots()
        const order = []
        for (let index = 0; index < snapshots.length; ++index)
            order.push(snapshots[index].seat)
        const signature = order.join(",")
        if (signature !== battlefieldSeatOrderSignature) {
            destroySeatStates(battlefieldSeats)
            const next = []
            for (let index = 0; index < snapshots.length; ++index) {
                const seatState = seatStateComponent.createObject(tableRoot)
                if (!seatState)
                    continue
                seatState.updateFrom(snapshots[index])
                next.push(seatState)
            }
            battlefieldSeatOrderSignature = signature
            battlefieldSeats = next
            return
        }
        for (let index = 0;
             index < snapshots.length && index < battlefieldSeats.length;
             ++index) {
            battlefieldSeats[index].updateFrom(snapshots[index])
        }
    }

    function reset() {
        destroySeatStates(battlefieldSeats)
        battlefieldSeats = []
        battlefieldSeatOrderSignature = ""
        ownHand = []
        ownHandModelSignature = ""
        handOrderIds = []
        gameLogModel.clear()
        activeHandDragCardId = ""
        handModelSyncDeferred = false
        activeBattlefieldDragCardId = ""
        battlefieldSeatSyncDeferred = false
    }

    Component.onDestruction: destroySeatStates(battlefieldSeats)
}
