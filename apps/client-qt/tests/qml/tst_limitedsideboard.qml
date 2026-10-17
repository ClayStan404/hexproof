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
        mockCatalog.faces = ({})
    }

    function cleanup() {
        harness.cleanupHarness()
        Theme.uiScale = 1
        testWindow.width = 1400
        testWindow.height = 800
    }

    function makeScoreSideboard() {
        mockWs.sideboarding = true
        mockWs.gameFinished = true
        mockWs.sideboardState = {
            deadlineUnixMs: Date.now() + 300000,
            seats: [{seat: 0, ready: false, mainboardCount: 60, sideboardCount: 1},
                    {seat: 1, ready: false, mainboardCount: 60, sideboardCount: 1}],
            mainboard: [{name: "Forest", count: 60, typeLine: "Basic Land"}],
            sideboard: [{name: "Reserve", count: 1, typeLine: "Creature"}]
        }
        const table = createTemporaryObject(tableComponent, tableHost, {
            width: testWindow.width, height: testWindow.height
        })
        verify(table !== null)
        const panel = findChild(table, "sideboardPanel")
        verify(panel !== null)
        return {table: table, panel: panel}
    }

    function test_matchScoreUsesViewerOrder_data() {
        return [{tag: "player-zero", role: "player", seat: 0, order: [0, 1]},
                {tag: "player-one", role: "player", seat: 1, order: [1, 0]},
                {tag: "spectator", role: "spectator", seat: -1, order: [0, 1]},
                {tag: "spectator-with-old-seat", role: "spectator", seat: 1, order: [0, 1]}]
    }

    function test_matchScoreUsesViewerOrder(data) {
        mockWs.roomRole = data.role
        mockWs.seatIndex = data.seat
        mockWs.matchScore = [1, 0]
        const workspace = makeScoreSideboard()
        const panel = workspace.panel
        const score = findChild(panel, "sideboardMatchScore")
        tryCompare(score, "visible", true)
        compare(panel.matchScoreSeatOrder, data.order)
        const names = ["Alice", "Bob"]
        for (let slot = 0; slot < 2; ++slot) {
            compare(findChild(score, "sideboardMatchPlayer" + slot).text, names[data.order[slot]])
            compare(findChild(score, "sideboardMatchWins" + slot).text, String([1, 0][data.order[slot]]))
        }
        mockWs.matchScore = [1, 1]
        for (let slot = 0; slot < 2; ++slot)
            tryCompare(findChild(score, "sideboardMatchWins" + slot), "text", "1")
        // A newly created table after reconnect uses the same authoritative score.
        workspace.table.destroy()
        const restored = makeScoreSideboard().panel
        compare(restored.matchScoreSeatOrder, data.order)
        compare(findChild(restored, "sideboardMatchWins0").text, "1")
        compare(findChild(restored, "sideboardMatchWins1").text, "1")
    }

    function test_matchScoreRequiresAuthoritativeBo3Score() {
        mockWs.matchMode = "bo1"
        mockWs.matchScore = [1, 0]
        const panel = makeScoreSideboard().panel
        const score = findChild(panel, "sideboardMatchScore")
        compare(score.visible, false)
        mockWs.matchMode = "bo3"
        tryCompare(score, "visible", true)
        mockWs.matchScore = []
        tryCompare(score, "visible", false)
        mockWs.matchScore = [1]
        compare(score.visible, false)
        mockWs.matchScore = [1, 1]
        tryCompare(score, "visible", true)
        compare(findChild(score, "sideboardMatchWins0").text, "1")
        compare(findChild(score, "sideboardMatchWins1").text, "1")
    }

    function test_matchScoreLongNamesKeepControlsVisible_data() {
        return [{tag: "modern-150-percent", scale: 1.5, format: "modern"},
                {tag: "modern-180-percent", scale: 1.8, format: "modern"},
                {tag: "duel-150-percent", scale: 1.5, format: "duel"}]
    }

    function test_matchScoreLongNamesKeepControlsVisible(data) {
        Theme.uiScale = data.scale
        testWindow.width = 900
        testWindow.height = 620
        mockWs.format = data.format
        mockWs.deckFormat = data.format
        mockWs.matchScore = [1, 0]
        const seats = JSON.parse(JSON.stringify(mockWs.gameSeats))
        seats[0].displayName = "<b>Very long player name with repeated words</b> ".repeat(8)
        seats[1].displayName = "Another very long player name with repeated words ".repeat(8)
        mockWs.gameSeats = seats
        const panel = makeScoreSideboard().panel
        verify(waitForPolish(testWindow))
        for (const objectName of ["sideboardMatchScore", "sideboardCountdown", "sideboardReadyButton",
                                  "sideboardMatchWins0", "sideboardMatchWins1"]) {
            const control = findChild(panel, objectName)
            verify(control !== null && control.visible, objectName + " must remain visible")
            const position = control.mapToItem(panel, 0, 0)
            verify(position.x >= 0 && position.x + control.width <= panel.width,
                   objectName + " must stay within horizontal bounds")
            verify(position.y >= 0 && position.y + control.height <= panel.height,
                   objectName + " must stay within vertical bounds")
        }
        for (let slot = 0; slot < 2; ++slot) {
            const name = findChild(panel, "sideboardMatchPlayer" + slot)
            compare(name.textFormat, Text.PlainText)
            verify(name.truncated, "Long names must elide independently from the score")
            const wins = findChild(panel, "sideboardMatchWins" + slot)
            compare(wins.text, String([1, 0][slot]))
            verify(wins.paintedWidth <= wins.width + 0.5, "Wins must remain fully readable")
        }
        for (const zone of data.format === "duel" ? ["mainboard"] : ["mainboard", "sideboard"])
            verify(findChild(panel, "sideboardCategoryTable-" + zone).height >= 100,
                   zone + " must retain usable card space")
    }

    function test_matchScoreTooltipShowsLiteralPublicName() {
        testWindow.width = 900
        testWindow.height = 620
        const publicName = "<b>Player Alpha</b> & <i>literal public name</i> ".repeat(6)
        const seats = JSON.parse(JSON.stringify(mockWs.gameSeats))
        seats[0].displayName = publicName
        mockWs.gameSeats = seats
        mockWs.matchScore = [1, 0]
        const panel = makeScoreSideboard().panel
        const name = findChild(panel, "sideboardMatchPlayer0")
        verify(waitForPolish(testWindow))
        verify(name.truncated)
        mouseMove(name)
        const tip = findChild(name, "sideboardMatchNameTooltip0")
        verify(tip !== null)
        tryCompare(tip, "opened", true)
        compare(tip.contentItem.textFormat, Text.PlainText)
        compare(tip.contentItem.text, publicName)
        verify(tip.width <= Theme.size(560))
        verify(tip.contentItem.lineCount > 1, "The full literal name wraps within the local tooltip")
        mouseMove(findChild(panel, "sideboardCountdown"))
        tryCompare(tip, "opened", false)
    }

    function test_bothFacesHandoffPreservesSideboardAndResetsOnSourceChange_data() {
        return [{tag: "desktop", width: 1400, height: 800, scale: 1},
                {tag: "compact-scaled", width: 900, height: 620, scale: 1.8}]
    }

    function test_bothFacesHandoffPreservesSideboardAndResetsOnSourceChange(data) {
        testWindow.width = data.width
        testWindow.height = data.height
        Theme.uiScale = data.scale
        const front = {name: "Front Card", count: 1, setCode: "FCE",
                       collectorNumber: "1", typeLine: "Creature"}
        mockCatalog.faces = {"Front Card": [front,
            {name: "Reverse Card", faceName: "Reverse Card", setCode: "FCE", collectorNumber: "1"}]}
        mockWs.deckFormat = "limited"
        mockWs.sideboarding = true
        mockWs.gameFinished = true
        mockWs.sideboardState = {
            deadlineUnixMs: Date.now() + 300000,
            seats: [{seat: 0, ready: false, mainboardCount: 1, sideboardCount: 0}],
            mainboard: [front], sideboard: []
        }
        const table = createTemporaryObject(tableComponent, tableHost, {
            width: testWindow.width, height: testWindow.height
        })
        verify(table !== null)
        const panel = findChild(table, "sideboardPanel")
        const source = findChild(panel, "sideboardCardArt-mainboard-0")
        verify(source !== null)
        verify(waitForPolish(testWindow))
        mouseMove(source)
        panel.inspectSideboardCard(front, source)
        const preview = findChild(panel, "sideboardHoverPreview")
        const controller = findChild(panel, "sideboardFacePreviewController")
        compare(controller.displayFaces.map(face => face.name), ["Front Card", "Reverse Card"])
        const reverse = findChild(preview, "sideboardHoverPreviewArt-1")
        verify(reverse !== null)
        verify(findChild(preview, "viewOtherFaceButton") === null)
        verify(waitForPolish(testWindow))
        const reversePosition = reverse.mapToItem(preview, 0, 0)
        verify(reversePosition.x >= 0 && reversePosition.x + reverse.width <= preview.width)
        verify(reversePosition.y >= 0 && reversePosition.y + reverse.height <= preview.height)
        panel.releaseSideboardCardPreview(source)
        mouseMove(reverse)
        wait(450)
        verify(preview.visible, "Moving onto either face must retain the preview")
        compare(controller.viewedName, "Front Card")
        compare(mockWs.sideboardMoveCount, 0)
        compare(panel.mainboard[0].name, front.name)
        compare(panel.sideboard.length, 0)
        verify(preview.y + preview.height <= panel.height)

        panel.inspectSideboardCard(front, panel)
        compare(controller.faceIndex, controller.initialFaceIndex)
        // A departure from the previous tile cannot release the new preview.
        panel.releaseSideboardCardPreview(source)
        wait(450)
        verify(preview.visible)
        panel.hideSideboardCardPreview()
        verify(!preview.visible)
        compare(controller.faceIndex, controller.initialFaceIndex)
    }

    function test_previousLoserChooserUsesAuthoritativeSelection() {
        mockWs.deckFormat = "limited"
        mockWs.sideboarding = true
        mockWs.gameFinished = true
        mockWs.sideboardState = {
            deadlineUnixMs: Date.now() + 300000,
            canChooseStartingPlayer: true, chosenStartingSeat: 0,
            seats: [{seat: 0, ready: false, mainboardCount: 40, sideboardCount: 0},
                    {seat: 1, ready: false, mainboardCount: 40, sideboardCount: 0}],
            mainboard: [{name: "Forest", count: 40, typeLine: "Basic Land"}], sideboard: []
        }
        const table = createTemporaryObject(tableComponent, tableHost, {
            width: testWindow.width, height: testWindow.height
        })
        verify(table !== null)
        const play = findChild(table, "sideboardChoosePlayButton")
        const draw = findChild(table, "sideboardChooseDrawButton")
        verify(play !== null && draw !== null)
        verify(play.visible && draw.visible)
        compare(play.variant, "highlight")
        mouseClick(draw)
        compare(mockWs.chosenStartingSeatRequest, 1)
        compare(play.variant, "highlight", "Selection waits for authoritative projection")
        mockWs.sideboardState = Object.assign({}, mockWs.sideboardState, {chosenStartingSeat: 1})
        tryCompare(draw, "variant", "highlight")
        mouseClick(play)
        compare(mockWs.chosenStartingSeatRequest, 0)
        mockWs.sideboardState = Object.assign({}, mockWs.sideboardState, {canChooseStartingPlayer: false})
        tryCompare(play, "visible", false)
        verify(!draw.visible)
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
            verify(cards.height >= 100, zone + " must retain usable card space; height=" + cards.height)
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

    function test_clearMainboardIgnoresFiltersAndPreservesPrintedBasicPreference() {
        mockWs.deckFormat = "limited"
        mockWs.sideboarding = true
        mockWs.gameFinished = true
        mockWs.sideboardState = {
            deadlineUnixMs: Date.now() + 300000,
            seats: [{seat:0, ready:false, mainboardCount:40, sideboardCount:1}],
            mainboard: [{name:"Pool Card", count:23, setCode:"TST", collectorNumber:"1", colors:"R", typeLine:"Creature"},
                        {name:"Island", count:17, setCode:"TST", collectorNumber:"2", virtualBasic:true, typeLine:"Basic Land"}],
            sideboard: [{name:"Island", count:1, setCode:"TST", collectorNumber:"2", typeLine:"Basic Land"}]
        }
        mockCatalog.basicPrintings = {
            "Island": [{setCode:"ALT", collectorNumber:"99"}, {setCode:"TST", collectorNumber:"20"}],
            "Swamp": [{setCode:"ALT", collectorNumber:"10"}, {setCode:"TST", collectorNumber:"12"},
                      {setCode:"TST", collectorNumber:"3"}]
        }
        const table = createTemporaryObject(tableComponent, tableHost, {width:1400, height:800})
        verify(table !== null)
        const panel = findChild(table, "sideboardPanel")
        const basics = findChild(panel, "sideboardBasicLandsPanel")
        compare(basics.virtualBasicCount("Island"), 17)
        findChild(panel, "limitedSideboardFilters").colorFilterIndex = 4
        const clearMainboard = findChild(panel, "sideboardClearMainboardButton")
        verify(waitForRendering(clearMainboard))
        mouseClick(clearMainboard)
        compare(mockWs.clearMainboardCount, 1)
        compare(mockWs.sideboardMoveCount, 0)
        const next = Object.assign({}, mockWs.sideboardState)
        next.mainboard = []
        mockWs.sideboardState = next
        compare(basics.virtualBasicCount("Island"), 0)
        basics.adjustLimitedBasic("Island", 1)
        compare(mockWs.lastSideboardMove.card.setCode, "TST")
        compare(mockWs.lastSideboardMove.card.collectorNumber, "2")
        basics.adjustLimitedBasic("Swamp", 1)
        compare(mockWs.lastSideboardMove.card.setCode, "TST")
        compare(mockWs.lastSideboardMove.card.collectorNumber, "3")
        verify(!findChild(panel, "sideboardReadyButton").enabled)
    }

    function test_coldSideboardRestoresEnvironmentBasicPrinting_data() {
        return [{tag:"product-overrides-pool", productSet:"ENV", expectedSet:"ENV"},
                {tag:"missing-product-uses-pool", productSet:"", expectedSet:"POOL"},
                {tag:"unavailable-product-uses-pool", productSet:"MISSING", expectedSet:"POOL"}]
    }

    function test_coldSideboardRestoresEnvironmentBasicPrinting(data) {
        mockWs.deckFormat = "limited"
        mockWs.sideboarding = true
        mockWs.gameFinished = true
        mockWs.limitedSession = {product:{setCode:data.productSet}}
        // A newly created view after reconnect receives an already empty main
        // deck and cannot rely on any preferences from the previous instance.
        mockWs.sideboardState = {
            deadlineUnixMs:Date.now() + 300000,
            seats:[{seat:0, ready:false, mainboardCount:0, sideboardCount:40}],
            mainboard:[],
            sideboard:[{name:"Bonus Card", count:1, setCode:"ALT", collectorNumber:"1"},
                       {name:"Pool Card", count:39, setCode:"POOL", collectorNumber:"2"}]
        }
        mockCatalog.basicPrintings = {
            "Swamp":[{setCode:"ALT", collectorNumber:"1"},
                     {setCode:"ENV", collectorNumber:"4"},
                     {setCode:"POOL", collectorNumber:"7"}]
        }
        const table = createTemporaryObject(tableComponent, tableHost, {width:1400, height:800})
        verify(table !== null)
        const basics = findChild(table, "sideboardBasicLandsPanel")
        compare(Object.keys(basics.preferredPrintings).length, 0)
        basics.adjustLimitedBasic("Swamp", 1)
        compare(mockWs.lastSideboardMove.card.setCode, data.expectedSet)
        compare(mockWs.lastSideboardMove.card.collectorNumber, data.expectedSet === "ENV" ? "4" : "7")
        compare(mockWs.lastSideboardMove.fromZone, "basic_lands")
        compare(mockWs.lastSideboardMove.toZone, "mainboard")
    }

    function test_cubeBasicPrintingHasStableCatalogFallback_data() {
        return [{tag:"shared-five-color-series", shared:true, empty:false, expectedSet:"SHARED", expectedNumber:"2"},
                {tag:"individual-printing", shared:false, empty:false, expectedSet:"AAA", expectedNumber:"3"},
                {tag:"missing-catalog-printings", shared:false, empty:true, expectedSet:"", expectedNumber:""}]
    }

    function test_cubeBasicPrintingHasStableCatalogFallback(data) {
        mockWs.deckFormat = "limited"
        mockWs.sideboarding = true
        mockWs.gameFinished = true
        mockWs.sideboardState = {
            deadlineUnixMs:Date.now() + 300000,
            seats:[{seat:0, ready:false, mainboardCount:0, sideboardCount:40}],
            mainboard:[],
            sideboard:[{name:"Cube Card", count:40, setCode:"NO_BASICS", collectorNumber:"1"}]
        }
        const printings = {}
        if (data.shared) {
            for (const name of ["Plains", "Island", "Swamp", "Mountain", "Forest"])
                printings[name] = [{setCode:"ZZZ", collectorNumber:"9"}, {setCode:"SHARED", collectorNumber:"2"}]
        }
        printings["Swamp"] = data.empty ? [] : [
            {setCode:"ZZZ", collectorNumber:"9"}, {setCode:"AAA", collectorNumber:"12"},
            {setCode:"SHARED", collectorNumber:"2"}, {setCode:"AAA", collectorNumber:"3"}]
        mockCatalog.basicPrintings = printings
        const table = createTemporaryObject(tableComponent, tableHost, {width:1400, height:800})
        verify(table !== null)
        const basics = findChild(table, "sideboardBasicLandsPanel")
        basics.adjustLimitedBasic("Swamp", 1)
        compare(mockWs.lastSideboardMove.card.setCode, data.expectedSet)
        compare(mockWs.lastSideboardMove.card.collectorNumber, data.expectedNumber)
        // Catalog delivery order does not alter the chosen fallback printing.
        printings.Swamp.reverse()
        mockCatalog.basicPrintings = Object.assign({}, printings)
        basics.adjustLimitedBasic("Swamp", 1)
        compare(mockWs.lastSideboardMove.card.setCode, data.expectedSet)
        compare(mockWs.lastSideboardMove.card.collectorNumber, data.expectedNumber)
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
