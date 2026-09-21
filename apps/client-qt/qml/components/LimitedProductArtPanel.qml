// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

pragma Translator: "TournamentLobby"

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

Surface {
    id: root

    required property var cardCatalogModel
    required property var preferencesModel
    property var product: ({})

    readonly property string productId: root.product && root.product.id
                                        ? String(root.product.id) : ""
    readonly property string productName: root.product && root.product.name
                                          ? String(root.product.name) : ""
    readonly property var localProduct:
        cardCatalogModel.installed && root.productId
        ? cardCatalogModel.limitedProduct(root.productId) : ({})
    readonly property bool hasLocalProduct: !!localProduct.id

    implicitHeight: content.implicitHeight + Theme.size(24)
    color: Theme.surfaceMuted

    RowLayout {
        id: content
        anchors.fill: parent
        anchors.margins: Theme.size(12)
        spacing: Theme.size(12)

        ColumnLayout {
            Layout.fillWidth: true
            spacing: Theme.size(4)

            Text {
                textFormat: Text.PlainText
                Layout.fillWidth: true
                text: root.productName
                      ? qsTranslate("TournamentLobby", "Offline product art · %1").arg(root.productName)
                      : qsTranslate("TournamentLobby", "Offline product art")
                color: Theme.text
                font.pixelSize: Theme.fontSize(13)
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }

            Text {
                textFormat: Text.PlainText
                Layout.fillWidth: true
                text: root.description()
                color: Theme.textMuted
                font.pixelSize: Theme.fontSize(11)
                elide: Text.ElideRight
            }

            ProgressBar {
                id: progress
                objectName: "limitedProductArtProgress"
                Layout.fillWidth: true
                implicitHeight: Theme.size(8)
                visible: root.productId.length > 0
                         && root.cardCatalogModel.limitedArtProductId === root.productId
                         && root.cardCatalogModel.limitedArtTotal > 0
                from: 0
                to: Math.max(1, root.cardCatalogModel.limitedArtTotal)
                value: root.cardCatalogModel.limitedArtCompleted

                background: Rectangle {
                    color: Theme.disabled
                    radius: height / 2
                }
                contentItem: Item {
                    Rectangle {
                        width: parent.width * progress.visualPosition
                        height: parent.height
                        radius: height / 2
                        color: root.cardCatalogModel.limitedArtFailed > 0
                               ? Theme.warning : Theme.primary
                    }
                }
            }
        }

        AppButton {
            objectName: "downloadLimitedProductArtButton"
            compact: true
            variant: "highlight"
            enabled: root.hasLocalProduct && !root.cardCatalogModel.limitedArtCaching
            disabledReason: !root.hasLocalProduct
                            ? qsTranslate("TournamentLobby", "Update the card database to install this product.")
                            : qsTranslate("TournamentLobby", "Another product download is running.")
            text: root.cardCatalogModel.limitedArtCaching
                  && root.cardCatalogModel.limitedArtProductId === root.productId
                  ? qsTranslate("TournamentLobby", "Downloading %1 / %2")
                      .arg(root.cardCatalogModel.limitedArtCompleted)
                      .arg(root.cardCatalogModel.limitedArtTotal)
                  : qsTranslate("TournamentLobby", "Download product art")
            onClicked: root.cardCatalogModel.cacheLimitedProductArt(root.productId)
        }
    }

    function description() {
        if (!root.hasLocalProduct)
            return qsTranslate("TournamentLobby", "This product is missing locally; update the card database first.")
        if (root.productId.length > 0
                && root.cardCatalogModel.limitedArtProductId === root.productId
                && !root.cardCatalogModel.limitedArtCaching
                && root.cardCatalogModel.limitedArtTotal > 0) {
            if (root.cardCatalogModel.limitedArtFailed > 0)
                return qsTranslate("TournamentLobby", "Finished · %1 unavailable image(s)")
                    .arg(root.cardCatalogModel.limitedArtFailed)
            return qsTranslate("TournamentLobby", "All %1 card image(s) are cached")
                .arg(root.cardCatalogModel.limitedArtTotal)
        }
        if (root.preferencesModel.cardArtProvider === "parallel")
            return qsTranslate("TournamentLobby", "Parallel sources · Scryfall + MTGCH")
        if (root.preferencesModel.cardArtProvider === "auto")
            return root.preferencesModel.cardLanguage === "zh"
                    ? qsTranslate("TournamentLobby", "Automatic source · MTGCH first, Scryfall fallback")
                    : qsTranslate("TournamentLobby", "Automatic source · Scryfall first, MTGCH fallback")
        return root.preferencesModel.cardArtProvider === "mtgch"
                ? qsTranslate("TournamentLobby", "MTGCH first · Scryfall fallback")
                : qsTranslate("TournamentLobby", "Scryfall first · MTGCH fallback")
    }
}
