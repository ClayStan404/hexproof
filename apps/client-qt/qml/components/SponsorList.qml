// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

ColumnLayout {
    id: root

    property bool compact: false
    property var newSponsorIds: []
    signal profileRequested(string url)

    spacing: Theme.size(compact ? 18 : 24)

    Repeater {
        model: SponsorCatalog.tiers

        delegate: ColumnLayout {
            id: tierGroup

            required property var modelData
            readonly property var members: SponsorCatalog.sponsorsForTier(modelData.id)

            objectName: "sponsorTier_" + modelData.id
            Layout.fillWidth: true
            spacing: Theme.size(root.compact ? 8 : 12)

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.size(12)

                Text {
                    objectName: "sponsorTierHeading_" + tierGroup.modelData.id
                    textFormat: Text.PlainText
                    Layout.fillWidth: true
                    text: tierGroup.modelData.name
                    color: Theme.accent
                    font.pixelSize: Theme.fontSize(root.compact ? 16 : 18)
                    font.weight: Font.DemiBold
                    wrapMode: Text.WordWrap
                }

                Text {
                    textFormat: Text.PlainText
                    text: tierGroup.members.length
                    color: Theme.textMuted
                    font.pixelSize: Theme.fontSize(12)
                }
            }

            Repeater {
                model: tierGroup.members

                delegate: Surface {
                    id: sponsorCard

                    required property var modelData
                    readonly property bool narrow: width < Theme.size(420)
                    readonly property bool featured: modelData.featured === true
                    readonly property string description: modelData.description || ""

                    objectName: "sponsorCard_" + modelData.name
                    Layout.fillWidth: true
                    implicitHeight: sponsorRow.implicitHeight
                                    + Theme.size(root.compact ? 20 : 28)
                    color: Theme.surfaceMuted
                    border.width: featured ? 0 : 1

                    SponsorHighlight {
                        anchors.fill: parent
                        visible: sponsorCard.featured
                    }

                    GridLayout {
                        id: sponsorRow
                        anchors.fill: parent
                        anchors.margins: Theme.size(root.compact ? 10 : 14)
                        columns: sponsorCard.narrow ? 2 : 3
                        columnSpacing: Theme.size(root.compact ? 12 : 16)
                        rowSpacing: Theme.size(6)

                        Rectangle {
                            Layout.row: 0
                            Layout.column: 0
                            Layout.preferredWidth: Theme.size(sponsorCard.featured
                                ? (root.compact ? 64 : 80) : (root.compact ? 48 : 64))
                            Layout.preferredHeight: Layout.preferredWidth
                            Layout.alignment: Qt.AlignVCenter
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
                                objectName: "sponsorAvatar_" + sponsorCard.modelData.name
                                anchors.fill: parent
                                source: sponsorCard.modelData.avatarSource
                                sourceSize: Qt.size(width * 2, height * 2)
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                cache: true
                                mipmap: true
                            }
                        }

                        ColumnLayout {
                            Layout.row: 0
                            Layout.column: 1
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            Layout.alignment: Qt.AlignVCenter
                            spacing: Theme.size(5)

                            Text {
                                textFormat: Text.PlainText
                                Layout.fillWidth: true
                                visible: root.newSponsorIds.indexOf(sponsorCard.modelData.id) >= 0
                                text: qsTr("New supporter")
                                color: Theme.primary
                                font.pixelSize: Theme.fontSize(12)
                                font.bold: true
                                wrapMode: Text.WordWrap
                            }

                            Text {
                                objectName: "sponsorRecognition_" + sponsorCard.modelData.name
                                textFormat: Text.PlainText
                                Layout.fillWidth: true
                                visible: sponsorCard.featured
                                text: "✦ " + qsTr("Special thanks")
                                color: "#EDD099"
                                font.pixelSize: Theme.fontSize(11)
                                font.weight: Font.DemiBold
                                wrapMode: Text.WordWrap
                            }

                            Text {
                                objectName: "sponsorName_" + sponsorCard.modelData.name
                                textFormat: Text.PlainText
                                Layout.fillWidth: true
                                text: sponsorCard.modelData.name
                                color: sponsorCard.featured ? "#FFF0D6" : Theme.text
                                font.pixelSize: Theme.fontSize(sponsorCard.featured
                                    ? (root.compact ? 19 : 24) : (root.compact ? 15 : 18))
                                font.weight: sponsorCard.featured ? Font.Bold : Font.DemiBold
                                wrapMode: Text.Wrap
                            }

                            Text {
                                objectName: "sponsorThanks_" + sponsorCard.modelData.name
                                textFormat: Text.PlainText
                                Layout.fillWidth: true
                                visible: sponsorCard.featured
                                text: qsTr("Thank you for your generous support.")
                                color: "#CCDBD7"
                                font.pixelSize: Theme.fontSize(root.compact ? 11 : 12)
                                wrapMode: Text.WordWrap
                            }
                        }

                        Text {
                            objectName: "sponsorDescription_" + sponsorCard.modelData.name
                            textFormat: Text.PlainText
                            Layout.row: 1
                            Layout.column: 0
                            Layout.columnSpan: sponsorRow.columns
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            Layout.topMargin: Theme.size(6)
                            visible: text.length > 0
                            text: sponsorCard.description
                            color: Theme.textSecondary
                            font.pixelSize: Theme.fontSize(root.compact ? 12 : 13)
                            lineHeight: 1.3
                            wrapMode: Text.Wrap
                        }

                        AppButton {
                            objectName: "sponsorProfileButton"
                            Layout.row: sponsorCard.narrow
                                ? (sponsorCard.description.length > 0 ? 2 : 1) : 0
                            Layout.column: sponsorCard.narrow ? 0 : 2
                            Layout.columnSpan: sponsorCard.narrow ? 2 : 1
                            Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter
                            visible: sponsorCard.modelData.profileUrl.length > 0
                            compact: true
                            variant: sponsorCard.featured ? "highlight" : "ghost"
                            text: qsTr("Visit profile")
                            onClicked: root.profileRequested(sponsorCard.modelData.profileUrl)
                        }
                    }
                }
            }

            Text {
                objectName: "sponsorTierEmpty_" + tierGroup.modelData.id
                textFormat: Text.PlainText
                Layout.fillWidth: true
                visible: tierGroup.members.length === 0
                text: qsTr("No sponsors in this tier yet")
                color: Theme.textMuted
                font.pixelSize: Theme.fontSize(12)
                wrapMode: Text.WordWrap
            }
        }
    }
}
