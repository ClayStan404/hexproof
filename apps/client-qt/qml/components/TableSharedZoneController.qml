// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

pragma ComponentBehavior: Bound

import QtQuick

QtObject {
    id: root

    required property var tableRoot
    required property string playerLabel
    required property string revealedLabel

    property var selectedCard: ({})
    property string selectedZone: ""
    property var opponentExpansionBySeat: ({})
    property var opponentPanelPositionBySeat: ({})

    readonly property bool selectedOwned:
        selectedCard.ownerSeat === tableRoot.roomSession.seatIndex
    readonly property var cards: combinedCards()

    function displayNameForSeat(seatIndex) {
        const seat = tableRoot.seatState.seatData(seatIndex)
        return seat.displayName ? seat.displayName : playerLabel
    }

    function selectCard(card, zone) {
        selectedCard = card && card.id ? card : ({})
        selectedZone = selectedCard.id ? zone : ""
    }

    function clearSelection() {
        selectedCard = ({})
        selectedZone = ""
    }

    function opponentZoneExpanded(seat) {
        const stored = opponentExpansionBySeat[String(seat)]
        return stored === undefined ? false : stored === true
    }

    function setOpponentZoneExpanded(seat, expanded) {
        const next = Object.assign({}, opponentExpansionBySeat)
        next[String(seat)] = expanded === true
        opponentExpansionBySeat = next
    }

    function opponentZonePanelPosition(seat) {
        const stored = opponentPanelPositionBySeat[String(seat)]
        if (!stored || !Number.isFinite(stored.x)
                || !Number.isFinite(stored.y)) {
            return ({})
        }
        return stored
    }

    function setOpponentZonePanelPosition(seat, xRatio, yRatio) {
        const next = Object.assign({}, opponentPanelPositionBySeat)
        next[String(seat)] = {
            "x": Math.max(0, Math.min(1, xRatio)),
            "y": Math.max(0, Math.min(1, yRatio))
        }
        opponentPanelPositionBySeat = next
    }

    function resetOpponentZonePanelPosition(seat) {
        const next = Object.assign({}, opponentPanelPositionBySeat)
        delete next[String(seat)]
        opponentPanelPositionBySeat = next
    }

    function combinedCards() {
        const result = []
        const stackCards = tableRoot.stackCards ? tableRoot.stackCards : []
        for (let index = 0; index < stackCards.length; ++index) {
            const card = stackCards[index]
            result.push(Object.assign(
                            {}, card,
                            {
                                "sharedZone": "stack",
                                "ownerDisplayName":
                                    displayNameForSeat(card.ownerSeat)
                            }))
        }

        const revealEntries = []
        const revealedCards = tableRoot.revealedCards
                              ? tableRoot.revealedCards : []
        for (let index = 0; index < revealedCards.length; ++index) {
            revealEntries.push(Object.assign({}, revealedCards[index],
                                              {"sharedZone": "reveal"}))
        }

        const pendingMoves = tableRoot.pendingCardMoves
                             ? tableRoot.pendingCardMoves : ({})
        const moveIds = Object.keys(pendingMoves)
        for (let index = 0; index < moveIds.length; ++index) {
            const move = pendingMoves[moveIds[index]]
            if (!move.card
                    || (move.toZone !== "stack" && move.toZone !== "reveal")
                    || tableRoot.zoneState.cardInZone(move.card.id, move.toZone, -1)) {
                continue
            }
            const entry = Object.assign({}, move.card,
                                        {"sharedZone": move.toZone})
            if (move.toZone === "stack") {
                entry.ownerDisplayName = displayNameForSeat(
                            move.card.ownerSeat)
            }
            if (move.toZone === "reveal")
                revealEntries.push(entry)
            else
                result.push(entry)
        }

        const revealSeats = []
        for (let index = 0; index < revealEntries.length; ++index) {
            const seat = revealEntries[index].ownerSeat
            if (revealSeats.indexOf(seat) < 0)
                revealSeats.push(seat)
        }
        if (revealSeats.length <= 1)
            return result.concat(revealEntries)

        for (let seatIndex = 0; seatIndex < revealSeats.length; ++seatIndex) {
            const seat = revealSeats[seatIndex]
            let first = true
            for (let cardIndex = 0;
                 cardIndex < revealEntries.length; ++cardIndex) {
                if (revealEntries[cardIndex].ownerSeat !== seat)
                    continue
                result.push(Object.assign(
                                {}, revealEntries[cardIndex],
                                first
                                ? {
                                      "revealDivider": true,
                                      "revealDividerLabel":
                                          displayNameForSeat(seat)
                                          + " · " + revealedLabel
                                  }
                                : {}))
                first = false
            }
        }
        return result
    }

    function reconcileSelection() {
        if (!selectedCard.id)
            return
        const visibleCards = cards
        for (let index = 0; index < visibleCards.length; ++index) {
            if (visibleCards[index].id === selectedCard.id
                    && visibleCards[index].sharedZone === selectedZone) {
                selectedCard = visibleCards[index]
                return
            }
        }
        clearSelection()
    }

    function reset() {
        clearSelection()
        opponentExpansionBySeat = ({})
        opponentPanelPositionBySeat = ({})
    }
}
