// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic
import QtTest
import "../../qml/components"

TestCase {
    name: "TournamentDecklist"
    when: windowShown
    ApplicationWindow {
        id: window
        width: 900; height: 620; visible: true
        TournamentDecklistPopup { id: popup }
    }
    function cleanup() { popup.close() }
    function test_mainboardReceivesMajorityOfAvailableWidth() {
        popup.showDeck("Alice", {mainboard:[{name:"Island",count:40}],sideboard:[]})
        tryCompare(popup, "opened", true)
        waitForRendering(popup.contentItem)
        const main = findChild(popup, "tournamentMainboardList")
        const side = findChild(popup, "tournamentSideboardList")
        verify(main.width > popup.availableWidth * 0.55)
        verify(side.width > popup.availableWidth * 0.3)
        verify(main.width > side.width)
        verify(main.width + side.width <= popup.availableWidth)
    }
}
