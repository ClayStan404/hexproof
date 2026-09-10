// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Dialogs
import QtQuick.Layouts
import "../components"

Page {
    id: root
    readonly property var appWindow: ApplicationWindow.window
    property var store: typeof customCardArtStore !== "undefined" ? customCardArtStore : null
    property var catalogModel: typeof cardCatalog !== "undefined" ? cardCatalog : null
    property string filterText: ""
    property var selectedIds: []
    property var exportIds: []
    property var pendingEntry: ({})
    property string pendingInspection: ""
    property url pendingSource: ""
    property url inspectionSource: ""
    property string operationResultMessage: ""
    readonly property bool busy: !!store && store.busy
    readonly property var entries: store ? store.entries : []
    readonly property var filteredEntries: Array.from(entries).filter(entry => {
        const query = filterText.trim().toLocaleLowerCase()
        return [entry.name, entry.faceName, entry.setCode, entry.collectorNumber]
                .join(" ").toLocaleLowerCase().includes(query)
    })
    function selectEntry(id, checked) {
        const values = selectedIds.slice()
        const index = values.indexOf(id)
        if (checked && index < 0)
            values.push(id)
        else if (!checked && index >= 0)
            values.splice(index, 1)
        selectedIds = values
    }
    function inspectSource(url, kind) {
        if (!store || busy)
            return
        pendingInspection = kind
        pendingSource = url
        if (kind === "directory")
            store.inspectDirectory(url)
        else
            store.inspectPack(url)
    }
    function chooseExport() {
        if (!store || busy || entries.length === 0)
            return
        exportIds = selectedIds.slice()
        exportFile.selectedFile = store.suggestedExportUrl()
        exportFile.open()
    }
    background: AppBackground { }
    ScreenHeader {
        id: header
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.topMargin: Theme.size(22)
        anchors.leftMargin: Theme.pageMargin
        anchors.rightMargin: Theme.pageMargin
        title: qsTr("Custom card art")
        subtitle: qsTr("Manage local cosmetic overrides separately from downloaded card images")
        onBackRequested: if (!root.busy) root.appWindow.popScreen()
    }
    ColumnLayout {
        id: activity
        anchors.top: header.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: Theme.pageMargin
        anchors.rightMargin: Theme.pageMargin
        spacing: Theme.size(6)
        visible: root.busy
        height: visible ? implicitHeight : 0
        Text {
            textFormat: Text.PlainText
            Layout.fillWidth: true
            text: root.store ? I18n.status(root.store.status) : ""
            color: Theme.textSecondary
            font.pixelSize: Theme.fontSize(12)
            wrapMode: Text.WordWrap
        }
        ProgressBar {
            objectName: "customArtManagerProgress"
            Layout.fillWidth: true
            indeterminate: true
        }
    }
    Flickable {
        id: body
        objectName: "customCardArtManagerBody"
        anchors.top: activity.bottom
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: Theme.pageMargin
        anchors.topMargin: Theme.size(14)
        clip: true
        contentWidth: width
        contentHeight: content.implicitHeight
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
        ColumnLayout {
            id: content
            width: body.width
            spacing: Theme.size(16)
            Surface {
                Layout.fillWidth: true
                implicitHeight: introduction.implicitHeight + Theme.size(40)
                elevated: true
                ColumnLayout {
                    id: introduction
                    anchors.fill: parent
                    anchors.margins: Theme.size(20)
                    spacing: Theme.size(12)
                    InfoBanner {
                        objectName: "customArtManagerError"
                        Layout.fillWidth: true
                        message: root.store ? I18n.status(root.store.lastError) : ""
                    }
                    InfoBanner {
                        objectName: "customArtManagerResult"
                        Layout.fillWidth: true
                        tone: "success"
                        message: root.operationResultMessage
                                 || (root.store ? I18n.status(root.store.lastResult) : "")
                    }
                    Text {
                        textFormat: Text.PlainText
                        Layout.fillWidth: true
                        text: qsTr("Use a card's actions menu in the deck editor, or Custom art in token and emblem details, to set one local image. Overrides apply only on this device and never change card rules or official cache entries.")
                        color: Theme.textSecondary
                        font.pixelSize: Theme.fontSize(13)
                        wrapMode: Text.WordWrap
                    }
                    Text {
                        textFormat: Text.PlainText
                        Layout.fillWidth: true
                        text: qsTr("For bulk import, provide custom-art-map.json, or arrange images as SET/<percent-encoded collector>.front|back|face-N.jpg (also .jpeg, .png, or .webp). File mappings are checked against the local card database before you confirm. Names are not guessed.")
                        color: Theme.textMuted
                        font.pixelSize: Theme.fontSize(12)
                        wrapMode: Text.WordWrap
                    }
                    Text {
                        textFormat: Text.PlainText
                        Layout.fillWidth: true
                        text: qsTr("Custom images use a separate .hexproof-custom-artpack sharing format. Recipients must review and explicitly apply its overrides. Share only images you have permission to redistribute.")
                        color: Theme.textMuted
                        font.pixelSize: Theme.fontSize(12)
                        wrapMode: Text.WordWrap
                    }
                    Flow {
                        Layout.fillWidth: true
                        spacing: Theme.size(10)
                        AppButton {
                            objectName: "importCustomArtFolderButton"
                            compact: true
                            text: qsTr("Import folder…")
                            enabled: !!root.store && !root.busy
                            onClicked: importFolder.open()
                        }
                        AppButton {
                            objectName: "importCustomArtPackButton"
                            compact: true
                            text: qsTr("Import custom pack…")
                            enabled: !!root.store && !root.busy
                            onClicked: importFile.open()
                        }
                        AppButton {
                            objectName: "exportCustomArtPackButton"
                            compact: true
                            text: root.selectedIds.length > 0 ? qsTr("Export selected…") : qsTr("Export all…")
                            enabled: !!root.store && !root.busy && root.entries.length > 0
                            onClicked: root.chooseExport()
                        }
                        AppButton {
                            objectName: "clearCustomArtButton"
                            compact: true
                            variant: "danger"
                            text: qsTr("Restore all…")
                            enabled: !!root.store && !root.busy && root.entries.length > 0
                            onClicked: clearConfirmation.open()
                        }
                    }
                }
            }
            Surface {
                Layout.fillWidth: true
                implicitHeight: listContent.implicitHeight + Theme.size(40)
                elevated: true
                ColumnLayout {
                    id: listContent
                    anchors.fill: parent
                    anchors.margins: Theme.size(20)
                    spacing: Theme.size(12)
                    AppTextField {
                        objectName: "customArtSearchField"
                        Layout.fillWidth: true
                        placeholderText: qsTr("Search card name, set, collector number, or image slot…")
                        onTextEdited: root.filterText = text
                    }
                    Flow {
                        Layout.fillWidth: true
                        spacing: Theme.size(10)
                        Text {
                            textFormat: Text.PlainText
                            text: qsTr("%1 override(s) · %2 selected").arg(root.filteredEntries.length).arg(root.selectedIds.length)
                            color: Theme.textSecondary
                            font.pixelSize: Theme.fontSize(13)
                        }
                        AppButton {
                            compact: true
                            visible: root.selectedIds.length > 0
                            text: qsTr("Clear selection")
                            onClicked: root.selectedIds = []
                        }
                    }
                    ListView {
                        id: entryList
                        objectName: "customArtEntries"
                        Layout.fillWidth: true
                        Layout.preferredHeight: Math.min(Theme.size(550), Math.max(Theme.size(120), contentHeight))
                        clip: true
                        model: root.filteredEntries
                        spacing: Theme.size(8)
                        boundsBehavior: Flickable.StopAtBounds
                        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                        ScrollChainHandler { innerFlickable: entryList; outerFlickable: body }
                        delegate: Surface {
                            required property var modelData
                            width: entryList.width
                            implicitHeight: entryContent.implicitHeight + Theme.size(16)
                            color: Theme.surfaceMuted
                            ColumnLayout {
                                id: entryContent
                                anchors.fill: parent
                                anchors.margins: Theme.size(8)
                                spacing: Theme.size(6)
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: Theme.size(8)
                                    CheckBox {
                                        objectName: "selectCustomArtEntry"
                                        checked: root.selectedIds.indexOf(modelData.id) >= 0
                                        enabled: !root.busy
                                        Accessible.name: qsTr("Select %1").arg(modelData.name)
                                        onToggled: root.selectEntry(modelData.id, checked)
                                    }
                                    Image {
                                        Layout.preferredWidth: Theme.size(52)
                                        Layout.preferredHeight: Theme.size(72)
                                        source: modelData.imageSource || ""
                                        asynchronous: true
                                        fillMode: Image.PreserveAspectFit
                                    }
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        Layout.minimumWidth: 0
                                        Text {
                                            textFormat: Text.PlainText
                                            Layout.fillWidth: true
                                            text: modelData.name
                                            color: Theme.text
                                            font.pixelSize: Theme.fontSize(13)
                                            elide: Text.ElideRight
                                        }
                                        Text {
                                            textFormat: Text.PlainText
                                            Layout.fillWidth: true
                                            text: (modelData.scope === "card" ? qsTr("All printings")
                                                   : modelData.setCode + " #" + modelData.collectorNumber)
                                                  + " · " + (modelData.faceName || qsTr("Front / whole image"))
                                            color: Theme.textSecondary
                                            font.pixelSize: Theme.fontSize(11)
                                            wrapMode: Text.WrapAnywhere
                                        }
                                    }
                                }
                                Flow {
                                    Layout.fillWidth: true
                                    spacing: Theme.size(8)
                                    AppButton {
                                        objectName: "editCustomArtEntryButton"
                                        compact: true
                                        text: qsTr("Change…")
                                        enabled: !root.busy
                                        onClicked: cardDialog.showFor(modelData)
                                    }
                                    AppButton {
                                        objectName: "removeCustomArtEntryButton"
                                        compact: true
                                        text: qsTr("Restore")
                                        enabled: !root.busy
                                        onClicked: { root.pendingEntry = modelData; removeConfirmation.open() }
                                    }
                                }
                            }
                        }
                        Text {
                            textFormat: Text.PlainText
                            anchors.centerIn: parent
                            width: parent.width
                            visible: root.filteredEntries.length === 0
                            text: qsTr("No custom overrides match this view.")
                            color: Theme.textMuted
                            font.pixelSize: Theme.fontSize(13)
                            horizontalAlignment: Text.AlignHCenter
                            wrapMode: Text.WordWrap
                        }
                    }
                }
            }
        }
    }
    FolderDialog {
        id: importFolder
        objectName: "customArtImportFolderDialog"
        title: qsTr("Choose custom-art folder")
        onAccepted: root.inspectSource(selectedFolder, "directory")
    }
    FileDialog {
        id: importFile
        objectName: "customArtImportPackDialog"
        title: qsTr("Import custom card-art pack")
        fileMode: FileDialog.OpenFile
        nameFilters: [qsTr("Hexproof custom card-art packs") + " (*.hexproof-custom-artpack)"]
        onAccepted: root.inspectSource(selectedFile, "pack")
    }
    FileDialog {
        id: exportFile
        objectName: "customArtExportPackDialog"
        title: qsTr("Export custom card-art pack")
        fileMode: FileDialog.SaveFile
        defaultSuffix: "hexproof-custom-artpack"
        nameFilters: [qsTr("Hexproof custom card-art packs") + " (*.hexproof-custom-artpack)"]
        onAccepted: if (!root.busy) root.store.exportPack(selectedFile, root.exportIds)
    }
    CustomArtImportDialog {
        id: previewDialog
        objectName: "customArtImportPreviewDialog"
        store: root.store
    }
    CustomCardArtDialog {
        id: cardDialog
        objectName: "managerCustomCardArtDialog"
        store: root.store
        catalogModel: root.catalogModel
    }
    ConfirmDialog {
        id: removeConfirmation
        titleText: qsTr("Remove this custom override?")
        message: qsTr("Remove the selected image-slot override for %1? Downloaded art and other overrides are kept.")
                 .arg(root.pendingEntry.name || "")
        confirmText: qsTr("Restore")
        onConfirmed: if (!root.busy) root.store.removeEntry(root.pendingEntry.id)
    }
    ConfirmDialog {
        id: clearConfirmation
        titleText: qsTr("Restore all custom card art?")
        message: qsTr("Remove every custom override on this device? Downloaded images, card data, and deck lists are kept.")
        confirmText: qsTr("Restore all")
        dangerous: true
        onConfirmed: if (!root.busy) root.store.clear()
    }
    Connections {
        target: root.store
        ignoreUnknownSignals: true
        function onInspectionFinished() {
            const value = root.store.preview || ({})
            root.inspectionSource = value.fileUrl || ""
            if (!root.pendingInspection || value.kind !== root.pendingInspection
                    || root.inspectionSource.toString() !== root.pendingSource.toString())
                return
            root.pendingInspection = ""
            previewDialog.showPreview(value)
        }
        function onChanged() {
            const ids = new Set(Array.from(root.entries).map(entry => entry.id))
            root.selectedIds = root.selectedIds.filter(id => ids.has(id))
        }
        function onOperationFinished(result) {
            if (result.ok && result.operation === "exportPack")
                root.operationResultMessage = qsTr("Exported %1 override(s) with %2 image(s).\n%3")
                    .arg(result.entryCount || 0).arg(result.imageCount || 0).arg(result.fileUrl || "")
            else if (result.ok && (result.operation === "removeEntry" || result.operation === "clear"))
                root.operationResultMessage = qsTr("Removed %1 override(s).").arg(result.removedCount || 0)
            body.contentY = 0
        }
        function onBusyChanged() {
            if (root.store.busy)
                root.operationResultMessage = ""
        }
    }
}
