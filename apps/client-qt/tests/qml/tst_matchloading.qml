// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic
import QtTest
import "../../qml/screens"

TestCase {
    name: "MatchLoading"
    when: windowShown

    property var page: null

    ApplicationWindow {
        id: testWindow
        width: 1400
        height: 800
        visible: true
        property string lastBanner: ""
        function showBanner(message) { lastBanner = message }
    }

    Item {
        id: tableHost
        parent: testWindow.contentItem
        anchors.fill: parent
        // The MatchLoading page is created after this static host. Keep test
        // tables above it so synthesized pointer events reach the table.
        z: 1
    }

    QtObject {
        id: mockWs
        property var roomSession: mockRoomSession
        property var gameSession: mockGameSession
        property string roomRole: "player"
        property bool youAreHost: false
        property bool playtest: false
        property string roomId: "ABC123"
        property string roomName: "Friday Modern"
        property string format: "modern"
        property string matchMode: "bo3"
        property string roomPhase: "started"
        property bool inRoom: true
        property int seatIndex: 0
        property int gameNumber: 1
        property int startingSeat: 1
        property int activeSeat: 0
        property string currentPhase: "untap"
        property int drawCount: 0
        property int leaveRoomCount: 0
        property int shuffleLibraryCount: 0
        property int mulliganCount: 0
        property int discardHandCount: 0
        property bool lastDiscardAll: false
        property int moveCount: 0
        property int arrangeBattlefieldCount: 0
        property var lastBattlefieldArrangement: []
        property int setTappedCount: 0
        property int setFaceDownCount: 0
        property var lastTapped: ({})
        property var lastFaceDown: ({})
        property int phaseCount: 0
        property string lastPhase: ""
        property int setCounterCallCount: 0
        property var lastCounter: ({})
        property int counterCountRequestCount: 0
        property int lastRequestedCounterCount: -1
        property int adjustCounterCount: 0
        property var lastCounterAdjustment: ({})
        property int renameCounterCount: 0
        property var lastCounterRename: ({})
        property int nextTurnCount: 0
        property int revealCount: 0
        property int recallRevealedCount: 0
        property int moveCardsCount: 0
        property var lastMoveCards: ({})
        property int movePublicCardsCount: 0
        property var lastMovePublicCards: ({})
        property int dumpLibraryCount: 0
        property int lastDumpLibrarySeat: -1
        property int lastDumpTopCount: -1
        property int moveLibraryCardsCount: 0
        property int lastMoveLibraryCardsCount: 0
        property string lastMoveLibraryDestination: ""
        property int respondZoneDumpCount: 0
        property var lastZoneDumpResponse: ({})
        property int respondPublicZoneMoveCount: 0
        property var lastPublicZoneMoveResponse: ({})
        property int searchLibraryCount: 0
        property int resolveLibraryCount: 0
        property int concedeCount: 0
        property int declareDrawCount: 0
        property int restartGameCount: 0
        property int rollDiceCount: 0
        property var lastDiceRoll: ({})
        property int flipCoinCount: 0
        property int randomPlayerCount: 0
        property int randomCardsCount: 0
        property var lastRandomCards: []
        property int returnToRoomCount: 0
        property int sayCount: 0
        property int createTokenCount: 0
        property var lastToken: ({})
        property int commanderTaxCount: 0
        property int lastCommanderTaxDelta: 0
        property int commanderCastCount: 0
        property string lastCommanderCastId: ""
        property int sideboardMoveCount: 0
        property var lastSideboardMove: ({})
        property int sideboardReadyCount: 0
        property int sideboardCommanderCount: 0
        property var lastSideboardCommander: ({})
        property bool lastSideboardReady: false
        property string lastSay: ""
        property string lastError: ""
        property bool gameFinished: false
        property bool sideboarding: false
        property var sideboardState: ({})
        property var matchScore: [0, 0]
        property var gameResult: ({})
        property var lastMove: ({})
        property var lastLibrarySearch: ({})
        property var lastLibraryResolve: ({})
        property int setArrowCount: 0
        property var lastArrow: ({})
        property int clearArrowCount: 0
        property int setAttachmentCount: 0
        property var lastAttachment: ({})
        signal libraryDumped(var cards, int sourceSeat, string approvalId,
                             int topCount)
        signal libraryAccessRequested(string approvalId, string requesterName,
                                      int requesterSeat, int topCount)
        signal publicZoneMoveRequested(string approvalId,
                                       string requesterName,
                                       int requesterSeat,
                                       string sourceZone, int cardCount,
                                       string toZone)
        signal commandQueued(string requestId, string commandType, var payload)
        signal commandSucceeded(string requestId, string commandType,
                                var payload)
        signal commandFailed(string requestId, string commandType,
                             var payload, string error)
        signal gameSnapshotChanged()
        property var seats: [{
            "occupied": true,
            "displayName": "Alice",
            "loaded": true
        }, {
            "occupied": true,
            "displayName": "Bob",
            "loaded": false
        }]
        property var baselineGameSeats: [{
            "seat": 0,
            "displayName": "Alice",
            "life": 20,
            "counterCount": 7,
            "counters": [
                {"key": "counter-1", "label": "", "value": 0},
                {"key": "counter-2", "label": "", "value": 0},
                {"key": "counter-3", "label": "", "value": 0},
                {"key": "counter-4", "label": "", "value": 0},
                {"key": "counter-5", "label": "", "value": 0},
                {"key": "counter-6", "label": "", "value": 0},
                {"key": "counter-7", "label": "", "value": 0}
            ],
            "libraryCount": 53,
            "handCount": 1,
            "mulliganCount": 0,
            "hand": [{
                "id": "s0-c1",
                "name": "Lightning Bolt",
                "setCode": "M11",
                "collectorNumber": "149"
            }],
            "battlefield": [],
            "graveyard": [{
                "id": "s0-gy1",
                "name": "Consider",
                "setCode": "MID",
                "collectorNumber": "44",
                "ownerSeat": 0
            }],
            "exile": [{
                "id": "s0-ex1",
                "name": "Treasure Cruise",
                "setCode": "KTK",
                "collectorNumber": "59",
                "ownerSeat": 0
            }]
        }, {
            "seat": 1,
            "displayName": "Bob",
            "life": 20,
            "counterCount": 1,
            "counters": [
                {"key": "counter-1", "label": "Energy", "value": 3},
                {"key": "counter-2", "label": "", "value": 0},
                {"key": "counter-3", "label": "", "value": 0},
                {"key": "counter-4", "label": "", "value": 0},
                {"key": "counter-5", "label": "", "value": 0},
                {"key": "counter-6", "label": "", "value": 0},
                {"key": "counter-7", "label": "", "value": 0}
            ],
            "libraryCount": 53,
            "handCount": 7,
            "mulliganCount": 0,
            "battlefield": [{
                "id": "s1-c1",
                "name": "Teferi, Hero of Dominaria",
                "setCode": "DOM",
                "collectorNumber": "207",
                "position": {"x": 0.72, "y": 0.35}
            }],
            "graveyard": [{
                "id": "s1-gy1",
                "name": "Opt",
                "setCode": "DOM",
                "collectorNumber": "60",
                "ownerSeat": 1
            }, {
                "id": "s1-gy2",
                "name": "Supreme Verdict",
                "setCode": "RTR",
                "collectorNumber": "201",
                "ownerSeat": 1
            }],
            "exile": [{
                "id": "s1-ex1",
                "name": "March of Otherworldly Light",
                "setCode": "NEO",
                "collectorNumber": "28",
                "ownerSeat": 1
            }]
        }]
        property var gameSeats:
            JSON.parse(JSON.stringify(baselineGameSeats))
        property var gameStack: [{
            "id": "s0-stack",
            "name": "Counterspell",
            "setCode": "MH2",
            "collectorNumber": "267",
            "ownerSeat": 0
        }]
        property var gameRevealed: [{
            "id": "s0-reveal",
            "name": "Mountain",
            "setCode": "M11",
            "collectorNumber": "242",
            "ownerSeat": 0
        }]
        property var gameArrows: []
        property var gameAttachments: []
        property var gameLog: [{
            "id": 1,
            "kind": "roll",
            "seat": 1,
            "text": "Bob won the opening roll."
        }]
        function setReady(ready) {}
        function leaveRoom() { ++leaveRoomCount }
        function drawCards(count) { drawCount += count }
        function shuffleLibrary() { ++shuffleLibraryCount }
        function setCardCounter(cardId, counter) {}
        function mulligan() { ++mulliganCount }
        function setCombatArrows(sourceCardIds, kind, targetCardId,
                                 targetSeat, tappedSourceCardIds) {
            ++setArrowCount
            lastArrow = {
                "sourceCardIds": sourceCardIds,
                "kind": kind,
                "targetCardId": targetCardId,
                "targetSeat": targetSeat,
                "tappedSourceCardIds": tappedSourceCardIds
                                        ? tappedSourceCardIds : []
            }
        }
        function clearCombatArrows(sourceCardIds) {}
        function clearArrow() { ++clearArrowCount }
        function setAttachment(sourceCardId, targetCardId) {
            ++setAttachmentCount
            lastAttachment = {
                "sourceCardId": sourceCardId,
                "targetCardId": targetCardId
            }
        }
        function setPhase(phase) {
            ++phaseCount
            lastPhase = phase
        }
        function setResponseStatus(status) {}
        function setCounter(counter, value) {
            ++setCounterCallCount
            lastCounter = {
                "counter": counter,
                "value": value
            }
        }
        function setCounterCount(count) {
            ++counterCountRequestCount
            lastRequestedCounterCount = count
        }
        function adjustCounter(counter, delta) {
            ++adjustCounterCount
            lastCounterAdjustment = {
                "counter": counter,
                "delta": delta
            }
        }
        function renameCounter(counter, label) {
            ++renameCounterCount
            lastCounterRename = {
                "counter": counter,
                "label": label
            }
        }
        function concede() { ++concedeCount }
        function declareDraw() { ++declareDrawCount }
        function restartGame() { ++restartGameCount }
        function rollDice(sides, count) {
            ++rollDiceCount
            lastDiceRoll = {"sides": sides, "count": count}
        }
        function flipCoin() { ++flipCoinCount }
        function randomSelectPlayer() { ++randomPlayerCount }
        function randomSelectCards(cardIds) {
            ++randomCardsCount
            lastRandomCards = cardIds
        }
        function discardHand(all) {
            ++discardHandCount
            lastDiscardAll = all === true
        }
        function returnToRoom() { ++returnToRoomCount }
        function sayGameMessage(message) {
            ++sayCount
            lastSay = message
        }
        function createToken(token, position) {
            ++createTokenCount
            lastToken = {"token": token, "position": position}
        }
        function adjustCommanderTax(commanderId, delta) {
            ++commanderTaxCount
            lastCommanderTaxDelta = delta
        }
        function castCommander(commanderId) {
            ++commanderCastCount
            lastCommanderCastId = commanderId
        }
        function moveSideboardCard(card, fromZone, toZone) {
            ++sideboardMoveCount
            lastSideboardMove = {
                "card": card, "fromZone": fromZone, "toZone": toZone
            }
        }
        function setSideboardCommander(name, designated) {
            ++sideboardCommanderCount
            lastSideboardCommander = {
                "name": name, "designated": designated
            }
        }
        function setSideboardReady(ready) {
            ++sideboardReadyCount
            lastSideboardReady = ready
        }
        function nextTurn() { ++nextTurnCount }
        function revealHand() { ++revealCount }
        function recallRevealed() { ++recallRevealedCount }
        function dumpLibrary(sourceSeat, topCount) {
            ++dumpLibraryCount
            lastDumpLibrarySeat = sourceSeat
            lastDumpTopCount = topCount === undefined ? 0 : topCount
        }
        function moveLibraryCards(count, toZone) {
            ++moveLibraryCardsCount
            lastMoveLibraryCardsCount = count
            lastMoveLibraryDestination = toZone
        }
        function moveCards(cardIds, fromZone, toZone, libraryPlacement,
                           randomize) {
            ++moveCardsCount
            lastMoveCards = {
                "cardIds": cardIds,
                "fromZone": fromZone,
                "toZone": toZone,
                "libraryPlacement": libraryPlacement,
                "randomize": randomize
            }
        }
        function movePublicCards(cardIds, fromZone, fromSeat, toZone,
                                 toSeat, position) {
            ++movePublicCardsCount
            lastMovePublicCards = {
                "cardIds": cardIds,
                "fromZone": fromZone,
                "fromSeat": fromSeat,
                "toZone": toZone,
                "toSeat": toSeat,
                "position": position
            }
        }
        function respondZoneDump(approvalId, approved) {
            ++respondZoneDumpCount
            lastZoneDumpResponse = {
                "approvalId": approvalId, "approved": approved
            }
        }
        function respondPublicZoneMove(approvalId, approved) {
            ++respondPublicZoneMoveCount
            lastPublicZoneMoveResponse = {
                "approvalId": approvalId, "approved": approved
            }
        }
        function searchLibrary(cardId, toZone, reveal, position,
                               sourceSeat, approvalId, toSeat) {
            ++searchLibraryCount
            lastLibrarySearch = {
                "cardId": cardId,
                "toZone": toZone,
                "reveal": reveal,
                "position": position,
                "sourceSeat": sourceSeat,
                "approvalId": approvalId,
                "toSeat": toSeat
            }
        }
        function searchLibraryCards(cardIds, toZone, reveal, randomize,
                                    position, sourceSeat, approvalId, toSeat,
                                    faceDown) {
            ++searchLibraryCount
            lastLibrarySearch = {
                "cardIds": cardIds,
                "toZone": toZone,
                "reveal": reveal,
                "randomize": randomize,
                "position": position,
                "sourceSeat": sourceSeat,
                "approvalId": approvalId,
                "toSeat": toSeat,
                "faceDown": faceDown === true
            }
        }
        function reorderLibrary(cardIds) {}
        function resolveLibraryView(selectedCardIds, remainderCardIds,
                                    toZone, remainderPlacement,
                                    randomizeRemainder, faceDown, position,
                                    sourceSeat, approvalId) {
            ++resolveLibraryCount
            lastLibraryResolve = {
                "selectedCardIds": selectedCardIds,
                "remainderCardIds": remainderCardIds,
                "toZone": toZone,
                "remainderPlacement": remainderPlacement,
                "randomizeRemainder": randomizeRemainder,
                "faceDown": faceDown,
                "position": position,
                "sourceSeat": sourceSeat,
                "approvalId": approvalId
            }
        }
        function moveCard(cardId, fromZone, toZone, position, toSeat,
                          libraryPlacement, libraryIndex, fromSeat,
                          faceName, faceDown) {
            ++moveCount
            lastMove = {
                "cardId": cardId,
                "fromZone": fromZone,
                "toZone": toZone,
                "position": position,
                "fromSeat": fromSeat,
                "toSeat": toSeat,
                "libraryPlacement": libraryPlacement,
                "libraryIndex": libraryIndex,
                "faceName": faceName ? faceName : "",
                "faceDown": faceDown === true
            }
        }
        function arrangeBattlefield(cards) {
            ++arrangeBattlefieldCount
            lastBattlefieldArrangement = cards
        }
        function setCardTapped(cardId, tapped) {
            ++setTappedCount
            lastTapped = {"cardId": cardId, "tapped": tapped}
        }
        function setCardFaceDown(cardId, faceDown) {
            ++setFaceDownCount
            lastFaceDown = {"cardId": cardId, "faceDown": faceDown}
        }
    }

    QtObject {
        id: mockRoomSession
        property string roomId: mockWs.roomId
        property string roomName: mockWs.roomName
        property string format: mockWs.format
        property bool playtest: mockWs.playtest
        property string matchMode: mockWs.matchMode
        property string phase: mockWs.roomPhase
        property bool host: mockWs.youAreHost
        property string role: mockWs.roomRole
        property int seatIndex: mockWs.seatIndex
        property var seats: mockWs.seats
    }

    QtObject {
        id: mockGameSession
        property int gameNumber: mockWs.gameNumber
        property int startingSeat: mockWs.startingSeat
        property int activeSeat: mockWs.activeSeat
        property string currentPhase: mockWs.currentPhase
        property var score: mockWs.matchScore
        property var result: mockWs.gameResult
        property var sideboard: mockWs.sideboardState
        property bool sideboarding: mockWs.sideboarding
        property bool finished: mockWs.gameFinished
    }

    QtObject {
        id: mockCatalog
        property bool tokenCatalogInstalled: true
        property bool tokenSearching: false
        property bool busy: false
        property string status: ""
        property var tokenSearchResults: [{
            "name": "Goblin",
            "typeLine": "Token Creature — Goblin",
            "setCode": "TNEO",
            "collectorNumber": "12",
            "power": "1",
            "toughness": "1",
            "oracleText": "Haste"
        }]
        property int searchTokenCount: 0
        property int cacheTokenCount: 0
        property var typeLines: ({})
        property var faces: ({})
        function imageSource(name, setCode, collectorNumber) { return "" }
        function cardFaces(name, setCode, collectorNumber) {
            return faces[name] ? faces[name] : []
        }
        function cardTypeLine(name, setCode, collectorNumber) {
            return typeLines[name] ? typeLines[name] : ""
        }
        function matchesCardQuery(name, setCode, collectorNumber, query) {
            const needle = query.trim().toLocaleLowerCase()
            return name.toLocaleLowerCase().includes(needle)
                   || cardTypeLine(name, setCode, collectorNumber)
                      .toLocaleLowerCase().includes(needle)
        }
        function tokenImageSource(name, setCode, collectorNumber) { return "" }
        function searchTokens(query) { ++searchTokenCount }
        function cacheToken(token) { ++cacheTokenCount }
        function downloadTokenCatalog() {}
    }

    QtObject {
        id: mockPreferences
        property bool tableShowPlayers: true
        property bool tableShowShared: true
        property bool tableShowInspector: true
        property bool tableShowGameLog: true
        property int tableCounterCount: 7
        property real tableOverviewCardScale: 0
        property real tableFocusCardScale: 0
        property real tableBattlefieldControlX: -1
        property real tableBattlefieldControlY: -1
        function setTableBattlefieldControlPosition(x, y) {
            tableBattlefieldControlX = x
            tableBattlefieldControlY = y
        }
    }

    QtObject {
        id: mockLoader
        property bool ready: false
        property int completed: 1
        property int total: 2
        property int failed: 0
        property real progress: 0.5
        property string lastError: ""
        property int retryCount: 0
        function retry() { ++retryCount }
    }

    Component {
        id: pageComponent
        MatchLoading {
            wsModel: mockWs
            loaderModel: mockLoader
        }
    }

    Component {
        id: tableComponent
        Table {
            wsModel: mockWs
            gameTableModel: testGameTable
            optimisticCommandModel: testOptimisticCommands
            sideboardTableModel: testSideboardTable
            cardCatalogModel: mockCatalog
            preferencesModel: mockPreferences
        }
    }

    function syncTestGameTable() {
        testGameTable.applySnapshot({
            "seats": mockWs.gameSeats,
            "stack": mockWs.gameStack,
            "revealed": mockWs.gameRevealed,
            "arrows": mockWs.gameArrows,
            "attachments": mockWs.gameAttachments,
            "log": mockWs.gameLog
        })
    }

    Connections {
        target: mockWs

        function onGameSeatsChanged() { syncTestGameTable() }
        function onGameStackChanged() { syncTestGameTable() }
        function onGameRevealedChanged() { syncTestGameTable() }
        function onGameArrowsChanged() { syncTestGameTable() }
        function onGameAttachmentsChanged() { syncTestGameTable() }
        function onGameLogChanged() { syncTestGameTable() }
    }

    function init() {
        mockLoader.failed = 0
        mockLoader.lastError = ""
        mockLoader.retryCount = 0
        mockWs.drawCount = 0
        mockWs.leaveRoomCount = 0
        mockWs.returnToRoomCount = 0
        mockWs.shuffleLibraryCount = 0
        mockWs.mulliganCount = 0
        mockWs.discardHandCount = 0
        mockWs.lastDiscardAll = false
        mockWs.moveCount = 0
        mockWs.lastMove = ({})
        mockWs.arrangeBattlefieldCount = 0
        mockWs.lastBattlefieldArrangement = []
        mockWs.setTappedCount = 0
        mockWs.lastTapped = ({})
        mockWs.setFaceDownCount = 0
        mockWs.lastFaceDown = ({})
        mockWs.declareDrawCount = 0
        mockWs.restartGameCount = 0
        mockWs.rollDiceCount = 0
        mockWs.lastDiceRoll = ({})
        mockWs.flipCoinCount = 0
        mockWs.randomPlayerCount = 0
        mockWs.randomCardsCount = 0
        mockWs.lastRandomCards = []
        mockWs.roomRole = "player"
        mockWs.youAreHost = false
        mockWs.playtest = false
        mockRoomSession.playtest = Qt.binding(() => mockWs.playtest)
        mockWs.inRoom = true
        mockWs.format = "modern"
        mockWs.matchMode = "bo3"
        mockWs.seatIndex = 0
        mockWs.activeSeat = 0
        mockWs.currentPhase = "untap"
        mockWs.phaseCount = 0
        mockWs.lastPhase = ""
        mockWs.setCounterCallCount = 0
        mockWs.lastCounter = ({})
        mockWs.counterCountRequestCount = 0
        mockWs.lastRequestedCounterCount = -1
        mockWs.adjustCounterCount = 0
        mockWs.lastCounterAdjustment = ({})
        mockWs.renameCounterCount = 0
        mockWs.lastCounterRename = ({})
        mockWs.nextTurnCount = 0
        mockWs.revealCount = 0
        mockWs.recallRevealedCount = 0
        mockWs.moveCardsCount = 0
        mockWs.lastMoveCards = ({})
        mockWs.movePublicCardsCount = 0
        mockWs.lastMovePublicCards = ({})
        mockWs.dumpLibraryCount = 0
        mockWs.lastDumpLibrarySeat = -1
        mockWs.lastDumpTopCount = -1
        mockWs.moveLibraryCardsCount = 0
        mockWs.lastMoveLibraryCardsCount = 0
        mockWs.lastMoveLibraryDestination = ""
        mockWs.respondZoneDumpCount = 0
        mockWs.lastZoneDumpResponse = ({})
        mockWs.respondPublicZoneMoveCount = 0
        mockWs.lastPublicZoneMoveResponse = ({})
        mockWs.searchLibraryCount = 0
        mockWs.lastLibrarySearch = ({})
        mockWs.resolveLibraryCount = 0
        mockWs.lastLibraryResolve = ({})
        mockWs.setArrowCount = 0
        mockWs.lastArrow = ({})
        mockWs.clearArrowCount = 0
        mockWs.setAttachmentCount = 0
        mockWs.lastAttachment = ({})
        mockWs.gameArrows = []
        mockWs.gameAttachments = []
        mockWs.concedeCount = 0
        mockWs.sayCount = 0
        mockWs.lastSay = ""
        mockWs.lastError = ""
        mockWs.gameFinished = false
        mockWs.sideboarding = false
        mockWs.sideboardState = ({})
        mockWs.matchScore = [0, 0]
        mockWs.gameResult = ({})
        mockWs.gameSeats =
            JSON.parse(JSON.stringify(mockWs.baselineGameSeats))
        mockWs.createTokenCount = 0
        mockWs.lastToken = ({})
        mockWs.commanderTaxCount = 0
        mockWs.lastCommanderTaxDelta = 0
        mockWs.commanderCastCount = 0
        mockWs.lastCommanderCastId = ""
        mockCatalog.typeLines = ({})
        mockCatalog.faces = ({})
        mockWs.sideboardMoveCount = 0
        mockWs.lastSideboardMove = ({})
        mockWs.sideboardCommanderCount = 0
        mockWs.lastSideboardCommander = ({})
        mockWs.sideboardReadyCount = 0
        mockWs.lastSideboardReady = false
        mockCatalog.searchTokenCount = 0
        mockCatalog.cacheTokenCount = 0
        mockCatalog.typeLines = ({})
        mockPreferences.tableShowPlayers = true
        mockPreferences.tableShowShared = true
        mockPreferences.tableShowInspector = true
        mockPreferences.tableShowGameLog = true
        mockPreferences.tableCounterCount = 7
        mockPreferences.tableOverviewCardScale = 0
        mockPreferences.tableFocusCardScale = 0
        mockPreferences.tableBattlefieldControlX = -1
        mockPreferences.tableBattlefieldControlY = -1
        testGameTable.clear()
        syncTestGameTable()
        page = pageComponent.createObject(testWindow.contentItem, {
            "width": testWindow.width,
            "height": testWindow.height
        })
        verify(page !== null)
    }

    function cleanup() {
        // Flush normal end-of-test destroy() calls first, then remove any
        // Table left behind when an assertion aborted a test early.
        wait(1)
        for (let index = tableHost.children.length - 1;
             index >= 0; --index) {
            const table = tableHost.children[index]
            if (table)
                table.destroy()
        }
        testGameTable.clear()
        wait(1)
        page.destroy()
        page = null
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
               >= viewTopCard.contentItem.implicitWidth)
        verify(viewTopCards.contentItem.width + 1
               >= viewTopCards.contentItem.implicitWidth)
        verify(moveTopToGraveyard.contentItem.width + 1
               >= moveTopToGraveyard.contentItem.implicitWidth)
        verify(moveTopToExile.contentItem.width + 1
               >= moveTopToExile.contentItem.implicitWidth)
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
        const graveyardAction =
            findChild(popup, "libraryContextLocalGraveyard")
        const topOrderedAction =
            findChild(popup, "libraryContextSourceTopOrdered")
        verify(topCard !== null)
        verify(selection !== null)
        verify(!selection.visible)
        verify(libraryCardMenu !== null)
        verify(graveyardAction !== null)
        verify(topOrderedAction !== null)
        verify(!topOrderedAction.visible)
        mouseClick(topCard, topCard.width / 2,
                   topCard.height / 2, Qt.RightButton)
        tryVerify(() => libraryCardMenu.opened)
        graveyardAction.triggered()

        compare(mockWs.searchLibraryCount, 1)
        compare(mockWs.lastLibrarySearch.cardIds.length, 1)
        compare(mockWs.lastLibrarySearch.cardIds[0], "s0-top1")
        compare(mockWs.lastLibrarySearch.toZone, "graveyard")
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
        searchPopup.toggleCard("s1-top1")
        const destinationBox = findChild(searchPopup, "topCardsDestination")
        verify(destinationBox !== null)
        let bottomIndex = -1
        for (let i = 0; i < destinationBox.count; ++i) {
            if (destinationBox.valueAt(i) === "library_bottom") {
                bottomIndex = i
                break
            }
        }
        verify(bottomIndex >= 0)
        destinationBox.currentIndex = bottomIndex
        searchPopup.resolveTopCards()
        compare(mockWs.resolveLibraryCount, 1)
        compare(mockWs.lastLibraryResolve.selectedCardIds.length, 1)
        compare(mockWs.lastLibraryResolve.selectedCardIds[0], "s1-top1")
        compare(mockWs.lastLibraryResolve.remainderCardIds.length, 2)
        compare(mockWs.lastLibraryResolve.toZone, "library_bottom")
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
