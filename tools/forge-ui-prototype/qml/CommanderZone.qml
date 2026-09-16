// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors
import QtQuick

Rectangle {
    id: root
    required property var card
    property string assetRoot: ""
    property real unit: 1
    property string caption: "YOUR COMMANDER"
    property string location: "command"
    property string cost: "2 W"
    property string tax: "+2"
    property int castCount: 1
    property bool actionable: false
    property string controlName: "studyCommanderOwn"
    signal activated()
    signal inspected(var card)
    width: 282 * unit
    height: 144 * unit
    radius: 11 * unit
    color: "#e6172833"
    border.color: actionable ? "#8eb7be" : "#566773"
    StudyCard {
        objectName: root.controlName
        x: 9 * root.unit
        y: 18 * root.unit
        width: 80 * root.unit
        height: 112 * root.unit
        card: root.card
        fullFace: true
        assetRoot: root.assetRoot
        unit: root.unit
        actionable: root.actionable
        opacity: root.location === "command" ? 1 : 0.35
        onActivated: root.activated()
        onInspected: card => root.inspected(card)
    }
    Column {
        x: 102 * root.unit
        y: 12 * root.unit
        width: parent.width - x - 11 * root.unit
        spacing: 6 * root.unit
        StudyLabel { text: root.caption; pointSize: 9; font.letterSpacing: 1; color: "#d8bd86"; unit: root.unit }
        StudyLabel {
            width: parent.width
            text: root.card.name
            pointSize: 12; unit: root.unit; color: "#e7e8de"
            wrapMode: Text.WordWrap
        }
        StudyLabel {
            text: root.location === "command" ? "Command zone" : root.location === "stack"
                ? "On the stack" : root.location === "battlefield" ? "On the battlefield" : "In the graveyard"
            pointSize: 10; unit: root.unit
        }
        StudyLabel { text: "Cast " + root.castCount + (root.castCount === 1 ? " time" : " times") + "  ·  tax " + root.tax; pointSize: 10; unit: root.unit }
        StudyLabel { text: "Next cost  " + root.cost; pointSize: 12; unit: root.unit; color: "#e5c88e" }
    }
}
