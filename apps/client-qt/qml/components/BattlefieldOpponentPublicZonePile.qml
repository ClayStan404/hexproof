// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

pragma ComponentBehavior: Bound
pragma Translator: "BattlefieldView"

import QtQuick
import QtQuick.Layouts

Item {
    id: root

    required property var tableController
    required property var publicZoneBrowserPopup
    required property var seatData
    required property string zoneName
    required property string zoneLabel
    required property string objectNamePrefix
    property bool isOwn: false

    readonly property bool hasSeatData:
        seatData !== null && seatData !== undefined
        && seatData.seat !== undefined
    readonly property int seatIndex: hasSeatData ? seatData.seat : -1
    readonly property string seatDisplayName:
        hasSeatData && seatData.displayName !== undefined
        ? seatData.displayName : ""

    readonly property var topCard:
        hasSeatData
        ? tableController.zoneState.displayedPublicZoneTopCard(
              seatIndex, zoneName)
        : ({})

    Layout.minimumWidth: Theme.size(60)
    Layout.fillWidth: true
    Layout.fillHeight: true

    Rectangle {
        anchors.fill: parent
        color: "transparent"
        radius: Theme.radiusMedium
        clip: true
        border.width: zoneDrop.containsDrag
                      ? 2 : (zoneMouse.containsMouse ? 1 : 0)
        border.color: Theme.primary

        Image {
            anchors.fill: parent
            visible: !!root.topCard.id
            source: root.tableController.presentation.tableCardImageSource(
                        root.topCard)
            fillMode: Image.PreserveAspectFit
            asynchronous: true
            smooth: true
        }

        Rectangle {
            anchors.centerIn: parent
            width: Math.min(parent.width, parent.height * 63 / 88)
            height: width * 88 / 63
            visible: !root.topCard.id
            color: "transparent"
            radius: Theme.radiusSmall
            border.width: 1
            border.color: Theme.border
        }

        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: Theme.size(4)
            width: zoneCountLabel.implicitWidth + Theme.size(12)
            height: Theme.size(20)
            radius: height / 2
            color: Theme.badgeBackground
            border.width: 1
            border.color: Theme.badgeBorder

            Text {
                textFormat: Text.PlainText
                id: zoneCountLabel
                anchors.centerIn: parent
                text: root.zoneLabel + " "
                      + (root.hasSeatData
                         ? root.tableController.zoneState.zoneCardCount(
                               root.seatIndex, root.zoneName)
                         : 0)
                color: Theme.text
                font.pixelSize: Theme.fontSize(9)
                font.weight: Font.DemiBold
            }
        }
    }

    DropArea {
        id: zoneDrop
        objectName: !root.isOwn
                    ? root.objectNamePrefix + "DropArea" + root.seatIndex
                    : "inactiveOpponent" + root.objectNamePrefix
                      + "Drop"
        property var cardSource: null
        anchors.fill: parent
        z: 2
        enabled: root.hasSeatData && root.tableController.canAct
        keys: ["hexproof/card"]
        onEntered: function(drag) {
            cardSource = drag.source
        }
        onExited: cardSource = null
        onDropped: function(drop) {
            if (!root.hasSeatData)
                return
            root.tableController.cardMoveCommands.finishPublicZoneDrop(
                        zoneDrop, drop, root.zoneName, root.seatIndex)
        }
    }

    MouseArea {
        id: zoneMouse
        objectName: !root.isOwn
                    ? root.objectNamePrefix + "BrowserButton"
                      + root.seatIndex
                    : "inactiveOpponent" + root.objectNamePrefix
        anchors.fill: parent
        z: 3
        enabled: root.hasSeatData
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onEntered: root.tableController.presentation.inspectCard(
                       root.topCard, root)
        onExited: root.tableController.presentation.hideCardPreview(root)
        onClicked: root.publicZoneBrowserPopup.showZone(
                       root.seatDisplayName, root.seatIndex, root.zoneName)
    }
}
