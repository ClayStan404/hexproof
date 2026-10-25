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
        readonly property var cases: records.filter(row => !row.parentSubmissionId
            || !records.some(parent => parent.id === row.parentSubmissionId))
        property bool enabled: true
        property string configurationErrorCode: ""
        property bool busy: false
        property bool saving: false
        property string errorCode: ""
        property string supportLabel: "Hexproof test support"
        property string publicRepository: "hexproof/feedback-test"
        property string noticeText: "Public test notice. No AI provider is enabled. Attachments are hosted by this local test service."
        property string noticeRevision: "test-notice-1"
        property string providerPolicyRevision: "no-ai-1"
        property string previewDigest: ""
        property int removals: 0
        property int closures: 0
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
        property var thread: ({})
        property var threadAttachmentPreview: ({})
        property int threadQueries: 0
        property int replyDrafts: 0
        signal changed()
        signal statusChanged()
        onBusyChanged: statusChanged()
        onSavingChanged: statusChanged()
        onDraftChanged: changed()
        function refreshThread(caseId) { ++threadQueries; return true }
        function createReplyDraft(caseId, questionId, revision) {
            const parent = records.filter(row => row.id === caseId)[0]
            if (!parent || parent.removalState !== "none" || parent.caseState === "closed"
                || (parent.closureRequestState && parent.closureRequestState !== "none")) return ""
            const id = "reply-" + (++nextId)
            ++replyDrafts
            saveRecord({id: id, state: "draft", editable: true, category: parent.category,
                description: "", isPublic: true, isReply: true, parentSubmissionId: caseId,
                questionId: questionId, questionRevision: revision,
                questionText: questionId && thread.question ? thread.question.description : "",
                attachments: [], context: {}, payloadAvailable: true})
            return id
        }
        function fetchThreadAttachment(contributionId, attachmentId) {
            threadAttachmentPreview = {contributionId: contributionId, attachmentId: attachmentId,
                loading: false, errorCode: "", content: "{\"public\":true}"}
            changed()
            return true
        }
        function saveRecord(value) {
            draft = value
            records = records.filter(row => row.id !== value.id).concat([value])
        }
        function createDraft(context) {
            const id = "draft-" + (++nextId)
            saveRecord({id: id, state: "draft", editable: true, category: "problem",
                description: "", isPublic: true, context: context || {}, attachments: [],
                payloadAvailable: true, createdAt: "2026-10-09T12:00:00Z"})
            return id
        }
        function updateDraft(fields) {
            const value = Object.assign({}, draft, fields)
            if (encodeURIComponent(value.description).replace(/%[A-F\d]{2}/gi, "x").length > 8192) {
                errorCode = "invalid_description"
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
            saveRecord(Object.assign({}, value, {id: newId, isPublic: true, replyEmail: undefined, editable: true, state: "draft", receipt: "", uploadAuthorized: false, publicationState: "", removalState: "none"}))
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
        function previewSubmission() {
            previewDigest = JSON.stringify(draft)
            return Object.assign({}, draft, {digest: previewDigest, publicRepository: publicRepository,
                noticeText: noticeText, noticeRevision: noticeRevision, providerPolicyRevision: providerPolicyRevision})
        }
        function confirmSubmission(digest) {
            if (digest !== JSON.stringify(draft)) { errorCode = "preview_changed"; return false }
            ++submissions
            updateDraft({state: "queued", editable: false, uploadAuthorized: true})
            return true
        }
        function submit() { return confirmSubmission(JSON.stringify(draft)) }
        function requestRemoval(id) {
            ++removals
            updateDraft({removalState: "requested"})
            return true
        }
        function closeFeedback(id) {
            ++closures
            updateDraft({closureRequestState: "requested"})
            return true
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
        mock.configurationErrorCode = ""
        mock.noticeText = "Public test notice. No AI provider is enabled. Attachments are hosted by this local test service."
        mock.operationCode = ""; mock.operationRecordId = ""
        mock.nextId = 0; mock.submissions = 0; mock.removals = 0; mock.closures = 0; mock.previewDigest = ""; mock.stops = 0; mock.queries = 0; mock.deletions = 0
        mock.previewValue = ""; mock.attachedReport = ({}); crash.entries = []; crash.noticeId = ""
        mock.thread = ({}); mock.threadAttachmentPreview = ({}); mock.threadQueries = 0; mock.replyDrafts = 0
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
        tryCompare(findChild(workflow, "feedbackPublicationPreview"), "opened", true)
        compare(mock.submissions, 0)
        verify(!findChild(workflow, "feedbackPublish").enabled)
        mouseClick(findChild(workflow, "feedbackPublicConsent"))
        mouseClick(findChild(workflow, "feedbackPublish"))
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
    function publishedCase() {
        mock.saveRecord({id: "case-1", state: "accepted", isPublic: true, editable: false,
            category: "problem", description: "Original report", attachments: [], context: {},
            publicationState: "published", removalState: "none", receipt: "case-1"})
        mock.thread = {caseId: "case-1", workState: "needs-information", summary: "Need a public example",
            syncedAt: "2026-10-22T00:00:00Z", items: [], question: {id: "question-1", revision: 2,
                code: "expected_actual", description: "What did you expect, and what happened instead?",
                answerDeadline: "2020-01-01T00:00:00Z"}}
    }
    function revealInComposer(item) {
        const view = findChild(workflow, "feedbackComposer").contentItem
        view.contentY = Math.max(0, Math.min(view.contentHeight - view.height,
            item.mapToItem(view.contentItem, 0, 0).y - 20))
        wait(30)
    }
    function visualChild(item, name) {
        if (item.objectName === name) return item
        for (const child of item.children || []) {
            const found = visualChild(child, name)
            if (found) return found
        }
        return null
    }
    function test_developmentPhaseLabels_data() {
        const data = []
        for (const state of ["ready", "implementing", "verifying", "verified-awaiting-review",
                "reviewing", "verifying-integration", "merge-ready", "merging"])
            data.push({tag: state + "-en", state: state, language: "en", text: "The AI team is working on this"})
        for (const state of ["merged-awaiting-release", "source-published-awaiting-release"])
            data.push({tag: state + "-en", state: state, language: "en", text: "Awaiting release"})
        data.push({tag: "released-en", state: "released", language: "en", text: "Released"})
        data.push({tag: "deferred-en", state: "deferred", language: "en", text: "Deferred · see the assessment"})
        data.push({tag: "implementing-zh", state: "implementing", language: "zh", text: "AI 团队正在处理"})
        data.push({tag: "awaiting-release-zh", state: "merged-awaiting-release", language: "zh", text: "等待发版"})
        return data
    }
    function test_developmentPhaseLabels(data) {
        testTranslations.setLanguage(data.language)
        publishedCase()
        mock.thread = Object.assign({}, mock.thread, {workState: data.state, question: undefined})
        const label = findChild(workflow, "feedbackWorkState")
        tryCompare(label, "text", data.text)
        compare(label.textFormat, Text.PlainText)
        verify(findChild(workflow, "feedbackAddReply").enabled)
    }
    function test_specificQuestionUsesIntentionalPlainTextAndLegacyTemplateFallback() {
        testTranslations.setLanguage("zh")
        publishedCase()
        const label = findChild(workflow, "feedbackCurrentQuestion")
        const question = "这是哪张牌？请描述 <b>抓牌</b> 前后的操作。"
        mock.thread = Object.assign({}, mock.thread, {question: {id: "question-2", revision: 1,
            code: "custom", description: question}})
        compare(label.text, question)
        compare(label.textFormat, Text.PlainText)
        mock.thread = Object.assign({}, mock.thread, {question: {id: "question-3", revision: 1,
            code: "expected_actual", description: "Legacy English template"}})
        verify(label.text !== "Legacy English template")
        verify(label.text.length > 0)
    }
    function test_deliveryHistorySurvivesReassessmentAndSyncFailure() {
        publishedCase()
        mock.thread = Object.assign({}, mock.thread, {workState: "assessing", question: undefined,
            errorCode: "network_error", deliveryHistory: [{projectionId: "delivery-1",
                publishedAt: "2026-10-22T00:00:00Z", inputRevision: 1, workflowRevision: 3,
                outcome: {kind: "release", repository: "hexproof/feedback-test", version: "3.1.0"}}]})
        const thread = findChild(workflow, "feedbackThread")
        tryVerify(() => visualChild(thread, "feedbackDelivery-delivery-1") !== null)
        compare(findChild(workflow, "feedbackWorkState").text, "Assessing the report")
        verify(visualChild(thread, "feedbackDelivery-delivery-1").text.includes("3.1.0"))
        verify(!findChild(workflow, "feedbackCurrentOutcome").visible)
        verify(findChild(workflow, "feedbackThreadSync").text.includes("Last synced"))
        verify(findChild(workflow, "feedbackThreadConnection").text.length > 0)
        mock.thread = Object.assign({}, mock.thread, {outcome: {kind: "duplicate", issueNumber: 42}})
        compare(findChild(workflow, "feedbackCurrentOutcome").text, "Related public report #42")
    }
    function test_groupedHistoryRecoversExistingReplyDraft() {
        mock.records = []
        publishedCase()
        const replyId = mock.createReplyDraft("case-1", "", 0)
        mock.updateDraft({description: "Continue my unsent reply"})
        const reply = mock.draft
        mock.thread = Object.assign({}, mock.thread, {localReplies: [reply]})
        workflow.showHistory()
        const history = findChild(workflow, "feedbackHistoryList")
        tryCompare(history, "count", 1)
        tryVerify(() => visualChild(history, "feedbackHistoryCase-case-1") !== null)
        const caseAction = visualChild(history, "feedbackHistoryCase-case-1")
        waitForRendering(caseAction)
        mouseClick(caseAction)
        compare(mock.draft.id, "case-1")
        const composer = findChild(workflow, "feedbackComposer")
        tryVerify(() => visualChild(composer, "feedbackLocalReply-" + replyId) !== null)
        const action = visualChild(composer, "feedbackLocalReply-" + replyId)
        revealInComposer(action)
        mouseClick(action)
        compare(mock.draft.id, replyId)
        compare(mock.draft.description, "Continue my unsent reply")
        compare(mock.replyDrafts, 1)
        compare(mock.submissions, 0)
    }
    function test_localReplyDraftRemainsAccessibleDuringRemovalAndAfterParentDeletion() {
        mock.records = []
        publishedCase()
        const replyId = mock.createReplyDraft("case-1", "", 0)
        mock.updateDraft({description: "Keep this local draft", parentAvailable: true})
        const reply = mock.draft
        mock.selectRecord("case-1")
        mock.updateDraft({removalState: "pending"})
        mock.thread = Object.assign({}, mock.thread, {localReplies: [reply]})
        const composer = findChild(workflow, "feedbackComposer")
        tryVerify(() => visualChild(composer, "feedbackLocalReply-" + replyId) !== null)
        const action = visualChild(composer, "feedbackLocalReply-" + replyId)
        verify(action.visible)
        verify(!findChild(workflow, "feedbackThread").visible)
        mock.deleteRecord("case-1")
        mock.selectRecord(replyId)
        mock.updateDraft({parentAvailable: false})
        workflow.showHistory()
        const history = findChild(workflow, "feedbackHistoryList")
        tryCompare(history, "count", 1)
        tryVerify(() => visualChild(history, "feedbackHistoryCase-" + replyId) !== null)
        mouseClick(visualChild(history, "feedbackHistoryCase-" + replyId))
        compare(mock.draft.description, "Keep this local draft")
        verify(!findChild(workflow, "feedbackBackToCase").enabled)
    }
    function test_clarificationReplyRequiresItsOwnPublicPreview() {
        publishedCase()
        tryVerify(() => mock.threadQueries > 0)
        const answer = findChild(workflow, "feedbackAnswerQuestion")
        verify(answer.enabled, "Past clarification deadlines do not forbid a later reply")
        revealInComposer(answer)
        mouseClick(answer)
        compare(mock.replyDrafts, 1)
        compare(mock.draft.parentSubmissionId, "case-1")
        compare(mock.draft.questionId, "question-1")
        compare(mock.draft.questionRevision, 2)
        compare(mock.submissions, 0)
        const queries = mock.threadQueries
        wait(50)
        compare(mock.threadQueries, queries, "Editing a reply must not refresh its parent's conversation")
        findChild(workflow, "feedbackDescription").text = "Expected a visible card; the card stayed hidden."
        mouseClick(findChild(workflow, "feedbackSend"))
        tryCompare(findChild(workflow, "feedbackPublicationPreview"), "opened", true)
        const target = findChild(workflow, "feedbackPublicReplyTarget")
        verify(target.text.indexOf("case-1") >= 0)
        verify(target.text.indexOf(mock.draft.questionText) >= 0)
        verify(!findChild(workflow, "feedbackPublish").enabled)
        mouseClick(findChild(workflow, "feedbackPublicConsent"))
        mouseClick(findChild(workflow, "feedbackPublish"))
        compare(mock.submissions, 1)
        compare(mock.draft.parentSubmissionId, "case-1")
    }
    function test_threadUsesPlainTextAndRemovalStopsReplyActions() {
        publishedCase()
        mock.thread = Object.assign({}, mock.thread, {summary: "<b>Untrusted markup</b>"})
        compare(findChild(workflow, "feedbackAssessmentSummary").textFormat, Text.PlainText)
        verify(findChild(workflow, "feedbackAddReply").enabled)
        mock.thread = Object.assign({}, mock.thread, {replyAllowed: false})
        verify(!findChild(workflow, "feedbackAddReply").enabled)
        verify(!findChild(workflow, "feedbackAnswerQuestion").enabled)
        mock.thread = Object.assign({}, mock.thread, {replyAllowed: true})
        mock.saveRecord(Object.assign({}, mock.draft, {removalState: "pending"}))
        verify(!findChild(workflow, "feedbackAddReply").enabled)
        verify(!findChild(workflow, "feedbackAnswerQuestion").enabled)
        verify(!findChild(workflow, "feedbackThread").visible)
        mock.thread = {caseId: "another-case", summary: "Must not be displayed", items: []}
        compare(findChild(workflow, "feedbackAssessmentSummary").text, "")
    }
    function test_rootAttachmentCanBeReadAfterLocalContentPruning() {
        publishedCase()
        mock.saveRecord(Object.assign({}, mock.draft, {payloadAvailable: false}))
        mock.thread = Object.assign({}, mock.thread, {items: [{submissionId: "case-1", sequence: 1,
            kind: "submission", description: "Original report", publicationState: "published",
            attachments: [{id: "hosting", kind: "hosting_diagnostics", mediaType: "application/json"}]}]})
        const thread = findChild(workflow, "feedbackThread")
        compare(thread.entries.length, 1)
        compare(thread.entries[0].attachments.length, 1)
        tryVerify(() => visualChild(thread, "feedbackThreadAttachment-case-1-hosting") !== null)
        const button = visualChild(thread, "feedbackThreadAttachment-case-1-hosting")
        wait(50)
        revealInComposer(button)
        mouseClick(button)
        tryCompare(findChild(workflow, "feedbackAttachmentPreview"), "opened", true)
        compare(mock.submissions, 0)
    }
    function test_recentConversationIsReusedAndAttachmentFailuresAreVisible() {
        publishedCase()
        mock.thread = Object.assign({}, mock.thread, {syncedAt: new Date().toISOString()})
        wait(50)
        const queries = mock.threadQueries
        workflow.refreshConversation()
        wait(50)
        compare(mock.threadQueries, queries)
        workflow.pendingThreadAttachment = "case-1:hosting"
        mock.threadAttachmentPreview = {contributionId: "case-1", attachmentId: "hosting",
            loading: false, errorCode: "invalid_attachment", content: ""}
        mock.changed()
        compare(workflow.threadPreviewError, "invalid_attachment")
        verify(workflow.operationText().length > 0)
        verify(!findChild(workflow, "feedbackAttachmentPreview").opened)
        mock.saveRecord(Object.assign({}, mock.draft, {id: "another-case"}))
        compare(workflow.threadPreviewError, "")
    }
    function test_rejectedInputSurvivesAttachmentAndCategoryUpdates_data() {
        return [{tag:"description-over-8KiB", field:"feedbackDescription", key:"description",
                    value:"x".repeat(8193), corrected:"Corrected description", code:"invalid_description"}]
    }
    function test_rejectedInputSurvivesAttachmentAndCategoryUpdates(data) {
        findChild(workflow, "feedbackDescription").text = "Previously saved description"
        const field = findChild(workflow, data.field)
        const saved = mock.draft[data.key]
        field.text = data.value
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
        compare(mock.draft[data.key], data.corrected)
        compare(composer.inputErrorCode, "")
        verify(composer.inputMatchesRecord)
        verify(findChild(workflow, "feedbackSend").enabled)
        workflow.newDraft()
        compare(findChild(workflow, "feedbackDescription").text, "")
        compare(findChild(workflow, "feedbackEmail"), null)
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
    function test_publicPreviewShowsFrozenContentAndRequiresFreshConfirmation() {
        findChild(workflow, "feedbackDescription").text = "<b>Literal public report</b>"
        mock.updateDraft({context: {feature: "feedback_test", uiLanguage: "en"}})
        mock.attachCrashReport({revision: 1, summary: "Literal diagnostic"})
        mouseClick(findChild(workflow, "feedbackSend"))
        const preview = findChild(workflow, "feedbackPublicationPreview")
        tryCompare(preview, "opened", true)
        compare(mock.submissions, 0)
        verify(workflow.interactionOpen)
        compare(findChild(workflow, "feedbackPublicDescription").text, "<b>Literal public report</b>")
        compare(findChild(workflow, "feedbackPublicDescription").textFormat, TextEdit.PlainText)
        verify(findChild(workflow, "feedbackPublicContext").text.includes("feedback_test"))
        verify(findChild(workflow, "feedbackPublicNoticeLink").enabled)
        verify(!findChild(workflow, "feedbackNotice").visible)
        const frozenNotice = mock.noticeText
        mock.noticeText = "A later service notice must not replace this preview."
        waitForRendering(findChild(workflow, "feedbackPublicNoticeLink"))
        mouseClick(findChild(workflow, "feedbackPublicNoticeLink"))
        tryCompare(findChild(workflow, "feedbackNotice"), "opened", true)
        compare(findChild(workflow, "feedbackNoticeText").text, frozenNotice)
        compare(findChild(workflow, "feedbackNoticeText").textFormat, TextEdit.PlainText)
        verify(!findChild(workflow, "feedbackPublicConsent").checked)
        compare(mock.submissions, 0)
        mouseClick(findChild(workflow, "feedbackNoticeClose"))
        tryCompare(findChild(workflow, "feedbackNotice"), "visible", false)
        verify(preview.visible)
        verify(!findChild(workflow, "feedbackPublish").enabled)
        verify(findChild(workflow, "feedbackPublicDestination").text.includes(mock.publicRepository))
        const attachments = findChild(workflow, "feedbackPublicAttachments")
        compare(attachments.count, 1)
        compare(findChild(attachments.itemAt(0), "feedbackPublicAttachment-crash").text, mock.previewValue)
        verify(!findChild(workflow, "feedbackPublish").enabled)
        mouseClick(findChild(workflow, "feedbackPublicConsent"))
        mock.updateDraft({description: "Changed after preview"})
        compare(findChild(workflow, "feedbackPublicDescription").text, "<b>Literal public report</b>")
        mouseClick(findChild(workflow, "feedbackPublish"))
        compare(mock.submissions, 0)
        compare(mock.errorCode, "preview_changed")
        verify(preview.visible)
        mouseClick(findChild(workflow, "feedbackPublicationCancel"))
        tryCompare(preview, "visible", false)
        compare(findChild(workflow, "feedbackPublicConsent").checked, false)
    }
    function test_fullNoticeIsAvailableOfflineAndDoesNotAuthorizePublication() {
        mock.noticeText = "<b>Full notice stays literal and scrollable.</b>\n".repeat(60)
        compare(mock.privacyUrl, "")
        verify(findChild(workflow, "feedbackPrivacyLink").visible)
        const button = findChild(workflow, "feedbackPrivacyLink")
        waitForRendering(button)
        mouseClick(button)
        const notice = findChild(workflow, "feedbackNotice")
        tryCompare(notice, "opened", true)
        compare(findChild(workflow, "feedbackNoticeText").text, mock.noticeText)
        verify(findChild(workflow, "feedbackNoticeText").readOnly)
        verify(findChild(workflow, "feedbackNoticeText").selectByMouse)
        tryVerify(() => findChild(workflow, "feedbackNoticeScroll").contentItem.contentHeight
                  > findChild(workflow, "feedbackNoticeScroll").height)
        compare(mock.submissions, 0)
        verify(workflow.interactionOpen)
        findChild(workflow, "feedbackDialog").close()
        tryCompare(notice, "visible", false)
        tryCompare(workflow, "interactionOpen", false)
    }
    function test_cancelledPreviewDoesNotAuthorizePublication() {
        findChild(workflow, "feedbackDescription").text = "Keep as draft"
        mouseClick(findChild(workflow, "feedbackSend"))
        tryCompare(findChild(workflow, "feedbackPublicationPreview"), "opened", true)
        mouseClick(findChild(workflow, "feedbackPublicConsent"))
        mouseClick(findChild(workflow, "feedbackPublicationCancel"))
        compare(mock.submissions, 0)
        compare(mock.draft.state, "draft")
        mouseClick(findChild(workflow, "feedbackSend"))
        tryCompare(findChild(workflow, "feedbackPublicationPreview"), "opened", true)
        verify(!findChild(workflow, "feedbackPublicConsent").checked)
        verify(!findChild(workflow, "feedbackPublish").enabled)
    }
    function test_legacyPrivateRecordRequiresNewPublicDraft() {
        mock.updateDraft({isPublic: false, replyEmail: "private@example.test", description: "Old private draft"})
        verify(findChild(workflow, "feedbackLegacyNotice").visible)
        verify(!findChild(workflow, "feedbackSend").visible)
        verify(findChild(workflow, "feedbackDescription").readOnly)
        compare(findChild(workflow, "feedbackEmail"), null)
        const originalId = mock.draft.id
        findChild(workflow, "feedbackComposer").cloneRequested()
        const confirmation = findChild(workflow, "feedbackCloneConfirmation")
        tryCompare(confirmation, "opened", true)
        compare(mock.submissions, 0)
        confirmation.confirmed()
        confirmation.close()
        verify(mock.draft.isPublic)
        verify(mock.draft.id !== originalId)
        compare(mock.draft.replyEmail, undefined)
        compare(mock.draft.description, "Old private draft")
        compare(mock.submissions, 0)
        verify(findChild(workflow, "feedbackSend").visible)
    }
    function test_publicationAndRemovalHaveIndependentVisibleStates() {
        mock.updateDraft({description: "Accepted report", state: "accepted", editable: false,
            receipt: "receipt-1", publicationState: "pending", removalState: "none"})
        const meaning = findChild(workflow, "feedbackPublicationMeaning")
        verify(meaning.visible && meaning.text.includes("pending"))
        verify(findChild(workflow, "feedbackCheckReceipt").visible)
        for (const state of ["stalled", "partial", "published", "rejected"]) {
            mock.updateDraft({publicationState: state})
            verify(meaning.text.length > 0)
        }
        mock.updateDraft({publicationState: "pending"})
        findChild(workflow, "feedbackComposer").removalRequested()
        const confirmation = findChild(workflow, "feedbackRemovalConfirmation")
        tryCompare(confirmation, "opened", true)
        compare(mock.removals, 0)
        compare(mock.deletions, 0)
        confirmation.confirmed()
        confirmation.close()
        compare(mock.removals, 1)
        compare(mock.deletions, 0)
        verify(findChild(workflow, "feedbackRemovalMeaning").visible)
        verify(!findChild(workflow, "feedbackRequestRemoval").visible)
        verify(!meaning.visible)
        mock.updateDraft({removalState: "stalled"})
        verify(findChild(workflow, "feedbackRemovalMeaning").text.includes("not yet confirmed"))
        mock.updateDraft({removalState: "removed"})
        verify(findChild(workflow, "feedbackRemovalMeaning").text.includes("Third-party"))
        verify(findChild(workflow, "feedbackDelete").enabled)
    }
    function test_closeFeedbackRetainsHistoryAndIsDistinctFromContentRemoval() {
        publishedCase()
        const closeAction = findChild(workflow, "feedbackCloseCase")
        const removeAction = findChild(workflow, "feedbackRequestRemoval")
        verify(closeAction.visible && removeAction.visible)
        compare(closeAction.text, "Close feedback")
        compare(removeAction.text, "Request content removal")
        findChild(workflow, "feedbackComposer").closureRequested()
        const confirmation = findChild(workflow, "feedbackClosureConfirmation")
        tryCompare(confirmation, "opened", true)
        verify(confirmation.message.includes("history and attachments"))
        verify(confirmation.message.includes("sensitive content"))
        compare(mock.closures, 0)
        compare(mock.removals, 0)
        confirmation.confirmed()
        confirmation.close()
        compare(mock.closures, 1)
        compare(mock.removals, 0)
        compare(mock.deletions, 0)
        verify(findChild(workflow, "feedbackClosureMeaning").text.includes("saved on this device"))
        verify(!findChild(workflow, "feedbackAddReply").enabled)
        mock.updateDraft({caseState: "closed", closureRequestState: "none", closurePublicationState: "pending"})
        verify(!closeAction.visible)
        verify(removeAction.visible)
        verify(findChild(workflow, "feedbackThread").visible)
        compare(mock.draft.description, "Original report")
        verify(findChild(workflow, "feedbackClosureMeaning").text.includes("Public issue closure is pending"))
        mock.updateDraft({closurePublicationState: "stalled"})
        verify(findChild(workflow, "feedbackClosureMeaning").text.includes("delayed"))
        findChild(workflow, "feedbackComposer").removalRequested()
        const removal = findChild(workflow, "feedbackRemovalConfirmation")
        tryCompare(removal, "opened", true)
        verify(removal.message.includes("AI task history may still await cleanup"))
        compare(mock.removals, 0)
        removal.confirmed()
        removal.close()
        compare(mock.removals, 1)
        compare(mock.closures, 1)
    }
    function test_delayedCloseCanRetryWhileContentRemovalRemainsAvailable() {
        publishedCase()
        mock.updateDraft({closureRequestState: "stalled"})
        const action = findChild(workflow, "feedbackCloseCase")
        verify(action.visible && action.enabled)
        compare(action.text, "Retry closing feedback")
        verify(findChild(workflow, "feedbackClosureMeaning").text.includes("could not be confirmed"))
        verify(findChild(workflow, "feedbackRequestRemoval").visible)
        verify(!findChild(workflow, "feedbackAddReply").enabled)
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
    function test_configurationMessageSurvivesDraftLifecycle_data() {
        return [
            {tag: "invalid-en", invalid: true, language: "en",
                expected: "Online submission is unavailable because the feedback configuration is invalid. You can save or export a draft."},
            {tag: "invalid-zh", invalid: true, language: "zh",
                expected: "反馈配置无效，无法在线提交。你仍可保存或导出草稿。"},
            {tag: "disabled-en", invalid: false, language: "en",
                expected: "Online submission is not enabled in this build. You can save or export a draft."},
            {tag: "disabled-zh", invalid: false, language: "zh",
                expected: "当前版本尚未开放在线提交。你仍可保存或导出草稿。"}
        ]
    }
    function test_configurationMessageSurvivesDraftLifecycle(data) {
        const service = data.invalid ? testInvalidFeedbackService : testDisabledFeedbackService
        tryCompare(service, "saving", false)
        for (const record of service.records) verify(service.deleteRecord(record.id))
        tryCompare(service, "saving", false)
        const dialog = findChild(workflow, "feedbackDialog")
        dialog.close()
        tryCompare(dialog, "opened", false)
        workflow.service = service
        testTranslations.setLanguage(data.language)
        workflow.openFor({}, "", {})
        tryCompare(dialog, "opened", true)
        const footer = findChild(workflow, "feedbackAvailability")
        const id = service.draft.id
        verify(String(id).length > 0)
        compare(service.errorCode, "")
        compare(footer.text, data.expected)
        verify(!findChild(workflow, "feedbackSend").enabled)

        findChild(workflow, "feedbackDescription").text = "Keep configuration diagnosis"
        tryCompare(service, "saving", false)
        compare(service.draft.description, "Keep configuration diagnosis")
        compare(footer.text, data.expected)
        verify(!service.updateDraft({description: "x".repeat(8193)}))
        compare(service.errorCode, "invalid_description")
        compare(footer.text, data.expected)
        workflow.newDraft()
        verify(service.draft.id !== id)
        verify(service.selectRecord(id))
        compare(service.errorCode, "")
        compare(findChild(workflow, "feedbackDescription").text, "Keep configuration diagnosis")
        compare(footer.text, data.expected)
        verify(findChild(workflow, "feedbackExport").enabled)

        dialog.close()
        tryCompare(dialog, "opened", false)
        workflow.openFor({}, "", {})
        tryCompare(dialog, "opened", true)
        compare(footer.text, data.expected)
        tryCompare(service, "saving", false)
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
        const receiver = findChild(workflow, "feedbackPrivacySummary")
        const meaning = findChild(workflow, "feedbackReceivedMeaning")
        const local = findChild(workflow, "feedbackReceivedLocalRetention")
        verify(receiver.visible)
        verify(receiver.text.includes("public") && receiver.text.includes("AI"))
        verify(!meaning.visible && !local.visible)
        compare(findChild(workflow, "feedbackSend").variant, "primary")
        findChild(workflow, "feedbackDescription").text = "Notice state test"
        mock.submit()
        verify(receiver.visible && !meaning.visible && !local.visible)
        mock.updateDraft({state:"accepted", receipt:"receipt-1", uploadAuthorized:false,
            accessExpiresAt:"2027-10-22T12:00:00Z"})
        verify(receiver.visible)
        verify(!meaning.visible && !local.visible)
        const composer = findChild(workflow, "feedbackComposer")
        composer.showOriginal = true
        verify(meaning.visible && local.visible)
        verify(meaning.text.includes("storage") && meaning.text.includes("separate steps"))
        verify(local.text.includes("30 days") && local.text.includes("deleting it loses access"))
        verify(!local.text.includes("90 days"))
        verify(findChild(workflow, "feedbackReceiptAccess").visible)
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
    function test_recoveryExplainsScheduledRetryAndStoppedUncertainty() {
        mock.updateDraft({state: "queued", editable: false, uploadAuthorized: true,
            automaticRetryPending: true, reason: "network_error"})
        const hint = findChild(workflow, "feedbackRecoveryHint")
        verify(hint.visible && hint.text.includes("retry automatically"))
        mock.updateDraft({nextAttempt: "2026-10-26T00:00:00Z"})
        verify(hint.text.includes("no earlier than") && hint.text.includes("running"))
        mock.updateDraft({state: "unconfirmed"})
        verify(hint.text.includes("automatically check") && hint.text.includes("Do not submit another copy"))
        mock.stop(mock.draft.id)
        mock.updateDraft({automaticRetryPending: false})
        verify(hint.text.includes("Delivery is uncertain") && !hint.text.includes("automatically"))
        const check = findChild(workflow, "feedbackCheckReceipt")
        compare(check.text, "Check status")
        mouseClick(check)
        compare(mock.queries, 1)
        compare(mock.submissions, 0)
        mock.errorCode = "storage_unavailable"
        verify(!hint.visible)
    }
    function test_historyDoesNotStartDetailRefreshOrShowDraftErrors() {
        mock.updateDraft({state: "accepted", editable: false})
        wait(10)
        const before = mock.threadQueries
        workflow.showHistory()
        mock.errorCode = "network_error"
        workflow.refreshConversation()
        wait(10)
        compare(mock.threadQueries, before)
        verify(!findChild(workflow, "feedbackError").visible)
        verify(!findChild(workflow, "feedbackRecoveryHint").visible)
        mouseClick(findChild(workflow, "feedbackClose"))
        tryCompare(findChild(workflow, "feedbackHistory"), "active", false)
    }
    function test_openingCaseDuringHistoryRefreshReusesItsCompletedSnapshot() {
        workflow.showHistory()
        mock.busy = true
        mock.updateDraft({state: "accepted", editable: false})
        workflow.historyVisible = false
        verify(workflow.pendingThreadCaseId === mock.draft.id)
        const before = mock.threadQueries
        mock.thread = {caseId: mock.draft.id, syncedAt: new Date().toISOString(), items: []}
        mock.busy = false
        tryCompare(workflow, "pendingThreadCaseId", "")
        compare(mock.threadQueries, before)
        compare(mock.errorCode, "")
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
        mouseClick(findChild(workflow, "feedbackSend"))
        tryCompare(findChild(workflow, "feedbackPublicationPreview"), "opened", true)
        tryVerify(function() { return findChild(workflow, "feedbackPublicationScroll").height > 0 })
        for (const name of ["feedbackPublicConsent", "feedbackPublish", "feedbackPublicationCancel"]) {
            const control = findChild(workflow, name)
            const pos = control.mapToItem(testWindow.contentItem, 0, 0)
            verify(pos.x >= 0 && pos.y >= 0, name)
            verify(pos.x + control.width <= testWindow.width, name + " width")
            verify(pos.y + control.height <= testWindow.height, name + " height")
        }
        waitForRendering(findChild(workflow, "feedbackPublicNoticeLink"))
        mouseClick(findChild(workflow, "feedbackPublicNoticeLink"))
        tryCompare(findChild(workflow, "feedbackNotice"), "opened", true)
        const noticeClose = findChild(workflow, "feedbackNoticeClose")
        const noticePos = noticeClose.mapToItem(testWindow.contentItem, 0, 0)
        verify(noticePos.x >= 0 && noticePos.y >= 0)
        verify(noticePos.x + noticeClose.width <= testWindow.width)
        verify(noticePos.y + noticeClose.height <= testWindow.height)
        mouseClick(noticeClose)
        tryCompare(findChild(workflow, "feedbackNotice"), "visible", false)
        mouseClick(findChild(workflow, "feedbackPublicationCancel"))
        mouseClick(findChild(workflow, "feedbackHistoryButton"))
        verify(workflow.historyVisible)
        tryVerify(function() { return findChild(workflow, "feedbackHistoryList").height > 0 })
    }
}
