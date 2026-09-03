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
    readonly property var cacheInventory: cardArtManager.inventory || ({})
    property var filteredGroups: []
    property bool pendingSelectionOnly: false
    property string pendingSetCode: ""
    property string pendingLanguage: ""
    property string pendingDeleteAction: ""
    property url pendingImportUrl
    property var pendingImportSummary: ({})
    property bool auditRequestedByUser: false

    background: AppBackground { }

    ScreenHeader {
        id: header
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.topMargin: Theme.size(22)
        anchors.leftMargin: Theme.pageMargin
        anchors.rightMargin: Theme.pageMargin
        title: qsTr("Card art storage")
        subtitle: qsTr("Inspect, clean up, import, and share downloaded card images")
        onBackRequested: root.appWindow.popScreen()
    }

    ScrollView {
        anchors.top: header.bottom
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.topMargin: Theme.size(14)
        anchors.bottomMargin: Theme.size(28)
        clip: true
        contentWidth: availableWidth
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

        ColumnLayout {
            width: Math.min(Theme.size(920), parent.width - Theme.size(72))
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Theme.size(16)

            Surface {
                Layout.fillWidth: true
                implicitHeight: overviewContent.implicitHeight + Theme.size(48)
                elevated: true

                ColumnLayout {
                    id: overviewContent
                    anchors.fill: parent
                    anchors.margins: Theme.size(24)
                    spacing: Theme.size(14)

                    RowLayout {
                        Layout.fillWidth: true
                        Text {
                            textFormat: Text.PlainText
                            text: qsTr("Local card art")
                            color: Theme.text
                            font.pixelSize: Theme.fontSize(20)
                            font.weight: Font.DemiBold
                        }
                        Item { Layout.fillWidth: true }
                        ActivityRing {
                            visible: cardArtManager.busy
                        }
                        AppButton {
                            compact: true
                            variant: "ghost"
                            text: qsTr("Refresh")
                            enabled: !cardArtManager.busy && !cardCatalog.busy
                            onClicked: cardArtManager.refresh()
                        }
                    }

                    GridLayout {
                        Layout.fillWidth: true
                        columns: width >= Theme.size(780) ? 5
                                                       : (width >= Theme.size(500) ? 3 : 2)
                        columnSpacing: Theme.size(10)
                        rowSpacing: Theme.size(10)

                        Repeater {
                            model: [
                                {"label": qsTr("Disk usage"),
                                 "value": root.formatBytes(root.cacheInventory.totalBytes)},
                                {"label": qsTr("Image files"),
                                 "value": String(root.cacheInventory.imageCount || 0)},
                                {"label": qsTr("Indexed entries"),
                                 "value": String(root.cacheInventory.indexedEntryCount || 0)},
                                {"label": qsTr("Missing files"),
                                 "value": String(root.cacheInventory.missingEntryCount || 0)},
                                {"label": qsTr("Unused files"),
                                 "value": String(root.cacheInventory.orphanCount || 0)}
                            ]

                            Rectangle {
                                required property var modelData
                                Layout.fillWidth: true
                                implicitHeight: Theme.size(76)
                                radius: Theme.radiusMedium
                                color: Theme.surfaceMuted
                                border.width: 1
                                border.color: Theme.border

                                Column {
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.margins: Theme.size(14)
                                    spacing: Theme.size(3)
                                    Text {
                                        textFormat: Text.PlainText
                                        text: modelData.value
                                        color: Theme.primary
                                        font.pixelSize: Theme.fontSize(19)
                                        font.weight: Font.DemiBold
                                    }
                                    Text {
                                        textFormat: Text.PlainText
                                        text: modelData.label
                                        color: Theme.textMuted
                                        font.pixelSize: Theme.fontSize(11)
                                    }
                                }
                            }
                        }
                    }

                    Text {
                        textFormat: Text.PlainText
                        Layout.fillWidth: true
                        text: qsTr("Cache folder: %1").arg(cardArtManager.storagePath)
                        color: Theme.textMuted
                        font.pixelSize: Theme.fontSize(10)
                        elide: Text.ElideMiddle
                    }

                    InfoBanner {
                        Layout.fillWidth: true
                        tone: "success"
                        message: I18n.status(cardArtManager.lastResult)
                    }
                    InfoBanner {
                        Layout.fillWidth: true
                        message: I18n.status(cardArtManager.lastError)
                    }
                    Text {
                        textFormat: Text.PlainText
                        Layout.fillWidth: true
                        visible: cardArtManager.busy && cardArtManager.status.length > 0
                        text: I18n.status(cardArtManager.status)
                        color: Theme.primary
                        font.pixelSize: Theme.fontSize(12)
                    }
                }
            }

            Surface {
                Layout.fillWidth: true
                implicitHeight: repairContent.implicitHeight + Theme.size(48)
                elevated: true

                ColumnLayout {
                    id: repairContent
                    anchors.fill: parent
                    anchors.margins: Theme.size(24)
                    spacing: Theme.size(12)

                    RowLayout {
                        Layout.fillWidth: true
                        Text {
                            textFormat: Text.PlainText
                            text: qsTr("Check and repair deck art")
                            color: Theme.text
                            font.pixelSize: Theme.fontSize(20)
                            font.weight: Font.DemiBold
                        }
                        Item { Layout.fillWidth: true }
                        StatusPill {
                            visible: cardArtManager.repairNeeded
                            text: qsTr("Repair recommended")
                            statusColor: Theme.warning
                        }
                    }

                    Text {
                        textFormat: Text.PlainText
                        Layout.fillWidth: true
                        text: qsTr("Check previously cached deck printings for missing double-faced card backs and outdated special-card mappings. The check is local and does not download anything.")
                        color: Theme.textSecondary
                        font.pixelSize: Theme.fontSize(12)
                        lineHeight: 1.35
                        wrapMode: Text.WordWrap
                    }

                    InfoBanner {
                        Layout.fillWidth: true
                        tone: "warning"
                        visible: cardArtManager.repairNeeded
                        message: qsTr("An older card art cache needs attention. Hexproof will reuse valid local images before offering to download missing faces.")
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.size(10)
                        AppButton {
                            objectName: "auditDeckArtButton"
                            text: cardArtManager.repairNeeded
                                  ? qsTr("Review repair…")
                                  : qsTr("Check and repair…")
                            enabled: !cardArtManager.busy && !cardCatalog.busy
                            onClicked: {
                                root.auditRequestedByUser = true
                                cardArtManager.auditCardArt(true)
                            }
                        }
                        Text {
                            textFormat: Text.PlainText
                            Layout.fillWidth: true
                            visible: (cardArtManager.auditResult.ok || false)
                            text: qsTr("Checked %1 cached printing(s) and %2 expected face(s).")
                                  .arg(cardArtManager.auditResult.printingCount || 0)
                                  .arg(cardArtManager.auditResult.faceCount || 0)
                            color: Theme.textMuted
                            font.pixelSize: Theme.fontSize(11)
                            horizontalAlignment: Text.AlignRight
                            wrapMode: Text.WordWrap
                        }
                    }
                }
            }

            Surface {
                Layout.fillWidth: true
                implicitHeight: sharingContent.implicitHeight + Theme.size(48)
                elevated: true

                ColumnLayout {
                    id: sharingContent
                    anchors.fill: parent
                    anchors.margins: Theme.size(24)
                    spacing: Theme.size(12)

                    Text {
                        textFormat: Text.PlainText
                        text: qsTr("Import and share")
                        color: Theme.text
                        font.pixelSize: Theme.fontSize(20)
                        font.weight: Font.DemiBold
                    }
                    Text {
                        textFormat: Text.PlainText
                        Layout.fillWidth: true
                        text: qsTr("Hexproof card art packs contain a versioned manifest and SHA-256 verified images. Existing valid images are kept when importing.")
                        color: Theme.textSecondary
                        font.pixelSize: Theme.fontSize(12)
                        wrapMode: Text.WordWrap
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.size(10)
                        AppButton {
                            text: qsTr("Import pack…")
                            enabled: !cardArtManager.busy && !cardCatalog.busy
                            onClicked: importFileDialog.open()
                        }
                        AppButton {
                            text: qsTr("Export all…")
                            enabled: !cardArtManager.busy && !cardCatalog.busy
                                     && (root.cacheInventory.cachedEntryCount || 0) > 0
                            onClicked: root.chooseExport(false, "", "")
                        }
                        Item { Layout.fillWidth: true }
                    }
                    InfoBanner {
                        Layout.fillWidth: true
                        tone: "warning"
                        message: qsTr("Card images come from third-party sources. Keep the source metadata in the pack and share only where you are permitted to do so.")
                    }
                }
            }

            Surface {
                Layout.fillWidth: true
                implicitHeight: collectionContent.implicitHeight + Theme.size(48)
                elevated: true

                ColumnLayout {
                    id: collectionContent
                    anchors.fill: parent
                    anchors.margins: Theme.size(24)
                    spacing: Theme.size(12)

                    RowLayout {
                        Layout.fillWidth: true
                        ColumnLayout {
                            spacing: Theme.size(3)
                            Text {
                                textFormat: Text.PlainText
                                text: qsTr("Cached sets and languages")
                                color: Theme.text
                                font.pixelSize: Theme.fontSize(20)
                                font.weight: Font.DemiBold
                            }
                            Text {
                                textFormat: Text.PlainText
                                text: qsTr("Each row can be exported or removed independently.")
                                color: Theme.textSecondary
                                font.pixelSize: Theme.fontSize(11)
                            }
                        }
                        Item { Layout.fillWidth: true }
                        Text {
                            textFormat: Text.PlainText
                            text: qsTr("%1 group(s)").arg(root.filteredGroups.length)
                            color: Theme.textMuted
                            font.pixelSize: Theme.fontSize(11)
                        }
                    }

                    AppTextField {
                        id: groupSearch
                        Layout.fillWidth: true
                        placeholderText: qsTr("Filter by set code, language, or source")
                        onTextChanged: root.rebuildGroups()
                    }

                    ListView {
                        id: groupList
                        Layout.fillWidth: true
                        Layout.preferredHeight: Theme.size(380)
                        clip: true
                        spacing: Theme.size(8)
                        model: root.filteredGroups
                        boundsBehavior: Flickable.StopAtBounds
                        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                        delegate: Rectangle {
                            id: groupRow
                            required property var modelData
                            width: ListView.view.width
                            height: Theme.size(74)
                            radius: Theme.radiusMedium
                            color: Theme.surfaceMuted
                            border.width: 1
                            border.color: Theme.border

                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: Theme.size(12)
                                spacing: Theme.size(10)

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: Theme.size(3)
                                    Text {
                                        textFormat: Text.PlainText
                                        Layout.fillWidth: true
                                        text: root.groupTitle(groupRow.modelData)
                                        color: Theme.text
                                        font.pixelSize: Theme.fontSize(14)
                                        font.weight: Font.DemiBold
                                        elide: Text.ElideRight
                                    }
                                    Text {
                                        textFormat: Text.PlainText
                                        Layout.fillWidth: true
                                        text: root.groupDetail(groupRow.modelData)
                                        color: Theme.textMuted
                                        font.pixelSize: Theme.fontSize(10)
                                        elide: Text.ElideRight
                                    }
                                }
                                AppButton {
                                    compact: true
                                    variant: "ghost"
                                    text: qsTr("Export…")
                                    enabled: !cardArtManager.busy && !cardCatalog.busy
                                             && (groupRow.modelData.imageCount || 0) > 0
                                    onClicked: root.chooseExport(
                                                   true,
                                                   groupRow.modelData.setCode || "",
                                                   groupRow.modelData.language || "")
                                }
                                AppButton {
                                    compact: true
                                    variant: "danger"
                                    text: qsTr("Delete")
                                    enabled: !cardArtManager.busy && !cardCatalog.busy
                                    onClicked: root.confirmGroupDelete(groupRow.modelData)
                                }
                            }
                        }

                        Text {
                            textFormat: Text.PlainText
                            anchors.centerIn: parent
                            visible: groupList.count === 0
                            text: groupSearch.text.length > 0
                                  ? qsTr("No cached group matches this filter")
                                  : qsTr("No indexed card images are cached")
                            color: Theme.textMuted
                            font.pixelSize: Theme.fontSize(12)
                        }
                    }
                }
            }

            Surface {
                Layout.fillWidth: true
                implicitHeight: cleanupContent.implicitHeight + Theme.size(48)
                elevated: true

                ColumnLayout {
                    id: cleanupContent
                    anchors.fill: parent
                    anchors.margins: Theme.size(24)
                    spacing: Theme.size(12)

                    Text {
                        textFormat: Text.PlainText
                        text: qsTr("Clean up")
                        color: Theme.text
                        font.pixelSize: Theme.fontSize(20)
                        font.weight: Font.DemiBold
                    }
                    Text {
                        textFormat: Text.PlainText
                        Layout.fillWidth: true
                        text: qsTr("Unused files are images in the cache folder that are no longer referenced by the card-art index.")
                        color: Theme.textSecondary
                        font.pixelSize: Theme.fontSize(12)
                        wrapMode: Text.WordWrap
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.size(10)
                        AppButton {
                            text: qsTr("Remove %1 unused file(s) · %2")
                                  .arg(root.cacheInventory.orphanCount || 0)
                                  .arg(root.formatBytes(root.cacheInventory.orphanBytes))
                            enabled: !cardArtManager.busy && !cardCatalog.busy
                                     && (root.cacheInventory.orphanCount || 0) > 0
                            onClicked: {
                                root.pendingDeleteAction = "orphans"
                                deleteDialog.open()
                            }
                        }
                        Item { Layout.fillWidth: true }
                        AppButton {
                            variant: "danger"
                            text: qsTr("Delete all card art")
                            enabled: !cardArtManager.busy && !cardCatalog.busy
                                     && ((root.cacheInventory.imageCount || 0) > 0
                                         || (root.cacheInventory.indexedEntryCount || 0) > 0)
                            onClicked: {
                                root.pendingDeleteAction = "all"
                                deleteDialog.open()
                            }
                        }
                    }
                }
            }
        }
    }

    FileDialog {
        id: importFileDialog
        title: qsTr("Import card art pack")
        fileMode: FileDialog.OpenFile
        nameFilters: [
            qsTr("Hexproof card art packs") + " (*.hexproof-artpack)",
            qsTr("All files") + " (*)"
        ]
        onAccepted: {
            root.pendingImportUrl = selectedFile
            cardArtManager.inspectPack(selectedFile)
        }
    }

    FileDialog {
        id: exportFileDialog
        title: qsTr("Export card art pack")
        fileMode: FileDialog.SaveFile
        nameFilters: [qsTr("Hexproof card art packs") + " (*.hexproof-artpack)"]
        onAccepted: cardArtManager.exportPack(
                        selectedFile, root.pendingSelectionOnly,
                        root.pendingSetCode, root.pendingLanguage)
    }

    ConfirmDialog {
        id: repairDialog
        titleText: qsTr("Repair cached deck art?")
        message: qsTr("Hexproof can repair %1 local cache mapping(s) and download %2 missing card face(s). Existing valid images will be reused. Continue?")
                 .arg(cardArtManager.auditResult.repairableEntryCount || 0)
                 .arg(cardArtManager.auditResult.missingFaceCount || 0)
        confirmText: qsTr("Repair")
        onConfirmed: cardArtManager.repairAuditedCardArt()
    }

    ConfirmDialog {
        id: importDialog
        titleText: qsTr("Import this card art pack?")
        message: qsTr("Version %1 · %2 image(s) · %3 new entries · %4 already cached · %5. Existing valid images will not be replaced.")
                 .arg(root.pendingImportSummary.formatVersion || "?")
                 .arg(root.pendingImportSummary.imageCount || 0)
                 .arg(root.pendingImportSummary.newEntryCount || 0)
                 .arg(root.pendingImportSummary.existingEntryCount || 0)
                 .arg(root.formatBytes(root.pendingImportSummary.bytes))
        confirmText: qsTr("Import")
        onConfirmed: cardArtManager.importPack(root.pendingImportUrl)
    }

    ConfirmDialog {
        id: deleteDialog
        titleText: root.pendingDeleteAction === "all"
                   ? qsTr("Delete all downloaded card art?")
                   : root.pendingDeleteAction === "group"
                     ? qsTr("Delete this cached group?")
                     : qsTr("Remove unused files?")
        message: root.deleteMessage()
        confirmText: qsTr("Delete")
        dangerous: true
        onConfirmed: {
            if (root.pendingDeleteAction === "orphans") {
                cardArtManager.removeOrphans()
            } else {
                cardArtManager.removeSelection(
                            root.pendingDeleteAction === "group",
                            root.pendingSetCode, root.pendingLanguage)
            }
        }
    }

    Connections {
        target: cardArtManager
        function onInventoryChanged() { root.rebuildGroups() }
        function onPackInspectionFinished() {
            const summary = cardArtManager.packPreview || ({})
            if (!summary.ok)
                return
            root.pendingImportSummary = summary
            importDialog.open()
        }
        function onAuditFinished() {
            if (!root.auditRequestedByUser)
                return
            root.auditRequestedByUser = false
            const summary = cardArtManager.auditResult || ({})
            if (summary.ok && summary.repairNeeded)
                repairDialog.open()
        }
    }

    Component.onCompleted: {
        root.rebuildGroups()
        cardArtManager.refresh()
    }

    function rebuildGroups() {
        const groups = root.cacheInventory.groups || []
        const needle = groupSearch.text.trim().toLowerCase()
        if (!needle) {
            root.filteredGroups = groups
            return
        }
        root.filteredGroups = groups.filter(function(group) {
            const source = (group.sources || []).join(" ")
            return String(group.setCode || "").toLowerCase().includes(needle)
                    || String(group.language || "").toLowerCase().includes(needle)
                    || source.toLowerCase().includes(needle)
        })
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

    function languageLabel(language) {
        if (language === "zh")
            return qsTr("Chinese art")
        if (language === "en")
            return qsTr("English art")
        return qsTr("Unspecified art language")
    }

    function groupTitle(group) {
        const setName = group.setCode ? group.setCode : qsTr("Unassigned printing")
        return setName + " · " + root.languageLabel(group.language)
    }

    function sourceLabel(sources) {
        const labels = (sources || []).map(function(source) {
            if (source === "scryfall")
                return qsTr("Scryfall")
            if (source === "mtgch")
                return qsTr("MTGCH")
            return qsTr("Imported/other")
        })
        return labels.join(" + ")
    }

    function groupDetail(group) {
        let detail = qsTr("%1 image(s) · %2 entries · %3 · %4")
                .arg(group.imageCount || 0)
                .arg(group.entryCount || 0)
                .arg(root.formatBytes(group.bytes))
                .arg(root.sourceLabel(group.sources))
        if ((group.missingEntryCount || 0) > 0)
            detail += qsTr(" · %1 missing").arg(group.missingEntryCount)
        return detail
    }

    function chooseExport(selectionOnly, setCode, language) {
        root.pendingSelectionOnly = selectionOnly
        root.pendingSetCode = setCode
        root.pendingLanguage = language
        exportFileDialog.selectedFile = cardArtManager.suggestedExportUrl(
                    selectionOnly, setCode, language)
        exportFileDialog.open()
    }

    function confirmGroupDelete(group) {
        root.pendingDeleteAction = "group"
        root.pendingSetCode = group.setCode || ""
        root.pendingLanguage = group.language || ""
        deleteDialog.open()
    }

    function deleteMessage() {
        if (root.pendingDeleteAction === "all") {
            return qsTr("This removes all indexed and unused image files. Card metadata and deck lists are preserved; images can be downloaded again later.")
        }
        if (root.pendingDeleteAction === "group") {
            return qsTr("This removes the selected set/language group. Shared files still referenced by another group are preserved.")
        }
        return qsTr("This removes %1 unreferenced file(s) and frees up to %2. Indexed card images are preserved.")
                .arg(root.cacheInventory.orphanCount || 0)
                .arg(root.formatBytes(root.cacheInventory.orphanBytes))
    }
}
