// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors
pragma ComponentBehavior: Bound
pragma Translator: "Feedback"
import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

AppPopup {
    id: root
    objectName: "feedbackNotice"
    property string noticeText: ""
    width: parent ? Math.min(Theme.size(760), parent.width - Theme.size(32)) : 0
    height: parent ? Math.min(Theme.size(720), parent.height - Theme.size(32)) : 0
    z: 340
    closePolicy: Popup.CloseOnEscape
    onOpened: {
        const flickable = noticeScroll.contentItem as Flickable
        if (flickable) flickable.contentY = 0
        noticeContent.forceActiveFocus()
    }
    onClosed: noticeText = ""
    contentItem: ColumnLayout {
        spacing: Theme.size(12)
        AppPopupHeader { titleText: qsTr("Public feedback notice") }
        ScrollView {
            id: noticeScroll
            objectName: "feedbackNoticeScroll"
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentWidth: availableWidth
            clip: true
            ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
            TextArea {
                id: noticeContent
                objectName: "feedbackNoticeText"
                text: root.noticeText
                Accessible.name: qsTr("Public feedback notice")
                textFormat: TextEdit.PlainText
                readOnly: true
                selectByMouse: true
                wrapMode: TextEdit.Wrap
                color: Theme.text
                font.pixelSize: Theme.fontSize(14)
                background: Rectangle { color: Theme.surface; radius: Theme.radiusSmall }
            }
        }
        AppButton {
            objectName: "feedbackNoticeClose"
            Layout.alignment: Qt.AlignRight
            text: qsTr("Close")
            onClicked: root.close()
        }
    }
}
