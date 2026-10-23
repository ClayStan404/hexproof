// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors
pragma ComponentBehavior: Bound
pragma Translator: "Feedback"
import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Dialogs
import QtQuick.Layouts
import "FeedbackLabels.js" as Labels

Item {
    id: root
    objectName: "feedbackWorkflow"
    property var service: null
    property var crashService: null
    property var hostingService: null
    property var baseContext: ({})
    property bool inGame: false
    property bool historyVisible: false
    property var pendingContext: ({})
    property string pendingKind: ""
    property var pendingSnapshot: ({})
    property string exportId: ""
    property string confirmRecordId: ""
    property string pendingThreadCaseId: ""
    property string pendingThreadAttachment: ""
    property string pendingThreadAttachmentTitle: ""
    property string threadPreviewError: ""
    readonly property var record: service ? service.draft : ({})
    readonly property string caseId: String(record.parentSubmissionId || record.id || "")
    readonly property bool threadEligible: record.isPublic === true && record.state === "accepted" && record.isReply !== true
    readonly property bool editable: record.isPublic === true && (record.editable === true || record.state === "draft")
    readonly property bool interactionOpen: panel.visible || imageDialog.visible || exportDialog.visible
        || preview.visible || chooseCrash.visible || contextChoice.visible || deleteConfirmation.visible
        || cloneConfirmation.visible || publicationPreview.visible || removalConfirmation.visible || closureConfirmation.visible
    signal finished()
    onCaseIdChanged: {
        pendingThreadAttachment = ""
        threadPreviewError = ""
        refreshConversation()
    }
    onThreadEligibleChanged: refreshConversation()

    function refreshConversation() {
        if (!panel || !panel.visible || !threadEligible || !service || typeof service.refreshThread !== "function") return
        const cached = service.thread || {}
        if (cached.caseId === caseId && cached.syncedAt && Date.now() - Date.parse(cached.syncedAt) < 5000) return
        pendingThreadCaseId = caseId
        Qt.callLater(flushThreadRequest)
    }
    function flushThreadRequest() {
        if (!pendingThreadCaseId || !service || service.busy || service.saving) return
        const id = pendingThreadCaseId
        pendingThreadCaseId = ""
        if (id === caseId && threadEligible && panel.visible) service.refreshThread(id)
    }
    function refreshStatus() {
        service.queryReceipt(record.id)
        refreshConversation()
    }
    function createReply(questionId, revision) {
        if (service && typeof service.createReplyDraft === "function")
            service.createReplyDraft(caseId, questionId, revision)
    }
    function showThreadAttachment(contributionId, attachmentId, title) {
        if (!service || typeof service.fetchThreadAttachment !== "function") return
        threadPreviewError = ""
        pendingThreadAttachment = contributionId + ":" + attachmentId
        pendingThreadAttachmentTitle = title
        if (!service.fetchThreadAttachment(contributionId, attachmentId)) pendingThreadAttachment = ""
    }
    function finishThreadPreview() {
        const value = service ? service.threadAttachmentPreview || {} : {}
        if (value.loading || !pendingThreadAttachment
            || pendingThreadAttachment !== value.contributionId + ":" + value.attachmentId) return
        pendingThreadAttachment = ""
        threadPreviewError = value.errorCode || ""
        if (!value.errorCode && value.content) {
            preview.titleText = pendingThreadAttachmentTitle
            preview.previewContent = value.content
            preview.open()
        }
    }
    Connections {
        target: root.service
        ignoreUnknownSignals: true
        function onChanged() {
            Qt.callLater(root.flushThreadRequest)
            root.finishThreadPreview()
        }
        function onStatusChanged() { Qt.callLater(root.flushThreadRequest) }
    }

    function openFor(context, kind, snapshot) {
        if (!service) return
        pendingContext = Object.assign({}, baseContext, context || {})
        pendingKind = kind || ""
        // Keep the user's explicitly selected revision even if the source changes.
        pendingSnapshot = JSON.parse(JSON.stringify(snapshot || {}))
        historyVisible = false
        panel.open()
        if (record.id && editable) {
            if (pendingKind || Object.keys(context || {}).length > 0) contextChoice.open()
            return
        }
        createPendingDraft()
    }
    function createPendingDraft() {
        if (service.createDraft(pendingContext)) applyPending(false)
    }
    function applyPending(mergeContext) {
        if (mergeContext && Object.keys(pendingContext).length)
            service.updateDraft({context: Object.assign({}, record.context || {}, pendingContext)})
        if (pendingKind === "crash") service.attachCrashReport(pendingSnapshot)
        if (pendingKind === "hosting") service.attachHostingDiagnostics(pendingSnapshot)
        pendingContext = ({})
        pendingKind = ""
        pendingSnapshot = ({})
    }
    function newDraft() {
        pendingContext = ({})
        pendingKind = ""
        pendingSnapshot = ({})
        if (service.createDraft(baseContext)) historyVisible = false
    }
    function showHistory() {
        historyVisible = true
        panel.open()
    }
    function openPreview(id, title) {
        preview.titleText = title
        preview.previewContent = service.attachmentPreview(id)
        preview.open()
    }
    function exportCurrent() {
        exportId = record.id || ""
        exportDialog.selectedFile = service.suggestedExport(exportId)
        exportDialog.open()
    }
    function reviewPublication() {
        const snapshot = service.previewSubmission()
        if (!snapshot || !snapshot.digest) return
        // Hold the normalized snapshot shown to the user; later editor changes
        // invalidate confirmation in the service rather than updating this view.
        const prepared = JSON.parse(JSON.stringify(snapshot))
        prepared.attachments = (prepared.attachments || []).map(value =>
            Object.assign({}, value, {previewContent: service.attachmentPreview(value.id)}))
        publicationPreview.snapshot = prepared
        publicationPreview.open()
    }
    function showCrashPicker() {
        if (crashService && typeof crashService.refresh === "function") crashService.refresh()
        chooseCrash.open()
    }
    function attachHosting() {
        if (hostingService && typeof hostingService.diagnosticsReport === "function")
            service.attachHostingDiagnostics(hostingService.diagnosticsReport())
    }
    function operationText() {
        if (threadPreviewError) return Labels.error(threadPreviewError)
        if (!service || service.operationRecordId !== record.id) return ""
        switch (service.operationCode) {
        case "copied": return qsTr("Receipt copied.")
        case "exported": return qsTr("Feedback exported.")
        default: return Labels.error(service.operationCode || "")
        }
    }

    AppPopup {
        id: panel
        objectName: "feedbackDialog"
        width: parent ? Math.min(Theme.size(840), parent.width - Theme.size(32)) : 0
        height: parent ? Math.min(Theme.size(850), parent.height - Theme.size(32)) : 0
        padding: Theme.size(20)
        z: 300
        closePolicy: Popup.CloseOnEscape
        onOpened: root.refreshConversation()
        onClosed: {
            root.pendingThreadCaseId = ""
            root.pendingThreadAttachment = ""
            root.finished()
        }
        contentItem: ColumnLayout {
            spacing: Theme.size(10)
            RowLayout {
                Layout.fillWidth: true
                Text {
                    Layout.fillWidth: true
                    textFormat: Text.PlainText
                    text: root.historyVisible ? qsTr("My feedback") : qsTr("Feedback")
                    color: Theme.text
                    font.pixelSize: Theme.fontSize(24)
                    font.weight: Font.DemiBold
                }
                AppButton {
                    objectName: "feedbackHistoryButton"
                    text: root.historyVisible ? qsTr("New feedback") : qsTr("My feedback")
                    compact: true
                    variant: "secondary"
                    onClicked: root.historyVisible ? root.newDraft() : root.showHistory()
                }
                AppButton {
                    objectName: "feedbackClose"
                    text: qsTr("Close")
                    compact: true
                    variant: "ghost"
                    onClicked: panel.close()
                }
            }
            Text {
                Layout.fillWidth: true
                visible: root.inGame
                textFormat: Text.PlainText
                text: qsTr("The game and its clock continue while feedback is open.")
                color: Theme.warning
                font.pixelSize: Theme.fontSize(12)
                wrapMode: Text.WordWrap
            }
            FeedbackHistory {
                objectName: "feedbackHistory"
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: root.historyVisible
                service: root.service
                onRecordRequested: id => {
                    root.service.selectRecord(id)
                    root.historyVisible = false
                }
            }
            RowLayout {
                objectName: "feedbackNewCrashHint"
                Layout.fillWidth: true
                visible: !root.historyVisible && root.editable && root.crashService
                    && !!root.crashService.noticeId
                Text {
                    Layout.fillWidth: true
                    textFormat: Text.PlainText
                    text: qsTr("New Forge crash report available.")
                    color: Theme.warning
                    font.pixelSize: Theme.fontSize(12)
                    wrapMode: Text.WordWrap
                }
                AppButton {
                    objectName: "feedbackNewCrashChoose"
                    text: qsTr("Choose crash report")
                    variant: "secondary"
                    compact: true
                    onClicked: root.showCrashPicker()
                }
            }
            FeedbackComposer {
                id: composer
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: !root.historyVisible && !!root.record.id
                service: root.service
                hostingAvailable: root.hostingService && typeof root.hostingService.diagnosticsReport === "function"
                onImageRequested: imageDialog.open()
                onCrashRequested: root.showCrashPicker()
                onHostingRequested: root.attachHosting()
                onPreviewRequested: (id, title) => root.openPreview(id, title)
                onExportRequested: root.exportCurrent()
                onDeleteRequested: {
                    root.confirmRecordId = root.record.id
                    deleteConfirmation.open()
                }
                onCloneRequested: {
                    root.confirmRecordId = root.record.id
                    cloneConfirmation.open()
                }
                onRemovalRequested: {
                    root.confirmRecordId = root.record.id
                    removalConfirmation.open()
                }
                onClosureRequested: {
                    root.confirmRecordId = root.record.id
                    closureConfirmation.open()
                }
                onReplyRequested: (questionId, revision) => root.createReply(questionId, revision)
                onRecordRequested: recordId => root.service.selectRecord(recordId)
                onThreadAttachmentRequested: (contributionId, attachmentId, title) => root.showThreadAttachment(contributionId, attachmentId, title)
                onParentRequested: root.service.selectRecord(root.record.parentSubmissionId)
            }
            AppButton {
                Layout.alignment: Qt.AlignHCenter
                visible: !root.historyVisible && !root.record.id
                text: qsTr("New draft")
                enabled: root.service && !root.service.busy
                onClicked: root.newDraft()
            }
            Text {
                objectName: "feedbackPrivacySummary"
                Layout.fillWidth: true
                visible: !root.historyVisible
                textFormat: Text.PlainText
                text: qsTr("Drafts stay on this device. Publishing makes the approved text and every attachment public.")
                color: Theme.textMuted
                font.pixelSize: Theme.fontSize(12)
                wrapMode: Text.WordWrap
            }
            Text {
                objectName: "feedbackPublicRetention"
                Layout.fillWidth: true
                visible: !root.historyVisible && root.editable && root.service && root.service.enabled
                textFormat: Text.PlainText
                text: qsTr("Public feedback remains part of the development record. Local deletion does not remove published content or copies made by others.")
                color: Theme.textMuted
                font.pixelSize: Theme.fontSize(12)
                wrapMode: Text.WordWrap
            }
            RowLayout {
                Layout.fillWidth: true
                visible: !root.historyVisible
                Text {
                    Layout.fillWidth: true
                    textFormat: Text.PlainText
                    text: root.service && root.service.enabled
                        ? qsTr("Publish to %1 after reviewing a public preview.").arg(root.service.publicRepository)
                        : Labels.error("disabled")
                    color: Theme.textSecondary
                    font.pixelSize: Theme.fontSize(12)
                    wrapMode: Text.WordWrap
                }
                AppButton {
                    objectName: "feedbackPrivacyLink"
                    visible: root.service && String(root.service.privacyUrl || "").length > 0
                    text: qsTr("Privacy")
                    compact: true
                    variant: "ghost"
                    onClicked: Qt.openUrlExternally(root.service.privacyUrl)
                }
            }
            Text {
                objectName: "feedbackError"
                Layout.fillWidth: true
                textFormat: Text.PlainText
                text: Labels.error(root.service ? root.service.errorCode || composer.inputErrorCode || root.record.reason || "" : "disabled")
                visible: text.length > 0
                color: Theme.warning
                wrapMode: Text.WordWrap
            }
            RowLayout {
                Layout.fillWidth: true
                visible: !root.historyVisible
                Text {
                    objectName: "feedbackSaveStatus"
                    Layout.fillWidth: true
                    textFormat: Text.PlainText
                    text: root.service && root.service.saving ? qsTr("Saving…")
                        : root.service && root.service.busy ? qsTr("Working…")
                        : root.operationText() || (root.editable && root.record.id
                            && composer.inputMatchesRecord && !root.service.errorCode ? qsTr("Draft saved") : "")
                    color: Theme.textMuted
                    wrapMode: Text.WordWrap
                    font.pixelSize: Theme.fontSize(12)
                }
                AppButton {
                    objectName: "feedbackRetryStorage"
                    visible: root.service && root.service.errorCode === "storage_unavailable"
                        && typeof root.service.retryStorage === "function"
                    text: qsTr("Retry saving")
                    compact: true
                    onClicked: root.service.retryStorage()
                }
                AppButton {
                    objectName: "feedbackStopSending"
                    visible: root.record.uploadAuthorized === true
                    text: qsTr("Stop sending")
                    variant: "secondary"
                    compact: true
                    onClicked: root.service.stop(root.record.id)
                }
                AppButton {
                    objectName: "feedbackCheckReceipt"
                    visible: !!root.record.id && !root.editable && (root.record.state !== "draft")
                    text: root.record.isPublic === true ? qsTr("Refresh status") : qsTr("Check receipt")
                    enabled: root.service && !root.service.busy
                    compact: true
                    onClicked: root.refreshStatus()
                }
                AppButton {
                    objectName: "feedbackSend"
                    variant: "primary"
                    visible: root.editable
                    text: qsTr("Review public feedback")
                    enabled: root.service && root.service.enabled && !root.service.busy
                        && !root.service.saving && !root.service.errorCode && composer.inputMatchesRecord
                        && String(root.record.description || "").trim().length > 0
                    compact: true
                    onClicked: root.reviewPublication()
                }
            }
        }
    }
    FeedbackAttachmentPreview { id: preview }
    FeedbackPublicationPreview {
        id: publicationPreview
        working: root.service && (root.service.busy || root.service.saving)
        errorCode: root.service ? root.service.errorCode : "disabled"
        onConfirmed: digest => {
            if (root.service.confirmSubmission(digest)) close()
        }
    }
    FileDialog {
        id: imageDialog
        objectName: "feedbackImageDialog"
        title: qsTr("Choose an image")
        fileMode: FileDialog.OpenFile
        nameFilters: [qsTr("Images (*.png *.jpg *.jpeg)")]
        onAccepted: root.service.attachImage(selectedFile)
    }
    FileDialog {
        id: exportDialog
        objectName: "feedbackExportDialog"
        title: qsTr("Export feedback")
        fileMode: FileDialog.SaveFile
        nameFilters: [qsTr("Feedback file (*.json)")]
        defaultSuffix: "json"
        onAccepted: root.service.exportRecord(root.exportId, selectedFile)
    }
    ConfirmDialog {
        id: deleteConfirmation
        objectName: "feedbackDeleteConfirmation"
        z: 320
        titleText: qsTr("Delete local feedback?")
        message: qsTr("This stops future uploads and deletes this device's record and access to its status or removal request. Received or published content is not removed. Request content removal first if needed.")
        confirmText: qsTr("Delete locally")
        dangerous: true
        onConfirmed: {
            root.service.deleteRecord(root.confirmRecordId)
            root.historyVisible = true
        }
    }
    ConfirmDialog {
        id: cloneConfirmation
        objectName: "feedbackCloneConfirmation"
        z: 320
        titleText: qsTr("Create another draft?")
        message: qsTr("The original record remains unchanged. Contact email is not copied. The new draft will be public only after you review the preview and confirm publication.")
        confirmText: qsTr("Create public draft")
        onConfirmed: root.service.cloneDraft(root.confirmRecordId)
    }
    ConfirmDialog {
        id: removalConfirmation
        objectName: "feedbackRemovalConfirmation"
        z: 340
        titleText: qsTr("Request content removal?")
        message: qsTr("Request deletion of this feedback, including accidentally published sensitive content. Publication will stop, but some AI task history may still await cleanup. AI provider records, GitHub history, notifications and copies held by others may remain. Closing feedback alone keeps its history. Keep this record to check progress.")
        confirmText: qsTr("Request content removal")
        dangerous: true
        onConfirmed: root.service.requestRemoval(root.confirmRecordId)
    }
    ConfirmDialog {
        id: closureConfirmation
        objectName: "feedbackClosureConfirmation"
        z: 340
        titleText: qsTr("Close feedback?")
        message: qsTr("Stop further follow-up and new replies while keeping this feedback's readable history and attachments. Existing tasks may still be stopping after closure is accepted. To address sensitive content, request content removal separately.")
        confirmText: qsTr("Close feedback")
        onConfirmed: root.service.closeFeedback(root.confirmRecordId)
    }
    AppPopup {
        id: contextChoice
        objectName: "feedbackContextChoice"
        width: parent ? Math.min(Theme.size(560), parent.width - Theme.size(32)) : 0
        z: 320
        closePolicy: Popup.CloseOnEscape
        contentItem: ColumnLayout {
            spacing: Theme.size(16)
            AppPopupHeader { titleText: qsTr("Keep working on this draft?") }
            Text {
                Layout.fillWidth: true
                textFormat: Text.PlainText
                text: qsTr("Add the selected context to your current draft, or start a new one. Your existing text will be kept.")
                color: Theme.textSecondary
                wrapMode: Text.WordWrap
            }
            Flow {
                Layout.fillWidth: true
                spacing: Theme.size(8)
                AppButton {
                    objectName: "feedbackContextAdd"
                    text: qsTr("Add to draft")
                    compact: true
                    onClicked: { root.applyPending(true); contextChoice.close() }
                }
                AppButton {
                    objectName: "feedbackContextNew"
                    text: qsTr("New draft")
                    compact: true
                    variant: "secondary"
                    onClicked: { root.createPendingDraft(); contextChoice.close() }
                }
                AppButton {
                    text: qsTr("Cancel")
                    compact: true
                    variant: "ghost"
                    onClicked: contextChoice.close()
                }
            }
        }
    }
    AppPopup {
        id: chooseCrash
        objectName: "feedbackCrashPicker"
        width: parent ? Math.min(Theme.size(630), parent.width - Theme.size(32)) : 0
        height: parent ? Math.min(Theme.size(480), parent.height - Theme.size(32)) : 0
        z: 320
        contentItem: ColumnLayout {
            spacing: Theme.size(12)
            AppPopupHeader { titleText: qsTr("Choose crash report") }
            Text {
                Layout.fillWidth: true
                textFormat: Text.PlainText
                text: qsTr("The selected report is copied into this draft. Later changes will not replace it.")
                color: Theme.textSecondary
                wrapMode: Text.WordWrap
            }
            Text {
                visible: !root.crashService || root.crashService.entries.length === 0
                textFormat: Text.PlainText
                text: qsTr("No crash reports available.")
                color: Theme.textMuted
            }
            ListView {
                id: crashList
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: Theme.size(8)
                model: root.crashService ? root.crashService.entries : []
                ScrollBar.vertical: ScrollBar { }
                delegate: AppButton {
                    required property var modelData
                    objectName: "feedbackSelectCrash-" + modelData.reportId
                    width: crashList.width
                    text: Labels.date(modelData.occurredAt) + " · " + qsTr("Revision %1").arg(modelData.revision)
                    variant: "secondary"
                    onClicked: {
                        root.service.attachCrashReport(root.crashService.report(modelData.reportId))
                        chooseCrash.close()
                    }
                }
            }
            AppButton {
                text: qsTr("Cancel")
                Layout.alignment: Qt.AlignRight
                onClicked: chooseCrash.close()
            }
        }
    }
}
