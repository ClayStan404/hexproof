// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

pragma ComponentBehavior: Bound

import QtQuick

QtObject {
    id: root

    required property var tableRoot
    property var pendingCardFaceAction: ({})
    readonly property var battlefieldLayout: TableBattlefieldLayoutController {
        tableRoot: root.tableRoot
    }

    // Public compatibility facade. Callers keep one card-move surface while
    // the layout policy evolves independently from command coordination.
    function catalogTypeLine(cardName, card) {
        return battlefieldLayout.catalogTypeLine(cardName, card)
    }

    function resolvedTypeLine(card) {
        return battlefieldLayout.resolvedTypeLine(card)
    }

    function battlefieldCategory(card) {
        return battlefieldLayout.battlefieldCategory(card)
    }

    function categoryOrder(category) {
        return battlefieldLayout.categoryOrder(category)
    }

    function battlefieldColumns(seatIndex) {
        return battlefieldLayout.battlefieldColumns(seatIndex)
    }

    function battlefieldSlot(seatIndex, category, index) {
        return battlefieldLayout.battlefieldSlot(
                    seatIndex, category, index)
    }

    function battlefieldCardId(card) {
        return battlefieldLayout.battlefieldCardId(card)
    }

    function battlefieldCardHasCounters(card) {
        return battlefieldLayout.battlefieldCardHasCounters(card)
    }

    function battlefieldCardHasRelation(card) {
        return battlefieldLayout.battlefieldCardHasRelation(card)
    }

    function battlefieldCardCanStack(card, category, seatIndex) {
        return battlefieldLayout.battlefieldCardCanStack(
                    card, category, seatIndex)
    }

    function battlefieldCardNeedsPriority(card, seatIndex) {
        return battlefieldLayout.battlefieldCardNeedsPriority(card, seatIndex)
    }

    function battlefieldStackKey(card, category, seatIndex) {
        return battlefieldLayout.battlefieldStackKey(
                    card, category, seatIndex)
    }

    function battlefieldCardPosition(card) {
        return battlefieldLayout.battlefieldCardPosition(card)
    }

    function stackedBattlefieldPosition(seatIndex, category, base,
                                        stackIndex) {
        return battlefieldLayout.stackedBattlefieldPosition(
                    seatIndex, category, base, stackIndex)
    }

    function smartBattlefieldPosition(seatIndex, card, movingCardId) {
        return battlefieldLayout.smartBattlefieldPosition(
                    seatIndex, card, movingCardId)
    }

    function smartBattlefieldAnchor(seatIndex, cards) {
        return battlefieldLayout.smartBattlefieldAnchor(seatIndex, cards)
    }

    function arrangeOwnBattlefield() {
        return battlefieldLayout.arrangeOwnBattlefield()
    }

    function nonOverlappingBattlefieldPosition(seatIndex, requested,
                                               movingCardId) {
        return battlefieldLayout.nonOverlappingBattlefieldPosition(
                    seatIndex, requested, movingCardId)
    }

    function batchBattlefieldPosition(anchor, index, count) {
        return battlefieldLayout.batchBattlefieldPosition(
                    anchor, index, count)
    }

    function canManageSelectedBattlefield() {
        return tableRoot.canAct && tableRoot.selection.selectedCount() === 1
                && tableRoot.selectedBattlefieldCardId.length > 0
                && (tableRoot.selectedBattlefieldOwnerSeat
                    === tableRoot.roomSession.seatIndex
                    || tableRoot.selectedBattlefieldCard.ownerSeat
                       === tableRoot.roomSession.seatIndex)
    }

    function canControlSelectedBattlefield() {
        return tableRoot.canAct && tableRoot.selection.selectedCount() === 1
                && tableRoot.selectedBattlefieldCardId.length > 0
                && tableRoot.selectedBattlefieldOwnerSeat
                   === tableRoot.roomSession.seatIndex
    }

    function moveSelectedBattlefieldCards(toZone, libraryPlacement,
                                          randomize) {
        const cardIds = Object.keys(tableRoot.selectedBattlefieldCardIds)
        if (!tableRoot.canAct || cardIds.length < 2)
            return
        tableRoot.wsModel.moveCards(
                    cardIds, "battlefield", toZone,
                    libraryPlacement ? libraryPlacement : "",
                    randomize === true)
        tableRoot.selection.clear()
    }

    function moveSelectedBattlefieldToLibrary(placement, index) {
        if (!canManageSelectedBattlefield())
            return
        tableRoot.optimisticCommands.beginPendingCardMove(
                    tableRoot.selectedBattlefieldCardId,
                    tableRoot.selectedBattlefieldCard,
                    "battlefield", tableRoot.selectedBattlefieldOwnerSeat,
                    "library", tableRoot.selectedBattlefieldCard.ownerSeat)
        tableRoot.wsModel.moveCard(
                    tableRoot.selectedBattlefieldCardId,
                    "battlefield", "library", {}, -1, placement, index)
        tableRoot.selection.clear()
    }

    function moveSelectedBattlefieldToZone(toZone) {
        if (!canManageSelectedBattlefield())
            return
        tableRoot.optimisticCommands.beginPendingCardMove(
                    tableRoot.selectedBattlefieldCardId,
                    tableRoot.selectedBattlefieldCard,
                    "battlefield", tableRoot.selectedBattlefieldOwnerSeat,
                    toZone, tableRoot.selectedBattlefieldCard.ownerSeat)
        tableRoot.wsModel.moveCard(
                    tableRoot.selectedBattlefieldCardId,
                    "battlefield", toZone, {})
        tableRoot.selection.clear()
    }

    function moveSelectedHandCard(toZone, faceDown) {
        const card = tableRoot.selectedHandCard
        if (!tableRoot.canAct || !card || !card.id)
            return
        if (toZone === "battlefield") {
            const placementCard = faceDown === true
                                  ? Object.assign({}, card, {"faceDown": true})
                                  : card
            const position = smartBattlefieldPosition(
                                 tableRoot.roomSession.seatIndex,
                                 placementCard, card.id)
            moveCardToBattlefield(
                        card.id, "hand", tableRoot.roomSession.seatIndex,
                        position.x, position.y, undefined,
                        faceDown === true)
        } else {
            tableRoot.optimisticCommands.beginPendingCardMove(
                        card.id, card, "hand", tableRoot.roomSession.seatIndex,
                        toZone, card.ownerSeat !== undefined
                        ? card.ownerSeat : tableRoot.roomSession.seatIndex)
            moveCardToShared(card.id, "hand", toZone)
        }
        tableRoot.selectedHandCard = ({})
    }

    function moveSelectedHandToLibrary(placement, index) {
        const card = tableRoot.selectedHandCard
        if (!tableRoot.canAct || !card || !card.id)
            return
        tableRoot.optimisticCommands.beginPendingCardMove(
                    card.id, card, "hand", tableRoot.roomSession.seatIndex,
                    "library", tableRoot.roomSession.seatIndex)
        tableRoot.wsModel.moveCard(
                    card.id, "hand", "library", {}, -1, placement, index)
        tableRoot.selectedHandCard = ({})
    }

    function canMoveSharedSource(source) {
        return source && source.cardId
                && tableRoot.canAct
                && (!source.modelData
                    || source.modelData.pending !== true)
                && (source.ownerSeat === tableRoot.roomSession.seatIndex
                    || (source.zoneName === "battlefield"
                        && source.zoneSeat === tableRoot.roomSession.seatIndex))
    }

    function canMoveToBattlefield(source) {
        if (!source)
            return false
        return source.zoneName === "hand"
                || source.zoneName === "library"
                || source.zoneName === "battlefield"
                || source.zoneName === "graveyard"
                || source.zoneName === "exile"
                || source.zoneName === "command"
                || source.zoneName === "stack"
                || source.zoneName === "reveal"
    }

    function canMoveToHand(source) {
        if (!canMoveSharedSource(source))
            return false
        return source.zoneName === "stack"
                || source.zoneName === "reveal"
                || source.zoneName === "battlefield"
                || source.zoneName === "library"
                || source.zoneName === "graveyard"
                || source.zoneName === "exile"
                || source.zoneName === "command"
    }

    function canDragBattlefieldCard(source) {
        return canMoveSharedSource(source)
    }

    function moveDroppedCardToBattlefield(source, targetSeat,
                                          normalizedX, normalizedY) {
        if (!canMoveSharedSource(source)
            || !canMoveToBattlefield(source)) {
            return false
        }

        // Public-zone pile bindings change as soon as the optimistic source
        // card is hidden. Snapshot every source field before that happens.
        const cardId = source.cardId
        const fromZone = source.zoneName
        const fromSeat = source.zoneSeat !== undefined
                         ? source.zoneSeat : -1
        const card = source.modelData ? source.modelData : ({})
        const adjustedPosition = fromZone === "battlefield"
                                 ? nonOverlappingBattlefieldPosition(
                                       targetSeat,
                                       {"x": normalizedX, "y": normalizedY},
                                       cardId)
                                 : smartBattlefieldPosition(
                                       targetSeat, card, cardId)
        moveCardToBattlefield(
                    cardId, fromZone, targetSeat,
                    adjustedPosition.x, adjustedPosition.y, fromSeat)
        return true
    }

    function beginBattlefieldPreview(source, targetSeat,
                                     normalizedX, normalizedY) {
        const card = source && source.modelData ? source.modelData : ({})
        beginBattlefieldPreviewForCard(
                    source.cardId, source.zoneName,
                    source.zoneSeat !== undefined ? source.zoneSeat : -1,
                    card, targetSeat, normalizedX, normalizedY)
    }

    function beginBattlefieldPreviewForCard(cardId, fromZone, fromSeat, card,
                                            targetSeat,
                                            normalizedX, normalizedY) {
        tableRoot.optimisticCommandModel.setBattlefieldMove({
            "cardId": cardId,
            "fromZone": fromZone,
            "name": card.name ? card.name : "",
            "setCode": card.setCode ? card.setCode : "",
            "collectorNumber": card.collectorNumber
                               ? card.collectorNumber : "",
            "faceName": card.faceName ? card.faceName : "",
            "faceDown": fromZone === "library" && !card.name,
            "pending": true,
            "tapped": card.tapped === true,
            "toSeat": targetSeat,
            "x": normalizedX,
            "y": normalizedY
        })
        tableRoot.optimisticCommands.beginPendingCardMoves([{
            "cardId": cardId,
            "card": card,
            "fromZone": fromZone,
            "fromSeat": fromSeat,
            "toZone": "battlefield",
            "toSeat": targetSeat,
            "x": normalizedX,
            "y": normalizedY,
            "tapped": card.tapped === true
        }])
    }

    function pendingBattlefieldMoveCommitted() {
        const pendingMove = tableRoot.pendingBattlefieldMove
        if (!pendingMove.cardId)
            return false
        const cards = tableRoot.zoneState.zoneCardsForSeat(
                          pendingMove.toSeat, "battlefield")
        for (let index = 0; index < cards.length; ++index) {
            const card = cards[index]
            const position = card.position ? card.position : ({})
            if ((card.id === pendingMove.cardId
                 || pendingMove.fromZone === "library")
                && position.x !== undefined
                && position.y !== undefined
                && Math.abs(position.x - pendingMove.x) < 0.001
                && Math.abs(position.y - pendingMove.y) < 0.001) {
                return true
            }
        }
        return false
    }

    function clearPendingBattlefieldMove() {
        tableRoot.optimisticCommandModel.clearBattlefieldMove()
    }

    function rejectDrop(dropArea, drop) {
        dropArea.cardSource = null
        drop.accepted = false
        if (tableRoot.appWindow
                && typeof tableRoot.appWindow.showBanner === "function") {
            tableRoot.appWindow.showBanner(
                qsTr("That card cannot move to this zone."))
        }
    }

    function finishLibraryDrop(dropArea, drop) {
        const source = drop.source ? drop.source : dropArea.cardSource
        if (!canMoveSharedSource(source)
            || source.zoneName === "library") {
            rejectDrop(dropArea, drop)
            return
        }
        const cardId = source.cardId
        const card = source.modelData
                     ? Object.assign({}, source.modelData) : ({})
        const fromZone = source.zoneName
        const sourceZoneSeat = source.zoneSeat !== undefined
                               ? source.zoneSeat : -1
        const fromSeat = fromZone === "graveyard"
                         || fromZone === "exile"
                         ? sourceZoneSeat : -1
        const ownerSeat = source.ownerSeat !== undefined
                          ? source.ownerSeat : tableRoot.roomSession.seatIndex
        tableRoot.optimisticCommands.beginPendingCardMove(
                    cardId, card, fromZone, sourceZoneSeat,
                    "library", ownerSeat)
        tableRoot.wsModel.moveCard(
                    cardId, fromZone, "library", {},
                    -1, "top", -1, fromSeat)
        dropArea.cardSource = null
        drop.acceptProposedAction()
    }

    function finishStackDrop(dropArea, drop) {
        const source = drop.source ? drop.source : dropArea.cardSource
        if (!canMoveSharedSource(source)
            || source.zoneName === "stack"
            || source.zoneName === "reveal"
            || source.zoneName === "library") {
            rejectDrop(dropArea, drop)
            return
        }
        moveCardToShared(source.cardId, source.zoneName, "stack")
        dropArea.cardSource = null
        drop.acceptProposedAction()
    }

    function finishPublicZoneDrop(dropArea, drop, toZone, toSeat) {
        const source = drop.source ? drop.source : dropArea.cardSource
        const requestedSeat = toSeat !== undefined ? toSeat : -1
        const ownerSeat = source && source.ownerSeat !== undefined
                          ? source.ownerSeat : tableRoot.roomSession.seatIndex
        const destinationSeat = toZone === "graveyard"
                                || toZone === "exile"
                                || toZone === "command"
                                ? ownerSeat : requestedSeat
        if (!canMoveSharedSource(source)
            || (source.zoneName === toZone
                && source.zoneSeat === destinationSeat)) {
            rejectDrop(dropArea, drop)
            return
        }
        const cardId = source.cardId
        const card = source.modelData
                     ? Object.assign({}, source.modelData) : ({})
        const fromZone = source.zoneName
        const sourceZoneSeat = source.zoneSeat !== undefined
                               ? source.zoneSeat : -1
        const publicFromSeat = fromZone === "graveyard"
                               || fromZone === "exile"
                               ? sourceZoneSeat : -1
        const remotePublicSource = publicFromSeat >= 0
                                   && publicFromSeat
                                      !== tableRoot.roomSession.seatIndex
        if (!remotePublicSource) {
            tableRoot.optimisticCommands.beginPendingCardMove(
                        cardId, card, fromZone, sourceZoneSeat,
                        toZone, destinationSeat >= 0
                        ? destinationSeat : ownerSeat)
        }
        // Graveyard, exile, and command-zone destinations follow immutable
        // ownership even when the card is controlled on another battlefield.
        const wireTargetSeat = toZone === "graveyard" || toZone === "exile"
                               ? destinationSeat : -1
        tableRoot.wsModel.moveCard(
                    cardId, fromZone, toZone, {},
                    wireTargetSeat, "", -1, publicFromSeat)
        dropArea.cardSource = null
        drop.acceptProposedAction()
    }

    function movePublicZoneCard(cardId, fromZone, fromSeat,
                                toZone, toSeat) {
        if (!tableRoot.canAct || !cardId)
            return
        const card = tableRoot.zoneState.cardDataForId(cardId)
        if (toZone === "battlefield") {
            const position = smartBattlefieldPosition(
                                 tableRoot.roomSession.seatIndex, card, cardId)
            moveCardToBattlefield(
                        cardId, fromZone, tableRoot.roomSession.seatIndex,
                        position.x, position.y, fromSeat)
        } else {
            const destinationSeat = toZone === "graveyard"
                                    || toZone === "exile"
                                    ? (card.ownerSeat !== undefined
                                       ? card.ownerSeat : fromSeat)
                                    : toSeat
            if (fromSeat === tableRoot.roomSession.seatIndex) {
                tableRoot.optimisticCommands.beginPendingCardMove(
                            cardId, card, fromZone, fromSeat,
                            toZone, destinationSeat)
            }
            tableRoot.wsModel.moveCard(
                        cardId, fromZone, toZone, {},
                        destinationSeat, "", -1, fromSeat)
        }
    }

    function movePublicZoneCards(cardIds, fromZone, fromSeat,
                                 toZone, toSeat) {
        const ids = cardIds ? cardIds.slice() : []
        if (!tableRoot.canAct || ids.length < 2
                || (fromZone !== "graveyard" && fromZone !== "exile")
                || fromSeat < 0) {
            return
        }
        const sourceCards = []
        for (let index = 0; index < ids.length; ++index)
            sourceCards.push(tableRoot.zoneState.cardDataForId(ids[index]))
        const anchor = toZone === "battlefield"
                       ? smartBattlefieldAnchor(toSeat, sourceCards)
                       : ({})
        const pendingMoves = []
        for (let index = 0; index < ids.length; ++index) {
            const card = tableRoot.zoneState.cardDataForId(ids[index])
            let destinationSeat = toSeat
            if (toZone === "hand" || toZone === "library"
                    || toZone === "graveyard" || toZone === "exile") {
                destinationSeat = card.ownerSeat !== undefined
                                  ? card.ownerSeat
                                  : tableRoot.roomSession.seatIndex
            }
            const position = toZone === "battlefield"
                             ? batchBattlefieldPosition(
                                   anchor, index, ids.length) : ({})
            pendingMoves.push({
                "cardId": ids[index],
                "card": card,
                "fromZone": fromZone,
                "fromSeat": fromSeat,
                "toZone": toZone,
                "toSeat": destinationSeat,
                "x": position.x !== undefined ? position.x : 0,
                "y": position.y !== undefined ? position.y : 0
            })
        }
        if (fromSeat === tableRoot.roomSession.seatIndex)
            tableRoot.optimisticCommands.beginPendingCardMoves(pendingMoves)
        const wireTargetSeat = toZone === "exile" ? -1 : toSeat
        tableRoot.wsModel.movePublicCards(
                    ids, fromZone, fromSeat, toZone, wireTargetSeat,
                    toZone === "battlefield" ? anchor : ({}))
    }

    function moveCardToBattlefield(cardId, fromZone, targetSeat,
                                   normalizedX, normalizedY, fromSeat,
                                   faceDown) {
        if (!tableRoot.canAct || !cardId)
            return
        const resolvedFromSeat = fromSeat !== undefined
                                 ? fromSeat
                                 : tableRoot.zoneState.visibleZoneSeatForCard(
                                       cardId, fromZone)
        const card = tableRoot.zoneState.cardDataForId(cardId)
        const faces = tableRoot.presentation.availableCardFaces(card)
        if (fromZone !== "battlefield" && faces.length > 1
                && faceDown !== true) {
            pendingCardFaceAction = {
                "type": "move",
                "cardId": cardId,
                "fromZone": fromZone,
                "targetSeat": targetSeat,
                "normalizedX": normalizedX,
                "normalizedY": normalizedY,
                "fromSeat": resolvedFromSeat,
                "faceDown": false
            }
            tableRoot.cardFacePicker.showFor(card, faces)
            return
        }
        commitCardToBattlefield(
                    cardId, fromZone, targetSeat,
                    normalizedX, normalizedY, resolvedFromSeat,
                    "", faceDown === true)
    }

    function commitCardToBattlefield(cardId, fromZone, targetSeat,
                                     normalizedX, normalizedY, fromSeat,
                                     faceName, faceDown) {
        const card = tableRoot.zoneState.cardDataForId(cardId)
        const previewCard = Object.assign({}, card, {
            "faceName": fromZone === "battlefield"
                        && card.faceName ? card.faceName : faceName,
            "faceDown": faceDown === true
        })
        const publicFromSeat = fromZone === "graveyard"
                               || fromZone === "exile"
                               ? fromSeat : -1
        if (publicFromSeat < 0
                || publicFromSeat === tableRoot.roomSession.seatIndex) {
            beginBattlefieldPreviewForCard(
                        cardId, fromZone, fromSeat, previewCard, targetSeat,
                        normalizedX, normalizedY)
        }
        tableRoot.wsModel.moveCard(
                    cardId, fromZone, "battlefield", {
                        "x": Math.max(0, Math.min(1, normalizedX)),
                        "y": Math.max(0, Math.min(1, normalizedY))
                    }, targetSeat, "", -1, publicFromSeat,
                    faceName, faceDown === true)
        tableRoot.selectedSharedCard = ({})
        tableRoot.selectedSharedZone = ""
    }

    function requestBattlefieldFaceSelection() {
        if (!tableRoot.selectedBattlefieldCard.id
            || tableRoot.selectedBattlefieldFaces.length < 2) {
            return
        }
        pendingCardFaceAction = {
            "type": "set",
            "cardId": tableRoot.selectedBattlefieldCard.id
        }
        tableRoot.cardFacePicker.showFor(
                    tableRoot.selectedBattlefieldCard,
                    tableRoot.selectedBattlefieldFaces)
    }

    function finishCardFaceSelection(faceName) {
        const action = pendingCardFaceAction
        pendingCardFaceAction = ({})
        if (action.type === "move") {
            const card = tableRoot.zoneState.cardDataForId(action.cardId)
            const selectedFaceCard = Object.assign(
                                       {}, card, {"faceName": faceName})
            const position = smartBattlefieldPosition(
                                 action.targetSeat, selectedFaceCard,
                                 action.cardId)
            commitCardToBattlefield(
                        action.cardId, action.fromZone, action.targetSeat,
                        position.x, position.y,
                        action.fromSeat, faceName, action.faceDown === true)
        } else if (action.type === "set") {
            tableRoot.wsModel.setCardFace(action.cardId, faceName)
        }
    }

    function moveCardToShared(cardId, fromZone, toZone) {
        if (!tableRoot.canAct || !cardId)
            return
        const card = tableRoot.zoneState.cardDataForId(cardId)
        const fromSeat = tableRoot.zoneState.visibleZoneSeatForCard(cardId, fromZone)
        let destinationSeat = -1
        if (toZone === "hand" || toZone === "graveyard"
            || toZone === "exile" || toZone === "library") {
            destinationSeat = card.ownerSeat !== undefined
                              ? card.ownerSeat : tableRoot.roomSession.seatIndex
        }
        tableRoot.optimisticCommands.beginPendingCardMove(
                    cardId, card, fromZone, fromSeat,
                    toZone, destinationSeat)
        const publicFromSeat = fromZone === "graveyard"
                               || fromZone === "exile"
                               ? fromSeat : -1
        // Hidden destinations are always inferred from the immutable owner by
        // the server. Only public player zones may carry an explicit target
        // seat on the wire.
        const targetSeat = toZone === "graveyard" || toZone === "exile"
                           ? destinationSeat : -1
        tableRoot.wsModel.moveCard(
                    cardId, fromZone, toZone, {},
                    targetSeat, "", -1, publicFromSeat)
        tableRoot.selectedSharedCard = ({})
        tableRoot.selectedSharedZone = ""
    }

    function moveSelectedSharedCard(toZone) {
        if (!tableRoot.selectedSharedOwned
            || !tableRoot.selectedSharedCard.id) {
            return
        }
        if (toZone === "battlefield") {
            const position = smartBattlefieldPosition(
                                 tableRoot.roomSession.seatIndex,
                                 tableRoot.selectedSharedCard,
                                 tableRoot.selectedSharedCard.id)
            moveCardToBattlefield(
                        tableRoot.selectedSharedCard.id,
                        tableRoot.selectedSharedZone,
                        tableRoot.roomSession.seatIndex,
                        position.x, position.y)
        } else {
            moveCardToShared(
                        tableRoot.selectedSharedCard.id,
                        tableRoot.selectedSharedZone, toZone)
        }
        tableRoot.selectedSharedCard = ({})
        tableRoot.selectedSharedZone = ""
    }
}
