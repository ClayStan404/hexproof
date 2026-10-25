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
    objectName: "feedbackThread"
    property var service: null
    property string caseId: ""
    property bool canReply: false
    readonly property var thread: service && service.thread && service.thread.caseId === caseId ? service.thread : ({})
    readonly property bool hasSnapshot: !!thread.syncedAt || !!thread.workState
    readonly property var question: thread.question || ({})
    readonly property var entries: (thread.items || []).filter(item => item.kind !== "submission" || (item.attachments || []).length > 0).slice().reverse()
    signal replyRequested(string questionId, int revision)
    signal attachmentRequested(string contributionId, string attachmentId, string title)
    spacing: Theme.size(10)

    Text {
        Layout.fillWidth: true
        text: qsTr("Conversation with the AI team")
        textFormat: Text.PlainText
        color: Theme.text
        font.weight: Font.DemiBold
    }
    Text {
        objectName: "feedbackWorkState"
        Layout.fillWidth: true
        text: root.thread.caseState === "closed" ? qsTr("Closed")
            : !root.hasSnapshot ? (root.thread.loading ? qsTr("Refreshing conversation…") : qsTr("Not synced yet"))
            : Labels.workState(String(root.thread.workState || "new"))
        textFormat: Text.PlainText
        color: Theme.primary
        wrapMode: Text.WordWrap
    }
    Text {
        objectName: "feedbackCurrentOutcome"
        Layout.fillWidth: true
        visible: text.length > 0
        text: Labels.outcome(root.thread.outcome)
        textFormat: Text.PlainText
        color: Theme.primary
        wrapMode: Text.WordWrap
    }
    Text {
        objectName: "feedbackAssessmentSummary"
        Layout.fillWidth: true
        visible: text.length > 0
        text: String(root.thread.summary || "")
        textFormat: Text.PlainText
        color: Theme.textSecondary
        wrapMode: Text.WrapAnywhere
    }
    Text {
        objectName: "feedbackThreadSync"
        Layout.fillWidth: true
        text: root.thread.syncedAt ? qsTr("Last synced: %1").arg(Labels.date(root.thread.syncedAt)) : ""
        textFormat: Text.PlainText
        color: Theme.textMuted
        wrapMode: Text.WordWrap
        visible: text.length > 0
    }
    Text {
        objectName: "feedbackThreadConnection"
        Layout.fillWidth: true
        text: root.thread.loading ? (root.hasSnapshot ? qsTr("Refreshing conversation…") : "")
            : Labels.error(root.thread.errorCode || "")
        textFormat: Text.PlainText
        color: Theme.warning
        wrapMode: Text.WordWrap
        visible: text.length > 0
    }
    Text {
        objectName: "feedbackAssessmentUnavailable"
        Layout.fillWidth: true
        visible: root.thread.assessmentDeliveryState === "unavailable"
        text: qsTr("Assessment updates are temporarily unavailable. Your feedback receipt remains available.")
        textFormat: Text.PlainText
        color: Theme.warning
        wrapMode: Text.WordWrap
    }
    Surface {
        Layout.fillWidth: true
        visible: !!root.question.id
        implicitHeight: questionBody.implicitHeight + Theme.size(24)
        ColumnLayout {
            id: questionBody
            anchors.fill: parent
            anchors.margins: Theme.size(12)
            spacing: Theme.size(8)
            Text {
                objectName: "feedbackCurrentQuestion"
                Layout.fillWidth: true
                text: Labels.question(root.question.code, root.question.description)
                textFormat: Text.PlainText
                color: Theme.text
                wrapMode: Text.WrapAnywhere
            }
            Text {
                Layout.fillWidth: true
                visible: !!root.question.answerDeadline
                text: qsTr("Requested by %1. Later replies can still be submitted.").arg(Labels.date(root.question.answerDeadline))
                textFormat: Text.PlainText
                color: Theme.textMuted
                wrapMode: Text.WordWrap
            }
            AppButton {
                objectName: "feedbackAnswerQuestion"
                text: qsTr("Reply to this question")
                enabled: root.canReply && root.thread.replyAllowed !== false
                compact: true
                onClicked: root.replyRequested(String(root.question.id), Number(root.question.revision || 0))
            }
        }
    }
    AppButton {
        objectName: "feedbackAddReply"
        text: qsTr("Add public information")
        enabled: root.canReply && root.thread.replyAllowed !== false
        compact: true
        variant: "secondary"
        onClicked: root.replyRequested("", 0)
    }
    Repeater {
        model: root.entries
        delegate: Surface {
            id: entry
            required property var modelData
            Layout.fillWidth: true
            implicitHeight: entryBody.implicitHeight + Theme.size(24)
            ColumnLayout {
                id: entryBody
                anchors.fill: parent
                anchors.margins: Theme.size(12)
                spacing: Theme.size(8)
                Text {
                    objectName: "feedbackThreadEntryStatus-" + String(entry.modelData.submissionId || "")
                    Layout.fillWidth: true
                    text: (entry.modelData.kind === "submission" ? qsTr("Original feedback")
                        : entry.modelData.kind === "reply" ? qsTr("Your public reply") : qsTr("AI team"))
                        + " · " + Labels.recordState({isPublic: true, publicationState: entry.modelData.publicationState})
                        + (entry.modelData.publishedAt || entry.modelData.acceptedAt
                            ? " · " + Labels.date(entry.modelData.publishedAt || entry.modelData.acceptedAt) : "")
                    textFormat: Text.PlainText
                    color: Theme.textSecondary
                    wrapMode: Text.WordWrap
                }
                Text {
                    Layout.fillWidth: true
                    visible: !!entry.modelData.outcome
                    text: Labels.outcome(entry.modelData.outcome)
                    textFormat: Text.PlainText
                    color: Theme.primary
                    wrapMode: Text.WordWrap
                }
                Text {
                    objectName: "feedbackThreadEntry-" + String(entry.modelData.submissionId || "")
                    Layout.fillWidth: true
                    visible: entry.modelData.kind !== "submission"
                    text: String(entry.modelData.description || "")
                    textFormat: Text.PlainText
                    color: Theme.text
                    wrapMode: Text.WrapAnywhere
                }
                Repeater {
                    model: entry.modelData.attachments || []
                    delegate: AppButton {
                        required property var modelData
                        readonly property var contribution: entry ? entry.modelData : ({})
                        Layout.fillWidth: true
                        objectName: "feedbackThreadAttachment-" + String(contribution.submissionId || "") + "-" + modelData.id
                        text: Labels.attachment(modelData.kind) + " · " + qsTr("Preview")
                        enabled: root.service && !root.service.busy && contribution.publicationState === "published"
                        compact: true
                        variant: "secondary"
                        onClicked: {
                            if (contribution.submissionId)
                                root.attachmentRequested(String(contribution.submissionId), String(modelData.id), Labels.attachment(modelData.kind))
                        }
                    }
                }
            }
        }
    }
    ColumnLayout {
        Layout.fillWidth: true
        visible: (root.thread.deliveryHistory || []).length > 0
        spacing: Theme.size(6)
        Text {
            Layout.fillWidth: true
            text: qsTr("Delivery history")
            textFormat: Text.PlainText
            color: Theme.text
            font.weight: Font.DemiBold
        }
        Text {
            Layout.fillWidth: true
            text: qsTr("Earlier deliveries remain listed while the AI team assesses new information.")
            textFormat: Text.PlainText
            color: Theme.textSecondary
            wrapMode: Text.WordWrap
        }
        Repeater {
            model: root.thread.deliveryHistory || []
            delegate: Text {
                required property var modelData
                objectName: "feedbackDelivery-" + String(modelData.projectionId || "")
                Layout.fillWidth: true
                text: Labels.outcome(modelData.outcome) + " · " + Labels.date(modelData.publishedAt)
                textFormat: Text.PlainText
                color: Theme.primary
                wrapMode: Text.WordWrap
            }
        }
    }
}
