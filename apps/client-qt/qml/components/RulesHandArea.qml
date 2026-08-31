// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

Surface {
    id: root

    required property var tableController
    readonly property var zoneKeys: [
        "library", "graveyard", "exile", "command"
    ]

    function zoneTitle(zone) {
        return root.tableController.zoneLabel(zone)
    }

    objectName: "rulesHandArea"
    Layout.fillWidth: true
    Layout.preferredHeight: root.tableController.handAreaHeight
    color: Theme.surfaceMuted
    radius: 0
    border.width: 0

    RowLayout {
        anchors.fill: parent
        anchors.margins: Theme.size(4)
        spacing: Theme.size(5)

        Surface {
            objectName: "rulesOwnHand"
            Layout.fillWidth: true
            Layout.fillHeight: true
            color: Theme.backgroundRaised
            radius: 0

            Text {
                textFormat: Text.PlainText
                anchors.centerIn: parent
                visible: root.tableController.localSeat < 0
                text: qsTr("Hands are hidden from spectators in this room")
                color: Theme.textMuted
                font.pixelSize: Theme.fontSize(11)
            }

            Text {
                textFormat: Text.PlainText
                anchors.centerIn: parent
                visible: root.tableController.localSeat >= 0
                         && root.tableController.rulesSession.zoneCount(
                             root.tableController.localSeat, "hand") === 0
                text: qsTr("Hand is empty")
                color: Theme.textMuted
                font.pixelSize: Theme.fontSize(11)
            }

            Flickable {
                anchors.fill: parent
                anchors.margins: Theme.size(7)
                contentWidth: handCards.implicitWidth
                contentHeight: height
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                Row {
                    id: handCards
                    height: parent.height
                    spacing: Theme.size(6)

                    Repeater {
                        model: root.tableController.rulesSession.zoneCards

                        delegate: Item {
                            id: handCard

                            required property string cardId
                            required property string zone
                            required property int zoneOwnerSeat
                            required property bool visibleIdentity
                            required property string name
                            required property string setCode
                            required property string collectorNumber
                            required property bool tapped
                            required property bool faceDown
                            required property bool attacking
                            required property string power
                            required property string toughness
                            required property string countersSummary

                            readonly property bool canPlay:
                                root.tableController.canDragHandCard(cardId)

                            objectName: "rulesHandCard-" + cardId
                            visible: zone === "hand"
                                     && zoneOwnerSeat
                                        === root.tableController.localSeat
                            width: visible ? root.tableController.handCardWidth : 0
                            height: visible ? handCards.height : 0
                            opacity: handDrag.drag.active ? 0.45 : 1

                            RulesCardSurface {
                                anchors.centerIn: parent
                                width: root.tableController.handCardWidth
                                height: root.tableController.handCardHeight
                                cardCatalogModel:
                                    root.tableController.cardCatalogModel
                                cardBackSource:
                                    root.tableController.cardBackSource
                                visibleIdentity: handCard.visibleIdentity
                                name: handCard.name
                                setCode: handCard.setCode
                                collectorNumber: handCard.collectorNumber
                                tapped: handCard.tapped
                                faceDown: handCard.faceDown
                                attacking: handCard.attacking
                                power: handCard.power
                                toughness: handCard.toughness
                                countersSummary: handCard.countersSummary
                                rotateTapped: false
                            }

                            RulesCardSurface {
                                id: dragCard

                                readonly property string cardId: handCard.cardId

                                objectName: "rulesHandDragPreview-"
                                            + handCard.cardId
                                parent: root.tableController
                                width: root.tableController.handCardWidth
                                height: root.tableController.handCardHeight
                                visible: handDrag.drag.active
                                z: 1000
                                scale: 1.045
                                opacity: 0.94
                                cardCatalogModel:
                                    root.tableController.cardCatalogModel
                                cardBackSource:
                                    root.tableController.cardBackSource
                                visibleIdentity: handCard.visibleIdentity
                                name: handCard.name
                                setCode: handCard.setCode
                                collectorNumber: handCard.collectorNumber
                                tapped: handCard.tapped
                                faceDown: handCard.faceDown
                                attacking: handCard.attacking
                                power: handCard.power
                                toughness: handCard.toughness
                                countersSummary: handCard.countersSummary
                                rotateTapped: false

                                Drag.active: handDrag.drag.active
                                Drag.source: dragCard
                                Drag.keys: ["hexproof/rules-card"]
                                Drag.hotSpot.x: width / 2
                                Drag.hotSpot.y: height / 2
                            }

                            MouseArea {
                                id: handDrag

                                objectName: "rulesHandCardDrag-" + handCard.cardId
                                anchors.fill: parent
                                enabled: handCard.canPlay
                                cursorShape: drag.active
                                             ? Qt.ClosedHandCursor
                                             : Qt.OpenHandCursor
                                drag.target: handCard.canPlay ? dragCard : null
                                drag.threshold: Theme.size(5)
                                preventStealing: true
                                onPressed: {
                                    const point = handCard.mapToItem(
                                                    root.tableController,
                                                    0,
                                                    (handCard.height
                                                     - dragCard.height) / 2)
                                    dragCard.x = point.x
                                    dragCard.y = point.y
                                }
                                onReleased: dragCard.Drag.drop()
                                onCanceled: dragCard.Drag.cancel()
                            }
                        }
                    }
                }
            }
        }

        Surface {
            objectName: "rulesOwnZoneDock"
            visible: root.tableController.localSeat >= 0
            Layout.minimumWidth: root.tableController.zoneDockWidth
            Layout.preferredWidth: root.tableController.zoneDockWidth
            Layout.maximumWidth: root.tableController.zoneDockWidth
            Layout.fillHeight: true
            color: Theme.surfaceElevated

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: Theme.size(7)
                spacing: Theme.size(4)

                Text {
                    textFormat: Text.PlainText
                    Layout.fillWidth: true
                    text: qsTr("Your zones")
                    color: Theme.text
                    font.pixelSize: Theme.fontSize(10)
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: Theme.size(4)

                    Repeater {
                        model: root.zoneKeys

                        delegate: Rectangle {
                            id: zoneTile
                            required property string modelData
                            required property int index

                            readonly property string zoneKey: modelData
                            readonly property int cardCount:
                                root.tableController.localSeat >= 0
                                ? root.tableController.rulesSession.zoneCount(
                                      root.tableController.localSeat, zoneKey)
                                : 0

                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            Layout.minimumWidth: Theme.size(48)
                            radius: Theme.radiusMedium
                            color: Theme.surfaceMuted
                            border.width: 1
                            border.color: Theme.border
                            clip: true

                            Image {
                                anchors.fill: parent
                                anchors.margins: Theme.size(3)
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
                                    required property string zone
                                    required property int zoneOwnerSeat
                                    required property bool visibleIdentity
                                    required property string name
                                    required property string setCode
                                    required property string collectorNumber
                                    required property bool faceDown

                                    anchors.fill: parent
                                    anchors.margins: Theme.size(3)
                                    visible: zone === zoneTile.zoneKey
                                             && zoneOwnerSeat
                                                === root.tableController.localSeat
                                    z: index
                                    source: visibleIdentity && !faceDown
                                            ? root.tableController.cardImage(
                                                  name, setCode,
                                                  collectorNumber)
                                            : root.tableController.cardBackSource
                                    fillMode: Image.PreserveAspectFit
                                    asynchronous: true
                                }
                            }

                            Rectangle {
                                anchors.horizontalCenter: parent.horizontalCenter
                                anchors.bottom: parent.bottom
                                anchors.bottomMargin: Theme.size(4)
                                width: Math.min(parent.width - Theme.size(4),
                                                zoneLabel.implicitWidth
                                                + Theme.size(10))
                                height: Theme.size(20)
                                radius: height / 2
                                color: Theme.badgeBackground
                                border.width: 1
                                border.color: Theme.badgeBorder

                                Text {
                                    textFormat: Text.PlainText
                                    id: zoneLabel
                                    anchors.fill: parent
                                    anchors.leftMargin: Theme.size(4)
                                    anchors.rightMargin: Theme.size(4)
                                    text: root.zoneTitle(zoneTile.zoneKey)
                                          + " " + zoneTile.cardCount
                                    color: Theme.text
                                    font.pixelSize: Theme.fontSize(8)
                                    font.weight: Font.DemiBold
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                    elide: Text.ElideRight
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
