// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

AppPopup {
    id: root
    property alias query: filterState.query
    property alias filters: filterState
    property var results: []
    property bool searching: false
    property bool searchScheduled: false
    readonly property bool searchPending: searching || searchScheduled
    property var deckLibraryModel: null
    property var catalogModel: null
    property bool allowSideboard: true
    property bool considerOnly: false
    property bool filtersAvailable: true
    property var selectedCard: null
    readonly property string selectedCardKey: selectedCard
        ? (selectedCard.instanceId || selectedCard.name || "") : ""
    readonly property bool canAddSelectedToDeck: {
        if (!selectedCard)
            return false
        if (!deckLibraryModel)
            return true
        return deckLibraryModel.canAddCard(selectedCard.name, selectedCard.typeLine)
    }
    property string typeFilter: ""
    property string setFilter: ""
    property string languageFilter: ""
    property string colorFilter: ""
    property string rarityFilter: ""
    property string legalityFilter: ""
    property string manaFilter: ""
    readonly property bool filtersActive: filterState.activeCount > 0
        || setFilter.trim().length > 0 || languageFilter.length > 0 || legalityFilter.length > 0
    readonly property bool hasSearchCriteria: query.trim().length > 0 || filtersActive
    readonly property var legalityOptions: [
        {"label": qsTr("Any format"), "value": ""},
        {"label": qsTr("Standard legal"), "value": "standard"},
        {"label": qsTr("Future Standard legal"), "value": "future"},
        {"label": qsTr("Pioneer legal"), "value": "pioneer"},
        {"label": qsTr("Modern legal"), "value": "modern"},
        {"label": qsTr("Legacy legal"), "value": "legacy"},
        {"label": qsTr("Vintage legal"), "value": "vintage"},
        {"label": qsTr("Pauper legal"), "value": "pauper"},
        {"label": qsTr("Commander legal"), "value": "commander"},
        {"label": qsTr("Duel Commander legal"), "value": "duel"},
        {"label": qsTr("Pauper Commander legal"), "value": "paupercommander"},
        {"label": qsTr("Oathbreaker legal"), "value": "oathbreaker"},
        {"label": qsTr("PreDH legal"), "value": "predh"},
        {"label": qsTr("Premodern legal"), "value": "premodern"},
        {"label": qsTr("Old School legal"), "value": "oldschool"},
        {"label": qsTr("Penny Dreadful legal"), "value": "penny"},
        {"label": qsTr("Alchemy legal"), "value": "alchemy"},
        {"label": qsTr("Historic legal"), "value": "historic"},
        {"label": qsTr("Timeless legal"), "value": "timeless"},
        {"label": qsTr("Brawl legal"), "value": "brawl"},
        {"label": qsTr("Standard Brawl legal"), "value": "standardbrawl"},
        {"label": qsTr("Competitive Brawl legal"), "value": "competitivebrawl"},
        {"label": qsTr("Gladiator legal"), "value": "gladiator"},
        {"label": qsTr("TLR legal"), "value": "tlr"}
    ]

    signal searchRequested(string query, string typeFilter, string setFilter,
                           string languageFilter, string colorFilter, string rarityFilter,
                           string legalityFilter, string manaFilter)
    signal addRequested(var card, string destination)

    width: Math.min(Theme.size(960), parent ? parent.width - Theme.size(48) : Theme.size(960))
    height: Math.min(Theme.size(720), parent ? parent.height - Theme.size(56) : Theme.size(720))
    CardFilterState {
        id: filterState
        onQueryChanged: root.scheduleSearch()
        onTypesChanged: root.typeFilter = types.join(",")
        onColorsChanged: root.colorFilter = colors.join(",")
        onRaritiesChanged: root.rarityFilter = rarities.join(",")
        onManaValuesChanged: root.manaFilter = manaValues.join(",")
    }
    contentItem: ColumnLayout {
        spacing: Theme.size(12)

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.size(10)

            AppPopupHeader {
                titleText: qsTr("Card search")
                subtitleText: root.allowSideboard
                    ? qsTr("Search first, then add the selected card to the main deck, sideboard, or Consider.")
                    : qsTr("Search first, then add the selected card to the main deck or Consider.")
            }

            Text {
                textFormat: Text.PlainText
                text: root.searchPending ? qsTr("Searching cards…")
                    : I18n.count("result", root.results.length)
                color: Theme.textMuted
            }

            AppButton {
                objectName: "cardSearchDoneButton"
                compact: true
                variant: "ghost"
                text: "×"
                accessibleName: qsTr("Close")
                Layout.preferredWidth: Theme.size(40)
                onClicked: root.close()
            }
        }

        CardFilterBar {
            id: filterBar
            Layout.fillWidth: true
            compact: true
            filters: filterState
            filtersAvailable: root.filtersAvailable
            onResetRequested: root.resetFilters()
            placeholderText: qsTr("Search English or Chinese names…")
            extraFilters: Component {
                ColumnLayout {
                    Text {
                        textFormat: Text.PlainText
                        text: qsTr("Printing and format")
                        color: Theme.text
                        font.pixelSize: Theme.fontSize(17)
                    }
                    AppTextField {
                        objectName: "cardSearchSetFilter"
                        Layout.fillWidth: true
                        placeholderText: qsTr("Set code")
                        text: root.setFilter
                        maximumLength: 12
                        onTextEdited: root.setFilter = text
                    }
                    AppComboBox {
                        objectName: "cardSearchLanguageFilter"
                        Layout.fillWidth: true
                        model: [qsTr("All printings"), qsTr("English printings"), qsTr("Chinese printings")]
                        currentIndex: ["", "en", "zhs"].indexOf(root.languageFilter)
                        onActivated: index => root.languageFilter = ["", "en", "zhs"][index]
                    }
                    AppComboBox {
                        objectName: "cardSearchLegalityFilter"
                        Layout.fillWidth: true
                        model: root.legalityOptions
                        textRole: "label"
                        valueRole: "value"
                        currentIndex: root.optionIndex(root.legalityOptions, root.legalityFilter)
                        onActivated: index => root.legalityFilter = root.legalityOptions[index].value
                    }
                    Text {
                        textFormat: Text.PlainText
                        Layout.fillWidth: true
                        text: qsTr("Filters narrow database results only; deck legality is not enforced.")
                        color: Theme.textMuted
                        wrapMode: Text.WordWrap
                    }
                }
            }
        }

        CardArtGrid {
            id: resultGrid
            objectName: "cardSearchResults"
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumHeight: 0
            cards: root.opened && root.hasSearchCriteria && !root.searchPending ? root.results : []
            catalogModel: root.catalogModel
            selectedKey: root.selectedCardKey
            preferredCardWidth: Math.max(Theme.size(150),
                Math.min(Theme.size(230), width / 4 - Theme.size(16)))
            prominentScrollBar: true
            emptyText: root.searchPending ? qsTr("Searching cards…")
                : !root.hasSearchCriteria ? qsTr("Type a card name or choose filters to see search results.")
                : qsTr("No matching cards")
            onCardActivated: card => root.selectedCard = card
            onCardInspected: (card, item) => preview.inspect(card, item)
            onCardInspectionEnded: item => preview.hide(item)
            onVisibleCardsChanged: root.schedulePreviews()
            onMovingChanged: {
                if (moving) preview.hide()
                root.schedulePreviews()
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.size(8)

            Text {
                textFormat: Text.PlainText
                Layout.fillWidth: true
                text: root.selectedCard
                      ? (root.selectedCard.displayName || root.selectedCard.name)
                      : qsTr("Select a search result to add it.")
                color: root.selectedCard ? Theme.text : Theme.textMuted
                elide: Text.ElideRight
            }

            AppButton {
                objectName: "cardSearchAddMain"
                compact: true
                text: qsTr("Main deck")
                enabled: root.canAddSelectedToDeck
                onClicked: root.addSelected("main")
            }

            AppButton {
                objectName: "cardSearchAddSideboard"
                compact: true
                visible: root.allowSideboard
                text: qsTr("Sideboard")
                enabled: root.canAddSelectedToDeck
                onClicked: root.addSelected("sideboard")
            }

            AppButton {
                objectName: "cardSearchAddConsider"
                compact: true
                text: qsTr("Consider")
                enabled: root.selectedCard !== null
                onClicked: root.addSelected("consider")
            }
        }
    }
    Item {
        parent: root.contentItem ? root.contentItem.parent : null
        anchors.fill: parent
        anchors.margins: Theme.size(12)
        visible: root.opened
        enabled: false
        z: 1000
        // Hover art is not part of the search ColumnLayout.
        CardHoverPreview {
            id: preview
            catalogModel: root.catalogModel
        }
    }
    Timer {
        id: searchTimer
        interval: 220
        onTriggered: root.searchNow()
    }
    Timer {
        id: previewTimer
        interval: 350
        onTriggered: root.updatePreviews(resultGrid.visibleCards)
    }
    onTypeFilterChanged: {
        if (filterState.types.join(",") !== typeFilter) filterState.types = typeFilter ? typeFilter.split(",") : []
        scheduleSearch()
    }
    onColorFilterChanged: {
        if (filterState.colors.join(",") !== colorFilter) filterState.colors = colorFilter ? colorFilter.split(",") : []
        scheduleSearch()
    }
    onRarityFilterChanged: {
        if (filterState.rarities.join(",") !== rarityFilter) filterState.rarities = rarityFilter ? rarityFilter.split(",") : []
        scheduleSearch()
    }
    onManaFilterChanged: {
        if (filterState.manaValues.join(",") !== manaFilter) filterState.manaValues = manaFilter ? manaFilter.split(",") : []
        scheduleSearch()
    }
    onSetFilterChanged: scheduleSearch()
    onLanguageFilterChanged: scheduleSearch()
    onLegalityFilterChanged: scheduleSearch()
    onResultsChanged: {
        selectedCard = null
        preview.hide()
        schedulePreviews()
    }
    onSearchingChanged: schedulePreviews()
    onSearchPendingChanged: if (searchPending) selectedCard = null
    onOpened: {
        selectedCard = null
        if (!filtersAvailable) resetFilters()
        filterBar.focusSearch()
        scheduleSearch()
    }
    onClosed: {
        selectedCard = null
        searchTimer.stop()
        previewTimer.stop()
        updatePreviews([])
        preview.hide()
    }
    onAboutToHide: {
        searchTimer.stop()
        searchScheduled = true
        previewTimer.stop()
        updatePreviews([])
    }
    Component.onDestruction: updatePreviews([])
    function openSearch() { open() }
    function addSelected(destination) {
        if (!opened || searchPending || !hasSearchCriteria || !selectedCard)
            return
        if (destination !== "consider" && deckLibraryModel
                && !deckLibraryModel.canAddCard(selectedCard.name, selectedCard.typeLine))
            return
        addRequested(selectedCard, destination)
    }
    function updatePreviews(cards) {
        if (catalogModel && typeof catalogModel.setSearchPreviewCards === "function")
            catalogModel.setSearchPreviewCards(cards)
    }
    function schedulePreviews() {
        previewTimer.stop()
        updatePreviews([])
        if (opened && !searchPending && !searchTimer.running && !resultGrid.moving && hasSearchCriteria)
            previewTimer.restart()
    }
    function scheduleSearch() {
        searchScheduled = true
        previewTimer.stop()
        updatePreviews([])
        if (opened) searchTimer.restart()
    }
    function searchNow() {
        searchScheduled = true
        searchTimer.stop()
        searchRequested(query.trim(), typeFilter, setFilter.trim(), languageFilter,
                        colorFilter, rarityFilter, legalityFilter, manaFilter)
        searchScheduled = false
        schedulePreviews()
    }
    function resetFilters() {
        filterState.reset()
        setFilter = ""; languageFilter = ""; legalityFilter = ""
        scheduleSearch()
    }
    function optionIndex(options, value) {
        for (let index = 0; index < options.length; ++index)
            if (options[index].value === value) return index
        return 0
    }
}
