// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Dialogs
import QtQuick.Layouts

Popup {
    id: root
    objectName: "forgeHostingDialog"
    property var service: null
    property var wsModel: null
    property string feedback: ""
    parent: Overlay.overlay
    x: parent ? Math.round((parent.width - width) / 2) : 0
    y: parent ? Math.round((parent.height - height) / 2) : 0
    width: parent ? Math.min(Theme.size(620), parent.width - Theme.size(40)) : 0
    height: parent ? Math.min(implicitHeight, parent.height - Theme.size(40)) : 0
    padding: Theme.size(24)
    modal: true
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    onOpened: {
        feedback = ""
        mirrorField.text = service ? service.downloadMirror : ""
        if (wsModel) wsModel.playerHostingAction("refresh")
    }
    background: Rectangle {
        color: Theme.surfaceElevated
        radius: Theme.radiusLarge
        border.width: 1
        border.color: Theme.borderStrong
    }
    Overlay.modal: Rectangle { color: "#A6050B09" }

    contentItem: ScrollView {
        implicitHeight: body.implicitHeight
        contentWidth: availableWidth
        clip: true
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
        ColumnLayout {
            id: body
            width: parent.width
            spacing: Theme.size(14)
            RowLayout {
                Layout.fillWidth: true
                Text {
                    Layout.fillWidth: true
                    textFormat: Text.PlainText
                    text: qsTr("Local Forge")
                    color: Theme.text
                    font.pixelSize: Theme.fontSize(22)
                    font.weight: Font.DemiBold
                }
                AppButton {
                    objectName: "forgeHostingClose"
                    text: qsTr("Close")
                    onClicked: root.close()
                }
            }
            Text {
                Layout.fillWidth: true
                textFormat: Text.PlainText
                text: root.service ? root.service.status : ""
                color: Theme.textSecondary
                font.pixelSize: Theme.fontSize(13)
                wrapMode: Text.WordWrap
            }
            ForgeMigrationControls {
                Layout.fillWidth: true
                wsModel: root.wsModel
            }
            ProgressBar {
                Layout.fillWidth: true
                visible: root.service ? root.service.busy && !root.service.hosting : false
                value: root.service ? root.service.progress : 0
                indeterminate: value <= 0
            }
            AppButton {
                objectName: "forgeRuntimePrepare"
                visible: root.service ? !root.service.hosting : true
                text: root.service && root.service.busy ? qsTr("Cancel") : qsTr("Prepare / retry")
                enabled: root.service ? !root.service.hosting : false
                onClicked: {
                    if (root.service.busy) root.service.cancel()
                    else root.service.prepare()
                }
            }
            Text {
                Layout.fillWidth: true
                textFormat: Text.PlainText
                text: qsTr("Interrupted downloads resume automatically. Only the player hosting Forge needs this installation.")
                color: Theme.textMuted
                font.pixelSize: Theme.fontSize(12)
                wrapMode: Text.WordWrap
            }
            AppButton {
                objectName: "forgeRuntimeImport"
                text: qsTr("Import offline pack")
                enabled: root.service ? !root.service.busy : false
                variant: "secondary"
                onClicked: importPackDialog.open()
            }
            Text {
                Layout.fillWidth: true
                textFormat: Text.PlainText
                text: qsTr("Select a shared .hexproof-forgepack file for your system. It includes Forge and Java, so installation needs no download.")
                color: Theme.textMuted
                font.pixelSize: Theme.fontSize(12)
                wrapMode: Text.WordWrap
            }
            Text {
                textFormat: Text.PlainText
                text: qsTr("Download mirror (optional)")
                color: Theme.text
                font.pixelSize: Theme.fontSize(14)
            }
            AppTextField {
                id: mirrorField
                objectName: "forgeDownloadMirror"
                Layout.fillWidth: true
                enabled: root.service ? !root.service.busy : false
                placeholderText: qsTr("HTTPS mirror directory; leave empty for the default source")
                selectByMouse: true
                maximumLength: 2048
            }
            Text {
                Layout.fillWidth: true
                textFormat: Text.PlainText
                text: qsTr("Use a mirror prepared for Hexproof. Downloads still use the pinned file checksums. The original source is tried if the mirror fails.")
                color: Theme.textMuted
                font.pixelSize: Theme.fontSize(12)
                wrapMode: Text.WordWrap
            }
            AppButton {
                objectName: "forgeSaveMirror"
                text: qsTr("Save download source")
                enabled: root.service ? !root.service.busy : false
                onClicked: root.feedback = root.service.saveDownloadMirror(mirrorField.text)
                    ? qsTr("Download source saved.")
                    : qsTr("Enter an HTTPS directory without a password, query, or fragment.")
            }
            AppButton {
                objectName: "forgeClearCache"
                text: qsTr("Clear download and old runtime cache")
                enabled: root.service ? !root.service.busy : false
                variant: "secondary"
                onClicked: root.service.clearCache()
            }
            Text {
                Layout.fillWidth: true
                textFormat: Text.PlainText
                text: qsTr("Keeps current and running installations. Partial downloads are removed and will restart from the beginning.")
                color: Theme.textMuted
                font.pixelSize: Theme.fontSize(12)
                wrapMode: Text.WordWrap
            }
            AppButton {
                objectName: "forgeExportDiagnostics"
                text: qsTr("Export hosting diagnostics")
                enabled: root.service !== null
                variant: "secondary"
                onClicked: {
                    saveReport.selectedFile = root.service.suggestedDiagnosticsUrl()
                    saveReport.open()
                }
            }
            Text {
                Layout.fillWidth: true
                textFormat: Text.PlainText
                text: qsTr("Includes versions, platform and recent hosting states. Excludes decks, cards, connection credentials and local paths.")
                color: Theme.textMuted
                font.pixelSize: Theme.fontSize(12)
                wrapMode: Text.WordWrap
            }
            Text {
                objectName: "forgeHostingFeedback"
                Layout.fillWidth: true
                visible: text.length > 0
                textFormat: Text.PlainText
                text: root.feedback
                color: Theme.text
                font.pixelSize: Theme.fontSize(12)
                wrapMode: Text.WordWrap
            }
        }
    }
    FileDialog {
        id: importPackDialog
        objectName: "forgeImportFileDialog"
        title: qsTr("Import offline Forge pack")
        fileMode: FileDialog.OpenFile
        nameFilters: [qsTr("Forge offline packs") + " (*.hexproof-forgepack)"]
        onAccepted: {
            root.feedback = ""
            if (root.service) root.service.importPack(selectedFile)
        }
    }
    FileDialog {
        id: saveReport
        objectName: "forgeDiagnosticsFileDialog"
        title: qsTr("Save hosting diagnostics")
        fileMode: FileDialog.SaveFile
        nameFilters: [qsTr("JSON files") + " (*.json)"]
        defaultSuffix: "json"
        onAccepted: root.feedback = root.service && root.service.exportDiagnostics(selectedFile)
            ? qsTr("Diagnostics saved.") : qsTr("Could not save the diagnostics file.")
    }
}
