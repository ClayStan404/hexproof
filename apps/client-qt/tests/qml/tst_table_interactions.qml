// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtTest

TestCase {
    id: testCase
    name: "TableInteractions"
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

    function test_arrangeBattlefieldStacksSameLaneAttachmentsAndSkipsCrossLane() {
        const arrangeSeats = JSON.parse(JSON.stringify(mockWs.gameSeats))
        arrangeSeats[0].battlefield = [{
            "id": "s0-bear",
            "name": "Grizzly Bears",
            "typeLine": "Creature — Bear",
            "ownerSeat": 0,
            "position": {"x": 0.20, "y": 0.50}
        }, {
            "id": "s0-aura",
            "name": "Pacifism",
            "typeLine": "Enchantment — Aura",
            "ownerSeat": 0,
            "position": {"x": 0.10, "y": 0.20}
        }, {
            "id": "s0-sword",
            "name": "Sword of Fire and Ice",
            "typeLine": "Artifact — Equipment",
            "ownerSeat": 0,
            "position": {"x": 0.15, "y": 0.25}
        }]
        mockWs.gameSeats = arrangeSeats
        mockWs.gameAttachments = [{
            "sourceCardId": "s0-aura",
            "targetCardId": "s0-bear"
        }, {
            "sourceCardId": "s0-sword",
            "targetCardId": "s1-c1"
        }]
        const table = tableComponent.createObject(tableHost, {
            "width": testWindow.width,
            "height": testWindow.height
        })
        verify(table !== null)

        const arrange = findChild(table, "arrangeBattlefieldAction")
        verify(arrange !== null)
        arrange.triggered()
        compare(mockWs.arrangeBattlefieldCount, 1)

        const placements = ({})
        for (let index = 0;
             index < mockWs.lastBattlefieldArrangement.length; ++index) {
            const placement = mockWs.lastBattlefieldArrangement[index]
            placements[placement.cardId] = placement.position
        }
        verify(placements["s0-bear"] !== undefined)
        verify(placements["s0-aura"] !== undefined)
        verify(placements["s0-sword"] === undefined)
        compare(placements["s0-aura"].x,
                Math.max(0, Math.min(1, placements["s0-bear"].x + 0.04)))
        compare(placements["s0-aura"].y,
                Math.max(0, Math.min(1, placements["s0-bear"].y + 0.05)))

        table.destroy()
    }

    function test_handAndBattlefieldContextMovesUsePublicZones() {
        const contextSeats = JSON.parse(JSON.stringify(mockWs.gameSeats))
        contextSeats[0].battlefield = [{
            "id": "s0-context",
            "name": "Raging Goblin",
            "setCode": "10E",
            "collectorNumber": "225",
            "ownerSeat": 0,
            "position": {"x": 0.3, "y": 0.55}
        }]
        mockWs.gameSeats = contextSeats
        const table = tableComponent.createObject(tableHost, {
            "width": testWindow.width,
            "height": testWindow.height
        })
        verify(table !== null)

        table.selectedHandCard = contextSeats[0].hand[0]
        table.cardMoveCommands.moveSelectedHandCard("graveyard")
        compare(mockWs.lastMove.cardId, "s0-c1")
        compare(mockWs.lastMove.fromZone, "hand")
        compare(mockWs.lastMove.toZone, "graveyard")

        table.selection.selectCard(contextSeats[0].battlefield[0], 0)
        table.cardMoveCommands.moveSelectedBattlefieldToZone("hand")
        compare(mockWs.lastMove.cardId, "s0-context")
        compare(mockWs.lastMove.fromZone, "battlefield")
        compare(mockWs.lastMove.toZone, "hand")

        table.selection.selectCard(contextSeats[0].battlefield[0], 0)
        table.cardMoveCommands.moveSelectedBattlefieldToZone("exile")
        compare(mockWs.lastMove.toZone, "exile")

        const controlledDropArea = {"cardSource": null}
        const controlledDrop = {
            "source": {
                "cardId": "s1-controlled",
                "zoneName": "battlefield",
                "zoneSeat": 0,
                "ownerSeat": 1,
                "modelData": {
                    "id": "s1-controlled",
                    "name": "Borrowed Permanent",
                    "ownerSeat": 1
                }
            },
            "accepted": false,
            "acceptProposedAction": function() {
                this.accepted = true
            }
        }
        table.cardMoveCommands.finishPublicZoneDrop(
                    controlledDropArea, controlledDrop, "graveyard", 0)
        compare(mockWs.lastMove.cardId, "s1-controlled")
        compare(mockWs.lastMove.toZone, "graveyard")
        compare(mockWs.lastMove.toSeat, 1)
        verify(controlledDrop.accepted)
        table.destroy()
    }

    // The DropArea clears cardSource on exit, which can run before onDropped.
    // The drop payload must therefore be the authoritative source, otherwise
    // dragging a card onto the stack silently does nothing.
    function test_stackDropUsesDropPayloadSource() {
        const table = tableComponent.createObject(tableHost, {
            "width": testWindow.width,
            "height": testWindow.height
        })
        verify(table !== null)
        const before = mockWs.moveCount

        const clearedDropArea = {"cardSource": null}
        const handDrop = {
            "source": {
                "cardId": "s0-c1",
                "zoneName": "hand",
                "zoneSeat": 0,
                "ownerSeat": 0,
                "modelData": {"id": "s0-c1", "name": "Lightning Bolt", "ownerSeat": 0}
            },
            "accepted": false,
            "acceptProposedAction": function() {
                this.accepted = true
            }
        }
        table.cardMoveCommands.finishStackDrop(clearedDropArea, handDrop)
        compare(mockWs.moveCount, before + 1)
        compare(mockWs.lastMove.cardId, "s0-c1")
        compare(mockWs.lastMove.fromZone, "hand")
        compare(mockWs.lastMove.toZone, "stack")
        verify(handDrop.accepted)

        // A hidden library source stays rejected, and a rejected drop must not
        // leave a stale source behind for the next drop.
        const libraryDrop = {
            "source": {
                "cardId": "s0-library",
                "zoneName": "library",
                "zoneSeat": 0,
                "ownerSeat": 0,
                "modelData": {"id": "s0-library", "ownerSeat": 0}
            },
            "accepted": true,
            "acceptProposedAction": function() {
                this.accepted = true
            }
        }
        const staleDropArea = {"cardSource": handDrop.source}
        table.cardMoveCommands.finishStackDrop(staleDropArea, libraryDrop)
        compare(mockWs.moveCount, before + 1)
        verify(!libraryDrop.accepted)
        compare(staleDropArea.cardSource, null)
        table.destroy()
    }

    // The test above calls the controller directly, so it cannot catch a broken
    // onDropped handler in SharedZonesView, and qmllint cannot type-check that
    // call either. Drive a real pointer drag so the DropArea signal, the handler,
    // and the controller are all exercised as they are wired.
    function test_draggingHandCardOntoSharedZoneCastsToStack() {
        const table = tableComponent.createObject(tableHost, {
            "width": testWindow.width,
            "height": testWindow.height
        })
        verify(table !== null)

        const sharedDropArea = findChild(table, "sharedDropArea")
        const handCard = findChild(table, "handCard0")
        verify(sharedDropArea !== null)
        verify(handCard !== null)
        tryVerify(() => sharedDropArea.width > 0 && sharedDropArea.height > 0)
        verify(sharedDropArea.enabled)

        mockWs.moveCount = 0
        mockWs.lastMove = ({})
        // The dragged card is reparented while the drag is active, so its own
        // coordinate frame moves mid-gesture. Express the whole gesture in the
        // stationary table frame instead.
        const pressPoint = handCard.mapToItem(
                             table, handCard.width / 2, handCard.height / 2)
        const dropPoint = sharedDropArea.mapToItem(
                            table, sharedDropArea.width / 2,
                            sharedDropArea.height / 2)
        mouseDrag(table, pressPoint.x, pressPoint.y,
                  dropPoint.x - pressPoint.x, dropPoint.y - pressPoint.y,
                  Qt.LeftButton, Qt.NoModifier, 30)

        tryCompare(mockWs, "moveCount", 1)
        compare(mockWs.lastMove.cardId, "s0-c1")
        compare(mockWs.lastMove.fromZone, "hand")
        compare(mockWs.lastMove.toZone, "stack")
        table.destroy()
    }

    function test_handContextBattlefieldMovesUseDistinctPositions() {
        const contextSeats = JSON.parse(JSON.stringify(mockWs.gameSeats))
        contextSeats[0].hand = [{
            "id": "s0-context-hand-a",
            "name": "Lightning Bolt",
            "setCode": "M11",
            "collectorNumber": "149",
            "typeLine": "Instant",
            "ownerSeat": 0
        }, {
            "id": "s0-context-hand-b",
            "name": "Raging Goblin",
            "setCode": "10E",
            "collectorNumber": "225",
            "typeLine": "Creature — Goblin",
            "ownerSeat": 0
        }]
        contextSeats[0].handCount = contextSeats[0].hand.length
        contextSeats[0].battlefield = []
        mockWs.gameSeats = contextSeats
        const table = tableComponent.createObject(tableHost, {
            "width": testWindow.width,
            "height": testWindow.height
        })
        verify(table !== null)

        table.selectedHandCard = contextSeats[0].hand[0]
        table.cardMoveCommands.moveSelectedHandCard("battlefield")
        const firstPosition = Object.assign({}, mockWs.lastMove.position)

        table.selectedHandCard = contextSeats[0].hand[1]
        table.cardMoveCommands.moveSelectedHandCard("battlefield")
        const secondPosition = Object.assign({}, mockWs.lastMove.position)

        compare(mockWs.moveCount, 2)
        compare(mockWs.lastMove.cardId, "s0-context-hand-b")
        compare(mockWs.lastMove.toZone, "battlefield")
        compare(firstPosition.y, 0.31)
        compare(secondPosition.y, 0.58)
        verify(firstPosition.x !== secondPosition.x
               || firstPosition.y !== secondPosition.y)
        compare(table.zoneState.pendingBattlefieldMovesForSeat(0).length, 2)
        table.destroy()
    }

    function test_handDoubleFacedCardUsesSelectedFaceTypeForPlacement() {
        const originalSeats = mockWs.gameSeats
        const contextSeats = JSON.parse(JSON.stringify(originalSeats))
        const cardName = "Restless Druid // Wrenn Awakened"
        contextSeats[0].hand = [{
            "id": "s0-dfc",
            "name": cardName,
            "setCode": "TST",
            "collectorNumber": "1",
            "typeLine": "Creature — Human Druid",
            "ownerSeat": 0
        }]
        contextSeats[0].handCount = 1
        contextSeats[0].battlefield = []
        mockWs.gameSeats = contextSeats
        const faceMap = ({})
        faceMap[cardName] = [{
            "name": cardName,
            "faceName": "",
            "displayName": "Restless Druid",
            "typeLine": "Creature — Human Druid"
        }, {
            "name": "Wrenn Awakened",
            "faceName": "Wrenn Awakened",
            "displayName": "Wrenn Awakened",
            "typeLine": "Planeswalker — Wrenn"
        }]
        mockCatalog.faces = faceMap
        const table = tableComponent.createObject(tableHost, {
            "width": testWindow.width,
            "height": testWindow.height
        })
        verify(table !== null)

        table.selectedHandCard = contextSeats[0].hand[0]
        table.cardMoveCommands.moveSelectedHandCard("battlefield")
        compare(mockWs.moveCount, 0)
        const picker = findChild(table, "cardFacePicker")
        verify(picker !== null)
        tryVerify(() => picker.opened)
        picker.choose("Wrenn Awakened")

        compare(mockWs.moveCount, 1)
        compare(mockWs.lastMove.faceName, "Wrenn Awakened")
        compare(mockWs.lastMove.position.y, 0.05)
        table.destroy()
        mockWs.gameSeats = originalSeats
    }

    function test_battlefieldMultiSelectionUsesOnlyBatchDestinations() {
        const contextSeats = JSON.parse(JSON.stringify(mockWs.gameSeats))
        contextSeats[0].battlefield = [{
            "id": "s0-batch-a",
            "name": "Batch A",
            "ownerSeat": 0,
            "position": {"x": 0.3, "y": 0.5}
        }, {
            "id": "s0-batch-b",
            "name": "Batch B",
            "ownerSeat": 0,
            "position": {"x": 0.5, "y": 0.5}
        }]
        mockWs.gameSeats = contextSeats
        const table = tableComponent.createObject(tableHost, {
            "width": testWindow.width,
            "height": testWindow.height
        })
        verify(table !== null)

        table.selection.selectCard(contextSeats[0].battlefield[0], 0, false)
        table.selection.selectCard(contextSeats[0].battlefield[1], 0, true)
        compare(table.selection.selectedCount(), 2)
        const batchMenu = findChild(table, "moveSelectedBattlefieldMenu")
        const singleHand = findChild(table, "moveBattlefieldCardToHand")
        const randomBottom = findChild(
                                 table,
                                 "moveSelectedBattlefieldToLibraryBottomRandom")
        verify(batchMenu !== null)
        verify(singleHand !== null)
        verify(randomBottom !== null)
        // A nested Menu's visible property is its popup-open state, not the
        // visibility of its entry in the parent menu.
        compare(batchMenu.title, "Move selected · 2")
        verify(!singleHand.visible)

        randomBottom.triggered()
        compare(mockWs.moveCardsCount, 1)
        compare(mockWs.lastMoveCards.cardIds.length, 2)
        compare(mockWs.lastMoveCards.fromZone, "battlefield")
        compare(mockWs.lastMoveCards.toZone, "library")
        compare(mockWs.lastMoveCards.libraryPlacement, "bottom")
        verify(mockWs.lastMoveCards.randomize)
        table.destroy()
    }

    function test_sideboardBrowserCanMoveCardToBattlefield() {
        const sideboardSeats = JSON.parse(JSON.stringify(mockWs.gameSeats))
        sideboardSeats[0].sideboardCount = 1
        sideboardSeats[0].sideboard = [{
            "id": "s0-sideboard",
            "name": "Sideboard Card",
            "ownerSeat": 0
        }]
        mockWs.gameSeats = sideboardSeats
        const table = tableComponent.createObject(tableHost, {
            "width": testWindow.width,
            "height": testWindow.height
        })
        verify(table !== null)

        const viewSideboard = findChild(table, "viewSideboardAction")
        const popup = findChild(table, "publicZoneBrowserPopup")
        const toBattlefield = findChild(popup, "zoneCardToBattlefield")
        verify(viewSideboard !== null)
        verify(popup !== null)
        verify(toBattlefield !== null)
        verify(viewSideboard.enabled)
        viewSideboard.triggered()
        tryVerify(() => popup.opened)
        compare(popup.zoneKey, "sideboard")
        compare(popup.selectedCard.id, "s0-sideboard")
        verify(toBattlefield.enabled)

        toBattlefield.triggered()
        compare(mockWs.lastMove.cardId, "s0-sideboard")
        compare(mockWs.lastMove.fromZone, "sideboard")
        compare(mockWs.lastMove.toZone, "battlefield")
        compare(mockWs.lastMove.toSeat, 0)
        table.destroy()
    }

    function test_battlefieldBackgroundCanUntapAll() {
        const originalSeats = mockWs.gameSeats
        const battlefieldSeats = JSON.parse(JSON.stringify(originalSeats))
        battlefieldSeats[0].battlefield = [{
            "id": "s0-tapped-a",
            "name": "Tapped A",
            "tapped": true,
            "position": {"x": 0.25, "y": 0.5}
        }, {
            "id": "s0-tapped-b",
            "name": "Tapped B",
            "tapped": true,
            "position": {"x": 0.5, "y": 0.5}
        }, {
            "id": "s0-untapped",
            "name": "Untapped",
            "tapped": false,
            "position": {"x": 0.75, "y": 0.5}
        }]
        mockWs.gameSeats = battlefieldSeats
        const table = tableComponent.createObject(tableHost, {
            "width": testWindow.width,
            "height": testWindow.height
        })
        verify(table !== null)
        const untapAll =
            findChild(table, "untapAllBattlefieldAction")
        verify(untapAll !== null)
        verify(untapAll.enabled)
        untapAll.triggered()
        compare(mockWs.setTappedCount, 2)
        compare(mockWs.lastTapped.cardId, "s0-tapped-b")
        verify(!mockWs.lastTapped.tapped)
        verify(!table.gameValues.displayedTapped(
                   battlefieldSeats[0].battlefield[0]))
        verify(!table.gameValues.displayedTapped(
                   battlefieldSeats[0].battlefield[1]))
        tryVerify(() => !untapAll.enabled)
        table.destroy()
        mockWs.gameSeats = originalSeats
    }

    function test_battlefieldBackgroundArrangesByPermanentType() {
        const originalSeats = mockWs.gameSeats
        const battlefieldSeats = JSON.parse(JSON.stringify(originalSeats))
        battlefieldSeats[0].battlefield = [{
            "id": "s0-land",
            "name": "Forest",
            "typeLine": "Basic Land — Forest",
            "position": {"x": 0.5, "y": 0.2}
        }, {
            "id": "s0-creature",
            "name": "Grizzly Bears",
            "typeLine": "Creature — Bear",
            "position": {"x": 0.5, "y": 0.2}
        }, {
            "id": "s0-creature-copy",
            "name": "Grizzly Bears",
            "setCode": "2ED",
            "typeLine": "Creature — Bear",
            "position": {"x": 0.5, "y": 0.2}
        }, {
            "id": "s0-creature-countered",
            "name": "Grizzly Bears",
            "typeLine": "Creature — Bear",
            "counters": [{
                "id": "number",
                "kind": "number",
                "value": 1
            }],
            "position": {"x": 0.5, "y": 0.2}
        }, {
            "id": "s0-artifact",
            "name": "Sol Ring",
            "typeLine": "Artifact",
            "position": {"x": 0.5, "y": 0.2}
        }, {
            "id": "s0-artifact-copy",
            "name": "Sol Ring",
            "setCode": "CMM",
            "typeLine": "Artifact",
            "position": {"x": 0.5, "y": 0.2}
        }, {
            "id": "s0-enchantment",
            "name": "Propaganda",
            "typeLine": "Enchantment",
            "position": {"x": 0.5, "y": 0.2}
        }, {
            "id": "s0-planeswalker",
            "name": "Jace, the Mind Sculptor",
            "typeLine": "Legendary Planeswalker — Jace",
            "position": {"x": 0.5, "y": 0.2}
        }, {
            "id": "s0-spell",
            "name": "Opt",
            "typeLine": "Instant",
            "position": {"x": 0.5, "y": 0.2}
        }, {
            "id": "s0-land-copy",
            "name": "Forest",
            "setCode": "M21",
            "typeLine": "Basic Land — Forest",
            "position": {"x": 0.5, "y": 0.2}
        }]
        mockWs.gameSeats = battlefieldSeats
        const table = tableComponent.createObject(tableHost, {
            "width": testWindow.width,
            "height": testWindow.height
        })
        verify(table !== null)

        const arrange = findChild(table, "arrangeBattlefieldAction")
        verify(arrange !== null)
        verify(arrange.enabled)
        arrange.triggered()

        compare(mockWs.arrangeBattlefieldCount, 1)
        compare(mockWs.lastBattlefieldArrangement.length, 10)
        const placements = ({})
        for (let index = 0;
             index < mockWs.lastBattlefieldArrangement.length; ++index) {
            const placement = mockWs.lastBattlefieldArrangement[index]
            placements[placement.cardId] = placement.position
        }
        compare(placements["s0-enchantment"].y, 0.05)
        compare(placements["s0-artifact"].y, 0.05)
        compare(placements["s0-planeswalker"].y, 0.05)
        verify(placements["s0-enchantment"].x
               < placements["s0-artifact"].x)
        verify(placements["s0-artifact"].x
               < placements["s0-planeswalker"].x)
        compare(placements["s0-spell"].y, 0.31)
        compare(placements["s0-creature"].y, 0.58)
        compare(placements["s0-land"].y, 1)
        verify(placements["s0-creature-copy"].x
               > placements["s0-creature"].x)
        verify(placements["s0-creature-copy"].x
               - placements["s0-creature"].x < 0.05)
        verify(placements["s0-creature-copy"].y
               > placements["s0-creature"].y)
        verify(Math.abs(placements["s0-creature-countered"].x
                        - placements["s0-creature"].x) > 0.05
               || Math.abs(placements["s0-creature-countered"].y
                           - placements["s0-creature"].y) > 0.05)
        verify(Math.abs(placements["s0-artifact-copy"].x
                        - placements["s0-artifact"].x) > 0.05
               || Math.abs(placements["s0-artifact-copy"].y
                           - placements["s0-artifact"].y) > 0.05)
        verify(placements["s0-land-copy"].x
               > placements["s0-land"].x)
        verify(placements["s0-land-copy"].y
               < placements["s0-land"].y)
        const firstCreature = table.cardMoveCommands.battlefieldSlot(
                                  0, "creature", 0)
        const secondCreature = table.cardMoveCommands.battlefieldSlot(
                                   0, "creature", 1)
        const thirdCreature = table.cardMoveCommands.battlefieldSlot(
                                  0, "creature", 2)
        verify(Math.abs(firstCreature.x - 0.5) < 0.15)
        verify((secondCreature.x - 0.5) * (thirdCreature.x - 0.5) < 0)
        table.destroy()
        mockWs.gameSeats = originalSeats
    }

    function test_concedeRequiresConfirmationAndLocksFinishedGame() {
        const table = tableComponent.createObject(tableHost, {
            "width": testWindow.width,
            "height": testWindow.height
        })
        verify(table !== null)

        const concede = findChild(table, "concedeAction")
        verify(concede !== null)
        verify(concede.enabled)

        const confirmation = findChild(table, "concedeConfirmation")
        verify(confirmation !== null)
        confirmation.open()
        tryVerify(() => confirmation.opened)
        const confirm = findChild(confirmation, "confirmButton")
        verify(confirm !== null)
        confirm.clicked()
        compare(mockWs.concedeCount, 1)
        tryVerify(() => !confirmation.opened)

        mockWs.matchScore = [0, 1]
        mockWs.gameResult = {
            "reason": "concede",
            "winnerSeat": 1,
            "concededSeat": 0,
            "matchFinished": true
        }
        mockWs.activeSeat = -1
        mockWs.gameFinished = true
        mockWs.gameSnapshotChanged()

        const resultPopup = findChild(table, "gameResultPopup")
        const title = findChild(table, "gameResultTitle")
        const draw = findChild(table, "drawCardButton0")
        const mulligan = findChild(table, "mulliganAction")
        const phase = findChild(table, "phaseButton0")
        const ownPip = findChild(table, "playerCounterPip0-0")
        tryVerify(() => resultPopup.opened)
        compare(title.text, "Bob wins the match")
        const stay = findChild(resultPopup, "stayAtTableButton")
        verify(stay !== null)
        stay.clicked()
        tryVerify(() => !resultPopup.opened)
        verify(!concede.enabled)
        verify(!draw.enabled)
        verify(!mulligan.enabled)
        verify(phase !== null)
        verify(!phase.enabled)
        verify(!ownPip.editable)
        const chatInput = findChild(table, "gameChatInput")
        verify(chatInput !== null)
        verify(chatInput.enabled)
        table.destroy()
    }

    function test_departureResultUsesDepartureWording() {
        mockWs.matchScore = [0, 2]
        mockWs.gameResult = {
            "reason": "departure",
            "winnerSeat": 1,
            "concededSeat": 0,
            "matchFinished": true
        }
        mockWs.activeSeat = -1
        mockWs.gameFinished = true
        const table = tableComponent.createObject(tableHost, {
            "width": testWindow.width,
            "height": testWindow.height
        })
        verify(table !== null)
        table.sessionUi.maybeShowGameResult()

        const resultPopup = findChild(table, "gameResultPopup")
        const detail = findChild(table, "gameResultDetail")
        tryVerify(() => resultPopup.opened)
        verify(detail !== null)
        compare(detail.text, "Alice left the match · Score 0–2")
        table.destroy()
    }

    function test_indexedModelRefreshesPrivateZonesAfterFirstSnapshot() {
        testGameTable.clear()
        const table = tableComponent.createObject(tableHost, {
            "width": testWindow.width,
            "height": testWindow.height
        })
        verify(table !== null)
        compare(table.ownHand.length, 0)
        verify(table.ownSeatData.libraryCount === undefined)

        const seats = JSON.parse(
                        JSON.stringify(mockWs.baselineGameSeats))
        seats[0].hand = []
        for (let index = 0; index < 7; ++index) {
            seats[0].hand.push({
                "id": "opening-" + index,
                "name": "Opening card " + index
            })
        }
        seats[0].handCount = 7
        seats[0].libraryCount = 53
        testGameTable.applySnapshot({"seats": seats})

        tryVerify(() => table.ownSeatData.libraryCount === 53)
        compare(table.ownSeatData.handCount, 7)
        tryVerify(() => table.ownHand.length === 7)
        compare(table.ownHand[0].id, "opening-0")

        const updatedSeats = JSON.parse(JSON.stringify(seats))
        updatedSeats[0].hand.push({
            "id": "drawn-card",
            "name": "Drawn card"
        })
        updatedSeats[0].handCount = 8
        updatedSeats[0].libraryCount = 52
        testGameTable.applySnapshot({"seats": updatedSeats})

        tryVerify(() => table.ownSeatData.libraryCount === 52)
        compare(table.ownSeatData.handCount, 8)
        tryVerify(() => table.ownHand.length === 8)
        compare(table.ownHand[7].id, "drawn-card")

        testGameTable.clear()
        tryVerify(() => table.ownSeatData.libraryCount === undefined)
        tryVerify(() => table.ownHand.length === 0)
        table.destroy()
    }

    function test_soloPlaytestRestoresHandAfterFirstTypedSnapshot() {
        mockWs.playtest = true
        testGameTable.clear()
        const table = tableComponent.createObject(tableHost, {
            "width": testWindow.width,
            "height": testWindow.height
        })
        verify(table !== null)
        compare(table.ownHand.length, 0)

        const soloSeat = JSON.parse(
                           JSON.stringify(mockWs.baselineGameSeats[0]))
        testGameTable.applySnapshot({"seats": [soloSeat]})
        mockWs.gameSnapshotChanged()

        const handSurface = findChild(table, "handSurface")
        verify(handSurface !== null)
        tryVerify(() => handSurface.height === table.handAreaHeight)
        tryVerify(() => table.ownHand.length === 1)
        tryVerify(() => findChild(table, "handCard0") !== null)
        table.destroy()
    }

    function test_battlefieldPerspectiveKeepsViewerAtBottom() {
        mockWs.seatIndex = 1
        const table = tableComponent.createObject(tableHost, {
            "width": testWindow.width,
            "height": testWindow.height
        })
        verify(table !== null)
        const opponentBattlefield = findChild(table, "battlefieldZone0")
        const ownBattlefield = findChild(table, "battlefieldZone1")
        const ownDropArea = findChild(table, "battlefieldDropArea")
        const opponentDropArea = findChild(table, "opponentBattlefieldDropArea0")
        verify(opponentBattlefield !== null)
        verify(ownBattlefield !== null)
        verify(ownDropArea !== null)
        verify(opponentDropArea !== null)
        tryVerify(() => opponentBattlefield.y < ownBattlefield.y)
        verify(ownDropArea.enabled)
        verify(opponentDropArea.enabled)
        table.destroy()
    }

    function test_librarySearchUsesPrivateDumpAndMultiSelection() {
        const table = tableComponent.createObject(tableHost, {
            "width": testWindow.width,
            "height": testWindow.height
        })
        verify(table !== null)
        const searchButton = findChild(table, "searchLibraryButton0")
        verify(searchButton !== null)
        verify(searchButton.enabled)
        searchButton.trigger()
        compare(mockWs.dumpLibraryCount, 1)

        mockWs.libraryDumped([{
            "id": "s0-lib1",
            "name": "Llanowar Elves",
            "setCode": "M19",
            "collectorNumber": "314",
            "typeLine": "Creature — Elf Druid"
        }, {
            "id": "s0-lib2",
            "name": "Elvish Mystic",
            "setCode": "M14",
            "collectorNumber": "169",
            "typeLine": "Creature — Elf Druid"
        }], 0, "", 0)
        const popup = findChild(table, "librarySearchPopup")
        verify(popup !== null)
        tryVerify(() => popup.opened)
        const cards = findChild(popup, "librarySearchCards")
        verify(cards !== null)
        compare(cards.count, 2)

        tryVerify(() => cards.itemAtIndex(1) !== null)
        const firstCard = cards.itemAtIndex(0)
        const secondCard = cards.itemAtIndex(1)
        const firstSelection = findChild(firstCard, "librarySelectBox0")
        const secondSelection = findChild(secondCard, "librarySelectBox1")
        verify(firstCard !== null)
        verify(secondCard !== null)
        verify(firstSelection !== null)
        verify(secondSelection !== null)
        compare(popup.selectedCount, 0)
        mouseClick(secondCard, secondCard.width / 2,
                   secondCard.height / 2, Qt.LeftButton)
        tryCompare(popup, "selectedIndex", 1)
        compare(popup.selectedCount, 0)
        mouseClick(firstSelection, firstSelection.width / 2,
                   firstSelection.height / 2, Qt.LeftButton)
        tryCompare(popup, "selectedCount", 1)
        compare(popup.selectedIndex, 0)
        mouseClick(secondSelection, secondSelection.width / 2,
                   secondSelection.height / 2, Qt.LeftButton)
        tryCompare(popup, "selectedCount", 2)
        compare(popup.selectedIndex, 1)
        const destination = findChild(popup, "libraryDestination")
        const reveal = findChild(popup, "revealLibrarySearch")
        const complete = findChild(popup, "completeLibrarySearchButton")
        const libraryCardMenu = findChild(popup, "libraryCardMenu")
        const battlefieldAreaMenu =
            findChild(table, "battlefieldAreaMenu")
        const battlefieldCardMenu = findChild(table, "cardToolsMenu")
        const modalShield = findChild(table, "tableModalInputShield")
        const handAction = findChild(popup, "libraryContextLocalHand")
        const battlefieldAction =
            findChild(popup, "libraryContextLocalBattlefield")
        const graveyardAction =
            findChild(popup, "libraryContextLocalGraveyard")
        const exileAction = findChild(popup, "libraryContextLocalExile")
        const topOrderedAction =
            findChild(popup, "libraryContextSourceTopOrdered")
        const topRandomAction =
            findChild(popup, "libraryContextSourceTopRandom")
        const bottomOrderedAction =
            findChild(popup, "libraryContextSourceBottomOrdered")
        const bottomRandomAction =
            findChild(popup, "libraryContextSourceBottomRandom")
        verify(destination !== null)
        verify(reveal !== null)
        verify(complete !== null)
        verify(libraryCardMenu !== null)
        verify(battlefieldAreaMenu !== null)
        verify(battlefieldCardMenu !== null)
        verify(modalShield !== null)
        verify(modalShield.visible)
        verify(handAction !== null)
        verify(battlefieldAction !== null)
        verify(graveyardAction !== null)
        verify(exileAction !== null)
        verify(topOrderedAction !== null)
        verify(topRandomAction !== null)
        verify(bottomOrderedAction !== null)
        verify(bottomRandomAction !== null)
        verify(battlefieldAction.enabled)
        mouseClick(secondCard, secondCard.width / 2,
                   secondCard.height / 2, Qt.RightButton)
        tryVerify(() => libraryCardMenu.opened)
        compare(popup.selectedCount, 2)
        verify(!battlefieldAreaMenu.opened)
        verify(!battlefieldCardMenu.opened)
        libraryCardMenu.close()
        tryVerify(() => !libraryCardMenu.opened)
        reveal.checked = false
        battlefieldAction.triggered()

        compare(mockWs.searchLibraryCount, 1)
        compare(mockWs.lastLibrarySearch.cardIds.length, 2)
        compare(mockWs.lastLibrarySearch.cardIds[0], "s0-lib1")
        compare(mockWs.lastLibrarySearch.cardIds[1], "s0-lib2")
        compare(mockWs.lastLibrarySearch.toZone, "battlefield")
        compare(mockWs.lastLibrarySearch.reveal, false)
        compare(mockWs.lastLibrarySearch.randomize, false)
        verify(mockWs.lastLibrarySearch.position.x > 0)
        verify(mockWs.lastLibrarySearch.position.x < 1)
        verify(mockWs.lastLibrarySearch.position.y > 0)
        verify(mockWs.lastLibrarySearch.position.y < 1)
        compare(mockWs.lastLibrarySearch.toSeat, 0)
        tryVerify(() => !popup.opened)
        table.destroy()
    }

}
