// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic
import QtTest
import "../../qml/components"

TestCase {
    id: testCase
    name: "LimitedConstructionDraft"
    when: windowShown
    ApplicationWindow { id: window; width: 1200; height: 800; visible: true }
    QtObject {
        id: limitedState
        signal snapshotChanged()
        property string tournamentId: "EVENT1"
        property string eventType: "set_draft"
        property string stage: "deck_building"
        property bool deckSubmitted: false
        property bool allDecksSubmitted: false
        property var mainboardInstanceIds: []
        property var basicLands: []
        property var participants: []
        property var pool: [
            {instanceId:"a",name:"Island",typeLine:"Basic Land — Island"},
            {instanceId:"b",name:"Test creature",typeLine:"Creature"}
        ]
    }
    QtObject {
        id: connection
        property string serverUrl: "ws://localhost:57320/ws"
        property bool connected: true
    }
    QtObject {
        id: catalog
        property int imageRevision: 0
        function tableImageSource() { return "" }
        function cacheCardsIncrementally() { }
    }
    QtObject {
        id: store
        property var entries: ({})
        property string lastError: ""
        function key(server, event, seat) { return JSON.stringify([server, event, seat]) }
        function loadDraft(server, event, seat) { return entries[key(server,event,seat)] || ({}) }
        function saveDraft(server, event, seat, draft) { entries[key(server,event,seat)] = JSON.parse(JSON.stringify(draft)) }
        function removeDraft(server, event, seat) { delete entries[key(server,event,seat)] }
    }
    Component {
        id: builderComponent
        LimitedDeckBuilder {
            width: 1200; height: 800
            limitedModel: limitedState
            wsModel: connection
            cardCatalogModel: catalog
            draftStore: store
            participantId: "p-1"
        }
    }
    function init() {
        store.entries = ({})
        limitedState.eventType = "set_draft"
        limitedState.deckSubmitted = false
        limitedState.allDecksSubmitted = false
        limitedState.participants = []
        limitedState.mainboardInstanceIds = []
        limitedState.basicLands = []
        connection.serverUrl = "ws://localhost:57320/ws"
        limitedState.stage = "deck_building"
        limitedState.tournamentId = "EVENT1"
        testLimitedDraftStore.removeDraft(connection.serverUrl, "EVENT1", "p-1")
    }
    function test_nativeStoreRestoresQtVariantSequence() {
        testLimitedDraftStore.saveDraft(connection.serverUrl, "EVENT1", "p-1", {
            mainboardInstanceIds: ["a", "b"], basics: {Island: 17}, initialPoolChosen: true
        })
        const builder = createTemporaryObject(builderComponent, window.contentItem, {
            draftStore: testLimitedDraftStore
        })
        compare(builder.selectedCount, 19)
        verify(builder.initialPoolChosen)
    }
    function test_submittedCubeStillShowsActiveSubmissionProgress() {
        limitedState.eventType = "cube_draft"
        limitedState.deckSubmitted = true
        limitedState.mainboardInstanceIds = ["b"]
        limitedState.basicLands = [{name: "Island", count: 39}]
        limitedState.participants = [
            {participantId: "p-1", deckSubmitted: true},
            {participantId: "p-2", deckSubmitted: false},
            {participantId: "p-3", deckSubmitted: false, withdrawn: true}
        ]
        const builder = createTemporaryObject(builderComponent, window.contentItem, {cubeFreePlay: true})
        const status = findChild(builder, "limitedDeckSubmissionStatus")
        const notice = findChild(builder, "limitedAutomaticTableNotice")
        compare(status.text, "Deck submitted · Waiting for participants: 1 / 2")
        verify(notice.visible)
        builder.adjustBasic("Island", 1)
        compare(status.text, "Unsubmitted deck changes", "Later edits keep their explicit warning")
        builder.adjustBasic("Island", -1)
        limitedState.participants = [
            {participantId: "p-1", deckSubmitted: true},
            {participantId: "p-2", deckSubmitted: true}
        ]
        compare(status.text, "Deck submitted · Waiting for participants: 2 / 2")
        limitedState.stage = "competition"
        compare(status.text, "Deck submitted")
        verify(!notice.visible)
    }
    function test_automaticEntryNoticeOnlyPromisesSupportedInitialTables_data() {
        return [{tag: "Cube two", event: "cube_draft", players: 2, cube: true, expected: true},
            {tag: "Cube four", event: "cube_draft", players: 4, cube: true, expected: false},
            {tag: "Commander two", event: "commander_cube", players: 2, cube: true, expected: true},
            {tag: "Commander three", event: "commander_cube", players: 3, cube: true, expected: true},
            {tag: "Commander four", event: "commander_cube", players: 4, cube: true, expected: true},
            {tag: "Commander five", event: "commander_cube", players: 5, cube: true, expected: true},
            {tag: "Commander eight", event: "commander_cube", players: 8, cube: true, expected: true},
            {tag: "Commander nine", event: "commander_cube", players: 9, cube: true, expected: false},
            {tag: "Swiss Cube", event: "cube_draft", players: 2, cube: false, expected: false},
            {tag: "Set draft", event: "set_draft", players: 2, cube: true, expected: false},
            {tag: "Sitting out", event: "commander_cube", players: 3, cube: true, expected: false}]
    }
    function test_automaticEntryNoticeOnlyPromisesSupportedInitialTables(data) {
        limitedState.eventType = data.event
        limitedState.participants = Array.from({length: data.players}, (_, index) => ({
            participantId: "p-" + (index + 1), withdrawn: data.tag === "Sitting out" && index === 0
        }))
        const builder = createTemporaryObject(builderComponent, window.contentItem, {cubeFreePlay: data.cube})
        compare(builder.automaticTableAfterSubmission, data.expected)
    }
    function test_reopeningRestoresUnsubmittedConstruction() {
        let builder = builderComponent.createObject(window.contentItem)
        builder.chooseInitialPool(true)
        builder.moveToSideboard("a")
        builder.adjustBasic("Island", 17)
        builder.destroy()
        wait(0)
        builder = createTemporaryObject(builderComponent, window.contentItem)
        compare(builder.selectedPoolCount, 1)
        verify(builder.cardSelected("b"))
        verify(!builder.cardSelected("a"))
        compare(builder.basicValue("Island"), 17)
        verify(builder.initialPoolChosen)
        builder.moveToSideboard("b")
        compare(store.loadDraft(connection.serverUrl,"EVENT1","p-1").mainboardInstanceIds.length, 0)
    }
    function test_changedServerDoesNotKeepPreviousDraft() {
        const builder = createTemporaryObject(builderComponent, window.contentItem)
        builder.chooseInitialPool(true)
        builder.adjustBasic("Island", 17)
        connection.serverUrl = "ws://localhost:57321/ws"
        tryCompare(builder, "selectedCount", 0)
        verify(!builder.initialPoolChosen)
    }
    function test_restorationDropsRemovedInstancesAndSubmissionWins() {
        store.saveDraft(connection.serverUrl,"EVENT1","p-1", {
            mainboardInstanceIds:["a","removed"], basics:{Island:17},initialPoolChosen:true
        })
        const builder = createTemporaryObject(builderComponent, window.contentItem)
        compare(builder.selectedPoolCount, 1)
        limitedState.mainboardInstanceIds = ["b"]
        limitedState.basicLands = [{name:"Forest",count:20}]
        limitedState.deckSubmitted = true
        limitedState.snapshotChanged()
        verify(builder.cardSelected("b"))
        verify(!builder.cardSelected("a"))
        compare(builder.basicValue("Forest"), 20)
        compare(builder.basicValue("Island"), 0)
        compare(Object.keys(store.loadDraft(connection.serverUrl,"EVENT1","p-1")).length, 0)
    }
    function test_sittingOutCubeFirstDeckSurvivesFreePlayAndRestart_data() {
        return [{tag: "regular Cube", eventType: "cube_draft"},
            {tag: "Commander Cube", eventType: "commander_cube"}]
    }
    function test_sittingOutCubeFirstDeckSurvivesFreePlayAndRestart(data) {
        limitedState.eventType = data.eventType
        let builder = builderComponent.createObject(window.contentItem, {cubeFreePlay: true})
        builder.chooseInitialPool(true)
        builder.moveToSideboard("a")
        builder.adjustBasic("Island", 17)
        if (data.eventType === "commander_cube") builder.toggleCommander("b")
        limitedState.stage = "competition"
        limitedState.snapshotChanged()
        verify(builder.cardSelected("b"))
        compare(builder.basicValue("Island"), 17)
        builder.adjustBasic("Island", 2)
        compare(store.loadDraft(connection.serverUrl, "EVENT1", "p-1").basics.Island, 19)
        builder.destroy()
        wait(0)
        builder = createTemporaryObject(builderComponent, window.contentItem, {cubeFreePlay: true})
        compare(builder.selectedPoolCount, 1)
        verify(builder.cardSelected("b"))
        verify(!builder.cardSelected("a"))
        compare(builder.basicValue("Island"), 19)
        verify(builder.initialPoolChosen)
        verify(!builder.autoBasicLands)
        compare(builder.commanderInstanceIds, data.eventType === "commander_cube" ? ["b"] : [])
        builder.adjustBasic("Forest", 3)
        compare(store.loadDraft(connection.serverUrl, "EVENT1", "p-1").basics.Forest, 3)
    }
    function test_sittingOutCubeRestoresDraftCreatedBeforeFreePlay() {
        limitedState.eventType = "cube_draft"
        let builder = builderComponent.createObject(window.contentItem, {cubeFreePlay: true})
        builder.chooseInitialPool(true)
        builder.adjustBasic("Forest", 18)
        builder.destroy()
        wait(0)
        limitedState.stage = "competition"
        builder = createTemporaryObject(builderComponent, window.contentItem, {cubeFreePlay: true})
        compare(builder.selectedPoolCount, 2)
        compare(builder.basicValue("Forest"), 18)
        verify(builder.initialPoolChosen)
    }
    function test_freePlayRestorationStillPrefersSubmittedDeck() {
        limitedState.eventType = "commander_cube"
        limitedState.stage = "competition"
        store.saveDraft(connection.serverUrl, "EVENT1", "p-1", {
            mainboardInstanceIds: ["b"], basics: {Island: 17}, initialPoolChosen: true
        })
        limitedState.deckSubmitted = true
        limitedState.mainboardInstanceIds = ["a"]
        limitedState.basicLands = [{name: "Forest", count: 20}]
        const builder = createTemporaryObject(builderComponent, window.contentItem, {cubeFreePlay: true})
        verify(builder.cardSelected("a"))
        verify(!builder.cardSelected("b"))
        compare(builder.basicValue("Forest"), 20)
        compare(builder.basicValue("Island"), 0)
        compare(Object.keys(store.loadDraft(connection.serverUrl, "EVENT1", "p-1")).length, 0)
    }
    function test_swissCubeAndOtherModesDoNotRestoreCompetitionDraft_data() {
        return [{tag: "Swiss Cube", eventType: "cube_draft", cubeFreePlay: false},
            {tag: "Set Draft", eventType: "set_draft", cubeFreePlay: true}]
    }
    function test_swissCubeAndOtherModesDoNotRestoreCompetitionDraft(data) {
        limitedState.eventType = data.eventType
        limitedState.stage = "competition"
        const saved = {mainboardInstanceIds: ["b"], basics: {Island: 17}, initialPoolChosen: true}
        store.saveDraft(connection.serverUrl, "EVENT1", "p-1", saved)
        const builder = createTemporaryObject(builderComponent, window.contentItem,
            {cubeFreePlay: data.cubeFreePlay})
        compare(builder.selectedPoolCount, 0)
        compare(builder.basicValue("Island"), 0)
        builder.adjustBasic("Forest", 2)
        compare(store.loadDraft(connection.serverUrl, "EVENT1", "p-1"), saved)
    }
}
