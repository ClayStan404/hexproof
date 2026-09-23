// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls.Basic

Popup {
    id: root

    required property var tableController
    readonly property var session: tableController.rulesSession
    property bool requested: false
    property bool inspectingBattlefield: false
    readonly property string contextKey: JSON.stringify([
        session.gameId, session.promptId, tableController.localSeat])

    parent: Overlay.overlay
    modal: true
    focus: true
    closePolicy: Popup.NoAutoClose
    visible: requested && !inspectingBattlefield

    function inspectBattlefield() {
        if (requested && !tableController.rulesResponsePending)
            inspectingBattlefield = true
    }

    function resumeDecision() {
        if (requested)
            inspectingBattlefield = false
    }

    onRequestedChanged: if (!requested) inspectingBattlefield = false
    onContextKeyChanged: inspectingBattlefield = false

    Connections {
        target: root.session
        // A re-published prompt can reuse its ID but still replace its choices.
        function onPromptChanged() { root.inspectingBattlefield = false }
    }
}
