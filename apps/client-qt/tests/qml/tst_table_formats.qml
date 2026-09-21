// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic
import QtTest
import "../../qml/components"

TestCase {
    id: testCase
    name: "TableFormats"
    when: windowShown

    property alias page: harness.page
    readonly property alias testWindow: harness.testWindowObject
    readonly property alias tableHost: harness.tableHostObject
    readonly property alias mockWs: harness.mockWsObject
    readonly property alias mockRoomSession: harness.mockRoomSessionObject
    readonly property alias mockGameSession: harness.mockGameSessionObject
    readonly property alias mockCatalog: harness.mockCatalogObject
    readonly property alias mockPreferences: harness.mockPreferencesObject
    readonly property alias mockLoader: harness.mockLoaderObject
    readonly property alias pageComponent: harness.pageComponentObject
    readonly property alias tableComponent: harness.tableComponentObject

    MatchLoadingTestHarness {
        id: harness
        testCase: testCase
    }

    function syncTestGameTable() {
        harness.syncTestGameTable()
    }

    function init() {
        Theme.uiTheme = "classic"
        TableBackgrounds.currentId = "default"
        verify(harness.reset())
    }

    function cleanup() {
        testTranslations.setLanguage("en")
        harness.cleanupHarness()
        Theme.uiScale = 1
        TableBackgrounds.currentId = "default"
    }

    function test_defaultRestoresOpaqueClassicBattlefield() {
        const table = createTemporaryObject(tableComponent, tableHost, {width: 1280, height: 800})
        verify(waitForRendering(table))
        const ownLane = findChild(table, "battlefieldZone0")
        const opponentLane = findChild(table, "battlefieldZone1")
        for (const background of ["default", "ink", "default"]) {
            TableBackgrounds.currentId = background
            for (const lane of [ownLane, opponentLane]) {
                verify(lane !== null)
                if (background === "default")
                    compare(lane.color, lane.isOwn ? Theme.primaryMuted : Theme.surfaceHover)
                else
                    verify(lane.color.a > 0 && lane.color.a < 1)
            }
        }
    }

    function test_sharedStackTrayMatchesRailWash() {
        const table = createTemporaryObject(tableComponent, tableHost, {width: 1280, height: 800})
        verify(waitForRendering(table))
        table.showSharedColumn = true
        const stack = findChild(table, "sharedZonesView")
        verify(stack !== null)
        compare(stack.color, Theme.surfaceMuted)
        Theme.uiTheme = "glass"
        compare(stack.color, Theme.tableRailFill)
        const dock = findChild(table, "ownZoneDock")
        verify(dock !== null)
        compare(dock.color, Theme.surfaceElevated)
        compare(dock.border.width, 1)
    }

    function test_zoneTitlesUseChineseTranslations() {
        testTranslations.setLanguage("zh")
        const table = tableComponent.createObject(tableHost, {width: 1280, height: 800})
        waitForRendering(table)
        compare(findChild(table, "graveyardDropArea0").parent.zoneTitle, "墓地")
        compare(findChild(table, "exileDropArea0").parent.zoneTitle, "放逐区")
    }

    function test_playerTurnCountsArePublicAndUpdateFromSnapshots_data() {
        return [{tag: "two-players", count: 2, viewer: 0, width: 1280, scale: 1},
                {tag: "four-players", count: 4, viewer: 1, width: 1000, scale: 1},
                {tag: "spectator", count: 4, viewer: -1, width: 1000, scale: 1},
                {tag: "compact-chinese", count: 2, viewer: 0, width: 900, scale: 1.5}]
    }

    function test_playerTurnCountsArePublicAndUpdateFromSnapshots(data) {
        Theme.uiScale = data.scale
        testTranslations.setLanguage("zh")
        mockWs.format = data.count > 2 ? "edh" : "modern"
        mockWs.seatIndex = data.viewer
        mockWs.roomRole = data.viewer < 0 ? "spectator" : "player"
        const seats = []
        for (let index = 0; index < data.count; ++index) {
            const seat = JSON.parse(JSON.stringify(mockWs.baselineGameSeats[index % 2]))
            seat.seat = index
            seat.displayName = "Player " + index
            seat.turnCount = index === 0 ? 1 : 0
            seat.battlefield = []
            seats.push(seat)
        }
        mockWs.turnOrder = seats.map(seat => seat.seat)
        mockWs.gameSeats = seats
        const table = createTemporaryObject(tableComponent, tableHost,
                                             {width: data.width, height: 720})
        verify(waitForRendering(table))
        for (const seat of seats) {
            const label = findChild(table, "playerTurnCount" + seat.seat)
            verify(label !== null && label.visible)
            compare(label.text, "回合 " + seat.turnCount)
            const zone = findChild(table, "battlefieldZone" + seat.seat)
            const point = label.mapToItem(zone, 0, 0)
            verify(point.x >= 0 && point.y >= 0)
            verify(point.x + label.width <= zone.width + 1)
            verify(point.y + label.height <= zone.height + 1)
        }
        const nextSeats = JSON.parse(JSON.stringify(seats))
        nextSeats[1].turnCount = 1
        mockWs.gameSeats = nextSeats
        tryCompare(findChild(table, "playerTurnCount1"), "text", "回合 1")
        compare(findChild(table, "playerTurnCount0").text, "回合 1")
    }

    function test_tokenBadgeStaysCompactAndExplainsItselfOnHover() {
        testTranslations.setLanguage("zh")
        const seats = JSON.parse(JSON.stringify(mockWs.gameSeats))
        seats[0].battlefield = [{id: "token-1", name: "Soldier", token: true,
                                 ownerSeat: 0, position: {x: 0.35, y: 0.5}}]
        const table = createTemporaryObject(tableComponent, tableHost, {width: 1280, height: 800})
        mockWs.gameSeats = seats
        verify(waitForRendering(table))
        const badge = findChild(table, "battlefieldTokenBadgetoken-1")
        verify(badge !== null && badge.visible)
        compare(badge.Accessible.name, "衍生物")
        compare(badge.width, Theme.size(18))
        mouseMove(badge, badge.width / 2, badge.height / 2)
        tryCompare(badge.ToolTip, "visible", true)
        compare(badge.ToolTip.text, "衍生物")
        const updated = JSON.parse(JSON.stringify(seats))
        updated[0].battlefield[0].token = false
        mockWs.gameSeats = updated
        tryVerify(() => !findChild(table, "battlefieldTokenBadgetoken-1").visible)
    }

    function test_emblemsStayPublicAndDoNotReserveBattlefieldSpace_data() {
        return [{tag:"modern-two",format:"modern",count:2,viewer:0,focus:false},
                {tag:"commander-two",format:"edh",count:2,viewer:1,focus:false},
                {tag:"commander-three",format:"edh",count:3,viewer:0,focus:false},
                {tag:"commander-four-focus",format:"edh",count:4,viewer:0,focus:true},
                {tag:"spectator",format:"edh",count:4,viewer:-1,focus:false}]
    }

    function test_emblemsStayPublicAndDoNotReserveBattlefieldSpace(data) {
        mockWs.format = data.format
        mockWs.seatIndex = data.viewer
        mockWs.roomRole = data.viewer < 0 ? "spectator" : "player"
        const seats = []
        for (let seat = 0; seat < data.count; ++seat) {
            const source = JSON.parse(JSON.stringify(mockWs.baselineGameSeats[seat % 2]))
            source.seat = seat
            source.displayName = "Player " + seat
            source.emblems = [{id:"s"+seat+"-e1",name:"Teferi Emblem",setCode:"TCMM",collectorNumber:"79",typeLine:"Emblem"}]
            source.battlefield = []
            seats.push(source)
        }
        mockWs.turnOrder = seats.map(seat => seat.seat)
        mockWs.gameSeats = seats
        const table = createTemporaryObject(tableComponent, tableHost,{width:1000,height:720})
        verify(table !== null)
        if (data.focus) table.battlefieldLayout.focusSeat(data.viewer)
        verify(waitForRendering(table))
        for (const seat of seats) {
            const button = findChild(table,"emblemZoneButton"+seat.seat)
            verify(button !== null && button.visible)
            const zone = findChild(table,"battlefieldZone"+seat.seat)
            const point = button.mapToItem(zone,0,0)
            verify(point.x>=0 && point.y>=0)
            verify(point.x+button.width<=zone.width+1 && point.y+button.height<=zone.height+1)
            const size = table.battlefieldScene.battlefieldSize(seat.seat)
            compare(size.height,zone.height-Theme.size(12))
            mouseClick(button)
            tryCompare(table.emblemBrowser,"opened",true)
            verify(table.tableModalOpen)
            verify(findChild(table,"tableModalInputShield").visible)
            const handInteraction = findChild(table,"handCardInteraction0")
            if (handInteraction !== null) verify(!handInteraction.enabled)
            compare(table.emblemBrowser.emblems.length,1)
            compare(table.emblemBrowser.canRemove,data.viewer===seat.seat)
            table.emblemBrowser.close()
            tryCompare(table.emblemBrowser,"opened",false)
        }
        table.emblemBrowser.showSeat(0)
        tryCompare(table.emblemBrowser,"opened",true)
        mockWs.gameRestarted()
        tryCompare(table.emblemBrowser,"opened",false)
        if (data.viewer >= 0) {
            table.tokenPicker.open()
            tryCompare(table.tokenPicker,"opened",true)
            table.tokenPicker.detailsPopup.showCard(seats[0].emblems[0])
            tryCompare(table.tokenPicker.detailsPopup,"opened",true)
            verify(table.tableModalOpen)
            verify(findChild(table,"tableModalInputShield").visible)
            mockWs.gameRestarted()
            tryCompare(table.tokenPicker,"opened",false)
            tryCompare(table.tokenPicker.detailsPopup,"opened",false)
            tryCompare(table,"tableModalOpen",false)
        }
    }

    function test_largeScaleTableNavigation_data() {
        return [{tag: "modern", format: "modern"}, {tag: "commander", format: "edh"}]
    }

    function test_largeScaleTableNavigation(data) {
        Theme.uiScale = 1.5
        mockWs.format = data.format
        const table = createTemporaryObject(tableComponent, tableHost, {width: 900, height: 620})
        verify(table !== null)
        verify(waitForRendering(table))
        const selector = findChild(table, "compactPhaseSelector")
        verify(selector.visible)
        compare(selector.count, 11)
        for (const name of ["tableSettingsButton", "tableShortcutHelpButton",
                            "restoreGameLogRailButton", "leaveRoomButton", "nextTurnButton"]) {
            const control = findChild(table, name)
            const point = control.mapToItem(table, 0, 0)
            verify(point.y >= 0 && point.y + control.height <= table.height + 1, name)
        }
        const restore = findChild(table, "restoreGameLogRailButton")
        verify(restore.mapToItem(table, 0, 0).x + restore.width <= table.actionRailWidth)
        mouseClick(restore)
        tryCompare(table, "showGameLogRail", true)
    }

    function test_ownDockControlsFitMinimumWindow_data() {
        return [{tag: "modern", partner: false}, {tag: "partner-commanders", partner: true}]
    }

    function test_revealGroupsFitSharedRail() {
        const originalStack = mockWs.gameStack
        const originalRevealed = mockWs.gameRevealed
        try {
            Theme.uiScale = 1.5
            mockWs.gameStack = []
            mockWs.gameRevealed = [
                {id: "reveal-a", name: "Forest", ownerSeat: 0},
                {id: "reveal-b", name: "Island", ownerSeat: 1}
            ]
            const seats = JSON.parse(JSON.stringify(mockWs.gameSeats))
            seats[0].displayName = "Player with a very long display name"
            mockWs.gameSeats = seats
            const table = createTemporaryObject(tableComponent, tableHost, {width: 900, height: 620})
            verify(table !== null)
            table.showSharedColumn = true
            verify(waitForRendering(table))
            const rail = findChild(table, "sharedZonesView")
            const label = findChild(table, "revealDividerLabel0")
            verify(label !== null)
            verify(label.width > 0)
            const position = label.mapToItem(rail, 0, 0)
            verify(position.x >= 0 && position.x + label.width <= rail.width)
            verify(label.lineCount <= 2)
            table.sharedZones.selectCard(table.revealedCards[0], "reveal")
            for (const name of ["sharedToBattlefieldButton", "sharedToGraveyardButton", "sharedToHandButton"]) {
                const button = findChild(table, name)
                verify(button.visible)
                verify(button.contentItem.width >= button.contentItem.implicitWidth, name)
                mouseClick(button)
                compare(mockWs.lastMove.cardId, "reveal-a")
                table.optimisticCommandModel.pendingCardMoves = ({})
                table.sharedZones.selectCard(table.revealedCards[0], "reveal")
            }
        } finally {
            mockWs.gameStack = originalStack
            mockWs.gameRevealed = originalRevealed
        }
    }

    function test_ownDockControlsFitMinimumWindow(data) {
        if (data.partner) {
            mockWs.format = "edh"
            const seats = JSON.parse(JSON.stringify(mockWs.gameSeats))
            seats[0].commandZone = [
                {id: "commander-a", name: "Tymna the Weaver", commander: true},
                {id: "commander-b", name: "Thrasios, Triton Hero", commander: true}
            ]
            seats[0].commanderTaxes = {"commander-a": 0, "commander-b": 0}
            mockWs.gameSeats = seats
        }
        const table = tableComponent.createObject(tableHost, {width: 900, height: 620})
        verify(table !== null)
        waitForRendering(table)
        const dock = findChild(table, "ownZoneDock")
        for (const name of ["decreaseLifeButton0", "setLifeButton0", "increaseLifeButton0",
                            "graveyardDropArea0", "exileDropArea0"]) {
            const control = findChild(table, name)
            verify(control !== null, name)
            const origin = control.mapToItem(dock, 0, 0)
            const end = control.mapToItem(dock, control.width, control.height)
            verify(origin.x >= 0 && origin.y >= 0 && end.x <= dock.width + 1
                   && end.y <= dock.height + 1, name + " must fit within the dock")
            verify(control.mapToItem(table, control.width, 0).x <= table.width)
        }
        const counters = findChild(table, "ownPlayerCounters")
        const library = findChild(table, "ownLibraryZone")
        verify(counters.visible && counters.height > 0)
        verify(counters.mapToItem(dock, 0, counters.height).y
               <= library.mapToItem(dock, 0, 0).y,
               "Counter controls must not overlap the clickable zone piles")
        if (data.partner) {
            const tax = findChild(table, "increaseCommanderTaxButton0-1")
            const increaseLife = findChild(table, "increaseLifeButton0")
            verify(tax !== null, "increaseCommanderTaxButton0-1")
            verify(tax.visible && tax.enabled)
            const origin = tax.mapToItem(dock, 0, 0)
            const end = tax.mapToItem(dock, tax.width, tax.height)
            verify(origin.x >= 0 && origin.y >= 0 && end.x <= dock.width + 1
                   && end.y <= dock.height + 1)
            compare(Math.round(tax.mapToItem(dock, tax.width, 0).x),
                    Math.round(increaseLife.mapToItem(dock, increaseLife.width, 0).x))
            verify(library.height >= Theme.size(80) - 1,
                   "Partner tax rows must not shrink the zone piles below the reserved floor")
        }
    }

    function test_sideboardOverlayMovesCardsAndLocksReady() {
        mockWs.sideboarding = true
        mockWs.gameResult = {
            "reason": "concede",
            "winnerSeat": 1,
            "concededSeat": 0,
            "matchFinished": false
        }
        mockWs.gameFinished = true
        mockCatalog.typeLines = {
            "Mountain": "基本地 — 山脉",
            "Meltdown": "法术"
        }
        mockWs.sideboardState = {
            "deadlineUnixMs": Date.now() + 300000,
            "seats": [
                {"seat": 0, "ready": false,
                 "mainboardCount": 60, "sideboardCount": 15},
                {"seat": 1, "ready": true,
                 "mainboardCount": 60, "sideboardCount": 15}
            ],
            "mainboard": [{
                "name": "Lightning Bolt", "count": 2,
                "setCode": "M11", "collectorNumber": "149",
                "typeLine": "瞬间"
            }, {
                "name": "Lightning Bolt", "count": 1,
                "setCode": "2X2", "collectorNumber": "117",
                "typeLine": "Instant"
            }, {
                "name": "Faithless Looting", "count": 1,
                "setCode": "STA", "collectorNumber": "38",
                "typeLine": "法术"
            }, {
                "name": "Mountain", "count": 1,
                "setCode": "M21", "collectorNumber": "312",
                "typeLine": ""
            }],
            "sideboard": [{
                "name": "Wear // Tear", "count": 1,
                "setCode": "DGM", "collectorNumber": "135",
                "typeLine": "瞬间"
            }, {
                "name": "Meltdown", "count": 1,
                "setCode": "USG", "collectorNumber": "203",
                "typeLine": ""
            }]
        }
        const table = tableComponent.createObject(tableHost, {
            "width": testWindow.width,
            "height": testWindow.height
        })
        verify(table !== null)

        const panel = findChild(table, "sideboardPanel")
        verify(panel !== null)
        verify(panel.visible)
        const sideboardStatus = findChild(panel, "sideboardSeatStatus0")
        verify(sideboardStatus !== null)
        compare(findChild(panel, "sideboardSeatName0").text, "Alice")
        compare(sideboardStatus.text, "60+15 · Editing")
        compare(panel.cardCategory("生物 ～ 地精"), "Creature")
        const cardArt = findChild(panel, "sideboardCardArt-sideboard-0")
        const category = findChild(
                             panel,
                             "sideboardCategory-sideboard-Instant")
        const sorceryCategory = findChild(
                                    panel,
                                    "sideboardCategory-sideboard-Sorcery")
        const landCategory = findChild(
                               panel,
                               "sideboardCategory-mainboard-Land")
        const sideboardCard = findChild(panel, "sideboardCard-sideboard-0")
        const secondSideboardPile = findChild(
                                       panel,
                                       "sideboardCard-sideboard-1")
        const thirdMainboardPile = findChild(
                                      panel,
                                      "sideboardCard-mainboard-2")
        const lightningPileCount = findChild(
                                       panel,
                                       "sideboardPileCountText-mainboard-0")
        const mainboardZone = findChild(panel, "sideboardZone-mainboard")
        const sideboardZone = findChild(panel, "sideboardZone-sideboard")
        const boardTables = findChild(panel, "sideboardTables")
        const readyButton = findChild(panel, "sideboardReadyButton")
        const hoverPreview = findChild(panel, "sideboardHoverPreview")
        verify(cardArt !== null)
        verify(category !== null)
        verify(sorceryCategory !== null)
        verify(landCategory !== null)
        verify(sideboardCard !== null)
        verify(secondSideboardPile !== null)
        verify(thirdMainboardPile !== null)
        verify(lightningPileCount !== null)
        compare(lightningPileCount.text, "×3")
        const groupedMainboard = panel.categoryGroups(
                                     mockWs.sideboardState.mainboard)
        compare(groupedMainboard[0].category, "Instant")
        compare(groupedMainboard[0].count, 3)
        compare(groupedMainboard[0].cards.length, 1)
        compare(groupedMainboard[0].cards[0].pileCount, 3)
        verify(mainboardZone !== null)
        verify(sideboardZone !== null)
        verify(boardTables !== null)
        tryVerify(() => boardTables.width > 0 && boardTables.sideBySide)
        verify(readyButton !== null)
        verify(hoverPreview !== null)
        tryVerify(() => mainboardZone.mapToItem(panel, 0, 0).x
                        < sideboardZone.mapToItem(panel, 0, 0).x)
        tryVerify(() => category.mapToItem(panel, 0, 0).y
                        < sorceryCategory.mapToItem(panel, 0, 0).y)
        mouseMove(sideboardCard, sideboardCard.width / 2,
                  sideboardCard.height / 2)
        tryVerify(() => hoverPreview.visible)
        compare(panel.inspectedCard.name, "Wear // Tear")
        mouseMove(readyButton, readyButton.width / 2,
                  readyButton.height / 2)
        tryVerify(() => !hoverPreview.visible)
        const dragStart = sideboardCard.mapToItem(
                            null, 24,
                            sideboardCard.height / 2)
        const dragEnd = mainboardZone.mapToItem(
                          null, mainboardZone.width / 2,
                          mainboardZone.height / 2)
        mouseDrag(sideboardCard, 24,
                  sideboardCard.height / 2,
                  dragEnd.x - dragStart.x,
                  dragEnd.y - dragStart.y,
                  Qt.LeftButton, Qt.NoModifier, 30)
        tryCompare(mockWs, "sideboardMoveCount", 1)
        compare(mockWs.lastSideboardMove.card.name, "Wear // Tear")
        compare(mockWs.lastSideboardMove.fromZone, "sideboard")
        compare(mockWs.lastSideboardMove.toZone, "mainboard")

        readyButton.clicked()
        compare(mockWs.sideboardReadyCount, 1)
        verify(mockWs.lastSideboardReady)
        table.destroy()
    }

    function test_duelCommanderSideboardPhaseKeepsDeckFixed() {
        mockWs.format = "duel"
        mockWs.sideboarding = true
        mockWs.gameFinished = true
        mockWs.sideboardState = {
            "deadlineUnixMs": Date.now() + 300000,
            "seats": [
                {"seat": 0, "ready": false,
                 "mainboardCount": 100, "sideboardCount": 0},
                {"seat": 1, "ready": false,
                 "mainboardCount": 100, "sideboardCount": 0}
            ],
            "mainboard": [{
                "name": "Sol Ring", "count": 1,
                "setCode": "CMM", "collectorNumber": "396",
                "typeLine": "Artifact"
            }],
            "sideboard": [],
            "commanders": ["Sol Ring"]
        }
        // Keep the owner projection consistent with its public 100-card count.
        const fixedDeck = Object.assign({}, mockWs.sideboardState)
        fixedDeck.mainboard = fixedDeck.mainboard.concat([{
            "name": "Plains", "count": 99, "typeLine": "Basic Land"
        }])
        mockWs.sideboardState = fixedDeck
        const table = tableComponent.createObject(tableHost, {
            "width": testWindow.width,
            "height": testWindow.height
        })
        verify(table !== null)
        const panel = findChild(table, "sideboardPanel")
        const mainboardZone = findChild(panel, "sideboardZone-mainboard")
        const sideboardZone = findChild(panel, "sideboardZone-sideboard")
        const readyButton = findChild(panel, "sideboardReadyButton")
        const rulesHint = findChild(panel, "sideboardDeckRulesHint")
        const commanderToggle = findChild(panel, "sideboardCommanderToggle-0")
        verify(panel !== null)
        compare(panel.deckChangesAllowed, false)
        verify(mainboardZone !== null)
        verify(sideboardZone !== null)
        verify(mainboardZone.enabled)
        verify(!sideboardZone.enabled)
        // The locked deck is explained by visible header copy, and the
        // sideboard table is hidden rather than shown empty.
        verify(!sideboardZone.visible)
        verify(rulesHint !== null)
        verify(rulesHint.visible)
        verify(rulesHint.text.length > 0)
        verify(commanderToggle !== null)
        verify(readyButton !== null)
        verify(readyButton.enabled)
        readyButton.clicked()
        compare(mockWs.sideboardMoveCount, 0)
        compare(mockWs.sideboardReadyCount, 1)
        table.destroy()
    }

    function test_duelCommanderUsesTwoPlayerLayoutWithCommandZone() {
        mockWs.format = "duel"
        mockWs.matchMode = "bo3"
        mockWs.gameSeats = [
            {
                "seat": 0, "displayName": "Alice", "life": 20,
                "counters": [], "libraryCount": 92, "handCount": 7,
                "hand": [], "battlefield": [], "graveyard": [], "exile": [],
                "commandZone": [{
                    "id": "s0-c1", "name": "Yoshimaru, Ever Faithful",
                    "setCode": "NEC", "collectorNumber": "32"
                }],
                "commanderTax": 0, "eliminated": false
            },
            {
                "seat": 1, "displayName": "Bob", "life": 20,
                "counters": [], "libraryCount": 92, "handCount": 7,
                "hand": [], "battlefield": [], "graveyard": [], "exile": [],
                "commandZone": [{
                    "id": "s1-c1", "name": "Keleth, Sunmane Familiar",
                    "setCode": "CMR", "collectorNumber": "27"
                }],
                "commanderTax": 1, "eliminated": false
            }
        ]
        const table = tableComponent.createObject(tableHost, {
            "width": testWindow.width,
            "height": testWindow.height
        })
        verify(table !== null)
        const ownZone = findChild(table, "battlefieldZone0")
        const opponentZone = findChild(table, "battlefieldZone1")
        const ownCommand = findChild(table, "commandZoneButton0")
        const taxControls = findChild(table, "commanderTaxControls0")
        verify(ownZone !== null)
        verify(opponentZone !== null)
        verify(ownCommand !== null)
        verify(ownCommand.visible)
        verify(taxControls !== null)
        verify(taxControls.visible)
        compare(findChild(table, "edhGridLayoutButton"), null)
        compare(findChild(table, "edhFocusLayoutButton"), null)
        tryVerify(() => opponentZone.mapToItem(table, 0, 0).y
                        < ownZone.mapToItem(table, 0, 0).y)
        table.destroy()
    }

    function test_commanderLayoutFollowsGameSeatCount_data() {
        return [
            {tag: "commander-cube-seat-0", count: 2, seat: 0, role: "player", playtest: false},
            {tag: "commander-cube-seat-1", count: 2, seat: 1, role: "player", playtest: false},
            {tag: "commander-cube-spectator", count: 2, seat: -1, role: "spectator", playtest: false},
            {tag: "three-player", count: 3, seat: 1, role: "player", playtest: false},
            {tag: "four-player", count: 4, seat: 2, role: "player", playtest: false},
            {tag: "eliminated-seats-stay", count: 4, seat: 0, role: "player", playtest: false,
                eliminated: true},
            {tag: "commander-playtest", count: 1, seat: 0, role: "player", playtest: true}
        ]
    }

    function test_commanderLayoutFollowsGameSeatCount(data) {
        mockWs.format = "edh"
        mockWs.deckFormat = "commander_limited"
        mockWs.matchMode = "bo1"
        mockWs.seatIndex = data.seat
        mockWs.roomRole = data.role
        mockWs.playtest = data.playtest
        const seats = []
        for (let seat = 0; seat < data.count; ++seat) {
            seats.push({seat: seat, displayName: "Player " + seat, life: 40,
                counters: [], libraryCount: 53, handCount: 7, hand: [],
                battlefield: [], graveyard: [], exile: [],
                commandZone: [{id: "commander-" + seat, name: "The Prismatic Piper",
                    setCode: "CMR", collectorNumber: "1", commander: true}],
                commanderTaxes: {}, eliminated: data.eliminated === true && seat >= 2})
        }
        mockWs.turnOrder = seats.map(seat => seat.seat).reverse()
        mockWs.gameSeats = seats
        const table = createTemporaryObject(tableComponent, tableHost, {width: 1280, height: 800})
        verify(table !== null)
        tryCompare(table.battlefieldSeats, "length", data.count)
        verify(waitForRendering(table))
        compare(table.usesEDHBattlefieldLayout, data.count >= 3)
        compare(table.isCommanderFormat, true)
        for (let seat = 0; seat < data.count; ++seat)
            compare(table.seatState.seatData(seat).life, 40)
        if (data.role === "player") {
            verify(findChild(table, "commandZoneButton" + data.seat).visible)
            verify(findChild(table, "commanderTaxControls" + data.seat).visible)
        }
        if (data.count === 2) {
            const lowerSeat = data.role === "player" ? data.seat : 1
            const upperSeat = 1 - lowerSeat
            const lower = findChild(table, "battlefieldZone" + lowerSeat)
            const upper = findChild(table, "battlefieldZone" + upperSeat)
            tryVerify(() => upper.mapToItem(table, 0, upper.height).y
                            <= lower.mapToItem(table, 0, 0).y)
            compare(upper.mapToItem(table, 0, 0).x, lower.mapToItem(table, 0, 0).x)
            compare(upper.width, lower.width)
            verify(upper.width > table.width / 2)
            compare(table.battlefieldLayout.cardScale, 1)
            compare(table.battlefieldLayout.mirrorsSeat(upperSeat), true)
            compare(table.battlefieldLayout.mirrorsSeat(lowerSeat), false)
            const focus = findChild(table, "focusBattlefieldButton" + upperSeat)
            verify(focus === null || !focus.visible)
        } else if (data.playtest) {
            compare(table.battlefieldLayout.cardScale, 1)
            compare(table.battlefieldLayout.mirrorsSeat(0), false)
            compare(findChild(table, "battlefieldZone1"), null)
        } else {
            compare(table.battlefieldLayout.cardScale, data.count === 4 ? 0.7 : 0.8)
            verify(findChild(table, "focusBattlefieldButton" + data.seat).visible)
        }
    }

    function test_threePlayerEdhUsesWideLocalBattlefield() {
        const originalSeats = mockWs.gameSeats
        mockWs.format = "edh"
        mockWs.matchMode = "bo1"
        mockWs.turnOrder = [0, 1, 2]
        mockWs.gameSeats = [
            {
                "seat": 0, "displayName": "Alice", "life": 40,
                "counters": [], "libraryCount": 92, "handCount": 7,
                "hand": [], "battlefield": [], "graveyard": [], "exile": [],
                "commandZone": [], "commanderTax": 0, "eliminated": false
            },
            {
                "seat": 1, "displayName": "Bob", "life": 40,
                "counters": [], "libraryCount": 92, "handCount": 7,
                "battlefield": [], "graveyard": [], "exile": [],
                "commandZone": [], "commanderTax": 0, "eliminated": false
            },
            {
                "seat": 2, "displayName": "Carol", "life": 40,
                "counters": [], "libraryCount": 92, "handCount": 7,
                "battlefield": [], "graveyard": [], "exile": [],
                "commandZone": [], "commanderTax": 0, "eliminated": false
            }
        ]
        const table = tableComponent.createObject(tableHost, {
            "width": testWindow.width,
            "height": testWindow.height
        })
        verify(table !== null)
        tryVerify(() => table.battlefieldSeats.length === 3
                        && table.battlefieldSeats[0].seat === 1
                        && table.battlefieldSeats[1].seat === 2
                        && table.battlefieldSeats[2].seat === 0)
        tryVerify(() => {
            const own = findChild(table, "battlefieldZone0")
            const first = findChild(table, "battlefieldZone1")
            const second = findChild(table, "battlefieldZone2")
            return own !== null && first !== null && second !== null
                    && own.width > 0 && first.width > 0 && second.width > 0
        })
        const ownZone = findChild(table, "battlefieldZone0")
        const firstOpponent = findChild(table, "battlefieldZone1")
        const secondOpponent = findChild(table, "battlefieldZone2")
        const focusFirst = findChild(table, "focusBattlefieldButton1")
        verify(ownZone !== null)
        verify(firstOpponent !== null)
        verify(secondOpponent !== null)
        verify(focusFirst !== null)
        compare(findChild(table, "edhGridLayoutButton"), null)
        compare(findChild(table, "edhFocusLayoutButton"), null)
        tryVerify(() => firstOpponent.mapToItem(table, 0, 0).y
                        < ownZone.mapToItem(table, 0, 0).y)
        tryVerify(() => secondOpponent.mapToItem(table, 0, 0).y
                        < ownZone.mapToItem(table, 0, 0).y)
        tryVerify(() => firstOpponent.mapToItem(table, 0, 0).x
                        < secondOpponent.mapToItem(table, 0, 0).x)
        tryVerify(() => ownZone.width > firstOpponent.width * 1.8)
        tryVerify(() => Math.abs(firstOpponent.width
                                 - secondOpponent.width) < 3)

        focusFirst.clicked()
        tryCompare(table, "edhBattlefieldLayout", "focus")
        compare(focusFirst.text, "▦")
        tryVerify(() => firstOpponent.width > ownZone.width * 2.5)
        tryVerify(() => Math.abs(ownZone.height
                                 - secondOpponent.height) < 3)
        focusFirst.clicked()
        tryCompare(table, "edhBattlefieldLayout", "grid")
        compare(focusFirst.text, "▣")
        tryVerify(() => ownZone.width > firstOpponent.width * 1.8)

        table.destroy()
        mockWs.gameSeats = originalSeats
    }

    function test_playerChromeDoesNotReserveBattlefieldSpace_data() {
        return [
            {tag: "modern", format: "modern", scale: 1, width: 1280, height: 800},
            {tag: "two-player-edh", format: "edh", scale: 1, width: 1280, height: 800},
            {tag: "modern-compact", format: "modern", scale: 1.5, width: 900, height: 620},
            {tag: "two-player-edh-compact", format: "edh", scale: 1.5, width: 900, height: 620}
        ]
    }

    function test_playerChromeDoesNotReserveBattlefieldSpace(data) {
        Theme.uiScale = data.scale
        mockWs.format = data.format
        const table = createTemporaryObject(tableComponent, tableHost,
                                             {width: data.width, height: data.height})
        verify(waitForRendering(table))
        for (const showStatus of [false, true]) {
            const seats = JSON.parse(JSON.stringify(mockWs.gameSeats))
            for (const seat of seats)
                seat.responseStatus = showStatus ? "hold" : ""
            mockWs.gameSeats = seats
            verify(waitForRendering(table))
            for (const seat of seats) {
                const zone = findChild(table, "battlefieldZone" + seat.seat)
                const drop = findChild(table, seat.seat === 0 ? "battlefieldDropArea"
                                       : "opponentBattlefieldDropArea" + seat.seat)
                const point = drop.mapToItem(zone, 0, 0)
                compare(point.x, Theme.size(6))
                compare(point.y, Theme.size(6),
                        "Player name, turn and response badges must not reserve a top strip")
                compare(drop.width, zone.width - Theme.size(12))
                compare(drop.height, zone.height - Theme.size(12))
                const size = table.battlefieldScene.battlefieldSize(seat.seat)
                compare(size.width, drop.width)
                compare(size.height, drop.height)
            }
        }
    }

    function test_responseSignalsRemainVisibleInCompactMultiplayer() {
        Theme.uiScale = 1.5
        mockWs.format = "edh"
        const seats = []
        for (let seat = 0; seat < 4; ++seat) {
            seats.push({seat: seat, displayName: "Player with a long name " + seat,
                life: 40, handCount: 7, libraryCount: 53, hand: [], battlefield: [],
                counters: [], graveyard: [], exile: [], commandZone: [],
                responseStatus: seat % 2 === 0 ? "hold" : "pass"})
            seats[seat].battlefield = [{id: "lane-card-"+seat, name: "Forest",
                ownerSeat: seat, tapped: true, position:{x:0,y:seat%2}}]
        }
        mockWs.gameSeats = seats
        mockWs.turnOrder = [0, 1, 2, 3]
        const table = createTemporaryObject(tableComponent, tableHost, {width: 900, height: 620})
        verify(waitForRendering(table))
        for (const focused of [false, true]) {
            if (focused) table.battlefieldLayout.focusSeat(0)
            verify(waitForRendering(table))
            for (const seat of seats) {
                const zone = findChild(table, "battlefieldZone" + seat.seat)
                const name = findChild(table, "battlefieldPlayerName" + seat.seat)
                const signal = findChild(table, "responseStatusBadge" + seat.seat)
                verify(signal.visible, "Other players must see pass/hold state")
                compare(signal.text, seat.responseStatus === "hold" ? "Wait" : "Passed")
                verify(name.width >= Theme.size(24), "Player names retain usable width: "
                       + name.width + " in " + zone.width + ", focused=" + focused)
                const signalPoint = signal.mapToItem(zone, 0, 0)
                verify(signalPoint.x >= 0 && signalPoint.x + signal.width <= zone.width + 1,
                       "Response signal stays within its own battlefield")
                verify(name.mapToItem(zone, 0, name.height).y <= signalPoint.y,
                       "Narrow battlefields place status below player identity")
                const card = findChild(table, "battlefieldCardlane-card-"+seat.seat)
                verify(card.height > 0, "A compact lane retains a visible card thumbnail; zone="
                       + zone.height + ", viewport=" + card.zoneArea.height + ", seat=" + seat.seat)
                compare(card.width, card.zoneArea.cardWidth,
                        "Rendering and drop coordinates share the lane's card dimensions")
                compare(card.height, card.zoneArea.cardHeight)
                verify(card.height <= card.zoneArea.height + 1,
                       "Focus-lane cards must not spill into adjacent battlefields")
                compare(card.zoneArea.mapToItem(zone, 0, 0).y, Theme.size(6),
                        "Compact headers must also float over the full card viewport")
                compare(card.zoneArea.height, zone.height - Theme.size(12))
                verify(card.y >= 0 && card.y + card.height <= card.zoneArea.height + 1,
                       "Cards may use the top strip but must stay within their lane")
                const paintedLeft = card.x - (card.height-card.width)/2
                verify(paintedLeft >= -1 && paintedLeft + card.height <= card.zoneArea.width + 1,
                       "Tapped cards stay inside their lane even at the left edge")
            }
            table.cardMoveCommands.beginBattlefieldPreviewForCard(
                        "pending-lane-card", "hand", 0, {name: "Forest", tapped: true}, 1, 0, 1)
            verify(waitForRendering(table))
            const pending = findChild(table, "opponentPendingBattlefieldCard1")
            const reference = findChild(table, "battlefieldCardlane-card-1")
            compare(pending.width, reference.width)
            compare(pending.height, reference.height)
            verify(pending.height <= pending.parent.height + 1,
                   "Slow-network optimistic cards also fit a compact lane")
            const pendingZone = findChild(table, "battlefieldZone1")
            compare(pending.parent.mapToItem(pendingZone, 0, 0).y, Theme.size(6))
            compare(pending.parent.height, pendingZone.height - Theme.size(12))
            verify(pending.y >= 0 && pending.y + pending.height <= pending.parent.height + 1,
                   "Optimistic cards share the full lane viewport")
            verify(pending.x - pending.tappedEdgeInset >= -1
                   && pending.x + pending.width + pending.tappedEdgeInset <= pending.parent.width + 1,
                   "Tapped optimistic cards retain their complete rotated bounds")
            table.optimisticCommandModel.clear()
        }
        seats[1].responseStatus = ""
        mockWs.gameSeats = JSON.parse(JSON.stringify(seats))
        tryVerify(() => !findChild(table, "responseStatusBadge1").visible)
    }

    function test_edhShowsFourBattlefieldsCommandZoneAndTax() {
        const originalSeats = mockWs.gameSeats
        mockWs.format = "edh"
        mockWs.matchMode = "bo1"
        mockWs.turnOrder = [0, 1, 2, 3]
        mockWs.gameSeats = [
            {
                "seat": 0, "displayName": "Alice", "life": 40,
                "counters": [], "libraryCount": 92, "handCount": 7,
                "hand": [], "battlefield": [], "graveyard": [], "exile": [],
                "commandZone": [{
                    "id": "s0-c1", "name": "Atraxa, Praetors' Voice",
                    "setCode": "C16", "collectorNumber": "28",
                    "commander": true
                }, {
                    "id": "s0-c2", "name": "Tymna the Weaver",
                    "setCode": "C16", "collectorNumber": "48",
                    "commander": true
                }],
                "commanderTax": 0,
                "commanderTaxes": {"s0-c1": 0, "s0-c2": 3},
                "eliminated": false
            },
            {
                "seat": 1, "displayName": "Bob", "life": 40,
                "counters": [], "libraryCount": 92, "handCount": 7,
                "battlefield": [{
                    "id": "s1-commander", "name": "Thrasios, Triton Hero",
                    "setCode": "C16", "collectorNumber": "46",
                    "ownerSeat": 1, "commander": true,
                    "position": {"x": 0.3, "y": 0.4}
                }], "graveyard": [], "exile": [],
                "commandZone": [{
                    "id": "s1-c1", "name": "Muldrotha, the Gravetide",
                    "setCode": "DOM", "collectorNumber": "199"
                }],
                "commanderTax": 1, "eliminated": false
            },
            {
                "seat": 2, "displayName": "Carol", "life": 0,
                "counters": [], "libraryCount": 80, "handCount": 5,
                "battlefield": [], "graveyard": [], "exile": [],
                "commandZone": [], "commanderTax": 0, "eliminated": true
            },
            {
                "seat": 3, "displayName": "Dan", "life": 40,
                "counters": [], "libraryCount": 92, "handCount": 7,
                "battlefield": [], "graveyard": [], "exile": [],
                "commandZone": [], "commanderTax": 0, "eliminated": false
            }
        ]
        const table = tableComponent.createObject(tableHost, {
            "width": testWindow.width,
            "height": testWindow.height
        })
        verify(table !== null)
        const ownDock = findChild(table, "ownZoneDock")
        verify(ownDock !== null)
        verify(ownDock.visible)
        for (let seat = 0; seat < 4; ++seat)
            verify(findChild(table, "battlefieldZone" + seat) !== null)
        const seat0Zone = findChild(table, "battlefieldZone0")
        const seat1Zone = findChild(table, "battlefieldZone1")
        const seat2Zone = findChild(table, "battlefieldZone2")
        const seat3Zone = findChild(table, "battlefieldZone3")
        tryVerify(() => {
            const seat0Point = seat0Zone.mapToItem(table, 0, 0)
            const seat1Point = seat1Zone.mapToItem(table, 0, 0)
            const seat2Point = seat2Zone.mapToItem(table, 0, 0)
            const seat3Point = seat3Zone.mapToItem(table, 0, 0)
            return seat1Point.x < seat2Point.x
                    && seat1Point.y < seat0Point.y
                    && seat0Point.x < seat3Point.x
                    && seat2Point.y < seat3Point.y
        })
        verify(findChild(table, "battlefieldOwner0") === null)
        verify(findChild(table, "battlefieldOwner1") === null)
        const expectedPlayerNames = ["Alice", "Bob", "Carol", "Dan"]
        for (let seat = 0; seat < 4; ++seat) {
            const playerName = findChild(
                                   table, "battlefieldPlayerName" + seat)
            verify(playerName !== null)
            verify(playerName.visible)
            compare(playerName.text, expectedPlayerNames[seat])
        }
        for (let seat = 1; seat < 4; ++seat) {
            const opponentDock = findChild(
                                     table, "opponentZoneDock" + seat)
            const toggle = findChild(table, "opponentZoneToggle" + seat)
            verify(opponentDock === null)
            verify(toggle !== null)
        }
        const battlefieldCommanderBadge =
            findChild(table, "battlefieldCommanderBadges1-commander")
        verify(battlefieldCommanderBadge !== null)
        verify(battlefieldCommanderBadge.visible)
        const firstOpponentToggle = findChild(table, "opponentZoneToggle1")
        const secondOpponentToggle = findChild(table, "opponentZoneToggle2")
        const thirdOpponentToggle = findChild(table, "opponentZoneToggle3")
        const panelLayer = findChild(table, "opponentZonePanelLayer")
        verify(panelLayer !== null)
        firstOpponentToggle.clicked()
        secondOpponentToggle.clicked()
        thirdOpponentToggle.clicked()
        tryVerify(() => findChild(table, "opponentZoneDock1") !== null)
        tryVerify(() => findChild(table, "opponentZoneDock2") !== null
                        && findChild(table, "opponentZoneDock3") !== null)
        const firstOpponentDock = findChild(table, "opponentZoneDock1")
        const secondOpponentDock = findChild(table, "opponentZoneDock2")
        const thirdOpponentDock = findChild(table, "opponentZoneDock3")
        const opponentCommand =
            findChild(table, "commandZoneButton1")
        const opponentCommanderArt =
            findChild(table, "opponentCommanderCard1")
        verify(firstOpponentDock.parent.parent === panelLayer)
        verify(opponentCommand !== null)
        verify(opponentCommanderArt !== null)
        verify(firstOpponentDock.width <= 184)
        verify(firstOpponentDock.height > 100)
        const opponentDocks = [firstOpponentDock, secondOpponentDock,
                               thirdOpponentDock]
        const opponentZones = [seat1Zone, seat2Zone, seat3Zone]
        tryVerify(() => {
            for (let index = 0; index < opponentDocks.length; ++index) {
                const dock = opponentDocks[index]
                const zone = opponentZones[index]
                const dockPoint = dock.mapToItem(table, 0, 0)
                const zonePoint = zone.mapToItem(table, 0, 0)
                const rightInset = zonePoint.x + zone.width
                                   - dockPoint.x - dock.width
                const bottomInset = zonePoint.y + zone.height
                                    - dockPoint.y - dock.height
                if (rightInset < 4 || rightInset > 20
                        || bottomInset < 4 || bottomInset > 20) {
                    return false
                }
            }
            return true
        })
        const firstOpponentName = findChild(
                                      table, "opponentDisplayName1")
        verify(firstOpponentName !== null)
        compare(firstOpponentName.text, "Bob")
        tryVerify(() => opponentCommanderArt.visible)

        const firstPanelHandle = findChild(
                                     table,
                                     "opponentZonePanelDragHandle1")
        verify(firstPanelHandle !== null)
        const firstPositionBeforeDrag = firstOpponentDock.mapToItem(
                                            table, 0, 0)
        const secondPositionBeforeDrag = secondOpponentDock.mapToItem(
                                             table, 0, 0)
        mouseDrag(firstPanelHandle,
                  firstPanelHandle.width / 2,
                  firstPanelHandle.height / 2,
                  -100, 30, Qt.LeftButton, Qt.NoModifier, 30)
        tryVerify(() => firstOpponentDock.mapToItem(table, 0, 0).x
                        < firstPositionBeforeDrag.x - 70)
        compare(secondOpponentDock.mapToItem(table, 0, 0).x,
                secondPositionBeforeDrag.x)
        firstOpponentToggle.clicked()
        tryVerify(() => findChild(table, "opponentZoneDock1") === null)
        verify(secondOpponentDock.visible && thirdOpponentDock.visible)
        secondOpponentToggle.clicked()
        thirdOpponentToggle.clicked()
        tryVerify(() => findChild(table, "opponentZoneDock2") === null
                        && findChild(table, "opponentZoneDock3") === null)

        const commandButton = findChild(table, "commandZoneButton0")
        const ownCommanderArt = findChild(table, "ownCommanderCard0")
        const secondCommanderArt = findChild(table, "ownCommanderCard0-1")
        const commanderDragCard = findChild(table, "commanderDragCard0")
        const commandDropArea = findChild(table, "commandDropArea0")
        const commanderZoneLabel = findChild(table, "commanderZoneLabel0")
        const commanderTaxControls = findChild(table, "commanderTaxControls0")
        const commanderTaxLabel = findChild(table, "commanderTaxLabel0")
        const secondCommanderTaxLabel = findChild(table,
                                                   "commanderTaxLabel0-1")
        const commanderTaxValue = findChild(table, "commanderTaxValue0")
        const secondCommanderTaxValue = findChild(table, "commanderTaxValue0-1")
        const commanderZoneBadge = findChild(table, "commanderZoneBadge0")
        const castButton = findChild(table, "castCommanderButton0")
        const decreaseTaxButton = findChild(table,
                                            "decreaseCommanderTaxButton0")
        const taxButton = findChild(table, "increaseCommanderTaxButton0")
        const decreaseLifeButton = findChild(table, "decreaseLifeButton0")
        const lifeButton = findChild(table, "setLifeButton0")
        const increaseLifeButton = findChild(table, "increaseLifeButton0")
        const concedeButton = findChild(table, "concedeAction")
        verify(commandButton !== null)
        verify(ownCommanderArt !== null)
        verify(ownCommanderArt.visible)
        verify(secondCommanderArt !== null)
        verify(secondCommanderArt.visible)
        verify(commanderDragCard !== null)
        verify(commandDropArea !== null)
        verify(commanderZoneLabel !== null)
        compare(commanderZoneLabel.text, "Command 2")
        verify(commanderTaxControls !== null)
        verify(commanderTaxControls.visible)
        verify(commanderTaxLabel !== null)
        verify(secondCommanderTaxLabel !== null)
        compare(commanderTaxLabel.text, "Atraxa")
        compare(secondCommanderTaxLabel.text, "Tymna the Weaver")
        const secondCommanderTaxControls = findChild(
                                               table, "commanderTaxControls0-1")
        verify(secondCommanderTaxControls !== null)
        verify(secondCommanderTaxControls.mapToItem(ownDock, 0, 0).y
               >= commanderTaxControls.mapToItem(ownDock, 0, 0).y
                  + commanderTaxControls.height)
        verify(commanderTaxControls.width > ownDock.width * 0.6)
        verify(secondCommanderTaxControls.width > ownDock.width * 0.6)
        verify(!commanderTaxLabel.truncated)
        verify(!secondCommanderTaxLabel.truncated)
        verify(commanderTaxValue !== null)
        verify(secondCommanderTaxValue !== null)
        compare(secondCommanderTaxValue.text, "6")
        verify(commanderZoneBadge !== null)
        verify(commanderZoneBadge.y + commanderZoneBadge.height
               <= commanderZoneBadge.cardVisualBottom + 1)
        // Compact piles may fit the card by height, without letterboxing.
        verify(commanderZoneBadge.cardVisualBottom
               <= commanderZoneBadge.parent.height)
        verify(decreaseTaxButton !== null)
        verify(taxButton !== null)
        verify(decreaseLifeButton !== null)
        verify(lifeButton !== null)
        verify(increaseLifeButton !== null)
        compare(commanderTaxValue.font.pixelSize,
                lifeButton.font.pixelSize)
        compare(decreaseTaxButton.width, decreaseLifeButton.width)
        compare(decreaseTaxButton.height, decreaseLifeButton.height)
        compare(taxButton.width, increaseLifeButton.width)
        compare(taxButton.height, increaseLifeButton.height)
        compare(Math.round(taxButton.mapToItem(ownDock, taxButton.width, 0).x),
                Math.round(increaseLifeButton.mapToItem(
                               ownDock, increaseLifeButton.width, 0).x))
        verify(castButton === null)
        verify(concedeButton !== null)
        verify(taxButton.enabled)
        const commandBrowser = findChild(table, "publicZoneBrowserPopup")
        const castCommanderAction = findChild(
                                        commandBrowser,
                                        "zoneCardCastCommander")
        verify(commandBrowser !== null)
        verify(castCommanderAction !== null)
        commandBrowser.showZone("Alice", 0, "command")
        tryVerify(() => commandBrowser.opened)
        compare(commandBrowser.selectedCard.id, "s0-c1")
        verify(castCommanderAction.enabled)
        castCommanderAction.triggered()
        compare(mockWs.commanderCastCount, 1)
        compare(mockWs.lastCommanderCastId, "s0-c1")
        compare(commandButton.cardAt(0).id, "s0-c1")
        compare(commandButton.cardAt(commandButton.width).id, "s0-c2")
        commandButton.selectedCard = Object.assign(
                    {}, commandButton.cardAt(commandButton.width))
        compare(commanderDragCard.cardId, "s0-c2")
        compare(commanderDragCard.zoneName, "command")
        verify(table.cardMoveCommands.canMoveToHand(commanderDragCard))
        verify(table.cardMoveCommands.moveDroppedCardToBattlefield(
                   commanderDragCard, 0, 0.5, 0.25))
        compare(mockWs.moveCount, 1)
        compare(mockWs.lastMove.cardId, "s0-c2")
        compare(mockWs.lastMove.fromZone, "command")
        compare(mockWs.lastMove.toZone, "battlefield")
        const returnDrop = {
            "source": {
                "cardId": "s0-c2",
                "zoneName": "battlefield",
                "ownerSeat": 0,
                "zoneSeat": 0,
                "modelData": {
                    "id": "s0-c2",
                    "name": "Tymna the Weaver",
                    "ownerSeat": 0,
                    "commander": true
                }
            },
            "accepted": false,
            "acceptProposedAction": function() {
                this.accepted = true
            }
        }
        table.cardMoveCommands.finishPublicZoneDrop(commandDropArea, returnDrop,
                                   "command", 0)
        compare(mockWs.moveCount, 2)
        compare(mockWs.lastMove.cardId, "s0-c2")
        compare(mockWs.lastMove.fromZone, "battlefield")
        compare(mockWs.lastMove.toZone, "command")
        compare(mockWs.lastMove.toSeat, -1)
        verify(returnDrop.accepted)
        taxButton.clicked()
        compare(mockWs.commanderTaxCount, 1)
        compare(mockWs.lastCommanderTaxDelta, 1)

        const focusSeat2 =
            findChild(table, "focusBattlefieldButton2")
        const layoutControls = findChild(
                    table, "battlefieldLayoutControls")
        const layoutControl = findChild(
                    table, "battlefieldLayoutControlButton")
        const battlefieldArea = findChild(table, "battlefieldArea")
        const battlefieldGrid = findChild(table, "battlefieldGrid")
        const gameLogRail = findChild(table, "gameLogRail")
        const decreaseCardScale = findChild(
                    table, "decreaseBattlefieldCardScaleButton")
        const increaseCardScale = findChild(
                    table, "increaseBattlefieldCardScaleButton")
        const resetCardScale = findChild(
                    table, "resetBattlefieldCardScaleButton")
        verify(focusSeat2 !== null)
        verify(layoutControls !== null)
        verify(layoutControl !== null)
        verify(battlefieldArea !== null)
        verify(battlefieldGrid !== null)
        verify(gameLogRail !== null)
        compare(findChild(table, "edhGridLayoutButton"), null)
        compare(findChild(table, "edhFocusLayoutButton"), null)
        verify(decreaseCardScale !== null)
        verify(increaseCardScale !== null)
        verify(resetCardScale !== null)
        verify(!layoutControls.visible)
        verify(layoutControl.visible)
        verify(!increaseCardScale.visible)
        verify(battlefieldGrid.mapToItem(battlefieldArea, 0, 0).y < 8)
        const controlPosition = layoutControl.mapToItem(table, 0, 0)
        const logPosition = gameLogRail.mapToItem(table, 0, 0)
        verify(controlPosition.x >= logPosition.x,
               "control x=" + controlPosition.x
               + ", local x=" + layoutControl.x
               + ", overlay width=" + layoutControl.parent.width
               + ", log x=" + logPosition.x
               + ", log visible=" + gameLogRail.visible
               + ", saved=" + mockPreferences.tableBattlefieldControlX
               + "/" + mockPreferences.tableBattlefieldControlY)
        verify(controlPosition.x + layoutControl.width
               <= logPosition.x + gameLogRail.width + 1)
        layoutControl.clicked()
        tryVerify(() => layoutControls.visible
                        && increaseCardScale.visible)
        compare(table.battlefieldLayout.cardScale, 0.7)
        increaseCardScale.clicked()
        compare(mockPreferences.tableOverviewCardScale, 0.75)
        compare(table.battlefieldLayout.cardScale, 0.75)
        focusSeat2.clicked()
        tryCompare(table, "edhBattlefieldLayout", "focus")
        compare(table.edhFocusedSeat, 2)
        compare(table.battlefieldLayout.cardScale, 1.0)
        decreaseCardScale.clicked()
        compare(mockPreferences.tableFocusCardScale, 0.95)
        compare(table.battlefieldLayout.cardScale, 0.95)
        tryVerify(() => seat2Zone.width > seat0Zone.width)
        tryVerify(() => seat2Zone.height > seat0Zone.height)
        focusSeat2.clicked()
        tryCompare(table, "edhBattlefieldLayout", "grid")
        compare(table.battlefieldLayout.cardScale, 0.75)
        resetCardScale.clicked()
        compare(mockPreferences.tableOverviewCardScale, 0.0)
        compare(table.battlefieldLayout.cardScale, 0.7)
        layoutControl.clicked()
        tryVerify(() => !layoutControls.visible
                        && !increaseCardScale.visible)

        const positionBeforeDrag = layoutControl.mapToItem(table, 0, 0)
        mouseDrag(layoutControl,
                  layoutControl.width / 2, layoutControl.height / 2,
                  -120, 100, Qt.LeftButton, Qt.NoModifier, 30)
        tryVerify(() => mockPreferences.tableBattlefieldControlX >= 0
                        && mockPreferences.tableBattlefieldControlY >= 0)
        tryVerify(() => layoutControl.mapToItem(table, 0, 0).x
                        < positionBeforeDrag.x - 80)
        layoutControl.resetRequested()
        compare(mockPreferences.tableBattlefieldControlX, -1)
        compare(mockPreferences.tableBattlefieldControlY, -1)
        tryVerify(() => layoutControl.mapToItem(table, 0, 0).x
                        >= gameLogRail.mapToItem(table, 0, 0).x)

        table.sessionUi.setGameLogRailVisible(false)
        tryVerify(() => !gameLogRail.visible)
        tryVerify(() => {
            const fallback = layoutControl.mapToItem(table, 0, 0)
            return fallback.x + layoutControl.width >= table.width - 8
                   && Math.abs(fallback.y + layoutControl.height / 2
                               - table.height / 2) < 2
        })
        table.sessionUi.setGameLogRailVisible(true)
        tryVerify(() => gameLogRail.visible
                        && layoutControl.mapToItem(table, 0, 0).x
                           >= gameLogRail.mapToItem(table, 0, 0).x)

        const stableSeats = JSON.parse(JSON.stringify(mockWs.gameSeats))
        for (let revision = 0; revision < 8; ++revision) {
            const nextSeats = JSON.parse(JSON.stringify(stableSeats))
            for (let seat = 0; seat < nextSeats.length; ++seat) {
                nextSeats[seat].battlefield = []
                for (let card = 0; card < 6; ++card) {
                    nextSeats[seat].battlefield.push({
                        "id": "s" + seat + "-r" + revision + "-c" + card,
                        "name": "Plains",
                        "setCode": "FDN",
                        "collectorNumber": "273",
                        "ownerSeat": seat,
                        "position": {
                            "x": (card + 1) / 8,
                            "y": (seat + 1) / 6
                        }
                    })
                }
            }
            mockWs.gameSeats = nextSeats
            tryVerify(() => table.battlefieldScene.cardItems.size
                      === 24 + table.sharedCards.length)
        }
        const emptySeats = JSON.parse(JSON.stringify(stableSeats))
        for (let seat = 0; seat < emptySeats.length; ++seat)
            emptySeats[seat].battlefield = []
        mockWs.gameSeats = emptySeats
        tryVerify(() => table.battlefieldScene.cardItems.size
                  === table.sharedCards.length)

        table.destroy()
        mockWs.gameSeats = originalSeats
    }

    function test_compactTableNarrowsRailsAndExposesShortcutHelp() {
        const table = tableComponent.createObject(tableHost, {
            "width": 900,
            "height": 620
        })
        verify(table !== null)
        tryVerify(() => table.compactLayout)
        const actionRail = findChild(table, "tableActionRail")
        const gameLogRail = findChild(table, "gameLogRail")
        const shared = findChild(table, "sharedZonesView")
        const restore = findChild(table, "restoreGameLogRailButton")
        const helpButton = findChild(table, "tableShortcutHelpButton")
        const help = findChild(table, "tableShortcutHelp")
        verify(actionRail !== null)
        verify(gameLogRail !== null)
        verify(shared !== null)
        verify(restore !== null)
        verify(helpButton !== null)
        verify(help !== null)
        compare(actionRail.width, table.actionRailWidth)
        compare(table.actionRailWidth, 120)
        compare(table.sharedZoneRailWidth, 92)
        tryVerify(() => !gameLogRail.visible)
        tryVerify(() => !shared.visible)
        verify(restore.visible)
        verify(mockPreferences.tableShowGameLog)
        verify(mockPreferences.tableShowShared)
        restore.clicked()
        tryVerify(() => gameLogRail.visible)
        verify(mockPreferences.tableShowGameLog)
        compare(helpButton.text, "?")
        helpButton.clicked()
        tryVerify(() => help.opened)
        const list = findChild(help, "tableShortcutHelpList")
        verify(list !== null)
        verify(list.count > 8)
        table.destroy()
    }

    function test_librarySearchRemindsOwnerToShuffle() {
        const table = tableComponent.createObject(tableHost, {
            "width": testWindow.width,
            "height": testWindow.height
        })
        verify(table !== null)
        mockWs.dumpLibraryCount = 0
        mockWs.shuffleLibraryCount = 0
        mockWs.libraryDumped([{
            "id": "s0-lib1",
            "name": "Llanowar Elves",
            "setCode": "M19",
            "collectorNumber": "314"
        }], 0, "", 0)
        const popup = findChild(table, "librarySearchPopup")
        const reminder = findChild(table, "shuffleLibraryReminder")
        verify(popup !== null)
        verify(reminder !== null)
        tryVerify(() => popup.opened)
        verify(popup.offerShuffleOnClose)
        popup.close()
        tryVerify(() => reminder.opened)
        const confirm = findChild(reminder, "confirmButton")
        verify(confirm !== null)
        confirm.clicked()
        compare(mockWs.shuffleLibraryCount, 1)
        table.destroy()
    }

    function test_libraryTopSearchShufflesBeforePlacement() {
        const table = tableComponent.createObject(tableHost, {
            "width": testWindow.width,
            "height": testWindow.height
        })
        verify(table !== null)
        mockWs.libraryDumped([{
            "id": "s0-lib1",
            "name": "Llanowar Elves",
            "setCode": "M19",
            "collectorNumber": "314"
        }, {
            "id": "s0-lib2",
            "name": "Forest",
            "setCode": "M19",
            "collectorNumber": "277"
        }], 0, "", 0)
        const popup = findChild(table, "librarySearchPopup")
        const reminder = findChild(table, "shuffleLibraryReminder")
        verify(popup !== null)
        verify(reminder !== null)
        tryVerify(() => popup.opened)
        popup.toggleCard("s0-lib1")
        compare(popup.selectedCount, 1)
        popup.completeSearch("library_top", 0, false)

        tryVerify(() => !popup.opened)
        tryVerify(() => reminder.opened)
        compare(mockWs.shuffleLibraryCount, 0)
        compare(mockWs.searchLibraryCount, 0)

        const confirm = findChild(reminder, "confirmButton")
        verify(confirm !== null)
        confirm.clicked()
        tryCompare(mockWs, "searchLibraryCount", 1)
        compare(mockWs.shuffleLibraryCount, 1)
        compare(mockWs.libraryActionOrder.length, 2)
        compare(mockWs.libraryActionOrder[0], "shuffle")
        compare(mockWs.libraryActionOrder[1], "search")
        compare(mockWs.lastLibrarySearch.toZone, "library_top")
        compare(mockWs.lastLibrarySearch.cardIds.length, 1)
        compare(mockWs.lastLibrarySearch.cardIds[0], "s0-lib1")
        table.destroy()
    }

    function test_libraryTopSearchCanPlaceWithoutShuffle() {
        const table = tableComponent.createObject(tableHost, {
            "width": testWindow.width,
            "height": testWindow.height
        })
        verify(table !== null)
        mockWs.libraryDumped([{
            "id": "s0-lib1",
            "name": "Llanowar Elves",
            "setCode": "M19",
            "collectorNumber": "314"
        }], 0, "", 0)
        const popup = findChild(table, "librarySearchPopup")
        const reminder = findChild(table, "shuffleLibraryReminder")
        verify(popup !== null)
        verify(reminder !== null)
        tryVerify(() => popup.opened)
        popup.toggleCard("s0-lib1")
        popup.completeSearch("library_top", 0, false)

        tryVerify(() => reminder.opened)
        const cancel = findChild(reminder, "cancelButton")
        verify(cancel !== null)
        cancel.clicked()
        tryCompare(mockWs, "searchLibraryCount", 1)
        compare(mockWs.shuffleLibraryCount, 0)
        compare(mockWs.libraryActionOrder.length, 1)
        compare(mockWs.libraryActionOrder[0], "search")
        compare(mockWs.lastLibrarySearch.toZone, "library_top")
        table.destroy()
    }
}
