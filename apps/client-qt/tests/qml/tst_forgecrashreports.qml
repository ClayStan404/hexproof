// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors
import QtQuick
import QtQuick.Controls.Basic
import QtTest
import "../../qml/components"
import "../../qml/screens"

TestCase {
    name: "ForgeCrashReports"
    when: windowShown
    ApplicationWindow { id: testWindow; width: 1000; height: 760; visible: true }
    QtObject {
        id: mockService
        property var entries: []
        property string noticeId: ""
        signal noticeChanged()
        onNoticeIdChanged: noticeChanged()
        property string storageError: ""
        property string operationStatus: ""
        property string operationReportId: ""
        property int copies: 0
        property int dismissals: 0
        property var value: ({})
        function report(id) { return value.reportId === id ? value : ({}) }
        function reportText(id) { return value.reportId === id ? JSON.stringify(value) : "" }
        function dismiss(id) { if (noticeId === id) { noticeId = ""; ++dismissals } }
        function copyReport(id) { if (report(id).reportId) { ++copies; operationStatus = "copied"; operationReportId = id } }
        function refresh() { }
        function suggestedFile(id) { return "file:///tmp/unused.json" }
        function saveReport(id, url) { return true }
        function receive(revision) {
            value = {reportId: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", revision: revision,
                     occurredAt: "2026-10-08T12:00:00.123456789Z",
                     collectionState: revision === 1 ? "collecting" : "partial",
                     failure: {kind: "engine_exception"},
                     context: {attribution: "execution_site", sources: [
                           {identity: {name: "<b>Public card</b>"}}]}}
            entries = [value]
            if (revision === 1) noticeId = value.reportId
        }
    }
    Component { id: noticeComponent; ForgeCrashReportNotice { service: mockService } }
    Component { id: historyComponent; ForgeCrashReports { service: mockService; width: 1000; height: 760 } }
    property var notice: null
    property var history: null
    function init() {
        mockService.entries = []; mockService.value = ({}); mockService.noticeId = ""
        mockService.storageError = ""; mockService.operationStatus = ""
        mockService.operationReportId = ""
        mockService.copies = 0; mockService.dismissals = 0
        notice = noticeComponent.createObject(testWindow.contentItem)
        verify(notice !== null)
    }
    function cleanup() {
        testWindow.width = 1000; testWindow.height = 760
        Theme.uiScale = 1
        testTranslations.setLanguage("en")
        if (notice) notice.destroy()
        if (history) history.destroy()
        notice = null; history = null
    }
    function test_revisionUpdatesWithoutReopeningDismissedNotice() {
        mockService.receive(1)
        tryCompare(notice, "opened", true)
        verify(notice.height <= testWindow.height)
        notice.detailsVisible = true
        const details = findChild(notice, "forgeCrashReportDetails")
        verify(details !== null)
        compare(details.textFormat, TextEdit.PlainText)
        tryVerify(function() { return details.text.indexOf('"revision":1') >= 0 })
        mockService.receive(2)
        tryVerify(function() { return details.text.indexOf('"revision":2') >= 0 })
        mouseClick(findChild(notice, "forgeCrashCopy"))
        compare(mockService.copies, 1)
        mouseClick(findChild(notice, "forgeCrashDismiss"))
        tryCompare(notice, "opened", false)
        compare(mockService.dismissals, 1)
        mockService.receive(2)
        wait(50)
        verify(!notice.opened)
        history = historyComponent.createObject(testWindow.contentItem)
        verify(history !== null)
        tryCompare(history, "selectedId", mockService.value.reportId)
        verify(!isNaN(new Date(mockService.value.occurredAt).getTime()))
        verify(findChild(history, "forgeCrashCopy").enabled)
        verify(findChild(history, "forgeCrashSaveDialog") !== null)
        verify(findChild(notice, "forgeCrashNoticeSaveDialog") !== null)
        compare(findChild(notice, "forgeCrashSaveDialog"), null)
    }
    function test_feedbackBelongsToTheSelectedReport() {
        mockService.receive(1)
        tryCompare(notice, "opened", true)
        const feedback = findChild(notice, "forgeCrashOperationFeedback")
        verify(feedback !== null)
        mockService.operationStatus = "saved"
        mockService.operationReportId = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
        compare(feedback.text, "")
        mockService.operationReportId = mockService.value.reportId
        tryVerify(function() { return feedback.text.length > 0 })
        mockService.operationReportId = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
        tryCompare(feedback, "text", "")
    }
    function test_compactActionsRemainVisible_data() {
        return [{tag: "compact-zh", language: "zh", scale: 1.5},
                {tag: "compact-de", language: "de", scale: 1.5},
                {tag: "compact-fr", language: "fr", scale: 1.5}]
    }
    function test_compactActionsRemainVisible(data) {
        testTranslations.setLanguage(data.language)
        Theme.uiScale = data.scale
        testWindow.width = 900; testWindow.height = 620
        mockService.receive(1)
        tryCompare(notice, "opened", true)
        notice.detailsVisible = true
        wait(25)
        for (const name of ["forgeCrashCopy", "forgeCrashSave", "forgeCrashDismiss"]) {
            const button = findChild(notice, name)
            const position = button.mapToItem(testWindow.contentItem, 0, 0)
            verify(position.x >= 0 && position.y >= 0, name)
            verify(position.x + button.width <= testWindow.width, name + " horizontal")
            verify(position.y + button.height <= testWindow.height, name + " vertical")
        }
        notice.close()
        tryCompare(notice, "opened", false)
        history = historyComponent.createObject(testWindow.contentItem, {width: 900, height: 620})
        verify(history !== null)
        wait(25)
        for (const name of ["forgeCrashCopy", "forgeCrashSave"]) {
            const button = findChild(history, name)
            const position = button.mapToItem(testWindow.contentItem, 0, 0)
            verify(position.x + button.width <= testWindow.width, name + " history horizontal")
            verify(position.y + button.height <= testWindow.height, name + " history vertical")
        }
    }
    function test_expiryClearsOpenReport() {
        mockService.receive(1)
        tryCompare(notice, "opened", true)
        mockService.value = ({}); mockService.entries = []; mockService.noticeId = ""
        tryCompare(notice, "opened", false)
    }
    function test_feedbackDefersNewCrashNotice() {
        notice.suspended = true
        mockService.receive(1)
        wait(50)
        verify(!notice.opened)
        notice.suspended = false
        tryCompare(notice, "opened", true)
    }
}
