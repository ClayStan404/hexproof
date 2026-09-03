// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

Popup {
    id: root

    property var preferencesModel: preferences
    property var artManagerModel: cardArtManager
    property bool acknowledged: false
    // Derived from the manager's audit version so a kCardFaceAuditVersion bump
    // re-shows this notice even for users who acknowledged the previous one.
    readonly property int noticeVersion: root.artManagerModel
                                          && root.artManagerModel.faceAuditVersion !== undefined
                                          ? root.artManagerModel.faceAuditVersion : 1
    signal reviewRequested()

    parent: Overlay.overlay
    x: Math.round((parent.width - width) / 2)
    y: Math.round((parent.height - height) / 2)
    width: Math.min(Theme.size(520), parent.width - Theme.size(40))
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
            text: qsTr("Some deck card art needs repair")
            color: Theme.text
            font.pixelSize: Theme.fontSize(22)
            font.weight: Font.DemiBold
            wrapMode: Text.WordWrap
        }

        Text {
            textFormat: Text.PlainText
            Layout.fillWidth: true
            text: qsTr("Hexproof found an older cache that may be missing double-faced card backs or contain outdated special-card mappings. You can review the local check before downloading anything.")
            color: Theme.textSecondary
            font.pixelSize: Theme.fontSize(13)
            lineHeight: 1.35
            wrapMode: Text.WordWrap
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: Theme.size(6)
            spacing: Theme.size(10)

            AppButton {
                objectName: "laterCardArtRepairButton"
                Layout.fillWidth: true
                variant: "secondary"
                text: qsTr("Later")
                onClicked: root.close()
            }

            AppButton {
                objectName: "reviewCardArtRepairButton"
                Layout.fillWidth: true
                variant: "primary"
                text: qsTr("Review repair")
                onClicked: {
                    root.acknowledge()
                    root.close()
                    root.reviewRequested()
                }
            }
        }
    }

    function openIfNeeded() {
        if (root.preferencesModel && root.artManagerModel
                && root.artManagerModel.repairNeeded
                && !root.preferencesModel.cardArtRepairNoticeSeen(
                    root.noticeVersion)) {
            root.open()
        }
    }

    function acknowledge() {
        if (root.acknowledged || !root.preferencesModel)
            return
        root.preferencesModel.acknowledgeCardArtRepairNotice(root.noticeVersion)
        root.acknowledged = true
    }
}
