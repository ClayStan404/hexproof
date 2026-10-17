// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

AppPopup {
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
    property var previewImageSources: []
    readonly property bool previewIsCurrent: printingIsCurrent(previewPrinting)
    signal chosen(var printing, bool sideboard)

    CardFacePreviewController {
        id: facePreview
        objectName: "printingFacePreviewController"
        catalogModel: root.catalogModel
        card: root.previewPrinting || ({})
        sourceItem: root.previewPrinting
        active: root.visible
        prioritizeImages: false
        onDisplayFacesChanged: root.ensurePreviewCached()
    }

    onClosed: facePreview.resetFace()

    Connections {
        target: root.catalogModel
        ignoreUnknownSignals: true
        function onImageRevisionChanged() {
            root.refreshPreviewSource()
            root.waitingForPreview = root.previewImageSources.some(source => !source)
        }
        function onCardCacheFinished(name, setCode, collectorNumber, success) {
            if (!root.matchesPreviewRequest(name, setCode, collectorNumber))
                return
            root.refreshPreviewSource()
            root.waitingForPreview = success && root.previewImageSources.some(source => !source)
        }
    }

    width: Math.min(Theme.size(1000), parent.width - Theme.size(48))
    height: Math.min(Theme.size(720), parent.height - Theme.size(56))

    contentItem: ColumnLayout {
        spacing: Theme.size(14)

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.size(12)

            AppPopupHeader {
                titleText: qsTr("Select printing")
                subtitleText: root.cardName.length > 0
                    ? qsTr("%1 · Choose a version to preview its card image before using it.").arg(root.cardName)
                    : qsTr("Choose a version to preview its card image before using it.")
                showClose: true
                onCloseRequested: root.close()
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
                Layout.preferredWidth: Math.min(Theme.size(620), root.width * 0.58)
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
                        text: facePreview.displayName || root.cardName
                        color: Theme.text
                        font.pixelSize: Theme.fontSize(15)
                        font.weight: Font.DemiBold
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                    }

                    ScrollView {
                        id: previewArea
                        objectName: "printingPreviewArea"
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        contentWidth: availableWidth
                        clip: true
                        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                        CardFacePreviewGallery {
                            objectName: "printingFaceGallery"
                            controller: facePreview
                            artObjectName: "printingPreviewImage"
                            fallbackObjectName: "printingPreviewFallback"
                            columns: facePreview.displayFaces.length > 1
                                && previewArea.availableWidth >= Theme.size(368) ? 2 : 1
                            width: Math.min(previewArea.availableWidth,
                                Math.max(1, previewArea.availableHeight - Theme.size(12)) * 63 / 88 * columns
                                + (columns - 1) * Theme.size(8))
                            imageSourceResolver: face => {
                                const index = facePreview.displayFaces.findIndex(value => value.faceIndex === face.faceIndex)
                                return root.previewImageSources[index] || ""
                            }
                        }
                    }

                    Text {
                        textFormat: Text.PlainText
                        objectName: "printingPreviewMetadata"
                        Layout.fillWidth: true
                        text: root.previewPrinting
                              ? [facePreview.viewedCard.setCode,
                                 "#" + facePreview.viewedCard.collectorNumber,
                                 facePreview.viewedCard.typeLine].filter(part => part).join(" · ")
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
                    ScrollBar.vertical: AppScrollBar { objectName: "printingOptionsScrollBar" }

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
        return facePreview.displayFaces.some(value => {
            const face = value.card
            return String(name) === String(face.name || cardName)
                   && String(setCode).toUpperCase() === String(face.setCode || "").toUpperCase()
                   && String(collectorNumber) === String(face.collectorNumber || "")
        })
    }

    function sourceForFace(value, index) {
        const face = value.card
        if (index === 0 && printingIsCurrent(previewPrinting) && currentImageSource.length > 0
                && !isRemoteHttpUrl(currentImageSource)) return currentImageSource
        const catalogSource = catalogPreviewSource(face)
        if (catalogSource.length > 0) return catalogSource
        const catalogFace = facePreview.faces[value.faceIndex] || ({})
        const fallback = index === 0 ? previewPrinting.imageUrl || "" : catalogFace.imageUrl || ""
        return isRemoteHttpUrl(fallback) ? "" : fallback
    }

    function refreshPreviewSource() {
        previewImageSources = previewPrinting && facePreview.hasIdentity
            ? facePreview.displayFaces.map((face, index) => sourceForFace(face, index)) : []
        previewImageSource = previewImageSources[0] || ""
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
        const missing = facePreview.displayFaces.filter((face, index) => !previewImageSources[index])
        waitingForPreview = !!previewPrinting && !!catalogModel && missing.length > 0
        if (!waitingForPreview || typeof catalogModel.cacheCardsIncrementally !== "function") return
        catalogModel.cacheCardsIncrementally(missing.map(face => ({
            name: face.card.name || cardName,
            setCode: face.card.setCode || "",
            collectorNumber: face.card.collectorNumber || "",
            exactArt: true
        })))
    }

    onPreviewPrintingChanged: ensurePreviewCached()
    onCurrentImageSourceChanged: ensurePreviewCached()
    onCatalogModelChanged: ensurePreviewCached()

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
