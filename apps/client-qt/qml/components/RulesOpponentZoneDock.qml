// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

pragma ComponentBehavior: Bound

import QtQuick

Surface {
    id: root

    required property var tableController
    required property int ownerSeat
    property bool compact: false
    readonly property var zoneKeys: [
        "library", "graveyard", "exile", "command"
    ]

    width: Math.min(Theme.size(compact ? 320 : 230),
                    parent ? parent.width * (compact ? 0.94 : 0.68)
                           : Theme.size(compact ? 320 : 230))
    height: Theme.size(compact ? 30 : 78)
    visible: ownerSeat !== tableController.localSeat
    color: Theme.surfaceElevated
    radius: Theme.radiusMedium
    border.color: Theme.borderStrong

    Row {
        id: zoneRow
        anchors.fill: parent
        anchors.margins: Theme.size(root.compact ? 3 : 5)
        spacing: Theme.size(3)

        Repeater {
            model: root.zoneKeys

            delegate: Rectangle {
                id: zoneTile
                required property string modelData
                required property int index

                readonly property string zoneKey: modelData
                objectName: "rulesOpponentZoneTile-" + root.ownerSeat + "-" + zoneKey
                readonly property int cardCount:
                    root.tableController.zoneCount(
                        root.ownerSeat, zoneKey)

                width: (zoneRow.width - Theme.size(9)) / 4
                height: zoneRow.height
                radius: Theme.radiusSmall
                color: Theme.surfaceMuted
                border.width: 1
                border.color: Theme.border
                clip: true

                Image {
                    anchors.fill: parent
                    anchors.margins: Theme.size(2)
                    visible: !root.compact && zoneTile.zoneKey === "library"
                             && zoneTile.cardCount > 0
                    source: root.tableController.cardBackSource
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                }

                Repeater {
                    model: root.tableController.rulesSession.zoneCards

                    delegate: Image {
                        id: zoneCard
                        required property int index
                        required property string cardId
                        required property string zone
                        required property int zoneOwnerSeat
                        required property bool visibleIdentity
                        required property string name
                        required property string setCode
                        required property string collectorNumber
                        required property bool faceDown

                        // Snapshot resets can destroy the dock before its nested images.
                        objectName: root && zoneTile
                                    ? "rulesOpponentZoneCard-" + root.ownerSeat
                                      + "-" + zoneTile.zoneKey + "-" + cardId
                                    : ""
                        anchors.fill: parent
                        anchors.margins: Theme.size(2)
                        visible: root && zoneTile && zone === zoneTile.zoneKey
                                 && zoneOwnerSeat === root.ownerSeat
                        z: index
                        source: !root || root.compact ? ""
                                : visibleIdentity && !faceDown
                                ? root.tableController.cardImage(
                                      name, setCode, collectorNumber)
                                : root.tableController.cardBackSource
                        fillMode: Image.PreserveAspectFit
                        asynchronous: true
                        Component.onDestruction: {
                            if (root && root.tableController
                                    && typeof root.tableController.endCardPreview === "function")
                                root.tableController.endCardPreview(zoneCard)
                        }
                        activeFocusOnTab: visible && visibleIdentity
                        onActiveFocusChanged: {
                            if (activeFocus && root && typeof root.tableController.previewCard === "function")
                                root.tableController.previewCard(cardId, zoneCard)
                            else if (!activeFocus && root && typeof root.tableController.endCardPreview === "function")
                                root.tableController.endCardPreview(zoneCard)
                        }
                        Keys.onReturnPressed: {
                            if (root && typeof root.tableController.openCardDetails === "function")
                                root.tableController.openCardDetails(cardId)
                        }
                        Keys.onSpacePressed: {
                            if (root && typeof root.tableController.openCardDetails === "function")
                                root.tableController.openCardDetails(cardId)
                        }
                        TapHandler {
                            enabled: zoneCard.visibleIdentity
                            gesturePolicy: TapHandler.WithinBounds
                            onTapped: {
                                if (root && typeof root.tableController.openCardDetails === "function")
                                    root.tableController.openCardDetails(zoneCard.cardId)
                            }
                        }
                        HoverHandler {
                            cursorShape: zoneCard.visibleIdentity ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onHoveredChanged: {
                                if (hovered && root && typeof root.tableController.previewCard === "function")
                                    root.tableController.previewCard(zoneCard.cardId, zoneCard)
                                else if (!hovered && root && typeof root.tableController.endCardPreview === "function")
                                    root.tableController.endCardPreview(zoneCard)
                            }
                        }
                    }
                }

                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: root.compact ? 0 : Theme.size(3)
                    width: root.compact ? parent.width : Math.min(parent.width - Theme.size(3),
                                    zoneLabelMetrics.width + Theme.size(7))
                    height: root.compact ? parent.height : Theme.size(17)
                    radius: root.compact ? Theme.radiusSmall : height / 2
                    color: root.compact ? "transparent" : Theme.badgeBackground
                    border.width: root.compact ? 0 : 1
                    border.color: Theme.badgeBorder

                    TextMetrics {
                        id: zoneLabelMetrics
                        text: zoneLabel.text
                        font: zoneLabel.font
                    }

                    Text {
                        textFormat: Text.PlainText
                        id: zoneLabel
                        visible: !root.compact
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

                    Row {
                        anchors.fill: parent
                        anchors.leftMargin: Theme.size(4)
                        anchors.rightMargin: Theme.size(4)
                        spacing: Theme.size(3)
                        visible: root.compact
                        Text {
                            objectName: "rulesOpponentZoneName-" + root.ownerSeat + "-" + zoneTile.zoneKey
                            textFormat: Text.PlainText
                            width: Math.max(0, parent.width - compactCount.implicitWidth - parent.spacing)
                            height: parent.height
                            text: zoneTile.zoneKey === "command" ? qsTr("Command")
                                  : root.tableController.zoneLabel(zoneTile.zoneKey)
                            color: Theme.textSecondary
                            font.pixelSize: Theme.fontSize(9)
                            elide: Text.ElideRight
                            verticalAlignment: Text.AlignVCenter
                        }
                        Text {
                            id: compactCount
                            objectName: "rulesOpponentZoneCount-" + root.ownerSeat + "-" + zoneTile.zoneKey
                            textFormat: Text.PlainText
                            height: parent.height
                            text: zoneTile.cardCount
                            color: Theme.text
                            font.pixelSize: Theme.fontSize(9)
                            font.weight: Font.DemiBold
                            verticalAlignment: Text.AlignVCenter
                        }
                    }
                }
            }
        }
    }
}
