// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors
pragma ComponentBehavior: Bound
pragma Translator: "Feedback"
import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import "FeedbackLabels.js" as Labels

AppPopup {
    id: root
    objectName: "feedbackPublicationPreview"
    property var snapshot: ({})
    property bool working: false
    property string errorCode: ""
    signal confirmed(string digest)
    width: parent ? Math.min(Theme.size(840), parent.width - Theme.size(32)) : 0
    height: parent ? Math.min(Theme.size(850), parent.height - Theme.size(32)) : 0
    z: 330
    closePolicy: Popup.CloseOnEscape
    onOpened: {
        consent.checked = false
        const flickable = contentScroll.contentItem as Flickable
        if (flickable) flickable.contentY = 0
    }
    onClosed: {
        consent.checked = false
        snapshot = ({})
    }
    contentItem: ColumnLayout {
        spacing: Theme.size(12)
        AppPopupHeader { titleText: qsTr("Review public feedback") }
        ScrollView {
            id: contentScroll
            objectName: "feedbackPublicationScroll"
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentWidth: availableWidth
            clip: true
            ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
            ColumnLayout {
                width: contentScroll.availableWidth
                spacing: Theme.size(12)
                Text {
                    objectName: "feedbackPublicDestination"
                    Layout.fillWidth: true
                    textFormat: Text.PlainText
                    text: qsTr("Public GitHub destination: %1").arg(String(root.snapshot.publicRepository || ""))
                    color: Theme.primary
                    font.weight: Font.DemiBold
                    wrapMode: Text.WrapAnywhere
                }
                Text {
                    objectName: "feedbackPublicWarning"
                    Layout.fillWidth: true
                    textFormat: Text.PlainText
                    text: qsTr("Anyone can view and copy this text, technical information and every attachment. Check images and reports for personal information or secrets. Preparing this preview sends nothing.")
                    color: Theme.warning
                    wrapMode: Text.WordWrap
                }
                Text {
                    objectName: "feedbackPublicReplyTarget"
                    Layout.fillWidth: true
                    visible: !!root.snapshot.parentSubmissionId
                    text: qsTr("Reply to feedback: %1").arg(String(root.snapshot.parentSubmissionId || ""))
                        + (root.snapshot.questionText ? "\n" + Labels.question(root.snapshot.questionCode, root.snapshot.questionText) : "")
                    textFormat: Text.PlainText
                    color: Theme.text
                    wrapMode: Text.WrapAnywhere
                }
                TextArea {
                    objectName: "feedbackPublicNotice"
                    Layout.fillWidth: true
                    textFormat: TextEdit.PlainText
                    text: String(root.snapshot.noticeText || "")
                    readOnly: true
                    selectByMouse: true
                    wrapMode: TextEdit.Wrap
                    color: Theme.textSecondary
                    font.pixelSize: Theme.fontSize(12)
                    background: Rectangle { color: Theme.surface; radius: Theme.radiusSmall }
                }
                Text {
                    Layout.fillWidth: true
                    textFormat: Text.PlainText
                    text: Labels.category(root.snapshot.category)
                    color: Theme.text
                    font.weight: Font.DemiBold
                }
                TextArea {
                    objectName: "feedbackPublicDescription"
                    Layout.fillWidth: true
                    textFormat: TextEdit.PlainText
                    text: String(root.snapshot.description || "")
                    readOnly: true
                    selectByMouse: true
                    wrapMode: TextEdit.WrapAnywhere
                    color: Theme.text
                    background: Rectangle { color: Theme.surfaceMuted; radius: Theme.radiusSmall }
                }
                Text {
                    Layout.fillWidth: true
                    textFormat: Text.PlainText
                    text: qsTr("Technical information")
                    color: Theme.text
                    font.weight: Font.DemiBold
                }
                TextArea {
                    objectName: "feedbackPublicContext"
                    Layout.fillWidth: true
                    textFormat: TextEdit.PlainText
                    text: JSON.stringify(root.snapshot.context || {}, null, 2)
                    readOnly: true
                    selectByMouse: true
                    wrapMode: TextEdit.WrapAnywhere
                    color: Theme.textSecondary
                    font.pixelSize: Theme.fontSize(12)
                    background: Rectangle { color: Theme.surface; radius: Theme.radiusSmall }
                }
                Repeater {
                    objectName: "feedbackPublicAttachments"
                    model: root.snapshot.attachments || []
                    delegate: ColumnLayout {
                        id: attachmentProjection
                        required property var modelData
                        readonly property string previewContent: String(modelData.previewContent || "")
                        readonly property bool isImage: previewContent.indexOf("data:image/") === 0
                        Layout.fillWidth: true
                        spacing: Theme.size(6)
                        Text {
                            Layout.fillWidth: true
                            textFormat: Text.PlainText
                            text: Labels.attachment(modelData.kind) + " · "
                                  + Math.ceil(Number(modelData.byteLength || 0) / 1024) + " KiB"
                            color: Theme.text
                            wrapMode: Text.WordWrap
                            font.weight: Font.DemiBold
                        }
                        Image {
                            objectName: "feedbackPublicImage-" + modelData.id
                            Layout.fillWidth: true
                            Layout.preferredHeight: Theme.size(320)
                            visible: attachmentProjection.isImage
                            source: attachmentProjection.isImage ? attachmentProjection.previewContent : ""
                            fillMode: Image.PreserveAspectFit
                            cache: false
                        }
                        TextArea {
                            objectName: "feedbackPublicAttachment-" + modelData.id
                            Layout.fillWidth: true
                            visible: !attachmentProjection.isImage
                            textFormat: TextEdit.PlainText
                            text: attachmentProjection.isImage ? "" : attachmentProjection.previewContent
                            readOnly: true
                            selectByMouse: true
                            wrapMode: TextEdit.WrapAnywhere
                            color: Theme.textSecondary
                            font.pixelSize: Theme.fontSize(12)
                            background: Rectangle { color: Theme.surface; radius: Theme.radiusSmall }
                        }
                    }
                }
            }
        }
        AppToggle {
            id: consent
            objectName: "feedbackPublicConsent"
            Layout.fillWidth: true
            text: qsTr("I have reviewed this content and the notice, and agree to publish it publicly.")
            checked: false
        }
        Text {
            objectName: "feedbackPublicPreviewError"
            Layout.fillWidth: true
            visible: text.length > 0
            textFormat: Text.PlainText
            text: Labels.error(root.errorCode)
            color: Theme.warning
            wrapMode: Text.WordWrap
        }
        RowLayout {
            Layout.fillWidth: true
            Item { Layout.fillWidth: true }
            AppButton {
                objectName: "feedbackPublicationCancel"
                text: qsTr("Back to draft")
                variant: "ghost"
                compact: true
                onClicked: root.close()
            }
            AppButton {
                objectName: "feedbackPublish"
                text: qsTr("Publish feedback")
                variant: "primary"
                compact: true
                enabled: consent.checked && !root.working && !root.errorCode && !!root.snapshot.digest
                onClicked: root.confirmed(String(root.snapshot.digest))
            }
        }
    }
}
