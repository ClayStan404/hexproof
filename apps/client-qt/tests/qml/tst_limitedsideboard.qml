// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtTest
import "../../qml/components"

TestCase {
    id: testCase
    name: "LimitedSideboard"
    when: windowShown

    readonly property alias testWindow: harness.testWindowObject
    readonly property alias tableHost: harness.tableHostObject
    readonly property alias mockWs: harness.mockWsObject
    readonly property alias mockCatalog: harness.mockCatalogObject
    readonly property alias tableComponent: harness.tableComponentObject
    property int slowTypeLineCalls: 0
    property int cachedTypeLineCalls: 0
    property int imageSourceCalls: 0
    property int tableImageSourceCalls: 0

    MatchLoadingTestHarness {
        id: harness
        testCase: testCase
    }

    Connections {
        target: mockCatalog
        function onCardTypeLineRequested() { ++testCase.slowTypeLineCalls }
        function onCachedCardTypeLineRequested() { ++testCase.cachedTypeLineCalls }
        function onImageSourceRequested() { ++testCase.imageSourceCalls }
        function onTableImageSourceRequested() { ++testCase.tableImageSourceCalls }
    }

    function init() {
        verify(harness.reset())
        slowTypeLineCalls = 0
        cachedTypeLineCalls = 0
        imageSourceCalls = 0
        tableImageSourceCalls = 0
        mockCatalog.language = "en"
        mockCatalog.imageRevision = 0
        mockCatalog.typeLines = ({})
    }

    function cleanup() {
        harness.cleanupHarness()
        Theme.uiScale = 1
        testWindow.width = 1400
        testWindow.height = 800
    }

    function test_compactWorkspace_data() {
        return [{tag: "150-percent", scale: 1.5},
                {tag: "180-percent", scale: 1.8}]
    }

    function test_compactWorkspace(data) {
        Theme.uiScale = data.scale
        testWindow.width = 900
        testWindow.height = 620
        testWindow.requestActivate()
        tryCompare(testWindow, "active", true)
        mockWs.deckFormat = "limited"
        mockWs.sideboarding = true
        mockWs.gameFinished = true
        mockWs.sideboardState = {
            deadlineUnixMs: Date.now() + 300000,
            seats: [
                {seat: 0, ready: false, mainboardCount: 40, sideboardCount: 15},
                {seat: 1, ready: false, mainboardCount: 40, sideboardCount: 15}
            ],
            mainboard: [
                {name: "Pool Card", count: 23, typeLine: "Creature", colors: "R"},
                {name: "Island", count: 17, typeLine: "Basic Land"}
            ],
            sideboard: [{name: "Reserve Card", count: 15, typeLine: "Instant"}]
        }
        const table = createTemporaryObject(tableComponent, tableHost, {
            width: 900, height: 620
        })
        verify(table !== null)
        const panel = findChild(table, "sideboardPanel")
        verify(waitForRendering(table))
        const ready = findChild(panel, "sideboardReadyButton")
        const readyPosition = ready.mapToItem(table, 0, 0)
        verify(readyPosition.x + ready.width <= table.width)
        verify(readyPosition.y + ready.height <= table.height)
        for (const zone of ["mainboard", "sideboard"]) {
            const cards = findChild(panel, "sideboardCategoryTable-" + zone)
            verify(cards.height >= 100, zone + " must retain usable card space")
        }
        const filterButton = findChild(panel, "sideboardFiltersButton")
        mouseClick(filterButton)
        const popup = findChild(panel, "sideboardToolsPopup")
        tryCompare(popup, "opened", true)
        const filters = findChild(panel, "limitedSideboardFilters")
        filters.colorFilterIndex = 4
        tryCompare(panel.tableModel, "mainboardCount", 23)
        const clear = findChild(panel, "limitedSideboardClearFiltersButton")
        verify(waitForRendering(clear))
        mouseClick(clear)
        tryCompare(panel.tableModel, "mainboardCount", 40)
        mouseClick(findChild(panel, "sideboardToolsCloseButton"))
        tryCompare(popup, "opened", false)
        mouseClick(findChild(panel, "sideboardBasicLandsButton"))
        tryCompare(popup, "opened", true)
        const add = findChild(popup.contentItem, "sideboardBasicAdd-Forest")
        verify(waitForRendering(add))
        mouseClick(add)
        compare(mockWs.sideboardMoveCount, 1)
        compare(mockWs.lastSideboardMove.card.name, "Forest")
        compare(mockWs.lastSideboardMove.fromZone, "basic_lands")
        keyClick(Qt.Key_Escape)
        tryCompare(popup, "opened", false)
        mouseClick(ready)
        compare(mockWs.sideboardReadyCount, 1)
        verify(panel.readyPending)
        verify(!ready.enabled)
        mouseClick(ready)
        compare(mockWs.sideboardReadyCount, 1)
        const acknowledged = Object.assign({}, mockWs.sideboardState)
        acknowledged.seats = [{seat:0, ready:true, mainboardCount:40, sideboardCount:15},
            {seat:1, ready:false, mainboardCount:40, sideboardCount:15}]
        mockWs.sideboardState = acknowledged
        tryCompare(panel, "readyPending", false)
        verify(ready.enabled)
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

    function test_missingTypeLineUsesLanguageKeyedCacheOnlyLookup() {
        mockWs.sideboarding = true
        mockWs.gameFinished = true
        mockWs.sideboardState = {
            "deadlineUnixMs": Date.now() + 300000,
            "seats": [
                {"seat": 0, "ready": false,
                 "mainboardCount": 1, "sideboardCount": 0}
            ],
            "mainboard": [{
                "name": "Cache Me", "count": 1,
                "setCode": "TST", "collectorNumber": "7",
                "typeLine": ""
            }],
            "sideboard": []
        }
        mockCatalog.typeLines = ({"Cache Me": "Artifact"})
        const table = tableComponent.createObject(tableHost, {
            "width": testWindow.width,
            "height": testWindow.height
        })
        verify(table !== null)
        const panel = findChild(table, "sideboardPanel")
        verify(panel !== null)

        compare(panel.resolvedTypeLine({
            "name": "Cache Me",
            "setCode": "TST",
            "collectorNumber": "7",
            "typeLine": ""
        }), "Artifact")
        verify(cachedTypeLineCalls > 0)
        compare(slowTypeLineCalls, 0)
        const englishCalls = cachedTypeLineCalls

        mockCatalog.typeLines = ({"Cache Me": "神器"})
        mockCatalog.language = "zh"
        compare(panel.resolvedTypeLine({
            "name": "Cache Me",
            "setCode": "TST",
            "collectorNumber": "7",
            "typeLine": ""
        }), "神器")
        verify(cachedTypeLineCalls > englishCalls)
        compare(slowTypeLineCalls, 0)
        table.destroy()
    }

    function test_cardArtBindingRefreshesOnImageRevision() {
        mockWs.sideboarding = true
        mockWs.gameFinished = true
        mockWs.sideboardState = {
            "deadlineUnixMs": Date.now() + 300000,
            "seats": [
                {"seat": 0, "ready": false,
                 "mainboardCount": 1, "sideboardCount": 0}
            ],
            "mainboard": [{
                "name": "Art Card", "count": 1,
                "setCode": "TST", "collectorNumber": "8",
                "typeLine": "Creature"
            }],
            "sideboard": []
        }
        const table = tableComponent.createObject(tableHost, {
            "width": testWindow.width,
            "height": testWindow.height
        })
        verify(table !== null)
        const panel = findChild(table, "sideboardPanel")
        const art = findChild(panel, "sideboardCardArt-mainboard-0")
        verify(panel !== null)
        tryVerify(() => art !== null)
        panel.inspectedCard = mockWs.sideboardState.mainboard[0]
        panel.hoverPreviewVisible = true
        tryVerify(() => imageSourceCalls > 0)
        wait(5)
        imageSourceCalls = 0
        tableImageSourceCalls = 0

        ++mockCatalog.imageRevision

        tryVerify(() => imageSourceCalls > 0
                         && tableImageSourceCalls > 0)
        table.destroy()
    }

    function test_lateCachedTypeLineRecomputesGroupingAndFilter() {
        mockWs.deckFormat = "limited"
        mockWs.sideboarding = true
        mockWs.gameFinished = true
        mockWs.sideboardState = {
            "deadlineUnixMs": Date.now() + 300000,
            "seats": [
                {"seat": 0, "ready": false,
                 "mainboardCount": 1, "sideboardCount": 0}
            ],
            "mainboard": [{
                "name": "Late Metadata", "count": 1,
                "setCode": "TST", "collectorNumber": "9",
                "typeLine": ""
            }],
            "sideboard": []
        }
        mockCatalog.typeLines = ({})
        const table = tableComponent.createObject(tableHost, {
            "width": testWindow.width,
            "height": testWindow.height
        })
        verify(table !== null)
        const panel = findChild(table, "sideboardPanel")
        const filters = findChild(panel, "limitedSideboardFilters")
        verify(panel !== null)
        verify(filters !== null)
        const originalMainboard = panel.mainboard
        const initialGroups = panel.categoryGroups(panel.mainboard)
        compare(panel.categoryGroup(initialGroups, "Other").count, 1)

        filters.typeFilterIndex = 6
        compare(filters.typeFilter, "artifact")
        compare(filters.visibleMainboardCount, 0)
        const callsBeforeMetadata = cachedTypeLineCalls

        mockCatalog.typeLines = ({"Late Metadata": "Artifact"})
        ++mockCatalog.imageRevision

        tryCompare(filters, "visibleMainboardCount", 1)
        tryCompare(panel.tableModel, "mainboardCount", 1)
        tryVerify(() => panel.mainboardGroups.length === 1
                         && panel.mainboardGroups[0].category === "Artifact")
        compare(panel.mainboard, originalMainboard)
        verify(cachedTypeLineCalls > callsBeforeMetadata)
        compare(slowTypeLineCalls, 0)
        table.destroy()
    }

    function test_typeLineCacheDropsPriorRevisionsAndLanguages() {
        mockWs.sideboarding = true
        mockWs.gameFinished = true
        mockWs.sideboardState = {
            "deadlineUnixMs": Date.now() + 300000,
            "seats": [
                {"seat": 0, "ready": false,
                 "mainboardCount": 2, "sideboardCount": 0}
            ],
            "mainboard": [{
                "name": "Cache Alpha", "count": 1,
                "setCode": "TST", "collectorNumber": "10",
                "typeLine": ""
            }, {
                "name": "Cache Beta", "count": 1,
                "setCode": "TST", "collectorNumber": "11",
                "typeLine": ""
            }],
            "sideboard": []
        }
        mockCatalog.typeLines = ({
            "Cache Alpha": "Artifact",
            "Cache Beta": "Creature"
        })
        const table = tableComponent.createObject(tableHost, {
            "width": testWindow.width,
            "height": testWindow.height
        })
        verify(table !== null)
        const panel = findChild(table, "sideboardPanel")
        verify(panel !== null)
        const originalMainboard = panel.mainboard
        panel.resolvedTypeLineCache = ({})

        function resolveUnchangedCards() {
            for (let index = 0; index < originalMainboard.length; ++index)
                panel.resolvedTypeLine(originalMainboard[index])
        }

        resolveUnchangedCards()
        compare(Object.keys(panel.resolvedTypeLineCache).length, 2)
        for (let revision = 1; revision <= 4; ++revision) {
            mockCatalog.imageRevision = revision
            wait(0)
            resolveUnchangedCards()
            compare(Object.keys(panel.resolvedTypeLineCache).length, 2)
        }

        const languages = ["zh", "en", "zh"]
        for (let index = 0; index < languages.length; ++index) {
            mockCatalog.language = languages[index]
            wait(0)
            resolveUnchangedCards()
            compare(Object.keys(panel.resolvedTypeLineCache).length, 2)
        }
        compare(panel.mainboard, originalMainboard)
        compare(slowTypeLineCalls, 0)
        verify(cachedTypeLineCalls > 0)
        table.destroy()
    }
}
