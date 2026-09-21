// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import "../components"

Page {
    id: root
    objectName: "setArtDownloadScreen"

    property var products: []

    background: AppBackground { }

    Component.onCompleted: root.reloadProducts()

    SettingsPage {
        anchors.fill: parent
        title: qsTr("Download set art")
        subtitle: qsTr("Cache every distinct printing from an installed set product")
        bodyObjectName: "setArtDownloadBody"

        Surface {
            Layout.fillWidth: true
            implicitHeight: productContent.implicitHeight + Theme.size(48)
            elevated: true

            ColumnLayout {
                id: productContent
                anchors.fill: parent
                anchors.margins: Theme.size(24)
                spacing: Theme.size(12)

                Text {
                    textFormat: Text.PlainText
                    text: qsTr("Set product")
                    color: Theme.text
                    font.pixelSize: Theme.fontSize(20)
                    font.weight: Font.DemiBold
                }
                Text {
                    textFormat: Text.PlainText
                    Layout.fillWidth: true
                    text: qsTr("Choose a set or booster product from the installed card database. Hexproof caches every distinct printing and independent face in that product, using the current card language and preferred art source. Already compatible local images are kept.")
                    color: Theme.textSecondary
                    font.pixelSize: Theme.fontSize(12)
                    wrapMode: Text.WordWrap
                    lineHeight: 1.35
                }

                LimitedSetPicker {
                    id: productSelector
                    Layout.fillWidth: true
                    Layout.topMargin: Theme.size(4)
                    sets: root.products
                    searchPlaceholder: qsTr("Search set, code, or booster product")
                    noMatchesText: qsTr("No set products match this search.")
                }

                Text {
                    textFormat: Text.PlainText
                    Layout.fillWidth: true
                    visible: productSelector.hasSelection
                    text: productSelector.hasSelection && productSelector.selectedSet.authentic
                          ? qsTr("Exact set product collation.")
                          : qsTr("Approximate rarity collation — not an exact retail pack.")
                    color: productSelector.hasSelection && productSelector.selectedSet
                           && !productSelector.selectedSet.authentic
                           ? Theme.warning : Theme.success
                    font.pixelSize: Theme.fontSize(11)
                    wrapMode: Text.WordWrap
                }

                LimitedProductArtPanel {
                    Layout.fillWidth: true
                    visible: productSelector.hasSelection
                    product: productSelector.selectedSet || ({})
                    cardCatalogModel: cardCatalog
                    preferencesModel: preferences
                }

                InfoBanner {
                    Layout.fillWidth: true
                    message: I18n.status(cardCatalog.lastError)
                }

                Text {
                    textFormat: Text.PlainText
                    Layout.fillWidth: true
                    visible: !cardCatalog.installed
                    text: qsTr("Install the card database first. Set Sealed and Set Draft lobbies still offer the same download for the event product.")
                    color: Theme.textMuted
                    font.pixelSize: Theme.fontSize(11)
                    wrapMode: Text.WordWrap
                }
            }
        }
    }

    Connections {
        target: cardCatalog
        function onCatalogChanged() { root.reloadProducts() }
    }

    function reloadProducts() {
        const source = cardCatalog.installed ? cardCatalog.limitedProducts() : []
        const result = []
        for (let index = 0; index < source.length; ++index) {
            const product = source[index]
            if (!product || product.productType === "cube")
                continue
            result.push(product)
        }
        root.products = result
    }
}
