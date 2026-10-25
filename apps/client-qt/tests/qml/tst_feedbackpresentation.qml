// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors
import QtQuick
import QtQuick.Controls.Basic
import QtTest
import "../../qml/components"

TestCase {
    id: testCase
    name: "FeedbackPresentation"
    when: windowShown
    readonly property string imageData: "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
    ApplicationWindow {
        id: testWindow
        width: 900
        height: 800
        visible: true
    }
    QtObject {
        id: mock
        property var draft: ({})
        property var thread: ({})
        property bool enabled: true
        property bool busy: false
        property bool saving: false
        property string errorCode: ""
        property int previewCalls: 0
        property string previewValue: testCase.imageData
        function updateDraft(fields) { draft = Object.assign({}, draft, fields); return true }
        function attachmentPreview(id) { ++previewCalls; return previewValue }
    }
    Component { id: composerComponent; FeedbackComposer { service: mock; width: 800; height: 700 } }
    SignalSpy { id: previewSpy; signalName: "previewRequested" }
    property var composer: null

    function init() {
        testTranslations.setLanguage("en")
        mock.draft = {id: "case-1", isPublic: true, state: "draft", editable: true,
            category: "problem", description: "Example", attachments: [], context: {}, payloadAvailable: true}
        mock.thread = ({})
        mock.previewCalls = 0
        mock.previewValue = imageData
        composer = null
        previewSpy.target = null
        previewSpy.clear()
    }
    function cleanup() {
        previewSpy.target = null
        if (composer) composer.destroy()
        composer = null
        testTranslations.setLanguage("en")
    }
    function createComposer() {
        composer = composerComponent.createObject(testWindow.contentItem)
        verify(composer !== null)
        verify(waitForPolish(testWindow))
        return composer
    }
    function visualChild(item, name) {
        if (item.objectName === name) return item
        for (const child of item.children || []) {
            const found = visualChild(child, name)
            if (found) return found
        }
        return null
    }
    function reveal(item) {
        const view = composer.contentItem
        view.contentY = Math.max(0, Math.min(view.contentHeight - view.height,
            item.mapToItem(view.contentItem, 0, 0).y - 20))
        verify(waitForPolish(testWindow))
    }
    function screenshot() {
        return {id: "image-1", kind: "screenshot", mediaType: "image/png", byteLength: 68, sha256: "a"}
    }
    function acceptedCase() {
        mock.updateDraft({state: "accepted", editable: false, receipt: "receipt-1",
            publicationState: "published", removalState: "none", caseState: "open"})
        mock.thread = {caseId: "case-1", workState: "needs-information", summary: "Please add a reproduction.",
            syncedAt: "2026-10-25T01:00:00Z", items: [], replyAllowed: true,
            question: {id: "question-1", revision: 1, code: "custom", description: "Which card was involved?"}}
    }

    function test_acceptedCaseLeadsWithProgressAndKeepsOriginalAndReceiptReachable() {
        acceptedCase()
        createComposer()
        const original = findChild(composer, "feedbackOriginalContent")
        const toggle = findChild(composer, "feedbackOriginalToggle")
        const summary = findChild(composer, "feedbackAssessmentSummary")
        const question = findChild(composer, "feedbackCurrentQuestion")
        verify(!original.visible)
        verify(summary.visible && question.visible)
        verify(question.mapToItem(composer, 0, 0).y < toggle.mapToItem(composer, 0, 0).y)
        reveal(toggle)
        mouseClick(toggle)
        tryCompare(original, "visible", true)
        verify(findChild(composer, "feedbackDescription").readOnly)
        verify(findChild(composer, "feedbackReceivedMeaning").visible)
        verify(findChild(composer, "feedbackReceivedLocalRetention").visible)
        verify(findChild(composer, "feedbackCloseCase").visible)
        verify(findChild(composer, "feedbackRequestRemoval").visible)
        compare(mock.draft.description, "Example")
    }

    function test_replyQuestionPrecedesEditableAnswer() {
        mock.updateDraft({isReply: true, parentSubmissionId: "parent-1", parentAvailable: true,
            questionCode: "custom", questionText: "Which card was involved?"})
        createComposer()
        const question = findChild(composer, "feedbackReplyQuestion")
        const description = findChild(composer, "feedbackDescription")
        verify(question.visible && description.visible && !description.readOnly)
        verify(question.mapToItem(composer, 0, 0).y < description.mapToItem(composer, 0, 0).y)
        verify(!findChild(composer, "feedbackOriginalToggle").visible)
    }

    function test_unsyncedLoadingAndVerifiedAssessmentAreDistinct() {
        acceptedCase()
        mock.thread = {caseId: "case-1", items: []}
        createComposer()
        const state = findChild(composer, "feedbackWorkState")
        compare(state.text, "Not synced yet")
        mock.thread = {caseId: "case-1", loading: true, items: []}
        tryCompare(state, "text", "Refreshing conversation…")
        mock.thread = {caseId: "case-1", workState: "new", syncedAt: "2026-10-25T01:00:00Z", items: []}
        tryCompare(state, "text", "Awaiting assessment")
    }

    function test_newestConversationEntriesHaveTimestampsWithoutChangingCachedOrder() {
        acceptedCase()
        mock.thread = Object.assign({}, mock.thread, {items: [
            {submissionId: "old", kind: "assessment", description: "Earlier progress", publicationState: "published",
                acceptedAt: "2026-10-24T01:00:00Z", publishedAt: "2026-10-24T01:01:00Z"},
            {submissionId: "new", kind: "reply", description: "More evidence", publicationState: "pending",
                acceptedAt: "2026-10-25T01:00:00Z"}]})
        createComposer()
        const thread = findChild(composer, "feedbackThread")
        tryVerify(() => visualChild(thread, "feedbackThreadEntry-new") !== null)
        const newer = visualChild(thread, "feedbackThreadEntry-new")
        const older = visualChild(thread, "feedbackThreadEntry-old")
        verify(newer.mapToItem(thread, 0, 0).y < older.mapToItem(thread, 0, 0).y)
        verify(visualChild(thread, "feedbackThreadEntryStatus-new").text.includes("2026"))
        verify(visualChild(thread, "feedbackThreadEntryStatus-old").text.includes("2026"))
        compare(mock.thread.items[0].submissionId, "old")
    }

    function test_localThumbnailIsPreviewableAndNotReencodedWhileTyping() {
        mock.updateDraft({attachments: [screenshot()]})
        createComposer()
        tryCompare(mock, "previewCalls", 1)
        const image = visualChild(composer, "feedbackThumbnailImage-image-1")
        verify(image !== null)
        tryCompare(image, "status", Image.Ready)
        compare(String(image.source), imageData)
        for (let index = 0; index < 8; ++index)
            mock.updateDraft({description: "Typing " + index, attachments: [screenshot()]})
        compare(mock.previewCalls, 1)
        previewSpy.target = composer
        const thumbnail = visualChild(composer, "feedbackThumbnail-image-1")
        reveal(thumbnail)
        mouseClick(thumbnail)
        compare(previewSpy.count, 1)
        compare(previewSpy.signalArguments[0][0], "image-1")
        verify(findChild(composer, "feedbackImageLimit").text.includes("two"))
    }

    function test_privateRemovedOrPurgedImagesAreNotLoaded_data() {
        return [{tag: "private", changes: {isPublic: false}},
            {tag: "removing", changes: {removalState: "requested"}},
            {tag: "removed", changes: {removalState: "removed"}},
            {tag: "purged", changes: {payloadAvailable: false}}]
    }
    function test_privateRemovedOrPurgedImagesAreNotLoaded(data) {
        mock.updateDraft(Object.assign({attachments: [screenshot()]}, data.changes))
        createComposer()
        compare(mock.previewCalls, 0)
        const thumbnail = visualChild(composer, "feedbackThumbnail-image-1")
        verify(thumbnail !== null && !thumbnail.visible)
        compare(String(visualChild(composer, "feedbackThumbnailImage-image-1").source), "")
    }

    function test_existingThumbnailClearsWhenRemovalStarts() {
        mock.updateDraft({attachments: [screenshot()]})
        createComposer()
        tryCompare(mock, "previewCalls", 1)
        mock.updateDraft({removalState: "requested"})
        const image = visualChild(composer, "feedbackThumbnailImage-image-1")
        tryCompare(image, "source", "")
        verify(!visualChild(composer, "feedbackThumbnail-image-1").visible)
    }

    function test_threadAttachmentsCanBeRemovedWhileNetworkBusyChanges() {
        acceptedCase()
        mock.thread = Object.assign({}, mock.thread, {items: [{submissionId: "case-1",
            kind: "submission", publicationState: "published", attachments: [screenshot()]}]})
        createComposer()
        verify(visualChild(composer, "feedbackThreadAttachment-case-1-image-1") !== null)
        mock.busy = true
        mock.thread = Object.assign({}, mock.thread, {items: [], removalState: "removed"})
        mock.busy = false
        wait(10) // Deferred delegate destruction must not produce engine warnings.
        verify(visualChild(composer, "feedbackThreadAttachment-case-1-image-1") === null)
    }

    function test_externalPreviewUrlNeverBecomesImageSource() {
        mock.previewValue = "https://example.invalid/image.png"
        mock.updateDraft({attachments: [screenshot()]})
        createComposer()
        compare(mock.previewCalls, 1)
        compare(String(visualChild(composer, "feedbackThumbnailImage-image-1").source), "")
        verify(!visualChild(composer, "feedbackThumbnail-image-1").visible)
    }
}
