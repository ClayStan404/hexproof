// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors
import QtQuick
import QtQuick.Controls.Basic
import QtTest
import "../../qml/components"

TestCase {
    id: testCase
    name: "Feedback"
    when: windowShown
    ApplicationWindow {
        id: testWindow
        width: 1000
        height: 800
        visible: true
        property bool feedbackInteractionOpen: workflow ? workflow.interactionOpen : false
        function openFeedback(context, kind, snapshot) { workflow.openFor(context, kind, snapshot) }
    }
    QtObject {
        id: mock
        property var draft: ({})
        property var records: []
        property bool enabled: true
        property bool busy: false
        property bool saving: false
        property string errorCode: ""
        property string supportLabel: "Hexproof test support"
        property string privacyUrl: ""
        property string operationCode: ""
        property string operationRecordId: ""
        property int nextId: 0
        property int submissions: 0
        property int stops: 0
        property int queries: 0
        property int deletions: 0
        property var attachedReport: ({})
        property string previewValue: ""
        function saveRecord(value) {
            draft = value
            records = records.filter(row => row.id !== value.id).concat([value])
        }
        function createDraft(context) {
            const id = "draft-" + (++nextId)
            saveRecord({id: id, state: "draft", editable: true, category: "problem",
                description: "", replyEmail: "", context: context || {}, attachments: [],
                payloadAvailable: true, createdAt: "2026-10-09T12:00:00Z"})
            return id
        }
        function updateDraft(fields) {
            const value = Object.assign({}, draft, fields)
            if (encodeURIComponent(value.description).replace(/%[A-F\d]{2}/gi, "x").length > 8192) {
                errorCode = "invalid_description"
                return false
            }
            if (encodeURIComponent(value.replyEmail).replace(/%[A-F\d]{2}/gi, "x").length > 254) {
                errorCode = "invalid_email"
                return false
            }
            errorCode = ""
            saveRecord(value)
            return true
        }
        function selectRecord(id) { draft = records.filter(row => row.id === id)[0] || {} }
        function cloneDraft(id) {
            const value = records.filter(row => row.id === id)[0]
            const newId = "draft-" + (++nextId)
            saveRecord(Object.assign({}, value, {id: newId, editable: true, state: "draft", receipt: "", uploadAuthorized: false}))
            return newId
        }
        function attachCrashReport(value) {
            attachedReport = JSON.parse(JSON.stringify(value))
            updateDraft({attachments: [{id: "crash", kind: "forge_crash", mediaType: "application/json", byteLength: 100}]})
            previewValue = JSON.stringify(attachedReport)
        }
        function attachHostingDiagnostics(value) { attachCrashReport(value) }
        function attachImage(url) { }
        function pasteImage() { }
        function removeAttachment(id) { updateDraft({attachments: draft.attachments.filter(value => value.id !== id)}) }
        function attachmentPreview(id) { return previewValue }
        function submit() {
            ++submissions
            updateDraft({state: "queued", editable: false, uploadAuthorized: true})
        }
        function stop(id) {
            ++stops
            updateDraft({state: "unconfirmed", editable: false, uploadAuthorized: false, reason: "stopped"})
        }
        function queryReceipt(id) { ++queries }
        function deleteRecord(id) {
            ++deletions
            records = records.filter(row => row.id !== id)
            if (draft.id === id) draft = ({})
        }
        function suggestedExport(id) { return "file:///tmp/feedback-test.json" }
        function exportRecord(id, file) { operationCode = "exported"; operationRecordId = id }
        function copyReceipt(id) { operationCode = "copied"; operationRecordId = id }
    }
    QtObject {
        id: crash
        property string noticeId: ""
        property var entries: []
        function refresh() { }
        function report(id) { return entries.filter(value => value.reportId === id)[0] || {} }
    }
    QtObject {
        id: host
        function diagnosticsReport() { return {schemaVersion: 2} }
    }
    Component { id: component; FeedbackWorkflow { service: mock; crashService: crash; hostingService: host } }
    property var workflow: null
    function init() {
        mock.draft = ({}); mock.records = []; mock.errorCode = ""
        mock.enabled = true; mock.busy = false; mock.saving = false
        mock.operationCode = ""; mock.operationRecordId = ""
        mock.nextId = 0; mock.submissions = 0; mock.stops = 0; mock.queries = 0; mock.deletions = 0
        mock.previewValue = ""; mock.attachedReport = ({}); crash.entries = []; crash.noticeId = ""
        workflow = component.createObject(testWindow.contentItem)
        verify(workflow !== null)
        workflow.openFor({}, "", {})
        tryCompare(findChild(workflow, "feedbackDialog"), "opened", true)
    }
    function cleanup() {
        if (workflow) workflow.destroy()
        workflow = null
        testWindow.width = 1000; testWindow.height = 800
        Theme.uiScale = 1
        testTranslations.setLanguage("en")
    }
    function test_draftEditingDoesNotSendOrTreatTextAsHtml() {
        const field = findChild(workflow, "feedbackDescription")
        compare(field.textFormat, TextEdit.PlainText)
        field.text = "<b>Private description</b>"
        compare(mock.draft.description, "<b>Private description</b>")
        compare(mock.submissions, 0)
        verify(workflow.interactionOpen)
        mouseClick(findChild(workflow, "feedbackSend"))
        compare(mock.submissions, 1)
        compare(mock.draft.state, "queued")
        verify(field.readOnly)
        waitForRendering(findChild(workflow, "feedbackStopSending"))
        mouseClick(findChild(workflow, "feedbackStopSending"))
        compare(mock.stops, 1)
        compare(mock.draft.uploadAuthorized, false)
        mouseClick(findChild(workflow, "feedbackClose"))
        tryCompare(workflow, "interactionOpen", false)
        compare(mock.submissions, 1)
        compare(mock.draft.description, "<b>Private description</b>")
    }
    function test_rejectedInputSurvivesAttachmentAndCategoryUpdates_data() {
        return [{tag:"description-over-8KiB", field:"feedbackDescription", key:"description",
                    value:"x".repeat(8193), corrected:"Corrected description", code:"invalid_description"},
                {tag:"email-over-254-UTF8-bytes", field:"feedbackEmail", key:"replyEmail",
                    value:"中".repeat(100), corrected:"player@example.test", code:"invalid_email"}]
    }
    function test_rejectedInputSurvivesAttachmentAndCategoryUpdates(data) {
        findChild(workflow, "feedbackDescription").text = "Previously saved description"
        const field = findChild(workflow, data.field)
        const saved = mock.draft[data.key]
        field.text = data.value
        if (data.key === "replyEmail") field.textEdited()
        compare(mock.errorCode, data.code)
        compare(mock.draft[data.key], saved)
        const composer = findChild(workflow, "feedbackComposer")
        verify(!composer.inputMatchesRecord)
        verify(!findChild(workflow, "feedbackSend").enabled)
        mock.attachCrashReport({reportId:"chosen", revision:1})
        compare(field.text, data.value)
        const category = findChild(workflow, "feedbackCategory")
        category.currentIndex = 1
        category.activated(1)
        compare(mock.draft.category, "suggestion")
        compare(field.text, data.value)
        compare(mock.draft[data.key], saved)
        compare(mock.errorCode, "")
        compare(composer.inputErrorCode, data.code)
        verify(findChild(workflow, "feedbackError").text.length > 0)
        verify(findChild(workflow, "feedbackSaveStatus").text !== "Draft saved")
        verify(!findChild(workflow, "feedbackSend").enabled)
        compare(mock.submissions, 0)
        field.text = data.corrected
        if (data.key === "replyEmail") field.textEdited()
        compare(mock.draft[data.key], data.corrected)
        compare(composer.inputErrorCode, "")
        verify(composer.inputMatchesRecord)
        verify(findChild(workflow, "feedbackSend").enabled)
        workflow.newDraft()
        compare(findChild(workflow, "feedbackDescription").text, "")
        compare(findChild(workflow, "feedbackEmail").text, "")
    }

    function test_contextualEntryOffersChoiceAndFreezesSelectedRevision() {
        findChild(workflow, "feedbackDescription").text = "Keep my draft"
        const originalId = mock.draft.id
        const report = {reportId: "report-1", revision: 1, description: "<b>Literal</b>"}
        workflow.openFor({feature: "forge_table"}, "crash", report)
        tryCompare(findChild(workflow, "feedbackContextChoice"), "opened", true)
        compare(mock.attachedReport.revision, undefined)
        report.revision = 2
        mouseClick(findChild(workflow, "feedbackContextAdd"))
        compare(mock.draft.id, originalId)
        compare(mock.draft.description, "Keep my draft")
        compare(mock.attachedReport.revision, 1)
        compare(mock.submissions, 0)
        workflow.openPreview("crash", "Crash")
        tryCompare(findChild(workflow, "feedbackAttachmentPreview"), "opened", true)
        compare(findChild(workflow, "feedbackPreviewText").textFormat, TextEdit.PlainText)
        verify(findChild(workflow, "feedbackPreviewText").text.includes('"revision":1'))
        mouseClick(findChild(workflow, "feedbackPreviewClose"))
        verify(workflow.interactionOpen)
    }
    function test_newCrashOffersSelectionWithoutAttachingOrReplacingDraft() {
        findChild(workflow, "feedbackDescription").text = "Draft in progress"
        crash.entries = [{reportId:"new-report", revision:1}]
        crash.noticeId = "new-report"
        const hint = findChild(workflow, "feedbackNewCrashHint")
        tryCompare(hint, "visible", true)
        compare(mock.draft.attachments.length, 0)
        compare(mock.draft.description, "Draft in progress")
        waitForRendering(hint)
        mouseClick(findChild(workflow, "feedbackNewCrashChoose"))
        tryCompare(findChild(workflow, "feedbackCrashPicker"), "opened", true)
        compare(mock.draft.attachments.length, 0)
        compare(mock.submissions, 0)
    }

    function test_historyDeleteRequiresExplicitConfirmation() {
        findChild(workflow, "feedbackDescription").text = "Keep until deleted"
        mock.submit()
        findChild(workflow, "feedbackComposer").deleteRequested()
        const confirm = findChild(workflow, "feedbackDeleteConfirmation")
        tryCompare(confirm, "opened", true)
        compare(mock.deletions, 0)
        confirm.confirmed()
        confirm.close()
        compare(mock.deletions, 1)
        verify(workflow.historyVisible)
        verify(workflow.interactionOpen)
        compare(mock.records.length, 0)
    }
    function test_disabledAndFailedStorageRemainVisible() {
        mock.enabled = false
        findChild(workflow, "feedbackDescription").text = "Offline"
        verify(!findChild(workflow, "feedbackSend").enabled)
        mock.errorCode = "storage_unavailable"
        verify(findChild(workflow, "feedbackError").text.length > 0)
        verify(findChild(workflow, "feedbackSaveStatus").text !== "Draft saved")
        compare(mock.submissions, 0)
    }
    function test_metadataSnapshotsOnlyWhenCreatingDraft() {
        workflow.baseContext = {uiLanguage:"en", catalogVersion:"2026-10-01"}
        workflow.newDraft()
        compare(mock.draft.context.uiLanguage, "en")
        workflow.baseContext = {uiLanguage:"zh_CN", catalogVersion:"2026-10-09"}
        workflow.openFor({}, "", {})
        verify(!findChild(workflow, "feedbackContextChoice").visible)
        compare(mock.draft.context.uiLanguage, "en")
        workflow.newDraft()
        compare(mock.draft.context.uiLanguage, "zh_CN")
        compare(mock.draft.context.catalogVersion, "2026-10-09")
    }

    function test_retentionAndReceiptNoticesFollowSubmissionState() {
        const receiver = findChild(workflow, "feedbackReceiverRetention")
        const meaning = findChild(workflow, "feedbackReceivedMeaning")
        const local = findChild(workflow, "feedbackReceivedLocalRetention")
        verify(receiver.visible)
        verify(receiver.text.includes("90 days") && receiver.text.includes("spam"))
        verify(!meaning.visible && !local.visible)
        compare(findChild(workflow, "feedbackSend").variant, "primary")
        findChild(workflow, "feedbackDescription").text = "Notice state test"
        mock.submit()
        verify(!receiver.visible && !meaning.visible && !local.visible)
        mock.updateDraft({state:"received", receipt:"receipt-1", uploadAuthorized:false})
        verify(!receiver.visible)
        verify(meaning.visible && local.visible)
        verify(meaning.text.includes("storage") && meaning.text.includes("review or resolution"))
        verify(local.text.includes("30 days") && local.text.includes("90 days"))
        compare(meaning.textFormat, Text.PlainText)
        workflow.showHistory()
        verify(!receiver.visible && !meaning.visible && !local.visible)
    }

    function test_operationResultBelongsToCurrentRecord() {
        mock.operationCode = "exported"; mock.operationRecordId = "another-record"
        compare(workflow.operationText(), "")
        mock.operationRecordId = mock.draft.id
        verify(workflow.operationText().length > 0)
    }
    function test_compactLayout_data() {
        return [{tag: "english", language: "en", scale: 1},
                {tag: "chinese-scaled", language: "zh", scale: 1.5},
                {tag: "german-scaled", language: "de", scale: 1.5}]
    }
    function test_compactLayout(data) {
        testTranslations.setLanguage(data.language)
        Theme.uiScale = data.scale
        testWindow.width = 900; testWindow.height = 620
        findChild(workflow, "feedbackDescription").text = "Responsive feedback"
        wait(30)
        for (const name of ["feedbackClose", "feedbackSend", "feedbackHistoryButton"]) {
            const button = findChild(workflow, name)
            const pos = button.mapToItem(testWindow.contentItem, 0, 0)
            verify(pos.x >= 0 && pos.y >= 0, name)
            verify(pos.x + button.width <= testWindow.width, name + " width")
            verify(pos.y + button.height <= testWindow.height, name + " height")
        }
        mouseClick(findChild(workflow, "feedbackHistoryButton"))
        verify(workflow.historyVisible)
        tryVerify(function() { return findChild(workflow, "feedbackHistoryList").height > 0 })
    }
}
