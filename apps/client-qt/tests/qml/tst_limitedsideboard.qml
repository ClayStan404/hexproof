// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtTest

TestCase {
    id: testCase
    name: "LimitedSideboard"
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

    function test_filtersAndUnlimitedBasicLandSupply() {
        mockWs.deckFormat = "limited"
        mockWs.sideboarding = true
        mockWs.gameFinished = true
        mockWs.sideboardState = {
            "deadlineUnixMs": Date.now() + 300000,
            "seats": [
                {"seat": 0, "ready": false,
                 "mainboardCount": 40, "sideboardCount": 1},
                {"seat": 1, "ready": false,
                 "mainboardCount": 40, "sideboardCount": 1}
            ],
            "mainboard": [{
                "name": "Pool Card", "count": 23,
                "setCode": "TST", "collectorNumber": "1",
                "typeLine": "Creature", "colors": "R",
                "manaValue": 3, "rarity": "mythic"
            }, {
                "name": "Island", "count": 17,
                "setCode": "", "collectorNumber": "",
                "typeLine": "Basic Land", "rarity": "unknown"
            }],
            "sideboard": [{
                "name": "Island", "count": 1,
                "setCode": "TST", "collectorNumber": "2",
                "typeLine": "Basic Land — Island", "rarity": "common"
            }]
        }
        const table = tableComponent.createObject(tableHost, {
            "width": testWindow.width,
            "height": testWindow.height
        })
        verify(table !== null)
        const panel = findChild(table, "sideboardPanel")
        const basicButton = findChild(panel, "sideboardBasicLandsButton")
        const basicPanel = findChild(panel, "sideboardBasicLandsPanel")
        const filters = findChild(panel, "limitedSideboardFilters")
        const readyButton = findChild(panel, "sideboardReadyButton")
        verify(panel !== null)
        verify(panel.limitedDeck)
        verify(basicButton !== null)
        verify(basicButton.visible)
        basicButton.clicked()
        verify(basicPanel !== null)
        verify(basicPanel.visible)
        compare(basicPanel.virtualBasicCount("Island"), 17)
        compare(basicPanel.virtualBasicTotal(), 17)
        verify(filters !== null)
        verify(filters.visible)
        verify(readyButton.enabled)

        filters.colorFilterIndex = 4
        filters.typeFilterIndex = 1
        filters.manaFilterIndex = 4
        filters.rarityFilterIndex = 4
        verify(filters.filtersActive)
        compare(filters.visibleMainboardCount, 23)
        compare(filters.visibleSideboardCount, 0)
        tryCompare(panel.tableModel, "mainboardCount", 23)
        tryCompare(panel.tableModel, "sideboardCount", 0)
        // Filtering the presentation must not disable a legal 40-card deck.
        verify(readyButton.enabled)
        filters.clearFilters()
        tryCompare(panel.tableModel, "mainboardCount", 40)
        tryCompare(panel.tableModel, "sideboardCount", 1)

        basicPanel.adjustLimitedBasic("Forest", 1)
        compare(mockWs.sideboardMoveCount, 1)
        compare(mockWs.lastSideboardMove.card.name, "Forest")
        compare(mockWs.lastSideboardMove.fromZone, "basic_lands")
        compare(mockWs.lastSideboardMove.toZone, "mainboard")

        panel.moveSideboardCard({
            "name": "Island", "setCode": "", "collectorNumber": "",
            "virtualCard": true
        }, "mainboard", "sideboard")
        compare(mockWs.sideboardMoveCount, 2)
        compare(mockWs.lastSideboardMove.toZone, "basic_lands")

        panel.moveSideboardCard({
            "name": "Island", "setCode": "TST", "collectorNumber": "2",
            "virtualCard": false
        }, "sideboard", "mainboard")
        compare(mockWs.sideboardMoveCount, 3)
        compare(mockWs.lastSideboardMove.toZone, "mainboard")
        table.destroy()
    }
}
