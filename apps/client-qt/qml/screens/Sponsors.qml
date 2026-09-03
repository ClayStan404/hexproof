// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import "../components"

Page {
    id: root

    readonly property var appWindow: ApplicationWindow.window

    background: AppBackground { }

    SponsorSupportPopup {
        id: supportPopup
        objectName: "sponsorSupportPopup"
        onAfdianRequested: url => Qt.openUrlExternally(url)
    }

    ScreenHeader {
        id: header
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.topMargin: Theme.size(22)
        anchors.leftMargin: Theme.pageMargin
        anchors.rightMargin: Theme.pageMargin
        title: qsTr("Sponsors & thanks")
        subtitle: qsTr("The people helping Hexproof stay online and keep improving")
        onBackRequested: root.appWindow.popScreen()
    }

    ScrollView {
        anchors.top: header.bottom
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.topMargin: Theme.size(14)
        anchors.bottomMargin: Theme.size(28)
        clip: true
        contentWidth: availableWidth
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

        ColumnLayout {
            width: Math.min(Theme.size(760), parent.width - Theme.size(72))
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Theme.size(16)

            Surface {
                Layout.fillWidth: true
                implicitHeight: thankYouContent.implicitHeight + Theme.size(48)
                elevated: true

                ColumnLayout {
                    id: thankYouContent
                    anchors.fill: parent
                    anchors.margins: Theme.size(24)
                    spacing: Theme.size(10)

                    Text {
                        textFormat: Text.PlainText
                        Layout.fillWidth: true
                        text: qsTr("Thank you for supporting Hexproof")
                        color: Theme.text
                        font.pixelSize: Theme.fontSize(22)
                        font.weight: Font.DemiBold
                        wrapMode: Text.WordWrap
                    }

                    Text {
                        textFormat: Text.PlainText
                        Layout.fillWidth: true
                        text: qsTr("Sponsor support helps cover public server costs and gives the project room to keep growing.")
                        color: Theme.textSecondary
                        font.pixelSize: Theme.fontSize(13)
                        lineHeight: 1.4
                        wrapMode: Text.WordWrap
                    }
                }
            }

            SponsorList {
                id: sponsorList
                objectName: "sponsorList"
                Layout.fillWidth: true
                onProfileRequested: url => Qt.openUrlExternally(url)
            }

            AppButton {
                objectName: "supportButton"
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: Theme.size(8)
                variant: "primary"
                text: qsTr("Sponsor Hexproof")
                onClicked: supportPopup.open()
            }

            Text {
                textFormat: Text.PlainText
                Layout.fillWidth: true
                Layout.topMargin: Theme.size(4)
                text: qsTr("With sincere thanks from the Hexproof project.")
                color: Theme.textMuted
                font.pixelSize: Theme.fontSize(12)
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
            }
        }
    }
}
