// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtTest
import "../../qml/components"

TestCase {
    id: testCase
    name: "LimitedConstructionController"
    QtObject {
        id: state
        signal snapshotChanged()
        property string tournamentId: "EVENT"
        property string eventType: "set_draft"
        property string stage: "deck_building"
        property bool deckSubmitted: false
        property var mainboardInstanceIds: []
        property var basicLands: []
        property var participants: []
        property var pool: [
            {instanceId: "a", name: "First", typeLine: "Creature"},
            {instanceId: "b", name: "Second", typeLine: "Creature"}
        ]
    }
    QtObject {
        id: store
        property var entries: ({})
        function key(server, event, seat) { return JSON.stringify([server, event, seat]) }
        function loadDraft(server, event, seat) { return entries[key(server, event, seat)] || ({}) }
        function saveDraft(server, event, seat, draft) { entries[key(server, event, seat)] = JSON.parse(JSON.stringify(draft)) }
        function removeDraft(server, event, seat) { delete entries[key(server, event, seat)] }
    }
    Component {
        id: controllerComponent
        LimitedDeckConstructionController {
            limitedModel: state
            cardCatalogModel: null
            draftStore: store
            draftServer: "ws://local/ws"
            participantId: "player"
        }
    }
    SignalSpy { id: submissions; signalName: "submissionRequested" }

    function init() {
        state.deckSubmitted = false
        state.mainboardInstanceIds = []
        state.basicLands = []
        store.entries = ({})
        submissions.target = null
        submissions.clear()
    }

    function test_editsSurviveAnOlderSubmissionWithoutViewOrTransport() {
        const controller = createTemporaryObject(controllerComponent, testCase)
        submissions.target = controller
        controller.chooseInitialPool(true)
        controller.adjustBasic("Island", 38)
        controller.submit()
        compare(submissions.count, 1)
        compare(submissions.signalArguments[0][0].slice().sort(), ["a", "b"])
        controller.moveToSideboard("a")
        controller.adjustBasic("Forest", 1)

        state.mainboardInstanceIds = ["a", "b"]
        state.basicLands = [{name: "Island", count: 38}]
        state.deckSubmitted = true
        state.snapshotChanged()
        verify(!controller.cardSelected("a"))
        compare(controller.basicValue("Forest"), 1)
        verify(controller.hasUnsubmittedChanges)
        compare(state.pool.length, 2)
        controller.discardUnsubmittedChanges()
        verify(controller.cardSelected("a"))
        compare(controller.basicValue("Forest"), 0)
        verify(!controller.hasUnsubmittedChanges)
    }

    function test_draftPrintingAndIdentityIsolationWithoutView() {
        const controller = createTemporaryObject(controllerComponent, testCase)
        controller.moveToMainDeck("a")
        controller.adjustBasic("Island", 10)
        controller.setBasicPrinting("Island", {setCode: "TST", collectorNumber: "42"})
        controller.draftServer = "ws://another/ws"
        tryCompare(controller, "selectedPoolCount", 0)
        compare(controller.basicValue("Island"), 0)
        controller.draftServer = "ws://local/ws"
        tryCompare(controller, "selectedPoolCount", 1)
        compare(controller.basicValue("Island"), 10)
        compare(controller.basicPrinting("Island").collectorNumber, "42")
        controller.moveToMainDeck("foreign")
        compare(controller.selectedPoolCount, 1)
    }
}
