// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic
import QtTest
import "../../qml/components"

TestCase {
    id: testCase
    name: "LibrarySearchPopup"
    when: windowShown

    ApplicationWindow {
        id: testWindow
        width: 900
        height: 620
        visible: true
        LibrarySearchPopup { id: popup }
    }

    SignalSpy { id: searchSpy; target: popup; signalName: "searchRequested" }
    SignalSpy { id: resolveSpy; target: popup; signalName: "resolveAssignmentsRequested" }

    function init() {
        testWindow.requestActivate()
        tryCompare(testWindow, "active", true)
        searchSpy.clear()
        resolveSpy.clear()
    }

    function cleanup() {
        popup.close()
        Theme.uiScale = 1
    }

    function test_compactControls_data() {
        const rows = []
        for (const scale of [1.5, 1.8]) {
            for (const topCount of [0, 1, 3])
                rows.push({tag: scale + "-top-" + topCount, scale, topCount})
        }
        return rows
    }

    function test_destinationNamesLeadWithZoneAndRetainOwnership() {
        popup.showCards([{id: "a", name: "Island"}], 1, "approval", 0,
                        "Local player with a long name", "Remote player with a long name", 3)
        const options = popup.destinations
        compare(options[0].label, "Hand · Local player with a long name")
        compare(options[0].seat, 0)
        compare(options[4].label, "Hand · Remote player with a long name")
        compare(options[4].seat, 1)
        compare(options[8].label, "Top of library · Remote player with a long name")
        compare(options[8].value, "library_top")
        compare(popup.topCardDestinations[4].label,
                "Top of library · Remote player with a long name")
    }

    function test_compactControls(data) {
        Theme.uiScale = data.scale
        popup.showCards([
            {id: "a", name: "Lightning Bolt", setCode: "M11", collectorNumber: "149"},
            {id: "b", name: "Island", setCode: "TST", collectorNumber: "2"},
            {id: "c", name: "Forest", setCode: "TST", collectorNumber: "3"}
        ].slice(0, data.topCount === 1 ? 1 : 3), 0, "", 0, "Alice", "Alice", data.topCount)
        tryCompare(popup, "opened", true)
        verify(waitForRendering(popup.contentItem))
        const list = findChild(popup, "librarySearchCards")
        verify(list.width >= 300)
        verify(list.height >= 150)
        if (data.topCount === 1)
            return

        if (data.topCount === 0) {
            mouseClick(findChild(popup, "selectAllLibraryCards"))
            compare(popup.selectedOrder, ["a", "b", "c"])
        }
        const scroll = findChild(popup, "libraryInspectorScroll")
        scroll.contentItem.contentY = scroll.contentItem.contentHeight - scroll.height
        verify(waitForRendering(popup.contentItem))
        const toggle = findChild(popup, data.topCount > 1
                                 ? "topCardsRandomizeBottom" : "revealLibrarySearch")
        verify(toggle.contentItem.paintedWidth <= toggle.contentItem.width + 1)
        if (data.topCount === 0) {
            popup.moveSelectedCardInOrder("b", -1)
            verify(waitForRendering(popup.contentItem))
            const up = findChild(popup.contentItem, "librarySelectedMoveUp0")
            verify(up.width <= Theme.size(40))
        }
        const complete = findChild(popup, "completeLibrarySearchButton")
        const position = complete.mapToItem(popup.contentItem, 0, 0)
        verify(position.y >= 0)
        verify(position.y + complete.height <= popup.availableHeight + 1)
        mouseClick(complete)
        if (data.topCount === 0) {
            compare(searchSpy.count, 1)
            compare(searchSpy.signalArguments[0][0], ["b", "a", "c"])
        } else {
            compare(resolveSpy.count, 1)
            compare(resolveSpy.signalArguments[0][0].length, 3)
        }
    }
}
