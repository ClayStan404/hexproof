// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic
import QtTest
import "../../qml/components"

TestCase {
    id: testCase
    name: "TableOverlayLayer"
    width: 800
    height: 600
    when: windowShown

    ApplicationWindow {
        id: testWindow
        width: 800
        height: 600
        visible: true
    }

    QtObject {
        id: fakeWs
        property bool sideboarding: false
    }

    Item {
        id: fakeTable
        width: 800
        height: 600
        property var wsModel: fakeWs
        property var gameSession: fakeWs
        property var sessionUi: fakeTable
        property var presentation: fakeTable
        property bool showGameLogRail: false
        property bool tableModalOpen: false
        property bool hoverPreviewVisible: true
        property real hoverPreviewX: 120
        property real hoverPreviewY: 80
        property var inspectedCard: ({"name": "Preview card"})
        property int restoreCalls: 0
        function setGameLogRailVisible(show) {
            showGameLogRail = show
            ++restoreCalls
        }
        function cardImageSource(card) { return "" }
        function tableCardImageSource(card) {
            if (card && card.faceDown === true)
                return ""
            return cardImageSource(card)
        }
        function tableCardPlaceholderName(card) {
            if (!card || card.faceDown === true)
                return ""
            return card.name ? card.name : ""
        }
    }

    TableOverlayLayer {
        id: layer
        parent: testWindow.contentItem
        tableController: fakeTable
    }

    function init() {
        fakeWs.sideboarding = false
        fakeTable.showGameLogRail = false
        fakeTable.tableModalOpen = false
        fakeTable.hoverPreviewVisible = true
        fakeTable.hoverPreviewX = 120
        fakeTable.hoverPreviewY = 80
        fakeTable.inspectedCard = {"name": "Preview card"}
        fakeTable.restoreCalls = 0
    }

    function test_restoresGameLogRail() {
        const button = findChild(layer, "restoreGameLogRailButton")
        verify(button.visible)
        button.clicked()
        verify(fakeTable.showGameLogRail)
        compare(fakeTable.restoreCalls, 1)
    }

    function test_modalShieldAndPreviewFollowTableState() {
        const shield = findChild(layer, "tableModalInputShield")
        const preview = findChild(layer, "cardHoverPreview")
        verify(!shield.visible)
        verify(preview.visible)
        compare(preview.x, 120)
        compare(preview.y, 80)

        fakeTable.tableModalOpen = true
        verify(shield.visible)
        verify(!preview.visible)
    }

    function test_hidesFaceDownPreviewName() {
        fakeTable.inspectedCard = {"name": "Willbender", "faceDown": true}
        const previewName = findChild(layer, "cardHoverPreviewName")
        verify(!previewName.visible)
        compare(previewName.text, "")
    }
}
