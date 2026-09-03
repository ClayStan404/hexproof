// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

Popup {
    id: root

    signal afdianRequested(string url)

    parent: Overlay.overlay
    x: Math.round((parent.width - width) / 2)
    y: Math.round((parent.height - height) / 2)
    width: Math.min(Theme.size(500), parent.width - Theme.size(48))
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

        Text {
            textFormat: Text.PlainText
            Layout.fillWidth: true
            text: qsTr("Support Hexproof")
            color: Theme.text
            font.pixelSize: Theme.fontSize(19)
            font.weight: Font.DemiBold
        }

        Text {
            textFormat: Text.PlainText
            Layout.fillWidth: true
            text: qsTr("Scan a code to sponsor with WeChat or Alipay, or become a recurring sponsor on Afdian.")
            color: Theme.textSecondary
            font.pixelSize: Theme.fontSize(12)
            lineHeight: 1.4
            wrapMode: Text.WordWrap
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: Theme.size(4)
            spacing: Theme.size(24)

            ColumnLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: Theme.size(8)

                Image {
                    objectName: "wechatPayQr"
                    Layout.preferredWidth: Theme.size(200)
                    Layout.preferredHeight: Theme.size(200)
                    source: SponsorCatalog.wechatPayQrSource
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                    cache: true
                    mipmap: true
                }

                Text {
                    textFormat: Text.PlainText
                    Layout.alignment: Qt.AlignHCenter
                    text: qsTr("WeChat")
                    color: Theme.textSecondary
                    font.pixelSize: Theme.fontSize(13)
                }
            }

            ColumnLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: Theme.size(8)

                Image {
                    objectName: "alipayPayQr"
                    Layout.preferredWidth: Theme.size(200)
                    Layout.preferredHeight: Theme.size(200)
                    source: SponsorCatalog.alipayPayQrSource
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                    cache: true
                    mipmap: true
                }

                Text {
                    textFormat: Text.PlainText
                    Layout.alignment: Qt.AlignHCenter
                    text: qsTr("Alipay")
                    color: Theme.textSecondary
                    font.pixelSize: Theme.fontSize(13)
                }
            }
        }

        AppButton {
            objectName: "afdianButton"
            Layout.fillWidth: true
            variant: "primary"
            text: qsTr("Sponsor on Afdian")
            onClicked: root.afdianRequested(SponsorCatalog.afdianUrl)
        }

        AppButton {
            Layout.fillWidth: true
            Layout.topMargin: Theme.size(2)
            variant: "ghost"
            text: qsTr("Close")
            onClicked: root.close()
        }
    }
}
