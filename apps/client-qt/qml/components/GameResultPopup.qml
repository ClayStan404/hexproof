// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

AppPopup {
    id: root

    property string titleText: ""
    property string detailText: ""
    property string outcome: "neutral"
    property bool returnEnabled: true
    signal stayRequested()
    signal returnRequested()

    width: parent ? Math.min(Theme.size(520), Math.max(0, parent.width - Theme.size(48))) : 0
    padding: Theme.size(28)
    closePolicy: Popup.NoAutoClose

    background: Surface {
        elevated: true
        radius: Theme.radiusLarge
        color: Theme.useGlass ? Theme.tableHandFill : Theme.surfaceElevated
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
                enabled: root.returnEnabled
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
