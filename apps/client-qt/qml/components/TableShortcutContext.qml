// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

pragma ComponentBehavior: Bound

import QtQuick

Item {
    id: root

    visible: false
    width: 0
    height: 0

    required property var tableRoot

    function blocked() {
        return tableRoot.sessionUi.counterShortcutBlocked()
    }

    function canEditSelectedCounter() {
        return tableRoot.canAct
                && tableRoot.selectedCounterSeat === tableRoot.roomSession.seatIndex
                && tableRoot.selectedCounterKey.length > 0
                && !blocked()
    }

    function canUseLibrary() {
        return tableRoot.canAct && tableRoot.ownSeatData.libraryCount > 0
                && !blocked()
    }

    function canUseGameAction() {
        return tableRoot.canAct && !blocked()
    }

    function canMulligan() {
        return tableRoot.canAct && tableRoot.authoritativeSeats.length > 0
                && !blocked()
    }

    function canToggleHand() {
        return tableRoot.canAct
                && (tableRoot.projectionSync.visibleOwnHandCount() > 0
                    || tableRoot.ownRevealedCards.length > 0)
                && !tableRoot.zoneState.handRevealTransitionPending()
                && !blocked()
    }

    function canConcede() {
        return !tableRoot.isPlaytest && tableRoot.canAct && !blocked()
    }

    function canAdvanceTurn() {
        return tableRoot.isActivePlayer && !blocked()
    }

    function selectedBattlefieldCount() {
        return tableRoot.selection.selectedCount()
    }

    function hasSelectedHandCard() {
        return !!tableRoot.selectedHandCard
                && !!tableRoot.selectedHandCard.id
    }

    function selectionDomain() {
        const hand = hasSelectedHandCard()
        const battlefield = selectedBattlefieldCount() > 0
        if (hand === battlefield)
            return ""
        return hand ? "hand" : "battlefield"
    }

    function canUseSelection() {
        return tableRoot.canAct && !blocked()
                && selectionDomain().length > 0
    }

    function canUseSingleBattlefieldSelection() {
        return tableRoot.canAct && !blocked()
                && selectionDomain() === "battlefield"
                && selectedBattlefieldCount() === 1
    }

    function canUseSingleBattlefieldCard() {
        return canUseSingleBattlefieldSelection()
                && tableRoot.cardMoveCommands.canControlSelectedBattlefield()
    }

    function canUseBattlefieldSources() {
        if (!tableRoot.canAct || blocked()
                || selectionDomain() !== "battlefield") {
            return false
        }
        const ids = Object.keys(tableRoot.selectedBattlefieldCardIds)
        for (let index = 0; index < ids.length; ++index) {
            if (tableRoot.gameTableModel.visibleZoneSeat(
                        ids[index], "battlefield")
                    !== tableRoot.roomSession.seatIndex) {
                return false
            }
        }
        return ids.length > 0
    }

    function selectedHasArrow(kinds) {
        const ids = Object.keys(tableRoot.selectedBattlefieldCardIds)
        for (let index = 0; index < ids.length; ++index) {
            const arrow = tableRoot.gameTableModel.arrowForSource(ids[index])
            if (kinds.indexOf(arrow.kind) >= 0)
                return true
        }
        return false
    }

    function hasIncomingAttacker() {
        const arrows = tableRoot.tableArrows ? tableRoot.tableArrows : []
        for (let index = 0; index < arrows.length; ++index) {
            if (arrows[index].kind !== "attack")
                continue
            if (arrows[index].targetSeat === tableRoot.roomSession.seatIndex)
                return true
            if (arrows[index].targetCardId
                    && tableRoot.gameTableModel.visibleZoneSeat(
                        arrows[index].targetCardId, "battlefield")
                       === tableRoot.roomSession.seatIndex) {
                return true
            }
        }
        return false
    }

    function canMoveSelection(destination) {
        if (!canUseSelection())
            return false
        const domain = selectionDomain()
        if (domain === "hand")
            return destination !== "hand"
        if (destination === "battlefield")
            return false
        if (selectedBattlefieldCount() === 1)
            return tableRoot.cardMoveCommands.canManageSelectedBattlefield()
        return destination !== "hand"
    }

    function moveSelection(destination, randomize) {
        if (!canMoveSelection(destination))
            return
        if (selectionDomain() === "hand") {
            if (destination === "library-top") {
                tableRoot.cardMoveCommands.moveSelectedHandToLibrary("top", -1)
            } else if (destination === "library-bottom") {
                tableRoot.cardMoveCommands.moveSelectedHandToLibrary("bottom", -1)
            } else {
                tableRoot.cardMoveCommands.moveSelectedHandCard(destination)
            }
            return
        }
        if (selectedBattlefieldCount() > 1) {
            const toZone = destination.indexOf("library-") === 0
                         ? "library" : destination
            const placement = destination === "library-top"
                            ? "top"
                            : (destination === "library-bottom"
                               ? "bottom" : "")
            tableRoot.cardMoveCommands.moveSelectedBattlefieldCards(
                        toZone, placement, randomize === true)
            return
        }
        if (destination === "library-top") {
            tableRoot.cardMoveCommands.moveSelectedBattlefieldToLibrary(
                        "top", -1)
        } else if (destination === "library-bottom") {
            tableRoot.cardMoveCommands.moveSelectedBattlefieldToLibrary(
                        "bottom", -1)
        } else {
            tableRoot.cardMoveCommands.moveSelectedBattlefieldToZone(destination)
        }
    }

    function toggleSelectedFaceDown() {
        if (!canUseSingleBattlefieldCard())
            return
        tableRoot.wsModel.setCardFaceDown(
                    tableRoot.selectedBattlefieldCard.id,
                    tableRoot.selectedBattlefieldCard.faceDown !== true)
        tableRoot.selection.clear()
    }

    function clearSelectedArrows(kinds) {
        if (!canUseBattlefieldSources() || !selectedHasArrow(kinds))
            return
        tableRoot.wsModel.clearCombatArrows(
                    Object.keys(tableRoot.selectedBattlefieldCardIds))
        tableRoot.selection.clear()
    }

    function adjustOwnLife(delta) {
        if (!canUseGameAction())
            return
        tableRoot.gameValues.setLife(
                    tableRoot.gameValues.displayedLife(
                        tableRoot.ownSeatData) + delta)
    }

    function adjustSelectedPlayerCounter(delta) {
        if (!canEditSelectedCounter())
            return
        const selected = tableRoot.sessionUi.selectedCounter()
        if (selected.counter) {
            tableRoot.gameValues.adjustCounter(
                        selected.player.seat, selected.counter, delta)
        }
    }

    function toggleSelectedPermanents() {
        if (!canUseBattlefieldSources())
            return
        const ids = Object.keys(tableRoot.selectedBattlefieldCardIds)
        for (let index = 0; index < ids.length; ++index) {
            const card = tableRoot.gameTableModel.cardData(ids[index])
            if (card && card.id)
                tableRoot.gameValues.toggleTapped(card)
        }
        tableRoot.selection.clear()
    }
}
