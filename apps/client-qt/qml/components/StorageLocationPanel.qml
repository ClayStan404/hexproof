// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Dialogs
import QtQuick.Layouts

Surface {
    id: root
    property var service: null
    property bool operationsBusy: false
    property var pendingPreview: ({})
    property url selectedBase: ""
    property bool defaultRequested: false
    property string previewError: ""
    readonly property bool busy: !!service && service.busy
    readonly property bool restartRequired: !!service && service.restartRequired
    readonly property bool canChange: !!service && !busy && !operationsBusy && !restartRequired
    implicitHeight: content.implicitHeight + Theme.size(40)
    elevated: true

    function previewFolder(url) {
        if (!canChange)
            return
        defaultRequested = false
        selectedBase = url
        pendingPreview = service.previewDirectory(url)
        previewError = pendingPreview.ok ? "" : I18n.status(pendingPreview.error || "")
        if (pendingPreview.ok)
            locationConfirmation.open()
    }
    function previewDefault() {
        if (!canChange)
            return
        defaultRequested = true
        pendingPreview = service.previewDefault()
        previewError = pendingPreview.ok ? "" : I18n.status(pendingPreview.error || "")
        if (pendingPreview.ok)
            locationConfirmation.open()
    }
    function confirmLocation() {
        if (!canChange || !pendingPreview.ok)
            return
        if (defaultRequested)
            service.resetToDefault()
        else
            service.migrateTo(selectedBase)
    }

    ColumnLayout {
        id: content
        anchors.fill: parent
        anchors.margins: Theme.size(20)
        spacing: Theme.size(12)
        Text {
            textFormat: Text.PlainText
            Layout.fillWidth: true
            text: qsTr("Card-art location")
            color: Theme.text
            font.pixelSize: Theme.fontSize(20)
            font.weight: Font.DemiBold
        }
        Text {
            textFormat: Text.PlainText
            objectName: "cardArtCurrentLocation"
            Layout.fillWidth: true
            text: qsTr("Current directory: %1").arg(root.service ? root.service.currentDirectory : "")
            color: Theme.textSecondary
            font.pixelSize: Theme.fontSize(12)
            wrapMode: Text.WrapAnywhere
        }
        Text {
            textFormat: Text.PlainText
            Layout.fillWidth: true
            text: qsTr("Choose a parent folder for a managed, profile-specific directory. Existing downloaded and custom images are copied and verified; original files are kept. Restart Hexproof to use the new location.")
            color: Theme.textSecondary
            font.pixelSize: Theme.fontSize(12)
            wrapMode: Text.WordWrap
        }
        InfoBanner {
            objectName: "cardArtLocationError"
            Layout.fillWidth: true
            message: root.previewError || (root.service ? I18n.status(root.service.lastError) : "")
        }
        InfoBanner {
            objectName: "cardArtLocationResult"
            Layout.fillWidth: true
            tone: root.restartRequired ? "warning" : "success"
            message: root.service ? I18n.status(root.service.lastResult) : ""
        }
        Text {
            textFormat: Text.PlainText
            Layout.fillWidth: true
            visible: root.busy
            text: root.service ? I18n.status(root.service.status) : ""
            color: Theme.textSecondary
            font.pixelSize: Theme.fontSize(12)
            wrapMode: Text.WordWrap
        }
        ProgressBar {
            objectName: "cardArtLocationProgress"
            Layout.fillWidth: true
            visible: root.busy
            value: root.service ? root.service.progress : 0
        }
        Flow {
            Layout.fillWidth: true
            spacing: Theme.size(10)
            AppButton {
                objectName: "chooseCardArtLocationButton"
                compact: true
                text: qsTr("Choose folder…")
                enabled: root.canChange
                onClicked: folderDialog.open()
            }
            AppButton {
                objectName: "resetCardArtLocationButton"
                compact: true
                text: qsTr("Use default location…")
                enabled: root.canChange && !root.service.defaultLocation
                onClicked: root.previewDefault()
            }
        }
    }
    FolderDialog {
        id: folderDialog
        objectName: "cardArtLocationFolderDialog"
        title: qsTr("Choose card-art parent folder")
        onAccepted: root.previewFolder(selectedFolder)
    }
    ConfirmDialog {
        id: locationConfirmation
        objectName: "cardArtLocationConfirmation"
        titleText: qsTr("Copy card art to this location?")
        message: qsTr("Managed destination:\n%1\n\nDownloaded and custom images will be copied and verified before the setting changes. Original files will not be removed. Card-art changes are paused after a successful copy until you restart Hexproof.")
                 .arg(root.pendingPreview.managedDirectory || "")
        confirmText: qsTr("Copy and use after restart")
        onConfirmed: root.confirmLocation()
    }
}
