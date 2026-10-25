// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors
pragma ComponentBehavior: Bound
pragma Translator: "Feedback"
import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import "FeedbackLabels.js" as Labels

ScrollView {
    id: root
    objectName: "feedbackComposer"
    property var service: null
    readonly property var record: service ? service.draft : ({})
    readonly property var localReplies: service && service.thread && service.thread.caseId === record.id
        ? service.thread.localReplies || [] : []
    readonly property bool editable: record.isPublic === true && (record.editable === true || record.state === "draft")
    readonly property bool inputMatchesRecord: descriptionField.text === String(record.description || "")
    readonly property string recordId: String(record.id || "")
    property string descriptionInputError: ""
    readonly property string inputErrorCode: descriptionField.text !== String(record.description || "")
        ? descriptionInputError || "invalid_description" : ""
    property bool hostingAvailable: false
    property bool syncing: false
    property bool showTechnical: false
    property bool showOriginal: false
    readonly property bool caseDetails: record.isPublic === true && record.state === "accepted" && record.isReply !== true
    readonly property bool localPreviewsAllowed: record.isPublic === true && record.payloadAvailable !== false
        && (!record.removalState || record.removalState === "none")
    property var thumbnailCache: ({})
    readonly property string screenshotKey: JSON.stringify([record.id || "", localPreviewsAllowed,
        (record.attachments || []).filter(item => item.kind === "screenshot")
            .map(item => [item.id, item.sha256 || "", item.byteLength || 0])])
    signal imageRequested()
    signal crashRequested()
    signal hostingRequested()
    signal previewRequested(string attachmentId, string title)
    signal exportRequested()
    signal deleteRequested()
    signal cloneRequested()
    signal removalRequested()
    signal closureRequested()
    signal replyRequested(string questionId, int revision)
    signal recordRequested(string recordId)
    signal threadAttachmentRequested(string contributionId, string attachmentId, string title)
    signal parentRequested()
    contentWidth: availableWidth
    clip: true
    ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

    function syncFields() {
        if (!descriptionField || !categoryField) return
        syncing = true
        descriptionInputError = ""
        if (descriptionField.text !== String(record.description || ""))
            descriptionField.text = String(record.description || "")
        categoryField.currentIndex = Math.max(0, ["problem", "suggestion", "other"].indexOf(record.category || "problem"))
        syncing = false
    }
    function update(fields) {
        if (syncing || !service || !editable) return
        const accepted = service.updateDraft(fields) !== false
        if (fields.description !== undefined)
            descriptionInputError = accepted ? "" : service.errorCode || "invalid_description"
    }
    function thumbnailKey(attachment) {
        return String(record.id || "") + ":" + attachment.id + ":"
            + String(attachment.sha256 || "") + ":" + String(attachment.byteLength || 0)
    }
    function refreshThumbnails() {
        const next = {}
        if (localPreviewsAllowed && service && typeof service.attachmentPreview === "function") {
            for (const attachment of record.attachments || []) {
                if (attachment.kind !== "screenshot") continue
                const key = thumbnailKey(attachment)
                if (Object.prototype.hasOwnProperty.call(thumbnailCache, key)) {
                    next[key] = thumbnailCache[key]
                    continue
                }
                const preview = String(service.attachmentPreview(attachment.id) || "")
                // Only normalized, local image bytes are eligible. Never bind an
                // attachment URL, legacy private image or removed payload here.
                next[key] = /^data:image\/(png|jpeg);base64,[A-Za-z0-9+/=]+$/.test(preview) ? preview : ""
            }
        }
        thumbnailCache = next
    }
    onScreenshotKeyChanged: refreshThumbnails()
    onServiceChanged: {
        thumbnailCache = ({})
        refreshThumbnails()
    }
    // Rejected text belongs to the editor until corrected. Attachment/category
    // updates republish the saved record and must not replace that pending input.
    onEditableChanged: syncFields()
    onRecordIdChanged: {
        syncFields()
        showOriginal = false
        Qt.callLater(() => {
            const flickable = contentItem as Flickable
            if (flickable) flickable.contentY = 0
        })
    }
    Component.onCompleted: {
        syncFields()
        refreshThumbnails()
    }

    ColumnLayout {
        width: root.availableWidth
        spacing: Theme.size(12)
        RowLayout {
            Layout.fillWidth: true
            AppComboBox {
                id: categoryField
                visible: !root.caseDetails
                objectName: "feedbackCategory"
                Layout.preferredWidth: Theme.size(190)
                enabled: root.editable && root.record.isReply !== true
                model: [qsTr("Problem"), qsTr("Suggestion"), qsTr("Other")]
                onActivated: root.update({category: ["problem", "suggestion", "other"][currentIndex]})
            }
            Text {
                objectName: "feedbackRecordState"
                Layout.fillWidth: true
                textFormat: Text.PlainText
                text: Labels.recordState(root.record)
                color: (root.record.state === "received" || root.record.state === "accepted") ? Theme.success : Theme.textSecondary
                wrapMode: Text.WordWrap
            }
        }
        Text {
            objectName: "feedbackPublicationMeaning"
            Layout.fillWidth: true
            visible: root.record.isPublic === true && !!root.record.publicationState
                && (root.record.publicationState !== "published" || !root.caseDetails || root.showOriginal)
                && (!root.record.removalState || root.record.removalState === "none")
            textFormat: Text.PlainText
            text: Labels.publicationDescription(root.record.publicationState)
            color: root.record.publicationState === "published" ? Theme.success : Theme.textSecondary
            wrapMode: Text.WordWrap
        }
        FeedbackThread {
            Layout.fillWidth: true
            visible: root.record.isPublic === true && root.record.state === "accepted" && root.record.isReply !== true
                && (!root.record.removalState || root.record.removalState === "none")
            service: root.service
            caseId: String(root.record.parentSubmissionId || root.record.id || "")
            canReply: visible && root.service && root.service.enabled && !root.service.busy && !root.service.saving
                && root.record.caseState !== "closed" && (!root.record.closureRequestState || root.record.closureRequestState === "none")
                && (!root.record.removalState || root.record.removalState === "none")
                && root.record.publicationState === "published"
            onReplyRequested: (questionId, revision) => root.replyRequested(questionId, revision)
            onAttachmentRequested: (contributionId, attachmentId, title) => root.threadAttachmentRequested(contributionId, attachmentId, title)
        }
        Text {
            objectName: "feedbackRemovalMeaning"
            Layout.fillWidth: true
            visible: root.record.isPublic === true && !!root.record.removalState && root.record.removalState !== "none"
            textFormat: Text.PlainText
            text: Labels.removalDescription(root.record.removalState)
            color: Theme.warning
            wrapMode: Text.WordWrap
        }
        Text {
            objectName: "feedbackClosureMeaning"
            Layout.fillWidth: true
            visible: root.record.isPublic === true && text.length > 0
            textFormat: Text.PlainText
            text: Labels.closureDescription(root.record)
            color: root.record.closureRequestState === "stalled" || root.record.closurePublicationState === "stalled" ? Theme.warning : Theme.textSecondary
            wrapMode: Text.WordWrap
        }
        ColumnLayout {
            Layout.fillWidth: true
            visible: root.record.isPublic === true && root.record.isReply !== true
                && root.localReplies.length > 0
            spacing: Theme.size(8)
            Text {
                Layout.fillWidth: true
                text: qsTr("Replies on this device")
                textFormat: Text.PlainText
                color: Theme.textSecondary
                wrapMode: Text.WordWrap
            }
            Repeater {
                model: root.localReplies
                delegate: AppButton {
                    id: localReply
                    required property var modelData
                    objectName: "feedbackLocalReply-" + modelData.id
                    Layout.fillWidth: true
                    implicitHeight: localReplyText.implicitHeight + Theme.size(24)
                    text: Labels.state(modelData.state) + " · " + String(modelData.description || qsTr("Empty draft"))
                    contentItem: Text {
                        id: localReplyText
                        text: localReply.text
                        textFormat: Text.PlainText
                        color: Theme.text
                        wrapMode: Text.WrapAnywhere
                        maximumLineCount: 3
                        elide: Text.ElideRight
                    }
                    variant: "secondary"
                    onClicked: root.recordRequested(String(modelData.id))
                }
            }
        }
        AppButton {
            objectName: "feedbackOriginalToggle"
            visible: root.caseDetails
            text: root.showOriginal ? qsTr("Hide original feedback and receipt") : qsTr("Original feedback and receipt")
            variant: "ghost"
            compact: true
            onClicked: root.showOriginal = !root.showOriginal
        }
        ColumnLayout {
            objectName: "feedbackOriginalContent"
            Layout.fillWidth: true
            visible: !root.caseDetails || root.showOriginal
            spacing: Theme.size(12)
            Text {
                objectName: "feedbackReplyQuestion"
                Layout.fillWidth: true
                visible: root.record.isReply === true && !!root.record.questionText
                text: Labels.question(root.record.questionCode, root.record.questionText)
                textFormat: Text.PlainText
                color: Theme.textSecondary
                wrapMode: Text.WrapAnywhere
            }
            Text {
                Layout.fillWidth: true
                textFormat: Text.PlainText
                text: root.record.isReply === true ? qsTr("Your public reply") : qsTr("What happened?")
                color: Theme.text
                font.weight: Font.DemiBold
            }
            TextArea {
                id: descriptionField
                objectName: "feedbackDescription"
                Layout.fillWidth: true
                Layout.minimumHeight: Theme.size(145)
                textFormat: TextEdit.PlainText
                readOnly: !root.editable
                selectByMouse: true
                wrapMode: TextEdit.Wrap
                color: Theme.text
                placeholderText: qsTr("Describe the problem, what you did and what you expected.")
                placeholderTextColor: Theme.textMuted
                font.pixelSize: Theme.fontSize(14)
                padding: Theme.size(12)
                background: Rectangle {
                    color: Theme.surfaceMuted
                    radius: Theme.radiusMedium
                    border.color: descriptionField.activeFocus ? Theme.primary : Theme.border
                }
                onTextChanged: root.update({description: text})
            }
            AppButton {
                objectName: "feedbackBackToCase"
                visible: root.record.isReply === true
                enabled: root.record.parentAvailable !== false
                text: qsTr("Back to original feedback")
                compact: true
                variant: "ghost"
                onClicked: root.parentRequested()
            }
            Text {
                objectName: "feedbackLegacyNotice"
                Layout.fillWidth: true
                visible: root.record.isPublic !== true
                textFormat: Text.PlainText
                text: qsTr("This record uses the earlier private-feedback contract. It will not be published. To share it publicly, create a new public draft and review it first.")
                color: Theme.warning
                wrapMode: Text.WordWrap
            }
            Text {
                Layout.fillWidth: true
                visible: !!root.record.receipt
                textFormat: Text.PlainText
                text: qsTr("Receipt: %1").arg(String(root.record.receipt || ""))
                      + (root.record.acceptedAt ? " · " + Labels.date(root.record.acceptedAt) : "")
                color: Theme.textSecondary
                wrapMode: Text.WrapAnywhere
            }
            Text {
                objectName: "feedbackReceivedMeaning"
                Layout.fillWidth: true
                visible: (root.record.state === "received" || root.record.state === "accepted")
                textFormat: Text.PlainText
                text: root.record.isPublic === true
                    ? qsTr("Accepted confirms storage by the feedback service. Publication, assessment and resolution are separate steps.")
                    : qsTr("Received confirms storage by support. It does not confirm review or resolution.")
                color: Theme.textSecondary
                font.pixelSize: Theme.fontSize(12)
                wrapMode: Text.WordWrap
            }
            Text {
                objectName: "feedbackReceivedLocalRetention"
                Layout.fillWidth: true
                visible: (root.record.state === "received" || root.record.state === "accepted")
                textFormat: Text.PlainText
                text: root.record.isPublic === true
                    ? qsTr("On this device, content is kept for up to 30 days. Keep this receipt to check status or request removal; deleting it loses access.")
                    : qsTr("On this device, received content is kept for up to 30 days and receipts for up to 90 days, subject to storage limits.")
                color: Theme.textMuted
                font.pixelSize: Theme.fontSize(12)
                wrapMode: Text.WordWrap
            }
            Text {
                objectName: "feedbackReceiptAccess"
                Layout.fillWidth: true
                visible: root.record.isPublic === true && !!root.record.accessExpiresAt
                textFormat: Text.PlainText
                text: qsTr("Receipt access until at least %1. Access is retained while removal remains unresolved.")
                    .arg(Labels.date(root.record.accessExpiresAt))
                color: Theme.textMuted
                font.pixelSize: Theme.fontSize(12)
                wrapMode: Text.WordWrap
            }
            Text {
                objectName: "feedbackIssueReference"
                Layout.fillWidth: true
                visible: !!root.record.issueUrl
                textFormat: Text.PlainText
                text: String(root.record.issueUrl || "")
                color: Theme.textSecondary
                wrapMode: Text.WrapAnywhere
            }
            Text {
                Layout.fillWidth: true
                visible: root.record.payloadAvailable === false
                textFormat: Text.PlainText
                text: qsTr("Older content has been removed from local storage. The receipt remains available.")
                color: Theme.warning
                wrapMode: Text.WordWrap
            }
            Flow {
                Layout.fillWidth: true
                visible: root.editable
                spacing: Theme.size(8)
                AppButton {
                    objectName: "feedbackAddImage"
                    text: qsTr("Add image")
                    variant: "secondary"
                    compact: true
                    enabled: root.service && !root.service.busy
                    onClicked: root.imageRequested()
                }
                AppButton {
                    objectName: "feedbackPasteImage"
                    text: qsTr("Paste image")
                    variant: "ghost"
                    compact: true
                    enabled: root.service && !root.service.busy
                    onClicked: root.service.pasteImage()
                }
                AppButton {
                    objectName: "feedbackChooseCrash"
                    text: qsTr("Choose crash report")
                    variant: "secondary"
                    compact: true
                    onClicked: root.crashRequested()
                }
                AppButton {
                    objectName: "feedbackAddHosting"
                    text: qsTr("Add hosting diagnostics")
                    variant: "ghost"
                    compact: true
                    enabled: root.hostingAvailable && root.service && !root.service.busy
                    onClicked: root.hostingRequested()
                }
            }
            Text {
                objectName: "feedbackImageLimit"
                Layout.fillWidth: true
                visible: root.editable
                text: qsTr("You can attach up to two screenshots.")
                textFormat: Text.PlainText
                color: Theme.textMuted
                font.pixelSize: Theme.fontSize(12)
                wrapMode: Text.WordWrap
            }
            Repeater {
                model: root.record.attachments || []
                delegate: Surface {
                    id: attachmentCard
                    required property var modelData
                    readonly property string thumbnailSource: root.localPreviewsAllowed
                        ? String(root.thumbnailCache[root.thumbnailKey(modelData)] || "") : ""
                    Layout.fillWidth: true
                    implicitHeight: attachmentRow.implicitHeight + Theme.size(20)
                    radius: Theme.radiusSmall
                    RowLayout {
                        id: attachmentRow
                        anchors.fill: parent
                        anchors.margins: Theme.size(10)
                        spacing: Theme.size(8)
                        AppButton {
                            objectName: "feedbackThumbnail-" + attachmentCard.modelData.id
                            visible: attachmentCard.modelData.kind === "screenshot"
                                && attachmentCard.thumbnailSource.length > 0
                            Layout.preferredWidth: Theme.size(96)
                            Layout.preferredHeight: Theme.size(72)
                            compact: true
                            variant: "ghost"
                            accessibleName: qsTr("Preview screenshot")
                            contentItem: Image {
                                objectName: "feedbackThumbnailImage-" + attachmentCard.modelData.id
                                source: attachmentCard.thumbnailSource
                                sourceSize.width: 192
                                sourceSize.height: 144
                                fillMode: Image.PreserveAspectFit
                                asynchronous: true
                            }
                            onClicked: root.previewRequested(attachmentCard.modelData.id,
                                Labels.attachment(attachmentCard.modelData.kind))
                        }
                        Text {
                            Layout.fillWidth: true
                            textFormat: Text.PlainText
                            text: Labels.attachment(modelData.kind) + " · "
                                  + Math.ceil(Number(modelData.byteLength || 0) / 1024) + " KiB"
                            color: Theme.text
                            wrapMode: Text.WordWrap
                        }
                        AppButton {
                            objectName: "feedbackPreview-" + modelData.id
                            enabled: root.service && root.record.payloadAvailable !== false
                                && (root.record.isPublic !== true || !root.record.removalState || root.record.removalState === "none")
                            compact: true
                            text: qsTr("Preview")
                            variant: "secondary"
                            onClicked: root.previewRequested(modelData.id, Labels.attachment(modelData.kind))
                        }
                        AppButton {
                            objectName: "feedbackRemove-" + modelData.id
                            visible: root.editable
                            enabled: root.service && !root.service.busy
                            compact: true
                            text: qsTr("Remove")
                            variant: "ghost"
                            onClicked: root.service.removeAttachment(modelData.id)
                        }
                    }
                }
            }
            AppButton {
                objectName: "feedbackTechnicalToggle"
                text: root.showTechnical ? qsTr("Hide technical information") : qsTr("Technical information")
                variant: "ghost"
                compact: true
                onClicked: root.showTechnical = !root.showTechnical
            }
            TextArea {
                objectName: "feedbackTechnicalInfo"
                Layout.fillWidth: true
                visible: root.showTechnical
                textFormat: TextEdit.PlainText
                text: JSON.stringify(root.record.context || {}, null, 2)
                readOnly: true
                selectByMouse: true
                wrapMode: TextEdit.WrapAnywhere
                color: Theme.textSecondary
                font.pixelSize: Theme.fontSize(12)
                background: Rectangle { color: Theme.surface; radius: Theme.radiusSmall }
            }
        }
        Flow {
            Layout.fillWidth: true
            spacing: Theme.size(8)
            AppButton {
                objectName: "feedbackCopyReceipt"
                visible: !!root.record.receipt
                text: qsTr("Copy receipt")
                variant: "ghost"
                compact: true
                onClicked: root.service.copyReceipt(root.record.id)
            }
            AppButton {
                objectName: "feedbackExport"
                text: qsTr("Export")
                enabled: !!root.record.id && root.record.payloadAvailable !== false
                variant: "ghost"
                compact: true
                onClicked: root.exportRequested()
            }
            AppButton {
                objectName: "feedbackEditCopy"
                visible: !!root.record.id && !root.editable && root.record.payloadAvailable !== false
                text: root.record.isPublic === true ? qsTr("Create editable copy") : qsTr("Create public draft")
                variant: "secondary"
                compact: true
                onClicked: root.cloneRequested()
            }
            AppButton {
                objectName: "feedbackCloseCase"
                visible: root.record.isPublic === true && root.record.isReply !== true && root.record.state === "accepted"
                    && root.record.caseState !== "closed" && root.record.closureRequestState !== "requested"
                    && (!root.record.removalState || root.record.removalState === "none")
                text: root.record.closureRequestState === "stalled" ? qsTr("Retry closing feedback") : qsTr("Close feedback")
                enabled: root.service && !root.service.busy && !root.service.saving
                variant: "secondary"
                compact: true
                onClicked: root.closureRequested()
            }
            AppButton {
                objectName: "feedbackRequestRemoval"
                visible: root.record.isPublic === true && root.record.isReply !== true && (root.record.state === "received" || root.record.state === "accepted")
                    && (!root.record.removalState || root.record.removalState === "none")
                text: qsTr("Request content removal")
                enabled: root.service && !root.service.busy && !root.service.saving
                variant: "secondary"
                compact: true
                onClicked: root.removalRequested()
            }
            AppButton {
                objectName: "feedbackDelete"
                text: qsTr("Delete locally")
                enabled: !!root.record.id
                variant: "ghost"
                compact: true
                onClicked: root.deleteRequested()
            }
        }
    }
}
