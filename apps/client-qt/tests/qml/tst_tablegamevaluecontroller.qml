// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtTest
import "../../qml/components"

TestCase {
    name: "TableGameValueController"

    QtObject {
        id: optimisticModel

        property var lifeValues: ({})
        property var tappedValues: ({})
        property var counterValues: ({})
        property var commanderTaxValues: ({})
        property string phase: ""
        property string lastTrackedKind: ""
        property var lastTrackedKeys: []

        function valueMap(kind) {
            if (kind === "life")
                return lifeValues
            if (kind === "tapped")
                return tappedValues
            if (kind === "counter")
                return counterValues
            if (kind === "tax")
                return commanderTaxValues
            return ({})
        }

        function assignValueMap(kind, values) {
            if (kind === "life")
                lifeValues = values
            else if (kind === "tapped")
                tappedValues = values
            else if (kind === "counter")
                counterValues = values
            else if (kind === "tax")
                commanderTaxValues = values
        }

        function setValue(kind, key, value) {
            const values = Object.assign({}, valueMap(kind))
            values[key] = value
            assignValueMap(kind, values)
        }

        function removeValue(kind, key) {
            const values = Object.assign({}, valueMap(kind))
            delete values[key]
            assignValueMap(kind, values)
        }

        function trackValues(kind, keys) {
            lastTrackedKind = kind
            lastTrackedKeys = keys.slice()
        }

        function beginPhase(value) {
            phase = value
        }

        function clearPhase() {
            phase = ""
        }
    }

    QtObject {
        id: mockWs

        property int seatIndex: 0
        property string currentPhase: "main_1"
        property string lastCounterName: ""
        property int lastCounterValue: 0
        property string lastAdjustedCounter: ""
        property int lastCounterDelta: 0
        property string lastTappedCard: ""
        property bool lastTappedValue: false
        property string lastCommanderId: ""
        property int lastCommanderDelta: 0
        property string lastPhase: ""
        property int nextTurnCount: 0

        function setCounter(name, value) {
            lastCounterName = name
            lastCounterValue = value
        }

        function adjustCounter(name, delta) {
            lastAdjustedCounter = name
            lastCounterDelta = delta
        }

        function setCardTapped(cardId, tapped) {
            lastTappedCard = cardId
            lastTappedValue = tapped
        }

        function adjustCommanderTax(commanderId, delta) {
            lastCommanderId = commanderId
            lastCommanderDelta = delta
        }

        function setPhase(value) {
            lastPhase = value
        }

        function nextTurn() {
            ++nextTurnCount
        }
    }

    QtObject {
        id: fakeRoomSession
        property int seatIndex: mockWs.seatIndex
    }

    QtObject {
        id: fakeGameSession
        property string currentPhase: mockWs.currentPhase
    }

    QtObject {
        id: fakeTable
        property var zoneState: fakeTable
        property var optimisticCommands: fakeTable
        property var seatState: fakeTable

        property bool canAct: true
        property bool isActivePlayer: true
        property var wsModel: mockWs
        property var roomSession: fakeRoomSession
        property var gameSession: fakeGameSession
        property var optimisticCommandModel: optimisticModel
        property var optimisticLifeTotals: optimisticModel.lifeValues
        property var optimisticTappedCards: optimisticModel.tappedValues
        property var optimisticCounterValues: optimisticModel.counterValues
        property var optimisticCommanderTax: optimisticModel.commanderTaxValues
        property string optimisticPhase: optimisticModel.phase
        property string displayedPhase: optimisticPhase.length > 0
                                        ? optimisticPhase
                                        : mockWs.currentPhase
        property var authoritativeSeats: [{"seat": 0}, {"seat": 1}]
        property var players: [{
            "seat": 0,
            "life": 20,
            "counters": [{"key": "energy", "value": 3}],
            "commanderTaxes": {"commander-1": 2}
        }, {
            "seat": 1,
            "life": 17,
            "counters": [],
            "commanderTaxes": ({})
        }]
        property var battlefieldCards: [{
            "id": "card-1",
            "ownerSeat": 0,
            "tapped": true,
            "commander": true
        }]

        function trackOptimisticValues(kind, keys) {
            optimisticModel.trackValues(kind, keys)
        }

        function seatData(seat) {
            for (let index = 0; index < players.length; ++index) {
                if (players[index].seat === seat)
                    return players[index]
            }
            return ({})
        }

        function zoneCardsForSeat(seat, zone) {
            if (seat === 0 && zone === "battlefield")
                return battlefieldCards
            return []
        }

        function clearOptimisticPhase() {
            optimisticModel.clearPhase()
        }
    }

    TableGameValueController {
        id: controller
        tableRoot: fakeTable
    }

    function init() {
        optimisticModel.lifeValues = ({})
        optimisticModel.tappedValues = ({})
        optimisticModel.counterValues = ({})
        optimisticModel.commanderTaxValues = ({})
        optimisticModel.phase = ""
        optimisticModel.lastTrackedKind = ""
        optimisticModel.lastTrackedKeys = []
        mockWs.lastCounterName = ""
        mockWs.lastCounterValue = 0
        mockWs.lastAdjustedCounter = ""
        mockWs.lastCounterDelta = 0
        mockWs.lastTappedCard = ""
        mockWs.lastTappedValue = false
        mockWs.lastCommanderId = ""
        mockWs.lastCommanderDelta = 0
        mockWs.lastPhase = ""
        mockWs.nextTurnCount = 0
        mockWs.currentPhase = "main_1"
        fakeTable.players = [{
            "seat": 0,
            "life": 20,
            "counters": [{"key": "energy", "value": 3}],
            "commanderTaxes": {"commander-1": 2}
        }, {
            "seat": 1,
            "life": 17,
            "counters": [],
            "commanderTaxes": ({})
        }]
        fakeTable.battlefieldCards = [{
            "id": "card-1",
            "ownerSeat": 0,
            "tapped": true,
            "commander": true
        }]
    }

    function test_updatesOptimisticValuesAndCommands() {
        controller.setLife(24)
        compare(controller.displayedLife(fakeTable.players[0]), 24)
        compare(mockWs.lastCounterName, "life")
        compare(mockWs.lastCounterValue, 24)

        controller.adjustCounter(
                    0, fakeTable.players[0].counters[0], 2)
        compare(controller.displayedCounterValue(
                    0, fakeTable.players[0].counters[0]), 5)
        compare(mockWs.lastAdjustedCounter, "energy")
        compare(mockWs.lastCounterDelta, 2)

        controller.toggleTapped(fakeTable.battlefieldCards[0])
        compare(controller.displayedTapped(
                    fakeTable.battlefieldCards[0]), false)
        compare(mockWs.lastTappedCard, "card-1")
        compare(mockWs.lastTappedValue, false)

        controller.adjustCommanderTax("commander-1", 1)
        compare(controller.displayedCommanderTax(
                    fakeTable.players[0], "commander-1"), 3)
        compare(mockWs.lastCommanderId, "commander-1")
        compare(mockWs.lastCommanderDelta, 1)
    }

    function test_phaseCommandsAndReconciliation() {
        controller.setPhase("combat_damage")
        compare(optimisticModel.phase, "combat_damage")
        compare(mockWs.lastPhase, "combat_damage")

        mockWs.currentPhase = "combat_damage"
        controller.reconcile()
        compare(optimisticModel.phase, "")

        mockWs.currentPhase = "main_1"
        controller.advancePhase()
        compare(optimisticModel.phase, "begin_combat")
        compare(mockWs.lastPhase, "begin_combat")

        controller.advanceTurn()
        compare(optimisticModel.phase, "untap")
        compare(mockWs.nextTurnCount, 1)
    }

    function test_reconcilesAuthoritativeValues() {
        optimisticModel.lifeValues = ({"0": 20})
        optimisticModel.tappedValues = ({"card-1": true})
        optimisticModel.counterValues = ({"0:energy": 3})
        optimisticModel.commanderTaxValues = ({"0:commander-1": 2})

        controller.reconcile()

        verify(!Object.prototype.hasOwnProperty.call(
                   optimisticModel.lifeValues, "0"))
        verify(!Object.prototype.hasOwnProperty.call(
                   optimisticModel.tappedValues, "card-1"))
        verify(!Object.prototype.hasOwnProperty.call(
                   optimisticModel.counterValues, "0:energy"))
        verify(!Object.prototype.hasOwnProperty.call(
                   optimisticModel.commanderTaxValues, "0:commander-1"))
    }
}
