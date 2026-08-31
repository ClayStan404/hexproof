// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

Surface {
    id: root

    required property var tableController

    objectName: "rulesSharedZoneRail"
    Layout.minimumWidth: root.tableController.sharedZoneRailWidth
    Layout.preferredWidth: root.tableController.sharedZoneRailWidth
    Layout.maximumWidth: root.tableController.sharedZoneRailWidth
    Layout.fillHeight: true
    color: Theme.surfaceMuted
    radius: 0
    border.width: 0

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.size(4)
        spacing: Theme.size(4)

        Text {
            textFormat: Text.PlainText
            Layout.fillWidth: true
            Layout.preferredHeight: Theme.size(40)
            text: qsTr("Stack")
            color: Theme.text
            font.pixelSize: Theme.fontSize(11)
            font.weight: Font.DemiBold
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 1
            color: Theme.border
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            Text {
                textFormat: Text.PlainText
                anchors.centerIn: parent
                width: parent.width - Theme.size(8)
                visible: stackList.count === 0
                text: qsTr("The stack is empty")
                color: Theme.textMuted
                font.pixelSize: Theme.fontSize(9)
                wrapMode: Text.WordWrap
                horizontalAlignment: Text.AlignHCenter
            }

            ListView {
                id: stackList
                objectName: "rulesStackCards"
                anchors.fill: parent
                model: root.tableController.rulesSession.stack
                spacing: -Theme.size(58)
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                delegate: RulesCardSurface {
                    required property int controllerSeat
                    required property int index

                    width: ListView.view.width
                    height: Math.round(width * 88 / 63)
                    z: index
                    cardCatalogModel: root.tableController.cardCatalogModel
                    cardBackSource: root.tableController.cardBackSource
                    visibleIdentity: true
                    tapped: false
                    faceDown: false
                    attacking: false
                    power: ""
                    toughness: ""
                    countersSummary: ""
                    rotateTapped: false

                    StatusPill {
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.top: parent.top
                        anchors.topMargin: Theme.size(5)
                        text: qsTr("Seat %1").arg(parent.controllerSeat + 1)
                        statusColor: Theme.accent
                    }
                }
            }
        }
    }
}
