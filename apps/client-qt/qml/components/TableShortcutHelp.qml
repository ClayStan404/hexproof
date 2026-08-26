// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

pragma ComponentBehavior: Bound
pragma Translator: "Table"

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

Popup {
    id: root

    objectName: "tableShortcutHelp"
    parent: Overlay.overlay
    x: Math.round((parent.width - width) / 2)
    y: Math.round((parent.height - height) / 2)
    width: Math.min(Theme.size(560), parent.width - Theme.size(48))
    height: Math.min(Theme.size(620), parent.height - Theme.size(56))
    padding: Theme.size(22)
    modal: true
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    Overlay.modal: Rectangle { color: "#A6050B09" }

    ShortcutActionCatalog { id: shortcutCatalog }

    background: Rectangle {
        color: Theme.surfaceElevated
        radius: Theme.radiusLarge
        border.width: 1
        border.color: Theme.borderStrong
    }

    readonly property var shortcutRows: buildShortcutRows()

    function buildShortcutRows() {
        const revision = preferences.shortcutRevision
        const rows = shortcutCatalog.tableActions.map(item => ({
            "keys": preferences.shortcutDisplay(item.id),
            "action": item.label
        }))
        rows.push(
            {"keys": "Ctrl + wheel", "action": qsTr("Adjust battlefield card size")},
            {"keys": "← / → / Home / End", "action": qsTr("Move between hand cards")},
            {"keys": "Enter", "action": qsTr("Open the focused hand card menu")})
        return rows
    }

    contentItem: ColumnLayout {
        spacing: Theme.size(12)

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.size(12)

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Theme.size(3)

                Text {
                    textFormat: Text.PlainText
                    Layout.fillWidth: true
                    text: qsTr("Table shortcuts")
                    color: Theme.text
                    font.pixelSize: Theme.fontSize(20)
                    font.weight: Font.DemiBold
                }
                Text {
                    textFormat: Text.PlainText
                    Layout.fillWidth: true
                    text: qsTr("Shortcuts are paused while a text field or modal editor is open.")
                    color: Theme.textSecondary
                    font.pixelSize: Theme.fontSize(11)
                    wrapMode: Text.WordWrap
                }
            }

            AppButton {
                objectName: "closeShortcutHelpButton"
                compact: true
                variant: "ghost"
                text: "×"
                accessibleName: qsTr("Close")
                Layout.preferredWidth: Theme.size(40)
                onClicked: root.close()
            }
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 1
            color: Theme.divider
        }

        ListView {
            id: shortcutList
            objectName: "tableShortcutHelpList"
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            spacing: Theme.size(2)
            model: root.shortcutRows

            delegate: RowLayout {
                id: shortcutRow
                required property var modelData
                width: ListView.view.width
                spacing: Theme.size(12)

                Text {
                    textFormat: Text.PlainText
                    text: shortcutRow.modelData.keys
                    color: Theme.accent
                    font.pixelSize: Theme.fontSize(12)
                    font.weight: Font.DemiBold
                    Layout.preferredWidth: Theme.size(168)
                }
                Text {
                    textFormat: Text.PlainText
                    Layout.fillWidth: true
                    text: shortcutRow.modelData.action
                    color: Theme.textSecondary
                    font.pixelSize: Theme.fontSize(12)
                    wrapMode: Text.WordWrap
                }
            }
        }
    }
}
