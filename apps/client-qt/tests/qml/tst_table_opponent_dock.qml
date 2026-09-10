// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtTest

TestCase {
    id: testCase
    name: "TableOpponentDock"
    when: windowShown

    readonly property alias testWindow: harness.testWindowObject
    readonly property alias tableHost: harness.tableHostObject
    readonly property alias mockWs: harness.mockWsObject
    readonly property alias tableComponent: harness.tableComponentObject

    MatchLoadingTestHarness {
        id: harness
        testCase: testCase
    }

    function init() {
        verify(harness.reset())
    }

    function cleanup() {
        harness.cleanupHarness()
    }

    function test_opponentDockConstructsOnlyWhileExpanded() {
        const table = tableComponent.createObject(tableHost, {
            "width": testWindow.width,
            "height": testWindow.height
        })
        verify(table !== null)

        const opponentToggle = findChild(table, "opponentZoneToggle1")
        verify(opponentToggle !== null)
        verify(findChild(table, "opponentZoneDock1") === null)

        opponentToggle.clicked()
        tryVerify(() => findChild(table, "opponentZoneDock1") !== null)

        opponentToggle.clicked()
        tryVerify(() => findChild(table, "opponentZoneDock1") === null)
        table.destroy()
    }

    function test_opponentPublicZonePilesHandleSeatRemoval() {
        const table = tableComponent.createObject(tableHost, {
            "width": testWindow.width,
            "height": testWindow.height
        })
        verify(table !== null)
        const opponentToggle = findChild(table, "opponentZoneToggle1")
        verify(opponentToggle !== null)
        verify(findChild(table, "opponentZoneDock1") === null)
        opponentToggle.clicked()
        tryVerify(() => findChild(table, "opponentZoneDock1") !== null)
        verify(findChild(table, "graveyardBrowserButton1") !== null)
        verify(findChild(table, "exileBrowserButton1") !== null)

        failOnWarning(/Cannot read property 'seat' of null/)
        mockWs.gameSeats = [JSON.parse(JSON.stringify(
                                          mockWs.baselineGameSeats[0]))]
        tryVerify(() => findChild(table, "opponentZoneDock1") === null)
        table.destroy()
    }
}
