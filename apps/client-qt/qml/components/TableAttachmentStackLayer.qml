// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

pragma ComponentBehavior: Bound

import QtQuick

Item {
    id: root

    required property var tableController
    anchors.fill: parent
    z: 50

    Repeater {
        model: root.tableController.attachmentUi.crossLaneStacks

        delegate: Item {
            id: overlay
            required property var modelData
            readonly property var card: modelData.card ? modelData.card : ({})
            readonly property var targetPoint:
                root.tableController.battlefieldCardPoints[modelData.targetCardId]
            objectName: "attachmentOverlay" + modelData.sourceCardId
            visible: !!targetPoint
            width: root.tableController.battlefieldCardWidth
            height: root.tableController.battlefieldCardHeight
            x: targetPoint
               ? targetPoint.x - width / 2
                 + modelData.stackIndex * Theme.size(14)
               : 0
            y: targetPoint
               ? targetPoint.y - height / 2
                 + modelData.stackIndex * Theme.size(10)
               : 0
            z: 10 + modelData.stackIndex

            Item {
                id: overlayCard
                anchors.fill: parent
                rotation: root.tableController.gameValues.displayedTapped(overlay.card)
                          ? 90 : 0

                Image {
                    anchors.fill: parent
                    source: root.tableController.presentation.tableCardImageSource(
                                overlay.card)
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                }
                Rectangle {
                    anchors.fill: parent
                    visible: root.tableController.selection.cardSelected(
                                 overlay.modelData.sourceCardId)
                    color: "transparent"
                    border.width: Theme.size(3)
                    border.color: Theme.primary
                }
            }

            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                cursorShape: Qt.PointingHandCursor
                onEntered:
                    root.tableController.presentation.inspectCard(
                        overlay.card, overlay)
                onExited:
                    root.tableController.presentation.hideCardPreview(overlay)
                onClicked: function(mouse) {
                    if (mouse.button === Qt.RightButton) {
                        root.tableController.suppressBattlefieldAreaMenu = true
                        root.tableController.selection.selectCardForMenu(
                                    overlay.card, overlay.modelData.sourceSeat)
                        root.tableController.cardToolsMenu.x = overlay.x + mouse.x
                        root.tableController.cardToolsMenu.y = overlay.y + mouse.y
                        root.tableController.cardToolsMenu.open()
                        Qt.callLater(function() {
                            root.tableController.suppressBattlefieldAreaMenu = false
                        })
                        return
                    }
                    root.tableController.selection.selectCard(
                                overlay.card, overlay.modelData.sourceSeat,
                                (mouse.modifiers & Qt.ControlModifier)
                                || (mouse.modifiers & Qt.ShiftModifier))
                }
            }
        }
    }
}
