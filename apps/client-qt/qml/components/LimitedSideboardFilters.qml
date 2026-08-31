// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

pragma ComponentBehavior: Bound
pragma Translator: "SideboardPanel"

import QtQuick
import QtQuick.Layouts

Surface {
    id: root

    required property var panel
    property int colorFilterIndex: 0
    property int typeFilterIndex: 0
    property int manaFilterIndex: 0
    property int rarityFilterIndex: 0
    property int metadataRevision: 0
    readonly property var colorFilterKeys: ["all", "W", "U", "B", "R", "G",
                                            "multicolor", "colorless", "land", "unknown"]
    readonly property var colorFilterOptions: [qsTr("All colors"), qsTr("White"),
                                               qsTr("Blue"), qsTr("Black"), qsTr("Red"),
                                               qsTr("Green"), qsTr("Multicolor"),
                                               qsTr("Colorless"), qsTr("Lands"),
                                               qsTr("Unknown")]
    readonly property var typeFilterKeys: ["all", "creature", "planeswalker", "battle",
                                           "instant", "sorcery", "artifact", "enchantment",
                                           "land", "other"]
    readonly property var typeFilterOptions: [qsTr("All card types"), qsTr("Creatures"),
                                              qsTr("Planeswalkers"), qsTr("Battles"),
                                              qsTr("Instants"), qsTr("Sorceries"),
                                              qsTr("Artifacts"), qsTr("Enchantments"),
                                              qsTr("Lands"), qsTr("Other")]
    readonly property var manaFilterKeys: ["all", "0", "1", "2", "3", "4", "5",
                                           "6", "7+", "land", "unknown"]
    readonly property var manaFilterOptions: [qsTr("All mana values"), "0", "1", "2",
                                              "3", "4", "5", "6", "7+",
                                              qsTr("Lands"), qsTr("Unknown")]
    readonly property var rarityFilterKeys: ["all", "common", "uncommon", "rare",
                                              "mythic", "unknown"]
    readonly property var rarityFilterOptions: [qsTr("All rarities"), qsTr("Common"),
                                                 qsTr("Uncommon"), qsTr("Rare"),
                                                 qsTr("Mythic rare"), qsTr("Unknown")]
    readonly property string colorFilter: colorFilterKeys[colorFilterIndex]
    readonly property string typeFilter: typeFilterKeys[typeFilterIndex]
    readonly property string manaFilter: manaFilterKeys[manaFilterIndex]
    readonly property string rarityFilter: rarityFilterKeys[rarityFilterIndex]
    readonly property bool filtersActive: colorFilterIndex !== 0
                                          || typeFilterIndex !== 0
                                          || manaFilterIndex !== 0
                                          || rarityFilterIndex !== 0
    readonly property var enrichedMainboard: enrichCards(panel.mainboard)
    readonly property var enrichedSideboard: enrichCards(panel.sideboard)
    readonly property var visibleMainboard: filterCards(enrichedMainboard)
    readonly property var visibleSideboard: filterCards(enrichedSideboard)
    readonly property int mainboardCount: cardCount(panel.mainboard)
    readonly property int sideboardCount: cardCount(panel.sideboard)
    readonly property int visibleMainboardCount: cardCount(visibleMainboard)
    readonly property int visibleSideboardCount: cardCount(visibleSideboard)

    objectName: "limitedSideboardFilters"
    Layout.fillWidth: true
    visible: panel.isPlayer && panel.limitedDeck
    implicitHeight: Theme.size(54)
    color: Theme.surfaceMuted

    Connections {
        target: root.panel.cardCatalogModel
        ignoreUnknownSignals: true
        function onCatalogChanged() { root.metadataRevision++ }
        function onLanguageChanged() { root.metadataRevision++ }
    }

    LimitedCardGrouping {
        id: grouping
    }

    RowLayout {
        anchors.fill: parent
        anchors.margins: Theme.size(7)
        spacing: Theme.size(7)

        Text {
            textFormat: Text.PlainText
            text: qsTr("Filter both tables")
            color: Theme.textSecondary
            font.pixelSize: Theme.fontSize(10)
            font.weight: Font.DemiBold
        }

        AppComboBox {
            objectName: "limitedSideboardColorFilter"
            Layout.preferredWidth: Theme.size(132)
            implicitHeight: Theme.size(40)
            model: root.colorFilterOptions
            currentIndex: root.colorFilterIndex
            displayText: qsTr("Color: %1").arg(currentText)
            onActivated: index => root.colorFilterIndex = index
        }

        AppComboBox {
            objectName: "limitedSideboardTypeFilter"
            Layout.preferredWidth: Theme.size(148)
            implicitHeight: Theme.size(40)
            model: root.typeFilterOptions
            currentIndex: root.typeFilterIndex
            displayText: qsTr("Type: %1").arg(currentText)
            onActivated: index => root.typeFilterIndex = index
        }

        AppComboBox {
            objectName: "limitedSideboardManaFilter"
            Layout.preferredWidth: Theme.size(126)
            implicitHeight: Theme.size(40)
            model: root.manaFilterOptions
            currentIndex: root.manaFilterIndex
            displayText: qsTr("Mana: %1").arg(currentText)
            onActivated: index => root.manaFilterIndex = index
        }

        AppComboBox {
            objectName: "limitedSideboardRarityFilter"
            Layout.preferredWidth: Theme.size(136)
            implicitHeight: Theme.size(40)
            model: root.rarityFilterOptions
            currentIndex: root.rarityFilterIndex
            displayText: qsTr("Rarity: %1").arg(currentText)
            onActivated: index => root.rarityFilterIndex = index
        }

        AppButton {
            visible: root.filtersActive
            compact: true
            variant: "ghost"
            text: qsTr("Clear filters")
            onClicked: root.clearFilters()
        }

        Item { Layout.fillWidth: true }
    }

    function enrichCards(cards) {
        const revision = metadataRevision
        const typedCards = panel.cardsWithResolvedTypes(cards || [])
        if (!panel.limitedDeck || !panel.cardCatalogModel
                || typeof panel.cardCatalogModel.enrichLimitedCards
                   !== "function") {
            return revision < 0 ? [] : typedCards
        }
        const enriched = panel.cardCatalogModel.enrichLimitedCards(typedCards)
        return revision < 0 ? [] : enriched
    }

    function filterCards(cards) {
        if (!panel.limitedDeck || !filtersActive)
            return cards
        return grouping.filterCards(cards, colorFilter, typeFilter,
                                    manaFilter, rarityFilter)
    }

    function cardCount(cards) {
        let count = 0
        for (let index = 0; index < cards.length; ++index)
            count += Math.max(0, Number(cards[index].count || 0))
        return count
    }

    function clearFilters() {
        colorFilterIndex = 0
        typeFilterIndex = 0
        manaFilterIndex = 0
        rarityFilterIndex = 0
        panel.hideSideboardCardPreview()
    }
}
