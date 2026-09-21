// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

pragma ComponentBehavior: Bound
pragma Translator: "Table"

import QtQuick
import QtQuick.Layouts

AppPopup {
    id: root

    objectName: "tableShortcutHelp"
    width: Math.min(Theme.size(560), parent.width - Theme.size(48))
    height: Math.min(Theme.size(620), parent.height - Theme.size(56))
    padding: Theme.size(22)

    ShortcutActionCatalog { id: shortcutCatalog }

    readonly property var shortcutRows: buildShortcutRows()

    function buildShortcutRows() {
        const revision = preferences.shortcutRevision
        const rows = shortcutCatalog.tableActions.map(item => ({
            "keys": preferences.shortcutDisplay(item.id),
            "action": item.label
        }))
        rows.push(
            {"keys": "Ctrl + wheel", "action": qsTranslate("Table", "Adjust battlefield card size")},
            {"keys": "← / → / Home / End", "action": qsTranslate("Table", "Move between hand cards")},
            {"keys": "Enter", "action": qsTranslate("Table", "Open the focused hand card menu")})
        return rows
    }

    contentItem: ColumnLayout {
        spacing: Theme.size(12)

        AppPopupHeader {
            titleText: qsTranslate("Table", "Table shortcuts")
            subtitleText: qsTranslate("Table", "Shortcuts are paused while a text field or modal editor is open.")
            showClose: true
            closeObjectName: "closeShortcutHelpButton"
            onCloseRequested: root.close()
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
