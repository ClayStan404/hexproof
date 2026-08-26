// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtTest

TestCase {
    id: testCase
    name: "MatchLoading"
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

    function test_showsProgressAndRetriesFailures() {
        const progress = findChild(page, "matchLoadProgress")
        verify(progress !== null)
        compare(progress.value, 0.5)

        const retry = findChild(page, "retryMatchLoadButton")
        verify(retry !== null)
        verify(!retry.visible)
        mockLoader.failed = 1
        mockLoader.lastError = "Some card images could not be loaded."
        tryVerify(() => retry.visible)
        retry.clicked()
        compare(mockLoader.retryCount, 1)
    }

    function test_matchLoadingLeaveRequiresConfirmation() {
        const leave = findChild(page, "matchLoadingLeaveRoomButton")
        const confirmation =
            findChild(page, "matchLoadingLeaveConfirmation")
        verify(leave !== null)
        verify(confirmation !== null)

        leave.clicked()
        tryVerify(() => confirmation.opened)
        compare(mockWs.leaveRoomCount, 0)

        const confirm = findChild(confirmation, "confirmButton")
        verify(confirm !== null)
        confirm.clicked()
        compare(mockWs.leaveRoomCount, 1)
        tryVerify(() => !confirmation.opened)
    }

    function test_leaveButtonUsesRoomSessionPlaytest() {
        mockWs.playtest = false
        mockRoomSession.playtest = true
        const leave = findChild(page, "matchLoadingLeaveRoomButton")
        const confirmation =
            findChild(page, "matchLoadingLeaveConfirmation")
        verify(leave !== null)
        verify(confirmation !== null)
        compare(leave.text, "End playtest")
        compare(confirmation.titleText, "End this playtest?")
        compare(confirmation.confirmText, "End playtest")
    }

    function test_tableLeaveRequiresConfirmation() {
        const table = tableComponent.createObject(tableHost, {
            "width": testWindow.width,
            "height": testWindow.height
        })
        verify(table !== null)
        const leave = findChild(table, "leaveRoomButton")
        const confirmation = findChild(table, "leaveRoomConfirmation")
        verify(leave !== null)
        verify(confirmation !== null)

        leave.clicked()
        tryVerify(() => confirmation.opened)
        compare(mockWs.leaveRoomCount, 0)

        const confirm = findChild(confirmation, "confirmButton")
        verify(confirm !== null)
        confirm.clicked()
        compare(mockWs.leaveRoomCount, 1)
        tryVerify(() => !confirmation.opened)
    }

    function test_tableShellCreatesAfterLoading() {
        const table = tableComponent.createObject(tableHost, {
            "width": testWindow.width,
            "height": testWindow.height
        })
        verify(table !== null)
        verify(table.cardMoveCommands !== null)
        verify(table.optimisticCommands !== null)
        verify(table.gameValues !== null)
        verify(table.zoneState !== null)
        compare(typeof table.moveCardToBattlefield, "undefined")
        compare(typeof table.beginPendingCardMove, "undefined")
        compare(typeof table.displayedTapped, "undefined")
        const hand = findChild(table, "ownHand")
        verify(hand !== null)
        compare(hand.count, 1)
        const draw = findChild(table, "drawCardButton0")
        verify(draw !== null)
        verify(draw.enabled)
        draw.trigger()
        compare(mockWs.drawCount, 1)
        const libraryCardBack = findChild(table, "ownLibraryCardBack")
        verify(libraryCardBack !== null)
        verify(libraryCardBack.source.toString().endsWith("card-back.jpg"))
        const mulligan = findChild(table, "mulliganAction")
        verify(mulligan !== null)
        mockWs.mulligan()
        compare(mockWs.mulliganCount, 1)
        const drawMultiple = findChild(table, "drawCardsAction")
        const actionRail = findChild(table, "tableActionRail")
        const gameLogRail = findChild(table, "gameLogRail")
        const primaryColumnDivider =
            findChild(table, "primaryColumnDivider")
        verify(drawMultiple !== null)
        verify(actionRail !== null)
        verify(gameLogRail !== null)
        verify(primaryColumnDivider !== null)
        verify(drawMultiple.text.startsWith("Draw X cards"))
        compare(actionRail.width, table.actionRailWidth)
        compare(table.actionRailWidth, 144)
        compare(table.sharedZoneRailWidth, 92)
        compare(gameLogRail.width, table.gameLogRailWidth)
        compare(table.gameLogRailWidth, 176)
        verify(actionRail.mapToItem(table, 0, 0).x
               < gameLogRail.mapToItem(table, 0, 0).x)
        verify(primaryColumnDivider.visible)
        verify(primaryColumnDivider.width >= 1)
        const roomName = findChild(table, "tableRoomName")
        const roomCode = findChild(table, "tableRoomCode")
        const gameNumber = findChild(table, "tableGameNumber")
        const matchScore = findChild(table, "tableMatchScore")
        verify(roomName !== null)
        verify(roomCode !== null)
        verify(gameNumber !== null)
        verify(matchScore !== null)
        compare(roomName.text, "Friday Modern")
        compare(roomCode.text, "ROOM CODE · ABC123")
        compare(gameNumber.text, "Game 1")
        compare(matchScore.text, "0–0")
        verify(matchScore.font.pixelSize > gameNumber.font.pixelSize)
        const handSurface = findChild(table, "handSurface")
        const initialHandCard = findChild(table, "handCard0")
        const battlefieldCard = findChild(table, "battlefieldCards1-c1")
        verify(handSurface !== null)
        verify(initialHandCard !== null)
        verify(battlefieldCard !== null)
        const handAreaMenu = findChild(table, "handAreaMenu")
        const handCardMenu = findChild(table, "handCardMenu")
        verify(handAreaMenu !== null)
        verify(handCardMenu !== null)
        mouseClick(initialHandCard, initialHandCard.width / 2,
                   initialHandCard.height / 2, Qt.RightButton)
        tryVerify(() => handCardMenu.opened)
        verify(!handAreaMenu.opened)
        handCardMenu.close()
        tryVerify(() => !handCardMenu.opened)
        compare(handSurface.height, table.handAreaHeight)
        compare(initialHandCard.width, table.handCardWidth)
        compare(battlefieldCard.width, table.battlefieldCardWidth)
        verify(battlefieldCard.width < 92)
        const log = findChild(table, "gameLog")
        verify(log !== null)
        compare(log.count, 1)
        const chatInput = findChild(table, "gameChatInput")
        const sendChat = findChild(table, "sendGameChatButton")
        verify(chatInput !== null)
        verify(sendChat !== null)
        verify(chatInput.enabled)
        chatInput.text = "Good luck!"
        verify(sendChat.enabled)
        sendChat.clicked()
        compare(mockWs.sayCount, 1)
        compare(mockWs.lastSay, "Good luck!")
        compare(chatInput.text, "")
        const untap = findChild(table, "phaseButton0")
        const damage = findChild(table, "phaseButton7")
        const phaseStrip = findChild(table, "phaseStrip")
        const nextTurn = findChild(table, "nextTurnButton")
        const nextPhase = findChild(table, "nextPhaseButton")
        verify(untap !== null)
        verify(damage !== null)
        verify(phaseStrip !== null)
        verify(nextTurn !== null)
        verify(nextPhase !== null)
        verify(untap.enabled)
        damage.clicked()
        const rulesWarning = findChild(table, "rulesWarningDialog")
        verify(rulesWarning !== null)
        tryVerify(() => rulesWarning.opened)
        const warningConfirm = findChild(rulesWarning, "confirmButton")
        verify(warningConfirm !== null)
        warningConfirm.clicked()
        compare(mockWs.phaseCount, 1)
        compare(mockWs.lastPhase, "combat_damage")
        nextTurn.clicked()
        tryVerify(() => rulesWarning.opened)
        warningConfirm.clicked()
        compare(mockWs.nextTurnCount, 1)
        verify(findChild(table, "playersScroll") === null)
        verify(findChild(table, "stackCards") === null)
        verify(findChild(table, "revealedCards") === null)
        verify(findChild(table, "legacyGameLog") === null)
        compare(mockWs.nextTurnCount, 1)

        const revealHand = findChild(table, "revealHandAction")
        const shuffle = findChild(table, "shuffleLibraryAction")
        const createToken = findChild(table, "createTokenAction")
        const concede = findChild(table, "concedeAction")
        const settings = findChild(table, "tableSettingsButton")
        const leave = findChild(table, "leaveRoomButton")
        verify(revealHand !== null)
        verify(shuffle !== null)
        verify(createToken !== null)
        verify(concede !== null)
        verify(settings !== null)
        verify(leave !== null)
        compare(table.tableModalOpen, false)
        settings.clicked()
        const settingsPopup = findChild(table, "tableSettingsPopup")
        verify(settingsPopup !== null)
        tryVerify(() => settingsPopup.opened)
        tryCompare(table, "tableModalOpen", true)
        settingsPopup.close()
        tryVerify(() => !settingsPopup.opened)
        tryCompare(table, "tableModalOpen", false)
        verify(settings.mapToItem(actionRail, 0, 0).y
               < leave.mapToItem(actionRail, 0, 0).y)
        compare(leave.variant, "secondary")
        verify(revealHand.enabled)
        verify(revealHand.text.startsWith("Recall hand"))
        table.cardActions.toggleHandReveal()
        compare(mockWs.recallRevealedCount, 1)
        compare(mockWs.revealCount, 0)
        table.optimisticCommands.clearPendingCardMoves()

        const sharedCards = findChild(table, "sharedCards")
        verify(sharedCards !== null)
        compare(sharedCards.count, 2)
        const stackCard = findChild(table, "sharedCard0")
        const stackOwner = findChild(table, "sharedCardOwner0")
        verify(stackCard !== null)
        verify(stackOwner !== null)
        compare(stackCard.width, sharedCards.width)
        compare(stackOwner.text, "Alice")
        verify(stackOwner.visible)
        verify(stackOwner.mapToItem(stackCard, 0, 0).y > 10)
        mouseClick(stackCard)
        const sharedChooseTarget = findChild(
                                     table, "sharedChooseTargetButton")
        const sharedTargetMenu = findChild(table, "sharedTargetMenu")
        const sharedTargetSeat = findChild(table, "sharedTargetSeat1Action")
        verify(sharedChooseTarget !== null)
        verify(sharedTargetMenu !== null)
        verify(sharedTargetSeat !== null)
        tryVerify(() => sharedChooseTarget.visible)
        sharedChooseTarget.clicked()
        tryVerify(() => sharedTargetMenu.opened)
        sharedTargetSeat.triggered()
        compare(mockWs.setArrowCount, 1)
        compare(mockWs.lastArrow.sourceCardIds[0], "s0-stack")
        compare(mockWs.lastArrow.kind, "target")
        compare(mockWs.lastArrow.targetSeat, 1)
        mouseClick(stackCard)
        const toGraveyard = findChild(table, "sharedToGraveyardButton")
        verify(toGraveyard !== null)
        tryVerify(() => toGraveyard.visible)
        toGraveyard.clicked()
        compare(mockWs.moveCount, 1)
        compare(mockWs.lastMove.cardId, "s0-stack")
        compare(mockWs.lastMove.fromZone, "stack")
        compare(mockWs.lastMove.toZone, "graveyard")
        compare(mockWs.lastMove.toSeat, 0)

        mockWs.moveCount = 0
        tryVerify(() => findChild(table, "sharedCard1") !== null)
        const revealedCard = findChild(table, "sharedCard1")
        verify(revealedCard !== null)
        mouseClick(revealedCard)
        const toHand = findChild(table, "sharedToHandButton")
        verify(toHand !== null)
        tryVerify(() => toHand.visible)
        toHand.clicked()
        compare(mockWs.moveCount, 1)
        compare(mockWs.lastMove.cardId, "s0-reveal")
        compare(mockWs.lastMove.fromZone, "reveal")
        compare(mockWs.lastMove.toZone, "hand")
        compare(mockWs.lastMove.toSeat, -1)

        mockWs.moveCount = 0
        table.cardMoveCommands.moveCardToBattlefield("s0-c1", "hand", 0, 0.25, 0.6)
        compare(mockWs.moveCount, 1)
        compare(mockWs.lastMove.cardId, "s0-c1")
        compare(mockWs.lastMove.fromZone, "hand")
        compare(mockWs.lastMove.toZone, "battlefield")
        compare(mockWs.lastMove.toSeat, 0)
        compare(mockWs.lastMove.position.x, 0.25)
        compare(mockWs.lastMove.position.y, 0.6)
        table.cardMoveCommands.clearPendingBattlefieldMove()

        const ownBattlefield = findChild(table, "battlefieldZone0")
        const opponentBattlefield = findChild(table, "battlefieldZone1")
        const ownDropArea = findChild(table, "battlefieldDropArea")
        const opponentDropArea = findChild(table, "opponentBattlefieldDropArea1")
        const opponentCard = findChild(table, "battlefieldCards1-c1")
        verify(ownBattlefield !== null)
        verify(opponentBattlefield !== null)
        verify(ownDropArea !== null)
        verify(opponentDropArea !== null)
        verify(opponentCard !== null)
        verify(opponentCard.visible)
        verify(opponentBattlefield.y < ownBattlefield.y)
        verify(ownDropArea.enabled)
        verify(opponentDropArea.enabled)

        mockWs.moveCount = 0
        mockWs.lastMove = ({})
        const handCard = findChild(table, "handCard0")
        verify(handCard !== null)
        const dropPoint = ownDropArea.mapToItem(
                            handCard, ownDropArea.width * 0.7,
                            ownDropArea.height * 0.55)
        mouseDrag(handCard, handCard.width / 2, handCard.height / 2,
                  (dropPoint.x - handCard.width / 2) * 0.55,
                  (dropPoint.y - handCard.height / 2) * 0.55,
                  Qt.LeftButton, Qt.NoModifier, 30)
        tryCompare(mockWs, "moveCount", 1)
        compare(mockWs.lastMove.cardId, "s0-c1")
        const pendingCard = findChild(table, "pendingBattlefieldCard")
        verify(pendingCard !== null)
        tryVerify(() => pendingCard.visible)
        verify(!pendingCard.enabled)

        const updatedSeats = JSON.parse(JSON.stringify(mockWs.gameSeats))
        updatedSeats[0].hand = []
        updatedSeats[0].handCount = 0
        updatedSeats[0].battlefield = [{
            "id": "s0-c1",
            "name": "Lightning Bolt",
            "setCode": "M11",
            "collectorNumber": "149",
            "position": {
                "x": mockWs.lastMove.position.x,
                "y": mockWs.lastMove.position.y
            }
        }]
        mockWs.gameSeats = updatedSeats
        tryVerify(() => findChild(table, "battlefieldCards0-c1") !== null)
        const ownPermanent = findChild(table, "battlefieldCards0-c1")
        const ownPermanentDrag = findChild(table, "battlefieldDrags0-c1")
        verify(ownPermanent.x >= 0)
        verify(ownPermanentDrag !== null)
        tryVerify(() => !pendingCard.visible)

        table.cardMoveCommands.moveCardToBattlefield(
                    "s0-c1", "battlefield", 0, 0.3, 0.45)
        compare(mockWs.moveCount, 2)
        compare(mockWs.lastMove.cardId, "s0-c1")
        compare(mockWs.lastMove.fromZone, "battlefield")
        compare(mockWs.lastMove.toZone, "battlefield")
        const repositionPending = findChild(table, "pendingBattlefieldCard")
        verify(repositionPending !== null)
        tryVerify(() => repositionPending.visible)

        table.cardMoveCommands.moveCardToBattlefield("s0-c1", "battlefield",
                                    1, 0.4, 0.5)
        compare(mockWs.lastMove.toSeat, 1)
        table.destroy()
    }

    function test_spectatorHandViewerIsReadOnlyAndSeatScoped() {
        mockWs.roomRole = "spectator"
        mockWs.seatIndex = -1
        mockRoomSession.spectatorsSeeHands = true
        mockWs.gameSeats[1].hand = [{
            "id": "s1-hand",
            "name": "Island",
            "setCode": "M11",
            "collectorNumber": "235"
        }]
        mockWs.gameSeats[1].handCount = 1
        syncTestGameTable()

        const table = tableComponent.createObject(tableHost, {
            "width": testWindow.width,
            "height": testWindow.height
        })
        verify(table !== null)
        const handList = findChild(table, "spectatorHandList")
        const aliceTab = findChild(table, "spectatorHandSeat0")
        const bobTab = findChild(table, "spectatorHandSeat1")
        verify(handList !== null)
        verify(aliceTab !== null)
        verify(bobTab !== null)
        compare(handList.count, 1)

        bobTab.clicked()
        tryCompare(handList, "count", 1)
        const card = findChild(table, "spectatorHandCard0")
        verify(card !== null)
        const handCardMenu = findChild(table, "handCardMenu")
        verify(handCardMenu !== null)
        mouseClick(card, card.width / 2, card.height / 2,
                   Qt.RightButton)
        verify(!handCardMenu.opened)
    }

    function test_handAreaOffersRandomAndWholeHandDiscard() {
        const table = tableComponent.createObject(tableHost, {
            "width": testWindow.width,
            "height": testWindow.height
        })
        verify(table !== null)

        const randomDiscard = findChild(table, "discardRandomHandCardAction")
        const discardAll = findChild(table, "discardEntireHandAction")
        const confirmation = findChild(table, "discardHandConfirmation")
        verify(randomDiscard !== null)
        verify(discardAll !== null)
        verify(confirmation !== null)
        verify(randomDiscard.enabled)
        verify(discardAll.enabled)

        randomDiscard.triggered()
        compare(mockWs.discardHandCount, 1)
        compare(mockWs.lastDiscardAll, false)

        discardAll.triggered()
        tryVerify(() => confirmation.opened)
        const confirm = findChild(confirmation, "confirmButton")
        verify(confirm !== null)
        confirm.clicked()
        compare(mockWs.discardHandCount, 2)
        compare(mockWs.lastDiscardAll, true)
        tryVerify(() => !confirmation.opened)
        table.destroy()
    }

    function test_libraryTopBatchMoveKeepsDestinationUntilSubmit() {
        const table = tableComponent.createObject(tableHost, {
            "width": testWindow.width,
            "height": testWindow.height
        })
        verify(table !== null)

        table.sessionUi.showLibraryMoveCardsEditor("exile")
        const popup = table.libraryMoveCardsEditor
        tryVerify(() => popup.opened)
        const field = findChild(popup, "numberInputField")
        verify(field !== null)
        field.text = "3"
        popup.submit()

        compare(mockWs.moveLibraryCardsCount, 1)
        compare(mockWs.lastMoveLibraryCardsCount, 3)
        compare(mockWs.lastMoveLibraryDestination, "exile")
        compare(table.libraryMoveDestination, "")
        tryVerify(() => !popup.opened)
        table.destroy()
    }

    function test_manualGameUtilitiesRequireConfirmationAndSendCommands() {
        mockWs.youAreHost = true
        const table = tableComponent.createObject(tableHost, {
            "width": testWindow.width,
            "height": testWindow.height
        })
        verify(table !== null)

        const drawAction = findChild(table, "declareDrawAction")
        const drawDialog = findChild(table, "drawConfirmation")
        verify(drawAction !== null)
        verify(drawDialog !== null)
        drawAction.clicked()
        tryVerify(() => drawDialog.opened)
        findChild(drawDialog, "confirmButton").clicked()
        compare(mockWs.declareDrawCount, 1)

        const restartAction = findChild(table, "restartGameAction")
        const restartDialog = findChild(table, "restartConfirmation")
        verify(restartAction !== null)
        verify(restartAction.enabled)
        restartAction.clicked()
        tryVerify(() => restartDialog.opened)
        findChild(restartDialog, "confirmButton").clicked()
        compare(mockWs.restartGameCount, 1)

        const rollAction = findChild(table, "rollDiceAction")
        const dicePopup = findChild(table, "diceRollPopup")
        verify(rollAction !== null)
        verify(dicePopup !== null)
        rollAction.clicked()
        tryVerify(() => dicePopup.opened)
        compare(findChild(dicePopup, "diceSidesField").text, "20")
        compare(findChild(dicePopup, "diceCountField").text, "1")
        findChild(dicePopup, "rollDiceButton").clicked()
        compare(mockWs.rollDiceCount, 1)
        compare(mockWs.lastDiceRoll.sides, 20)
        compare(mockWs.lastDiceRoll.count, 1)

        findChild(table, "flipCoinAction").clicked()
        compare(mockWs.flipCoinCount, 1)
        findChild(table, "randomPlayerAction").clicked()
        compare(mockWs.randomPlayerCount, 1)
        findChild(table, "randomBattlefieldCardAction").clicked()
        compare(mockWs.randomCardsCount, 1)
        compare(mockWs.lastRandomCards.length, 1)
        compare(mockWs.lastRandomCards[0], "s1-c1")
    }

    function test_overflowingHandScrollsWithMouseWheel() {
        const originalSeats = mockWs.gameSeats
        const seats = JSON.parse(JSON.stringify(mockWs.baselineGameSeats))
        seats[0].hand = []
        for (let index = 0; index < 18; ++index) {
            seats[0].hand.push({
                "id": "wheel-card-" + index,
                "name": "Wheel card " + index,
                "ownerSeat": 0
            })
        }
        seats[0].handCount = seats[0].hand.length
        mockWs.gameSeats = seats

        const table = tableComponent.createObject(tableHost, {
            "width": testWindow.width,
            "height": testWindow.height
        })
        verify(table !== null)
        const hand = findChild(table, "ownHand")
        const wheelMouseArea = findChild(table, "handWheelMouseArea")
        verify(hand !== null)
        verify(wheelMouseArea !== null)
        tryVerify(() => hand.count === 18
                  && hand.contentWidth > hand.width)
        const hoveredCard = findChild(table, "handCard5")
        verify(hoveredCard !== null)

        hand.contentX = 0
        mouseWheel(hoveredCard, hoveredCard.width / 2,
                   hoveredCard.height / 2,
                   0, -120, Qt.NoButton, Qt.NoModifier)
        tryVerify(() => hand.contentX > 0)
        const scrolledX = hand.contentX
        mouseWheel(hoveredCard, hoveredCard.width / 2,
                   hoveredCard.height / 2,
                   0, 120, Qt.NoButton, Qt.NoModifier)
        tryVerify(() => hand.contentX < scrolledX)

        table.destroy()
        mockWs.gameSeats = originalSeats
    }

    function test_gameLogRailCanBeHiddenAndRestored() {
        const table = tableComponent.createObject(tableHost, {
            "width": testWindow.width,
            "height": testWindow.height
        })
        verify(table !== null)
        const settings = findChild(table, "tableSettingsButton")
        const settingsPopup = findChild(table, "tableSettingsPopup")
        const gameLogRail = findChild(table, "gameLogRail")
        const restore = findChild(table, "restoreGameLogRailButton")
        verify(settings !== null)
        verify(settingsPopup !== null)
        verify(gameLogRail !== null)
        verify(restore !== null)

        settings.clicked()
        tryVerify(() => settingsPopup.opened)
        const gameLogToggle =
            findChild(settingsPopup, "showGameLogToggle")
        const apply = findChild(settingsPopup, "applyTableSettingsButton")
        verify(gameLogToggle !== null)
        verify(apply !== null)
        verify(gameLogToggle.checked)
        gameLogToggle.checked = false
        apply.clicked()
        tryVerify(() => !gameLogRail.visible)
        verify(restore.visible)
        verify(!mockPreferences.tableShowGameLog)

        restore.clicked()
        tryVerify(() => gameLogRail.visible)
        verify(!restore.visible)
        verify(mockPreferences.tableShowGameLog)
        table.destroy()
    }

    function test_libraryTopDragMovesToBattlefieldAndHand() {
        const table = tableComponent.createObject(tableHost, {
            "width": testWindow.width,
            "height": testWindow.height
        })
        verify(table !== null)

        const library = findChild(table, "ownLibraryZone")
        const battlefield = findChild(table, "battlefieldDropArea")
        const hand = findChild(table, "handDropArea")
        verify(library !== null)
        verify(battlefield !== null)
        verify(hand !== null)
        verify(library.enabled)
        verify(battlefield.enabled)
        verify(hand.enabled)
        verify(hand.width > 0)
        verify(hand.height > 0)

        const startX = library.width / 2
        const startY = library.height / 2
        let destination = battlefield.mapToItem(
                    library, battlefield.width * 0.55,
                    battlefield.height * 0.65)
        mouseDrag(library, startX, startY,
                  destination.x - startX, destination.y - startY,
                  Qt.LeftButton, Qt.NoModifier, 30)
        tryCompare(mockWs, "moveCount", 1)
        compare(mockWs.lastMove.cardId, "__library_top__")
        compare(mockWs.lastMove.fromZone, "library")
        compare(mockWs.lastMove.toZone, "battlefield")

        table.cardMoveCommands.clearPendingBattlefieldMove()
        wait(1)
        destination = hand.mapToItem(
                    library, hand.width * 0.75, hand.height * 0.5)
        mouseDrag(library, startX, startY,
                  destination.x - startX, destination.y - startY,
                  Qt.LeftButton, Qt.NoModifier, 30)
        tryCompare(mockWs, "moveCount", 2)
        compare(mockWs.lastMove.cardId, "__library_top__")
        compare(mockWs.lastMove.fromZone, "library")
        compare(mockWs.lastMove.toZone, "hand")
        compare(mockWs.lastMove.toSeat, -1)

        table.destroy()
    }

    function test_p7ShuffleAndBattlefieldRelationCommands() {
        const relationSeats = JSON.parse(JSON.stringify(mockWs.gameSeats))
        relationSeats[1].battlefield[0].ownerSeat = 0
        relationSeats[0].battlefield = [{
            "id": "s0-permanent",
            "name": "Raging Goblin",
            "setCode": "10E",
            "collectorNumber": "225",
            "position": {"x": 0.3, "y": 0.55}
        }]
        mockWs.gameSeats = relationSeats

        const table = tableComponent.createObject(tableHost, {
            "width": testWindow.width,
            "height": testWindow.height
        })
        verify(table !== null)

        const shuffle = findChild(table, "shuffleLibraryAction")
        verify(shuffle !== null)
        verify(shuffle.enabled)
        mockWs.shuffleLibrary()
        compare(mockWs.shuffleLibraryCount, 1)

        const ownPermanent = findChild(table, "battlefieldCards0-permanent")
        const remoteOwnerBadge = findChild(
                                   table,
                                   "battlefieldOwnerBadges1-c1")
        verify(ownPermanent !== null)
        verify(remoteOwnerBadge !== null)
        verify(remoteOwnerBadge.visible)
        compare(remoteOwnerBadge.toolTipText, "Owner · Alice")
        const remoteOwnerGlyph = findChild(
                                   remoteOwnerBadge,
                                   "battlefieldOwnerGlyphs1-c1")
        verify(remoteOwnerGlyph !== null)
        compare(remoteOwnerGlyph.text, "◇")
        const battlefieldAreaMenu =
            findChild(table, "battlefieldAreaMenu")
        const cardToolsMenu = findChild(table, "cardToolsMenu")
        const targetBattlefieldCard =
            findChild(table, "targetBattlefieldCardAction")
        const targetSeat = findChild(table, "targetSeat1Action")
        verify(battlefieldAreaMenu !== null)
        verify(cardToolsMenu !== null)
        verify(targetBattlefieldCard !== null)
        verify(targetSeat !== null)
        mouseClick(ownPermanent, ownPermanent.width / 2,
                   ownPermanent.height / 2, Qt.RightButton)
        tryVerify(() => cardToolsMenu.opened)
        verify(!battlefieldAreaMenu.opened)
        cardToolsMenu.close()
        tryVerify(() => !cardToolsMenu.opened)
        mouseMove(ownPermanent, ownPermanent.width / 2,
                  ownPermanent.height / 2)
        table.presentation.inspectCard(relationSeats[0].battlefield[0], ownPermanent)
        const hoverPreview = findChild(table, "cardHoverPreview")
        const previewArt = findChild(table, "cardHoverPreviewArt")
        const previewName = findChild(table, "cardHoverPreviewName")
        verify(hoverPreview !== null)
        verify(previewArt !== null)
        verify(previewName !== null)
        verify(!previewName.visible)
        tryVerify(() => hoverPreview.visible)
        compare(hoverPreview.height,
                Math.round(hoverPreview.width * 88 / 63))
        table.selection.selectCard(relationSeats[0].battlefield[0], 0)
        targetSeat.triggered()
        compare(mockWs.setArrowCount, 1)
        compare(mockWs.lastArrow.sourceCardIds[0], "s0-permanent")
        compare(mockWs.lastArrow.kind, "target")
        compare(mockWs.lastArrow.targetSeat, 1)

        table.selection.selectCard(relationSeats[0].battlefield[0], 0)
        targetBattlefieldCard.triggered()
        table.selection.selectCard(relationSeats[1].battlefield[0], 1)
        compare(mockWs.setArrowCount, 2)
        compare(mockWs.lastArrow.sourceCardIds[0], "s0-permanent")
        compare(mockWs.lastArrow.kind, "target")
        compare(mockWs.lastArrow.targetCardId, "s1-c1")

        table.selection.selectCard(relationSeats[0].battlefield[0], 0)
        table.selection.beginRelationTarget("attack")
        table.selection.selectCard(relationSeats[1].battlefield[0], 1)
        const combatPopup = findChild(table, "combatDeclarationPopup")
        const confirmCombat = findChild(
                                  combatPopup,
                                  "confirmCombatDeclarationButton")
        verify(combatPopup !== null)
        verify(confirmCombat !== null)
        tryVerify(() => combatPopup.opened)
        confirmCombat.clicked()
        compare(mockWs.setArrowCount, 3)
        compare(mockWs.lastArrow.sourceCardIds[0], "s0-permanent")
        compare(mockWs.lastArrow.kind, "attack")
        compare(mockWs.lastArrow.targetCardId, "s1-c1")
        compare(mockWs.lastArrow.targetSeat, -1)
        compare(mockWs.lastArrow.tappedSourceCardIds.length, 1)
        compare(mockWs.lastArrow.tappedSourceCardIds[0], "s0-permanent")

        mouseDoubleClickSequence(ownPermanent, ownPermanent.width / 2,
                                 ownPermanent.height / 2, Qt.LeftButton)
        compare(mockWs.setTappedCount, 1)
        compare(mockWs.lastTapped.cardId, "s0-permanent")
        verify(!mockWs.lastTapped.tapped)

        mockWs.gameArrows = [{
            "seat": 0,
            "sourceCardId": "s0-permanent",
            "kind": "attack",
            "targetSeat": 1
        }]
        const playerAttackBadge = findChild(
                                      table,
                                      "playerAttackBadges0-permanent")
        verify(playerAttackBadge !== null)
        tryVerify(() => playerAttackBadge.visible)
        const playerAttackLabel = findChild(
                                      playerAttackBadge,
                                      "playerAttackLabels0-permanent")
        verify(playerAttackLabel !== null)
        compare(playerAttackLabel.text, "Attacking Bob")

        table.selection.selectCard(relationSeats[0].battlefield[0], 0)
        table.battlefieldInteractionMode = "attach"
        table.selection.selectCard(relationSeats[1].battlefield[0], 1)
        compare(mockWs.setAttachmentCount, 1)
        compare(mockWs.lastAttachment.sourceCardId, "s0-permanent")
        compare(mockWs.lastAttachment.targetCardId, "s1-c1")

        table.selection.selectCard(relationSeats[0].battlefield[0], 0)
        const attachTo = findChild(table, "attachToAction")
        const detach = findChild(table, "detachAttachmentAction")
        verify(attachTo !== null)
        verify(detach !== null)
        verify(attachTo.enabled)
        verify(!detach.enabled)
        attachTo.triggered()
        compare(table.battlefieldInteractionMode, "attach")
        table.selection.clear()

        mockWs.gameAttachments = [{
            "sourceCardId": "s0-permanent",
            "targetCardId": "s1-c1"
        }]
        tryVerify(() => !ownPermanent.visible)
        tryVerify(() => findChild(table, "attachmentOverlays0-permanent") !== null)
        const overlay = findChild(table, "attachmentOverlays0-permanent")
        tryVerify(() => overlay.visible)
        mouseClick(overlay, overlay.width / 2, overlay.height / 2)
        compare(table.selectedBattlefieldCardId, "s0-permanent")
        verify(detach.enabled)

        table.destroy()
    }

}
