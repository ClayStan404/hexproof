// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic
import QtTest
import "../../qml/components"

TestCase {
    name: "RulesPromptContext"
    when: windowShown

    ApplicationWindow {
        width: 720
        height: 180
        visible: true

        QtObject {
            id: fakeCatalog
            property int imageRevision: 0

            function tableImageSource(name, setCode, collectorNumber) {
                return ""
            }
        }

        ListModel {
            id: sourceCards
            ListElement {
                cardId: "context-card:0"
                name: "Circle of Protection: Red"
                setCode: "4ED"
                collectorNumber: "17"
                token: false
            }
        }

        ListModel {
            id: affectedTargets
            ListElement {
                responseId: "context-target:0"
                kind: "card"
                label: "Ball Lightning"
                objectId: "target-card-1"
                name: "Ball Lightning"
                setCode: "4ED"
                collectorNumber: "174"
                token: false
            }
            ListElement {
                responseId: "context-target:1"
                kind: "player"
                label: "Alice · Seat 1"
                objectId: ""
                name: ""
                setCode: ""
                collectorNumber: ""
                token: false
            }
        }

        RulesPromptContext {
            id: prompt
            anchors.fill: parent
            anchors.margins: 20
            cardCatalogModel: fakeCatalog
            sourceCardModel: sourceCards
            targetModel: affectedTargets
            contextText: "otherwise: \"3 damage is dealt.\""
        }
    }

    function test_presentsSourceEffectAndAffectedObjects() {
        verify(prompt.visible)
        verify(prompt.hasContext)
        compare(prompt.sourceCount, 1)
        compare(prompt.targetCount, 2)
        const textItem = findChild(prompt, "rulesPromptContextText")
        verify(textItem !== null)
        compare(textItem.text, "otherwise: \"3 damage is dealt.\"")
    }
}
