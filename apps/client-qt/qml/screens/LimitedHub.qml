// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import "../components"

Page {
    id: root

    readonly property var appWindow: ApplicationWindow.window
    property var products: []
    property var openedPacks: []

    background: AppBackground { }

    Component.onCompleted: root.reloadProducts()

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.pageMargin
        spacing: Theme.size(14)

        ScreenHeader {
            Layout.fillWidth: true
            title: qsTr("Pack simulator")
            subtitle: qsTr("Open installed set products locally without changing a deck or event")
            onBackRequested: root.appWindow.popScreen()
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: Theme.size(14)

            Surface {
                Layout.preferredWidth: Theme.size(360)
                Layout.fillHeight: true
                elevated: true

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: Theme.size(20)
                    spacing: Theme.size(10)

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: Theme.size(10)

                        Text {
                            textFormat: Text.PlainText
                            text: qsTr("BOOSTER PRODUCT")
                            color: Theme.textMuted
                            font.pixelSize: Theme.fontSize(11)
                            font.weight: Font.Bold
                        }

                        LimitedSetPicker {
                            id: productSelector
                            Layout.fillWidth: true
                            sets: root.products
                            searchPlaceholder: qsTr("Search set, code, or booster product")
                            noMatchesText: qsTr("No booster products match this search.")
                        }

                        Text {
                            textFormat: Text.PlainText
                            Layout.fillWidth: true
                            text: productSelector.hasSelection
                                  && !productSelector.selectedSet.authentic
                                  ? qsTr("Approximate rarity collation — not an exact retail pack.")
                                  : qsTr("Exact generated product collation.")
                            color: productSelector.hasSelection
                                   && !productSelector.selectedSet.authentic
                                   ? Theme.warning : Theme.success
                            font.pixelSize: Theme.fontSize(11)
                            wrapMode: Text.WordWrap
                        }

                        AppTextField {
                            id: packCountField
                            Layout.fillWidth: true
                            text: "1"
                            placeholderText: qsTr("Pack count")
                            inputMethodHints: Qt.ImhDigitsOnly
                            validator: IntValidator { bottom: 1; top: 36 }
                        }

                        AppButton {
                            Layout.fillWidth: true
                            variant: "primary"
                            text: qsTr("Open packs")
                            enabled: productSelector.hasSelection
                                     && packCountField.acceptableInput
                                     && !packOpeningOverlay.opened
                            onClicked: root.openSelectedPacks()
                        }
                    }

                    Item { Layout.fillHeight: true }

                    Text {
                        textFormat: Text.PlainText
                        Layout.fillWidth: true
                        text: qsTr("Local pack opening does not create a collection or modify a deck. Online set limited uses server-authoritative physical card instances.")
                        color: Theme.textMuted
                        font.pixelSize: Theme.fontSize(10)
                        wrapMode: Text.WordWrap
                    }
                }
            }

            Surface {
                Layout.fillWidth: true
                Layout.fillHeight: true
                color: Theme.surfaceMuted

                Text {
                    textFormat: Text.PlainText
                    anchors.centerIn: parent
                    visible: root.openedPacks.length === 0
                    text: qsTr("Opened cards appear here.")
                    color: Theme.textMuted
                    font.pixelSize: Theme.fontSize(14)
                }

                ScrollView {
                    anchors.fill: parent
                    anchors.margins: Theme.size(14)
                    visible: root.openedPacks.length > 0
                    contentWidth: availableWidth
                    ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

                    Column {
                        width: parent.width
                        spacing: Theme.size(18)

                        Repeater {
                            model: root.openedPacks

                            delegate: Column {
                                id: packColumn
                                required property var modelData
                                required property int index
                                width: parent.width
                                spacing: Theme.size(8)

                                Text {
                                    textFormat: Text.PlainText
                                    text: qsTr("Pack %1").arg(parent.index + 1)
                                    color: Theme.text
                                    font.pixelSize: Theme.fontSize(15)
                                    font.weight: Font.DemiBold
                                }

                                Flow {
                                    width: parent.width
                                    spacing: Theme.size(9)

                                    Repeater {
                                        model: packColumn.modelData.cards || []

                                        delegate: Rectangle {
                                            id: openedCard
                                            required property var modelData
                                            width: Theme.size(116)
                                            height: Theme.size(168)
                                            radius: Theme.radiusSmall
                                            color: Theme.surfaceElevated
                                            clip: true

                                            Image {
                                                anchors.fill: parent
                                                fillMode: Image.PreserveAspectFit
                                                asynchronous: true
                                                source: root.cardImageSource(openedCard.modelData)
                                            }

                                            Rectangle {
                                                anchors.left: parent.left
                                                anchors.right: parent.right
                                                anchors.bottom: parent.bottom
                                                height: Theme.size(34)
                                                color: "#D9081512"
                                                Text {
                                                    textFormat: Text.PlainText
                                                    anchors.fill: parent
                                                    anchors.margins: Theme.size(5)
                                                    text: openedCard.modelData.name
                                                    color: "white"
                                                    font.pixelSize: Theme.fontSize(9)
                                                    elide: Text.ElideRight
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    Connections {
        target: cardCatalog
        function onCatalogChanged() { root.reloadProducts() }
    }

    PackOpeningOverlay {
        id: packOpeningOverlay
        cardCatalogModel: cardCatalog
    }

    function reloadProducts() {
        root.products = cardCatalog.limitedProducts()
    }

    function cardImageSource(card) {
        if (!card || !card.name)
            return ""
        void cardCatalog.imageRevision
        return cardCatalog.tableImageSource(
                    card.name, card.setCode || "", card.collectorNumber || "")
    }

    function openSelectedPacks() {
        const definition = cardCatalog.limitedProduct(productSelector.selectedId)
        const packs = cardCatalog.simulateLimitedPacks(
                        definition, Number(packCountField.text))
        root.openedPacks = packs

        const cards = []
        for (let packIndex = 0; packIndex < packs.length; ++packIndex) {
            const packCards = packs[packIndex].cards || []
            for (let cardIndex = 0; cardIndex < packCards.length; ++cardIndex)
                cards.push(packCards[cardIndex])
        }
        cardCatalog.cacheCardsIncrementally(cards)
        if (preferences.animatePackOpenings && packs.length > 0) {
            const product = productSelector.selectedSet
            packOpeningOverlay.showPacks(
                        packs, product && product.name ? product.name : "")
        }
    }
}
