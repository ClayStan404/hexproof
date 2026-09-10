// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Dialogs
import QtQuick.Layouts

Popup {
    id: root
    property var store: null
    property var catalogModel: null
    property var card: ({})
    property var bindings: []
    property int faceIndex: 0
    property string scope: "printing"
    property var candidate: ({})
    property url inspectedUrl: ""
    property url operationUrl: ""
    property url resultUrl: ""
    property string pendingOperation: ""
    property string errorMessage: ""
    property string resultMessage: ""
    readonly property bool busy: !!store && store.busy
    readonly property var binding: {
        if (faceIndex < 0 || faceIndex >= bindings.length
                || !scopeOptions.some(option => option.value === scope))
            return ({})
        const value = Object.assign({}, bindings[faceIndex])
        value.scope = scope
        return value
    }
    readonly property bool exactPrintingAvailable: bindings.length > 0
        && faceIndex >= 0 && faceIndex < bindings.length
        && !!bindings[faceIndex].setCode && !!bindings[faceIndex].collectorNumber
    readonly property bool cardScopeAvailable: faceIndex >= 0 && faceIndex < bindings.length
        && !!bindings[faceIndex].oracleId && bindings[faceIndex].allowCardScope !== false
    readonly property var scopeOptions: {
        const options = []
        if (exactPrintingAvailable)
            options.push({label: qsTr("This printing only"), value: "printing"})
        if (cardScopeAvailable)
            options.push({label: qsTr("All printings of this card"), value: "card"})
        return options
    }
    readonly property var currentOverride: {
        if (!store || !binding.name)
            return ({})
        void store.revision
        return store.entryFor(binding) || ({})
    }
    readonly property string currentImage: {
        if (!catalogModel || !binding.name)
            return ""
        void catalogModel.imageRevision
        if ((card.token || card.kind === "token" || card.kind === "emblem")
                && typeof catalogModel.tokenImageSource === "function")
            return catalogModel.tokenImageSource(binding.faceName || binding.name,
                                                 binding.setCode || "", binding.collectorNumber || "")
        return catalogModel.imageSource(binding.faceName || binding.name,
                                         binding.setCode || "", binding.collectorNumber || "")
    }
    readonly property bool canApply: !busy && !!candidate.ok && !!candidate.imageSource
                                     && !!binding.name && !!scope

    function showFor(value) {
        if (busy || !store)
            return false
        card = JSON.parse(JSON.stringify(value || {}))
        bindings = catalogModel && typeof catalogModel.customArtBindings === "function"
                 ? catalogModel.customArtBindings(card) : []
        faceIndex = Math.max(0, Array.from(bindings).findIndex(
                               item => String(item.faceName || "") === String(card.faceName || "")))
        scope = card.scope === "card" && cardScopeAvailable ? "card"
              : exactPrintingAvailable ? "printing" : ""
        candidate = ({})
        inspectedUrl = ""
        pendingOperation = ""
        resultMessage = ""
        errorMessage = scopeOptions.length === 0 && bindings.length > 0
                     ? qsTr("An exact printing or stable card identity is required. Select a printing or update the local card database.")
                     : bindings.length > 0 ? ""
                     : qsTr("This card could not be mapped to a supported image slot. Install or update the local card database first.")
        body.contentY = 0
        open()
        return true
    }
    function inspectImage(url) {
        if (busy || !store)
            return
        inspectedUrl = url
        candidate = ({})
        errorMessage = ""
        resultMessage = ""
        store.inspectImage(inspectedUrl)
    }
    function applyImage() {
        if (!canApply)
            return
        pendingOperation = "setImage"
        operationUrl = candidate.imageSource
        errorMessage = ""
        resultMessage = ""
        store.setImage(operationUrl, binding)
    }
    function restore(allFaces) {
        if (busy || !store || !binding.name)
            return
        pendingOperation = "removeBindings"
        errorMessage = ""
        resultMessage = ""
        store.removeBindings(binding, allFaces)
    }
    function clearCandidate() {
        candidate = ({})
        inspectedUrl = ""
        errorMessage = ""
        resultMessage = ""
    }

    parent: Overlay.overlay
    width: Math.min(Theme.size(780), parent.width - Theme.size(40))
    height: Math.min(Theme.size(760), parent.height - Theme.size(40))
    x: Math.round((parent.width - width) / 2)
    y: Math.round((parent.height - height) / 2)
    padding: Theme.size(22)
    modal: true
    focus: true
    closePolicy: busy ? Popup.NoAutoClose : Popup.CloseOnEscape | Popup.CloseOnPressOutside
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
            text: qsTr("Custom card art")
            color: Theme.text
            font.pixelSize: Theme.fontSize(20)
            font.weight: Font.DemiBold
        }
        Flickable {
            id: body
            objectName: "customCardArtBody"
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
                    objectName: "customCardArtError"
                    Layout.fillWidth: true
                    message: root.errorMessage
                }
                InfoBanner {
                    objectName: "customCardArtResult"
                    Layout.fillWidth: true
                    tone: "success"
                    message: root.resultMessage
                }
                Text {
                    textFormat: Text.PlainText
                    Layout.fillWidth: true
                    text: root.card.displayName || root.card.name || ""
                    color: Theme.primary
                    font.pixelSize: Theme.fontSize(16)
                    wrapMode: Text.WrapAnywhere
                }
                Text {
                    textFormat: Text.PlainText
                    Layout.fillWidth: true
                    text: qsTr("Custom images are local cosmetic overrides. They do not change card rules, printing identity, downloaded art, or other players' images.")
                    color: Theme.textSecondary
                    font.pixelSize: Theme.fontSize(12)
                    wrapMode: Text.WordWrap
                }
                Text {
                    textFormat: Text.PlainText
                    Layout.fillWidth: true
                    text: qsTr("Image slot")
                    color: Theme.textSecondary
                    font.pixelSize: Theme.fontSize(12)
                }
                AppComboBox {
                    objectName: "customArtFaceSelector"
                    Layout.fillWidth: true
                    model: root.bindings
                    textRole: "label"
                    currentIndex: root.faceIndex
                    enabled: !root.busy && root.bindings.length > 0
                    onActivated: index => { root.faceIndex = index; root.clearCandidate() }
                }
                Text {
                    textFormat: Text.PlainText
                    Layout.fillWidth: true
                    text: qsTr("Apply to")
                    color: Theme.textSecondary
                    font.pixelSize: Theme.fontSize(12)
                }
                AppComboBox {
                    objectName: "customArtScopeSelector"
                    Layout.fillWidth: true
                    model: root.scopeOptions
                    textRole: "label"
                    currentIndex: root.scopeOptions.findIndex(option => option.value === root.scope)
                    displayText: currentIndex < 0 ? qsTr("Choose an override scope") : currentText
                    enabled: !root.busy && root.bindings.length > 0
                    onActivated: index => { root.scope = root.scopeOptions[index].value; root.clearCandidate() }
                }
                InfoBanner {
                    Layout.fillWidth: true
                    tone: "warning"
                    visible: root.scope === "card"
                    message: qsTr("This override applies to this image slot across all printings and languages. A printing-specific override still takes priority.")
                }
                GridLayout {
                    Layout.fillWidth: true
                    columns: width >= Theme.size(450) ? 2 : 1
                    columnSpacing: Theme.size(14)
                    rowSpacing: Theme.size(10)
                    Repeater {
                        model: [{label: qsTr("Current image"), source: root.currentImage},
                                {label: qsTr("Selected local image"), source: root.candidate.imageSource || ""}]
                        delegate: ColumnLayout {
                            required property var modelData
                            Layout.fillWidth: true
                            spacing: Theme.size(6)
                            Text {
                                textFormat: Text.PlainText
                                Layout.fillWidth: true
                                text: modelData.label
                                color: Theme.textSecondary
                                font.pixelSize: Theme.fontSize(12)
                            }
                            Rectangle {
                                Layout.fillWidth: true
                                implicitHeight: Theme.size(220)
                                color: Theme.surfaceMuted
                                radius: Theme.radiusMedium
                                Image {
                                    objectName: "customArtImagePreview"
                                    anchors.fill: parent
                                    anchors.margins: Theme.size(6)
                                    source: modelData.source
                                    asynchronous: true
                                    fillMode: Image.PreserveAspectFit
                                }
                            }
                        }
                    }
                }
                Flow {
                    Layout.fillWidth: true
                    spacing: Theme.size(8)
                    AppButton {
                        objectName: "chooseCustomArtImageButton"
                        compact: true
                        text: qsTr("Choose local image…")
                        enabled: !root.busy && !!root.binding.name
                        onClicked: imageFile.open()
                    }
                    AppButton {
                        objectName: "restoreCustomArtFaceButton"
                        compact: true
                        text: qsTr("Restore this face")
                        enabled: !root.busy && !!root.currentOverride.id
                        onClicked: root.restore(false)
                    }
                    AppButton {
                        objectName: "restoreCustomArtCardButton"
                        compact: true
                        text: qsTr("Restore this card…")
                        enabled: !root.busy && !!root.binding.name
                        onClicked: restoreConfirmation.open()
                    }
                }
                Text {
                    textFormat: Text.PlainText
                    Layout.fillWidth: true
                    text: qsTr("Restoring removes overrides at the selected scope only. Removing a printing override may reveal an all-printings override; downloaded images are always preserved.")
                    color: Theme.textMuted
                    font.pixelSize: Theme.fontSize(11)
                    wrapMode: Text.WordWrap
                }
            }
        }
        ProgressBar {
            objectName: "customCardArtProgress"
            Layout.fillWidth: true
            visible: root.busy
            indeterminate: true
        }
        Flow {
            Layout.fillWidth: true
            spacing: Theme.size(10)
            AppButton {
                compact: true
                text: qsTr("Close")
                enabled: !root.busy
                onClicked: root.close()
            }
            AppButton {
                objectName: "applyCustomArtButton"
                compact: true
                variant: "primary"
                text: qsTr("Apply custom image")
                enabled: root.canApply
                onClicked: root.applyImage()
            }
        }
    }
    FileDialog {
        id: imageFile
        objectName: "customArtImageFileDialog"
        title: qsTr("Choose local card image")
        fileMode: FileDialog.OpenFile
        nameFilters: [qsTr("Card images") + " (*.jpg *.jpeg *.png *.webp)"]
        onAccepted: root.inspectImage(selectedFile)
    }
    ConfirmDialog {
        id: restoreConfirmation
        titleText: qsTr("Restore this card's art?")
        message: qsTr("Remove all image-slot overrides for this card at the selected scope? Downloaded images and overrides at other scopes are kept.")
        confirmText: qsTr("Restore")
        onConfirmed: root.restore(true)
    }
    Connections {
        target: root.store
        ignoreUnknownSignals: true
        function onInspectionFinished() {
            const preview = root.store.preview || ({})
            root.resultUrl = preview.fileUrl || ""
            if (!root.opened || preview.kind !== "image"
                    || root.resultUrl.toString() !== root.inspectedUrl.toString())
                return
            root.candidate = JSON.parse(JSON.stringify(preview))
            root.errorMessage = preview.ok ? "" : I18n.status(preview.error || root.store.lastError)
            if (root.errorMessage)
                body.contentY = 0
        }
        function onOperationFinished(result) {
            if (!root.opened || result.operation !== root.pendingOperation)
                return
            root.resultUrl = result.fileUrl || ""
            if (root.pendingOperation === "setImage"
                    && root.resultUrl.toString() !== root.operationUrl.toString())
                return
            root.pendingOperation = ""
            root.errorMessage = result.ok ? "" : I18n.status(result.error || root.store.lastError)
            root.resultMessage = result.ok
                ? result.operation === "setImage" ? qsTr("Custom image applied.")
                  : qsTr("Removed %1 override(s).").arg(result.removedCount || 0)
                : ""
            if (result.ok)
                root.candidate = ({})
            body.contentY = 0
        }
    }
}
