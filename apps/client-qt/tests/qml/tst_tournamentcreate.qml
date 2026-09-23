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
        property bool forgeRulesAvailable: true
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
        mockWs.forgeRulesAvailable = true
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
        compare(mockWs.submitted.length, 6)
        compare(mockWs.submitted[5], "manual")
        compare(mockWs.submitted[3], 75)
        compare(mockWs.submitted[4], 16)
    }

    function test_firstClickAfterWheelBoundarySubmits_data() {
        return [{tag:"constructed", index:0}, {tag:"sealed", index:1},
                {tag:"draft", index:2}, {tag:"cube", index:3}]
    }
    function test_firstClickAfterWheelBoundarySubmits(data) {
        const selector = findChild(page, "tournamentEventTypeSelector")
        selector.currentIndex = data.index
        selector.activated(data.index)
        findChild(page, "tournamentNameField").text = "Wheel boundary event"
        findChild(page, "tournamentPlayerCapField").text = "4"
        findChild(page, "tournamentRulesMode").activated(1)
        const body = findChild(page, "tournamentCreateBody")
        const button = findChild(page, "tournamentCreateSubmitButton")
        verify(waitForRendering(page))
        verify(button.enabled)
        verify(body.contentHeight > body.height)
        mouseWheel(body, body.width - 10, body.height / 2, 0, -12000)
        tryVerify(() => body.atYEnd && !body.moving)
        mouseClick(button, button.width / 2, button.height / 2)
        compare(data.index === 0 ? mockWs.submitted[5] : mockWs.submittedLimited[6], "forge")
    }

    function test_forgeAvailabilityAndSubmission() {
        findChild(page, "tournamentNameField").text = "Forge Swiss"
        const button = findChild(page, "tournamentCreateSubmitButton")
        const control = findChild(page, "tournamentRulesMode")
        control.activated(1)
        compare(page.rulesMode, "forge")
        mockWs.forgeRulesAvailable = false
        verify(!button.enabled)
        control.activated(0)
        verify(button.enabled)
        mockWs.forgeRulesAvailable = true
        control.activated(1)
        button.clicked()
        compare(mockWs.submitted[5], "forge")
        findChild(page, "tournamentEventTypeSelector").currentIndex = 1
        button.clicked()
        compare(mockWs.submittedLimited[6], "forge")
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
                ["Limited via Events", data.mode, "bo1", 75, data.cap, {id: "pid-1"}, "manual"])
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
                 {id: "cube-1", productType: "cube"}, "manual"])
        cap.text = "9"
        verify(!button.enabled)
    }
}
