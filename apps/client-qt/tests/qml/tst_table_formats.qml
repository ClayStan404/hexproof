// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtTest

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
        verify(harness.reset())
    }

    function cleanup() {
        harness.cleanupHarness()
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
        compare(sideboardStatus.text, "Alice · 60+15 · Editing")
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

    function test_threePlayerEdhUsesWideLocalBattlefield() {
        const originalSeats = mockWs.gameSeats
        mockWs.format = "edh"
        mockWs.matchMode = "bo1"
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

    function test_edhShowsFourBattlefieldsCommandZoneAndTax() {
        const originalSeats = mockWs.gameSeats
        mockWs.format = "edh"
        mockWs.matchMode = "bo1"
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
            verify(opponentDock !== null)
            verify(toggle !== null)
            verify(!opponentDock.visible)
        }
        const opponentCommand =
            findChild(table, "commandZoneButton1")
        const opponentCommanderArt =
            findChild(table, "opponentCommanderCard1")
        verify(opponentCommand !== null)
        verify(opponentCommanderArt !== null)
        const battlefieldCommanderBadge =
            findChild(table, "battlefieldCommanderBadges1-commander")
        verify(battlefieldCommanderBadge !== null)
        verify(battlefieldCommanderBadge.visible)
        const firstOpponentDock = findChild(table, "opponentZoneDock1")
        const firstOpponentToggle = findChild(table, "opponentZoneToggle1")
        const secondOpponentDock = findChild(table, "opponentZoneDock2")
        const secondOpponentToggle = findChild(table, "opponentZoneToggle2")
        const thirdOpponentDock = findChild(table, "opponentZoneDock3")
        const thirdOpponentToggle = findChild(table, "opponentZoneToggle3")
        const panelLayer = findChild(table, "opponentZonePanelLayer")
        verify(panelLayer !== null)
        verify(firstOpponentDock.parent === panelLayer)
        firstOpponentToggle.clicked()
        secondOpponentToggle.clicked()
        thirdOpponentToggle.clicked()
        tryVerify(() => firstOpponentDock.visible)
        tryVerify(() => secondOpponentDock.visible
                        && thirdOpponentDock.visible)
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
        tryVerify(() => !firstOpponentDock.visible)
        verify(secondOpponentDock.visible && thirdOpponentDock.visible)
        secondOpponentToggle.clicked()
        thirdOpponentToggle.clicked()
        tryVerify(() => !secondOpponentDock.visible
                        && !thirdOpponentDock.visible)

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
        compare(commanderTaxLabel.text, "Tax · Atraxa")
        compare(secondCommanderTaxLabel.text, "Tax · Tymna the Weaver")
        verify(commanderTaxValue !== null)
        verify(secondCommanderTaxValue !== null)
        compare(secondCommanderTaxValue.text, "6")
        verify(commanderZoneBadge !== null)
        verify(commanderZoneBadge.y + commanderZoneBadge.height
               <= commanderZoneBadge.cardVisualBottom + 1)
        verify(commanderZoneBadge.cardVisualBottom
               < commanderZoneBadge.parent.height)
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
}
