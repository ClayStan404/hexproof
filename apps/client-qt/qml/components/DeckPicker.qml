// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

Popup {
    id: root

    property var decks: []
    property var deckLibraryModel: null
    property string requiredFormat: ""
    property string requiredTableMode: ""
    property bool allowMissingArt: false
    signal selected(string deckId, string deckName)
    signal openDeckLibraryRequested()

    parent: Overlay.overlay
    x: Math.round((parent.width - width) / 2)
    y: Math.round((parent.height - height) / 2)
    width: Math.min(Theme.size(720), parent.width - Theme.size(48))
    height: Math.min(Theme.size(620), parent.height - Theme.size(56))
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
                    text: qsTr("Select a deck")
                    color: Theme.text
                    font.pixelSize: Theme.fontSize(20)
                    font.weight: Font.DemiBold
                }

                Text {
                    textFormat: Text.PlainText
                    text: qsTr("Only decks matching this room's format can be selected.")
                    color: Theme.textSecondary
                    font.pixelSize: Theme.fontSize(12)
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

        Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Theme.divider }

        ListView {
            id: deckList
            objectName: "matchDeckOptions"
            Layout.fillWidth: true
            Layout.fillHeight: true
            model: root.decks
            spacing: Theme.size(9)
            clip: true
            visible: root.decks.length > 0
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

            delegate: Surface {
                id: deckRow
                required property var modelData
                required property int index
                objectName: "matchDeckOption" + index

                width: ListView.view.width
                height: Theme.size(88)
                radius: Theme.radiusMedium
                color: Theme.surfaceMuted
                border.color: modelData.ready ? Theme.borderStrong : Theme.border

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: Theme.size(16)
                    anchors.rightMargin: Theme.size(12)
                    spacing: Theme.size(14)

                    Rectangle {
                        Layout.preferredWidth: Theme.size(48)
                        Layout.preferredHeight: Theme.size(58)
                        radius: Theme.size(10)
                        color: root.requiredTableMode !== "modern" ? Theme.accentMuted : Theme.primaryMuted
                        border.width: 1
                        border.color: root.requiredTableMode !== "modern" ? "#695834" : "#2C654E"

                        Text {
                            textFormat: Text.PlainText
                            anchors.centerIn: parent
                            text: root.requiredFormat === "custom" ? "1"
                                  : (root.requiredFormat === "duel" ? "D"
                                     : (root.requiredFormat === "commander" ? "C"
                                        : I18n.formatLabel(root.requiredFormat).charAt(0)))
                            color: root.requiredTableMode !== "modern" ? Theme.accent : Theme.primary
                            font.pixelSize: Theme.fontSize(19)
                            font.weight: Font.Bold
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: Theme.size(4)

                        Text {
                            textFormat: Text.PlainText
                            Layout.fillWidth: true
                            text: deckRow.modelData.deckName
                            color: Theme.text
                            font.pixelSize: Theme.fontSize(15)
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                        }

                        Text {
                            textFormat: Text.PlainText
                            Layout.fillWidth: true
                            text: qsTr("%1 main · %2 side")
                                  .arg(deckRow.modelData.mainCount)
                                  .arg(deckRow.modelData.sideboardCount)
                            color: Theme.textMuted
                            font.pixelSize: Theme.fontSize(11)
                            elide: Text.ElideRight
                        }
                    }

                    StatusPill {
                        objectName: "deckAvailabilityStatus"
                        text: I18n.status(deckRow.modelData.status)
                        statusColor: deckRow.modelData.ready
                                     && deckRow.modelData.artReady !== false
                                     && deckRow.modelData.legalityVerified !== false
                                     && (!deckRow.modelData.legalityWarnings
                                         || deckRow.modelData.legalityWarnings.length === 0)
                                     ? Theme.success : Theme.warning
                    }

                    AppButton {
                        objectName: "selectMatchDeckButton"
                        compact: true
                        variant: "primary"
                        text: qsTr("Select")
                        enabled: deckRow.modelData.ready
                        onClicked: {
                            root.selected(deckRow.modelData.deckId, deckRow.modelData.deckName)
                            root.close()
                        }
                    }
                }
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.decks.length === 0

            ColumnLayout {
                anchors.centerIn: parent
                spacing: Theme.size(9)

                Text {
                    textFormat: Text.PlainText
                    Layout.alignment: Qt.AlignHCenter
                    text: "◇"
                    color: Theme.borderStrong
                    font.pixelSize: Theme.fontSize(38)
                }
                Text {
                    textFormat: Text.PlainText
                    Layout.alignment: Qt.AlignHCenter
                    text: qsTr("No matching local decks")
                    color: Theme.text
                    font.pixelSize: Theme.fontSize(15)
                    font.weight: Font.DemiBold
                }
                Text {
                    textFormat: Text.PlainText
                    Layout.alignment: Qt.AlignHCenter
                    text: qsTr("Import or edit a deck in the deck library first.")
                    color: Theme.textMuted
                    font.pixelSize: Theme.fontSize(12)
                }

                AppButton {
                    objectName: "openDeckLibraryButton"
                    Layout.alignment: Qt.AlignHCenter
                    variant: "primary"
                    text: qsTr("Open deck library")
                    leadingText: "◇"
                    onClicked: {
                        root.close()
                        root.openDeckLibraryRequested()
                    }
                }
            }
        }
    }

    function showForFormat(tableMode, deckFormat) {
        requiredTableMode = tableMode
        requiredFormat = deckFormat
        decks = deckLibraryModel
                ? deckLibraryModel.matchDecks(deckFormat, allowMissingArt) : []
        open()
    }
}
