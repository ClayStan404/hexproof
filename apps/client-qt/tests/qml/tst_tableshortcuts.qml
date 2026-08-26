// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic
import QtTest
import "../../qml/components"

TestCase {
    id: testCase
    name: "TableShortcuts"
    when: windowShown

    QtObject {
        id: fakeWs
        property int seatIndex: 0
        property string lastAction: ""
        property var lastArgs: []

        function record(action, args) {
            lastAction = action
            lastArgs = args ? args : []
        }
        function drawCards(count) { record("draw", [count]) }
        function dumpLibrary(seat, count) { record("dump", [seat, count]) }
        function discardHand(all) { record("discard", [all]) }
        function flipCoin() { record("coin") }
        function randomSelectPlayer() { record("random-player") }
        function randomSelectCards(ids) { record("random-cards", ids) }
        function returnToRoom() { record("return") }
        function setCardFaceDown(id, down) {
            record("face-down", [id, down])
        }
        function clearCombatArrows(ids) { record("clear-arrows", ids) }
    }

    QtObject {
        id: fakeRoomSession
        property int seatIndex: fakeWs.seatIndex
        property bool host: true
    }

    QtObject {
        id: fakeGameSession
        property string currentPhase: "main_1"
        property bool sideboarding: false
        property var result: ({"matchFinished": false})
    }

    QtObject {
        id: fakeTable
        property var sessionUi: fakeTable
        property var projectionSync: fakeTable
        property var zoneState: fakeTable
        property var cardActions: fakeTable
        property var cardMoveCommands: fakeTable
        property var gameValues: fakeTable
        property var selection: fakeTable
        property var gameTableModel: fakeTable
        property var attachmentUi: fakeTable
        property var landPlay: fakeTable
        property var wsModel: fakeWs
        property var roomSession: fakeRoomSession
        property var gameSession: fakeGameSession
        property var publicZoneBrowser: fakePopup
        property var discardHandConfirmation: fakePopup
        property var drawConfirmation: fakePopup
        property var restartConfirmation: fakePopup
        property var lifeEditor: fakePopup
        property var commanderDamagePopup: fakePopup
        property var leaveRoomConfirmation: fakePopup
        property var cardCounterEditor: fakePopup
        property bool canAct: true
        property bool isPlaytest: false
        property bool isActivePlayer: true
        property bool isCommanderFormat: true
        property bool gameFinished: false
        property bool showGameLogRail: true
        property bool showSharedColumn: true
        property int selectedCounterSeat: 0
        property string selectedCounterKey: "poison"
        property var ownSeatData: ({
            "libraryCount": 10,
            "sideboardCount": 2,
            "displayName": "Alice"
        })
        property var authoritativeSeats: [{"seat": 0}]
        property var ownRevealedCards: []
        property var selectedHandCard: ({})
        property var selectedBattlefieldCard: ({})
        property string selectedBattlefieldCardId: ""
        property var selectedBattlefieldCardIds: ({})
        property var selectedBattlefieldFaces: []
        property var tableArrows: []
        property bool blockedValue: false
        property int handCount: 1
        property bool transitionPending: false
        property int selectionCount: 0
        property var allIds: ["card-1"]
        property string lastAction: ""
        property string lastDestination: ""
        property string lastPlacement: ""
        property bool lastRandomize: false

        function counterShortcutBlocked() { return blockedValue }
        function visibleOwnHandCount() { return handCount }
        function handRevealTransitionPending() { return transitionPending }
        function openSelectedCounterLabelEditor() { lastAction = "counter-label" }
        function openSelectedCounterValueEditor() { lastAction = "counter-value" }
        function showLibraryMoveCardsEditor(destination) {
            lastAction = "library-move"
            lastDestination = destination
        }
        function toggleHandReveal() { lastAction = "toggle-hand" }
        function openTableSettings() { lastAction = "settings" }
        function setGameLogRailVisible(show) {
            showGameLogRail = show
            lastAction = "game-log"
        }
        function setSharedColumnVisible(show) {
            showSharedColumn = show
            lastAction = "shared"
        }
        function selectedCounter() {
            return {
                "player": {"seat": 0},
                "counter": {"key": "poison", "value": 2}
            }
        }
        function selectedCount() { return selectionCount }
        function allCardIds() { return allIds }
        function clear() {
            selectionCount = 0
            selectedBattlefieldCardIds = ({})
            selectedBattlefieldCardId = ""
            lastAction = "clear-selection"
        }
        function visibleZoneSeat(id, zone) { return 0 }
        function arrowForSource(id) {
            for (let index = 0; index < tableArrows.length; ++index) {
                if (tableArrows[index].sourceCardId === id)
                    return tableArrows[index]
            }
            return ({})
        }
        function cardData(id) { return {"id": id} }
        function canControlSelectedBattlefield() {
            return selectionCount === 1
        }
        function canManageSelectedBattlefield() {
            return selectionCount === 1
        }
        function canAttachSelected() { return selectionCount === 1 }
        function canDetachSelected() { return selectionCount === 1 }
        function hasTappedOwnPermanent() { return true }
        function zoneCardCount(seat, zone) { return 1 }
        function displayedLife(player) { return 20 }
        function setLife(value) {
            lastAction = "set-life"
            lastDestination = String(value)
        }
        function adjustCounter(seat, counter, delta) {
            lastAction = "adjust-counter"
            lastDestination = String(delta)
        }
        function requestSelectedHandCard() { lastAction = "play-land" }
        function arrangeOwnBattlefield() { lastAction = "arrange" }
        function untapOwnBattlefield() { lastAction = "untap-all" }
        function toggleTapped(card) { lastAction = "toggle-tapped" }
        function beginAttach() { lastAction = "attach" }
        function detachSelected() { lastAction = "detach" }
        function beginRelationTarget(kind) {
            lastAction = "relation-" + kind
        }
        function moveSelectedHandCard(zone, faceDown) {
            lastAction = faceDown === true ? "move-hand-face-down" : "move-hand"
            lastDestination = zone
        }
        function moveSelectedHandToLibrary(placement, index) {
            lastAction = "move-hand-library"
            lastPlacement = placement
        }
        function moveSelectedBattlefieldCards(zone, placement, randomize) {
            lastAction = "move-battlefield-many"
            lastDestination = zone
            lastPlacement = placement
            lastRandomize = randomize === true
        }
        function moveSelectedBattlefieldToZone(zone) {
            lastAction = "move-battlefield"
            lastDestination = zone
        }
        function moveSelectedBattlefieldToLibrary(placement, index) {
            lastAction = "move-battlefield-library"
            lastPlacement = placement
        }
        function requestBattlefieldFaceSelection() { lastAction = "face-picker" }
        function addNumberCounter() { lastAction = "add-number-counter" }
        function adjustNumberCounter(delta) {
            lastAction = "adjust-number-counter"
            lastDestination = String(delta)
        }
        function numberCounterValue(counters) { return 3 }
        function createSelectedTokenCopy() { lastAction = "token-copy" }
    }

    QtObject {
        id: fakePopup
        property bool opened: false
        function showFor(value) {}
        function showForLibrary(seat, count, value) {}
        function showZone(name, seat, zone) {}
        function showNewAbility(name) {}
        function showNumber(name, value) {}
        function open() { opened = true }
        function close() { opened = false }
    }

    QtObject {
        id: fakeShuffle
        property bool opened: false
        function open() { opened = true }
        function close() { opened = false }
    }

    QtObject {
        id: fakeMulligan
        property bool opened: false
        function open() { opened = true }
        function close() { opened = false }
    }

    ApplicationWindow {
        id: testWindow
        width: 480
        height: 320
        visible: true

        TableShortcuts {
            id: shortcuts
            tableRoot: fakeTable
            drawCardsEditor: fakePopup
            libraryTopCountEditor: fakePopup
            tokenPicker: fakePopup
            concedeConfirmation: fakePopup
            shuffleConfirmation: fakeShuffle
            mulliganConfirmation: fakeMulligan
            shortcutHelp: fakePopup
        }
    }

    function init() {
        fakeTable.canAct = true
        fakeTable.isPlaytest = false
        fakeTable.isCommanderFormat = true
        fakeTable.isActivePlayer = true
        fakeTable.gameFinished = false
        fakeRoomSession.host = true
        fakeGameSession.currentPhase = "main_1"
        fakeGameSession.sideboarding = false
        fakeGameSession.result = {"matchFinished": false}
        fakeTable.selectedCounterSeat = 0
        fakeTable.selectedCounterKey = "poison"
        fakeTable.ownSeatData = {
            "libraryCount": 10,
            "sideboardCount": 2,
            "displayName": "Alice"
        }
        fakeTable.authoritativeSeats = [{"seat": 0}]
        fakeTable.ownRevealedCards = []
        fakeTable.blockedValue = false
        fakeTable.handCount = 1
        fakeTable.transitionPending = false
        fakeTable.selectedHandCard = ({})
        fakeTable.selectedBattlefieldCard = ({})
        fakeTable.selectedBattlefieldCardId = ""
        fakeTable.selectedBattlefieldCardIds = ({})
        fakeTable.selectedBattlefieldFaces = []
        fakeTable.tableArrows = []
        fakeTable.selectionCount = 0
        fakeTable.lastAction = ""
        fakeTable.lastDestination = ""
        fakeTable.lastPlacement = ""
        fakeTable.lastRandomize = false
        fakeWs.lastAction = ""
        fakeWs.lastArgs = []
        fakePopup.opened = false
        fakeShuffle.opened = false
        fakeMulligan.opened = false
    }

    function test_enablesAvailableActions() {
        verify(shortcuts.canEditSelectedCounter())
        verify(shortcuts.canUseLibrary())
        verify(shortcuts.canUseGameAction())
        verify(shortcuts.canMulligan())
        verify(shortcuts.canToggleHand())
        verify(shortcuts.canConcede())
    }

    function test_blocksActionsDuringModalInteraction() {
        fakeTable.blockedValue = true
        verify(!shortcuts.canEditSelectedCounter())
        verify(!shortcuts.canUseLibrary())
        verify(!shortcuts.canUseGameAction())
        verify(!shortcuts.canMulligan())
        verify(!shortcuts.canToggleHand())
        verify(!shortcuts.canConcede())
    }

    function test_handAndConcedeSpecificConditions() {
        fakeTable.handCount = 0
        verify(!shortcuts.canToggleHand())
        fakeTable.ownRevealedCards = [{"id": "revealed"}]
        verify(shortcuts.canToggleHand())
        fakeTable.transitionPending = true
        verify(!shortcuts.canToggleHand())

        fakeTable.isPlaytest = true
        verify(!shortcuts.canConcede())
    }

    function test_shortcutHelpCanToggleWhileModalIsOpen() {
        testWindow.requestActivate()
        tryVerify(() => testWindow.active)
        keyClick(Qt.Key_F1)
        tryVerify(() => fakePopup.opened)
        fakeTable.blockedValue = true
        keyClick(Qt.Key_F1)
        tryVerify(() => !fakePopup.opened)
    }

    function test_selectionDomainRejectsAmbiguousSelections() {
        fakeTable.selectedHandCard = {"id": "hand-1"}
        compare(shortcuts.selectionDomain(), "hand")
        fakeTable.selectionCount = 1
        fakeTable.selectedBattlefieldCardIds = {"battlefield-1": true}
        compare(shortcuts.selectionDomain(), "")
        verify(!shortcuts.canUseSelection())
    }

    function test_movesHandAndBattlefieldSelections() {
        fakeTable.selectedHandCard = {"id": "hand-1"}
        shortcuts.moveSelection("graveyard")
        compare(fakeTable.lastAction, "move-hand")
        compare(fakeTable.lastDestination, "graveyard")

        fakeTable.selectedHandCard = ({})
        fakeTable.selectionCount = 2
        fakeTable.selectedBattlefieldCardIds = {
            "battlefield-1": true,
            "battlefield-2": true
        }
        shortcuts.moveSelection("library-bottom", true)
        compare(fakeTable.lastAction, "move-battlefield-many")
        compare(fakeTable.lastDestination, "library")
        compare(fakeTable.lastPlacement, "bottom")
        verify(fakeTable.lastRandomize)
    }

    function test_newGlobalShortcutsInvokeExistingActions() {
        testWindow.requestActivate()
        tryVerify(() => testWindow.active)
        keyClick(Qt.Key_U, Qt.ControlModifier)
        tryCompare(fakeTable, "lastAction", "untap-all")
        keyClick(Qt.Key_C, Qt.ControlModifier | Qt.ShiftModifier)
        tryCompare(fakeWs, "lastAction", "coin")
        keyClick(Qt.Key_D, Qt.ControlModifier | Qt.AltModifier)
        tryCompare(fakeWs, "lastAction", "draw")
        compare(fakeWs.lastArgs[0], 1)
    }

    function test_lifeAndCounterAdjustmentsReuseExistingControllers() {
        shortcuts.adjustOwnLife(1)
        compare(fakeTable.lastAction, "set-life")
        compare(fakeTable.lastDestination, "21")
        shortcuts.adjustSelectedPlayerCounter(-1)
        compare(fakeTable.lastAction, "adjust-counter")
        compare(fakeTable.lastDestination, "-1")
    }

    function test_numberCounterAdjustmentShortcuts() {
        testWindow.requestActivate()
        tryVerify(() => testWindow.active)
        fakeTable.selectionCount = 1
        fakeTable.selectedBattlefieldCardId = "battlefield-1"
        fakeTable.selectedBattlefieldCardIds = {"battlefield-1": true}
        fakeTable.selectedBattlefieldCard = {
            "id": "battlefield-1",
            "counters": [{"kind": "number", "value": 3}]
        }

        keyClick(Qt.Key_Minus)
        tryCompare(fakeTable, "lastAction", "adjust-number-counter")
        compare(fakeTable.lastDestination, "-1")

        fakeTable.lastAction = ""
        keyClick(Qt.Key_Equal)
        tryCompare(fakeTable, "lastAction", "adjust-number-counter")
        compare(fakeTable.lastDestination, "1")
    }
}
