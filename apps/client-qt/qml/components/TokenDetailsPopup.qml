// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import "TokenPresentation.js" as TokenPresentation

Popup {
    id: root
    objectName: "tokenDetailsPopup"
    required property var catalogModel
    property var card: ({})
    readonly property string cardLanguage: catalogModel && catalogModel.language || "en"
    readonly property var details: TokenPresentation.details(catalogModel, card)
    readonly property var customArtStore: typeof customCardArtStore !== "undefined"
                                         ? customCardArtStore : null

    parent: Overlay.overlay
    width: Math.min(Theme.size(780), parent.width - Theme.size(48))
    height: Math.min(Theme.size(620), parent.height - Theme.size(56))
    x: Math.round((parent.width - width) / 2)
    y: Math.round((parent.height - height) / 2)
    padding: Theme.size(24)
    modal: true
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    Overlay.modal: Rectangle { color: "#A6050B09" }
    background: Rectangle {
        color: Theme.surfaceElevated
        radius: Theme.radiusLarge
        border.color: Theme.borderStrong
    }

    function showCard(value) {
        card = value || ({})
        rulesScroll.contentY = 0
        open()
    }
    function cacheCard() {
        TokenPresentation.prioritize(catalogModel, card)
    }
    onOpened: cacheCard()
    onCardLanguageChanged: {
        if (opened) {
            cacheCard()
            rulesScroll.contentY = 0
        }
    }

    contentItem: ColumnLayout {
        spacing: Theme.size(16)
        RowLayout {
            Layout.fillWidth: true
            Text {
                textFormat: Text.PlainText
                Layout.fillWidth: true
                text: root.details.displayName
                font.pixelSize: Theme.fontSize(20)
                font.weight: Font.DemiBold
                color: Theme.text
                elide: Text.ElideRight
            }
            AppButton {
                objectName: "closeTokenDetailsButton"
                compact: true
                variant: "ghost"
                text: "×"
                accessibleName: qsTr("Close")
                Layout.preferredWidth: Theme.size(40)
                onClicked: root.close()
            }
        }
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: Theme.size(20)
            Image {
                objectName: "tokenDetailsArt"
                Layout.preferredWidth: Math.min(Theme.size(280), root.availableWidth * 0.42)
                Layout.fillHeight: true
                asynchronous: true
                fillMode: Image.PreserveAspectFit
                source: {
                    if (!root.opened || !root.card.name || !root.catalogModel) return ""
                    void root.catalogModel.imageRevision
                    void root.cardLanguage
                    return root.catalogModel.tokenImageSource(root.card.name,
                                      root.card.setCode || "", root.card.collectorNumber || "")
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
                    text: TokenPresentation.fullText(root.details)
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
