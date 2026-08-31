// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic
import QtTest
import "../../qml/components"

TestCase {
    name: "RulesRevealPrompt"
    when: windowShown

    ApplicationWindow {
        id: testWindow
        width: 720
        height: 260
        visible: true

        QtObject {
            id: fakeWs
            property int responseCount: 0
            property int lastPromptId: 0
            property string lastResponseId: ""

            function respondRulesPrompt(promptId, responseId) {
                responseCount++
                lastPromptId = promptId
                lastResponseId = responseId
            }
        }

        QtObject {
            id: fakeCatalog
            property int imageRevision: 0

            function tableImageSource(name, setCode, collectorNumber) {
                return ""
            }
        }

        ListModel {
            id: revealCards
            ListElement {
                cardId: "card-a"
                name: "Plains"
                setCode: "M21"
                collectorNumber: "309"
                token: false
            }
            ListElement {
                cardId: "card-b"
                name: "Soldier"
                setCode: "TM21"
                collectorNumber: "1"
                token: true
            }
        }

        RulesRevealPrompt {
            id: prompt
            anchors.fill: parent
            anchors.margins: 20
            wsModel: fakeWs
            cardCatalogModel: fakeCatalog
            cardModel: revealCards
            promptId: 71
        }
    }

    function init() {
        fakeWs.responseCount = 0
        fakeWs.lastPromptId = 0
        fakeWs.lastResponseId = ""
        if (revealCards.count === 0) {
            revealCards.append({
                "cardId": "card-a", "name": "Plains", "setCode": "M21",
                "collectorNumber": "309", "token": false
            })
        }
    }

    function test_showsCardsAndAcknowledgesExactPrompt() {
        const cardList = findChild(prompt, "revealCardList")
        verify(cardList !== null)
        compare(cardList.count, revealCards.count)

        const button = findChild(prompt, "acknowledgeRevealButton")
        verify(button !== null)
        mouseClick(button, button.width / 2, button.height / 2)
        compare(fakeWs.responseCount, 1)
        compare(fakeWs.lastPromptId, 71)
        compare(fakeWs.lastResponseId, "$ack")
    }

    function test_notificationWithoutCardsRemainsActionable() {
        revealCards.clear()
        tryCompare(findChild(prompt, "revealCardList"), "count", 0)
        prompt.acknowledge()
        compare(fakeWs.responseCount, 1)
        compare(fakeWs.lastResponseId, "$ack")
    }
}
