// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

pragma ComponentBehavior: Bound

import QtQuick

QtObject {
    id: root

    required property var tableRoot

    function zoneModelForSeat(seatIndex, zone) {
        // Make a null-to-model transition observable when Table is created
        // before the first game snapshot (notably in solo playtest).
        const snapshotSeats = tableRoot.gameTableModel.seats
        return tableRoot.gameTableModel.zoneModel(seatIndex, zone)
    }

    function cardsFromZoneModel(model) {
        if (!model)
            return []
        // revision makes same-sized card replacements observable to bindings
        // that need an array for optimistic overlays or command helpers.
        const revision = model.revision
        const cards = []
        for (let index = 0; index < model.count; ++index)
            cards.push(model.get(index))
        return cards
    }

    function zoneCardsForSeat(seatIndex, zone) {
        const model = zoneModelForSeat(seatIndex, zone)
        return cardsFromZoneModel(model)
    }

    function sharedZoneCards(zone) {
        const model = zoneModelForSeat(-1, zone)
        return cardsFromZoneModel(model)
    }

    function zoneCardCount(seatIndex, zone) {
        const model = zoneModelForSeat(seatIndex, zone)
        return model ? model.count : 0
    }

    function zoneCardAt(seatIndex, zone, index) {
        const model = zoneModelForSeat(seatIndex, zone)
        return model && index >= 0 && index < model.count
               ? model.get(index) : ({})
    }

    function zoneDelegateModel(seatIndex, zone) {
        const model = zoneModelForSeat(seatIndex, zone)
        return model ? model : []
    }

    function modelCardCount(model) {
        if (!model)
            return 0
        return model.count !== undefined ? model.count : model.length
    }

    function cardInZone(cardId, zone, seat) {
        if (!cardId)
            return false
        return tableRoot.gameTableModel.cardInZone(cardId, zone, seat)
    }

    function cardDataForId(cardId) {
        if (Object.prototype.hasOwnProperty.call(
                    tableRoot.pendingCardMoves, cardId)
            && tableRoot.pendingCardMoves[cardId].card) {
            return tableRoot.pendingCardMoves[cardId].card
        }
        const indexedCard = tableRoot.gameTableModel.cardData(cardId)
        if (indexedCard && indexedCard.id)
            return indexedCard
        return ({"id": cardId})
    }

    function visibleZoneSeatForCard(cardId, zone) {
        if (zone === "stack" || zone === "reveal")
            return -1
        if (zone === "hand")
            return tableRoot.roomSession.seatIndex
        return tableRoot.gameTableModel.visibleZoneSeat(cardId, zone)
    }

    function reconcilePendingCardMoves() {
        const moveIds = Object.keys(tableRoot.pendingCardMoves)
        for (let index = 0; index < moveIds.length; ++index) {
            const cardId = moveIds[index]
            const move = tableRoot.pendingCardMoves[cardId]
            if (move.toZone === "battlefield") {
                if (move.fromZone !== "library"
                    && cardInZone(cardId, "battlefield", move.toSeat)) {
                    tableRoot.optimisticCommandModel.removeValue(
                                "move", cardId)
                }
                continue
            }
            if (!cardInZone(cardId, move.fromZone, move.fromSeat)
                || cardInZone(cardId, move.toZone, move.toSeat)) {
                tableRoot.optimisticCommandModel.removeValue("move", cardId)
            }
        }
    }

    function pendingBattlefieldMovesForSeat(seatIndex) {
        const cards = []
        const moveIds = Object.keys(tableRoot.pendingCardMoves)
        for (let index = 0; index < moveIds.length; ++index) {
            const move = tableRoot.pendingCardMoves[moveIds[index]]
            if (move.toZone !== "battlefield" || move.toSeat !== seatIndex)
                continue
            const card = move.card ? Object.assign({}, move.card) : ({})
            card.cardId = move.cardId
            card.id = card.id ? card.id : move.cardId
            card.x = move.x !== undefined ? move.x : 0
            card.y = move.y !== undefined ? move.y : 0
            card.tapped = move.tapped === true
            cards.push(card)
        }
        return cards
    }

    function displayedPublicZoneTopCard(seatIndex, zoneKey) {
        const cards = zoneCardsForSeat(seatIndex, zoneKey)
        let topCard = ({})
        for (let index = cards.length - 1; index >= 0; --index) {
            if (!tableRoot.optimisticCommands.isCardPendingFrom(
                        cards[index].id, zoneKey, seatIndex)) {
                topCard = cards[index]
                break
            }
        }
        const moveIds = Object.keys(tableRoot.pendingCardMoves)
        for (let index = 0; index < moveIds.length; ++index) {
            const move = tableRoot.pendingCardMoves[moveIds[index]]
            if (move.toZone === zoneKey && move.toSeat === seatIndex
                && move.card) {
                topCard = move.card
            }
        }
        return topCard
    }

    function revealedCardsForSeat(seatIndex) {
        const revealed = sharedZoneCards("reveal")
        const cards = []
        for (let index = 0; index < revealed.length; ++index) {
            if (revealed[index].ownerSeat === seatIndex)
                cards.push(revealed[index])
        }
        return cards
    }

    function handRevealTransitionPending() {
        const moveIds = Object.keys(tableRoot.pendingCardMoves)
        for (let index = 0; index < moveIds.length; ++index) {
            const move = tableRoot.pendingCardMoves[moveIds[index]]
            if ((move.fromZone === "hand" && move.toZone === "reveal")
                || (move.fromZone === "reveal" && move.toZone === "hand")) {
                return true
            }
        }
        return false
    }
}
