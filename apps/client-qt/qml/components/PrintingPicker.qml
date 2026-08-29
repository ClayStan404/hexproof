// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

Popup {
    id: root

    property string cardName: ""
    property string currentSetCode: ""
    property string currentCollectorNumber: ""
    property string currentImageSource: ""
    property bool sideboard: false
    property var options: []
    property var previewPrinting: null
    property var catalogModel: null
    property string queryError: ""
    property bool waitingForPreview: false
    property string previewImageSource: ""
    readonly property bool previewIsCurrent: printingIsCurrent(previewPrinting)
    signal chosen(var printing, bool sideboard)

    Connections {
        target: root.catalogModel
        ignoreUnknownSignals: true
        function onImageRevisionChanged() {
            root.refreshPreviewSource()
        }
        function onCardCacheFinished(name, setCode, collectorNumber, success) {
            if (!root.matchesPreviewRequest(name, setCode, collectorNumber))
                return
            root.refreshPreviewSource()
            if (!success || root.previewImageSource.length > 0)
                root.waitingForPreview = false
        }
    }

    parent: Overlay.overlay
    x: Math.round((parent.width - width) / 2)
    y: Math.round((parent.height - height) / 2)
    width: Math.min(Theme.size(1000), parent.width - Theme.size(48))
    height: Math.min(Theme.size(720), parent.height - Theme.size(56))
    padding: Theme.size(24)
    modal: true
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

    Overlay.modal: Rectangle { color: "#A6050B09" }

    background: Rectangle {
        color: Theme.surfaceElevated
        radius: Theme.radiusLarge
        border.width: 1
        border.color: Theme.borderStrong
    }

    contentItem: ColumnLayout {
        spacing: Theme.size(14)

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.size(12)

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Theme.size(3)

                Text {
                    textFormat: Text.PlainText
                    Layout.fillWidth: true
                    text: qsTr("Select printing") + " · " + root.cardName
                    color: Theme.text
                    font.pixelSize: Theme.fontSize(20)
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }

                Text {
                    textFormat: Text.PlainText
                    Layout.fillWidth: true
                    text: qsTr("Choose a version to preview its card image before using it.")
                    color: Theme.textSecondary
                    font.pixelSize: Theme.fontSize(13)
                    wrapMode: Text.WordWrap
                }
            }

            AppButton {
                compact: true
                variant: "ghost"
                text: "×"
                accessibleName: qsTr("Close")
                Layout.preferredWidth: Theme.size(40)
                onClicked: root.close()
            }
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 1
            color: Theme.divider
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: Theme.size(18)

            Surface {
                Layout.preferredWidth: Math.min(Theme.size(350), root.width * 0.42)
                Layout.fillHeight: true
                radius: Theme.radiusMedium
                color: Theme.surfaceMuted

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: Theme.size(16)
                    spacing: Theme.size(10)

                    Text {
                        textFormat: Text.PlainText
                        Layout.fillWidth: true
                        text: root.previewPrinting ? root.previewPrinting.displayName : root.cardName
                        color: Theme.text
                        font.pixelSize: Theme.fontSize(15)
                        font.weight: Font.DemiBold
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                    }

                    Item {
                        id: previewArea
                        Layout.fillWidth: true
                        Layout.fillHeight: true

                        Rectangle {
                            id: imageFrame
                            anchors.centerIn: parent
                            width: Math.min(parent.width, Math.round(parent.height * 0.7176))
                            height: Math.min(parent.height, Math.round(parent.width / 0.7176))
                            radius: Theme.radiusMedium
                            color: Theme.surfaceElevated
                            border.width: 1
                            border.color: Theme.borderStrong
                            clip: true

                            Image {
                                id: previewImage
                                objectName: "printingPreviewImage"
                                anchors.fill: parent
                                source: root.previewImageSource
                                fillMode: Image.PreserveAspectFit
                                asynchronous: true
                                cache: false
                                visible: status === Image.Ready
                            }

                            ActivityRing {
                                anchors.centerIn: parent
                                width: Theme.size(28)
                                height: Theme.size(28)
                                visible: previewImage.status === Image.Loading
                                         || root.waitingForPreview
                                         || (root.previewImageSource.length > 0
                                             && previewImage.status === Image.Null)
                            }

                            Column {
                                anchors.centerIn: parent
                                width: parent.width - Theme.size(32)
                                spacing: Theme.size(8)
                                visible: !root.waitingForPreview
                                         && previewImage.status !== Image.Loading
                                         && previewImage.status !== Image.Ready
                                         && (previewImage.status === Image.Error
                                             || root.previewImageSource.length === 0)

                                Text {
                                    textFormat: Text.PlainText
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: "◇"
                                    color: Theme.borderStrong
                                    font.pixelSize: Theme.fontSize(38)
                                }

                                Text {
                                    textFormat: Text.PlainText
                                    width: parent.width
                                    text: root.previewImageSource.length > 0
                                          ? qsTr("Could not load this card image.")
                                          : qsTr("No card image is available for this version.")
                                    color: Theme.textMuted
                                    font.pixelSize: Theme.fontSize(11)
                                    horizontalAlignment: Text.AlignHCenter
                                    wrapMode: Text.WordWrap
                                }
                            }
                        }
                    }

                    Text {
                        textFormat: Text.PlainText
                        Layout.fillWidth: true
                        text: root.previewPrinting
                              ? root.previewPrinting.setCode + " · #"
                                + root.previewPrinting.collectorNumber + " · "
                                + root.previewPrinting.typeLine
                              : ""
                        color: Theme.textSecondary
                        font.pixelSize: Theme.fontSize(11)
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                    }

                    AppButton {
                        id: usePrintingButton
                        objectName: "usePrintingButton"
                        Layout.fillWidth: true
                        variant: root.previewIsCurrent ? "ghost" : "primary"
                        text: root.previewIsCurrent ? qsTr("Current") : qsTr("Use version")
                        enabled: root.previewPrinting !== null && !root.previewIsCurrent
                        onClicked: {
                            root.chosen(root.previewPrinting, root.sideboard)
                            root.close()
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillHeight: true
                implicitWidth: 1
                color: Theme.divider
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: Theme.size(10)

                RowLayout {
                    Layout.fillWidth: true

                    Text {
                        textFormat: Text.PlainText
                        text: qsTr("Available versions")
                        color: Theme.text
                        font.pixelSize: Theme.fontSize(14)
                        font.weight: Font.DemiBold
                    }

                    Item { Layout.fillWidth: true }

                    Text {
                        textFormat: Text.PlainText
                        text: I18n.count("printing", root.options.length)
                        color: Theme.textMuted
                        font.pixelSize: Theme.fontSize(11)
                    }
                }

                InfoBanner {
                    objectName: "printingQueryError"
                    Layout.fillWidth: true
                    message: root.queryError.length > 0 ? I18n.status(root.queryError) : ""
                }

                ListView {
                    id: printingList
                    objectName: "printingOptions"
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    model: root.options
                    spacing: Theme.size(7)
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                    delegate: Surface {
                        id: printingDelegate
                        required property var modelData
                        required property int index
                        objectName: "printingOption" + index
                        readonly property bool current: root.printingIsCurrent(modelData)
                        readonly property bool previewed:
                            root.printingsMatch(modelData, root.previewPrinting)

                        width: ListView.view.width
                        height: Theme.size(68)
                        radius: Theme.radiusMedium
                        interactive: true
                        color: previewed ? Theme.primaryMuted
                                         : (optionMouse.containsMouse
                                            ? Theme.surfaceHover : Theme.surfaceMuted)
                        border.color: previewed ? Theme.primary
                                               : (current ? Theme.accent : Theme.border)

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: Theme.size(12)
                            anchors.rightMargin: Theme.size(12)
                            spacing: Theme.size(12)

                            Rectangle {
                                Layout.preferredWidth: Theme.size(76)
                                Layout.preferredHeight: Theme.size(38)
                                radius: Theme.radiusSmall
                                color: Theme.surfaceElevated
                                border.width: 1
                                border.color: Theme.borderStrong

                                Text {
                                    textFormat: Text.PlainText
                                    anchors.centerIn: parent
                                    text: printingDelegate.modelData.setCode
                                    color: Theme.primary
                                    font.pixelSize: Theme.fontSize(13)
                                    font.weight: Font.Bold
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: Theme.size(2)

                                Text {
                                    textFormat: Text.PlainText
                                    Layout.fillWidth: true
                                    text: printingDelegate.modelData.displayName
                                    color: Theme.text
                                    font.pixelSize: Theme.fontSize(13)
                                    font.weight: Font.Medium
                                    elide: Text.ElideRight
                                }

                                Text {
                                    textFormat: Text.PlainText
                                    Layout.fillWidth: true
                                    text: printingDelegate.modelData.typeLine + " · #"
                                          + printingDelegate.modelData.collectorNumber
                                    color: Theme.textMuted
                                    font.pixelSize: Theme.fontSize(10)
                                    elide: Text.ElideRight
                                }
                            }

                            StatusPill {
                                visible: printingDelegate.current
                                text: qsTr("Current")
                                statusColor: Theme.accent
                            }

                            Text {
                                textFormat: Text.PlainText
                                visible: printingDelegate.previewed
                                         && !printingDelegate.current
                                text: qsTr("Previewing")
                                color: Theme.primary
                                font.pixelSize: Theme.fontSize(10)
                                font.weight: Font.DemiBold
                            }
                        }

                        MouseArea {
                            id: optionMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                printingList.currentIndex = printingDelegate.index
                                root.previewPrinting = printingDelegate.modelData
                            }
                        }
                    }
                }
            }
        }
    }

    function printingIsCurrent(printing) {
        return printing
               && printing.setCode === currentSetCode
               && printing.collectorNumber === currentCollectorNumber
    }

    function isRemoteHttpUrl(url) {
        const value = String(url || "").toLowerCase()
        return value.startsWith("https:") || value.startsWith("http:")
    }

    function matchesPreviewRequest(name, setCode, collectorNumber) {
        if (!previewPrinting)
            return false
        return String(name) === String(previewPrinting.name || cardName)
               && String(setCode).toUpperCase()
                  === String(previewPrinting.setCode || "").toUpperCase()
               && String(collectorNumber)
                  === String(previewPrinting.collectorNumber || "")
    }

    function refreshPreviewSource() {
        if (!previewPrinting) {
            previewImageSource = ""
            return
        }
        if (printingIsCurrent(previewPrinting) && currentImageSource.length > 0
                && !isRemoteHttpUrl(currentImageSource)) {
            previewImageSource = currentImageSource
            return
        }
        const catalogSource = catalogPreviewSource(previewPrinting)
        if (catalogSource.length > 0) {
            previewImageSource = catalogSource
            return
        }
        const fallback = previewPrinting.imageUrl || ""
        previewImageSource = isRemoteHttpUrl(fallback) ? "" : fallback
    }

    function catalogPreviewSource(printing) {
        if (!printing || !root.catalogModel
                || (typeof root.catalogModel.printingImageSource !== "function"
                    && typeof root.catalogModel.imageSource !== "function"))
            return ""
        const source = typeof root.catalogModel.printingImageSource === "function"
                     ? root.catalogModel.printingImageSource(
                           String(printing.name || root.cardName || ""),
                           String(printing.setCode || ""),
                           String(printing.collectorNumber || ""))
                     : root.catalogModel.imageSource(
                           String(printing.name || root.cardName || ""),
                           String(printing.setCode || ""),
                           String(printing.collectorNumber || ""))
        return isRemoteHttpUrl(source) ? "" : (source || "")
    }

    function ensurePreviewCached() {
        refreshPreviewSource()
        if (!previewPrinting) {
            waitingForPreview = false
            return
        }
        if (previewImageSource.length > 0) {
            waitingForPreview = false
            return
        }
        if (!catalogModel) {
            waitingForPreview = false
            return
        }
        waitingForPreview = true
        catalogModel.cacheCardsIncrementally([{
            "name": previewPrinting.name || cardName,
            "setCode": previewPrinting.setCode || "",
            "collectorNumber": previewPrinting.collectorNumber || "",
            "exactArt": true
        }])
    }

    onPreviewPrintingChanged: ensurePreviewCached()
    onCurrentImageSourceChanged: ensurePreviewCached()
    onCatalogModelChanged: ensurePreviewCached()
    onPreviewImageSourceChanged: {
        if (previewImageSource.length > 0)
            waitingForPreview = false
    }

    function printingsMatch(left, right) {
        return left && right
               && left.setCode === right.setCode
               && left.collectorNumber === right.collectorNumber
    }

    function showFor(card, isSideboard) {
        cardName = card.name
        currentSetCode = card.setCode || ""
        currentCollectorNumber = card.collectorNumber || ""
        currentImageSource = card.imageSource || ""
        if (currentImageSource.length === 0)
            currentImageSource = catalogPreviewSource(card) || ""
        if (isRemoteHttpUrl(currentImageSource))
            currentImageSource = ""
        sideboard = isSideboard
        const available = catalogModel && typeof catalogModel.printings === "function"
                          ? catalogModel.printings(card.name) : []
        queryError = catalogModel && typeof catalogModel.printingsError !== "undefined"
                     ? String(catalogModel.printingsError || "") : ""
        available.sort((left, right) => {
            const leftCurrent = printingIsCurrent(left)
            const rightCurrent = printingIsCurrent(right)
            return leftCurrent === rightCurrent ? 0 : (leftCurrent ? -1 : 1)
        })
        options = available
        previewPrinting = available.length > 0 ? available[0] : null
        printingList.currentIndex = available.length > 0 ? 0 : -1
        open()
    }
}
