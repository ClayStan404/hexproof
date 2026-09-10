// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic
import QtTest
import "../../qml/screens"

TestCase {
    name: "LimitedRoomCreate"
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
        function createLimitedTournament() { submitted = Array.from(arguments) }
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
        function limitedProduct() { return ({}) }
    }

    property var page: null

    Component {
        id: pageComponent
        LimitedRoomCreate {
            wsModel: mockWs
            cardCatalogModel: mockCatalog
        }
    }

    function init() {
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
        const body = findChild(page, "limitedRoomCreateBody")
        const button = findChild(page, "limitedRoomCreateSubmitButton")
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

    function test_sharedSettingsAndDraftCapacity() {
        const selector = findChild(page, "limitedEventTypeSelector")
        const name = findChild(page, "tournamentNameField")
        const minutes = findChild(page, "tournamentRoundMinutesField")
        const cap = findChild(page, "tournamentPlayerCapField")
        const button = findChild(page, "limitedRoomCreateSubmitButton")
        compare(selector.count, 2)
        compare(selector.currentValue, "set_sealed")
        compare(minutes.text, "50")
        compare(cap.text, "8")
        name.text = "Limited Swiss"
        minutes.text = "75"
        cap.text = "12"
        verify(button.enabled)
        button.clicked()
        compare(mockWs.submitted.length, 6)
        compare(mockWs.submitted[1], "set_sealed")
        compare(mockWs.submitted[3], 75)
        compare(mockWs.submitted[4], 12)
        selector.currentIndex = 1
        selector.activated(1)
        compare(cap.text, "8")
        button.clicked()
        compare(mockWs.submitted[1], "set_draft")
        compare(mockWs.submitted[4], 8)
    }
}
