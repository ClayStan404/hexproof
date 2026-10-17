// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors
pragma Translator: "Feedback"
import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

AppPopup {
    id: root
    objectName: "feedbackAttachmentPreview"
    property string previewContent: ""
    property string titleText: ""
    readonly property bool isImage: previewContent.indexOf("data:image/") === 0
    width: parent ? Math.min(Theme.size(960), parent.width - Theme.size(32)) : 0
    height: parent ? Math.min(Theme.size(720), parent.height - Theme.size(32)) : 0
    z: 310
    closePolicy: Popup.CloseOnEscape
    onClosed: previewContent = ""
    contentItem: ColumnLayout {
        spacing: Theme.size(12)
        AppPopupHeader { titleText: root.titleText }
        Image {
            objectName: "feedbackPreviewImage"
            visible: root.isImage
            Layout.fillWidth: true
            Layout.fillHeight: true
            source: root.isImage ? root.previewContent : ""
            fillMode: Image.PreserveAspectFit
            asynchronous: true
            cache: false
        }
        ScrollView {
            visible: !root.isImage
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentWidth: availableWidth
            clip: true
            TextArea {
                objectName: "feedbackPreviewText"
                textFormat: TextEdit.PlainText
                text: root.isImage ? "" : root.previewContent
                readOnly: true
                selectByMouse: true
                wrapMode: TextEdit.WrapAnywhere
                color: Theme.text
                font.pixelSize: Theme.fontSize(12)
                background: Rectangle { color: Theme.surface; radius: Theme.radiusSmall }
            }
        }
        AppButton {
            objectName: "feedbackPreviewClose"
            Layout.alignment: Qt.AlignRight
            text: qsTr("Close")
            onClicked: root.close()
        }
    }
}
