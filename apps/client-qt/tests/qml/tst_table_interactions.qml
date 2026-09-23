// SPDX-License-Identifier: GPL-3.0-or-later
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
        testWindow.width = 1400
        testWindow.height = 800
    }

    function test_audioSettingsOpenWithoutLeavingManualMatch() {
        testWindow.openedScreen = ({})
        const table = createTemporaryObject(tableComponent, tableHost, {
            width:testWindow.width, height:testWindow.height
        })
        verify(table !== null)
        const popup = findChild(table, "tableSettingsPopup")
        verify(popup !== null)
        popup.showFor(false, true, false, 3, true, true)
        tryCompare(popup, "opened", true)
        const audio = findChild(popup.contentItem, "openTableAudioButton")
        verify(audio !== null)
        mouseClick(audio)
        tryCompare(popup, "visible", false)
        compare(testWindow.openedScreen.url, "screens/AudioSettings.qml")
        compare(testWindow.openedScreen.properties.settings, mockPreferences)
        compare(mockWs.leaveRoomCount, 0)
        verify(mockWs.inRoom)
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

        // A library drag names only the unknown top card. The server reveals
        // that card when it reaches the public stack, without a private peek.
        const libraryDrop = {
            "source": {
                "cardId": "__library_top__",
                "zoneName": "library",
                "zoneSeat": 0,
                "ownerSeat": 0,
                "modelData": ({})
            },
            "accepted": true,
            "acceptProposedAction": function() {
                this.accepted = true
            }
        }
        const staleDropArea = {"cardSource": handDrop.source}
        table.cardMoveCommands.finishStackDrop(staleDropArea, libraryDrop)
        compare(mockWs.moveCount, before + 2)
        compare(mockWs.lastMove.cardId, "__library_top__")
        compare(mockWs.lastMove.fromZone, "library")
        compare(mockWs.lastMove.toZone, "stack")
        verify(libraryDrop.accepted)
        compare(staleDropArea.cardSource, null)
        table.destroy()
    }

    // The test above calls the controller directly, so it cannot catch a broken
    // onDropped handler in SharedZonesView, and qmllint cannot type-check that
    // call either. Drive a real pointer drag so the DropArea signal, the handler,
    // and the controller are all exercised as they are wired.
    function test_draggingCardOntoSharedZoneMovesToStack_data() {
        return [
            {tag: "hand", source: "handCard0", cardId: "s0-c1", zone: "hand"},
            {tag: "library-top", source: "ownLibraryCardBack", cardId: "__library_top__", zone: "library"},
            {tag: "library-top-off-center", source: "ownLibraryCardBack", cardId: "__library_top__", zone: "library", offset: 0.1}
        ]
    }
    function test_draggingCardOntoSharedZoneMovesToStack(data) {
        const table = tableComponent.createObject(tableHost, {
            "width": testWindow.width,
            "height": testWindow.height
        })
        verify(table !== null)

        const sharedDropArea = findChild(table, "sharedDropArea")
        verify(sharedDropArea !== null)
        tryVerify(() => findChild(table, "handCard0") !== null)
        const handCard = findChild(table, data.source)
        verify(handCard !== null)
        tryVerify(() => sharedDropArea.width > 0 && sharedDropArea.height > 0)
        verify(sharedDropArea.enabled)

        mockWs.moveCount = 0
        mockWs.lastMove = ({})
        // The dragged card is reparented while the drag is active, so its own
        // coordinate frame moves mid-gesture. Express the whole gesture in the
        // stationary table frame instead.
        const pressPoint = handCard.mapToItem(
                             table, handCard.width * (data.offset || 0.5),
                             handCard.height * (data.offset || 0.5))
        const dropPoint = sharedDropArea.mapToItem(
                            table, sharedDropArea.width / 2,
                            sharedDropArea.height / 2)
        mouseDrag(table, pressPoint.x, pressPoint.y,
                  dropPoint.x - pressPoint.x, dropPoint.y - pressPoint.y,
                  Qt.LeftButton, Qt.NoModifier, 30)

        tryCompare(mockWs, "moveCount", 1)
        compare(mockWs.lastMove.cardId, data.cardId)
        compare(mockWs.lastMove.fromZone, data.zone)
        compare(mockWs.lastMove.toZone, "stack")
        compare(table.sharedCards[table.sharedCards.length - 1].ownerSeat, 0)
        compare(mockWs.dumpLibraryCount, 0)
        table.destroy()
    }

    function test_draggingLibraryTopToExile_data() {
        return [{tag: "face-up", modifiers: Qt.NoModifier, faceDown: false},
                {tag: "face-down", modifiers: Qt.ShiftModifier, faceDown: true}]
    }

    function test_draggingLibraryTopToExile(data) {
        const table = createTemporaryObject(tableComponent, tableHost, {
            width: testWindow.width, height: testWindow.height
        })
        verify(table !== null)
        const source = findChild(table, "ownLibraryCardBack")
        const destination = findChild(table, "exileDropArea0")
        tryVerify(() => source.width > 0 && destination.width > 0)
        const start = source.mapToItem(table, source.width * 0.2, source.height * 0.3)
        const end = destination.mapToItem(table, destination.width / 2, destination.height / 2)
        mouseDrag(table, start.x, start.y, end.x - start.x, end.y - start.y,
                  Qt.LeftButton, data.modifiers, 30)
        tryCompare(mockWs, "moveCount", 1)
        compare(mockWs.lastMove.cardId, "__library_top__")
        compare(mockWs.lastMove.fromZone, "library")
        compare(mockWs.lastMove.toZone, "exile")
        compare(mockWs.lastMove.faceDown, data.faceDown)
        compare(mockWs.dumpLibraryCount, 0)
    }

    function test_libraryMenuExilesWithoutLookingAtTop() {
        const table = createTemporaryObject(tableComponent, tableHost, {
            width: testWindow.width, height: testWindow.height
        })
        verify(table !== null)
        const action = findChild(table, "exileLibraryTopFaceDownAction")
        verify(action !== null && action.enabled)
        action.triggered()
        compare(mockWs.moveCount, 1)
        compare(mockWs.lastMove.fromZone, "library")
        compare(mockWs.lastMove.toZone, "exile")
        compare(mockWs.lastMove.faceDown, true)
        compare(mockWs.dumpLibraryCount, 0)
        // A second click cannot enqueue the same unknown top while pending.
        action.triggered()
        compare(mockWs.moveCount, 1)
    }

    function test_draggingHandCardsReordersOnlyTheLocalProjection() {
        const handSeats = JSON.parse(JSON.stringify(mockWs.gameSeats))
        handSeats[0].hand = [{
            "id": "s0-hand-a",
            "name": "Alpha",
            "ownerSeat": 0
        }, {
            "id": "s0-hand-b",
            "name": "Beta",
            "ownerSeat": 0
        }, {
            "id": "s0-hand-c",
            "name": "Gamma",
            "ownerSeat": 0
        }]
        handSeats[0].handCount = handSeats[0].hand.length
        mockWs.gameSeats = handSeats
        const table = tableComponent.createObject(tableHost, {
            "width": testWindow.width,
            "height": testWindow.height
        })
        verify(table !== null)

        tryVerify(() => findChild(table, "handCard0") !== null
                        && findChild(table, "handCard2") !== null)
        const firstCard = findChild(table, "handCard0")
        const thirdCard = findChild(table, "handCard2")
        verify(firstCard !== null)
        verify(thirdCard !== null)
        const beforeMoves = mockWs.moveCount
        const pressPoint = firstCard.mapToItem(
                             table, firstCard.width / 2,
                             firstCard.height / 2)
        const dropPoint = thirdCard.mapToItem(
                            table, thirdCard.width / 2,
                            thirdCard.height / 2)
        mouseDrag(table, pressPoint.x, pressPoint.y,
                  dropPoint.x - pressPoint.x, dropPoint.y - pressPoint.y,
                  Qt.LeftButton, Qt.NoModifier, 30)

        tryVerify(() => table.ownHand[2].id === "s0-hand-a")
        compare(table.ownHand[0].id, "s0-hand-b")
        compare(table.ownHand[1].id, "s0-hand-c")
        compare(mockWs.moveCount, beforeMoves)
        table.destroy()
    }

    function test_draggingNonFirstHandCardToStackKeepsDropLocation_data() {
        return [{tag: "first", index: 0, count: 7}, {tag: "sixth", index: 5, count: 7},
                {tag: "seventh", index: 6, count: 7},
                {tag: "clipped-card", index: 10, count: 16, clipped: true},
                {tag: "two-pixel-fragment", index: 10, count: 16, clipped: true, thin: true},
                {tag: "top-edge-grab", index: 5, count: 7, pressTop: true},
                {tag: "bottom-edge-grab", index: 5, count: 7, pressBottom: true},
                {tag: "rejected-drop", index: 6, count: 7, rejected: true}]
    }

    function test_draggingNonFirstHandCardToStackKeepsDropLocation(data) {
        // Fitted hand cards use the strip height (63/88 aspect), so a full
        // seven-card hand overflows the hand viewport at 1440 px. Rows that
        // need every card fully visible use a wider table; clipped rows keep
        // the narrow viewport their scrolling fixture depends on.
        const tableWidth = data.clipped ? 1440 : 1920
        testWindow.width = tableWidth
        testWindow.height = 900
        const seats = JSON.parse(JSON.stringify(mockWs.gameSeats))
        seats[0].hand = []
        for (let index = 0; index < data.count; ++index)
            seats[0].hand.push({id: "drag-hand-" + index, name: "Spell " + index, ownerSeat: 0})
        seats[0].handCount = data.count
        mockWs.gameSeats = seats
        const table = tableComponent.createObject(tableHost, {width: tableWidth, height: 900})
        verify(table !== null)
        const hand = findChild(table, "ownHand")
        const stack = findChild(table, "sharedDropArea")
        tryCompare(hand, "count", data.count)
        if (data.clipped)
            hand.positionViewAtIndex(data.index, ListView.Beginning)
        tryVerify(() => hand.itemAtIndex(data.index) !== null && stack.width > 0)
        if (data.clipped) {
            // Fixture setup exposes only part of the card. The gesture below
            // still presses only that visible fragment.
            const target = hand.itemAtIndex(data.index)
            hand.contentX = target.x - hand.width + (data.thin ? 2 : target.width / 4)
        }
        wait(100)
        const card = hand.itemAtIndex(data.index)
        const cardLeft = card.mapToItem(hand, 0, 0).x
        const visibleWidth = Math.min(card.width, hand.width - cardLeft)
        verify(visibleWidth > 0, "The drag must start within the visible hand viewport")
        if (data.clipped) verify(visibleWidth < card.width / 2, "The clipping fixture must actually clip the card")
        if (data.thin) verify(visibleWidth <= 2.5, "Only the two-pixel card fragment may be exposed")
        const press = card.mapToItem(table, visibleWidth / 2,
                                    data.pressTop ? 2 : data.pressBottom ? card.height - 2 : card.height / 2)
        const dropY = data.pressTop ? stack.height - 10 : data.pressBottom ? 10 : stack.height / 2
        const drop = data.rejected ? Qt.point(20, 30)
                                  : stack.mapToItem(table, stack.width / 2, dropY)
        mousePress(table, press.x, press.y, Qt.LeftButton)
        wait(20)
        for (let step = 1; step <= 12; ++step) {
            mouseMove(table, press.x + (drop.x - press.x) * step / 12,
                      press.y + (drop.y - press.y) * step / 12, 0, Qt.LeftButton)
            wait(20)
        }
        const hotspot = card.mapToItem(stack, card.Drag.hotSpot.x, card.Drag.hotSpot.y)
        const pointer = stack.mapFromItem(table, drop.x, drop.y)
        mouseRelease(table, drop.x, drop.y, Qt.LeftButton)
        if (data.rejected) {
            tryCompare(table, "activeHandDragCardId", "")
            compare(mockWs.moveCount, 0)
            compare(table.ownHand.map(row => row.id).sort(), seats[0].hand.map(row => row.id).sort())
            tryVerify(() => card.parent !== table && !card.Drag.active)
            table.destroy()
            return
        }
        verify(hotspot.x >= 0 && hotspot.x <= stack.width && hotspot.y >= 0 && hotspot.y <= stack.height,
               "The dragged card's drop hotspot must reach the stack with the pointer")
        verify(Math.abs(hotspot.x - pointer.x) <= 1.5 && Math.abs(hotspot.y - pointer.y) <= 1.5,
               "The drop hotspot must follow the actual grab point, including edge presses")
        tryCompare(mockWs, "moveCount", 1)
        compare(mockWs.lastMove.cardId, "drag-hand-" + data.index)
        compare(mockWs.lastMove.fromZone, "hand")
        compare(mockWs.lastMove.toZone, "stack", "A pointer released on the stack must not move the card to another zone")
        table.destroy()
    }

    function test_reorderingLargeHandKeepsBothScrollEdgesVisible() {
        const handSeats = JSON.parse(JSON.stringify(mockWs.gameSeats))
        handSeats[0].hand = []
        for (let index = 0; index < 27; ++index) {
            handSeats[0].hand.push({
                "id": "s0-large-hand-" + index,
                "name": "Card " + index,
                "ownerSeat": 0
            })
        }
        handSeats[0].handCount = handSeats[0].hand.length
        mockWs.gameSeats = handSeats
        const table = tableComponent.createObject(tableHost, {
            "width": testWindow.width,
            "height": testWindow.height
        })
        verify(table !== null)

        const handList = findChild(table, "ownHand")
        const slider = findChild(table, "handScrollSlider")
        verify(handList !== null)
        verify(slider !== null)
        tryCompare(handList, "count", handSeats[0].hand.length)
        tryVerify(() => handList.contentWidth > handList.width)
        handList.contentX = slider.to
        wait(0)

        const lastIndex = handList.count - 1
        const targetCard = handList.itemAtIndex(lastIndex)
        verify(targetCard !== null)
        let movedIndex = -1
        let movedCard = null
        for (let index = lastIndex - 1; index >= 0; --index) {
            const item = handList.itemAtIndex(index)
            if (item === null)
                continue
            movedCard = item
            movedIndex = index
            if (lastIndex - index >= 3)
                break
        }
        verify(movedCard !== null)
        const pressPoint = movedCard.mapToItem(
                             table, movedCard.width / 2,
                             movedCard.height / 2)
        const dropPoint = targetCard.mapToItem(
                            table, targetCard.width / 2,
                            targetCard.height / 2)
        mouseDrag(table, pressPoint.x, pressPoint.y,
                  dropPoint.x - pressPoint.x, dropPoint.y - pressPoint.y,
                  Qt.LeftButton, Qt.NoModifier, 30)

        const movedId = "s0-large-hand-" + movedIndex
        tryVerify(() => table.ownHand[movedIndex].id !== movedId)
        compare(slider.from, handList.originX)
        compare(slider.to, handList.originX
                + Math.max(0, handList.contentWidth - handList.width))

        handList.contentX = slider.from
        wait(0)
        const leftCard = handList.itemAtIndex(0)
        const leftPosition = leftCard.mapToItem(handList, 0, 0)
        verify(leftPosition.x >= -1)

        handList.contentX = slider.to
        wait(0)
        const rightCard = handList.itemAtIndex(handList.count - 1)
        const rightPosition = rightCard.mapToItem(handList, 0, 0)
        verify(rightPosition.x + rightCard.width <= handList.width + 1)
        table.destroy()
    }

    function test_handCardsGrowIntoSpaceFormerlyUsedBySliderRow() {
        const handSeats = JSON.parse(JSON.stringify(mockWs.gameSeats))
        handSeats[0].hand = []
        for (let index = 0; index < 27; ++index) {
            handSeats[0].hand.push({
                "id": "s0-fitted-hand-" + index,
                "name": "Card " + index,
                "ownerSeat": 0
            })
        }
        handSeats[0].handCount = handSeats[0].hand.length
        mockWs.gameSeats = handSeats
        const table = tableComponent.createObject(tableHost, {
            "width": testWindow.width,
            "height": testWindow.height
        })
        verify(table !== null)

        const header = findChild(table, "ownHandHeader")
        const label = findChild(table, "ownHandLabel")
        const slider = findChild(table, "handScrollSlider")
        const handList = findChild(table, "ownHand")
        verify(header !== null)
        verify(label !== null)
        verify(slider !== null)
        verify(handList !== null)
        tryCompare(handList, "count", handSeats[0].hand.length)
        tryVerify(() => handList.contentWidth > handList.width)
        tryVerify(() => handList.itemAtIndex(0) !== null)

        compare(header.height, label.implicitHeight)
        verify(slider.visible)
        verify(slider.height <= header.height + 1)
        const handCard = handList.itemAtIndex(0)
        const fittedWidth = Math.max(
                    table.handCardWidth,
                    Math.round(handList.height * 63 / 88))
        compare(handCard.width, fittedWidth)
        verify(fittedWidth > table.handCardWidth)
        compare(handCard.height, handList.height)
        table.destroy()
    }

    function test_handSliderThumbDragMovesContent() {
        const handSeats = JSON.parse(JSON.stringify(mockWs.gameSeats))
        handSeats[0].hand = []
        for (let index = 0; index < 27; ++index) {
            handSeats[0].hand.push({
                "id": "s0-scroll-hand-" + index,
                "name": "Card " + index,
                "ownerSeat": 0
            })
        }
        handSeats[0].handCount = handSeats[0].hand.length
        mockWs.gameSeats = handSeats
        const table = tableComponent.createObject(tableHost, {
            "width": testWindow.width,
            "height": testWindow.height
        })
        verify(table !== null)

        const slider = findChild(table, "handScrollSlider")
        const thumb = findChild(table, "handScrollThumb")
        const handList = findChild(table, "ownHand")
        verify(slider !== null)
        verify(thumb !== null)
        verify(handList !== null)
        tryCompare(handList, "count", handSeats[0].hand.length)
        tryVerify(() => handList.contentWidth > handList.width)
        tryVerify(() => thumb.width >= 28)

        const startX = handList.contentX
        mouseDrag(thumb, thumb.width / 2, thumb.height / 2,
                  120, 0, Qt.LeftButton, Qt.NoModifier, 16)
        tryVerify(() => handList.contentX > startX + 8)
        compare(slider.from, handList.originX)
        compare(slider.to, handList.originX
                + Math.max(0, handList.contentWidth - handList.width))
        compare(slider.value, handList.contentX)
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
