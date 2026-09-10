// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic
import QtTest
import "../../qml/screens"

TestCase {
    name: "TournamentCreate"
    when: windowShown

    ApplicationWindow {
        id: testWindow
        width: 1280
        height: 720
        visible: true
        function popScreen() { }
        function pushScreen(url) { }
    }

    QtObject {
        id: mockWs
        property bool connected: true
        property bool inRoom: false
        property string lastError: ""
        property var submitted: []
        property var submittedLimited: []
        function createTournament() { submitted = Array.from(arguments) }
        function createLimitedTournament() { submittedLimited = Array.from(arguments) }
    }

    QtObject {
        id: mockCatalog
        function limitedSets() {
            return [{
                "id": "set-1",
                "setCode": "MCK",
                "name": "Mock Set",
                "productName": "Mock Set",
                "releaseDate": "2026-01-01",
                "authentic": true,
                "boosterKind": "draft",
                "productId": "pid-1"
            }]
        }
        function limitedProduct(id) { return ({id: id}) }
    }

    property var page: null

    QtObject {
        id: mockDecks
        property int count: 1
        property string currentDeckId: "cube-1"
        function matchDecks() {
            return [{deckId: "cube-1", deckName: "Cube", mainCount: 180,
                     exactPrintings: true}]
        }
        function cubeProduct(id) { return ({id: id, productType: "cube"}) }
    }

    Component {
        id: pageComponent
        TournamentCreate {
            wsModel: mockWs
            cardCatalogModel: mockCatalog
            deckLibraryModel: mockDecks
        }
    }

    function init() {
        mockWs.submitted = []
        mockWs.submittedLimited = []
        page = pageComponent.createObject(testWindow.contentItem)
        verify(page !== null)
        page.anchors.fill = testWindow.contentItem
        waitForRendering(page)
    }

    function cleanup() {
        if (page !== null)
            page.destroy()
        page = null
    }

    function test_createButtonStaysReachableOnLaptopHeight() {
        const body = findChild(page, "tournamentCreateBody")
        const button = findChild(page, "tournamentCreateSubmitButton")
        verify(body !== null)
        verify(button !== null)

        const buttonBottom = button.mapToItem(body.contentItem, 0, button.height).y
        verify(body.contentHeight + 0.5 >= buttonBottom)

        body.contentY = Math.max(0, body.contentHeight - body.height)
        waitForRendering(page)
        const buttonTop = button.mapToItem(body, 0, 0).y
        verify(buttonTop + button.height <= body.height + 1)
        verify(buttonTop >= -1)
    }

    function test_creationUsesAutomaticRounds() {
        const name = findChild(page, "tournamentNameField")
        const minutes = findChild(page, "tournamentRoundMinutesField")
        const cap = findChild(page, "tournamentPlayerCapField")
        const button = findChild(page, "tournamentCreateSubmitButton")
        name.text = "Modern Swiss"
        minutes.text = "75"
        cap.text = "16"
        verify(button.enabled)
        button.clicked()
        compare(mockWs.submitted.length, 5)
        compare(mockWs.submitted[3], 75)
        compare(mockWs.submitted[4], 16)
    }

    function test_eventsCreatesLimitedModes_data() {
        return [{tag: "sealed", index: 1, mode: "set_sealed", cap: 12},
                {tag: "draft", index: 2, mode: "set_draft", cap: 8}]
    }
    function test_eventsCreatesLimitedModes(data) {
        const selector = findChild(page, "tournamentEventTypeSelector")
        compare(selector.count, 4)
        selector.currentIndex = data.index
        selector.activated(data.index)
        compare(selector.currentValue, data.mode)
        findChild(page, "tournamentNameField").text = "Limited via Events"
        findChild(page, "tournamentRoundMinutesField").text = "75"
        findChild(page, "tournamentPlayerCapField").text = String(data.cap)
        page.matchMode = "bo1"
        const button = findChild(page, "tournamentCreateSubmitButton")
        verify(button.enabled)
        button.clicked()
        compare(mockWs.submitted.length, 0)
        compare(mockWs.submittedLimited,
                ["Limited via Events", data.mode, "bo1", 75, data.cap, {id: "pid-1"}])
    }

    function test_cubeTournamentRemainsInEventsAndValidatesCapacity() {
        const selector = findChild(page, "tournamentEventTypeSelector")
        selector.currentIndex = 3
        selector.activated(3)
        compare(selector.currentValue, "cube_draft")
        findChild(page, "tournamentNameField").text = "Cube Swiss"
        const cap = findChild(page, "tournamentPlayerCapField")
        compare(cap.text, "8")
        const button = findChild(page, "tournamentCreateSubmitButton")
        verify(!button.enabled, "180 cards cannot fill eight seats")
        cap.text = "4"
        verify(button.enabled)
        button.clicked()
        compare(mockWs.submittedLimited,
                ["Cube Swiss", "cube_draft", "bo3", 50, 4,
                 {id: "cube-1", productType: "cube"}])
        cap.text = "9"
        verify(!button.enabled)
    }
}
