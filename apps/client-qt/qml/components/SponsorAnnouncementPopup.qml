// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

Popup {
    id: root

    property var preferencesModel: preferences
    property string applicationVersion: Qt.application.version
    readonly property string announcementId: "sponsors:" + applicationVersion
    property bool acknowledged: false
    signal viewSponsorsRequested()

    parent: Overlay.overlay
    x: Math.round((parent.width - width) / 2)
    y: Math.round((parent.height - height) / 2)
    width: Math.min(Theme.size(620), parent.width - Theme.size(40))
    height: Math.min(Theme.size(560), parent.height - Theme.size(40))
    padding: Theme.size(24)
    modal: true
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    onOpened: acknowledged = false
    onClosed: acknowledge()

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
            text: qsTr("Thank you to our sponsors")
            color: Theme.text
            font.pixelSize: Theme.fontSize(24)
            font.weight: Font.DemiBold
            wrapMode: Text.WordWrap
        }

        Text {
            textFormat: Text.PlainText
            Layout.fillWidth: true
            text: qsTr("Your support helps keep Hexproof servers running and development moving forward.")
            color: Theme.textSecondary
            font.pixelSize: Theme.fontSize(13)
            lineHeight: 1.35
            wrapMode: Text.WordWrap
        }

        Flickable {
            id: sponsorScroller
            objectName: "sponsorAnnouncementScroll"
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumHeight: 0
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            contentWidth: width
            contentHeight: sponsorList.implicitHeight
            ScrollBar.vertical: ScrollBar {
                policy: sponsorScroller.contentHeight > sponsorScroller.height
                        ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
            }

            SponsorList {
                id: sponsorList
                // Keep names, tier counts and links clear of the scrollbar.
                width: Math.max(0, sponsorScroller.width - Theme.size(14))
                compact: true
                onProfileRequested: url => Qt.openUrlExternally(url)
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: Theme.size(4)
            spacing: Theme.size(10)

            AppButton {
                objectName: "viewSponsorsButton"
                Layout.fillWidth: true
                variant: "secondary"
                text: qsTr("View full sponsor list")
                onClicked: {
                    root.acknowledge()
                    root.close()
                    root.viewSponsorsRequested()
                }
            }

            AppButton {
                objectName: "dismissSponsorsButton"
                Layout.fillWidth: true
                variant: "primary"
                text: qsTr("Close")
                onClicked: root.close()
            }
        }
    }

    function openIfNeeded() {
        if (root.preferencesModel
                && !root.preferencesModel.sponsorAnnouncementSeen(
                    root.announcementId)) {
            root.open()
        }
    }

    function acknowledge() {
        if (root.acknowledged || !root.preferencesModel)
            return
        root.preferencesModel.acknowledgeSponsorAnnouncement(
            root.announcementId)
        root.acknowledged = true
    }
}
