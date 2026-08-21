// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

Popup {
    id: root

    property string deckName: ""
    signal copyRequested()
    signal saveRequested()

    parent: Overlay.overlay
    x: Math.round((parent.width - width) / 2)
    y: Math.round((parent.height - height) / 2)
    width: Math.min(Theme.size(440), parent.width - Theme.size(48))
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
        spacing: Theme.size(18)

        Text {
            textFormat: Text.PlainText
            Layout.fillWidth: true
            text: root.deckName.length > 0
                  ? qsTr("Export %1").arg(root.deckName)
                  : qsTr("Export deck")
            color: Theme.text
            font.pixelSize: Theme.fontSize(20)
            font.weight: Font.DemiBold
            wrapMode: Text.WordWrap
        }

        Text {
            textFormat: Text.PlainText
            Layout.fillWidth: true
            text: qsTr("Copy the list or save a .txt file. The file uses explicit Deck, Sideboard, and Commander headings so it can be imported again.")
            color: Theme.textSecondary
            font.pixelSize: Theme.fontSize(14)
            lineHeight: 1.35
            wrapMode: Text.WordWrap
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: Theme.size(4)
            spacing: Theme.size(10)

            Item { Layout.fillWidth: true }

            AppButton {
                objectName: "cancelDeckExportButton"
                compact: true
                variant: "ghost"
                text: qsTr("Cancel")
                onClicked: root.close()
            }

            AppButton {
                objectName: "copyDeckExportButton"
                compact: true
                text: qsTr("Copy list")
                onClicked: {
                    root.close()
                    root.copyRequested()
                }
            }

            AppButton {
                objectName: "saveDeckExportButton"
                compact: true
                variant: "primary"
                text: qsTr("Save as file")
                onClicked: {
                    root.close()
                    root.saveRequested()
                }
            }
        }
    }
}
