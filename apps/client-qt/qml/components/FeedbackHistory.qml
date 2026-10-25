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
    property bool active: false
    property bool awaitingReplyOnly: false
    readonly property var rows: service ? service.cases : []
    readonly property var awaitingReplies: rows.filter(row => needsReply(row))
    readonly property var visibleRows: awaitingReplyOnly ? awaitingReplies : rows
    property bool refreshing: false
    property bool refreshFailed: false
    property bool prepareRefresh: false
    property var refreshQueue: []
    property string refreshingId: ""
    property string previousSync: ""
    property bool initialized: false
    signal recordRequested(string recordId)
    spacing: Theme.size(12)
    function openCase(row) {
        return row.isPublic === true && row.isReply !== true && !row.parentSubmissionId
            && row.state === "accepted" && row.caseState !== "closed"
            && (!row.closureRequestState || row.closureRequestState === "none")
            && (!row.removalState || row.removalState === "none")
    }
    function needsReply(row) { return openCase(row) && row.needsReply === true }
    function canRefresh(row) {
        const next = Date.parse(row.threadNextAttempt || "")
        return openCase(row) && row.threadRefreshAllowed === true
            && (!isFinite(next) || next <= Date.now())
    }
    function stopRefresh() {
        refreshing = false
        refreshingId = ""
        prepareRefresh = false
        refreshQueue = []
    }
    function beginRefresh() {
        if (!active || !service || refreshing) return
        refreshFailed = false
        prepareRefresh = true
        refreshing = true
        Qt.callLater(advanceRefresh)
    }
    function advanceRefresh() {
        if (!active || !service || !refreshing || service.busy || service.saving) return
        if (prepareRefresh) {
            // Freeze a bounded round after loading/saving. Signals only advance it.
            refreshQueue = rows.filter(row => canRefresh(row)).slice().sort((a, b) =>
                (Date.parse(a.syncedAt || "") || 0) - (Date.parse(b.syncedAt || "") || 0))
                .slice(0, 5).map(row => ({id: row.id, syncedAt: row.syncedAt || ""}))
            prepareRefresh = false
        }
        if (refreshingId) {
            const result = service.caseRefresh || ({})
            const row = rows.find(value => value.id === refreshingId)
            if (result.caseId !== refreshingId || result.errorCode
                || (row && (row.syncedAt || "") === previousSync)) {
                refreshFailed = true
                stopRefresh()
                return
            }
            refreshingId = ""
        }
        while (refreshQueue.length) {
            const next = refreshQueue[0]
            refreshQueue = refreshQueue.slice(1)
            const row = rows.find(value => value.id === next.id)
            if (!row || !canRefresh(row) || (row.syncedAt || "") !== next.syncedAt) continue
            refreshingId = row.id
            previousSync = row.syncedAt || ""
            if (!service.refreshCaseSummary(row.id)) {
                refreshFailed = true
                stopRefresh()
            }
            return
        }
        stopRefresh()
    }
    onActiveChanged: {
        if (!active) stopRefresh()
        else if (initialized) beginRefresh()
    }
    onServiceChanged: {
        stopRefresh()
        if (initialized) beginRefresh()
    }
    Component.onCompleted: { initialized = true; beginRefresh() }
    Connections {
        target: root.service
        function onChanged() { Qt.callLater(root.advanceRefresh) }
        function onStatusChanged() { Qt.callLater(root.advanceRefresh) }
    }
    Text {
        Layout.fillWidth: true
        textFormat: Text.PlainText
        text: qsTr("Drafts stay on this device until deleted. Received content is kept locally for up to 30 days. Keep public receipts for status and removal; legacy private receipts expire after 90 days, subject to storage limits.")
        color: Theme.textSecondary
        wrapMode: Text.WordWrap
    }
    Flow {
        Layout.fillWidth: true
        spacing: Theme.size(8)
        AppButton {
            objectName: "feedbackHistoryAll"
            text: qsTr("All feedback")
            variant: root.awaitingReplyOnly ? "secondary" : "primary"
            onClicked: root.awaitingReplyOnly = false
        }
        AppButton {
            objectName: "feedbackHistoryAwaitingReply"
            text: qsTr("Awaiting your reply (%1)").arg(root.awaitingReplies.length)
            variant: root.awaitingReplyOnly ? "primary" : "secondary"
            onClicked: root.awaitingReplyOnly = true
        }
        AppButton {
            objectName: "feedbackHistoryRefresh"
            text: qsTr("Refresh")
            variant: "secondary"
            enabled: root.active && !!root.service && !root.refreshing
                && !root.service.busy && !root.service.saving
            onClicked: root.beginRefresh()
        }
    }
    Text {
        objectName: "feedbackHistorySyncStatus"
        Layout.fillWidth: true
        visible: root.refreshing || root.refreshFailed
        textFormat: Text.PlainText
        text: root.refreshFailed
            ? qsTr("Refresh stopped. Saved information may be out of date. Try again later.")
            : qsTr("Refreshing feedback…")
        color: root.refreshFailed ? Theme.warning : Theme.textSecondary
        wrapMode: Text.WordWrap
    }
    Text {
        visible: root.visibleRows.length === 0
        textFormat: Text.PlainText
        text: root.awaitingReplyOnly ? qsTr("No feedback awaiting your reply in saved information.") : qsTr("No feedback yet.")
        color: Theme.textMuted
    }
    ListView {
        id: list
        objectName: "feedbackHistoryList"
        Layout.fillWidth: true
        Layout.fillHeight: true
        spacing: Theme.size(8)
        clip: true
        model: root.visibleRows
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
                    objectName: "feedbackHistoryNeedsReply-" + historyEntry.row.id
                    Layout.fillWidth: true
                    visible: root.needsReply(historyEntry.row)
                    textFormat: Text.PlainText
                    text: qsTr("Needs your reply")
                    color: Theme.warning
                    font.weight: Font.DemiBold
                    wrapMode: Text.WordWrap
                }
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
                    objectName: "feedbackHistorySummary-" + historyEntry.row.id
                    Layout.fillWidth: true
                    visible: !!historyEntry.row.summary
                        && (!historyEntry.row.removalState || historyEntry.row.removalState === "none")
                    textFormat: Text.PlainText
                    text: qsTr("AI update: %1").arg(historyEntry.row.summary || "")
                    color: Theme.textSecondary
                    maximumLineCount: 3
                    elide: Text.ElideRight
                    wrapMode: Text.Wrap
                }
                Text {
                    Layout.fillWidth: true
                    textFormat: Text.PlainText
                    text: Labels.date(historyEntry.row.acceptedAt || historyEntry.row.createdAt || historyEntry.row.draftCreatedAt)
                        + (historyEntry.row.syncedAt ? "\n" + qsTr("Last synced: %1").arg(Labels.date(historyEntry.row.syncedAt))
                           : root.openCase(historyEntry.row) ? "\n" + qsTr("Not synced yet. Replies may be missing.") : "")
                    color: Theme.textMuted
                    font.pixelSize: Theme.fontSize(11)
                }
            }
        }
    }
}
