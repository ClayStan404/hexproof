// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

Surface {
    id: root

    required property var tableController

    function relativePosition(seat, index, count) {
        const localSeat = root.tableController.localSeat
        if (localSeat < 0)
            return index
        return (seat - localSeat + count) % count
    }

    function laneRow(seat, index, count) {
        if (count <= 2) {
            if (root.tableController.localSeat < 0)
                return index
            return seat === root.tableController.localSeat ? 1 : 0
        }
        const relative = relativePosition(seat, index, count)
        return relative === 0 || relative === 3 ? 1 : 0
    }

    function laneColumn(seat, index, count) {
        if (count <= 2)
            return 0
        const relative = relativePosition(seat, index, count)
        return relative >= 2 ? 1 : 0
    }

    objectName: "rulesBattlefieldPanel"
    color: Theme.surfaceMuted
    radius: 0
    border.width: 0

    GridLayout {
        id: battlefieldGrid
        objectName: "rulesBattlefieldGrid"
        anchors.fill: parent
        anchors.margins: Theme.size(4)
        columns: playerRepeater.count > 2 ? 2 : 1
        rows: playerRepeater.count > 2 ? 2 : Math.max(1, playerRepeater.count)
        columnSpacing: Theme.size(6)
        rowSpacing: Theme.size(6)

        Repeater {
            id: playerRepeater
            model: root.tableController.rulesSession.players

            delegate: Surface {
                id: lane

                required property int index
                required property int seat
                required property string name
                required property string status
                required property int life
                required property string countersSummary
                required property string manaSummary

                readonly property bool isOwn:
                    seat === root.tableController.localSeat
                readonly property bool isActive:
                    seat === root.tableController.rulesSession.activeSeat
                readonly property bool hasPriority:
                    seat === root.tableController.rulesSession.prioritySeat

                objectName: "rulesBattlefieldLane" + seat
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.row: root.laneRow(
                                seat, index, playerRepeater.count)
                Layout.column: root.laneColumn(
                                   seat, index, playerRepeater.count)
                color: isOwn ? Theme.primaryMuted : Theme.surfaceHover
                radius: 0
                border.width: isActive ? Theme.size(2) : 1
                border.color: isActive ? Theme.primary : Theme.border

                DropArea {
                    id: handCardDrop

                    objectName: "rulesBattlefieldDropArea" + lane.seat
                    anchors.fill: parent
                    z: 15
                    enabled: lane.isOwn
                    keys: ["hexproof/rules-card"]

                    onDropped: function(drop) {
                        const source = drop.source
                        if (!root.tableController.playDraggedHandCardSource(
                                    source)) {
                            drop.accepted = false
                            return
                        }
                        drop.acceptProposedAction()
                    }
                }

                Rectangle {
                    anchors.fill: parent
                    z: 16
                    visible: handCardDrop.containsDrag
                    color: "transparent"
                    border.width: Theme.size(2)
                    border.color: Theme.primary
                }

                Text {
                    textFormat: Text.PlainText
                    anchors.left: parent.left
                    anchors.right: laneBadges.left
                    anchors.top: parent.top
                    anchors.leftMargin: Theme.size(9)
                    anchors.rightMargin: Theme.size(8)
                    anchors.topMargin: Theme.size(7)
                    height: Theme.size(24)
                    z: 20
                    text: lane.name + " · " + qsTr("Life %1").arg(lane.life)
                          + " · " + root.tableController.rulesSession.zoneCount(
                              lane.seat, "hand") + qsTr("H")
                          + " / " + root.tableController.rulesSession.zoneCount(
                              lane.seat, "library") + qsTr("D")
                    color: lane.isOwn ? Theme.primary : Theme.text
                    font.pixelSize: Theme.fontSize(11)
                    font.weight: Font.Bold
                    elide: Text.ElideRight
                    verticalAlignment: Text.AlignVCenter
                }

                RowLayout {
                    id: laneBadges
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: Theme.size(7)
                    spacing: Theme.size(5)
                    z: 20

                    StatusPill {
                        visible: lane.isActive
                        text: lane.isOwn ? qsTr("Your turn")
                                         : qsTr("Current turn")
                        statusColor: Theme.primary
                    }

                    StatusPill {
                        visible: lane.hasPriority
                        text: qsTr("Priority")
                        statusColor: Theme.accent
                    }
                }

                Text {
                    textFormat: Text.PlainText
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.margins: Theme.size(8)
                    z: 20
                    text: [lane.status, lane.countersSummary, lane.manaSummary]
                          .filter(value => value.length > 0).join(" · ")
                    color: Theme.textMuted
                    font.pixelSize: Theme.fontSize(9)
                    elide: Text.ElideRight
                }

                RulesOpponentZoneDock {
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.rightMargin: Theme.size(7)
                    anchors.bottomMargin: Theme.size(27)
                    z: 30
                    tableController: root.tableController
                    ownerSeat: lane.seat
                }

                Text {
                    textFormat: Text.PlainText
                    anchors.centerIn: parent
                    visible: root.tableController.rulesSession.zoneCount(
                                 lane.seat, "battlefield") === 0
                    text: lane.isOwn
                          && root.tableController.rulesSession.promptPending
                          && root.tableController.rulesSession.promptKind
                             === "chooseAction"
                          ? qsTr("Drag a legal card from your hand here")
                          : qsTr("No permanents on the battlefield")
                    color: Theme.textMuted
                    font.pixelSize: Theme.fontSize(10)
                }

                Flickable {
                    anchors.fill: parent
                    anchors.topMargin: Theme.size(34)
                    anchors.bottomMargin: Theme.size(26)
                    anchors.leftMargin: Theme.size(8)
                    anchors.rightMargin: Theme.size(8)
                    contentWidth: width
                    contentHeight: battlefieldCards.implicitHeight
                    clip: true

                    Flow {
                        id: battlefieldCards
                        width: parent.width
                        spacing: Theme.size(8)

                        Repeater {
                            model: root.tableController.rulesSession
                                       .battlefieldCards

                            delegate: RulesCardSurface {
                                required property string cardId
                                required property int controllerSeat

                                objectName: "rulesBattlefieldCard-" + lane.seat
                                            + "-" + cardId
                                visible: controllerSeat === lane.seat
                                width: visible
                                       ? root.tableController.battlefieldCardWidth : 0
                                height: visible
                                        ? root.tableController.battlefieldCardHeight : 0
                                cardCatalogModel:
                                    root.tableController.cardCatalogModel
                                cardBackSource:
                                    root.tableController.cardBackSource
                            }
                        }
                    }
                }
            }
        }
    }
}
