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

    TableShortcutContext {
        id: shortcutState
        tableRoot: root.tableRoot
    }

    TableViewShortcuts {
        shortcutState: shortcutState
        shortcutHelp: root.shortcutHelp
    }

    TableLibraryShortcuts {
        shortcutState: shortcutState
        drawCardsEditor: root.drawCardsEditor
        libraryTopCountEditor: root.libraryTopCountEditor
        shuffleConfirmation: root.shuffleConfirmation
    }

    TableGameShortcuts {
        shortcutState: shortcutState
        tokenPicker: root.tokenPicker
        mulliganConfirmation: root.mulliganConfirmation
        concedeConfirmation: root.concedeConfirmation
    }

    TableSelectionShortcuts {
        shortcutState: shortcutState
    }

    // Stable test and integration facade. Shortcut policy lives in
    // TableShortcutContext; callers do not need to know the domain split.
    function blocked() { return shortcutState.blocked() }
    function canEditSelectedCounter() {
        return shortcutState.canEditSelectedCounter()
    }
    function canUseLibrary() { return shortcutState.canUseLibrary() }
    function canUseGameAction() { return shortcutState.canUseGameAction() }
    function canMulligan() { return shortcutState.canMulligan() }
    function canToggleHand() { return shortcutState.canToggleHand() }
    function canConcede() { return shortcutState.canConcede() }
    function canAdvanceTurn() { return shortcutState.canAdvanceTurn() }
    function selectedBattlefieldCount() {
        return shortcutState.selectedBattlefieldCount()
    }
    function hasSelectedHandCard() {
        return shortcutState.hasSelectedHandCard()
    }
    function selectionDomain() { return shortcutState.selectionDomain() }
    function canUseSelection() { return shortcutState.canUseSelection() }
    function canUseSingleBattlefieldSelection() {
        return shortcutState.canUseSingleBattlefieldSelection()
    }
    function canUseSingleBattlefieldCard() {
        return shortcutState.canUseSingleBattlefieldCard()
    }
    function canUseBattlefieldSources() {
        return shortcutState.canUseBattlefieldSources()
    }
    function selectedHasArrow(kinds) {
        return shortcutState.selectedHasArrow(kinds)
    }
    function hasIncomingAttacker() {
        return shortcutState.hasIncomingAttacker()
    }
    function canMoveSelection(destination) {
        return shortcutState.canMoveSelection(destination)
    }
    function moveSelection(destination, randomize) {
        shortcutState.moveSelection(destination, randomize)
    }
    function toggleSelectedFaceDown() {
        shortcutState.toggleSelectedFaceDown()
    }
    function clearSelectedArrows(kinds) {
        shortcutState.clearSelectedArrows(kinds)
    }
    function adjustOwnLife(delta) { shortcutState.adjustOwnLife(delta) }
    function adjustSelectedPlayerCounter(delta) {
        shortcutState.adjustSelectedPlayerCounter(delta)
    }
    function toggleSelectedPermanents() {
        shortcutState.toggleSelectedPermanents()
    }
}
