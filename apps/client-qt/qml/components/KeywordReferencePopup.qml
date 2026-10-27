// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import Hexproof.Native

AppPopup {
    id: root
    objectName: "keywordReferencePopup"
    width: Math.min(Theme.size(780), parent.width - Theme.size(40))
    height: Math.min(Theme.size(720), parent.height - Theme.size(40))
    padding: Theme.size(20)
    closePolicy: Popup.CloseOnEscape

    property var returnFocusItem: null
    readonly property bool chinese: preferences.uiLanguage.indexOf("zh") === 0
    readonly property var document: KeywordReference.document
    readonly property var entries: document.entries || []
    readonly property var filteredEntries: {
        const query = search.text.trim().toLowerCase()
        return entries.filter(entry => !query
            || [entry.english, entry.chinese, entry.rule].concat(entry.aliases || [])
                .some(name => String(name).toLowerCase().indexOf(query) >= 0))
    }
    readonly property string searchText: search.text

    function showFor(item) {
        returnFocusItem = item
        open()
    }
    onOpened: {
        search.clear()
        search.forceActiveFocus()
    }
    onClosed: {
        search.clear()
        if (returnFocusItem && returnFocusItem.visible && returnFocusItem.enabled)
            returnFocusItem.forceActiveFocus()
        returnFocusItem = null
    }
    onFilteredEntriesChanged: results.positionViewAtBeginning()

    contentItem: ColumnLayout {
        spacing: Theme.size(10)
        AppPopupHeader {
            titleText: qsTr("Keyword reference")
            subtitleText: qsTr("Read-only reference · search English or Chinese names")
            showClose: true
            closeObjectName: "closeKeywordReference"
            onCloseRequested: root.close()
        }
        RowLayout {
            Layout.fillWidth: true
            AppTextField {
                id: search
                objectName: "keywordSearch"
                Layout.fillWidth: true
                placeholderText: qsTr("Search keywords…")
                Accessible.name: placeholderText
                // Escape belongs to this popup; it must not reach the table.
                Keys.onEscapePressed: event => { root.close(); event.accepted = true }
            }
            AppButton {
                objectName: "resetKeywordSearch"
                text: qsTr("Reset")
                compact: true
                onClicked: { search.clear(); search.forceActiveFocus() }
            }
        }
        Text {
            Layout.fillWidth: true
            textFormat: Text.PlainText
            text: qsTr("%1 of %2 keywords").arg(root.filteredEntries.length).arg(root.entries.length)
            color: Theme.textSecondary
            font.pixelSize: Theme.fontSize(12)
        }
        ListView {
            id: results
            objectName: "keywordResults"
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            spacing: Theme.size(12)
            model: root.filteredEntries
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
            delegate: ColumnLayout {
                id: row
                required property var modelData
                width: results.width - Theme.size(18)
                spacing: Theme.size(5)
                Text {
                    Layout.fillWidth: true
                    textFormat: Text.PlainText
                    text: row.modelData.chinese + " · " + row.modelData.english
                    wrapMode: Text.WordWrap
                    color: Theme.text
                    font.pixelSize: Theme.fontSize(16)
                    font.weight: Font.DemiBold
                }
                Text {
                    Layout.fillWidth: true
                    textFormat: Text.PlainText
                    text: (row.modelData.category === "action" ? qsTr("Keyword action") : qsTr("Keyword ability"))
                        + " · CR " + row.modelData.rule
                    color: Theme.accent
                    font.pixelSize: Theme.fontSize(12)
                }
                Text {
                    objectName: "keywordExplanation"
                    Layout.fillWidth: true
                    textFormat: Text.PlainText
                    text: root.chinese ? row.modelData.summaryZh : row.modelData.summaryEn
                    wrapMode: Text.WordWrap
                    color: Theme.textSecondary
                    font.pixelSize: Theme.fontSize(14)
                }
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 1
                    color: Theme.divider
                }
            }
            Text {
                objectName: "keywordNoResults"
                anchors.centerIn: parent
                width: parent.width
                visible: root.filteredEntries.length === 0
                textFormat: Text.PlainText
                text: root.entries.length > 0 ? qsTr("No keywords found. Try another name or reset.")
                                             : qsTr("Keyword reference is unavailable.")
                wrapMode: Text.WordWrap
                horizontalAlignment: Text.AlignHCenter
                color: Theme.textSecondary
                font.pixelSize: Theme.fontSize(14)
            }
            footer: Text {
                width: results.width - Theme.size(18)
                textFormat: Text.PlainText
                text: (root.chinese ? root.document.noticeZh : root.document.noticeEn) || ""
                wrapMode: Text.WordWrap
                color: Theme.textMuted
                font.pixelSize: Theme.fontSize(11)
                topPadding: Theme.size(12)
            }
        }
        Text {
            objectName: "keywordCoverage"
            Layout.fillWidth: true
            textFormat: Text.PlainText
            text: (root.chinese ? (root.document.coverage || {}).notesZh : (root.document.coverage || {}).notesEn) || ""
            color: Theme.textSecondary
            font.pixelSize: Theme.fontSize(11)
            wrapMode: Text.WordWrap
        }
        Text {
            objectName: "keywordSource"
            Layout.fillWidth: true
            textFormat: Text.PlainText
            text: "Magic: The Gathering Comprehensive Rules · " + (root.document.source || {}).version
            color: Theme.textMuted
            font.pixelSize: Theme.fontSize(11)
            wrapMode: Text.WordWrap
        }
        AppButton {
            objectName: "keywordSourceLink"
            text: qsTr("Official rules source")
            compact: true
            variant: "ghost"
            onClicked: Qt.openUrlExternally(root.document.source.url)
        }
    }
}
