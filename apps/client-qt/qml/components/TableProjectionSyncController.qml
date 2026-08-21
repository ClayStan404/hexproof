// SPDX-License-Identifier: GPL-2.0-only
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
        const cards = authoritative.slice().concat(pendingCards)
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
        const signature = signatureParts.join("\u001f")
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
        if (tableRoot.isEDH
                && tableRoot.roomSession.role === "player"
                && tableRoot.roomSession.seatIndex >= 0) {
            if (authoritative.length === 3) {
                const threePlayerOrder = []
                const ownSeat = tableRoot.roomSession.seatIndex
                for (let offset = 1; offset < 4; ++offset) {
                    const wantedSeat = (ownSeat + offset) % 4
                    for (let gameSeatIndex = 0;
                         gameSeatIndex < authoritative.length;
                         ++gameSeatIndex) {
                        if (authoritative[gameSeatIndex].seat === wantedSeat) {
                            threePlayerOrder.push(
                                        authoritative[gameSeatIndex])
                            break
                        }
                    }
                }
                for (let gameSeatIndex = 0;
                     gameSeatIndex < authoritative.length;
                     ++gameSeatIndex) {
                    if (authoritative[gameSeatIndex].seat === ownSeat) {
                        threePlayerOrder.push(authoritative[gameSeatIndex])
                        break
                    }
                }
                return threePlayerOrder
            }
            const ordered = []
            const offsets = [1, 2, 0, 3]
            for (let offsetIndex = 0;
                 offsetIndex < offsets.length; ++offsetIndex) {
                const wantedSeat = (tableRoot.roomSession.seatIndex
                                    + offsets[offsetIndex]) % 4
                for (let gameSeatIndex = 0;
                     gameSeatIndex < authoritative.length;
                     ++gameSeatIndex) {
                    if (authoritative[gameSeatIndex].seat === wantedSeat) {
                        ordered.push(authoritative[gameSeatIndex])
                        break
                    }
                }
            }
            return ordered
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
        gameLogModel.clear()
        activeHandDragCardId = ""
        handModelSyncDeferred = false
        activeBattlefieldDragCardId = ""
        battlefieldSeatSyncDeferred = false
    }

    Component.onDestruction: destroySeatStates(battlefieldSeats)
}
