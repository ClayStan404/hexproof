// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

Popup {
    id: root

    property string titleText: ""
    property string detailText: ""
    property string outcome: "neutral"
    signal stayRequested()
    signal returnRequested()

    parent: Overlay.overlay
    x: Math.round((parent.width - width) / 2)
    y: Math.round((parent.height - height) / 2)
    width: Math.min(Theme.size(520), parent.width - Theme.size(48))
    padding: Theme.size(28)
    modal: true
    focus: true
    closePolicy: Popup.NoAutoClose

    Overlay.modal: Rectangle { color: "#B3050B09" }

    background: Rectangle {
        color: Theme.surfaceElevated
        radius: Theme.radiusLarge
        border.width: Theme.size(2)
        border.color: Theme.primary
    }

    contentItem: ColumnLayout {
        spacing: Theme.size(16)

        Text {
            textFormat: Text.PlainText
            objectName: "gameResultOutcome"
            Layout.fillWidth: true
            text: root.outcome === "win" ? "✓"
                  : (root.outcome === "loss" ? "×" : "—")
            color: root.outcome === "win" ? Theme.success
                   : (root.outcome === "loss" ? Theme.error
                      : Theme.textMuted)
            font.pixelSize: Theme.fontSize(34)
            font.weight: Font.Bold
            horizontalAlignment: Text.AlignHCenter
        }
        Text {
            textFormat: Text.PlainText
            objectName: "gameResultTitle"
            Layout.fillWidth: true
            text: root.titleText
            color: Theme.text
            font.pixelSize: Theme.fontSize(22)
            font.weight: Font.DemiBold
            wrapMode: Text.WordWrap
            horizontalAlignment: Text.AlignHCenter
        }
        Text {
            textFormat: Text.PlainText
            objectName: "gameResultDetail"
            Layout.fillWidth: true
            text: root.detailText
            color: Theme.textSecondary
            font.pixelSize: Theme.fontSize(13)
            wrapMode: Text.WordWrap
            horizontalAlignment: Text.AlignHCenter
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.size(10)

            AppButton {
                objectName: "stayAtTableButton"
                Layout.fillWidth: true
                compact: true
                variant: "secondary"
                text: qsTr("Stay for review")
                onClicked: {
                    root.close()
                    root.stayRequested()
                }
            }
            AppButton {
                objectName: "resultReturnToRoomButton"
                Layout.fillWidth: true
                compact: true
                variant: "primary"
                text: qsTr("Return to room")
                onClicked: {
                    root.close()
                    root.returnRequested()
                }
            }
        }
    }
}
