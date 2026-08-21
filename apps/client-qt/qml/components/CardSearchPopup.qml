// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

Popup {
    id: root

    property alias query: searchField.text
    property var results: []
    property bool searching: false
    property var deckLibraryModel: null
    property bool allowSideboard: true
    property bool filtersAvailable: true
    property string typeFilter: ""
    property alias setFilter: setCodeField.text
    property string languageFilter: ""
    property string colorFilter: ""
    property string rarityFilter: ""
    property string legalityFilter: ""
    readonly property bool filtersActive:
        typeFilter.length > 0 || setFilter.trim().length > 0
        || languageFilter.length > 0 || colorFilter.length > 0
        || rarityFilter.length > 0 || legalityFilter.length > 0
    readonly property bool hasSearchCriteria:
        searchField.text.trim().length > 0 || filtersActive
    readonly property var typeOptions: [
        {"label": qsTr("All types"), "value": ""},
        {"label": qsTr("Creature"), "value": "Creature"},
        {"label": qsTr("Instant"), "value": "Instant"},
        {"label": qsTr("Sorcery"), "value": "Sorcery"},
        {"label": qsTr("Artifact"), "value": "Artifact"},
        {"label": qsTr("Enchantment"), "value": "Enchantment"},
        {"label": qsTr("Planeswalker"), "value": "Planeswalker"},
        {"label": qsTr("Land"), "value": "Land"}
    ]
    readonly property var languageOptions: [
        {"label": qsTr("All printings"), "value": ""},
        {"label": qsTr("English printings"), "value": "en"},
        {"label": qsTr("Chinese printings"), "value": "zhs"}
    ]
    readonly property var colorOptions: [
        {"label": qsTr("Any color identity"), "value": ""},
        {"label": qsTr("White"), "value": "W"},
        {"label": qsTr("Blue"), "value": "U"},
        {"label": qsTr("Black"), "value": "B"},
        {"label": qsTr("Red"), "value": "R"},
        {"label": qsTr("Green"), "value": "G"},
        {"label": qsTr("Multicolor"), "value": "M"},
        {"label": qsTr("Colorless"), "value": "C"}
    ]
    readonly property var rarityOptions: [
        {"label": qsTr("All rarities"), "value": ""},
        {"label": qsTr("Common"), "value": "common"},
        {"label": qsTr("Uncommon"), "value": "uncommon"},
        {"label": qsTr("Rare"), "value": "rare"},
        {"label": qsTr("Mythic"), "value": "mythic"}
    ]
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
                           string languageFilter, string colorFilter,
                           string rarityFilter, string legalityFilter)
    signal addRequested(var card, bool sideboard)

    parent: Overlay.overlay
    x: Math.round((parent.width - width) / 2)
    y: Math.round((parent.height - height) / 2)
    width: Math.min(Theme.size(960), parent.width - Theme.size(48))
    height: Math.min(Theme.size(720), parent.height - Theme.size(56))
    padding: Theme.size(24)
    modal: true
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

    Overlay.modal: Rectangle { color: "#A6050B09" }

    background: Rectangle {
        color: Theme.surfaceElevated
        radius: Theme.radiusLarge
        border.width: 1
        border.color: Theme.borderStrong
    }

    contentItem: ColumnLayout {
        spacing: Theme.size(14)

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.size(12)

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Theme.size(3)

                Text {
                    textFormat: Text.PlainText
                    Layout.fillWidth: true
                    text: qsTr("Card search")
                    color: Theme.text
                    font.pixelSize: Theme.fontSize(20)
                    font.weight: Font.DemiBold
                }

                Text {
                    textFormat: Text.PlainText
                    Layout.fillWidth: true
                    text: qsTr("Search by English or Chinese card name.")
                    color: Theme.textSecondary
                    font.pixelSize: Theme.fontSize(12)
                }
            }

            ActivityRing {
                visible: root.searching
                Layout.preferredWidth: Theme.size(18)
                Layout.preferredHeight: Theme.size(18)
            }

            Text {
                textFormat: Text.PlainText
                visible: root.hasSearchCriteria && !root.searching
                text: I18n.count("result", root.results.length)
                color: Theme.textMuted
                font.pixelSize: Theme.fontSize(11)
            }

            AppButton {
                compact: true
                variant: "ghost"
                text: "×"
                accessibleName: qsTr("Close")
                Layout.preferredWidth: Theme.size(40)
                onClicked: root.close()
            }
        }

        AppTextField {
            id: searchField
            objectName: "cardSearchField"
            Layout.fillWidth: true
            implicitHeight: Theme.size(46)
            placeholderText: qsTr("Search English or Chinese names…")
            onTextChanged: {
                if (root.opened)
                    searchTimer.restart()
            }
            onAccepted: root.searchNow()
        }

        GridLayout {
            Layout.fillWidth: true
            columns: 3
            columnSpacing: Theme.size(10)
            rowSpacing: Theme.size(8)
            enabled: root.filtersAvailable

            AppComboBox {
                id: typeFilterBox
                objectName: "cardSearchTypeFilter"
                Layout.fillWidth: true
                model: root.typeOptions
                textRole: "label"
                valueRole: "value"
                currentIndex: root.optionIndex(root.typeOptions, root.typeFilter)
                onActivated: index => root.typeFilter =
                             root.typeOptions[index].value
            }

            AppTextField {
                id: setCodeField
                objectName: "cardSearchSetFilter"
                Layout.fillWidth: true
                placeholderText: qsTr("Set code")
                maximumLength: 12
                onTextChanged: {
                    if (root.opened)
                        searchTimer.restart()
                }
                onAccepted: root.searchNow()
            }

            AppComboBox {
                id: languageFilterBox
                objectName: "cardSearchLanguageFilter"
                Layout.fillWidth: true
                model: root.languageOptions
                textRole: "label"
                valueRole: "value"
                currentIndex: root.optionIndex(root.languageOptions,
                                               root.languageFilter)
                onActivated: index => root.languageFilter =
                             root.languageOptions[index].value
            }

            AppComboBox {
                id: colorFilterBox
                objectName: "cardSearchColorFilter"
                Layout.fillWidth: true
                model: root.colorOptions
                textRole: "label"
                valueRole: "value"
                currentIndex: root.optionIndex(root.colorOptions, root.colorFilter)
                onActivated: index => root.colorFilter =
                             root.colorOptions[index].value
            }

            AppComboBox {
                id: rarityFilterBox
                objectName: "cardSearchRarityFilter"
                Layout.fillWidth: true
                model: root.rarityOptions
                textRole: "label"
                valueRole: "value"
                currentIndex: root.optionIndex(root.rarityOptions,
                                               root.rarityFilter)
                onActivated: index => root.rarityFilter =
                             root.rarityOptions[index].value
            }

            AppComboBox {
                id: legalityFilterBox
                objectName: "cardSearchLegalityFilter"
                Layout.fillWidth: true
                model: root.legalityOptions
                textRole: "label"
                valueRole: "value"
                currentIndex: root.optionIndex(root.legalityOptions,
                                               root.legalityFilter)
                onActivated: index => root.legalityFilter =
                             root.legalityOptions[index].value
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.size(10)

            Text {
                textFormat: Text.PlainText
                Layout.fillWidth: true
                text: root.filtersAvailable
                      ? qsTr("Filters narrow database results only; deck legality is not enforced.")
                      : qsTr("Update the local card database to use search filters.")
                color: Theme.textMuted
                font.pixelSize: Theme.fontSize(10)
                wrapMode: Text.WordWrap
            }

            AppButton {
                objectName: "cardSearchResetFilters"
                compact: true
                variant: "ghost"
                text: qsTr("Reset filters")
                enabled: root.filtersActive
                onClicked: root.resetFilters()
            }
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 1
            color: Theme.divider
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            ListView {
                id: resultList
                objectName: "cardSearchResults"
                anchors.fill: parent
                visible: root.hasSearchCriteria && !root.searching
                         && root.results.length > 0
                model: root.results
                spacing: Theme.size(7)
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                delegate: Surface {
                    id: searchResultDelegate
                    required property var modelData
                    property bool canIncrement: !root.deckLibraryModel
                                                || root.deckLibraryModel.canAddCard(
                                                    modelData.name,
                                                    modelData.typeLine)

                    width: ListView.view.width
                    height: Theme.size(72)
                    radius: Theme.radiusMedium
                    color: Theme.surfaceMuted

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Theme.size(14)
                        anchors.rightMargin: Theme.size(10)
                        spacing: Theme.size(12)

                        Rectangle {
                            Layout.preferredWidth: Theme.size(76)
                            Layout.preferredHeight: Theme.size(40)
                            radius: Theme.radiusSmall
                            color: Theme.surfaceElevated
                            border.width: 1
                            border.color: Theme.borderStrong

                            Column {
                                anchors.centerIn: parent
                                spacing: Theme.size(1)

                                Text {
                                    textFormat: Text.PlainText
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: searchResultDelegate.modelData.setCode
                                    color: Theme.primary
                                    font.pixelSize: Theme.fontSize(12)
                                    font.weight: Font.Bold
                                }

                                Text {
                                    textFormat: Text.PlainText
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: "#" + searchResultDelegate.modelData.collectorNumber
                                    color: Theme.textMuted
                                    font.pixelSize: Theme.fontSize(9)
                                }
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: Theme.size(3)

                            Text {
                                textFormat: Text.PlainText
                                Layout.fillWidth: true
                                text: searchResultDelegate.modelData.displayName
                                color: Theme.text
                                font.pixelSize: Theme.fontSize(14)
                                font.weight: Font.Medium
                                elide: Text.ElideRight
                            }

                            Text {
                                textFormat: Text.PlainText
                                Layout.fillWidth: true
                                text: searchResultDelegate.modelData.displayName
                                      !== searchResultDelegate.modelData.name
                                      ? searchResultDelegate.modelData.name + " · "
                                        + searchResultDelegate.modelData.typeLine
                                      : searchResultDelegate.modelData.typeLine
                                color: Theme.textMuted
                                font.pixelSize: Theme.fontSize(10)
                                elide: Text.ElideRight
                            }
                        }

                        Text {
                            textFormat: Text.PlainText
                            visible: searchResultDelegate.modelData.versionCount > 1
                            text: I18n.count("printing",
                                             searchResultDelegate.modelData.versionCount)
                            color: Theme.textMuted
                            font.pixelSize: Theme.fontSize(10)
                        }

                        AppButton {
                            compact: true
                            variant: "primary"
                            text: qsTr("+ Main")
                            Layout.preferredWidth: Theme.size(82)
                            enabled: searchResultDelegate.canIncrement
                            onClicked: root.addRequested(searchResultDelegate.modelData, false)
                        }

                        AppButton {
                            visible: root.allowSideboard
                            compact: true
                            text: qsTr("+ Side")
                            Layout.preferredWidth: Theme.size(78)
                            enabled: searchResultDelegate.canIncrement
                            onClicked: root.addRequested(searchResultDelegate.modelData, true)
                        }
                    }

                    Connections {
                        target: root.deckLibraryModel

                        function onCurrentDeckChanged() {
                            searchResultDelegate.canIncrement =
                                !root.deckLibraryModel
                                || root.deckLibraryModel.canAddCard(
                                    searchResultDelegate.modelData.name,
                                    searchResultDelegate.modelData.typeLine)
                        }
                    }
                }
            }

            Column {
                anchors.centerIn: parent
                width: Math.min(parent.width, Theme.size(440))
                spacing: Theme.size(8)
                visible: !root.hasSearchCriteria

                Text {
                    textFormat: Text.PlainText
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "⌕"
                    color: Theme.borderStrong
                    font.pixelSize: Theme.fontSize(38)
                }

                Text {
                    textFormat: Text.PlainText
                    width: parent.width
                    text: qsTr("Type a card name or choose filters to see search results.")
                    color: Theme.textSecondary
                    font.pixelSize: Theme.fontSize(13)
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                }
            }

            Column {
                anchors.centerIn: parent
                spacing: Theme.size(10)
                visible: root.searching && root.hasSearchCriteria

                ActivityRing {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: Theme.size(26)
                    height: Theme.size(26)
                }

                Text {
                    textFormat: Text.PlainText
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: qsTr("Searching cards…")
                    color: Theme.textSecondary
                    font.pixelSize: Theme.fontSize(12)
                }
            }

            Text {
                textFormat: Text.PlainText
                anchors.centerIn: parent
                visible: root.hasSearchCriteria && !root.searching
                         && root.results.length === 0
                text: qsTr("No matching cards")
                color: Theme.textMuted
                font.pixelSize: Theme.fontSize(12)
            }
        }
    }

    Timer {
        id: searchTimer
        interval: 220
        onTriggered: root.searchNow()
    }

    onTypeFilterChanged: scheduleSearch()
    onLanguageFilterChanged: scheduleSearch()
    onColorFilterChanged: scheduleSearch()
    onRarityFilterChanged: scheduleSearch()
    onLegalityFilterChanged: scheduleSearch()

    onOpened: {
        if (!filtersAvailable)
            resetFilters()
        searchField.forceActiveFocus()
        searchField.selectAll()
        searchTimer.restart()
    }

    onClosed: searchTimer.stop()

    function openSearch() {
        open()
    }

    function optionIndex(options, value) {
        for (let index = 0; index < options.length; ++index) {
            if (options[index].value === value)
                return index
        }
        return 0
    }

    function scheduleSearch() {
        if (opened)
            searchTimer.restart()
    }

    function searchNow() {
        searchTimer.stop()
        searchRequested(searchField.text.trim(), typeFilter,
                        setFilter.trim(), languageFilter, colorFilter,
                        rarityFilter, legalityFilter)
    }

    function resetFilters() {
        typeFilter = ""
        setFilter = ""
        languageFilter = ""
        colorFilter = ""
        rarityFilter = ""
        legalityFilter = ""
        scheduleSearch()
    }
}
