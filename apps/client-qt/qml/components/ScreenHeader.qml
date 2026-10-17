// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Layouts

Item {
    id: root

    property string title: ""
    property string subtitle: ""
    property bool showBack: true
    property bool titleEditable: false
    property bool titleEditing: false
    property bool compact: false
    signal backRequested()
    signal titleEdited(string title)

    function beginTitleEditing() {
        if (!titleEditable)
            return
        titleEditor.text = root.title
        titleEditing = true
        titleEditor.forceActiveFocus()
        titleEditor.selectAll()
    }

    function cancelTitleEditing() {
        titleEditing = false
        titleEditor.text = root.title
    }

    function commitTitleEditing() {
        if (!titleEditing)
            return
        const next = titleEditor.text.trim()
        titleEditing = false
        if (next.length === 0 || next === root.title)
            return
        root.titleEdited(next)
    }

    implicitHeight: Math.max(Theme.size(root.compact ? 44 : 58), headerRow.implicitHeight)

    RowLayout {
        id: headerRow
        anchors.fill: parent
        spacing: Theme.size(14)

        AppButton {
            objectName: "screenBackButton"
            visible: root.showBack
            variant: "ghost"
            compact: true
            text: qsTr("Back")
            leadingText: "‹"
            onClicked: root.backRequested()
        }

        BrandMark {
            visible: !root.showBack
            markSize: Theme.size(34)
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: Theme.size(2)

            Text {
                objectName: "screenHeaderTitle"
                textFormat: Text.PlainText
                Layout.fillWidth: true
                visible: !root.titleEditing
                text: root.title
                color: titleHover.hovered && root.titleEditable ? Theme.primary : Theme.text
                font.pixelSize: Theme.fontSize(18)
                font.weight: Font.DemiBold
                wrapMode: Text.Wrap
                HoverHandler {
                    id: titleHover
                    enabled: root.titleEditable
                    cursorShape: Qt.IBeamCursor
                }
                TapHandler {
                    enabled: root.titleEditable
                    onTapped: root.beginTitleEditing()
                }
            }

            TextInput {
                id: titleEditor
                objectName: "screenHeaderTitleField"
                Layout.fillWidth: true
                visible: root.titleEditing
                color: Theme.text
                font.pixelSize: Theme.fontSize(18)
                font.weight: Font.DemiBold
                selectByMouse: true
                clip: true
                onAccepted: root.commitTitleEditing()
                onEditingFinished: root.commitTitleEditing()
                Keys.onEscapePressed: event => {
                    root.cancelTitleEditing()
                    event.accepted = true
                }
            }

            Text {
                objectName: "screenHeaderSubtitle"
                textFormat: Text.PlainText
                Layout.fillWidth: true
                visible: root.subtitle.length > 0
                text: root.subtitle
                color: Theme.textMuted
                font.pixelSize: Theme.fontSize(12)
                wrapMode: Text.Wrap
            }
        }

    }
}
