// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

Popup {
    id: root
    property var store: null
    property var preview: ({})
    property bool replaceExisting: false
    property bool importing: false
    property string errorMessage: ""
    property string resultMessage: ""
    readonly property bool busy: !!store && store.busy
    readonly property var rows: preview.rows || []
    readonly property bool canImport: !!preview.ok && (preview.validCount || 0) > 0
                                     && !busy && !importing && !resultMessage
    function showPreview(value) {
        if (importing)
            return
        preview = JSON.parse(JSON.stringify(value || {}))
        replaceExisting = false
        errorMessage = preview.ok ? "" : I18n.status(preview.error || "")
        resultMessage = ""
        body.contentY = 0
        open()
    }
    function importConfirmed() {
        if (!canImport || !store)
            return
        importing = true
        errorMessage = ""
        store.importPreview(replaceExisting)
    }

    parent: Overlay.overlay
    width: Math.min(Theme.size(900), parent.width - Theme.size(40))
    height: Math.min(Theme.size(780), parent.height - Theme.size(40))
    x: Math.round((parent.width - width) / 2)
    y: Math.round((parent.height - height) / 2)
    padding: Theme.size(22)
    modal: true
    focus: true
    closePolicy: importing ? Popup.NoAutoClose : Popup.CloseOnEscape | Popup.CloseOnPressOutside
    Overlay.modal: Rectangle { color: "#A6050B09" }
    background: Rectangle {
        color: Theme.surfaceElevated
        radius: Theme.radiusLarge
        border.color: Theme.borderStrong
    }
    contentItem: ColumnLayout {
        spacing: Theme.size(14)
        Text {
            textFormat: Text.PlainText
            Layout.fillWidth: true
            text: qsTr("Review custom card art")
            color: Theme.text
            font.pixelSize: Theme.fontSize(20)
            font.weight: Font.DemiBold
        }
        Flickable {
            id: body
            objectName: "customArtImportBody"
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumHeight: 0
            clip: true
            contentWidth: width
            contentHeight: content.implicitHeight
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
            ColumnLayout {
                id: content
                width: body.width
                spacing: Theme.size(12)
                InfoBanner {
                    Layout.fillWidth: true
                    message: root.errorMessage
                }
                InfoBanner {
                    Layout.fillWidth: true
                    tone: "success"
                    message: root.resultMessage
                }
                InfoBanner {
                    Layout.fillWidth: true
                    tone: "warning"
                    message: qsTr("These are custom images, not official cache entries. Applying them changes how these cards look on this device. Card rules and other players' images are unchanged.")
                }
                Text {
                    textFormat: Text.PlainText
                    objectName: "customArtImportCounts"
                    Layout.fillWidth: true
                    text: qsTr("%1 valid · %2 conflicts · %3 invalid or unmapped")
                          .arg(root.preview.validCount || 0)
                          .arg(root.preview.conflictCount || 0)
                          .arg(root.preview.errorCount || 0)
                    color: Theme.text
                    font.pixelSize: Theme.fontSize(14)
                    wrapMode: Text.WordWrap
                }
                Text {
                    textFormat: Text.PlainText
                    Layout.fillWidth: true
                    text: qsTr("Review every mapping and image slot below. Invalid or unmapped files are skipped; existing overrides are preserved unless you explicitly choose replacement.")
                    color: Theme.textSecondary
                    font.pixelSize: Theme.fontSize(12)
                    wrapMode: Text.WordWrap
                }
                AppToggle {
                    objectName: "replaceCustomArtConflictsToggle"
                    Layout.fillWidth: true
                    visible: (root.preview.conflictCount || 0) > 0
                    text: qsTr("Replace existing custom overrides")
                    checked: root.replaceExisting
                    enabled: !root.busy && !root.resultMessage
                    onToggled: root.replaceExisting = checked
                }
                ListView {
                    id: mappings
                    objectName: "customArtImportMappings"
                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.min(Theme.size(360), Math.max(Theme.size(100), contentHeight))
                    model: root.rows
                    spacing: Theme.size(8)
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                    ScrollChainHandler { innerFlickable: mappings; outerFlickable: body }
                    delegate: Surface {
                        required property var modelData
                        width: mappings.width
                        implicitHeight: mappingContent.implicitHeight + Theme.size(20)
                        color: Theme.surfaceMuted
                        RowLayout {
                            id: mappingContent
                            anchors.fill: parent
                            anchors.margins: Theme.size(10)
                            spacing: Theme.size(10)
                            Image {
                                Layout.preferredWidth: Theme.size(52)
                                Layout.preferredHeight: Theme.size(72)
                                source: modelData.valid ? modelData.imageSource || "" : ""
                                asynchronous: true
                                fillMode: Image.PreserveAspectFit
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.minimumWidth: 0
                                Text {
                                    textFormat: Text.PlainText
                                    objectName: "customArtImportRowName"
                                    Layout.fillWidth: true
                                    text: modelData.name || modelData.sourceFile || modelData.fileName || ""
                                    color: Theme.text
                                    font.pixelSize: Theme.fontSize(13)
                                    elide: Text.ElideRight
                                }
                                Text {
                                    textFormat: Text.PlainText
                                    Layout.fillWidth: true
                                    text: (modelData.scope === "card" ? qsTr("All printings")
                                           : (modelData.setCode || "") + " #" + (modelData.collectorNumber || ""))
                                          + " · " + (modelData.faceName || qsTr("Front / whole image"))
                                    color: Theme.textSecondary
                                    font.pixelSize: Theme.fontSize(11)
                                    wrapMode: Text.WrapAnywhere
                                }
                                Text {
                                    textFormat: Text.PlainText
                                    Layout.fillWidth: true
                                    text: modelData.error ? I18n.status(modelData.error)
                                          : modelData.conflict ? qsTr("Existing override")
                                          : (modelData.sourceFile || modelData.fileName || "")
                                    color: modelData.error ? Theme.error
                                           : modelData.conflict ? Theme.warning : Theme.textMuted
                                    font.pixelSize: Theme.fontSize(11)
                                    wrapMode: Text.WrapAnywhere
                                }
                            }
                        }
                    }
                }
            }
        }
        ProgressBar {
            Layout.fillWidth: true
            visible: root.importing
            indeterminate: true
        }
        Flow {
            Layout.fillWidth: true
            spacing: Theme.size(10)
            AppButton {
                objectName: "closeCustomArtImportButton"
                compact: true
                text: qsTr("Close")
                enabled: !root.importing
                onClicked: root.close()
            }
            AppButton {
                objectName: "confirmCustomArtImportButton"
                compact: true
                variant: "primary"
                text: qsTr("Apply custom images")
                enabled: root.canImport
                onClicked: root.importConfirmed()
            }
        }
    }
    Connections {
        target: root.store
        ignoreUnknownSignals: true
        function onOperationFinished(result) {
            if (!root.importing || result.operation !== "importPreview")
                return
            root.importing = false
            root.errorMessage = result.ok ? "" : I18n.status(result.error || root.store.lastError)
            root.resultMessage = result.ok
                ? qsTr("Applied %1 override(s); kept %2 existing override(s).")
                  .arg(result.importedCount || 0).arg(result.preservedCount || 0)
                : ""
            body.contentY = 0
        }
    }
}
