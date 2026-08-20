// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic
import QtTest
import "../../qml/components"

TestCase {
    name: "ZoneBrowserPopup"
    when: windowShown

    ApplicationWindow {
        id: testWindow
        width: 1100
        height: 800
        visible: true

        ZoneBrowserPopup {
            id: popup
            cards: [
                {"id": "c0", "name": "Opt", "setCode": "MID",
                 "collectorNumber": "1"},
                {"id": "c1", "name": "Ponder", "setCode": "M10",
                 "collectorNumber": "2"},
                {"id": "c2", "name": "Preordain", "setCode": "M11",
                 "collectorNumber": "3"}
            ]
        }
    }

    function init() {
        if (popup.opened)
            popup.close()
        popup.filterQuery = ""
        popup.selectedIndex = -1
        popup.selectedOrder = []
    }

    function cleanup() {
        if (popup.opened)
            popup.close()
        wait(1)
    }

    // showZone / onClosed assign searchField.text. That must not restart the
    // debounce timer and snap selectedIndex back to 0 after the user already
    // clicked a later card.
    function test_programmaticFilterClearDoesNotResetSelection() {
        popup.showZone("Alice", 0, "graveyard")
        tryVerify(() => popup.opened)
        const filter = findChild(popup, "zoneBrowserFilter")
        verify(filter !== null)
        filter.text = "tmp"
        filter.text = ""
        popup.selectedIndex = 2
        wait(200)
        compare(popup.selectedIndex, 2)
        compare(popup.filterQuery, "")
    }
}
