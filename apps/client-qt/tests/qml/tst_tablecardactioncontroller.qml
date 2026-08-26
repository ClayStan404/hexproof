// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtTest
import "../../qml/components"

TestCase {
    id: testCase
    name: "TableCardActionController"

    QtObject {
        id: fakeWs
        property int seatIndex: 1
        property var counterCalls: []
        property var tokenCalls: []
        property var chatCalls: []
        property int revealCalls: 0
        property int recallCalls: 0

        function setCardCounter(cardId, payload) {
            counterCalls = counterCalls.concat([{
                "cardId": cardId,
                "payload": payload
            }])
        }

        function createToken(card, position) {
            tokenCalls = tokenCalls.concat([{
                "card": card,
                "position": position
            }])
        }

        function sayGameMessage(message) {
            chatCalls = chatCalls.concat([message])
        }

        function revealHand() {
            ++revealCalls
        }

        function recallRevealed() {
            ++recallCalls
        }
    }

    QtObject {
        id: fakeRoomSession
        property int seatIndex: fakeWs.seatIndex
    }

    QtObject {
        id: fakeChatInput
        property string text: ""
        property int clearCalls: 0
        property int focusCalls: 0

        function clear() {
            text = ""
            ++clearCalls
        }

        function forceActiveFocus() {
            ++focusCalls
        }
    }

    QtObject {
        id: fakeTable
        property var optimisticCommands: fakeTable
        property var zoneState: fakeTable
        property var selection: fakeTable
        property var wsModel: fakeWs
        property var roomSession: fakeRoomSession
        property bool canAct: true
        property bool canChat: true
        property int selectedBattlefieldOwnerSeat: 1
        property string selectedBattlefieldCardId: "card-1"
        property var selectedBattlefieldCard: ({
            "id": "card-1",
            "name": "Copy target",
            "setCode": "TST",
            "collectorNumber": "7",
            "position": {"x": 0.98, "y": 0.30}
        })
        property var ownRevealedCards: []
        property var ownHand: []
        property bool revealTransitionPending: false
        property var pendingFrom: ({})
        property var pendingMoves: []
        property int clearSelectionCalls: 0

        function clear() {
            ++clearSelectionCalls
        }

        function handRevealTransitionPending() {
            return revealTransitionPending
        }

        function isCardPendingFrom(cardId, zone, seat) {
            return pendingFrom[cardId] === true
        }

        function beginPendingCardMoves(moves) {
            pendingMoves = moves
        }
    }

    TableCardActionController {
        id: controller
        tableRoot: fakeTable
        chatInput: fakeChatInput
    }

    function init() {
        fakeWs.counterCalls = []
        fakeWs.tokenCalls = []
        fakeWs.chatCalls = []
        fakeWs.revealCalls = 0
        fakeWs.recallCalls = 0
        fakeChatInput.text = ""
        fakeChatInput.clearCalls = 0
        fakeChatInput.focusCalls = 0
        fakeTable.canAct = true
        fakeTable.canChat = true
        fakeTable.selectedBattlefieldOwnerSeat = 1
        fakeTable.selectedBattlefieldCardId = "card-1"
        fakeTable.selectedBattlefieldCard = ({
            "id": "card-1",
            "name": "Copy target",
            "setCode": "TST",
            "collectorNumber": "7",
            "position": {"x": 0.98, "y": 0.30}
        })
        fakeTable.ownRevealedCards = []
        fakeTable.ownHand = []
        fakeTable.revealTransitionPending = false
        fakeTable.pendingFrom = ({})
        fakeTable.pendingMoves = []
        fakeTable.clearSelectionCalls = 0
    }

    function test_counterHelpersSeparateNumberAndAbilityCounters() {
        const counters = [
            {"kind": "number", "value": 4},
            {"kind": "ability", "label": "Flying", "value": 1},
            {"kind": "ability", "label": "Ward", "value": 2}
        ]
        compare(controller.numberCounterValue(counters), 4)
        compare(controller.abilityCounters(counters).length, 2)
        compare(controller.abilityCounterSummary(counters),
                "Flying · 1\nWard · 2")
    }

    function test_numberCounterAdjustmentRequiresActionableOwnedCard() {
        verify(controller.addNumberCounter())
        compare(fakeWs.counterCalls.length, 1)
        compare(fakeWs.counterCalls[0].cardId, "card-1")
        compare(fakeWs.counterCalls[0].payload.delta, 1)

        fakeTable.selectedBattlefieldCard = {
            "id": "card-1",
            "name": "Copy target",
            "counters": [{"kind": "number", "value": 2}]
        }
        verify(controller.adjustNumberCounter(-1))
        compare(fakeWs.counterCalls.length, 2)
        compare(fakeWs.counterCalls[1].payload.delta, -1)

        fakeTable.selectedBattlefieldCard = {
            "id": "card-1",
            "name": "Copy target",
            "counters": []
        }
        verify(!controller.adjustNumberCounter(-1))

        fakeTable.canAct = false
        verify(!controller.addNumberCounter())
        fakeTable.canAct = true
        fakeTable.selectedBattlefieldOwnerSeat = 0
        verify(!controller.addNumberCounter())
        fakeTable.selectedBattlefieldOwnerSeat = 1
        fakeTable.selectedBattlefieldCardId = ""
        verify(!controller.addNumberCounter())
        compare(fakeWs.counterCalls.length, 2)
    }

    function test_tokenCopyClampsPositionAndClearsSelection() {
        verify(controller.createSelectedTokenCopy())
        compare(fakeWs.tokenCalls.length, 1)
        compare(fakeWs.tokenCalls[0].card.name, "Copy target")
        compare(fakeWs.tokenCalls[0].position.x, 1)
        verify(Math.abs(fakeWs.tokenCalls[0].position.y - 0.34) < 0.0001)
        compare(fakeTable.clearSelectionCalls, 1)
    }

    function test_chatSubmissionTrimsAndRestoresFocus() {
        fakeChatInput.text = "  hello table  "
        verify(controller.submitChatMessage())
        compare(fakeWs.chatCalls, ["hello table"])
        compare(fakeChatInput.text, "")
        compare(fakeChatInput.clearCalls, 1)
        compare(fakeChatInput.focusCalls, 1)

        fakeChatInput.text = "   "
        verify(!controller.submitChatMessage())
        fakeChatInput.text = "blocked"
        fakeTable.canChat = false
        verify(!controller.submitChatMessage())
        compare(fakeWs.chatCalls.length, 1)
    }

    function test_revealHandSkipsPendingCardsAndEmptyCommands() {
        verify(!controller.toggleHandReveal())
        compare(fakeWs.revealCalls, 0)

        fakeTable.ownHand = [
            {"id": "card-1", "name": "One"},
            {"id": "card-2", "name": "Two"}
        ]
        fakeTable.pendingFrom = ({"card-2": true})
        verify(controller.toggleHandReveal())
        compare(fakeTable.pendingMoves.length, 1)
        compare(fakeTable.pendingMoves[0].cardId, "card-1")
        compare(fakeTable.pendingMoves[0].toZone, "reveal")
        compare(fakeWs.revealCalls, 1)
    }

    function test_recallRevealedAndTransitionGuard() {
        fakeTable.ownRevealedCards = [
            {"id": "card-3", "name": "Three"}
        ]
        verify(controller.toggleHandReveal())
        compare(fakeTable.pendingMoves.length, 1)
        compare(fakeTable.pendingMoves[0].fromZone, "reveal")
        compare(fakeTable.pendingMoves[0].toZone, "hand")
        compare(fakeWs.recallCalls, 1)

        fakeTable.revealTransitionPending = true
        verify(!controller.toggleHandReveal())
        compare(fakeWs.recallCalls, 1)
    }
}
