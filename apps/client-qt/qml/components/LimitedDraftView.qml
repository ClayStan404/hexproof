// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

pragma ComponentBehavior: Bound
pragma Translator: "TournamentLobby"

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

Item {
    id: root

    required property var limitedModel
    required property var wsModel
    required property var cardCatalogModel
    property string selectedInstanceId: ""

    Component.onCompleted: root.cacheVisibleCards()

    Connections {
        target: root.limitedModel
        function onSnapshotChanged() { root.cacheVisibleCards() }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: Theme.size(10)

        RowLayout {
            Layout.fillWidth: true

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Theme.size(2)
                Text {
                    textFormat: Text.PlainText
                    text: qsTr("Draft pack %1 · %2")
                          .arg(root.limitedModel.packRound)
                          .arg(root.limitedModel.direction > 0
                               ? qsTr("pass left") : qsTr("pass right"))
                    color: Theme.text
                    font.pixelSize: Theme.fontSize(18)
                    font.weight: Font.DemiBold
                }
                Text {
                    textFormat: Text.PlainText
                    text: qsTr("Select one card, then confirm the irreversible pick.")
                    color: Theme.textMuted
                    font.pixelSize: Theme.fontSize(11)
                }
            }

            AppButton {
                variant: "primary"
                text: qsTr("Confirm pick")
                enabled: root.selectedInstanceId.length > 0
                onClicked: {
                    root.wsModel.pickLimitedCard(root.selectedInstanceId)
                    root.selectedInstanceId = ""
                }
            }
        }

        Surface {
            Layout.fillWidth: true
            Layout.fillHeight: true
            color: Theme.surfaceMuted

            Text {
                textFormat: Text.PlainText
                anchors.centerIn: parent
                visible: root.limitedModel.currentPack.length === 0
                text: root.limitedModel.participants.length > 0
                      ? qsTr("Waiting for the next pack…")
                      : qsTr("Draft progress is private to participants.")
                color: Theme.textMuted
                font.pixelSize: Theme.fontSize(13)
            }

            ScrollView {
                anchors.fill: parent
                anchors.margins: Theme.size(12)
                visible: root.limitedModel.currentPack.length > 0
                contentWidth: availableWidth
                ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

                Flow {
                    width: parent.width
                    spacing: Theme.size(10)

                    Repeater {
                        model: root.limitedModel.currentPack

                        delegate: Rectangle {
                            id: cardTile
                            required property var modelData
                            width: Theme.size(142)
                            height: Theme.size(204)
                            radius: Theme.radiusMedium
                            color: Theme.surfaceElevated
                            border.width: root.selectedInstanceId === modelData.instanceId ? 3 : 1
                            border.color: root.selectedInstanceId === modelData.instanceId
                                          ? Theme.primary : Theme.border
                            clip: true

                            Image {
                                anchors.fill: parent
                                anchors.margins: Theme.size(3)
                                asynchronous: true
                                fillMode: Image.PreserveAspectFit
                                source: root.cardImageSource(cardTile.modelData)
                            }

                            TapHandler {
                                onTapped: root.selectedInstanceId = cardTile.modelData.instanceId
                            }

                            ToolTip.visible: hover.hovered
                            ToolTip.text: cardTile.modelData.name + " · "
                                          + cardTile.modelData.setCode + " #"
                                          + cardTile.modelData.collectorNumber
                            HoverHandler { id: hover }
                        }
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.size(8)

            Text {
                textFormat: Text.PlainText
                Layout.fillWidth: true
                text: qsTr("Your pool: %1 cards").arg(root.limitedModel.pool.length)
                color: Theme.textSecondary
                font.pixelSize: Theme.fontSize(11)
            }

            Repeater {
                model: root.limitedModel.participants
                delegate: StatusPill {
                    required property var modelData
                    text: modelData.displayName + " · " + modelData.picked
                    statusColor: modelData.packCards > 0 ? Theme.accent : Theme.textMuted
                }
            }
        }
    }

    function cardImageSource(card) {
        if (!card || !card.name)
            return ""
        void root.cardCatalogModel.imageRevision
        return root.cardCatalogModel.tableImageSource(
                    card.name, card.setCode || "", card.collectorNumber || "")
    }

    function cacheVisibleCards() {
        if (root.cardCatalogModel
                && typeof root.cardCatalogModel.cacheCardsIncrementally
                   === "function") {
            root.cardCatalogModel.cacheCardsIncrementally(
                        root.limitedModel.currentPack || [])
        }
    }
}
