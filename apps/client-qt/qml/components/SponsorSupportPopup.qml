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
    height: Math.min(Theme.size(540), parent.height - Theme.size(48))
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

        ScrollView {
            id: supportScroll
            objectName: "sponsorSupportScroll"
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumHeight: 0
            implicitHeight: supportDetails.implicitHeight
            contentWidth: availableWidth
            clip: true
            ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
            ColumnLayout {
                id: supportDetails
                width: supportScroll.availableWidth
                spacing: Theme.size(14)

                RowLayout {
                    id: qrCodes
                    Layout.fillWidth: true
                    Layout.topMargin: Theme.size(4)
                    spacing: Theme.size(24)

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: Theme.size(8)

                        Image {
                            objectName: "wechatPayQr"
                            Layout.alignment: Qt.AlignHCenter
                            Layout.preferredWidth: Math.min(Theme.size(200),
                                    (supportScroll.availableWidth - qrCodes.spacing) / 2,
                                    Math.max(1, supportScroll.availableHeight - Theme.size(50)))
                            Layout.preferredHeight: Layout.preferredWidth
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
                        Layout.fillWidth: true
                        spacing: Theme.size(8)

                        Image {
                            objectName: "alipayPayQr"
                            Layout.alignment: Qt.AlignHCenter
                            Layout.preferredWidth: Math.min(Theme.size(200),
                                    (supportScroll.availableWidth - qrCodes.spacing) / 2,
                                    Math.max(1, supportScroll.availableHeight - Theme.size(50)))
                            Layout.preferredHeight: Layout.preferredWidth
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

                Text {
                    textFormat: Text.PlainText
                    Layout.fillWidth: true
                    text: qsTr("Scan a code to sponsor with WeChat or Alipay, or become a recurring sponsor on Afdian.")
                    color: Theme.textSecondary
                    font.pixelSize: Theme.fontSize(12)
                    lineHeight: 1.4
                    wrapMode: Text.WordWrap
                }

            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.size(10)

            AppButton {
                objectName: "afdianButton"
                Layout.fillWidth: true
                variant: "primary"
                text: qsTr("Sponsor on Afdian")
                onClicked: root.afdianRequested(SponsorCatalog.afdianUrl)
            }

            AppButton {
                objectName: "closeSponsorSupportButton"
                variant: "ghost"
                text: qsTr("Close")
                onClicked: root.close()
            }
        }
    }
}
