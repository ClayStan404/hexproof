// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic
import "../../qml/screens"

Item {
    property var page: null

    required property var testCase
    readonly property alias testWindowObject: testWindow
    readonly property alias tableHostObject: tableHost
    readonly property alias mockWsObject: mockWs
    readonly property alias mockRoomSessionObject: mockRoomSession
    readonly property alias mockGameSessionObject: mockGameSession
    readonly property alias mockCatalogObject: mockCatalog
    readonly property alias mockPreferencesObject: mockPreferences
    readonly property alias mockLoaderObject: mockLoader
    readonly property alias pageComponentObject: pageComponent
    readonly property alias tableComponentObject: tableComponent


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
        property var turnOrder: [1, 0]
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
        function resolveLibraryViewAssignments(assignments, randomizeTop,
                                               randomizeBottom, position,
                                               sourceSeat, approvalId) {
            ++resolveLibraryCount
            lastLibraryResolve = {
                "assignments": assignments,
                "randomizeTop": randomizeTop,
                "randomizeBottom": randomizeBottom,
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
        property bool spectatorsSeeHands: false
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
        property var turnOrder: mockWs.turnOrder
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

    function reset() {
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
        mockRoomSession.spectatorsSeeHands = false
        mockWs.inRoom = true
        mockWs.format = "modern"
        mockWs.matchMode = "bo3"
        mockWs.turnOrder = [1, 0]
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
        return page !== null
    }

    function cleanupHarness() {
        // Flush normal end-of-test destroy() calls first, then remove any
        // Table left behind when an assertion aborted a test early.
        testCase.wait(1)
        for (let index = tableHost.children.length - 1;
             index >= 0; --index) {
            const table = tableHost.children[index]
            if (table)
                table.destroy()
        }
        testGameTable.clear()
        testCase.wait(1)
        page.destroy()
        page = null
    }
}
