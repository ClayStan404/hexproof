// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors
pragma ComponentBehavior: Bound
pragma Translator: "Feedback"
import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import "FeedbackLabels.js" as Labels

ColumnLayout {
    id: root
    property var service: null
    signal recordRequested(string recordId)
    spacing: Theme.size(12)
    Text {
        Layout.fillWidth: true
        textFormat: Text.PlainText
        text: qsTr("Drafts and unreceived feedback stay on this device until you delete them. Received content is kept locally for up to 30 days; receipts for up to 90 days, subject to storage limits.")
        color: Theme.textSecondary
        wrapMode: Text.WordWrap
    }
    Text {
        visible: !root.service || root.service.records.length === 0
        textFormat: Text.PlainText
        text: qsTr("No feedback yet.")
        color: Theme.textMuted
    }
    ListView {
        id: list
        objectName: "feedbackHistoryList"
        Layout.fillWidth: true
        Layout.fillHeight: true
        spacing: Theme.size(8)
        clip: true
        model: root.service ? root.service.records : []
        ScrollBar.vertical: ScrollBar { }
        delegate: AppButton {
            required property var modelData
            objectName: "feedbackHistory-" + modelData.id
            width: list.width
            implicitHeight: historyRow.implicitHeight + Theme.size(24)
            variant: "secondary"
            onClicked: root.recordRequested(modelData.id)
            contentItem: ColumnLayout {
                id: historyRow
                spacing: Theme.size(5)
                Text {
                    Layout.fillWidth: true
                    textFormat: Text.PlainText
                    text: Labels.category(modelData.category) + " · " + Labels.state(modelData.state)
                    color: Theme.primary
                    font.weight: Font.DemiBold
                    wrapMode: Text.WordWrap
                }
                Text {
                    Layout.fillWidth: true
                    textFormat: Text.PlainText
                    text: modelData.description || qsTr("Empty draft")
                    color: Theme.text
                    maximumLineCount: 2
                    elide: Text.ElideRight
                    wrapMode: Text.Wrap
                }
                Text {
                    Layout.fillWidth: true
                    textFormat: Text.PlainText
                    text: Labels.date(modelData.acceptedAt || modelData.createdAt || modelData.draftCreatedAt)
                    color: Theme.textMuted
                    font.pixelSize: Theme.fontSize(11)
                }
            }
        }
    }
}
