// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic
import QtTest
import "../../qml/screens"

TestCase {
    name: "CreateRoom"
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
        property bool forgeRulesAvailable: true
        property bool inRoom: false
        property string lastError: ""
        property int createCount: 0
        function createRoom() { ++createCount }
        function createLimitedTournament() { }
    }

    QtObject {
        id: mockDecks
        property int count: 0
        property string currentDeckId: ""
        signal currentDeckChanged()
        function matchDecks() { return [] }
        function cubeProduct() { return ({}) }
    }

    property var page: null

    Component {
        id: pageComponent
        CreateRoom {
            wsModel: mockWs
            deckLibraryModel: mockDecks
        }
    }

    function init() {
        mockWs.createCount = 0
        page = pageComponent.createObject(testWindow.contentItem)
        verify(page !== null)
        page.anchors.fill = testWindow.contentItem
        page.roomName = "Friday night"
        waitForRendering(page)
    }

    function cleanup() {
        if (page !== null)
            page.destroy()
        page = null
    }

    function test_createButtonStaysReachableOnLaptopHeight() {
        const body = findChild(page, "createRoomBody")
        const button = findChild(page, "createRoomSubmitButton")
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

    function test_formatsUsePopularOrderAndCustomLast() {
        compare(page.formatOptions[0].value, "modern")
        compare(page.formatOptions[1].value, "commander")
        compare(page.formatOptions[2].value, "duel")
        compare(page.formatOptions[3].value, "legacy")
        compare(page.formatOptions[page.formatOptions.length - 1].value,
                "custom")
        compare(page.deckFormat, "modern")
    }

    function test_playtestKeepsCustomAndExcludesCube() {
        page.playtestMode = true
        compare(page.selectableFormatOptions.length,
                page.formatOptions.length - 1)
        compare(page.selectableFormatOptions[
                    page.selectableFormatOptions.length - 1].value,
                "custom")
        for (let index = 0;
             index < page.selectableFormatOptions.length; ++index) {
            verify(page.selectableFormatOptions[index].value !== "cube")
        }
    }
}
