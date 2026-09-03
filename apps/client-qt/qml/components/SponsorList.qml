// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Layouts

ColumnLayout {
    id: root

    property bool compact: false
    signal profileRequested(string url)

    spacing: Theme.size(compact ? 8 : 12)

    Repeater {
        model: SponsorCatalog.sponsors

        delegate: Surface {
            id: sponsorCard

            required property var modelData

            Layout.fillWidth: true
            implicitHeight: sponsorRow.implicitHeight
                            + Theme.size(root.compact ? 20 : 28)
            color: Theme.surfaceMuted

            RowLayout {
                id: sponsorRow
                anchors.fill: parent
                anchors.margins: Theme.size(root.compact ? 10 : 14)
                spacing: Theme.size(root.compact ? 12 : 16)

                Rectangle {
                    Layout.preferredWidth: Theme.size(root.compact ? 48 : 64)
                    Layout.preferredHeight: Layout.preferredWidth
                    radius: width / 2
                    color: Theme.primaryMuted
                    clip: true

                    Text {
                        textFormat: Text.PlainText
                        anchors.centerIn: parent
                        text: String(sponsorCard.modelData.name).charAt(0)
                        color: Theme.primary
                        font.pixelSize: Theme.fontSize(root.compact ? 18 : 22)
                        font.weight: Font.DemiBold
                    }

                    Image {
                        id: sponsorAvatar
                        anchors.fill: parent
                        source: sponsorCard.modelData.avatarSource
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        cache: true
                        mipmap: true
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Theme.size(3)

                    Text {
                        textFormat: Text.PlainText
                        Layout.fillWidth: true
                        text: sponsorCard.modelData.name
                        color: Theme.text
                        font.pixelSize: Theme.fontSize(root.compact ? 15 : 18)
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }

                    Text {
                        textFormat: Text.PlainText
                        Layout.fillWidth: true
                        text: qsTr("Hexproof sponsor")
                        color: Theme.textSecondary
                        font.pixelSize: Theme.fontSize(root.compact ? 11 : 12)
                    }
                }

                AppButton {
                    objectName: "sponsorProfileButton"
                    visible: sponsorCard.modelData.profileUrl.length > 0
                    compact: true
                    variant: "ghost"
                    text: qsTr("Visit profile")
                    onClicked: root.profileRequested(sponsorCard.modelData.profileUrl)
                }
            }
        }
    }
}
