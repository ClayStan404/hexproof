// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Dialogs
import QtQuick.Layouts

Popup {
    id: root

    property var manager: null
    property string deckName: ""
    property var cardRequests: []
    property bool exporting: false
    property var exportResult: ({})
    property string errorMessage: ""
    property url destination: ""
    property url completedDestination: ""
    readonly property bool managerBusy: manager !== null && manager.busy
    readonly property bool canExport: manager !== null && !managerBusy
                                      && !exporting && cardRequests.length > 0
    onErrorMessageChanged: {
        if (errorMessage.length > 0)
            exportBody.contentY = 0
    }

    function prepare(name, requests) {
        if (exporting)
            return false
        deckName = name
        // Keep the selected deck stable while the native save dialog is open.
        cardRequests = JSON.parse(JSON.stringify(requests || []))
        exportResult = ({})
        errorMessage = cardRequests.length > 0 ? ""
                       : qsTr("No cards are available for this deck.")
        destination = ""
        exportBody.contentY = 0
        open()
        return true
    }

    function chooseDestination() {
        if (!canExport)
            return
        exportFileDialog.selectedFile = manager.suggestedDeckExportUrl(deckName)
        exportFileDialog.open()
    }

    function startExport(fileUrl) {
        if (exporting)
            return
        if (!manager || cardRequests.length === 0) {
            errorMessage = qsTr("No cards are available for this deck.")
            return
        }
        if (manager.busy) {
            errorMessage = qsTr("Another card-art operation is running. Try again when it finishes.")
            return
        }
        destination = fileUrl
        exportResult = ({})
        errorMessage = ""
        exportBody.contentY = 0
        exporting = true
        manager.exportDeckPack(destination, cardRequests)
    }

    function resultSummary() {
        if (!exportResult.ok)
            return ""
        const lines = [qsTr("Exported %1 image(s) across %2 cache mapping(s).")
                       .arg(exportResult.imageCount || 0).arg(exportResult.entryCount || 0)]
        lines.push(qsTr("Checked %1 printing(s) and %2 card face(s).")
                   .arg(exportResult.requestedPrintingCount || 0)
                   .arg(exportResult.requestedFaceCount || 0))
        lines.push(qsTr("Image data: %1").arg(formatBytes(exportResult.bytes)))
        if ((exportResult.missingPrintingCount || 0) > 0
                || (exportResult.missingFaceCount || 0) > 0)
            lines.push(qsTr("Not included: %1 printing(s), %2 card face(s) without valid cached images. Cache or repair this deck's art, then export again for a more complete pack.")
                       .arg(exportResult.missingPrintingCount || 0)
                       .arg(exportResult.missingFaceCount || 0))
        if ((exportResult.skippedEntryCount || 0) > 0)
            lines.push(qsTr("Skipped %1 unavailable or invalid cache mapping(s).")
                       .arg(exportResult.skippedEntryCount))
        if (!exportResult.faceCoverageVerified)
            lines.push(qsTr("The local card database could not verify every card face. This pack may be incomplete."))
        return lines.join("\n\n")
    }

    function formatBytes(value) {
        let bytes = Number(value || 0)
        if (bytes < 1024)
            return qsTr("%1 B").arg(Math.round(bytes))
        const units = [qsTr("KiB"), qsTr("MiB"), qsTr("GiB")]
        let unit = 0
        bytes /= 1024
        while (bytes >= 1024 && unit < units.length - 1) {
            bytes /= 1024
            ++unit
        }
        return qsTr("%1 %2").arg(bytes.toFixed(bytes >= 10 ? 1 : 2)).arg(units[unit])
    }

    parent: Overlay.overlay
    x: Math.round((parent.width - width) / 2)
    y: Math.round((parent.height - height) / 2)
    width: Math.min(Theme.size(560), parent.width - Theme.size(40))
    height: Math.min(implicitHeight, parent.height - Theme.size(40))
    padding: Theme.size(24)
    modal: true
    focus: true
    closePolicy: exporting ? Popup.NoAutoClose
                           : Popup.CloseOnEscape | Popup.CloseOnPressOutside

    Overlay.modal: Rectangle { color: "#A6050B09" }
    background: Rectangle {
        color: Theme.surfaceElevated
        radius: Theme.radiusLarge
        border.width: 1
        border.color: Theme.borderStrong
    }

    contentItem: ColumnLayout {
        spacing: Theme.size(18)

        Text {
            textFormat: Text.PlainText
            Layout.fillWidth: true
            text: qsTr("Export card art")
            color: Theme.text
            font.pixelSize: Theme.fontSize(20)
            font.weight: Font.DemiBold
        }

        Flickable {
            id: exportBody
            objectName: "deckArtExportBody"
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumHeight: 0
            implicitHeight: exportContent.implicitHeight
            contentWidth: width
            contentHeight: exportContent.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

            ColumnLayout {
                id: exportContent
                width: exportBody.width
                spacing: Theme.size(14)

                InfoBanner {
                    objectName: "deckArtExportError"
                    Layout.fillWidth: true
                    visible: root.errorMessage.length > 0
                    tone: "error"
                    message: root.errorMessage
                }

                InfoBanner {
                    Layout.fillWidth: true
                    visible: root.managerBusy && !root.exporting && root.errorMessage.length === 0
                    tone: "warning"
                    message: qsTr("Another card-art operation is running. Try again when it finishes.")
                }

                InfoBanner {
                    objectName: "deckArtExportResult"
                    Layout.fillWidth: true
                    visible: !!root.exportResult.ok
                    tone: (root.exportResult.missingFaceCount || 0) > 0
                          || (root.exportResult.missingPrintingCount || 0) > 0
                          || (root.exportResult.skippedEntryCount || 0) > 0
                          || !root.exportResult.faceCoverageVerified ? "warning" : "success"
                    message: root.resultSummary()
                }

                Text {
                    textFormat: Text.PlainText
                    objectName: "deckArtExportName"
                    Layout.fillWidth: true
                    text: root.deckName
                    color: Theme.primary
                    font.pixelSize: Theme.fontSize(17)
                    font.weight: Font.DemiBold
                    wrapMode: Text.WrapAnywhere
                    maximumLineCount: 2
                    elide: Text.ElideRight
                }

                Text {
                    textFormat: Text.PlainText
                    objectName: "deckArtExportDestination"
                    Layout.fillWidth: true
                    visible: !!root.exportResult.ok
                    text: root.destination.toString()
                    color: Theme.textMuted
                    font.pixelSize: Theme.fontSize(12)
                    wrapMode: Text.WrapAnywhere
                }

                Text {
                    textFormat: Text.PlainText
                    Layout.fillWidth: true
                    text: qsTr("Only this deck's locally cached images are exported, including its saved tokens and emblems, available languages, and card faces. Missing images are skipped; nothing is downloaded automatically.")
                    color: Theme.textSecondary
                    font.pixelSize: Theme.fontSize(14)
                    wrapMode: Text.WordWrap
                }

                Text {
                    textFormat: Text.PlainText
                    Layout.fillWidth: true
                    text: qsTr("Share the .hexproof-artpack file. Other players can import it in Settings → Card art storage → Manage → Import. The pack does not include the deck list.")
                    color: Theme.textSecondary
                    font.pixelSize: Theme.fontSize(14)
                    wrapMode: Text.WordWrap
                }

                Text {
                    textFormat: Text.PlainText
                    Layout.fillWidth: true
                    text: qsTr("Card images belong to their respective rights holders. Share only where you have permission.")
                    color: Theme.textMuted
                    font.pixelSize: Theme.fontSize(12)
                    wrapMode: Text.WordWrap
                }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            visible: root.exporting
            spacing: Theme.size(8)

            ProgressBar {
                objectName: "deckArtExportProgress"
                Layout.fillWidth: true
                indeterminate: root.exporting
            }

            Text {
                textFormat: Text.PlainText
                Layout.fillWidth: true
                text: qsTr("Exporting card art pack… Large Cube packs may take a while.")
                color: Theme.textSecondary
                font.pixelSize: Theme.fontSize(14)
                wrapMode: Text.WordWrap
            }
        }

        Flow {
            Layout.fillWidth: true
            spacing: Theme.size(10)

            AppButton {
                objectName: "closeDeckArtExportButton"
                compact: true
                variant: "ghost"
                text: qsTr("Close")
                enabled: !root.exporting
                onClicked: root.close()
            }

            AppButton {
                objectName: "saveDeckArtPackButton"
                compact: true
                variant: "primary"
                text: qsTr("Save card art pack…")
                enabled: root.canExport
                onClicked: root.chooseDestination()
            }
        }
    }

    FileDialog {
        id: exportFileDialog
        objectName: "deckArtExportFileDialog"
        title: qsTr("Export card art pack")
        fileMode: FileDialog.SaveFile
        defaultSuffix: "hexproof-artpack"
        nameFilters: [qsTr("Hexproof card art packs") + " (*.hexproof-artpack)"]
        onAccepted: root.startExport(selectedFile)
    }

    Connections {
        target: root.manager
        ignoreUnknownSignals: true
        function onDeckExportFinished(result) {
            root.completedDestination = result.fileUrl || ""
            if (!root.exporting
                    || root.completedDestination.toString() !== root.destination.toString())
                return
            root.exporting = false
            root.exportResult = result
            root.errorMessage = result.ok ? "" : I18n.status(result.error || "")
            exportBody.contentY = 0
        }
    }
}
