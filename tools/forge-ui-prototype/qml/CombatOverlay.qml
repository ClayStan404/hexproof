// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors
import QtQuick
import QtQuick.Layouts

Item {
    id: root
    required property var model
    required property var board
    property string assetRoot: ""
    property real unit: 1
    readonly property Item primaryButton: confirm
    readonly property Item cancelButton: clear
    readonly property string heading: model.mode === "attack" ? "Declare attackers"
        : model.mode === "block" ? "Declare blockers" : "Assign combat damage"
    function primaryAction() { model.confirm() }

    Rectangle {
        x: (parent.width - width) / 2
        y: 69 * root.unit
        width: 660 * root.unit
        height: 76 * root.unit
        radius: 10 * root.unit
        color: "#f1192934"
        border.color: "#8f836c"
        Column {
            x: 17 * root.unit
            y: 12 * root.unit
            spacing: 7 * root.unit
            StudyLabel { text: root.heading; color: "#ead8b4"; pointSize: 17; unit: root.unit }
            StudyLabel {
                text: root.model.committed ? "Choice submitted. Waiting for the next decision."
                    : root.model.mode === "attack" ? "Select your creatures. Each selected attacker attacks the opponent."
                    : root.model.mode === "block" ? (root.model.selectedBlocker ? "Now select an opposing attacker." : "Select your blocker, then the attacker it will block.")
                    : "Distribute all 6 damage between the two blockers."
                pointSize: 11
                unit: root.unit
            }
        }
    }
    Row {
        x: 27 * root.unit
        y: 122 * root.unit
        spacing: 4 * root.unit
        Repeater {
            model: [{id:"attack",name:"Attack"}, {id:"block",name:"Block"}, {id:"damage",name:"Damage"}]
            delegate: StudyButton {
                required property var modelData
                objectName: "studyCombatMode-" + modelData.id
                text: modelData.name
                checked: root.model.mode === modelData.id
                quiet: true
                implicitWidth: 81 * root.unit
                implicitHeight: 31 * root.unit
                unit: root.unit
                onClicked: root.model.reset(modelData.id)
            }
        }
    }
    StudyLabel {
        x: 28 * root.unit
        y: 104 * root.unit
        text: "COMBAT EXAMPLES"
        pointSize: 8
        font.letterSpacing: 1.2
        unit: root.unit
        color: "#92a9b5"
    }
    Repeater {
        model: root.model.links
        delegate: StudyArrow {
            required property var modelData
            anchors.fill: parent
            unit: root.unit
            lineColor: root.model.mode === "block" ? "#7ebcca" : "#e1bd7f"
            startPoint: root.board.pointFor(modelData.from)
            endPoint: root.board.pointFor(modelData.to)
        }
    }
    Rectangle {
        visible: root.model.mode === "damage"
        x: parent.width - width - 26 * root.unit
        y: 325 * root.unit
        width: 274 * root.unit
        height: 279 * root.unit
        color: "#f1162631"
        radius: 12 * root.unit
        border.color: "#65727a"
        Column {
            anchors.fill: parent
            anchors.margins: 13 * root.unit
            spacing: 13 * root.unit
            StudyLabel { text: "ARCBOUND RAVAGER"; color: "#e5d1aa"; pointSize: 12; unit: root.unit }
            StudyLabel { text: "6 damage available  /  two blockers"; pointSize: 10; unit: root.unit }
            Repeater {
                model: [{id:"ballista",name:"Walking Ballista"}, {id:"walker",name:"Hangarback Walker"}]
                delegate: Rectangle {
                    required property var modelData
                    width: parent.width
                    height: 83 * root.unit
                    radius: 7 * root.unit
                    color: "#223641"
                    Image {
                        x: 6 * root.unit; y: 6 * root.unit
                        width: 61 * root.unit; height: 71 * root.unit
                        source: root.assetRoot ? root.assetRoot + modelData.id + "-art.jpg" : ""
                        fillMode: Image.PreserveAspectCrop
                    }
                    StudyLabel {
                        x: 76 * root.unit; y: 8 * root.unit
                        width: parent.width - x - 7 * root.unit
                        text: modelData.name
                        pointSize: 11; unit: root.unit
                        wrapMode: Text.WordWrap
                    }
                    Row {
                        x: 73 * root.unit; y: 43 * root.unit
                        spacing: 7 * root.unit
                        StudyButton {
                            objectName: "studyDamageMinus-" + modelData.id
                            text: "−"; unit: root.unit
                            implicitWidth: 36 * root.unit; implicitHeight: 29 * root.unit
                            enabled: !root.model.committed && root.model.damage[modelData.id] > 0
                            onClicked: root.model.adjustDamage(modelData.id, -1)
                        }
                        StudyLabel { text: root.model.damage[modelData.id]; width: 26 * root.unit; height: 29 * root.unit; horizontalAlignment: Text.AlignHCenter; pointSize: 17; unit: root.unit; color: "#ecd29d" }
                        StudyButton {
                            objectName: "studyDamagePlus-" + modelData.id
                            text: "+"; unit: root.unit
                            implicitWidth: 36 * root.unit; implicitHeight: 29 * root.unit
                            enabled: !root.model.committed && root.model.damage[modelData.id] < root.model.damageTotal
                            onClicked: root.model.adjustDamage(modelData.id, 1)
                        }
                    }
                }
            }
        }
    }
    Rectangle {
        x: parent.width - width - 24 * root.unit
        y: parent.height - height - 26 * root.unit
        width: 308 * root.unit
        height: 171 * root.unit
        radius: 13 * root.unit
        color: "#f114222c"
        border.color: "#a89064"
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 15 * root.unit
            spacing: 10 * root.unit
            StudyLabel {
                text: root.model.committed ? "CHOICE SUBMITTED" : root.heading.toUpperCase()
                unit: root.unit; pointSize: 11; color: "#dcc18e"
            }
            StudyLabel {
                Layout.fillWidth: true
                text: root.model.committed ? "The battlefield keeps your chosen relationships visible."
                    : root.model.mode === "attack" ? root.model.attackers.length + " attackers selected"
                    : root.model.mode === "block" ? root.model.blocks.length + " blockers assigned"
                    : root.model.assignedDamage + " / " + root.model.damageTotal + " damage assigned"
                pointSize: 13; unit: root.unit
                wrapMode: Text.WordWrap
            }
            Item { Layout.fillHeight: true }
            RowLayout {
                Layout.fillWidth: true
                StudyButton {
                    id: clear
                    objectName: "studyCombatClear"
                    text: "Reset"
                    unit: root.unit
                    Layout.fillWidth: true
                    onClicked: root.model.reset(root.model.mode)
                }
                StudyButton {
                    id: confirm
                    objectName: "studyCombatConfirm"
                    text: root.model.committed ? "Submitted" : root.model.mode === "attack"
                        ? (root.model.attackers.length ? "Attack with " + root.model.attackers.length : "No attacks")
                        : root.model.mode === "block" ? "Confirm blocks" : "Confirm damage"
                    enabled: root.model.canConfirm
                    primary: true
                    unit: root.unit
                    Layout.fillWidth: true
                    onClicked: root.primaryAction()
                }
            }
        }
    }
}
