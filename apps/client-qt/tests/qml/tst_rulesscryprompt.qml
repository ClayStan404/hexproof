// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic
import QtTest
import "../../qml/components"

TestCase {
    name: "RulesScryPrompt"
    when: windowShown

    ApplicationWindow {
        width: 760
        height: 320
        visible: true

        QtObject {
            id: fakeWs
            property int responseCount: 0
            property int lastPromptId: 0
            property var lastPiles: []

            function respondRulesPromptWithScry(promptId, piles) {
                responseCount++
                lastPromptId = promptId
                lastPiles = piles
            }
        }

        QtObject {
            id: fakeCatalog
            property int imageRevision: 0

            function tableImageSource(name, setCode, collectorNumber) {
                return ""
            }
        }

        QtObject {
            id: scryCards

            function items() {
                return [
                    {"cardId": "scry:0", "name": "Island", "setCode": "M21",
                     "collectorNumber": "310", "token": false},
                    {"cardId": "scry:1", "name": "Opt", "setCode": "M21",
                     "collectorNumber": "59", "token": false}
                ]
            }
        }

        RulesScryPrompt {
            id: prompt
            anchors.fill: parent
            anchors.margins: 20
            wsModel: fakeWs
            cardCatalogModel: fakeCatalog
            cardModel: scryCards
            destinations: ["libraryTop", "graveyard"]
            promptId: 72
        }
    }

    function init() {
        fakeWs.responseCount = 0
        fakeWs.lastPromptId = 0
        fakeWs.lastPiles = []
        prompt.resetPiles()
    }

    function test_partitionsOrdersAndSubmitsOpaqueCards() {
        compare(prompt.cardsForPile(0).length, 2)
        compare(prompt.cardsForPile(1).length, 0)
        verify(prompt.moveWithinPile("scry:1", 0, -1))
        compare(prompt.cardsForPile(0)[0].cardId, "scry:1")
        verify(prompt.moveCard("scry:0", 0, 1))
        compare(prompt.cardsForPile(0).length, 1)
        compare(prompt.cardsForPile(1)[0].cardId, "scry:0")

        prompt.submitPiles()
        compare(fakeWs.responseCount, 1)
        compare(fakeWs.lastPromptId, 72)
        compare(fakeWs.lastPiles.length, 2)
        compare(fakeWs.lastPiles[0].destination, "libraryTop")
        compare(fakeWs.lastPiles[0].cardIds[0], "scry:1")
        compare(fakeWs.lastPiles[1].destination, "graveyard")
        compare(fakeWs.lastPiles[1].cardIds[0], "scry:0")
    }
}
