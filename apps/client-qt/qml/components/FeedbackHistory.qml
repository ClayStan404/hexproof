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
        text: qsTr("Drafts stay on this device until deleted. Received content is kept locally for up to 30 days. Keep public receipts for status and removal; legacy private receipts expire after 90 days, subject to storage limits.")
        color: Theme.textSecondary
        wrapMode: Text.WordWrap
    }
    Text {
        visible: !root.service || root.service.cases.length === 0
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
        model: root.service ? root.service.cases : []
        ScrollBar.vertical: ScrollBar { }
        delegate: AppButton {
            id: historyEntry
            required property var modelData
            readonly property var row: modelData || ({})
            objectName: "feedbackHistoryCase-" + historyEntry.row.id
            width: list.width
            implicitHeight: historyRow.implicitHeight + Theme.size(24)
            variant: "secondary"
            onClicked: root.recordRequested(historyEntry.row.id)
            contentItem: ColumnLayout {
                id: historyRow
                spacing: Theme.size(5)
                Text {
                    Layout.fillWidth: true
                    visible: historyEntry.row.isReply === true && historyEntry.row.parentAvailable === false
                    textFormat: Text.PlainText
                    text: qsTr("Reply · original feedback is no longer on this device")
                    color: Theme.warning
                    wrapMode: Text.WordWrap
                }
                Text {
                    Layout.fillWidth: true
                    textFormat: Text.PlainText
                    text: Labels.category(historyEntry.row.category) + " · " + Labels.recordState(historyEntry.row)
                    color: Theme.primary
                    font.weight: Font.DemiBold
                    wrapMode: Text.WordWrap
                }
                Text {
                    Layout.fillWidth: true
                    visible: !!historyEntry.row.workState && historyEntry.row.caseState !== "closed"
                        && (!historyEntry.row.removalState || historyEntry.row.removalState === "none")
                    textFormat: Text.PlainText
                    text: Labels.workState(historyEntry.row.workState)
                    color: Theme.primary
                    wrapMode: Text.WordWrap
                }
                Text {
                    Layout.fillWidth: true
                    visible: Number(historyEntry.row.localReplyCount || 0) > 0
                    textFormat: Text.PlainText
                    text: qsTr("Replies on this device: %1").arg(historyEntry.row.localReplyCount || 0)
                    color: Theme.textSecondary
                    wrapMode: Text.WordWrap
                }
                Text {
                    Layout.fillWidth: true
                    textFormat: Text.PlainText
                    text: historyEntry.row.description || qsTr("Empty draft")
                    color: Theme.text
                    maximumLineCount: 2
                    elide: Text.ElideRight
                    wrapMode: Text.Wrap
                }
                Text {
                    Layout.fillWidth: true
                    textFormat: Text.PlainText
                    text: Labels.date(historyEntry.row.acceptedAt || historyEntry.row.createdAt || historyEntry.row.draftCreatedAt)
                        + (historyEntry.row.syncedAt ? "\n" + qsTr("Last synced: %1").arg(Labels.date(historyEntry.row.syncedAt)) : "")
                    color: Theme.textMuted
                    font.pixelSize: Theme.fontSize(11)
                }
            }
        }
    }
}
