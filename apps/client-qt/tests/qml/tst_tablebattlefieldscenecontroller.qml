// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic
import QtTest
import "../../qml/components"

TestCase {
    id: testCase
    name: "TableBattlefieldSceneController"
    when: windowShown
    width: 640
    height: 480

    ApplicationWindow {
        id: testWindow
        width: 640
        height: 480
        visible: true
    }

    Item {
        id: fakeTable
        parent: testWindow.contentItem
        width: 640
        height: 480

        property var gameTableModel: relationModel
    }

    QtObject {
        id: relationModel

        property var attachments: [{
            "sourceCardId": "card-1",
            "targetCardId": "card-2"
        }]
        property var arrows: [{
            "seat": 2,
            "sourceCardId": "card-2",
            "kind": "target",
            "targetCardId": "card-1"
        }]

        function attachmentForSource(cardId) {
            for (let index = 0; index < attachments.length; ++index) {
                if (attachments[index].sourceCardId === cardId)
                    return attachments[index]
            }
            return ({})
        }

        function arrowForSource(cardId) {
            for (let index = 0; index < arrows.length; ++index) {
                if (arrows[index].sourceCardId === cardId)
                    return arrows[index]
            }
            return ({})
        }
    }

    Item {
        id: battlefieldSurface
        parent: fakeTable
        x: 20
        y: 30
        width: 500
        height: 350
        property int paintRequests: 0

        function requestPaint() {
            ++paintRequests
        }
    }

    Item {
        id: cardOne
        parent: battlefieldSurface
        x: 40
        y: 50
        width: 80
        height: 112
    }

    Item {
        id: cardTwo
        parent: battlefieldSurface
        x: 180
        y: 90
        width: 80
        height: 112
    }

    TableBattlefieldSceneController {
        id: controller
        tableRoot: fakeTable
        sceneView: battlefieldSurface
    }

    function init() {
        controller.cardItems.clear()
        controller.seatItems.clear()
        controller.cardPoints = ({})
        controller.seatPoints = ({})
        controller.pointRefreshScheduled = false
        battlefieldSurface.paintRequests = 0
        cardOne.visible = true
        cardTwo.visible = true
    }

    function test_registersCardsAndBuildsScenePoints() {
        controller.registerCard("card-1", cardOne)
        controller.registerCard("card-2", cardTwo)
        controller.refreshCardPoints()

        compare(controller.cardItems.size, 2)
        compare(controller.cardPoints["card-1"].x,
                cardOne.x + cardOne.width / 2)
        compare(controller.cardPoints["card-1"].y,
                cardOne.y + cardOne.height / 2)
        verify(battlefieldSurface.paintRequests > 0)

        const rootPoint = cardOne.mapToItem(
                            fakeTable, cardOne.width / 2,
                            cardOne.height / 2)
        verify(controller.cardAtRootPoint(rootPoint.x, rootPoint.y))
        verify(!controller.cardAtRootPoint(630, 470))
    }

    function test_unregisterIgnoresStaleDelegateAndRemovesCurrentOne() {
        controller.registerCard("card-1", cardOne)
        controller.unregisterCard("card-1", cardTwo)
        compare(controller.cardItems.get("card-1"), cardOne)

        controller.unregisterCard("card-1", cardOne)
        verify(!controller.cardItems.has("card-1"))
    }

    function test_queriesIndexedRelations() {
        compare(controller.selectedAttachment("card-1").targetCardId,
                "card-2")
        compare(controller.arrowForSource("card-2").seat, 2)
        compare(Object.keys(controller.selectedAttachment("missing")).length,
                0)
    }

    function test_hiddenCardsAreExcludedFromPointCache() {
        controller.registerCard("card-1", cardOne)
        controller.registerCard("card-2", cardTwo)
        cardTwo.visible = false
        controller.refreshCardPoints()
        verify(controller.cardPoints["card-1"] !== undefined)
        verify(controller.cardPoints["card-2"] === undefined)
    }
}
