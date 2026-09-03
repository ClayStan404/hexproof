// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

pragma Translator: "TournamentLobby"

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

Surface {
    id: root

    required property var tournamentModel
    required property var cardCatalogModel
    required property var preferencesModel

    readonly property var localProduct:
        cardCatalogModel.installed && tournamentModel.product.id
        ? cardCatalogModel.limitedProduct(tournamentModel.product.id) : ({})
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
                text: qsTr("Offline product art · %1").arg(root.tournamentModel.product.name)
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
                visible: root.cardCatalogModel.limitedArtProductId
                         === root.tournamentModel.product.id
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
                            ? qsTr("Update the card database to install this product.")
                            : qsTr("Another product download is running.")
            text: root.cardCatalogModel.limitedArtCaching
                  && root.cardCatalogModel.limitedArtProductId
                     === root.tournamentModel.product.id
                  ? qsTr("Downloading %1 / %2")
                      .arg(root.cardCatalogModel.limitedArtCompleted)
                      .arg(root.cardCatalogModel.limitedArtTotal)
                  : qsTr("Download product art")
            onClicked: root.cardCatalogModel.cacheLimitedProductArt(
                           root.tournamentModel.product.id)
        }
    }

    function description() {
        if (!root.hasLocalProduct)
            return qsTr("This product is missing locally; update the card database first.")
        if (root.cardCatalogModel.limitedArtProductId === root.tournamentModel.product.id
                && !root.cardCatalogModel.limitedArtCaching
                && root.cardCatalogModel.limitedArtTotal > 0) {
            if (root.cardCatalogModel.limitedArtFailed > 0)
                return qsTr("Finished · %1 unavailable image(s)")
                    .arg(root.cardCatalogModel.limitedArtFailed)
            return qsTr("All %1 card image(s) are cached")
                .arg(root.cardCatalogModel.limitedArtTotal)
        }
        if (root.preferencesModel.cardArtProvider === "auto")
            return root.preferencesModel.cardLanguage === "zh"
                    ? qsTr("Automatic source · MTGCH first, Scryfall fallback")
                    : qsTr("Automatic source · Scryfall first, MTGCH fallback")
        return root.preferencesModel.cardArtProvider === "mtgch"
                ? qsTr("MTGCH first · Scryfall fallback")
                : qsTr("Scryfall first · MTGCH fallback")
    }
}
