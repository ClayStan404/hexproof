// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

Popup {
    id: root

    property var cardCatalogModel: null
    property string participantName: ""
    property var deck: ({})

    parent: Overlay.overlay
    x: Math.round((parent.width - width) / 2)
    y: Math.round((parent.height - height) / 2)
    width: Math.min(Theme.size(960), parent.width - Theme.size(48))
    height: Math.min(Theme.size(720), parent.height - Theme.size(56))
    padding: Theme.size(24)
    modal: true
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    Overlay.modal: Rectangle { color: "#A6050B09" }

    background: Rectangle {
        color: Theme.surfaceElevated
        radius: Theme.radiusLarge
        border.width: 1
        border.color: Theme.borderStrong
    }

    contentItem: ColumnLayout {
        spacing: Theme.size(14)

        RowLayout {
            Layout.fillWidth: true

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Theme.size(3)

                Text {
                    textFormat: Text.PlainText
                    Layout.fillWidth: true
                    text: qsTr("%1's decklist").arg(root.participantName)
                    color: Theme.text
                    font.pixelSize: Theme.fontSize(20)
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }

                Text {
                    textFormat: Text.PlainText
                    Layout.fillWidth: true
                    text: (root.deck.name || "") + root.commanderSummary()
                    color: Theme.textMuted
                    font.pixelSize: Theme.fontSize(12)
                    elide: Text.ElideRight
                }
            }

            AppButton {
                compact: true
                variant: "ghost"
                text: "×"
                accessibleName: qsTr("Close")
                Layout.preferredWidth: Theme.size(40)
                onClicked: root.close()
            }
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 1
            color: Theme.divider
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: Theme.size(14)

            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: Theme.size(8)

                Text {
                    textFormat: Text.PlainText
                    text: qsTr("Mainboard · %1").arg(
                          root.cardCount(root.deck.mainboard))
                    color: Theme.text
                    font.pixelSize: Theme.fontSize(14)
                    font.weight: Font.DemiBold
                }

                ListView {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    model: root.deck.mainboard || []
                    spacing: Theme.size(5)
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                    delegate: deckCardDelegate
                }
            }

            ColumnLayout {
                // Use the popup's explicit width rather than the RowLayout's
                // in-progress width. Referencing parent.width here feeds the
                // layout result back into its own size hint and makes Qt Quick
                // Layouts recursively rearrange the row.
                Layout.preferredWidth: root.availableWidth * 0.38
                Layout.fillHeight: true
                spacing: Theme.size(8)

                Text {
                    textFormat: Text.PlainText
                    text: qsTr("Sideboard · %1").arg(
                          root.cardCount(root.deck.sideboard))
                    color: Theme.text
                    font.pixelSize: Theme.fontSize(14)
                    font.weight: Font.DemiBold
                }

                ListView {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    model: root.deck.sideboard || []
                    spacing: Theme.size(5)
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                    delegate: deckCardDelegate
                }
            }
        }
    }

    Component {
        id: deckCardDelegate

        Surface {
            id: deckCardRow
            required property var modelData
            width: ListView.view.width
            height: Theme.size(58)
            color: Theme.surfaceMuted

            RowLayout {
                anchors.fill: parent
                anchors.margins: Theme.size(7)
                spacing: Theme.size(9)

                Rectangle {
                    Layout.preferredWidth: Theme.size(32)
                    Layout.preferredHeight: Theme.size(44)
                    radius: Theme.size(5)
                    color: Theme.primaryMuted
                    clip: true

                    Image {
                        id: deckCardImage
                        anchors.fill: parent
                        source: root.cardCatalogModel
                                ? root.cardCatalogModel.imageSource(
                                      deckCardRow.modelData.name,
                                      deckCardRow.modelData.setCode,
                                      deckCardRow.modelData.collectorNumber)
                                : ""
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        visible: status === Image.Ready
                    }

                    Text {
                        textFormat: Text.PlainText
                        anchors.centerIn: parent
                        text: deckCardRow.modelData.name
                              ? deckCardRow.modelData.name.charAt(0) : "?"
                        color: Theme.primary
                        font.pixelSize: Theme.fontSize(13)
                        font.weight: Font.Bold
                        visible: deckCardImage.status !== Image.Ready
                    }
                }

                Text {
                    textFormat: Text.PlainText
                    Layout.preferredWidth: Theme.size(30)
                    text: deckCardRow.modelData.count + "×"
                    color: Theme.accent
                    font.pixelSize: Theme.fontSize(12)
                    font.weight: Font.Bold
                    horizontalAlignment: Text.AlignRight
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Theme.size(2)

                    Text {
                        textFormat: Text.PlainText
                        Layout.fillWidth: true
                        text: deckCardRow.modelData.name
                        color: Theme.text
                        font.pixelSize: Theme.fontSize(12)
                        font.weight: Font.Medium
                        elide: Text.ElideRight
                    }

                    Text {
                        textFormat: Text.PlainText
                        Layout.fillWidth: true
                        text: deckCardRow.modelData.setCode.toUpperCase()
                              + " #" + deckCardRow.modelData.collectorNumber
                        color: Theme.textMuted
                        font.pixelSize: Theme.fontSize(9)
                        elide: Text.ElideRight
                    }
                }
            }
        }
    }

    function showDeck(displayName, value) {
        participantName = displayName
        deck = value || ({})
        open()
    }

    function cardCount(cards) {
        let count = 0
        const values = cards || []
        for (let index = 0; index < values.length; ++index)
            count += Number(values[index].count || 0)
        return count
    }

    function commanderSummary() {
        const commanders = deck && deck.commanders ? deck.commanders : []
        return commanders.length > 0
                ? " · " + qsTr("Commander: %1").arg(commanders.join(" / "))
                : ""
    }
}
