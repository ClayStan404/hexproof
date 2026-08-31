// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

Item {
    id: root

    required property var wsModel
    required property var cardCatalogModel
    required property var cardModel
    required property int promptId

    implicitHeight: cardList.count > 0 ? Theme.size(142) : Theme.size(48)

    function acknowledge() {
        wsModel.respondRulesPrompt(promptId, "$ack")
    }

    RowLayout {
        anchors.fill: parent
        spacing: Theme.size(12)

        ListView {
            id: cardList
            objectName: "revealCardList"

            Layout.fillWidth: true
            Layout.fillHeight: true
            orientation: ListView.Horizontal
            spacing: Theme.size(8)
            clip: true
            model: root.cardModel

            delegate: Rectangle {
                id: cardTile

                required property string cardId
                required property string name
                required property string setCode
                required property string collectorNumber
                required property bool token

                width: Theme.size(88)
                height: cardList.height
                radius: Theme.radiusSmall
                color: Theme.surfaceMuted
                border.width: 1
                border.color: Theme.border
                clip: true

                Image {
                    id: art

                    anchors.fill: parent
                    anchors.margins: Theme.size(3)
                    asynchronous: true
                    fillMode: Image.PreserveAspectFit
                    source: {
                        if (!root.cardCatalogModel || !cardTile.name
                                || typeof root.cardCatalogModel.tableImageSource
                                !== "function") {
                            return ""
                        }
                        void root.cardCatalogModel.imageRevision
                        return root.cardCatalogModel.tableImageSource(
                                    cardTile.name, cardTile.setCode,
                                    cardTile.collectorNumber)
                    }
                }

                Text {
                    textFormat: Text.PlainText
                    anchors.centerIn: parent
                    width: parent.width - Theme.size(10)
                    visible: art.status !== Image.Ready
                    text: cardTile.name.length > 0
                          ? cardTile.name : qsTr("Unknown card")
                    color: Theme.textSecondary
                    font.pixelSize: Theme.fontSize(9)
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                }

                HoverHandler { id: hover }
                ToolTip.visible: hover.hovered
                ToolTip.delay: 350
                ToolTip.text: cardTile.name + " · " + cardTile.setCode
                              + " #" + cardTile.collectorNumber
            }
        }

        Text {
            textFormat: Text.PlainText
            Layout.fillWidth: true
            visible: cardList.count === 0
            text: qsTr("No cards to display")
            color: Theme.textSecondary
            font.pixelSize: Theme.fontSize(10)
            horizontalAlignment: Text.AlignHCenter
        }

        AppButton {
            objectName: "acknowledgeRevealButton"
            Layout.preferredWidth: Theme.size(150)
            compact: true
            variant: "primary"
            text: qsTr("Continue")
            onClicked: root.acknowledge()
        }
    }
}
