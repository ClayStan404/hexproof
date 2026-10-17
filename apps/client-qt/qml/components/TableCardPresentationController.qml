// SPDX-License-Identifier: GPL-3.0-or-later
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
    property bool previewSourceActive: false
    property bool previewHeld: false
    property real hoverPreviewWidth: Theme.size(250)
    property real hoverPreviewHeight: Math.round(hoverPreviewWidth * 88 / 63)
    readonly property CardFacePreviewController facePreview: CardFacePreviewController {
        catalogModel: root.tableRoot.cardCatalogModel
        card: root.inspectedCard
        sourceItem: root.inspectedSourceItem
        identityVisible: !!root.inspectedCard.name && root.inspectedCard.faceDown !== true
            && root.inspectedCard.visible !== false
        active: root.hoverPreviewVisible
        fallbackImageSource: active && hasIdentity ? root.tableCardImageSource(root.inspectedCard) : ""
    }
    readonly property Timer previewDeparture: Timer {
        interval: 350
        onTriggered: if (!root.previewSourceActive && !root.previewHeld) root.hideCardPreview()
    }
    readonly property Connections inspectionProjectionSync: Connections {
        target: root.tableRoot && root.tableRoot.gameTableModel ? root.tableRoot.gameTableModel : null
        ignoreUnknownSignals: true
        function onCardIndexRevisionChanged() { root.reconcileInspection() }
        function onSnapshotChanged() { root.reconcileInspection() }
    }
    onPreviewHeldChanged: {
        if (previewHeld) previewDeparture.stop()
        else if (!previewSourceActive && hoverPreviewVisible) previewDeparture.restart()
    }
    onHoverPreviewHeightChanged: if (hoverPreviewVisible) repositionPreview()
    onHoverPreviewWidthChanged: if (hoverPreviewVisible) repositionPreview()
    onInspectedSourceItemChanged: if (!inspectedSourceItem && hoverPreviewVisible) hideCardPreview()

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
        if (tableRoot.roomSession
                && tableRoot.roomSession.role === "spectator"
                && tableRoot.roomSession.spectatorsSeeHands === true) {
            for (let index = 0; index < seats.length; ++index) {
                appendZone(cards, keys, tableRoot.zoneState.zoneCardsForSeat(
                               seats[index].seat, "hand"))
            }
        }
        for (let index = 0; index < seats.length; ++index) {
            appendZone(cards, keys, tableRoot.zoneState.zoneCardsForSeat(
                           seats[index].seat, "battlefield"))
        }
        appendZone(cards, keys, tableRoot.stackCards)
        appendZone(cards, keys, tableRoot.revealedCards)
        for (let index = 0; index < seats.length; ++index) {
            appendVisibleCard(cards, keys, seats[index].libraryTopCard)
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
        previewSourceActive = true
        previewDeparture.stop()
        repositionPreview()
        hoverPreviewVisible = true
    }

    function repositionPreview() {
        const previewWidth = hoverPreviewWidth
        const previewHeight = hoverPreviewHeight
        const margin = Theme.size(12)
        const sourceItem = inspectedSourceItem
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
    }

    function hideCardPreview(sourceItem) {
        if (sourceItem && inspectedSourceItem
                && sourceItem !== inspectedSourceItem) {
            return
        }
        if (sourceItem && hoverPreviewVisible && facePreview.canSwitch) {
            previewSourceActive = false
            if (!previewHeld) previewDeparture.restart()
            return
        }
        previewDeparture.stop()
        previewSourceActive = false
        previewHeld = false
        hoverPreviewVisible = false
        inspectedSourceItem = null
        facePreview.resetFace()
    }

    function reconcileInspection() {
        const model = tableRoot.gameTableModel
        const id = inspectedCard.id
        if (!hoverPreviewVisible || !id || !model || typeof model.cardData !== "function") return
        let current = model.cardData(id)
        if ((!current || !current.id) && model.seats) {
            // Public library tops are seat metadata, outside the ordinary
            // zone-card index. Read only the current, explicitly revealed top.
            const seat = model.seats.find(entry => entry.libraryTopRevealed === true
                && entry.libraryTopCard && entry.libraryTopCard.id === id)
            if (seat) current = seat.libraryTopCard
        }
        if (!current || !current.id || !current.name || current.faceDown === true
                || current.visibleIdentity === false || current.visible === false) {
            hideCardPreview()
            inspectedCard = ({})
            return
        }
        if (JSON.stringify(current) !== JSON.stringify(inspectedCard)) inspectedCard = current
    }

    function reset() {
        previewDeparture.stop()
        previewSourceActive = false
        previewHeld = false
        facePreview.resetFace()
        prioritizedSignature = ""
        prioritizingVisibleCards = false
        inspectedCard = ({})
        inspectedSourceItem = null
        hoverPreviewVisible = false
        hoverPreviewX = 0
        hoverPreviewY = 0
    }
}
