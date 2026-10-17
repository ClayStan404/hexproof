// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors
import QtQuick
import QtQuick.Layouts

Rectangle {
    id: root
    required property var controller
    property real unit: 1
    readonly property Item primaryButton: primaryControl
    readonly property Item cancelButton: cancelControl
    width: 308 * unit
    height: (controller.stage === "payment" ? 225 : controller.stage === "target" ? 164 : 182) * unit
    radius: 13 * unit
    color: "#f114222c"
    border.color: controller.choosing ? "#a89064" : "#3d505e"
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 15 * root.unit
        spacing: 9 * root.unit
        RowLayout {
            Layout.fillWidth: true
            Text {
                textFormat: Text.PlainText
                text: root.controller.stage === "target" ? "CHOOSE A TARGET"
                    : root.controller.stage === "payment" ? "PAY FOR LIGHTNING BOLT"
                    : "YOU HAVE PRIORITY"
                color: "#dcc18e"
                font.pixelSize: 10 * root.unit
                font.weight: Font.DemiBold
                font.letterSpacing: 1.2
                Layout.fillWidth: true
            }
            Text {
                textFormat: Text.PlainText
                text: root.controller.choosing ? (root.controller.stage === "target" ? "1 / 2" : "2 / 2") : "●"
                color: "#9fbbc4"
                font.pixelSize: 11 * root.unit
            }
        }
        Text {
            textFormat: Text.PlainText
            Layout.fillWidth: true
            text: root.controller.stage === "target" ? "Click a highlighted creature or player."
                : root.controller.stage === "payment" ? "Target: " + root.controller.selectedTargetName
                : root.controller.stack.length ? "Respond now, or resolve the top object."
                : "First main phase · turn 4"
            color: "#a6bac6"
            font.pixelSize: 12 * root.unit
            wrapMode: Text.WordWrap
        }
        RowLayout {
            visible: root.controller.stage === "payment"
            spacing: 10 * root.unit
            Rectangle {
                Layout.preferredWidth: 38 * root.unit
                Layout.preferredHeight: 38 * root.unit
                radius: width / 2
                color: root.controller.canPay ? "#b57462" : "#3b3030"
                border.color: "#cd9478"
                Text {
                    textFormat: Text.PlainText
                    anchors.centerIn: parent
                    text: "R"
                    color: "#fae9d6"
                    font.pixelSize: 20 * root.unit
                    font.weight: Font.Bold
                }
            }
            Text {
                textFormat: Text.PlainText
                text: root.controller.canPay ? "1 / 1 mana selected" : "Choose a red mana source"
                color: "#d2dce0"
                font.pixelSize: 12 * root.unit
            }
        }
        RowLayout {
            visible: root.controller.stage === "payment"
            Layout.fillWidth: true
            StudyButton {
                text: "Change target"
                quiet: true
                unit: root.unit
                Layout.fillWidth: true
                onClicked: root.controller.changeTarget()
            }
            StudyButton {
                objectName: "studyAutoPay"
                text: "Auto pay"
                unit: root.unit
                Layout.fillWidth: true
                onClicked: root.controller.autoPay()
            }
        }
        Item { Layout.fillHeight: true; implicitHeight: 0 }
        RowLayout {
            visible: !root.controller.choosing
            Layout.fillWidth: true
            StudyButton {
                text: root.controller.fullControl ? "Full control · on" : "Full control · off"
                checkable: true
                checked: root.controller.fullControl
                quiet: true
                unit: root.unit
                implicitHeight: 29 * root.unit
                Layout.fillWidth: true
                onClicked: root.controller.fullControl = !root.controller.fullControl
            }
        }
        RowLayout {
            Layout.fillWidth: true
            StudyButton {
                id: cancelControl
                objectName: "studyCancel"
                text: root.controller.choosing ? "Cancel" : "Pass"
                unit: root.unit
                Layout.fillWidth: true
                onClicked: {
                    if (root.controller.choosing) root.controller.cancel()
                    else root.controller.notice = "Priority passed in this preview."
                }
            }
            StudyButton {
                id: primaryControl
                objectName: "studyPrimary"
                visible: root.controller.stage !== "target"
                text: root.controller.stage === "payment" ? "Pay R"
                    : root.controller.stack.length ? "Resolve top" : "To combat  →"
                primary: true
                enabled: root.controller.stage !== "payment" || root.controller.canPay
                unit: root.unit
                Layout.fillWidth: true
                onClicked: {
                    if (root.controller.stage === "payment") root.controller.pay()
                    else if (root.controller.stack.length) root.controller.resolve()
                    else root.controller.notice = "Combat assignment is the next design slice."
                }
            }
        }
    }
}
