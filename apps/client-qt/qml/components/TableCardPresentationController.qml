// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

pragma ComponentBehavior: Bound

import QtQuick

QtObject {
    id: root

    required property var tableRoot

    property string prioritizedSignature: ""
    property bool prioritizingVisibleCards: false
    property var inspectedCard: ({})
    property var inspectedSourceItem: null
    property bool hoverPreviewVisible: false
    property real hoverPreviewX: 0
    property real hoverPreviewY: 0

    function cardImageSource(card) {
        if (!card || !card.name)
            return ""
        const catalog = tableRoot.cardCatalogModel
        if (!catalog)
            return ""
        if (typeof catalog.imageRevision !== "undefined"
                && catalog.imageRevision === -1) {
            return ""
        }
        return catalog.imageSource(
                    card.faceName ? card.faceName : card.name,
                    card.setCode ? card.setCode : "",
                    card.collectorNumber ? card.collectorNumber : "")
    }

    function availableCardFaces(card) {
        const catalog = tableRoot.cardCatalogModel
        if (!card || !card.name || !catalog
                || typeof catalog.cardFaces !== "function") {
            return []
        }
        return catalog.cardFaces(
                    card.name, card.setCode ? card.setCode : "",
                    card.collectorNumber ? card.collectorNumber : "")
    }

    function tableCardImageSource(card) {
        if (card && card.faceDown === true)
            return tableRoot.cardBackSource
        if (!card || !card.name)
            return ""
        const catalog = tableRoot.cardCatalogModel
        if (!catalog)
            return ""
        if (typeof catalog.imageRevision !== "undefined"
                && catalog.imageRevision === -1) {
            return ""
        }
        if (typeof catalog.tableImageSource === "function") {
            return catalog.tableImageSource(
                        card.faceName ? card.faceName : card.name,
                        card.setCode ? card.setCode : "",
                        card.collectorNumber ? card.collectorNumber : "")
        }
        return cardImageSource(card)
    }

    function tableCardPlaceholderName(card) {
        if (!card || card.faceDown === true)
            return ""
        return card.name ? card.name : ""
    }

    function priorityCard(card) {
        if (!card || !card.faceName)
            return card
        return Object.assign({}, card, {"name": card.faceName})
    }

    function cardKey(card) {
        const catalog = tableRoot.cardCatalogModel
        const language = catalog
                         && typeof catalog.language !== "undefined"
                         ? catalog.language : ""
        return language + "\u001f"
                + String(card.name).trim().toLowerCase() + "\u001f"
                + String(card.setCode ? card.setCode : "").toUpperCase()
                + "\u001f"
                + String(card.collectorNumber
                         ? card.collectorNumber : "")
    }

    function appendVisibleCard(cards, keys, card) {
        if (!card || !card.name)
            return
        const requestCard = priorityCard(card)
        const key = cardKey(requestCard)
        if (keys[key] === true)
            return
        keys[key] = true
        cards.push(requestCard)
    }

    function appendZone(cards, keys, zoneCards) {
        const values = zoneCards ? zoneCards : []
        for (let index = 0; index < values.length; ++index)
            appendVisibleCard(cards, keys, values[index])
    }

    function invalidatePriorities() {
        prioritizedSignature = ""
    }

    function prioritizeVisibleCards() {
        const catalog = tableRoot.cardCatalogModel
        if (prioritizingVisibleCards
                || !catalog || typeof catalog.prioritizeCards !== "function")
            return

        const cards = []
        const keys = ({})
        appendZone(cards, keys, tableRoot.authoritativeOwnHand)

        const seats = tableRoot.authoritativeSeats
                      ? tableRoot.authoritativeSeats : []
        for (let index = 0; index < seats.length; ++index) {
            appendZone(cards, keys, tableRoot.zoneState.zoneCardsForSeat(
                           seats[index].seat, "battlefield"))
        }
        appendZone(cards, keys, tableRoot.stackCards)
        appendZone(cards, keys, tableRoot.revealedCards)
        for (let index = 0; index < seats.length; ++index) {
            const seat = seats[index].seat
            appendZone(cards, keys,
                       tableRoot.zoneState.zoneCardsForSeat(seat, "graveyard"))
            appendZone(cards, keys,
                       tableRoot.zoneState.zoneCardsForSeat(seat, "exile"))
            appendZone(cards, keys,
                       tableRoot.zoneState.zoneCardsForSeat(seat, "command"))
        }

        const signatureParts = []
        for (let index = 0; index < cards.length; ++index)
            signatureParts.push(cardKey(cards[index]))
        const signature = signatureParts.join("\u001e")
        if (signature === prioritizedSignature)
            return
        prioritizedSignature = signature
        prioritizingVisibleCards = true
        try {
            catalog.prioritizeCards(cards)
        } finally {
            prioritizingVisibleCards = false
        }
    }

    function inspectCard(card, sourceItem) {
        if (!card || !card.name)
            return
        inspectedCard = card
        inspectedSourceItem = sourceItem ? sourceItem : null
        const previewWidth = Theme.size(250)
        const previewHeight = Math.round(previewWidth * 88 / 63)
        const margin = Theme.size(12)
        if (sourceItem) {
            const right = sourceItem.mapToItem(
                              tableRoot, sourceItem.width, 0)
            const left = sourceItem.mapToItem(tableRoot, 0, 0)
            let x = right.x + margin
            if (x + previewWidth > tableRoot.width - margin)
                x = left.x - previewWidth - margin
            hoverPreviewX = Math.max(
                                margin,
                                Math.min(tableRoot.width
                                         - previewWidth - margin, x))
            hoverPreviewY = Math.max(
                                margin,
                                Math.min(tableRoot.height
                                         - previewHeight - margin, left.y))
        } else {
            hoverPreviewX = Math.max(
                                margin,
                                tableRoot.width - previewWidth - margin)
            hoverPreviewY = margin
        }
        hoverPreviewVisible = true
    }

    function hideCardPreview(sourceItem) {
        if (sourceItem && inspectedSourceItem
                && sourceItem !== inspectedSourceItem) {
            return
        }
        hoverPreviewVisible = false
        inspectedSourceItem = null
    }

    function reset() {
        prioritizedSignature = ""
        prioritizingVisibleCards = false
        inspectedCard = ({})
        inspectedSourceItem = null
        hoverPreviewVisible = false
        hoverPreviewX = 0
        hoverPreviewY = 0
    }
}
