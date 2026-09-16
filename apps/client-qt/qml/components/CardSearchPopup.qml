// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

Popup {
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
    property string typeFilter: ""
    property string setFilter: ""
    property string languageFilter: ""
    property string colorFilter: ""
    property string rarityFilter: ""
    property string legalityFilter: ""
    property string manaFilter: ""
    property int targetIndex: 0
    readonly property bool filtersActive: filterState.activeCount > 0
        || setFilter.trim().length > 0 || languageFilter.length > 0 || legalityFilter.length > 0
    readonly property bool hasSearchCriteria: query.trim().length > 0 || filtersActive
    readonly property var deckCards: !deckLibraryModel ? []
        : considerOnly ? (deckLibraryModel.considerCards || [])
        : targetIndex === 1 && allowSideboard ? (deckLibraryModel.sideboardCards || [])
        : (deckLibraryModel.mainCards || [])
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
    signal addRequested(var card, bool sideboard)

    parent: Overlay.overlay
    x: Theme.size(12)
    y: Theme.size(12)
    width: parent ? parent.width - Theme.size(24) : Theme.size(1000)
    height: parent ? parent.height - Theme.size(24) : Theme.size(700)
    padding: Theme.size(16)
    modal: true
    focus: true
    closePolicy: Popup.CloseOnEscape
    background: Rectangle {
        color: Theme.backgroundRaised
        border.color: Theme.borderStrong
        radius: Theme.radiusMedium
    }
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
            Text {
                textFormat: Text.PlainText
                Layout.fillWidth: true
                text: qsTr("Card search")
                font.pixelSize: Theme.fontSize(22)
                font.bold: true
                color: Theme.text
            }
            Text {
                textFormat: Text.PlainText
                text: root.searchPending ? qsTr("Searching cards…") : I18n.count("result", root.results.length)
                color: Theme.textMuted
            }
            AppButton {
                objectName: "cardSearchDoneButton"
                text: qsTr("Done")
                onClicked: root.close()
            }
        }
        GridLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumHeight: 0
            columns: root.width < Theme.size(660) ? 1 : 2
            columnSpacing: Theme.size(16)
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumWidth: 0
                Layout.minimumHeight: 0
                CardFilterBar {
                    id: filterBar
                    Layout.fillWidth: true
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
                Text {
                    textFormat: Text.PlainText
                    Layout.fillWidth: true
                    text: root.filtersAvailable ? qsTr("Click a card to add one copy to the selected section.")
                         : qsTr("Update the local card database to use search filters.")
                    color: Theme.textMuted
                    font.pixelSize: Theme.fontSize(11)
                    wrapMode: Text.WordWrap
                }
                CardArtGrid {
                    id: resultGrid
                    objectName: "cardSearchResults"
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.minimumHeight: 0
                    cards: root.opened && root.hasSearchCriteria && !root.searchPending ? root.results : []
                    catalogModel: root.catalogModel
                    preferredCardWidth: Math.max(Theme.size(150),
                        Math.min(Theme.size(230), width / 5 - Theme.size(16)))
                    emptyText: root.searchPending ? qsTr("Searching cards…")
                        : !root.hasSearchCriteria ? qsTr("Type a card name or choose filters to see search results.")
                        : qsTr("No matching cards")
                    onCardActivated: card => {
                        if (!root.opened || root.searchPending || !root.hasSearchCriteria) return
                        if (!root.deckLibraryModel || root.deckLibraryModel.canAddCard(card.name, card.typeLine))
                            root.addRequested(card, root.allowSideboard && root.targetIndex === 1)
                    }
                    onCardInspected: (card, item) => preview.inspect(card, item)
                    onCardInspectionEnded: item => preview.hide(item)
                    onVisibleCardsChanged: root.schedulePreviews()
                    onMovingChanged: {
                        if (moving) preview.hide()
                        root.schedulePreviews()
                    }
                }
            }
            Surface {
                visible: !!root.deckLibraryModel
                Layout.fillWidth: root.width < Theme.size(660)
                Layout.preferredWidth: Theme.size(310)
                Layout.maximumWidth: root.width < Theme.size(660) ? root.width : Theme.size(350)
                Layout.fillHeight: true
                Layout.minimumHeight: 0
                Layout.preferredHeight: root.width < Theme.size(660) ? Theme.size(220) : -1
                color: Theme.surfaceMuted
                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: Theme.size(10)
                    RowLayout {
                        Layout.fillWidth: true
                        Text {
                            textFormat: Text.PlainText
                            Layout.fillWidth: true
                            text: root.considerOnly ? qsTr("Consider")
                                : root.deckLibraryModel ? (root.deckLibraryModel.currentDeckName || qsTr("Main deck")) : ""
                            color: Theme.text
                            font.pixelSize: Theme.fontSize(18)
                            font.bold: true
                            elide: Text.ElideRight
                        }
                        CardManaCurve { cards: root.deckCards }
                    }
                    Text {
                        textFormat: Text.PlainText
                        text: qsTr("%1 cards").arg(root.deckCards.reduce((sum, card) => sum + Number(card.count || 1), 0))
                        color: Theme.accent
                    }
                    SegmentedControl {
                        visible: root.allowSideboard && !root.considerOnly
                        Layout.fillWidth: true
                        options: [qsTr("Main deck"), qsTr("Sideboard")]
                        currentIndex: root.targetIndex
                        onActivated: index => root.targetIndex = index
                    }
                    CompactCardList {
                        objectName: "cardSearchDeckList"
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.minimumHeight: 0
                        cards: root.deckCards
                        onCardActivated: card => {
                            if (!root.deckLibraryModel) return
                            if (root.considerOnly)
                                root.deckLibraryModel.changeConsiderCardCount(card.name, card.setCode, card.collectorNumber, -1)
                            else root.deckLibraryModel.changeCardCount(card.name, card.setCode, card.collectorNumber,
                                                                      root.allowSideboard && root.targetIndex === 1, -1)
                        }
                        onCardInspected: (card, item) => preview.inspect(card, item)
                        onCardInspectionEnded: item => preview.hide(item)
                        onMovingChanged: if (moving) preview.hide()
                    }
                    CardMetadataNotice {
                        Layout.fillWidth: true
                        cards: root.deckCards
                    }
                    AppButton {
                        Layout.fillWidth: true
                        text: qsTr("Done")
                        variant: "primary"
                        onClicked: root.close()
                    }
                }
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
        // Hover art is not part of the search/deck ColumnLayout.
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
        preview.hide()
        schedulePreviews()
    }
    onSearchingChanged: schedulePreviews()
    onOpened: {
        targetIndex = 0
        if (!filtersAvailable) resetFilters()
        filterBar.focusSearch()
        scheduleSearch()
    }
    onClosed: {
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
