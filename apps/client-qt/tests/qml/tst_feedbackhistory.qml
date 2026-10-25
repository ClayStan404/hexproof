// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors
import QtQuick
import QtQuick.Controls.Basic
import QtTest
import "../../qml/components"

TestCase {
    id: testCase
    name: "FeedbackHistory"
    when: windowShown
    ApplicationWindow {
        id: testWindow
        width: 900
        height: 800
        visible: true
    }
    QtObject {
        id: mock
        property var cases: []
        property var draft: ({id: "unsent", description: "Keep this draft"})
        property var thread: ({caseId: "unsent", errorCode: "existing"})
        property var caseRefresh: ({})
        property bool busy: false
        property bool saving: false
        property bool rejectRefresh: false
        property var requests: []
        property int completed: 0
        signal changed()
        signal statusChanged()
        onBusyChanged: statusChanged()
        onSavingChanged: statusChanged()
        onCasesChanged: changed()
        function refreshCaseSummary(id) {
            if (rejectRefresh) return false
            if (busy || saving) throw new Error("Concurrent or unsaved refresh")
            requests = requests.concat([id])
            caseRefresh = {caseId: id, errorCode: ""}
            busy = true
            return true
        }
        function finish(error) {
            const id = caseRefresh.caseId
            ++completed
            if (!error) {
                cases = cases.map(row => row.id !== id ? row : Object.assign({}, row, {
                    syncedAt: new Date(Date.now() + completed).toISOString(),
                    threadNextAttempt: new Date(Date.now() + 60000).toISOString()
                }))
            }
            caseRefresh = {caseId: id, errorCode: error || ""}
            busy = false
            changed()
        }
    }
    Component { id: component; FeedbackHistory { anchors.fill: parent; service: mock } }
    property var history: null
    function row(id, options) {
        return Object.assign({id: id, isPublic: true, state: "accepted", category: "problem",
            description: "Report " + id, caseState: "open", closureRequestState: "none",
            removalState: "none", threadRefreshAllowed: true, needsReply: false,
            syncedAt: "", threadNextAttempt: "", summary: "", createdAt: "2026-01-01T00:00:00Z"}, options || {})
    }
    function init() {
        testTranslations.setLanguage("en")
        mock.cases = []; mock.busy = false; mock.saving = false
        mock.rejectRefresh = false; mock.requests = []; mock.caseRefresh = ({}); mock.completed = 0
        history = createTemporaryObject(component, testWindow.contentItem)
        verify(history !== null)
    }
    function cleanup() {
        history.active = false
        history = null
    }
    function test_openRefreshesFiveOldestSeriallyWithoutChangingSelection() {
        mock.cases = [7, 2, 6, 1, 5, 4, 3].map(n => row("case-" + n,
            {syncedAt: "2026-01-0" + n + "T00:00:00Z"}))
        history.active = true
        for (let n = 1; n <= 5; ++n) {
            tryCompare(mock, "busy", true)
            compare(mock.requests.length, n)
            compare(mock.requests[n - 1], "case-" + n)
            mock.finish("")
        }
        tryCompare(history, "refreshing", false)
        compare(mock.requests.length, 5)
        compare(mock.draft.id, "unsent")
        compare(mock.thread.caseId, "unsent")
        mock.changed(); mock.statusChanged()
        wait(20)
        compare(mock.requests.length, 5) // No polling after the bounded round.
        mouseClick(findChild(history, "feedbackHistoryRefresh"))
        tryCompare(mock, "busy", true)
        compare(mock.requests[5], "case-6")
        mock.finish("")
        tryCompare(mock, "busy", true)
        compare(mock.requests[6], "case-7")
        mock.finish("")
        tryCompare(history, "refreshing", false)
    }
    function test_waitsForBusyAndSaveBeforeTakingLoadedSnapshot() {
        mock.busy = true; mock.saving = true
        history.active = true
        wait(20)
        compare(mock.requests.length, 0)
        mock.cases = [row("loaded")]
        mock.busy = false
        wait(20)
        compare(mock.requests.length, 0)
        mock.saving = false
        tryCompare(mock, "busy", true)
        compare(mock.requests, ["loaded"])
        mock.finish("")
        tryCompare(history, "refreshing", false)
    }
    function test_closedRemovedPrivateRepliesAndCooldownNeverRefresh() {
        mock.cases = [row("closed", {caseState: "closed"}),
            row("closing", {closureRequestState: "requested"}),
            row("removing", {removalState: "requested"}), row("private", {isPublic: false}),
            row("reply", {isReply: true, parentSubmissionId: "parent"}),
            row("draft", {state: "draft"}), row("untrusted", {threadRefreshAllowed: false}),
            row("cooldown", {threadNextAttempt: "2999-01-01T00:00:00Z"}), row("eligible")]
        history.active = true
        tryCompare(mock, "busy", true)
        compare(mock.requests, ["eligible"])
        mock.finish("")
        tryCompare(history, "refreshing", false)
        compare(mock.requests.length, 1)
    }
    function test_hidingStopsQueueAndRevalidatesClosedCases() {
        mock.cases = [row("first"), row("second"), row("third")]
        history.active = true
        tryCompare(mock, "busy", true)
        history.active = false
        mock.finish("")
        wait(20)
        compare(mock.requests, ["first"])
        history.active = true
        tryCompare(mock, "busy", true)
        compare(mock.requests, ["first", "second"])
        mock.cases = mock.cases.map(value => value.id === "third"
            ? Object.assign({}, value, {caseState: "closed"}) : value)
        mock.finish("")
        tryCompare(history, "refreshing", false)
        compare(mock.requests.length, 2)
    }
    function test_failureKeepsCacheAndStopsUntilExplicitRefresh() {
        mock.cases = [row("first", {summary: "Cached AI summary"}), row("second")]
        history.active = true
        tryCompare(mock, "busy", true)
        mock.finish("network_error")
        tryCompare(history, "refreshing", false)
        verify(history.refreshFailed)
        compare(mock.cases[0].summary, "Cached AI summary")
        const status = findChild(history, "feedbackHistorySyncStatus")
        verify(status.visible)
        verify(status.text.indexOf("Saved information may be out of date") >= 0)
        mock.statusChanged()
        wait(20)
        compare(mock.requests.length, 1)
        mock.rejectRefresh = true
        mouseClick(findChild(history, "feedbackHistoryRefresh"))
        tryCompare(history, "refreshing", false)
        verify(history.refreshFailed)
        compare(mock.requests.length, 1)
    }
    function test_replyFilterUsesCurrentQuestionAndSummaryIsPlainText() {
        mock.cases = [row("waiting", {workState: "needs-information", needsReply: true,
                summary: "<b>Which card?</b>"}),
            row("withdrawn", {workState: "needs-information", needsReply: false}),
            row("closed", {caseState: "closed", needsReply: true}), row("ordinary")]
        const filter = findChild(history, "feedbackHistoryAwaitingReply")
        compare(filter.text, "Awaiting your reply (1)")
        mouseClick(filter)
        tryCompare(findChild(history, "feedbackHistoryList"), "count", 1)
        const badge = findChild(history, "feedbackHistoryNeedsReply-waiting")
        verify(badge !== null)
        verify(badge.visible)
        compare(badge.text, "Needs your reply")
        const summary = findChild(history, "feedbackHistorySummary-waiting")
        compare(summary.textFormat, Text.PlainText)
        compare(summary.text, "AI update: <b>Which card?</b>")
        mock.cases = mock.cases.map(value => Object.assign({}, value, {needsReply: false}))
        tryCompare(findChild(history, "feedbackHistoryList"), "count", 0)
        compare(mock.requests.length, 0)
    }
}
