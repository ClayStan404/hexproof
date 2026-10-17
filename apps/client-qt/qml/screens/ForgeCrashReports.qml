// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import "../components"

Page {
    id: root
    objectName: "forgeCrashReportsScreen"
    property var service: ws.crashReports
    property string selectedId: ""
    readonly property bool compactLayout: width < Theme.size(1100)
    readonly property var appWindow: ApplicationWindow.window
    background: AppBackground { }
    function refreshSelection() {
        if (!service) return
        const entries = service.entries
        if (!entries.some(function(entry) { return entry.reportId === selectedId }))
            selectedId = entries.length ? entries[0].reportId : ""
    }
    Component.onCompleted: {
        service.refresh()
        refreshSelection()
    }
    Connections {
        target: root.service
        function onEntriesChanged() { root.refreshSelection() }
    }
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.pageMargin
        spacing: Theme.size(16)
        RowLayout {
            Layout.fillWidth: true
            AppButton {
                objectName: "forgeCrashBack"
                text: qsTr("Back")
                onClicked: root.appWindow.popScreen()
            }
            Text {
                Layout.fillWidth: true
                textFormat: Text.PlainText
                text: qsTr("Forge crash reports")
                color: Theme.text
                font.pixelSize: Theme.fontSize(24)
                wrapMode: Text.WordWrap
            }
            FeedbackEntryButton { }
        }
        Text {
            Layout.fillWidth: true
            textFormat: Text.PlainText
            text: qsTr("Reports work offline and are kept for up to seven days, subject to storage limits. Nothing is uploaded automatically; send a copied or saved report to support when you choose.")
            color: Theme.textSecondary
            wrapMode: Text.WordWrap
        }
        Text {
            visible: root.service.entries.length === 0
            textFormat: Text.PlainText
            text: qsTr("No Forge crash reports.")
            color: Theme.textMuted
        }
        GridLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            columns: root.compactLayout ? 1 : 2
            rowSpacing: Theme.size(12)
            columnSpacing: Theme.size(20)
            ListView {
                id: list
                Layout.preferredWidth: root.compactLayout ? -1 : Theme.size(230)
                Layout.fillWidth: root.compactLayout
                Layout.preferredHeight: root.compactLayout ? Theme.size(56) : -1
                Layout.fillHeight: !root.compactLayout
                orientation: root.compactLayout ? ListView.Horizontal : ListView.Vertical
                clip: true
                spacing: Theme.size(8)
                model: root.service.entries
                ScrollBar.vertical: ScrollBar { policy: root.compactLayout ? ScrollBar.AlwaysOff : ScrollBar.AsNeeded }
                ScrollBar.horizontal: ScrollBar { policy: root.compactLayout ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff }
                delegate: AppButton {
                    required property var modelData
                    width: root.compactLayout ? Theme.size(230) : list.width
                    text: new Date(modelData.occurredAt).toLocaleString(Qt.locale(), Locale.ShortFormat)
                    variant: root.selectedId === modelData.reportId ? "highlight" : "secondary"
                    onClicked: root.selectedId = modelData.reportId
                }
            }
            ForgeCrashReportPanel {
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: root.selectedId.length > 0
                service: root.service
                reportId: root.selectedId
                showDetails: true
            }
        }
    }
}
