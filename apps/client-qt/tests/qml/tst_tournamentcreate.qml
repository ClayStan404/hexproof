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
        function createTournament() { }
        function createLimitedTournament() { }
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
        TournamentCreate {
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
}
