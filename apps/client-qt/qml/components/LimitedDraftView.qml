// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

pragma ComponentBehavior: Bound
pragma Translator: "TournamentLobby"

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

Item {
    id: root

    required property var limitedModel
    required property var tournamentModel
    required property var wsModel
    required property var cardCatalogModel
    property string selectedInstanceId: ""
    readonly property string participantId: tournamentModel.participantId || ""

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
                    text: root.participantId.length > 0
                          ? qsTr("Choose one card. The rest of this pack goes to %1.")
                            .arg(seatMap.outgoingName)
                          : qsTr("Draft progress is private to participants.")
                    color: Theme.textMuted
                    font.pixelSize: Theme.fontSize(11)
                }
            }

            AppButton {
                objectName: "limitedConfirmPickButton"
                variant: "primary"
                text: qsTr("Confirm pick")
                enabled: root.selectedInstanceId.length > 0
                onClicked: {
                    root.wsModel.pickLimitedCard(root.selectedInstanceId)
                    root.selectedInstanceId = ""
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: Theme.size(12)

            Surface {
                Layout.fillWidth: true
                Layout.fillHeight: true
                color: Theme.surfaceMuted

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: Theme.size(12)
                    spacing: Theme.size(8)

                    RowLayout {
                        Layout.fillWidth: true

                        Text {
                            textFormat: Text.PlainText
                            Layout.fillWidth: true
                            text: qsTr("Current pack · %1 cards")
                                  .arg(root.limitedModel.currentPack.length)
                            color: Theme.text
                            font.pixelSize: Theme.fontSize(14)
                            font.weight: Font.DemiBold
                        }

                        Text {
                            textFormat: Text.PlainText
                            visible: root.limitedModel.currentPack.length > 0
                            text: qsTr("Click a card to select it")
                            color: Theme.textMuted
                            font.pixelSize: Theme.fontSize(10)
                        }
                    }

                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true

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
                            visible: root.limitedModel.currentPack.length > 0
                            contentWidth: availableWidth
                            ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

                            Flow {
                                objectName: "limitedCurrentPackGrid"
                                width: parent.width
                                spacing: Theme.size(10)

                                Repeater {
                                    model: root.limitedModel.currentPack

                                    delegate: LimitedCardTile {
                                        required property var modelData
                                        width: Theme.size(142)
                                        height: Theme.size(204)
                                        card: modelData
                                        catalogModel: root.cardCatalogModel
                                        emphasized: root.selectedInstanceId
                                                    === modelData.instanceId
                                        actionText: emphasized ? "✓" : "+"
                                        onActivated: root.selectedInstanceId = modelData.instanceId
                                    }
                                }
                            }
                        }
                    }
                }
            }

            ColumnLayout {
                Layout.preferredWidth: Math.min(Theme.size(370), root.width * 0.34)
                Layout.minimumWidth: Theme.size(300)
                Layout.fillHeight: true
                spacing: Theme.size(12)

                LimitedDraftSeatMap {
                    id: seatMap
                    objectName: "limitedDraftSeatMap"
                    Layout.fillWidth: true
                    participants: root.limitedModel.participants
                    participantId: root.participantId
                    direction: root.limitedModel.direction
                }

                Surface {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    color: Theme.surfaceMuted

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: Theme.size(12)
                        spacing: Theme.size(8)

                        RowLayout {
                            Layout.fillWidth: true

                            Text {
                                textFormat: Text.PlainText
                                Layout.fillWidth: true
                                text: qsTr("Your picks")
                                color: Theme.text
                                font.pixelSize: Theme.fontSize(14)
                                font.weight: Font.DemiBold
                            }

                            StatusPill {
                                objectName: "limitedPickedCount"
                                text: String(root.limitedModel.pool.length)
                                statusColor: Theme.primary
                            }
                        }

                        Text {
                            textFormat: Text.PlainText
                            Layout.fillWidth: true
                            visible: root.limitedModel.pool.length === 0
                            text: qsTr("Cards you draft will remain visible here.")
                            color: Theme.textMuted
                            font.pixelSize: Theme.fontSize(10)
                            wrapMode: Text.WordWrap
                        }

                        ScrollView {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            visible: root.limitedModel.pool.length > 0
                            contentWidth: availableWidth
                            ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

                            Flow {
                                objectName: "limitedPickedCardGrid"
                                width: parent.width
                                spacing: Theme.size(7)

                                Repeater {
                                    model: root.limitedModel.pool

                                    delegate: LimitedCardTile {
                                        required property var modelData
                                        width: Theme.size(92)
                                        height: Theme.size(132)
                                        card: modelData
                                        catalogModel: root.cardCatalogModel
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    function cacheVisibleCards() {
        if (!root.cardCatalogModel
                || typeof root.cardCatalogModel.cacheCardsIncrementally
                   !== "function") {
            return
        }
        root.cardCatalogModel.cacheCardsIncrementally(
                    (root.limitedModel.currentPack || [])
                    .concat(root.limitedModel.pool || []))
    }
}
