// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic
import QtTest
import "../../qml/screens"
import "../../qml/components"

TestCase {
    name: "WaitingRoom"
    when: windowShown

    ApplicationWindow {
        id: testWindow
        width: 1400
        height: 900
        visible: true
        property string lastBanner: ""
        function showBanner(message) { lastBanner = message }
        function pushScreen(url) { }
    }

    QtObject {
        id: mockRoomSession
        property string roomId: "ABCDEF"
        property string roomName: "Friday Night"
        property string format: "modern"
        property string deckFormat: "modern"
        property bool playtest: false
        property string matchMode: "bo3"
        property string cardLoadMode: "preload"
        property string rulesMode: "manual"
        property string aiDifficulty: ""
        property string aiSource: ""
        property string hostingMode: "server"
        property bool hostConnected: true
        property var hostStatus: ({})
        property int maxSeats: 2
        property string phase: "waiting"
        property bool host: true
        property string role: "player"
        property int seatIndex: 0
        property string selectedDeckName: "Burn"
        property var seats: [{
            "occupied": true,
            "displayName": "Alice",
            "host": true,
            "deckSelected": true,
            "ready": false
        }, {
            "occupied": false,
            "displayName": "",
            "host": false,
            "deckSelected": false,
            "ready": false
        }]
        property var spectators: []
        property bool spectatorsSeeHands: false
    }

    QtObject {
        id: mockWs
        property var roomSession: mockRoomSession
        property string lastError: ""
        property var rulesStartFailure: ({})
        function dismissRulesStartFailure() { rulesStartFailure = ({}); lastError = "" }
        property bool peerTransportAvailable: true
        property bool directPeerEnabled: false
        property string peerTransportState: "off"
        property var peerRequests: []
        function setDirectPeerEnabled(enabled, retry) {
            peerRequests = peerRequests.concat([{enabled:enabled, retry:retry === true}])
            directPeerEnabled = enabled
            peerTransportState = enabled ? "waiting" : "off"
        }
        property int copyCount: 0
        property string lastCopied: ""
        function copyToClipboard(text) {
            ++copyCount
            lastCopied = text
        }
        function setReady(ready) { }
        function leaveRoom() { }
        function disbandRoom() { }
        function kickSeat(seat) { }
        property var selectedDeck: ({})
        property var aiRequests: []
        function selectDeck(deck) { selectedDeck = deck }
        function configureAiOpponent(difficulty, deck) { aiRequests = aiRequests.concat([{difficulty, deck}]) }
        property int lastRemovedSpectator: -1
        function kickSpectator(index) { lastRemovedSpectator = index }
    }

    QtObject {
        id: mockDeckLibrary
        property var decks: []
        property var submittedDeck: ({})
        property string activeMatchDeckId: ""
        function deckForMatch() { return submittedDeck }
        function matchDecks() { return decks }
        function setActiveMatchDeck(id) { activeMatchDeckId = id }
    }

    property var page: null

    Component {
        id: pageComponent
        WaitingRoom {
            wsModel: mockWs
            deckLibraryModel: mockDeckLibrary
        }
    }

    function init() {
        testWindow.lastBanner = ""
        mockWs.copyCount = 0
        mockWs.lastCopied = ""
        mockWs.lastError = ""
        mockWs.rulesStartFailure = ({})
        mockWs.aiRequests = []
        mockWs.selectedDeck = ({})
        mockRoomSession.aiDifficulty = ""
        mockRoomSession.aiSource = ""
        mockDeckLibrary.submittedDeck = ({})
        mockDeckLibrary.activeMatchDeckId = ""
        mockWs.peerTransportAvailable = true
        mockWs.directPeerEnabled = false
        mockWs.peerTransportState = "off"
        mockWs.peerRequests = []
        mockRoomSession.spectators = []
        mockRoomSession.spectatorsSeeHands = false
        mockWs.lastRemovedSpectator = -1
        mockRoomSession.rulesMode = "manual"
        mockRoomSession.hostingMode = "server"
        mockRoomSession.roomName = "Friday Night"
        mockRoomSession.roomId = "ABCDEF"
        mockRoomSession.format = "modern"
        mockRoomSession.deckFormat = "modern"
        mockRoomSession.maxSeats = 2
        mockRoomSession.playtest = false
        mockRoomSession.host = true
        mockRoomSession.role = "player"
        mockRoomSession.seatIndex = 0
        mockRoomSession.selectedDeckName = "Burn"
        mockRoomSession.seats = [{
            "occupied": true,
            "displayName": "Alice",
            "host": true,
            "deckSelected": true,
            "ready": false
        }, {
            "occupied": false,
            "displayName": "",
            "host": false,
            "deckSelected": false,
            "ready": false
        }]
        page = pageComponent.createObject(testWindow.contentItem)
        verify(page !== null)
        page.anchors.fill = testWindow.contentItem
        verify(waitForPolish(testWindow))
    }

    function cleanup() {
        Theme.uiScale = 1
        testWindow.width = 1400
        testWindow.height = 900
        if (page !== null)
            page.destroy()
        page = null
    }

    function configureAiRoom(deckSelected) {
        mockRoomSession.rulesMode = "forge"
        mockRoomSession.aiDifficulty = "normal"
        mockRoomSession.matchMode = "bo1"
        mockRoomSession.seats = [
            {occupied: true, displayName: "Alice", host: true, deckSelected: true, ready: false},
            {occupied: true, displayName: "Forge AI", host: false, controller: "forgeAi",
             aiDifficulty: "normal", deckSelected: deckSelected, ready: deckSelected}]
    }

    function test_aiDeckBlocksReadyAndCannotBeKicked() {
        configureAiRoom(false)
        compare(page.hasEnoughPlayersToStart(), true)
        verify(!findChild(page, "playerReadyButton").enabled)
        compare(page.readyBlockerReason(), "Select a deck for the AI before readying up")
        const repeater = findChild(page, "waitingRoomSeatRepeater")
        const aiRow = repeater.itemAt(1)
        verify(aiRow !== null)
        verify(!findChild(aiRow, "waitingRoomRemovePlayerButton").visible)
        configureAiRoom(true)
        verify(findChild(page, "playerReadyButton").enabled)
        compare(page.readyBlockerReason(), "")
        compare(findChild(page, "waitingRoomAiSummary").text, "Forge AI · Normal")
    }

    function test_aiDeckSelectionDoesNotReplaceHumanDeck() {
        configureAiRoom(false)
        mockDeckLibrary.submittedDeck = {name: "AI Burn", format: "modern", main: []}
        const selectAi = findChild(page, "waitingRoomSelectAiDeckButton")
        verify(selectAi.visible)
        selectAi.clicked()
        const picker = findChild(page, "waitingRoomDeckPicker")
        compare(picker.titleText, "Select AI deck")
        picker.selected("ai-burn", "AI Burn")
        picker.close()
        compare(mockWs.aiRequests.length, 1)
        compare(mockWs.aiRequests[0].difficulty, "normal")
        compare(mockWs.aiRequests[0].deck.name, "AI Burn")
        compare(mockDeckLibrary.activeMatchDeckId, "")
        compare(Object.keys(mockWs.selectedDeck).length, 0)
        findChild(page, "waitingRoomAiDifficultyControl").activated(0)
        compare(mockWs.aiRequests.length, 2)
        compare(mockWs.aiRequests[1].difficulty, "easy")
        compare(mockWs.aiRequests[1].deck, undefined)
        compare(findChild(page, "waitingRoomAiDifficultyControl").currentIndex, 1)
        mockRoomSession.aiDifficulty = "easy"
        compare(findChild(page, "waitingRoomAiDifficultyControl").currentIndex, 0)
        mockRoomSession.host = false
        verify(!findChild(page, "waitingRoomAiOptions").visible)
    }

    function test_modelDeckSelectionKeepsNativeDifficultyHidden() {
        mockRoomSession.rulesMode = "forge"
        mockRoomSession.aiSource = "local"
        mockRoomSession.matchMode = "bo1"
        mockRoomSession.seats = [
            {occupied:true,displayName:"Alice",host:true,deckSelected:true,ready:false},
            {occupied:true,displayName:"Local model",host:false,controller:"modelAi",deckSelected:false,ready:false}]
        verify(page.aiPractice)
        compare(findChild(page, "waitingRoomAiSummary").text, "Local model")
        verify(!findChild(page, "waitingRoomAiDifficultyControl").visible)
        verify(!findChild(page, "playerReadyButton").enabled)
        const aiRow = findChild(page, "waitingRoomSeatRepeater").itemAt(1)
        verify(!findChild(aiRow, "waitingRoomRemovePlayerButton").visible)
        mockDeckLibrary.submittedDeck = {name:"Model deck",format:"modern",main:[]}
        findChild(page, "waitingRoomSelectAiDeckButton").clicked()
        const picker = findChild(page, "waitingRoomDeckPicker")
        picker.selected("model-deck", "Model deck")
        picker.close()
        compare(mockWs.aiRequests.length, 1)
        compare(mockWs.aiRequests[0].difficulty, "")
        compare(mockWs.aiRequests[0].deck.name, "Model deck")
        compare(Object.keys(mockWs.selectedDeck).length, 0)
    }

    function test_longNamesAndFullSpectatorListRemainReachable_data() {
        return [{tag: "large", scale: 1.5}, {tag: "maximum", scale: 1.8}]
    }

    function test_peerConsentIsAvailableOnRoomSurface_data() {
        return [{tag:"host", seat:0}, {tag:"opponent", seat:1}]
    }

    function test_peerConsentIsAvailableOnRoomSurface(data) {
        mockRoomSession.rulesMode = "forge"
        mockRoomSession.hostingMode = "player"
        mockRoomSession.host = data.seat === 0
        mockRoomSession.seatIndex = data.seat
        waitForRendering(page)
        const panel = findChild(page, "waitingRoomPeerConnection")
        const enable = findChild(panel, "forgePeerEnable")
        const notice = findChild(panel, "forgePeerConsentNotice")
        const status = findChild(panel, "forgePeerStatus")
        verify(panel.visible && enable.visible && enable.enabled)
        verify(notice.visible)
        compare(mockWs.peerRequests.length, 0)
        const seats = findChild(page, "waitingRoomSeats")
        const actions = findChild(page, "waitingRoomActions")
        const point = enable.mapToItem(page, 0, 0)
        verify(point.y >= 0 && point.y + enable.height <= page.height)
        verify(panel.mapToItem(page, 0, 0).y >= seats.mapToItem(page, 0, 0).y + seats.height - 1)
        verify(panel.mapToItem(page, 0, 0).x < actions.mapToItem(page, 0, 0).x)
        mouseClick(enable)
        compare(mockWs.peerRequests, [{enabled:true, retry:false}])
        verify(!notice.visible)
        compare(status.text, "P2P: Waiting for the other player")
        mockWs.peerTransportState = "direct"
        compare(status.text, "P2P: Direct connection active")
        mockWs.peerTransportState = "relay"
        const retry = findChild(panel, "forgePeerRetry")
        verify(retry.visible)
        waitForRendering(page)
        mouseClick(retry)
        compare(mockWs.peerRequests[1], {enabled:true, retry:true})
        waitForRendering(page)
        mouseClick(enable)
        compare(mockWs.peerRequests[2], {enabled:false, retry:false})
        verify(notice.visible)
    }

    function test_peerControlsExplainUnavailableServerAndExcludeSpectators() {
        const panel = findChild(page, "waitingRoomPeerConnection")
        verify(!panel.visible)
        mockRoomSession.rulesMode = "forge"
        mockRoomSession.hostingMode = "player"
        mockWs.peerTransportAvailable = false
        waitForRendering(page)
        verify(panel.visible)
        verify(!findChild(panel, "forgePeerEnable").enabled)
        compare(findChild(panel, "forgePeerStatus").text, "P2P: This server does not support direct connections.")
        mockRoomSession.role = "spectator"
        verify(!panel.visible)
        mockRoomSession.role = "player"
        mockRoomSession.seatIndex = -1
        verify(!panel.visible)
        compare(mockWs.peerRequests.length, 0)
    }

    function test_longNamesAndFullSpectatorListRemainReachable(data) {
        testWindow.width = 900
        testWindow.height = 620
        Theme.uiScale = data.scale
        mockRoomSession.roomName = "A long room title WWWWWWWWWWWWWWWWWWWWWWWWWWWW"
        mockRoomSession.spectatorsSeeHands = true
        mockRoomSession.format = "edh"
        mockRoomSession.deckFormat = "commander"
        mockRoomSession.maxSeats = 4
        const seats = []
        const spectators = []
        for (let index = 0; index < 4; ++index) {
            seats.push({occupied: true, displayName: "Long player name ".repeat(4),
                        host: index === 0, deckSelected: true, ready: false})
        }
        for (let index = 0; index < 8; ++index)
            spectators.push({displayName: "Long spectator name ".repeat(4)})
        mockRoomSession.seats = seats
        mockRoomSession.spectators = spectators
        waitForRendering(page)
        for (const name of ["waitingRoomTitle", "copyRoomCodeButton",
                            "playerReadyButton", "waitingRoomOverflowButton"]) {
            const item = findChild(page, name)
            const point = item.mapToItem(page, 0, 0)
            verify(point.x >= -1 && point.x + item.width <= page.width + 1, name)
            verify(point.y >= 0 && point.y + item.height <= page.height,
                   name + " y=" + point.y + " h=" + item.height + " page=" + page.height)
        }
        const copy = findChild(page, "copyRoomCodeButton")
        mouseClick(copy)
        compare(mockWs.lastCopied, "ABCDEF")
        const body = findChild(page, "waitingRoomBody")
        const spectatorSurface = findChild(page, "waitingRoomSpectators")
        body.contentY = body.contentHeight - body.height
        waitForRendering(page)
        const removeButtons = []
        function walk(item) {
            if (item.objectName === "waitingRoomRemoveSpectatorButton")
                removeButtons.push(item)
            for (const child of item.children || [])
                walk(child)
        }
        walk(spectatorSurface)
        compare(removeButtons.length, 8)
        const last = removeButtons[7]
        const point = last.mapToItem(body, 0, 0)
        verify(point.y >= 0 && point.y + last.height <= body.height + 1)
        mouseClick(last)
        const confirmations = []
        function findPopup(item) {
            if (item.titleText !== undefined && item.confirmText === "Remove spectator")
                confirmations.push(item)
            for (const child of item.data || [])
                findPopup(child)
        }
        findPopup(page)
        compare(confirmations.length, 1)
        tryVerify(() => confirmations[0].opened)
        mouseClick(findChild(confirmations[0], "confirmButton"))
        compare(mockWs.lastRemovedSpectator, 7)
    }

    function test_showsRoomNameAndCodeFromSession() {
        const title = findChild(page, "waitingRoomTitle")
        const code = findChild(page, "waitingRoomCode")
        verify(title !== null)
        verify(code !== null)
        compare(title.text, "Friday Night")
        compare(code.text, "ABCDEF")
    }

    function test_fallsBackToUntitledRoomName() {
        mockRoomSession.roomName = ""
        const title = findChild(page, "waitingRoomTitle")
        verify(title !== null)
        compare(title.text, "Untitled room")
    }

    function test_copyRoomCodeUsesSessionId() {
        const copyButton = findChild(page, "copyRoomCodeButton")
        verify(copyButton !== null)
        verify(copyButton.visible && copyButton.enabled)
        verify(copyButton.width > 0 && copyButton.height > 0)
        mouseClick(copyButton)
        compare(mockWs.copyCount, 1)
        compare(mockWs.lastCopied, "ABCDEF")
        compare(testWindow.lastBanner, "Room code copied")
    }

    function test_readyBlockerExplainsMissingSeatAndDeck() {
        const reason = findChild(page, "readyBlockerText")
        const ready = findChild(page, "playerReadyButton")
        verify(reason !== null)
        verify(ready !== null)
        compare(reason.text, "Waiting for 1 more player")
        compare(ready.disabledReason, reason.text)

        mockRoomSession.seats = [{
            "occupied": true,
            "displayName": "Alice",
            "host": true,
            "deckSelected": false,
            "ready": false
        }, {
            "occupied": true,
            "displayName": "Bob",
            "host": false,
            "deckSelected": true,
            "ready": false
        }]
        tryCompare(reason, "text", "Select a deck before readying up")
        compare(ready.disabledReason, reason.text)
    }

    function test_edhCanReadyWithTwoOrThreeOfFourPlayers() {
        mockRoomSession.format = "edh"
        mockRoomSession.deckFormat = "commander"
        mockRoomSession.maxSeats = 4
        mockRoomSession.seats = [{
            "occupied": true,
            "displayName": "Alice",
            "host": true,
            "deckSelected": true,
            "ready": false
        }, {
            "occupied": true,
            "displayName": "Bob",
            "host": false,
            "deckSelected": true,
            "ready": false
        }, {
            "occupied": false,
            "displayName": "",
            "host": false,
            "deckSelected": false,
            "ready": false
        }, {
            "occupied": false,
            "displayName": "",
            "host": false,
            "deckSelected": false,
            "ready": false
        }]
        const reason = findChild(page, "readyBlockerText")
        const ready = findChild(page, "playerReadyButton")
        const status = findChild(page, "waitingRoomSeatStatus")
        verify(reason !== null)
        verify(ready !== null)
        verify(status !== null)
        tryCompare(reason, "text", "")
        tryVerify(() => ready.enabled)
        compare(status.text, "Ready to start")

        const threeSeats = mockRoomSession.seats.slice()
        threeSeats[2] = {
            "occupied": true,
            "displayName": "Carol",
            "host": false,
            "deckSelected": true,
            "ready": false
        }
        mockRoomSession.seats = threeSeats
        tryCompare(reason, "text", "")
        tryVerify(() => ready.enabled)
        compare(status.text, "Ready to start")
    }

    function test_stacksDetailsBelowSeatsInCompactLayout() {
        testWindow.width = 900
        testWindow.height = 620
        tryVerify(() => page.compactLayout)
        const content = findChild(page, "waitingRoomContent")
        const seats = findChild(page, "waitingRoomSeats")
        const details = findChild(page, "waitingRoomDetails")
        verify(content !== null)
        verify(seats !== null)
        verify(details !== null)
        compare(content.columns, 1)
        tryVerify(() => details.y >= seats.y + seats.height - 1)
        tryVerify(() => seats.width >= content.width - 8)
        tryVerify(() => details.width >= content.width - 8)
        testWindow.width = 1400
        testWindow.height = 900
        tryVerify(() => !page.compactLayout)
        compare(content.columns, 2)
        tryVerify(() => details.x >= seats.x + seats.width - 1)
    }
    function test_commanderCubeRequiresEveryInvitedPlayer() {
        mockRoomSession.format = "edh"
        mockRoomSession.deckFormat = "commander_limited"
        mockRoomSession.maxSeats = 4
        const occupied = {occupied: true, displayName: "Player", host: false,
                          deckSelected: true, ready: false}
        mockRoomSession.seats = [occupied, occupied, occupied,
            {occupied: false, displayName: "", host: false, deckSelected: false, ready: false}]
        compare(page.minimumPlayersToStart(), 4)
        verify(!findChild(page, "playerReadyButton").enabled)
        mockRoomSession.seats = [occupied, occupied, occupied, occupied]
        tryVerify(() => findChild(page, "playerReadyButton").enabled)
        mockRoomSession.maxSeats = 2
        mockRoomSession.seats = [occupied, occupied]
        compare(page.minimumPlayersToStart(), 2)
        verify(findChild(page, "playerReadyButton").enabled)
    }

    function seatRows(seatsItem) {
        const rows = []
        function walk(item) {
            if (!item || item.children === undefined)
                return
            for (let i = 0; i < item.children.length; ++i) {
                const child = item.children[i]
                if (child.objectName === "waitingRoomSeatRow")
                    rows.push(child)
                walk(child)
            }
        }
        walk(seatsItem)
        return rows
    }

    function test_sizesCompactSeatsToFitFourRows() {
        mockRoomSession.format = "edh"
        mockRoomSession.deckFormat = "commander"
        mockRoomSession.maxSeats = 4
        mockRoomSession.seats = [{
            "occupied": true,
            "displayName": "Alice",
            "host": true,
            "deckSelected": true,
            "ready": false
        }, {
            "occupied": true,
            "displayName": "Bob",
            "host": false,
            "deckSelected": true,
            "ready": false
        }, {
            "occupied": false,
            "displayName": "",
            "host": false,
            "deckSelected": false,
            "ready": false
        }, {
            "occupied": false,
            "displayName": "",
            "host": false,
            "deckSelected": false,
            "ready": false
        }]
        testWindow.width = 900
        testWindow.height = 620
        tryVerify(() => page.compactLayout)
        const seats = findChild(page, "waitingRoomSeats")
        verify(seats !== null)
        tryVerify(() => {
            const rows = seatRows(seats)
            if (rows.length !== 4)
                return false
            return rows.every(row => row.height >= Theme.size(66) - 1
                              && row.y + row.height <= seats.height + 1)
        })
        testWindow.width = 1400
        testWindow.height = 900
    }

    function test_movesSecondaryActionsIntoOverflowInCompactLayout() {
        testWindow.width = 900
        testWindow.height = 620
        tryVerify(() => page.compactLayout)
        const overflow = findChild(page, "waitingRoomOverflowButton")
        const deckLibrary = findChild(page, "waitingRoomDeckLibraryButton")
        const leave = findChild(page, "waitingRoomLeaveButton")
        const disband = findChild(page, "waitingRoomDisbandButton")
        const ready = findChild(page, "playerReadyButton")
        verify(overflow !== null)
        verify(deckLibrary !== null)
        verify(leave !== null)
        verify(disband !== null)
        verify(ready !== null)
        verify(overflow.visible)
        verify(!deckLibrary.visible)
        verify(!leave.visible)
        verify(!disband.visible)
        verify(ready.visible)
        overflow.clicked()
        const menu = findChild(page, "waitingRoomOverflowMenu")
        verify(menu !== null)
        tryVerify(() => menu.opened)
        const overflowLeave = findChild(page, "overflowLeaveAction")
        verify(overflowLeave !== null)
        verify(overflowLeave.visible)
        testWindow.width = 1400
        testWindow.height = 900
        tryVerify(() => !page.compactLayout)
        tryVerify(() => deckLibrary.visible)
        verify(!overflow.visible)
    }

    function test_keepsActionButtonsRightAlignedOnWideLayout() {
        tryVerify(() => !page.compactLayout)
        const host = findChild(page, "waitingRoomActionsHost")
        const actions = findChild(page, "waitingRoomActions")
        verify(host !== null)
        verify(actions !== null)
        verify(findChild(page, "waitingRoomSelectDeckButton") !== null)
        verify(findChild(page, "playerReadyButton") !== null)
        verify(findChild(page, "waitingRoomDeckLibraryButton") !== null)
        // Font metrics may make the buttons wider than half the window.
        // Right alignment requires containment and a flush right edge, not a fixed fraction.
        tryVerify(() => actions.width > 0 && actions.width <= host.width)
        tryVerify(() => actions.x >= 0)
        tryVerify(() => Math.abs((actions.x + actions.width) - host.width) <= 1)
    }

    function test_limitedPairingUsesServerLockedDeck() {
        mockRoomSession.deckFormat = "limited"
        mockRoomSession.selectedDeckName = ""
        mockRoomSession.seats = [{
            "occupied": true,
            "displayName": "Alice",
            "host": true,
            "deckSelected": true,
            "ready": false
        }, {
            "occupied": true,
            "displayName": "Bob",
            "host": false,
            "deckSelected": true,
            "ready": false
        }]

        const selectDeck = findChild(page, "waitingRoomSelectDeckButton")
        const lockedDeck = findChild(page, "waitingRoomLimitedDeckStatus")
        const ready = findChild(page, "playerReadyButton")
        verify(selectDeck !== null)
        verify(lockedDeck !== null)
        verify(ready !== null)
        tryVerify(() => !selectDeck.visible)
        tryVerify(() => lockedDeck.visible)
        compare(lockedDeck.text, "Limited deck locked")
        tryVerify(() => ready.enabled)
    }

    function test_forgeFailureKeepsReadyRecoveryVisible() {
        mockRoomSession.rulesMode = "forge"
        mockWs.lastError = "rules_unavailable: runtime stopped"
        const banner = findChild(page, "waitingRoomErrorBanner")
        verify(banner.visible)
        verify(banner.message.indexOf("Your seats and selected decks are kept") >= 0)
        verify(banner.message.indexOf("Ready again") >= 0)
        compare(mockRoomSession.selectedDeckName, "Burn")
        verify(findChild(page, "playerReadyButton").visible)
        mockWs.lastError = ""
        verify(!banner.visible)
    }

    function test_startFailureDetailsAreImmediateCopyableAndKeptAtTheTop() {
        const oldWidth = testWindow.width
        const oldHeight = testWindow.height
        testWindow.width = 900
        testWindow.height = 620
        Theme.uiScale = 1.5
        try {
            page.width = testWindow.width
            page.height = testWindow.height
            mockRoomSession.rulesMode = "forge"
            const issues = []
            for (let i = 0; i < 32; ++i)
                issues.push({deck:"player", section:"mainboard", code:"printing_unavailable",
                    cardName:"Forest <literal> %2 " + i, setCode:"M21", collectorNumber:"999999"})
            mockWs.lastError = "rules_unavailable: raw engine text must not be displayed"
            mockWs.rulesStartFailure = {reason:"deck_rejected", issues:issues, truncated:true}
            const notice = findChild(page, "waitingRoomStartFailure")
            const popup = findChild(page, "rulesStartFailureDialog")
            tryVerify(() => popup.opened)
            const details = findChild(popup, "rulesStartFailureText")
            verify(details.text.indexOf("Forest <literal> %2 0 (M21 999999)") >= 0)
            verify(details.text.indexOf("raw engine text") < 0)
            compare(details.textFormat, TextEdit.PlainText)
            verify(details.readOnly && details.selectByMouse)
            verify(!findChild(page, "waitingRoomErrorBanner").visible)
            verify(waitForPolish(testWindow))
            const copy = findChild(popup, "rulesStartFailureDialogCopyButton")
            const copyPosition = copy.mapToItem(page, 0, 0)
            verify(copyPosition.y >= 0 && copyPosition.y + copy.height <= page.height)
            mouseClick(copy)
            compare(mockWs.lastCopied, details.text)
            mouseClick(findChild(popup, "rulesStartFailureDialogCloseButton"))
            tryVerify(() => !popup.opened)
            mockWs.lastError = ""
            verify(notice.visible)
            const summary = findChild(notice, "rulesStartFailureSummary")
            const position = summary.mapToItem(page, 0, 0)
            verify(position.y >= 0 && position.y + summary.height <= page.height)
            verify(position.y < findChild(page, "waitingRoomBody").y)
            mouseClick(findChild(notice, "rulesStartFailureDismissButton"))
            tryVerify(() => !notice.visible)
        } finally {
            Theme.uiScale = 1
            testWindow.width = oldWidth
            testWindow.height = oldHeight
        }
    }

    function test_existingStartFailureReopensAfterReturningToRoom() {
        mockWs.rulesStartFailure = {reason:"runtime_timeout", issues:[]}
        const original = findChild(page, "rulesStartFailureDialog")
        tryVerify(() => original.opened)
        original.close()
        page.destroy()
        wait(1)
        page = pageComponent.createObject(testWindow.contentItem,
            {width:testWindow.width, height:testWindow.height})
        verify(page !== null)
        const popup = findChild(page, "rulesStartFailureDialog")
        tryVerify(() => popup.opened)
        verify(findChild(popup, "rulesStartFailureText").text.indexOf("in time") >= 0)
        mockWs.rulesStartFailure = ({})
        tryVerify(() => !popup.opened)
    }
}
