// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

Surface {
    id: root

    required property var tableController
    readonly property var phaseSteps: [
        "untap", "upkeep", "draw", "main1", "begin_combat",
        "declare_attackers", "declare_blockers", "combat_damage",
        "end_combat", "main2", "end", "cleanup"
    ]

    objectName: "rulesActionRail"
    Layout.minimumWidth: root.tableController.actionRailWidth
    Layout.preferredWidth: root.tableController.actionRailWidth
    Layout.maximumWidth: root.tableController.actionRailWidth
    Layout.fillHeight: true
    color: Theme.surfaceMuted
    radius: 0
    border.width: 0

    Rectangle {
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        width: Theme.size(2)
        color: Theme.borderStrong
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.size(4)
        spacing: Theme.size(4)

        Text {
            textFormat: Text.PlainText
            Layout.fillWidth: true
            text: root.tableController.roomSession.roomName
                  || qsTr("Forge rules game")
            color: Theme.text
            font.pixelSize: Theme.fontSize(10)
            font.weight: Font.DemiBold
            elide: Text.ElideRight
            horizontalAlignment: Text.AlignHCenter
        }

        Text {
            textFormat: Text.PlainText
            Layout.fillWidth: true
            visible: root.tableController.roomSession.roomId.length > 0
            text: qsTr("ROOM CODE") + " · "
                  + root.tableController.roomSession.roomId
            color: Theme.textSecondary
            font.pixelSize: Theme.fontSize(9)
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
        }

        Text {
            textFormat: Text.PlainText
            Layout.fillWidth: true
            text: qsTr("Turn %1 · %2")
                  .arg(root.tableController.rulesSession.turn)
                  .arg(root.tableController.stepLabel(
                           root.tableController.rulesSession.step))
            color: Theme.textSecondary
            font.pixelSize: Theme.fontSize(9)
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
        }

        AppButton {
            objectName: "rulesReturnToRoomButton"
            Layout.fillWidth: true
            compact: true
            variant: "primary"
            visible: root.tableController.rulesSession.gameOver
            text: qsTr("Return to room")
            onClicked: root.tableController.wsModel.returnToRoom()
        }

        Repeater {
            model: root.tableController.rulesSession.players

            delegate: AppButton {
                required property int seat
                required property string status

                objectName: "rulesConcedeButton-" + seat
                Layout.fillWidth: true
                compact: true
                variant: "danger"
                visible: seat === root.tableController.localSeat
                         && status === "playing"
                         && !root.tableController.rulesSession.gameOver
                text: qsTr("Concede")
                onClicked: root.tableController.openConcedeConfirmation()
            }
        }

        AppButton {
            objectName: "rulesLeaveRoomButton"
            Layout.fillWidth: true
            compact: true
            variant: "secondary"
            text: qsTr("Leave room")
            onClicked: root.tableController.wsModel.leaveRoom()
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 1
            color: Theme.borderStrong
        }

        Text {
            textFormat: Text.PlainText
            Layout.fillWidth: true
            text: root.tableController.rulesSession.activeSeat >= 0
                  ? qsTr("Active · Seat %1").arg(
                        root.tableController.rulesSession.activeSeat + 1)
                  : qsTr("Waiting for Forge")
            color: Theme.primary
            font.pixelSize: Theme.fontSize(10)
            font.weight: Font.DemiBold
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
        }

        Text {
            textFormat: Text.PlainText
            Layout.fillWidth: true
            visible: root.tableController.rulesSession.prioritySeat >= 0
            text: qsTr("Priority · Seat %1").arg(
                      root.tableController.rulesSession.prioritySeat + 1)
            color: Theme.accent
            font.pixelSize: Theme.fontSize(9)
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 1
            color: Theme.divider
        }

        ScrollView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            contentWidth: availableWidth
            ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
            ScrollBar.vertical.policy: ScrollBar.AsNeeded

            Column {
                width: parent.width
                spacing: Theme.size(3)

                Repeater {
                    model: root.phaseSteps

                    delegate: Rectangle {
                        id: phaseItem
                        required property string modelData
                        required property int index

                        objectName: "rulesPhaseItem" + index
                        width: parent ? parent.width : 0
                        height: Theme.size(30)
                        radius: Theme.radiusSmall
                        color: root.tableController.rulesSession.step
                               === modelData ? Theme.primaryMuted : "transparent"
                        border.width: root.tableController.rulesSession.step
                                      === modelData ? 1 : 0
                        border.color: Theme.primary

                        Text {
                            textFormat: Text.PlainText
                            anchors.fill: parent
                            anchors.leftMargin: Theme.size(4)
                            anchors.rightMargin: Theme.size(4)
                            text: root.tableController.stepLabel(
                                      phaseItem.modelData)
                            color: root.tableController.rulesSession.step
                                   === phaseItem.modelData
                                   ? Theme.primary : Theme.textDisabled
                            font.pixelSize: Theme.fontSize(9)
                            font.weight: root.tableController.rulesSession.step
                                         === phaseItem.modelData
                                         ? Font.DemiBold : Font.Normal
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            elide: Text.ElideRight
                        }
                    }
                }
            }
        }

        Text {
            textFormat: Text.PlainText
            Layout.fillWidth: true
            text: qsTr("Forge controls phases and legal actions")
            color: Theme.textMuted
            font.pixelSize: Theme.fontSize(8)
            wrapMode: Text.WordWrap
            horizontalAlignment: Text.AlignHCenter
        }
    }
}
