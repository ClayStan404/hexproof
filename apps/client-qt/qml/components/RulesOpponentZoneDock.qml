// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

pragma ComponentBehavior: Bound

import QtQuick

Surface {
    id: root

    required property var tableController
    required property int ownerSeat
    readonly property var zoneKeys: [
        "library", "graveyard", "exile", "command"
    ]

    width: Math.min(Theme.size(230),
                    parent ? parent.width * 0.68 : Theme.size(230))
    height: Theme.size(78)
    visible: ownerSeat !== tableController.localSeat
    color: Theme.surfaceElevated
    radius: Theme.radiusMedium
    border.color: Theme.borderStrong

    Row {
        anchors.fill: parent
        anchors.margins: Theme.size(5)
        spacing: Theme.size(3)

        Repeater {
            model: root.zoneKeys

            delegate: Rectangle {
                id: zoneTile
                required property string modelData
                required property int index

                readonly property string zoneKey: modelData
                readonly property int cardCount:
                    root.tableController.rulesSession.zoneCount(
                        root.ownerSeat, zoneKey)

                width: (parent.width - Theme.size(9)) / 4
                height: parent.height
                radius: Theme.radiusSmall
                color: Theme.surfaceMuted
                border.width: 1
                border.color: Theme.border
                clip: true

                Image {
                    anchors.fill: parent
                    anchors.margins: Theme.size(2)
                    visible: zoneTile.zoneKey === "library"
                             && zoneTile.cardCount > 0
                    source: root.tableController.cardBackSource
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                }

                Repeater {
                    model: root.tableController.rulesSession.zoneCards

                    delegate: Image {
                        required property int index
                        required property string cardId
                        required property string zone
                        required property int zoneOwnerSeat
                        required property bool visibleIdentity
                        required property string name
                        required property string setCode
                        required property string collectorNumber
                        required property bool faceDown

                        objectName: "rulesOpponentZoneCard-"
                                    + root.ownerSeat + "-" + zoneTile.zoneKey
                                    + "-" + cardId
                        anchors.fill: parent
                        anchors.margins: Theme.size(2)
                        visible: zone === zoneTile.zoneKey
                                 && zoneOwnerSeat === root.ownerSeat
                        z: index
                        source: visibleIdentity && !faceDown
                                ? root.tableController.cardImage(
                                      name, setCode, collectorNumber)
                                : root.tableController.cardBackSource
                        fillMode: Image.PreserveAspectFit
                        asynchronous: true
                    }
                }

                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: Theme.size(3)
                    width: Math.min(parent.width - Theme.size(3),
                                    zoneLabel.implicitWidth + Theme.size(7))
                    height: Theme.size(17)
                    radius: height / 2
                    color: Theme.badgeBackground
                    border.width: 1
                    border.color: Theme.badgeBorder

                    Text {
                        textFormat: Text.PlainText
                        id: zoneLabel
                        anchors.fill: parent
                        anchors.leftMargin: Theme.size(3)
                        anchors.rightMargin: Theme.size(3)
                        text: root.tableController.zoneLabel(zoneTile.zoneKey)
                              + " " + zoneTile.cardCount
                        color: Theme.text
                        font.pixelSize: Theme.fontSize(7)
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        elide: Text.ElideRight
                    }
                }
            }
        }
    }
}
