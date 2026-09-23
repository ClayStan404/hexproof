// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import "../components"

Page {
    id: root
    readonly property var appWindow: ApplicationWindow.window
    property var contentModel: publicContent
    property bool showHistory: false
    property string expandedId: ""
    readonly property var entries: showHistory ? contentModel.historicalAnnouncements
                                              : contentModel.currentAnnouncements

    Component.onCompleted: contentModel.refresh()
    background: AppBackground { }

    ScreenHeader {
        id: header
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.topMargin: Theme.size(22)
        anchors.leftMargin: Theme.pageMargin
        anchors.rightMargin: Theme.pageMargin
        title: qsTr("Announcements")
        subtitle: qsTr("Project news, maintenance and past announcements")
        onBackRequested: root.appWindow.popScreen()
    }

    ScrollView {
        id: scroll
        objectName: "announcementsScroll"
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
            width: Math.min(Theme.size(850), scroll.availableWidth - Theme.pageMargin * 2)
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Theme.size(16)

            ContentRefreshBar {
                Layout.fillWidth: true
                contentModel: root.contentModel
            }

            Flow {
                Layout.fillWidth: true
                spacing: Theme.size(8)

                AppButton {
                    objectName: "currentAnnouncementsButton"
                    text: qsTr("Current")
                    variant: root.showHistory ? "secondary" : "primary"
                    compact: true
                    onClicked: root.showHistory = false
                }
                AppButton {
                    objectName: "historicalAnnouncementsButton"
                    text: qsTr("History")
                    variant: root.showHistory ? "primary" : "secondary"
                    compact: true
                    onClicked: root.showHistory = true
                }
                AppButton {
                    objectName: "markAnnouncementsReadButton"
                    text: qsTr("Mark all as read")
                    compact: true
                    enabled: root.contentModel.unreadCount > 0
                    onClicked: root.contentModel.markAllRead()
                }
            }

            Text {
                textFormat: Text.PlainText
                Layout.fillWidth: true
                visible: root.entries.length === 0
                text: root.showHistory ? qsTr("No past announcements yet.")
                                       : qsTr("No current announcements.")
                color: Theme.textMuted
                font.pixelSize: Theme.fontSize(14)
                wrapMode: Text.WordWrap
            }

            Repeater {
                model: root.entries
                delegate: Surface {
                    id: card
                    required property var modelData
                    objectName: "announcement_" + modelData.id
                    Layout.fillWidth: true
                    implicitHeight: content.implicitHeight + Theme.size(36)
                    border.color: modelData.unread ? Theme.primary : Theme.border

                    ColumnLayout {
                        id: content
                        anchors.fill: parent
                        anchors.margins: Theme.size(18)
                        spacing: Theme.size(10)

                        Text {
                            textFormat: Text.PlainText
                            Layout.fillWidth: true
                            text: (card.modelData.unread ? qsTr("Unread") + " · " : "")
                                  + (card.modelData.pinned ? qsTr("Pinned") + " · " : "")
                                  + Qt.formatDateTime(card.modelData.publishedAt, "yyyy-MM-dd")
                            color: card.modelData.unread ? Theme.primary : Theme.textMuted
                            font.pixelSize: Theme.fontSize(12)
                            font.bold: card.modelData.unread
                            wrapMode: Text.WordWrap
                        }
                        Text {
                            textFormat: Text.PlainText
                            Layout.fillWidth: true
                            text: card.modelData.title
                            color: Theme.text
                            font.pixelSize: Theme.fontSize(19)
                            font.weight: Font.DemiBold
                            wrapMode: Text.Wrap
                        }
                        Text {
                            objectName: "announcementBody_" + card.modelData.id
                            textFormat: Text.PlainText
                            Layout.fillWidth: true
                            visible: root.expandedId === card.modelData.id
                            text: card.modelData.body
                            color: Theme.textSecondary
                            font.pixelSize: Theme.fontSize(14)
                            lineHeight: 1.4
                            wrapMode: Text.Wrap
                        }
                        AppButton {
                            objectName: "readAnnouncement_" + card.modelData.id
                            text: root.expandedId === card.modelData.id ? qsTr("Collapse")
                                                                      : qsTr("Read announcement")
                            compact: true
                            onClicked: {
                                if (root.expandedId === card.modelData.id) {
                                    root.expandedId = ""
                                } else {
                                    root.expandedId = card.modelData.id
                                    root.contentModel.markRead(card.modelData.id)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
