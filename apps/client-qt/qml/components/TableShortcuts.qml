// SPDX-License-Identifier: GPL-3.0-or-later
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
        id: shortcutContext
        tableRoot: root.tableRoot
    }

    TableViewShortcuts {
        shortcutState: shortcutContext
        shortcutHelp: root.shortcutHelp
    }

    TableLibraryShortcuts {
        shortcutState: shortcutContext
        drawCardsEditor: root.drawCardsEditor
        libraryTopCountEditor: root.libraryTopCountEditor
        shuffleConfirmation: root.shuffleConfirmation
    }

    TableGameShortcuts {
        shortcutState: shortcutContext
        tokenPicker: root.tokenPicker
        mulliganConfirmation: root.mulliganConfirmation
        concedeConfirmation: root.concedeConfirmation
    }

    TableSelectionShortcuts {
        shortcutState: shortcutContext
    }

    // Stable test and integration facade. Shortcut policy lives in
    // TableShortcutContext; callers do not need to know the domain split.
    function blocked() { return shortcutContext.blocked() }
    function canEditSelectedCounter() {
        return shortcutContext.canEditSelectedCounter()
    }
    function canUseLibrary() { return shortcutContext.canUseLibrary() }
    function canUseGameAction() { return shortcutContext.canUseGameAction() }
    function canMulligan() { return shortcutContext.canMulligan() }
    function canToggleHand() { return shortcutContext.canToggleHand() }
    function canConcede() { return shortcutContext.canConcede() }
    function canAdvanceTurn() { return shortcutContext.canAdvanceTurn() }
    function selectedBattlefieldCount() {
        return shortcutContext.selectedBattlefieldCount()
    }
    function hasSelectedHandCard() {
        return shortcutContext.hasSelectedHandCard()
    }
    function selectionDomain() { return shortcutContext.selectionDomain() }
    function canUseSelection() { return shortcutContext.canUseSelection() }
    function canUseSingleBattlefieldSelection() {
        return shortcutContext.canUseSingleBattlefieldSelection()
    }
    function canUseSingleBattlefieldCard() {
        return shortcutContext.canUseSingleBattlefieldCard()
    }
    function canUseBattlefieldSources() {
        return shortcutContext.canUseBattlefieldSources()
    }
    function selectedHasArrow(kinds) {
        return shortcutContext.selectedHasArrow(kinds)
    }
    function hasIncomingAttacker() {
        return shortcutContext.hasIncomingAttacker()
    }
    function canMoveSelection(destination) {
        return shortcutContext.canMoveSelection(destination)
    }
    function moveSelection(destination, randomize) {
        shortcutContext.moveSelection(destination, randomize)
    }
    function toggleSelectedFaceDown() {
        shortcutContext.toggleSelectedFaceDown()
    }
    function clearSelectedArrows(kinds) {
        shortcutContext.clearSelectedArrows(kinds)
    }
    function adjustOwnLife(delta) { shortcutContext.adjustOwnLife(delta) }
    function adjustSelectedPlayerCounter(delta) {
        shortcutContext.adjustSelectedPlayerCounter(delta)
    }
    function toggleSelectedPermanents() {
        shortcutContext.toggleSelectedPermanents()
    }
}
