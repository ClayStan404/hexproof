// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtTest

TestCase {
    id: testCase
    name: "TableZones"
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

    function test_viewLibraryTopCardUsesContextDestinations() {
        const table = tableComponent.createObject(tableHost, {
            "width": testWindow.width,
            "height": testWindow.height
        })
        verify(table !== null)
        const viewTopCard =
            findChild(table, "viewLibraryTopCardAction")
        const viewTopCards =
            findChild(table, "viewLibraryTopCardsAction")
        const moveTopToGraveyard =
            findChild(table, "moveLibraryTopToGraveyardAction")
        const moveTopToExile =
            findChild(table, "moveLibraryTopToExileAction")
        verify(viewTopCard !== null)
        verify(viewTopCards !== null)
        verify(moveTopToGraveyard !== null)
        verify(moveTopToExile !== null)
        verify(!viewTopCard.text.includes("\t"))
        verify(viewTopCard.text.endsWith("Ctrl+Shift+L"))
        verify(!viewTopCards.text.includes("\t"))
        verify(viewTopCards.text.endsWith("Ctrl+L"))
        verify(moveTopToGraveyard.text.endsWith("Ctrl+Shift+G"))
        verify(moveTopToExile.text.endsWith("Ctrl+Shift+E"))
        table.ownLibraryMenu.open()
        tryVerify(() => table.ownLibraryMenu.opened)
        verify(viewTopCard.contentItem.width + 1
               >= viewTopCard.contentItem.implicitWidth,
               "View-top-card menu text must not be elided")
        verify(viewTopCards.contentItem.width + 1
               >= viewTopCards.contentItem.implicitWidth,
               "View-top-cards menu text must not be elided")
        verify(moveTopToGraveyard.contentItem.width + 1
               >= moveTopToGraveyard.contentItem.implicitWidth,
               "Move-to-graveyard menu text must not be elided")
        verify(moveTopToExile.contentItem.width + 1
               >= moveTopToExile.contentItem.implicitWidth,
               "Move-to-exile menu text must not be elided")
        table.ownLibraryMenu.close()
        verify(viewTopCard.enabled)
        viewTopCard.triggered()
        compare(mockWs.dumpLibraryCount, 1)
        compare(mockWs.lastDumpLibrarySeat, 0)
        compare(mockWs.lastDumpTopCount, 1)

        mockWs.libraryDumped([{
            "id": "s0-top1",
            "name": "Forest",
            "setCode": "M19",
            "collectorNumber": "277",
            "typeLine": "Basic Land — Forest"
        }], 0, "", 1)
        const popup = findChild(table, "librarySearchPopup")
        verify(popup !== null)
        tryVerify(() => popup.opened)
        verify(popup.topCardMode)
        verify(!popup.reorderMode)
        const cards = findChild(popup, "librarySearchCards")
        verify(cards !== null)
        tryVerify(() => cards.itemAtIndex(0) !== null)
        const topCard = cards.itemAtIndex(0)
        const selection = findChild(topCard, "librarySelectBox0")
        const libraryCardMenu = findChild(popup, "libraryCardMenu")
        const topOrderedAction =
            findChild(popup, "libraryContextSourceTopOrdered")
        const topRandomAction =
            findChild(popup, "libraryContextSourceTopRandom")
        const bottomOrderedAction =
            findChild(popup, "libraryContextSourceBottomOrdered")
        const bottomRandomAction =
            findChild(popup, "libraryContextSourceBottomRandom")
        verify(topCard !== null)
        verify(selection !== null)
        verify(!selection.visible)
        verify(libraryCardMenu !== null)
        verify(topOrderedAction !== null)
        verify(topRandomAction !== null)
        verify(bottomOrderedAction !== null)
        verify(bottomRandomAction !== null)
        mouseClick(topCard, topCard.width / 2,
                   topCard.height / 2, Qt.RightButton)
        tryVerify(() => libraryCardMenu.opened)
        verify(topOrderedAction.visible)
        verify(!topRandomAction.visible)
        verify(bottomOrderedAction.visible)
        verify(!bottomRandomAction.visible)
        bottomOrderedAction.triggered()

        compare(mockWs.searchLibraryCount, 1)
        compare(mockWs.lastLibrarySearch.cardIds.length, 1)
        compare(mockWs.lastLibrarySearch.cardIds[0], "s0-top1")
        compare(mockWs.lastLibrarySearch.toZone, "library_bottom")
        compare(mockWs.lastLibrarySearch.randomize, false)
        compare(mockWs.lastLibrarySearch.toSeat, 0)
        tryVerify(() => !popup.opened)
        table.destroy()
    }

    function test_lifeControlsOnlyEditOwnSeat() {
        const table = tableComponent.createObject(tableHost, {
            "width": testWindow.width,
            "height": testWindow.height
        })
        verify(table !== null)

        const decrease = findChild(table, "decreaseLifeButton0")
        const increase = findChild(table, "increaseLifeButton0")
        const exact = findChild(table, "setLifeButton0")
        const opponentIncrease = findChild(table, "increaseLifeButton1")
        verify(decrease !== null)
        verify(increase !== null)
        verify(exact !== null)
        verify(opponentIncrease === null)
        verify(decrease.visible)
        verify(increase.visible)
        verify(exact.visible)

        decrease.clicked()
        compare(mockWs.setCounterCallCount, 1)
        compare(mockWs.lastCounter.counter, "life")
        compare(mockWs.lastCounter.value, 19)
        increase.clicked()
        compare(mockWs.setCounterCallCount, 2)
        compare(mockWs.lastCounter.counter, "life")
        compare(mockWs.lastCounter.value, 20)

        exact.clicked()
        const popup = findChild(table, "lifeEditorPopup")
        verify(popup !== null)
        const field = findChild(popup, "lifeEditorField")
        const confirm = findChild(popup, "confirmLifeEditorButton")
        verify(field !== null)
        verify(confirm !== null)
        tryVerify(() => popup.opened)
        compare(field.text, "20")
        field.text = "-4"
        verify(confirm.enabled)
        confirm.clicked()
        compare(mockWs.setCounterCallCount, 3)
        compare(mockWs.lastCounter.counter, "life")
        compare(mockWs.lastCounter.value, -4)
        tryVerify(() => !popup.opened)

        mockWs.roomRole = "spectator"
        tryVerify(() => !decrease.visible && !increase.visible && !exact.visible)
        table.destroy()
    }

    function test_optimisticValuesExpireIndependently() {
        const table = tableComponent.createObject(tableHost, {
            "width": testWindow.width,
            "height": testWindow.height,
            "optimisticValueTimeoutMs": 500
        })
        verify(table !== null)

        table.optimisticCommandModel.lifeValues = ({"0": 19})
        table.optimisticCommands.trackOptimisticValues("life", ["0"])
        wait(250)
        table.optimisticCommandModel.counterValues = ({"0:counter-1": 1})
        table.optimisticCommands.trackOptimisticValues("counter", ["0:counter-1"])

        tryVerify(() => !Object.prototype.hasOwnProperty.call(
                      table.optimisticLifeTotals, "0"), 500)
        verify(Object.prototype.hasOwnProperty.call(
                   table.optimisticCounterValues, "0:counter-1"))
        tryVerify(() => !Object.prototype.hasOwnProperty.call(
                      table.optimisticCounterValues, "0:counter-1"), 500)
        table.destroy()
    }

    function test_commandErrorsRollbackOnlyTheirOptimisticAction() {
        const table = tableComponent.createObject(tableHost, {
            "width": testWindow.width,
            "height": testWindow.height
        })
        verify(table !== null)

        table.optimisticCommandModel.tappedValues = ({
            "card-a": true,
            "card-b": false
        })
        table.optimisticCommands.trackOptimisticValues("tapped", ["card-a", "card-b"])
        mockWs.commandQueued(
                    "tap-a", "game.set_tapped",
                    {"cardId": "card-a", "tapped": true})
        mockWs.commandQueued(
                    "tap-b", "game.set_tapped",
                    {"cardId": "card-b", "tapped": false})

        mockWs.commandFailed(
                    "chat", "game.say", {"message": "hello"},
                    "invalid chat")
        verify(Object.prototype.hasOwnProperty.call(
                   table.optimisticTappedCards, "card-a"))
        verify(Object.prototype.hasOwnProperty.call(
                   table.optimisticTappedCards, "card-b"))

        mockWs.commandFailed(
                    "tap-a", "game.set_tapped",
                    {"cardId": "card-a", "tapped": true},
                    "not controller")
        verify(!Object.prototype.hasOwnProperty.call(
                   table.optimisticTappedCards, "card-a"))
        verify(Object.prototype.hasOwnProperty.call(
                   table.optimisticTappedCards, "card-b"))

        table.optimisticCommands.beginPendingCardMove(
                    "move-a", {"id": "move-a"}, "hand", 0,
                    "graveyard", 0)
        table.optimisticCommands.beginPendingCardMove(
                    "move-b", {"id": "move-b"}, "hand", 0,
                    "exile", 0)
        mockWs.commandQueued(
                    "request-a", "game.move_card",
                    {"cardId": "move-a"})
        mockWs.commandQueued(
                    "request-b", "game.move_card",
                    {"cardId": "move-b"})
        mockWs.commandFailed(
                    "request-a", "game.move_card",
                    {"cardId": "move-a"}, "invalid target")
        verify(!Object.prototype.hasOwnProperty.call(
                   table.pendingCardMoves, "move-a"))
        verify(Object.prototype.hasOwnProperty.call(
                   table.pendingCardMoves, "move-b"))

        table.optimisticCommandModel.beginPhase("draw")
        mockWs.commandQueued(
                    "phase", "game.set_phase", {"phase": "draw"})
        mockWs.commandFailed(
                    "counter", "game.set_counter",
                    {"counter": "life", "value": 19}, "invalid counter")
        compare(table.optimisticPhase, "draw")
        mockWs.commandFailed(
                    "phase", "game.set_phase",
                    {"phase": "draw"}, "not active")
        compare(table.optimisticPhase, "")
        table.destroy()
    }

    function test_playerCounterPipsAdjustAndRenameOwnSlots() {
        const table = tableComponent.createObject(tableHost, {
            "width": testWindow.width,
            "height": testWindow.height
        })
        verify(table !== null)

        const ownPip = findChild(table, "playerCounterPip0-0")
        const ownLastPip = findChild(table, "playerCounterPip0-6")
        const opponentPip = findChild(table, "playerCounterPip1-0")
        const opponentLastPip = findChild(table, "playerCounterPip1-6")
        verify(ownPip !== null)
        verify(ownLastPip !== null)
        verify(opponentPip !== null)
        verify(opponentLastPip === null)
        verify(ownPip.editable)
        verify(!opponentPip.editable)
        verify(ownPip.activeFocusOnTab)
        compare(ownPip.accessibleSummary, "Counter · 0")
        const chatInput = findChild(table, "gameChatInput")
        verify(chatInput !== null)
        chatInput.text = "Keep this draft"
        testWindow.requestActivate()
        tryVerify(() => testWindow.active)
        chatInput.forceActiveFocus()
        tryVerify(() => chatInput.activeFocus)
        const ownPipLabel = findChild(ownPip, "playerCounterLabel")
        verify(ownPipLabel !== null)
        compare(ownPipLabel.text, "")
        compare(opponentPip.label, "Energy")
        compare(opponentPip.value, 3)
        mouseClick(ownPip, ownPip.width * 0.18, ownPip.height / 2,
                   Qt.LeftButton)
        compare(mockWs.adjustCounterCount, 0)
        compare(table.selectedCounterKey, "counter-1")
        compare(table.selectedCounterSeat, 0)
        tryVerify(() => !chatInput.activeFocus)
        compare(ownPipLabel.text, "I rename · S set")

        mouseClick(ownPip, ownPip.width * 0.18, ownPip.height / 2,
                   Qt.LeftButton)
        compare(mockWs.adjustCounterCount, 1)
        compare(mockWs.lastCounterAdjustment.counter, "counter-1")
        compare(mockWs.lastCounterAdjustment.delta, 1)

        mouseClick(ownPip, ownPip.width * 0.18, ownPip.height / 2,
                   Qt.RightButton)
        compare(mockWs.adjustCounterCount, 2)
        compare(mockWs.lastCounterAdjustment.delta, -1)

        compare(mockWs.adjustCounterCount, 2)
        compare(table.selectedCounterKey, "counter-1")
        compare(table.selectedCounterSeat, 0)
        keyClick(Qt.Key_I)
        compare(chatInput.text, "Keep this draft")
        const popup = findChild(table, "counterLabelPopup")
        verify(popup !== null)
        const field = findChild(popup, "counterLabelField")
        const confirm = findChild(popup, "confirmCounterLabelButton")
        verify(field !== null)
        verify(confirm !== null)
        tryVerify(() => popup.opened)
        compare(field.text, "")
        field.text = "Energy"
        confirm.clicked()
        compare(mockWs.renameCounterCount, 1)
        compare(mockWs.lastCounterRename.counter, "counter-1")
        compare(mockWs.lastCounterRename.label, "Energy")
        tryVerify(() => !popup.opened)

        mockWs.roomRole = "spectator"
        tryVerify(() => !ownPip.editable)
        table.destroy()
    }

    function test_coordinationStateKeyboardAndInvalidDropFeedback() {
        const seats = JSON.parse(
                          JSON.stringify(mockWs.baselineGameSeats))
        seats[0].mulliganCount = 1
        seats[1].mulliganCount = 2
        seats[0].hand.push({
            "id": "s0-c2",
            "name": "Mountain",
            "setCode": "M11",
            "collectorNumber": "242"
        })
        seats[0].handCount = 2
        mockWs.gameSeats = seats
        syncTestGameTable()

        const table = tableComponent.createObject(tableHost, {
            "width": testWindow.width,
            "height": testWindow.height
        })
        verify(table !== null)

        const ownMulligan = findChild(table, "ownMulliganCount")
        const remoteSummary = findChild(
                                  table, "battlefieldPlayerSummary1")
        const startingPlayer = findChild(table, "startingPlayerSummary")
        verify(ownMulligan !== null)
        verify(remoteSummary !== null)
        verify(startingPlayer !== null)
        compare(ownMulligan.text, "Mulligan 1")
        verify(remoteSummary.text.indexOf("M2") >= 0)
        compare(startingPlayer.text, "First player · Bob")

        const first = findChild(table, "handCard0")
        const second = findChild(table, "handCard1")
        const handList = findChild(table, "ownHand")
        verify(first !== null)
        verify(second !== null)
        verify(handList !== null)
        handList.focusCard(1)
        compare(handList.currentIndex, 1)

        testWindow.lastBanner = ""
        const source = {
            "cardId": "library-card",
            "zoneName": "library",
            "zoneSeat": 0,
            "ownerSeat": 0,
            "modelData": {"id": "library-card"}
        }
        const dropArea = {"cardSource": source}
        const drop = {"source": source, "accepted": true}
        table.cardMoveCommands.finishLibraryDrop(dropArea, drop)
        verify(!drop.accepted)
        compare(testWindow.lastBanner,
                "That card cannot move to this zone.")
        table.destroy()
    }

    function test_counterCountIsOwnedAndHiddenDockShowsPublicSummary() {
        const originalSeats = mockWs.gameSeats
        const sevenCounterSeats = JSON.parse(JSON.stringify(originalSeats))
        sevenCounterSeats[1].counterCount = 7
        mockWs.gameSeats = sevenCounterSeats
        const table = tableComponent.createObject(tableHost, {
            "width": testWindow.width,
            "height": testWindow.height
        })
        verify(table !== null)

        table.sessionUi.applyTableSettings(false, true, true, 2)
        compare(mockWs.counterCountRequestCount, 1)
        compare(mockWs.lastRequestedCounterCount, 2)
        tryVerify(() => findChild(table, "playerCounterPip0-1") !== null)
        tryVerify(() => findChild(table, "playerCounterPip0-2") === null)
        verify(findChild(table, "playerCounterPip1-0") !== null)
        verify(findChild(table, "playerCounterPip1-6") !== null)
        verify(findChild(table, "playerCounterPip1-7") === null)

        const summary = findChild(table, "battlefieldPlayerSummary1")
        const opponentHeader = findChild(
                                   table, "opponentZonePanelHeader1")
        const lastOpponentPip = findChild(table, "playerCounterPip1-6")
        verify(summary !== null)
        verify(opponentHeader !== null)
        verify(lastOpponentPip !== null)
        tryVerify(() => lastOpponentPip.mapToItem(
                        opponentHeader, lastOpponentPip.width, 0).x
                        <= opponentHeader.width)
        tryVerify(() => summary.visible)
        compare(summary.text, "20HP / 7H / 53D")
        table.destroy()
        mockWs.gameSeats = originalSeats
    }

    function test_opponentPublicZonePilesHandleSeatRemoval() {
        const table = tableComponent.createObject(tableHost, {
            "width": testWindow.width,
            "height": testWindow.height
        })
        verify(table !== null)
        verify(findChild(table, "graveyardBrowserButton1") !== null)
        verify(findChild(table, "exileBrowserButton1") !== null)

        failOnWarning(/Cannot read property 'seat' of null/)
        mockWs.gameSeats = [JSON.parse(JSON.stringify(
                                          mockWs.baselineGameSeats[0]))]
        tryVerify(() => findChild(table, "opponentZoneDock1") === null)
        table.destroy()
    }

    function test_opponentLibraryRightClickOffersScopedRequests() {
        const table = tableComponent.createObject(tableHost, {
            "width": testWindow.width,
            "height": testWindow.height
        })
        verify(table !== null)

        const opponentToggle = findChild(table, "opponentZoneToggle1")
        const opponentDock = findChild(table, "opponentZoneDock1")
        verify(opponentToggle !== null)
        verify(opponentDock !== null)
        opponentToggle.clicked()
        tryVerify(() => opponentDock.visible)

        const libraryPile = findChild(table, "searchLibraryButton1")
        const menu = findChild(table, "opponentLibraryMenu")
        const searchAction = findChild(
                               table, "opponentLibrarySearchAction")
        const topCardAction = findChild(
                                table,
                                "opponentLibraryViewTopCardAction")
        const topCardsAction = findChild(
                                 table,
                                 "opponentLibraryViewTopCardsAction")
        verify(libraryPile !== null)
        verify(menu !== null)
        verify(searchAction !== null)
        verify(topCardAction !== null)
        verify(topCardsAction !== null)
        tryVerify(() => libraryPile.width > 0 && libraryPile.height > 0)
        verify(libraryPile.enabled)

        mouseClick(libraryPile, libraryPile.width / 2,
                   libraryPile.height / 2, Qt.LeftButton)
        compare(mockWs.dumpLibraryCount, 0)
        verify(!menu.opened)

        mouseClick(libraryPile, libraryPile.width / 2,
                   libraryPile.height / 2, Qt.RightButton)
        tryVerify(() => menu.opened)
        compare(menu.sourceSeat, 1)
        compare(menu.sourceLibraryCount, 53)
        searchAction.triggered()
        compare(mockWs.dumpLibraryCount, 1)
        compare(mockWs.lastDumpLibrarySeat, 1)
        compare(mockWs.lastDumpTopCount, 0)
        menu.close()

        mouseClick(libraryPile, libraryPile.width / 2,
                   libraryPile.height / 2, Qt.RightButton)
        tryVerify(() => menu.opened)
        topCardAction.triggered()
        compare(mockWs.dumpLibraryCount, 2)
        compare(mockWs.lastDumpLibrarySeat, 1)
        compare(mockWs.lastDumpTopCount, 1)
        menu.close()

        mouseClick(libraryPile, libraryPile.width / 2,
                   libraryPile.height / 2, Qt.RightButton)
        tryVerify(() => menu.opened)
        topCardsAction.triggered()
        const topCountPopup = findChild(table, "libraryTopCountPopup")
        verify(topCountPopup !== null)
        tryVerify(() => topCountPopup.opened)
        compare(topCountPopup.sourceSeat, 1)
        compare(topCountPopup.maximumValue, 53)
        const valueField = findChild(topCountPopup, "numberInputField")
        verify(valueField !== null)
        valueField.text = "3"
        topCountPopup.submit()
        compare(mockWs.dumpLibraryCount, 3)
        compare(mockWs.lastDumpLibrarySeat, 1)
        compare(mockWs.lastDumpTopCount, 3)

        mockWs.libraryDumped([{
            "id": "s1-top1", "name": "Remote One"
        }, {
            "id": "s1-top2", "name": "Remote Two"
        }, {
            "id": "s1-top3", "name": "Remote Three"
        }], 1, "zone-dump-remote", 3)
        const searchPopup = findChild(table, "librarySearchPopup")
        verify(searchPopup !== null)
        tryVerify(() => searchPopup.opened)
        verify(searchPopup.reorderMode)
        searchPopup.setTopCardDestination("s1-top1", "library_bottom")
        searchPopup.setTopCardDestination("s1-top2", "hand")
        searchPopup.resolveTopCards()
        compare(mockWs.resolveLibraryCount, 1)
        compare(mockWs.lastLibraryResolve.assignments.length, 3)
        compare(mockWs.lastLibraryResolve.assignments[0].cardId, "s1-top1")
        compare(mockWs.lastLibraryResolve.assignments[0].toZone,
                "library_bottom")
        compare(mockWs.lastLibraryResolve.assignments[1].cardId, "s1-top2")
        compare(mockWs.lastLibraryResolve.assignments[1].toZone, "hand")
        compare(mockWs.lastLibraryResolve.assignments[2].cardId, "s1-top3")
        compare(mockWs.lastLibraryResolve.assignments[2].toZone,
                "library_top")
        compare(mockWs.lastLibraryResolve.sourceSeat, 1)
        compare(mockWs.lastLibraryResolve.approvalId,
                "zone-dump-remote")
        table.destroy()
    }

    function test_libraryAccessPromptNamesRequestedScope() {
        const table = tableComponent.createObject(tableHost, {
            "width": testWindow.width,
            "height": testWindow.height
        })
        verify(table !== null)
        const confirmation = findChild(
                                 table, "libraryAccessConfirmation")
        verify(confirmation !== null)

        mockWs.libraryAccessRequested("approval-top", "Bob", 1, 3)
        tryVerify(() => confirmation.opened)
        compare(confirmation.message,
                "Bob wants to view the top 3 cards of your library. Allow access?\nExpires in 90s")
        confirmation.close()
        tryVerify(() => !confirmation.opened)
        compare(mockWs.respondZoneDumpCount, 1)

        mockWs.libraryAccessRequested("approval-search", "Bob", 1, 0)
        tryVerify(() => confirmation.opened)
        compare(confirmation.message,
                "Bob wants to search your library. Allow access?\nExpires in 90s")
        confirmation.close()
        tryVerify(() => !confirmation.opened)
        compare(mockWs.respondZoneDumpCount, 2)
        table.destroy()
    }

    function test_publicZoneMovePromptRequiresSourcePlayerDecision() {
        const table = tableComponent.createObject(tableHost, {
            "width": testWindow.width,
            "height": testWindow.height
        })
        verify(table !== null)
        const confirmation = findChild(
                                 table, "publicZoneMoveConfirmation")
        verify(confirmation !== null)

        mockWs.publicZoneMoveRequested(
                    "public-move-1", "Bob", 1,
                    "graveyard", 2, "battlefield")
        tryVerify(() => confirmation.opened)
        compare(confirmation.message,
                "Bob wants to move 2 card(s) from your graveyard to battlefield. Allow this move?\nExpires in 90s")
        confirmation.close()
        tryVerify(() => !confirmation.opened)
        compare(mockWs.respondPublicZoneMoveCount, 1)
        compare(mockWs.lastPublicZoneMoveResponse.approvalId,
                "public-move-1")
        compare(mockWs.lastPublicZoneMoveResponse.approved, false)
        table.destroy()
    }

    function test_libraryAccessPromptExpiresLocally() {
        const table = tableComponent.createObject(tableHost, {
            "width": testWindow.width,
            "height": testWindow.height,
            "approvalTimeoutSeconds": 1
        })
        verify(table !== null)
        const confirmation = findChild(
                                 table, "libraryAccessConfirmation")
        verify(confirmation !== null)

        testWindow.lastBanner = ""
        mockWs.libraryAccessRequested("approval-timeout", "Bob", 1, 3)
        tryVerify(() => confirmation.opened)
        tryVerify(() => !confirmation.opened, 1500)
        compare(testWindow.lastBanner,
                "The library access request expired.")
        table.destroy()
    }

    function test_publicZonesBrowseAnySeat() {
        const table = tableComponent.createObject(tableHost, {
            "width": testWindow.width,
            "height": testWindow.height
        })
        verify(table !== null)

        const opponentGraveyard = findChild(table, "graveyardBrowserButton1")
        const opponentGraveyardDrop = findChild(table, "graveyardDropArea1")
        const ownExile = findChild(table, "exileBrowserButton0")
        const opponentHeader = findChild(
                                   table, "opponentZonePanelHeader1")
        const opponentLifeValue = findChild(table, "opponentLifeValue1")
        const opponentHandValue = findChild(table, "opponentHandValue1")
        const opponentLibraryBack = findChild(
                                        table,
                                        "opponentLibraryCardBack1")
        const opponentDock = findChild(table, "opponentZoneDock1")
        const opponentToggle = findChild(table, "opponentZoneToggle1")
        verify(opponentGraveyard !== null)
        verify(opponentGraveyardDrop !== null)
        verify(ownExile !== null)
        verify(opponentHeader !== null)
        verify(opponentLifeValue === null)
        verify(opponentHandValue === null)
        verify(opponentLibraryBack !== null)
        verify(opponentDock !== null)
        verify(opponentToggle !== null)
        verify(!opponentDock.visible)
        opponentToggle.clicked()
        tryVerify(() => opponentDock.visible)
        tryVerify(() => opponentGraveyard.width > 0
                     && opponentGraveyard.height > 0)
        verify(opponentGraveyard.enabled)
        verify(opponentGraveyardDrop.enabled)
        verify(ownExile.enabled)
        verify(opponentHeader.visible)
        verify(opponentDock.height > 82)
        mouseClick(opponentGraveyard,
                   opponentGraveyard.width / 2,
                   opponentGraveyard.height / 2,
                   Qt.LeftButton)
        const popup = findChild(table, "publicZoneBrowserPopup")
        verify(popup !== null)
        tryVerify(() => popup.opened)
        compare(popup.ownerDisplayName, "Bob")
        compare(popup.seatIndex, 1)
        compare(popup.zoneKey, "graveyard")
        const cards = findChild(popup, "zoneBrowserCards")
        verify(cards !== null)
        compare(cards.count, 2)
        popup.selectedIndex = 0
        compare(popup.selectedCard.name, "Opt")
        popup.requestSelectedMove("battlefield")
        compare(mockWs.lastMove.cardId, "s1-gy1")
        compare(mockWs.lastMove.fromZone, "graveyard")
        compare(mockWs.lastMove.fromSeat, 1)
        compare(mockWs.lastMove.toZone, "battlefield")
        compare(mockWs.lastMove.toSeat, 0)

        mouseClick(opponentGraveyard,
                   opponentGraveyard.width / 2,
                   opponentGraveyard.height / 2,
                   Qt.LeftButton)
        tryVerify(() => popup.opened)

        const originalSeats = mockWs.gameSeats
        const updatedSeats = JSON.parse(JSON.stringify(originalSeats))
        updatedSeats[1].graveyard.push({
            "id": "s1-gy3",
            "name": "Memory Deluge",
            "setCode": "MID",
            "collectorNumber": "62"
        })
        mockWs.gameSeats = updatedSeats
        tryCompare(cards, "count", 3)
        mockWs.gameSeats = originalSeats

        popup.close()
        tryVerify(() => !popup.opened)
        mouseClick(ownExile, ownExile.width / 2, ownExile.height / 2,
                   Qt.LeftButton)
        tryVerify(() => popup.opened)
        compare(popup.ownerDisplayName, "Alice")
        compare(popup.seatIndex, 0)
        compare(popup.zoneKey, "exile")
        compare(cards.count, 1)
        compare(popup.selectedCard.name, "Treasure Cruise")
        popup.requestSelectedMove("hand")
        compare(mockWs.lastMove.cardId, "s0-ex1")
        compare(mockWs.lastMove.fromSeat, 0)
        compare(mockWs.lastMove.toZone, "hand")
        popup.close()

        opponentToggle.clicked()
        tryVerify(() => {
            const dock = findChild(table, "opponentZoneDock1")
            return dock !== null && !dock.visible
        })
        const battlefieldUpdate = JSON.parse(JSON.stringify(originalSeats))
        battlefieldUpdate[1].battlefield.push({
            "id": "s1-c2",
            "name": "Sol Ring",
            "setCode": "CMM",
            "collectorNumber": "396",
            "position": {"x": 0.25, "y": 0.4}
        })
        mockWs.gameSeats = battlefieldUpdate
        tryVerify(() => {
            const dock = findChild(table, "opponentZoneDock1")
            return dock !== null && !dock.visible
        })
        const refreshedToggle = findChild(table, "opponentZoneToggle1")
        verify(refreshedToggle !== null)
        refreshedToggle.clicked()
        tryVerify(() => {
            const dock = findChild(table, "opponentZoneDock1")
            return dock !== null && dock.visible
        })
        mockWs.gameSeats = originalSeats
        table.destroy()
    }

    function test_graveyardBrowserSelectAllMovesAtomically() {
        const graveyardSeats = JSON.parse(JSON.stringify(
                                              mockWs.gameSeats))
        graveyardSeats[0].graveyard = [{
            "id": "s0-gy-a",
            "name": "Consider",
            "setCode": "MID",
            "collectorNumber": "44",
            "ownerSeat": 0
        }, {
            "id": "s0-gy-b",
            "name": "Consider",
            "setCode": "MID",
            "collectorNumber": "44",
            "ownerSeat": 0
        }, {
            "id": "s0-gy-c",
            "name": "Opt",
            "setCode": "DOM",
            "collectorNumber": "60",
            "ownerSeat": 0
        }]
        mockWs.gameSeats = graveyardSeats
        const table = tableComponent.createObject(tableHost, {
            "width": testWindow.width,
            "height": testWindow.height
        })
        verify(table !== null)

        const popup = findChild(table, "publicZoneBrowserPopup")
        verify(popup !== null)
        popup.showZone("Alice", 0, "graveyard")
        tryVerify(() => popup.opened)
        const cards = findChild(popup, "zoneBrowserCards")
        const selectAll = findChild(popup, "selectAllZoneCards")
        const menu = findChild(popup, "zoneCardMenu")
        const libraryAction = findChild(popup, "zoneCardToLibrary")
        const exileAction = findChild(popup, "zoneCardToExile")
        verify(cards !== null)
        verify(selectAll !== null)
        verify(menu !== null)
        verify(libraryAction !== null)
        verify(exileAction !== null)
        compare(cards.count, 2)
        verify(selectAll.visible)
        compare(popup.selectedCount, 0)
        selectAll.clicked()
        tryCompare(popup, "selectedCount", 3)
        compare(selectAll.text, "Deselect all")
        selectAll.clicked()
        tryCompare(popup, "selectedCount", 0)
        compare(selectAll.text, "Select all")
        selectAll.clicked()
        tryCompare(popup, "selectedCount", 3)

        tryVerify(() => cards.itemAtIndex(0) !== null)
        const firstCard = cards.itemAtIndex(0)
        mouseClick(firstCard, firstCard.width / 2,
                   firstCard.height / 2, Qt.RightButton)
        tryVerify(() => menu.opened)
        compare(menu.title, "Move selected · 3")
        verify(libraryAction.enabled)
        exileAction.triggered()

        compare(mockWs.movePublicCardsCount, 1)
        compare(mockWs.lastMovePublicCards.cardIds.length, 3)
        compare(mockWs.lastMovePublicCards.cardIds[0], "s0-gy-a")
        compare(mockWs.lastMovePublicCards.cardIds[1], "s0-gy-b")
        compare(mockWs.lastMovePublicCards.cardIds[2], "s0-gy-c")
        compare(mockWs.lastMovePublicCards.fromZone, "graveyard")
        compare(mockWs.lastMovePublicCards.fromSeat, 0)
        compare(mockWs.lastMovePublicCards.toZone, "exile")
        compare(mockWs.lastMovePublicCards.toSeat, -1)
        tryVerify(() => !popup.opened)
        table.destroy()
    }

    function test_exileBrowserMatchesGraveyardBatchActions() {
        const exileSeats = JSON.parse(JSON.stringify(mockWs.gameSeats))
        exileSeats[0].exile = [{
            "id": "s0-exile-a",
            "name": "Consider",
            "setCode": "MID",
            "collectorNumber": "44",
            "ownerSeat": 0
        }, {
            "id": "s0-exile-b",
            "name": "Opt",
            "setCode": "DOM",
            "collectorNumber": "60",
            "ownerSeat": 0
        }]
        mockWs.gameSeats = exileSeats
        const table = tableComponent.createObject(tableHost, {
            "width": testWindow.width,
            "height": testWindow.height
        })
        verify(table !== null)

        const popup = findChild(table, "publicZoneBrowserPopup")
        verify(popup !== null)
        popup.showZone("Alice", 0, "exile")
        tryVerify(() => popup.opened)
        const cards = findChild(popup, "zoneBrowserCards")
        const selectAll = findChild(popup, "selectAllZoneCards")
        const menu = findChild(popup, "zoneCardMenu")
        const libraryAction = findChild(popup, "zoneCardToLibrary")
        const graveyardAction = findChild(popup, "zoneCardToGraveyard")
        verify(cards !== null)
        verify(selectAll !== null)
        verify(menu !== null)
        verify(libraryAction !== null)
        verify(graveyardAction !== null)
        verify(selectAll.visible)
        selectAll.clicked()
        tryCompare(popup, "selectedCount", 2)

        tryVerify(() => cards.itemAtIndex(0) !== null)
        const firstCard = cards.itemAtIndex(0)
        mouseClick(firstCard, firstCard.width / 2,
                   firstCard.height / 2, Qt.RightButton)
        tryVerify(() => menu.opened)
        compare(menu.title, "Move selected · 2")
        verify(libraryAction.enabled)
        verify(graveyardAction.enabled)
        libraryAction.triggered()

        compare(mockWs.movePublicCardsCount, 1)
        compare(mockWs.lastMovePublicCards.cardIds.length, 2)
        compare(mockWs.lastMovePublicCards.fromZone, "exile")
        compare(mockWs.lastMovePublicCards.fromSeat, 0)
        compare(mockWs.lastMovePublicCards.toZone, "library")
        compare(mockWs.lastMovePublicCards.toSeat, -1)
        tryVerify(() => !popup.opened)
        table.destroy()
    }

    function test_publicZonePileMovesStableTopCard() {
        const originalSeats = mockWs.gameSeats
        const zoneSeats = JSON.parse(JSON.stringify(originalSeats))
        zoneSeats[0].graveyard = [{
            "id": "s0-grave-bottom",
            "name": "Bottom card",
            "ownerSeat": 0
        }, {
            "id": "s0-grave-top",
            "name": "Top card",
            "ownerSeat": 0
        }]
        zoneSeats[0].exile = [{
            "id": "s0-exile-only",
            "name": "Only card",
            "ownerSeat": 0
        }]
        mockWs.gameSeats = zoneSeats

        const table = tableComponent.createObject(tableHost, {
            "width": testWindow.width,
            "height": testWindow.height
        })
        verify(table !== null)
        const graveyardSource =
            findChild(table, "graveyardDragCard0")
        const exileSource = findChild(table, "exileDragCard0")
        verify(graveyardSource !== null)
        verify(exileSource !== null)
        compare(graveyardSource.cardId, "s0-grave-top")
        compare(exileSource.cardId, "s0-exile-only")

        verify(table.cardMoveCommands.moveDroppedCardToBattlefield(
                   graveyardSource, 0, 0.4, 0.45))
        compare(mockWs.moveCount, 1)
        compare(mockWs.lastMove.cardId, "s0-grave-top")
        compare(mockWs.lastMove.fromZone, "graveyard")
        compare(mockWs.lastMove.fromSeat, 0)
        compare(table.pendingBattlefieldMove.cardId,
                "s0-grave-top")
        compare(table.zoneState.displayedPublicZoneTopCard(
                    0, "graveyard").id,
                "s0-grave-bottom")

        table.cardMoveCommands.clearPendingBattlefieldMove()
        verify(table.cardMoveCommands.moveDroppedCardToBattlefield(
                   exileSource, 0, 0.55, 0.45))
        compare(mockWs.moveCount, 2)
        compare(mockWs.lastMove.cardId, "s0-exile-only")
        compare(mockWs.lastMove.fromZone, "exile")
        compare(mockWs.lastMove.fromSeat, 0)
        compare(table.pendingBattlefieldMove.cardId,
                "s0-exile-only")
        verify(!table.zoneState.displayedPublicZoneTopCard(0, "exile").id)

        table.destroy()
        mockWs.gameSeats = originalSeats
    }

    function test_createsEnglishCatalogTokenOnBattlefield() {
        const table = tableComponent.createObject(tableHost, {
            "width": testWindow.width,
            "height": testWindow.height
        })
        verify(table !== null)

        const openButton = findChild(table, "createTokenAction")
        verify(openButton !== null)
        verify(openButton.enabled)
        openButton.triggered()

        const picker = findChild(table, "tokenPicker")
        verify(picker !== null)
        tryVerify(() => picker.opened)
        const results = findChild(picker, "tokenSearchResults")
        verify(results !== null)
        tryCompare(results, "count", 1)
        tryVerify(() => results.itemAtIndex(0) !== null)
        const resultRow = results.itemAtIndex(0)
        const details = findChild(resultRow, "tokenResultDetails")
        verify(details !== null)
        compare(details.text, "1/1 · Haste · TNEO #12")
        const createButton = findChild(resultRow, "createTokenResultButton")
        verify(createButton !== null)
        createButton.clicked()
        compare(mockCatalog.cacheTokenCount, 1)
        compare(mockWs.createTokenCount, 1)
        compare(mockWs.lastToken.token.name, "Goblin")
        verify(Math.abs(mockWs.lastToken.position.x - 0.5) < 0.15)
        compare(mockWs.lastToken.position.y, 0.58)
        tryVerify(() => !picker.opened)
        table.destroy()
    }

}
