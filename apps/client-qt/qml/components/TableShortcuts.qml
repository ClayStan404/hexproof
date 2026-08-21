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
    required property var drawCardsEditor
    required property var libraryTopCountEditor
    required property var tokenPicker
    required property var concedeConfirmation
    required property var shuffleConfirmation
    required property var mulliganConfirmation
    required property var shortcutHelp

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

    Shortcut {
        sequences: ["F1", "?"]
        context: Qt.WindowShortcut
        enabled: !root.tableRoot.sessionUi.counterShortcutBlocked()
                 || root.shortcutHelp.opened
        onActivated: {
            if (root.shortcutHelp.opened)
                root.shortcutHelp.close()
            else
                root.shortcutHelp.open()
        }
    }

    Shortcut {
        sequence: "Ctrl+Right"
        context: Qt.WindowShortcut
        enabled: root.canAdvanceTurn()
        onActivated: root.tableRoot.rulesAssist.requestAdvancePhase()
    }

    Shortcut {
        sequence: "Ctrl+Return"
        context: Qt.WindowShortcut
        enabled: root.canAdvanceTurn()
        onActivated: root.tableRoot.rulesAssist.requestAdvanceTurn()
    }

    Shortcut {
        sequence: "Ctrl+,"
        context: Qt.WindowShortcut
        enabled: !root.blocked()
        onActivated: root.tableRoot.sessionUi.openTableSettings()
    }

    Shortcut {
        sequence: "Ctrl+G"
        context: Qt.WindowShortcut
        enabled: !root.blocked()
        onActivated: root.tableRoot.sessionUi.setGameLogRailVisible(
                         !root.tableRoot.showGameLogRail)
    }

    Shortcut {
        sequence: "Ctrl+Shift+V"
        context: Qt.WindowShortcut
        enabled: !root.blocked()
        onActivated: root.tableRoot.sessionUi.setSharedColumnVisible(
                         !root.tableRoot.showSharedColumn)
    }

    Shortcut {
        sequence: "I"
        context: Qt.WindowShortcut
        enabled: root.canEditSelectedCounter()
        onActivated: root.tableRoot.sessionUi.openSelectedCounterLabelEditor()
    }

    Shortcut {
        sequence: "S"
        context: Qt.WindowShortcut
        enabled: root.canEditSelectedCounter()
        onActivated: root.tableRoot.sessionUi.openSelectedCounterValueEditor()
    }

    Shortcut {
        sequence: "["
        context: Qt.WindowShortcut
        enabled: root.canEditSelectedCounter()
        onActivated: root.adjustSelectedPlayerCounter(-1)
    }

    Shortcut {
        sequence: "]"
        context: Qt.WindowShortcut
        enabled: root.canEditSelectedCounter()
        onActivated: root.adjustSelectedPlayerCounter(1)
    }

    Shortcut {
        sequence: "Ctrl+D"
        context: Qt.WindowShortcut
        enabled: root.canUseLibrary()
        onActivated: root.drawCardsEditor.showFor(2)
    }

    Shortcut {
        sequence: "Ctrl+Alt+D"
        context: Qt.WindowShortcut
        enabled: root.canUseLibrary()
        onActivated: root.tableRoot.wsModel.drawCards(1)
    }

    Shortcut {
        sequence: "Ctrl+F"
        context: Qt.WindowShortcut
        enabled: root.canUseLibrary()
        onActivated: root.tableRoot.wsModel.dumpLibrary(
                         root.tableRoot.roomSession.seatIndex)
    }

    Shortcut {
        sequence: "Ctrl+L"
        context: Qt.WindowShortcut
        enabled: root.canUseLibrary()
        onActivated: root.libraryTopCountEditor.showForLibrary(
                         root.tableRoot.roomSession.seatIndex,
                         root.tableRoot.ownSeatData.libraryCount,
                         Math.min(5, root.tableRoot.ownSeatData.libraryCount))
    }

    Shortcut {
        sequence: "Ctrl+Shift+L"
        context: Qt.WindowShortcut
        enabled: root.canUseLibrary()
        onActivated: root.tableRoot.wsModel.dumpLibrary(
                         root.tableRoot.roomSession.seatIndex, 1)
    }

    Shortcut {
        sequence: "Ctrl+B"
        context: Qt.WindowShortcut
        enabled: root.canUseGameAction()
                 && root.tableRoot.ownSeatData.sideboardCount > 0
        onActivated: root.tableRoot.publicZoneBrowser.showZone(
                         root.tableRoot.ownSeatData.displayName,
                         root.tableRoot.roomSession.seatIndex, "sideboard")
    }

    Shortcut {
        sequence: "Ctrl+Shift+G"
        context: Qt.WindowShortcut
        enabled: root.canUseLibrary()
        onActivated:
            root.tableRoot.sessionUi.showLibraryMoveCardsEditor("graveyard")
    }

    Shortcut {
        sequence: "Ctrl+Shift+E"
        context: Qt.WindowShortcut
        enabled: root.canUseLibrary()
        onActivated: root.tableRoot.sessionUi.showLibraryMoveCardsEditor("exile")
    }

    Shortcut {
        sequence: "Ctrl+Shift+S"
        context: Qt.WindowShortcut
        enabled: root.canUseGameAction()
        onActivated: root.shuffleConfirmation.open()
    }

    Shortcut {
        sequence: "Ctrl+U"
        context: Qt.WindowShortcut
        enabled: root.canUseGameAction()
                 && root.tableRoot.gameValues.hasTappedOwnPermanent()
        onActivated: root.tableRoot.gameValues.untapOwnBattlefield()
    }

    Shortcut {
        sequence: "Ctrl+Shift+A"
        context: Qt.WindowShortcut
        enabled: root.canUseGameAction()
                 && root.tableRoot.zoneState.zoneCardCount(
                     root.tableRoot.roomSession.seatIndex,
                     "battlefield") > 0
        onActivated: root.tableRoot.cardMoveCommands.arrangeOwnBattlefield()
    }

    Shortcut {
        sequence: "Ctrl+T"
        context: Qt.WindowShortcut
        enabled: root.canUseGameAction()
        onActivated: root.tokenPicker.open()
    }

    Shortcut {
        sequence: "Ctrl+M"
        context: Qt.WindowShortcut
        enabled: root.canMulligan()
        onActivated: root.mulliganConfirmation.open()
    }

    Shortcut {
        sequence: "Ctrl+H"
        context: Qt.WindowShortcut
        enabled: root.canToggleHand()
        onActivated: root.tableRoot.cardActions.toggleHandReveal()
    }

    Shortcut {
        sequence: "Ctrl+Alt+X"
        context: Qt.WindowShortcut
        enabled: root.canUseGameAction()
                 && root.tableRoot.projectionSync.visibleOwnHandCount() > 0
        onActivated: root.tableRoot.wsModel.discardHand(false)
    }

    Shortcut {
        sequence: "Ctrl+Shift+X"
        context: Qt.WindowShortcut
        enabled: root.canUseGameAction()
                 && root.tableRoot.projectionSync.visibleOwnHandCount() > 0
        onActivated: root.tableRoot.discardHandConfirmation.open()
    }

    Shortcut {
        sequence: "Ctrl+R"
        context: Qt.WindowShortcut
        enabled: root.canUseGameAction()
        onActivated: root.tableRoot.diceRollPopup.showFor(20, 1)
    }

    Shortcut {
        sequence: "Ctrl+Shift+C"
        context: Qt.WindowShortcut
        enabled: root.canUseGameAction()
        onActivated: root.tableRoot.wsModel.flipCoin()
    }

    Shortcut {
        sequence: "Ctrl+Alt+P"
        context: Qt.WindowShortcut
        enabled: root.canUseGameAction()
        onActivated: root.tableRoot.wsModel.randomSelectPlayer()
    }

    Shortcut {
        sequence: "Ctrl+Alt+R"
        context: Qt.WindowShortcut
        enabled: root.canUseGameAction()
                 && root.tableRoot.selection.allCardIds().length > 0
        onActivated: {
            const selected = Object.keys(
                               root.tableRoot.selectedBattlefieldCardIds)
            root.tableRoot.wsModel.randomSelectCards(
                        selected.length > 1
                        ? selected : root.tableRoot.selection.allCardIds())
            root.tableRoot.selection.clear()
        }
    }

    Shortcut {
        sequence: "Ctrl+Shift+D"
        context: Qt.WindowShortcut
        enabled: root.canUseGameAction() && !root.tableRoot.isPlaytest
        onActivated: root.tableRoot.drawConfirmation.open()
    }

    Shortcut {
        sequence: "Ctrl+Shift+R"
        context: Qt.WindowShortcut
        enabled: root.canUseGameAction()
                 && root.tableRoot.roomSession.host
        onActivated: root.tableRoot.restartConfirmation.open()
    }

    Shortcut {
        sequence: "Ctrl+Shift+H"
        context: Qt.WindowShortcut
        enabled: root.canUseGameAction()
                 && root.tableRoot.roomSession.seatIndex >= 0
        onActivated: root.tableRoot.lifeEditor.showFor(
                         root.tableRoot.ownSeatData.displayName,
                         root.tableRoot.gameValues.displayedLife(
                             root.tableRoot.ownSeatData))
    }

    Shortcut {
        sequence: "Alt+-"
        context: Qt.WindowShortcut
        enabled: root.canUseGameAction()
        onActivated: root.adjustOwnLife(-1)
    }

    Shortcut {
        sequence: "Alt+="
        context: Qt.WindowShortcut
        enabled: root.canUseGameAction()
        onActivated: root.adjustOwnLife(1)
    }

    Shortcut {
        sequence: "Ctrl+K"
        context: Qt.WindowShortcut
        enabled: !root.blocked() && root.tableRoot.isCommanderFormat
        onActivated: root.tableRoot.commanderDamagePopup.open()
    }

    Shortcut {
        sequence: "Ctrl+Shift+Q"
        context: Qt.WindowShortcut
        enabled: root.canConcede()
        onActivated: root.concedeConfirmation.open()
    }

    Shortcut {
        sequence: "Ctrl+Shift+W"
        context: Qt.WindowShortcut
        enabled: !root.blocked()
        onActivated: root.tableRoot.leaveRoomConfirmation.open()
    }

    Shortcut {
        sequence: "Ctrl+Backspace"
        context: Qt.WindowShortcut
        enabled: !root.blocked() && root.tableRoot.gameFinished
                 && root.tableRoot.gameSession.result.matchFinished === true
                 && !root.tableRoot.gameSession.sideboarding
        onActivated: root.tableRoot.wsModel.returnToRoom()
    }

    Shortcut {
        sequence: "P"
        context: Qt.WindowShortcut
        enabled: !root.blocked() && root.selectionDomain() === "hand"
                 && root.tableRoot.isActivePlayer
        onActivated: root.tableRoot.landPlay.requestSelectedHandCard()
    }

    Shortcut {
        sequence: "Alt+B"
        context: Qt.WindowShortcut
        enabled: root.selectionDomain() === "hand" && root.canUseSelection()
        onActivated: root.moveSelection("battlefield")
    }

    Shortcut {
        sequence: "Alt+Shift+B"
        context: Qt.WindowShortcut
        enabled: root.selectionDomain() === "hand" && root.canUseSelection()
        onActivated:
            root.tableRoot.cardMoveCommands.moveSelectedHandCard(
                "battlefield", true)
    }

    Shortcut {
        sequence: "Alt+H"
        context: Qt.WindowShortcut
        enabled: root.canMoveSelection("hand")
        onActivated: root.moveSelection("hand")
    }

    Shortcut {
        sequence: "Alt+G"
        context: Qt.WindowShortcut
        enabled: root.canMoveSelection("graveyard")
        onActivated: root.moveSelection("graveyard")
    }

    Shortcut {
        sequence: "Alt+E"
        context: Qt.WindowShortcut
        enabled: root.canMoveSelection("exile")
        onActivated: root.moveSelection("exile")
    }

    Shortcut {
        sequence: "Alt+Up"
        context: Qt.WindowShortcut
        enabled: root.canMoveSelection("library-top")
        onActivated: root.moveSelection("library-top")
    }

    Shortcut {
        sequence: "Alt+Down"
        context: Qt.WindowShortcut
        enabled: root.canMoveSelection("library-bottom")
        onActivated: root.moveSelection("library-bottom")
    }

    Shortcut {
        sequence: "Alt+Shift+Up"
        context: Qt.WindowShortcut
        enabled: root.selectionDomain() === "battlefield"
                 && root.selectedBattlefieldCount() > 1
                 && root.canUseSelection()
        onActivated: root.moveSelection("library-top", true)
    }

    Shortcut {
        sequence: "Alt+Shift+Down"
        context: Qt.WindowShortcut
        enabled: root.selectionDomain() === "battlefield"
                 && root.selectedBattlefieldCount() > 1
                 && root.canUseSelection()
        onActivated: root.moveSelection("library-bottom", true)
    }

    Shortcut {
        sequence: "T"
        context: Qt.WindowShortcut
        enabled: root.canUseBattlefieldSources()
        onActivated: root.toggleSelectedPermanents()
    }

    Shortcut {
        sequence: "F"
        context: Qt.WindowShortcut
        enabled: root.canUseSingleBattlefieldCard()
        onActivated: root.toggleSelectedFaceDown()
    }

    Shortcut {
        sequence: "V"
        context: Qt.WindowShortcut
        enabled: root.canUseSingleBattlefieldCard()
                 && root.tableRoot.selectedBattlefieldFaces.length > 1
        onActivated:
            root.tableRoot.cardMoveCommands.requestBattlefieldFaceSelection()
    }

    Shortcut {
        sequence: "A"
        context: Qt.WindowShortcut
        enabled: root.canUseSingleBattlefieldCard()
                 && root.tableRoot.attachmentUi.canAttachSelected()
        onActivated: root.tableRoot.attachmentUi.beginAttach()
    }

    Shortcut {
        sequence: "Shift+A"
        context: Qt.WindowShortcut
        enabled: root.canUseSingleBattlefieldCard()
                 && root.tableRoot.attachmentUi.canDetachSelected()
        onActivated: root.tableRoot.attachmentUi.detachSelected()
    }

    Shortcut {
        sequence: "R"
        context: Qt.WindowShortcut
        enabled: root.canUseBattlefieldSources()
        onActivated:
            root.tableRoot.selection.beginRelationTarget("arrow")
    }

    Shortcut {
        sequence: "Shift+R"
        context: Qt.WindowShortcut
        enabled: root.canUseBattlefieldSources()
                 && root.selectedHasArrow(["target"])
        onActivated: root.clearSelectedArrows(["target"])
    }

    Shortcut {
        sequence: "X"
        context: Qt.WindowShortcut
        enabled: root.canUseBattlefieldSources()
                 && root.tableRoot.isActivePlayer
                 && root.tableRoot.gameSession.currentPhase
                    === "declare_attackers"
        onActivated:
            root.tableRoot.selection.beginRelationTarget("attack")
    }

    Shortcut {
        sequence: "Shift+X"
        context: Qt.WindowShortcut
        enabled: root.canUseBattlefieldSources()
                 && root.tableRoot.gameSession.currentPhase
                    === "declare_blockers"
                 && root.hasIncomingAttacker()
        onActivated:
            root.tableRoot.selection.beginRelationTarget("block")
    }

    Shortcut {
        sequence: "Shift+C"
        context: Qt.WindowShortcut
        enabled: root.canUseBattlefieldSources()
                 && root.selectedHasArrow(["attack", "block"])
        onActivated: root.clearSelectedArrows(["attack", "block"])
    }

    Shortcut {
        sequence: "N"
        context: Qt.WindowShortcut
        enabled: root.canUseSingleBattlefieldCard()
        onActivated: root.tableRoot.cardActions.addNumberCounter()
    }

    Shortcut {
        sequence: "Shift+N"
        context: Qt.WindowShortcut
        enabled: root.canUseSingleBattlefieldCard()
        onActivated: root.tableRoot.cardCounterEditor.showNewAbility(
                         root.tableRoot.selectedBattlefieldCard.name)
    }

    Shortcut {
        sequence: "Ctrl+N"
        context: Qt.WindowShortcut
        enabled: root.canUseSingleBattlefieldCard()
        onActivated: root.tableRoot.cardCounterEditor.showNumber(
                         root.tableRoot.selectedBattlefieldCard.name,
                         root.tableRoot.cardActions.numberCounterValue(
                             root.tableRoot.selectedBattlefieldCard.counters
                             ? root.tableRoot.selectedBattlefieldCard.counters
                             : []))
    }

    Shortcut {
        sequence: "Alt+C"
        context: Qt.WindowShortcut
        enabled: root.canUseSingleBattlefieldSelection()
        onActivated: root.tableRoot.cardActions.createSelectedTokenCopy()
    }
}
