// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Dialogs
import QtQuick.Layouts

ColumnLayout {
    id: root
    property var service: null
    property string reportId: ""
    property bool showDetails: false
    property string saveDialogObjectName: "forgeCrashSaveDialog"
    property var record: ({})
    property string details: ""
    readonly property bool available: !!record.reportId
    readonly property var appWindow: ApplicationWindow.window
    spacing: Theme.size(12)

    function reload() {
        record = service && reportId ? service.report(reportId) : ({})
        details = service && record.reportId ? service.reportText(reportId) : ""
    }
    onReportIdChanged: reload()
    onServiceChanged: reload()
    Component.onCompleted: reload()
    Connections {
        target: root.service
        function onEntriesChanged() { root.reload() }
    }
    function cause() {
        switch ((record.failure || {}).kind) {
        case "engine_exception": return qsTr("Forge encountered an engine error.")
        case "resource_exhausted": return qsTr("Forge reported a resource error.")
        case "execution_timeout": return qsTr("An engine operation timed out.")
        case "protocol_failure": return qsTr("Engine communication or game state became invalid.")
        case "process_exit": return qsTr("The Forge process stopped. The exact cause may be unknown.")
        case "host_connection_lost": return qsTr("The hosting connection was lost.")
        default: return qsTr("This report has expired or is no longer available.")
        }
    }
    function attribution() {
        switch ((record.context || {}).attribution) {
        case "execution_site": return qsTr("The report identifies the operation where the error was captured.")
        case "resolution_context": return qsTr("An effect was resolving; the exact failing operation is unknown.")
        case "recent_context": return qsTr("Only preceding public events are available; they do not establish the cause.")
        default: return qsTr("No reliable failing operation or public card source was captured.")
        }
    }
    function feedback() {
        if (!service || service.operationReportId !== reportId) return ""
        switch (service ? service.operationStatus : "") {
        case "copied": return qsTr("Report copied.")
        case "saved": return qsTr("Report saved.")
        case "copy_failed": return qsTr("Could not copy the report.")
        case "export_failed": return qsTr("Could not save the report. Choose another location.")
        case "report_expired": return qsTr("This report has expired or is no longer available.")
        default: return ""
        }
    }
    ScrollView {
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.minimumHeight: 0
        implicitHeight: reportBody.implicitHeight
        contentWidth: availableWidth
        clip: true
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
        ColumnLayout {
            id: reportBody
            width: parent.width
            spacing: Theme.size(12)
            Text {
                Layout.fillWidth: true
                textFormat: Text.PlainText
                text: root.cause()
                color: Theme.text
                font.pixelSize: Theme.fontSize(18)
                font.weight: Font.DemiBold
                wrapMode: Text.WordWrap
            }
            Text {
                Layout.fillWidth: true
                visible: root.available
                textFormat: Text.PlainText
                text: root.attribution() + " " + qsTr("A recorded card or effect is context, not proof that it alone caused the failure.")
                color: Theme.textSecondary
                wrapMode: Text.WordWrap
            }
            Text {
                Layout.fillWidth: true
                visible: root.available && ((root.record.context || {}).sources || []).length > 0
                textFormat: Text.PlainText
                text: qsTr("Public sources: %1").arg(((root.record.context || {}).sources || [])
                      .map(function(source) { return (source.identity || {}).name || "" }).join(" · "))
                color: Theme.text
                wrapMode: Text.WordWrap
            }
            Text {
                Layout.fillWidth: true
                visible: root.available
                textFormat: Text.PlainText
                text: root.record.collectionState === "collecting"
                      ? qsTr("Collecting final process evidence…")
                      : root.record.collectionState === "partial"
                        ? qsTr("Some evidence is unavailable. Missing details do not establish the cause.")
                        : qsTr("Evidence collection finished.")
                color: Theme.textSecondary
                wrapMode: Text.WordWrap
            }
            Text {
                Layout.fillWidth: true
                visible: root.available
                textFormat: Text.PlainText
                text: qsTr("Report ID: %1").arg(root.reportId)
                color: Theme.textMuted
                wrapMode: Text.WrapAnywhere
                font.pixelSize: Theme.fontSize(12)
            }
            TextArea {
                Layout.fillWidth: true
                visible: root.showDetails && root.available
                objectName: "forgeCrashReportDetails"
                textFormat: TextEdit.PlainText
                text: root.details
                readOnly: true
                selectByMouse: true
                wrapMode: TextEdit.WrapAnywhere
                color: Theme.textSecondary
                font.family: "monospace"
                font.pixelSize: Theme.fontSize(12)
                background: Rectangle { color: Theme.surface; radius: Theme.radiusSmall }
            }
            Text {
                Layout.fillWidth: true
                visible: root.service ? root.service.storageError.length > 0 : false
                textFormat: Text.PlainText
                text: qsTr("Local history could not be saved. Copy or save this report before closing the application.")
                color: Theme.warning
                wrapMode: Text.WordWrap
            }
            Text {
                objectName: "forgeCrashOperationFeedback"
                Layout.fillWidth: true
                visible: text.length > 0
                textFormat: Text.PlainText
                text: root.feedback()
                color: Theme.textSecondary
                wrapMode: Text.WordWrap
            }
        }
    }
    Flow {
        Layout.fillWidth: true
        spacing: Theme.size(10)
        AppButton {
            objectName: "forgeCrashSendFeedback"
            text: qsTranslate("Feedback", "Report this problem")
            visible: root.appWindow && typeof root.appWindow.openFeedback === "function"
            enabled: root.available
            onClicked: root.appWindow.openFeedback({feature: "forge_table"}, "crash", root.record)
        }
        AppButton {
            objectName: "forgeCrashCopy"
            text: qsTr("Copy report")
            enabled: root.available
            onClicked: root.service.copyReport(root.reportId)
        }
        AppButton {
            objectName: "forgeCrashSave"
            text: qsTr("Save report")
            enabled: root.available
            variant: "secondary"
            onClicked: {
                saveDialog.selectedFile = root.service.suggestedFile(root.reportId)
                saveDialog.open()
            }
        }
    }
    FileDialog {
        id: saveDialog
        objectName: root.saveDialogObjectName
        title: qsTr("Save Forge crash report")
        fileMode: FileDialog.SaveFile
        nameFilters: [qsTr("JSON report (*.json)")]
        defaultSuffix: "json"
        onAccepted: root.service.saveReport(root.reportId, selectedFile)
    }
}
