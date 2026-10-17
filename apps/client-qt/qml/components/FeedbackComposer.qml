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
    readonly property bool editable: record.editable === true || record.state === "draft"
    readonly property bool inputMatchesRecord: descriptionField.text === String(record.description || "")
        && emailField.text === String(record.replyEmail || "")
    readonly property string recordId: String(record.id || "")
    property string descriptionInputError: ""
    property string emailInputError: ""
    readonly property string inputErrorCode: descriptionField.text !== String(record.description || "")
        ? descriptionInputError || "invalid_description"
        : emailField.text !== String(record.replyEmail || "") ? emailInputError || "invalid_email" : ""
    property bool hostingAvailable: false
    property bool syncing: false
    property bool showTechnical: false
    signal imageRequested()
    signal crashRequested()
    signal hostingRequested()
    signal previewRequested(string attachmentId, string title)
    signal exportRequested()
    signal deleteRequested()
    signal cloneRequested()
    contentWidth: availableWidth
    clip: true
    ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

    function syncFields() {
        if (!descriptionField || !emailField || !categoryField) return
        syncing = true
        descriptionInputError = ""
        emailInputError = ""
        if (descriptionField.text !== String(record.description || ""))
            descriptionField.text = String(record.description || "")
        if (emailField.text !== String(record.replyEmail || ""))
            emailField.text = String(record.replyEmail || "")
        categoryField.currentIndex = Math.max(0, ["problem", "suggestion", "other"].indexOf(record.category || "problem"))
        syncing = false
    }
    function update(fields) {
        if (syncing || !service || !editable) return
        const accepted = service.updateDraft(fields) !== false
        if (fields.description !== undefined)
            descriptionInputError = accepted ? "" : service.errorCode || "invalid_description"
        if (fields.replyEmail !== undefined)
            emailInputError = accepted ? "" : service.errorCode || "invalid_email"
    }
    // Rejected text belongs to the editor until corrected. Attachment/category
    // updates republish the saved record and must not replace that pending input.
    onEditableChanged: syncFields()
    onRecordIdChanged: {
        syncFields()
        Qt.callLater(() => {
            const flickable = contentItem as Flickable
            if (flickable) flickable.contentY = 0
        })
    }
    Component.onCompleted: syncFields()

    ColumnLayout {
        width: root.availableWidth
        spacing: Theme.size(12)
        RowLayout {
            Layout.fillWidth: true
            AppComboBox {
                id: categoryField
                objectName: "feedbackCategory"
                Layout.preferredWidth: Theme.size(190)
                enabled: root.editable
                model: [qsTr("Problem"), qsTr("Suggestion"), qsTr("Other")]
                onActivated: root.update({category: ["problem", "suggestion", "other"][currentIndex]})
            }
            Text {
                objectName: "feedbackRecordState"
                Layout.fillWidth: true
                textFormat: Text.PlainText
                text: Labels.state(root.record.state)
                color: root.record.state === "received" ? Theme.success : Theme.textSecondary
                wrapMode: Text.WordWrap
            }
        }
        Text {
            Layout.fillWidth: true
            textFormat: Text.PlainText
            text: qsTr("What happened?")
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
        AppTextField {
            id: emailField
            objectName: "feedbackEmail"
            Layout.fillWidth: true
            readOnly: !root.editable
            maximumLength: 254
            maximumUtf8Bytes: 254
            placeholderText: qsTr("Contact email (optional)")
            inputMethodHints: Qt.ImhEmailCharactersOnly
            onTextEdited: root.update({replyEmail: text})
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
            visible: root.record.state === "received"
            textFormat: Text.PlainText
            text: qsTr("Received confirms storage by support. It does not confirm review or resolution.")
            color: Theme.textSecondary
            font.pixelSize: Theme.fontSize(12)
            wrapMode: Text.WordWrap
        }
        Text {
            objectName: "feedbackReceivedLocalRetention"
            Layout.fillWidth: true
            visible: root.record.state === "received"
            textFormat: Text.PlainText
            text: qsTr("On this device, received content is kept for up to 30 days and receipts for up to 90 days, subject to storage limits.")
            color: Theme.textMuted
            font.pixelSize: Theme.fontSize(12)
            wrapMode: Text.WordWrap
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
        Repeater {
            model: root.record.attachments || []
            delegate: Surface {
                required property var modelData
                Layout.fillWidth: true
                implicitHeight: attachmentRow.implicitHeight + Theme.size(20)
                radius: Theme.radiusSmall
                RowLayout {
                    id: attachmentRow
                    anchors.fill: parent
                    anchors.margins: Theme.size(10)
                    spacing: Theme.size(8)
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
                text: qsTr("Create editable copy")
                variant: "secondary"
                compact: true
                onClicked: root.cloneRequested()
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
