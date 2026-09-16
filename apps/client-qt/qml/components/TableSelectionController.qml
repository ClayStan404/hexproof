// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick

QtObject {
    id: root

    required property var tableRoot

    property string selectedCardId: ""
    property int selectedOwnerSeat: -1
    property var selectedCard: ({})
    readonly property var selectedFaces: {
        if (!selectedCardId || !selectedCard.id)
            return []
        const catalog = tableRoot.cardCatalogModel
        // Metadata can arrive after a background-loading game has started.
        // Refresh only the active selection; cardFaces() is a cached lookup.
        if (catalog && typeof catalog.imageRevision !== "undefined"
                && catalog.imageRevision === -1)
            return []
        return tableRoot.presentation.availableCardFaces(selectedCard)
    }
    property var selectedCardIds: ({})
    property string interactionMode: ""
    property var interactionSourceIds: []

    function cardSelected(cardId) {
        return selectedCardIds[cardId] === true
    }

    function selectedCount() {
        return Object.keys(selectedCardIds).length
    }

    function pendingMove(cardId) {
        const moves = tableRoot.pendingCardMoves
                      ? tableRoot.pendingCardMoves : ({})
        return Object.prototype.hasOwnProperty.call(moves, cardId)
                ? moves[cardId] : null
    }

    function effectiveBattlefieldSeat(cardId) {
        const move = pendingMove(cardId)
        if (move) {
            if (move.toZone === "battlefield")
                return Number(move.toSeat)
            if (move.fromZone === "battlefield")
                return -1
        }
        return tableRoot.zoneState.visibleZoneSeatForCard(
                    cardId, "battlefield")
    }

    function interactionSourceValid(cardId) {
        const stackAllowed = interactionMode === "arrow"
        const move = pendingMove(cardId)
        if (move) {
            if (move.toZone === "battlefield")
                return true
            if (move.toZone === "stack")
                return stackAllowed
            if (move.fromZone === "battlefield" || move.fromZone === "stack")
                return false
        }
        return effectiveBattlefieldSeat(cardId) >= 0
                || (stackAllowed
                    && tableRoot.zoneState.cardInZone(cardId, "stack", -1))
    }

    function reconcileBattlefieldSelection() {
        const selectedIds = Object.keys(selectedCardIds)
        const retained = ({})
        for (let index = 0; index < selectedIds.length; ++index) {
            const cardId = selectedIds[index]
            if (effectiveBattlefieldSeat(cardId) >= 0)
                retained[cardId] = true
        }
        const retainedIds = Object.keys(retained)
        if (selectedIds.length > 0 && retainedIds.length === 0) {
            clearBattlefieldSelection()
        } else if (selectedIds.length > 0) {
            if (retainedIds.length !== selectedIds.length)
                selectedCardIds = retained
            const activeId = retained[selectedCardId] === true
                           ? selectedCardId
                           : retainedIds[retainedIds.length - 1]
            selectedCardId = activeId
            selectedOwnerSeat = effectiveBattlefieldSeat(activeId)
            selectedCard = tableRoot.zoneState.cardDataForId(activeId)
        }

        if (interactionSourceIds.length === 0)
            return
        const validSources = []
        for (let index = 0; index < interactionSourceIds.length; ++index) {
            if (interactionSourceValid(interactionSourceIds[index]))
                validSources.push(interactionSourceIds[index])
        }
        if (validSources.length === 0) {
            endRelationTarget()
        } else if (validSources.length !== interactionSourceIds.length) {
            interactionSourceIds = validSources
        }
    }

    function allCardIds() {
        const result = []
        for (let seatIndex = 0;
             seatIndex < tableRoot.authoritativeSeats.length; ++seatIndex) {
            const battlefield = tableRoot.zoneState.zoneCardsForSeat(
                                    tableRoot.authoritativeSeats[seatIndex].seat,
                                    "battlefield")
            for (let cardIndex = 0;
                 cardIndex < battlefield.length; ++cardIndex) {
                if (battlefield[cardIndex].id)
                    result.push(battlefield[cardIndex].id)
            }
        }
        return result
    }

    function selectCard(card, ownerSeat, additive) {
        if (!tableRoot.canAct || !card || !card.id)
            return
        const cardId = card.id
        if (interactionMode.length > 0) {
            const relationMode = interactionMode
            if (interactionSourceIds.indexOf(cardId) >= 0)
                return
            if (relationMode === "attack") {
                const targetSeat = tableRoot.zoneState.visibleZoneSeatForCard(
                                       cardId, "battlefield")
                if (targetSeat < 0 || targetSeat === tableRoot.roomSession.seatIndex)
                    return
            } else if (relationMode === "block") {
                const attack = tableRoot.gameTableModel.arrowForSource(cardId)
                const targetsLocalPlayer = attack.targetSeat
                                           === tableRoot.roomSession.seatIndex
                const targetsLocalPermanent = attack.targetCardId
                        && tableRoot.zoneState.visibleZoneSeatForCard(
                            attack.targetCardId, "battlefield")
                           === tableRoot.roomSession.seatIndex
                if (attack.kind !== "attack"
                        || (!targetsLocalPlayer
                            && !targetsLocalPermanent)) {
                    return
                }
            }
            if (relationMode === "arrow") {
                tableRoot.wsModel.setCombatArrows(
                            interactionSourceIds, "target", cardId, -1)
            } else if (relationMode === "attack") {
                tableRoot.rulesAssist.requestCombatDeclaration(
                            "attack", interactionSourceIds, cardId, -1)
            } else if (relationMode === "block") {
                tableRoot.rulesAssist.requestCombatDeclaration(
                            "block", interactionSourceIds, cardId, -1)
            } else if (relationMode === "attach") {
                if (tableRoot.attachmentUi
                        && tableRoot.attachmentUi.isAttachmentSource(cardId))
                    return
                const sourceId = interactionSourceIds.length > 0
                                 ? interactionSourceIds[0] : selectedCardId
                tableRoot.wsModel.setAttachment(sourceId, cardId)
            }
            if (relationMode !== "attack" && relationMode !== "block")
                clear()
            if (relationMode === "arrow")
                tableRoot.sharedZones.clearSelection()
            return
        }
        const immutableOwner = card.ownerSeat !== undefined
                             ? card.ownerSeat : ownerSeat
        if (ownerSeat !== tableRoot.roomSession.seatIndex
            && immutableOwner !== tableRoot.roomSession.seatIndex) {
            return
        }
        const next = additive ? Object.assign({}, selectedCardIds) : ({})
        if (additive && next[card.id] === true)
            delete next[card.id]
        else
            next[card.id] = true
        selectedCardIds = next
        if (next[card.id] !== true) {
            const remaining = Object.keys(next)
            if (remaining.length === 0) {
                clear()
                return
            }
            const fallback = tableRoot.zoneState.cardDataForId(
                               remaining[remaining.length - 1])
            selectedCardId = fallback.id ? fallback.id : remaining[0]
            selectedOwnerSeat = tableRoot.zoneState.visibleZoneSeatForCard(
                                  selectedCardId, "battlefield")
            selectedCard = fallback
            return
        }
        selectedCardId = cardId
        selectedOwnerSeat = ownerSeat
        selectedCard = card
    }

    function beginRelationTarget(kind) {
        const sources = Object.keys(selectedCardIds)
        beginRelationTargetForSources(kind, sources)
    }

    function beginRelationTargetForSources(kind, sources) {
        if (!sources || sources.length === 0)
            return
        interactionSourceIds = sources.slice()
        interactionMode = kind
    }

    function endRelationTarget() {
        interactionMode = ""
        interactionSourceIds = []
    }

    function clearBattlefieldSelection() {
        selectedCardId = ""
        selectedOwnerSeat = -1
        selectedCard = ({})
        selectedCardIds = ({})
    }

    function selectCardForMenu(card, ownerSeat) {
        if (cardSelected(card.id)) {
            selectedCardId = card.id
            selectedOwnerSeat = ownerSeat
            selectedCard = card
            return
        }
        selectCard(card, ownerSeat, false)
    }

    function clear() {
        clearBattlefieldSelection()
        endRelationTarget()
    }
}
