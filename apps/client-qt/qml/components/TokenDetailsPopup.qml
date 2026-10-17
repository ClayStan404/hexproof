// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import "TokenPresentation.js" as TokenPresentation

AppPopup {
    id: root
    objectName: "tokenDetailsPopup"
    required property var catalogModel
    property var card: ({})
    readonly property string cardLanguage: catalogModel && catalogModel.language || "en"
    readonly property var details: TokenPresentation.details(catalogModel, facePreview.viewedCard)
    readonly property var customArtStore: typeof customCardArtStore !== "undefined"
                                         ? customCardArtStore : null

    width: Math.min(Theme.size(1040), parent.width - Theme.size(48))
    height: Math.min(Theme.size(620), parent.height - Theme.size(56))

    function showCard(value) {
        card = value || ({})
        facePreview.resetFace()
        rulesScroll.contentY = 0
        open()
    }
    function cacheCard() {
        if (facePreview.hasIdentity)
            TokenPresentation.prioritize(catalogModel, facePreview.viewedCard)
    }
    onOpened: cacheCard()
    onClosed: facePreview.resetFace()
    onCardLanguageChanged: {
        if (opened) {
            cacheCard()
            rulesScroll.contentY = 0
        }
    }

    CardFacePreviewController {
        id: facePreview
        catalogModel: root.catalogModel
        card: root.card
        tokenArt: true
        active: root.opened
    }

    Connections {
        target: facePreview
        function onViewedCardChanged() { rulesScroll.contentY = 0 }
    }

    contentItem: ColumnLayout {
        spacing: Theme.size(16)
        AppPopupHeader {
            titleText: root.details.displayName
            showClose: true
            closeObjectName: "closeTokenDetailsButton"
            onCloseRequested: root.close()
        }
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: Theme.size(20)
            ScrollView {
                id: artScroll
                objectName: "tokenDetailsArtScroll"
                Layout.preferredWidth: Math.min(Theme.size(580), root.availableWidth * 0.60)
                Layout.minimumWidth: 0
                Layout.fillHeight: true
                contentWidth: availableWidth
                clip: true
                ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                CardFacePreviewGallery {
                    controller: facePreview
                    artObjectName: "tokenDetailsArt"
                    columns: facePreview.displayFaces.length > 1
                             && artScroll.availableWidth >= Theme.size(368) ? 2 : 1
                    width: Math.min(artScroll.availableWidth,
                        Math.max(1, artScroll.availableHeight - Theme.size(12)) * 63 / 88 * columns
                        + (columns - 1) * Theme.size(8))
                }
            }
            Flickable {
                id: rulesScroll
                objectName: "tokenDetailsRulesScroll"
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumWidth: 0
                contentWidth: width
                contentHeight: rulesText.implicitHeight
                flickableDirection: Flickable.VerticalFlick
                boundsBehavior: Flickable.StopAtBounds
                clip: true
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                Text {
                    id: rulesText
                    objectName: "tokenDetailsRulesText"
                    textFormat: Text.PlainText
                    width: rulesScroll.width - Theme.size(16)
                    text: facePreview.displayFaces.map(face => face.fallbackText).join("\n\n")
                    font.pixelSize: Theme.fontSize(14)
                    color: Theme.text
                    wrapMode: Text.Wrap
                }
            }
        }
        AppButton {
            objectName: "tokenCustomArtButton"
            Layout.alignment: Qt.AlignRight
            compact: true
            visible: root.customArtStore !== null
            text: qsTr("Custom art…")
            onClicked: customArtDialog.showFor(root.card)
        }
    }

    CustomCardArtDialog {
        id: customArtDialog
        objectName: "tokenCustomCardArtDialog"
        store: root.customArtStore
        catalogModel: root.catalogModel
    }
}
