// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

Surface {
    id: root

    required property var tableController

    objectName: "rulesStateRail"
    Layout.minimumWidth: root.tableController.stateRailWidth
    Layout.preferredWidth: root.tableController.stateRailWidth
    Layout.maximumWidth: root.tableController.stateRailWidth
    Layout.fillHeight: true
    color: Theme.surfaceMuted
    radius: 0
    border.width: 0

    Rectangle {
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        width: Theme.size(2)
        color: Theme.borderStrong
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.size(6)
        spacing: Theme.size(5)

        Text {
            textFormat: Text.PlainText
            Layout.fillWidth: true
            Layout.preferredHeight: Theme.size(40)
            text: qsTr("Game state")
            color: Theme.text
            font.pixelSize: Theme.fontSize(13)
            font.weight: Font.DemiBold
            verticalAlignment: Text.AlignVCenter
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 1
            color: Theme.border
        }

        ListView {
            id: playerStateList
            objectName: "rulesPlayerStates"
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(contentHeight, Theme.size(210))
            model: root.tableController.rulesSession.players
            spacing: Theme.size(5)
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

            delegate: Surface {
                required property int seat
                required property string name
                required property string status
                required property int life
                required property string countersSummary
                required property string manaSummary

                width: ListView.view.width
                height: Theme.size(58)
                color: seat === root.tableController.rulesSession.prioritySeat
                       ? Theme.accentMuted : Theme.surface
                border.color:
                    seat === root.tableController.rulesSession.activeSeat
                    ? Theme.primary : Theme.border

                Column {
                    anchors.fill: parent
                    anchors.margins: Theme.size(7)
                    spacing: Theme.size(2)

                    Text {
                        textFormat: Text.PlainText
                        width: parent.width
                        text: name + " · " + qsTr("Life %1").arg(life)
                        color: Theme.text
                        font.pixelSize: Theme.fontSize(10)
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }

                    Text {
                        textFormat: Text.PlainText
                        width: parent.width
                        text: [status, countersSummary, manaSummary]
                              .filter(value => value.length > 0).join(" · ")
                        color: Theme.textMuted
                        font.pixelSize: Theme.fontSize(8)
                        elide: Text.ElideRight
                    }
                }
            }
        }

        Text {
            textFormat: Text.PlainText
            Layout.fillWidth: true
            text: qsTr("Zones")
            color: Theme.textSecondary
            font.pixelSize: Theme.fontSize(10)
            font.weight: Font.DemiBold
        }

        ListView {
            objectName: "rulesZoneStates"
            Layout.fillWidth: true
            Layout.fillHeight: true
            model: root.tableController.rulesSession.zones
            spacing: Theme.size(3)
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

            delegate: Rectangle {
                required property string zone
                required property int ownerSeat
                required property int count

                width: ListView.view.width
                height: Theme.size(30)
                radius: Theme.radiusSmall
                color: Theme.surfaceMuted

                Text {
                    textFormat: Text.PlainText
                    anchors.left: parent.left
                    anchors.right: zoneCountLabel.left
                    anchors.leftMargin: Theme.size(7)
                    anchors.rightMargin: Theme.size(4)
                    anchors.verticalCenter: parent.verticalCenter
                    text: qsTr("Seat %1 · %2")
                          .arg(ownerSeat + 1)
                          .arg(root.tableController.zoneLabel(zone))
                    color: Theme.textSecondary
                    font.pixelSize: Theme.fontSize(8)
                    elide: Text.ElideRight
                }

                Text {
                    textFormat: Text.PlainText
                    id: zoneCountLabel
                    anchors.right: parent.right
                    anchors.rightMargin: Theme.size(7)
                    anchors.verticalCenter: parent.verticalCenter
                    text: count
                    color: Theme.text
                    font.pixelSize: Theme.fontSize(9)
                    font.weight: Font.Bold
                }
            }
        }
    }
}
