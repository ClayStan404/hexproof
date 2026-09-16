// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import "CardTypes.js" as CardTypes

Item {
    id: root

    required property var cards
    required property var deckLibraryModel
    required property var catalogModel
    property bool commanderFormat: false
    property bool cubeFormat: false
    property bool customArtEnabled: false
    property bool searchActive: false
    property Item sideboardDropTarget: null
    property Flickable outerFlickable: null
    property int viewModeIndex: 1
    property int groupModeIndex: 0
    property int sortModeIndex: 0
    property var previewCard: null
    property string previewImageSource: ""
    property var savedListPosition: ({index: -1, offset: 0, atEnd: false})
    property var savedGalleryPosition: ({index: -1, offset: 0, atEnd: false})
    property bool scrollRestorePending: false
    readonly property var viewOptions: [qsTr("List"), qsTr("Visual")]
    readonly property var groupOptions: [qsTr("Card type"), qsTr("Mana value"), qsTr("None")]
    readonly property var sortOptions: [qsTr("Name"), qsTr("Mana value"), qsTr("Card type")]
    readonly property var groups: buildGroups()
    readonly property var flatCards: viewModeIndex === 0 ? flattenGroups() : []
    signal printingRequested(var card)
    signal customArtRequested(var card)

    CardHoverPreview {
        id: floatingPreview
        catalogModel: root.catalogModel
    }
    onVisibleChanged: if (!visible) floatingPreview.hide()

    Connections {
        target: root.deckLibraryModel

        function onCurrentDeckCardsAboutToChange() {
            floatingPreview.hide()
            if (root.scrollRestorePending)
                return
            root.saveVisibleScrollPosition()
            root.scrollRestorePending = true
        }

        function onCurrentDeckCardsChanged() {
            if (root.scrollRestorePending)
                Qt.callLater(root.restoreScrollPositions)
        }
    }

    Component {
        id: groupedGalleryComponent

        ListView {
            id: groupedDeckGallery
            objectName: "groupedDeckGallery"
            readonly property int columns: Math.max(1, Math.floor(
                (width + Theme.size(8)) / Theme.size(192)))
            readonly property var rows: root.galleryRows(columns)
            model: rows.length
            spacing: Theme.size(8)
            cacheBuffer: Theme.size(388)
            reuseItems: true
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
            ScrollChainHandler {
                enabled: root.outerFlickable !== null
                innerFlickable: groupedDeckGallery
                outerFlickable: root.outerFlickable
            }

            delegate: Column {
                id: visualRow
                required property int index
                readonly property var row: groupedDeckGallery.rows[index] || ({cards: [], heading: false})
                width: groupedDeckGallery.width
                height: Theme.size(380) + (row.heading ? Theme.size(32) : 0)

                Item {
                    width: parent.width
                    height: Theme.size(32)
                    visible: visualRow.row.heading

                    Text {
                        textFormat: Text.PlainText
                        anchors.left: parent.left
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: Theme.size(7)
                        text: visualRow.row.heading ? root.groupTitle(visualRow.row.groupKey).toUpperCase() : ""
                        color: Theme.primary
                        font.pixelSize: Theme.fontSize(11)
                        font.weight: Font.Bold
                        font.letterSpacing: 0.8
                    }
                }

                Row {
                    spacing: Theme.size(8)

                    Repeater {
                        model: visualRow.row.cards.length

                        DeckVisualCard {
                            id: visualCard
                            required property int index
                            readonly property var modelData: visualRow.row.cards[index]
                                || ({name: "", displayName: "", count: 0, typeLine: "",
                                     setCode: "", collectorNumber: ""})
                            width: Theme.size(184)
                            height: Theme.size(380)
                            card: modelData
                            catalogModel: root.catalogModel
                            incrementEnabled: modelData.name.length > 0
                                && root.deckLibraryModel.canAddCard(modelData.name, modelData.typeLine)
                            commanderEnabled: root.commanderFormat
                            printingEnabled: root.catalogModel.installed
                            customArtEnabled: root.customArtEnabled
                            considerEnabled: true
                            moveText: !root.commanderFormat && !root.cubeFormat ? qsTr("To side") : ""
                            onPreviewRequested: (card, source) => {
                                root.previewCard = card
                                root.previewImageSource = source
                                floatingPreview.inspect(card, visualCard)
                            }
                            onPreviewEnded: floatingPreview.hide(visualCard)
                            onMoveRequested: root.deckLibraryModel.moveCard(
                                                 modelData.name, modelData.setCode,
                                                 modelData.collectorNumber, true)
                            onConsiderRequested: root.deckLibraryModel.moveCardToConsider(
                                                     modelData.name, modelData.setCode,
                                                     modelData.collectorNumber)
                            onIncrementRequested: root.deckLibraryModel.changeCardCount(
                                                      modelData.name, modelData.setCode,
                                                      modelData.collectorNumber, false, 1)
                            onDecrementRequested: root.deckLibraryModel.changeCardCount(
                                                      modelData.name, modelData.setCode,
                                                      modelData.collectorNumber, false, -1)
                            onCommanderRequested: root.deckLibraryModel.setCommander(modelData.name)
                            onPrintingRequested: root.printingRequested(modelData)
                            onCustomArtRequested: root.customArtRequested(modelData)
                        }
                    }
                }
            }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: Theme.size(9)

        GridLayout {
            id: collectionOptions
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            columns: width >= Theme.size(480) ? 3 : (width >= Theme.size(280) ? 2 : 1)
            columnSpacing: Theme.size(7)
            rowSpacing: Theme.size(7)

            AppComboBox {
                objectName: "deckEditorViewMode"
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                Layout.preferredWidth: Theme.size(126)
                model: root.viewOptions
                currentIndex: root.viewModeIndex
                displayText: qsTr("View: %1").arg(currentText)
                onActivated: index => root.switchView(index)
            }

            AppComboBox {
                objectName: "deckEditorGroupMode"
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                Layout.preferredWidth: Theme.size(166)
                model: root.groupOptions
                currentIndex: root.groupModeIndex
                displayText: qsTr("Group: %1").arg(currentText)
                onActivated: index => root.groupModeIndex = index
            }

            AppComboBox {
                objectName: "deckEditorSortMode"
                Layout.fillWidth: true
                Layout.columnSpan: collectionOptions.columns === 2 ? 2 : 1
                Layout.minimumWidth: 0
                Layout.preferredWidth: Theme.size(166)
                model: root.sortOptions
                currentIndex: root.sortModeIndex
                displayText: qsTr("Sort: %1").arg(currentText)
                onActivated: index => root.sortModeIndex = index
            }

            Text {
                textFormat: Text.PlainText
                Layout.columnSpan: collectionOptions.columns
                Layout.fillWidth: true
                visible: root.width >= Theme.size(720)
                text: qsTr("%1 categories · %2 cards")
                      .arg(root.groups.length)
                      .arg(root.copyCount(root.cards))
                color: Theme.textMuted
                font.pixelSize: Theme.fontSize(10)
            }
        }

        StackLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            currentIndex: root.viewModeIndex

            Item {
                ListView {
                    id: mainList
                    objectName: "mainDeckList"
                    anchors.fill: parent
                    model: root.viewModeIndex === 0 ? root.flatCards : []
                    reuseItems: true
                    cacheBuffer: Theme.size(100)
                    spacing: Theme.size(7)
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    section.property: "groupKey"
                    section.criteria: ViewSection.FullString
                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                    ScrollChainHandler {
                        enabled: root.outerFlickable !== null
                        innerFlickable: mainList
                        outerFlickable: root.outerFlickable
                    }

                    section.delegate: Item {
                        required property string section
                        width: mainList.width
                        height: Theme.size(34)

                        Text {
                            textFormat: Text.PlainText
                            anchors.left: parent.left
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: Theme.size(7)
                            text: root.groupTitle(parent.section).toUpperCase()
                            color: Theme.primary
                            font.pixelSize: Theme.fontSize(10)
                            font.weight: Font.Bold
                            font.letterSpacing: 1.1
                        }
                    }

                    delegate: DeckCardRow {
                        required property var modelData
                        width: mainList.width
                        card: modelData
                        sideboard: false
                        sideboardEnabled: !root.commanderFormat && !root.cubeFormat
                        considerEnabled: true
                        commanderEnabled: root.commanderFormat
                        printingEnabled: root.catalogModel.installed
                        customArtEnabled: root.customArtEnabled
                        catalogModel: root.catalogModel
                        incrementEnabled: root.deckLibraryModel.canAddCard(
                                              modelData.name, modelData.typeLine)
                        dropTarget: root.sideboardDropTarget
                        onMoveRequested: root.deckLibraryModel.moveCard(
                                             modelData.name, modelData.setCode,
                                             modelData.collectorNumber, true)
                        onConsiderRequested: root.deckLibraryModel.moveCardToConsider(
                                                 modelData.name, modelData.setCode,
                                                 modelData.collectorNumber)
                        onIncrementRequested: root.deckLibraryModel.changeCardCount(
                                                  modelData.name, modelData.setCode,
                                                  modelData.collectorNumber, false, 1)
                        onDecrementRequested: root.deckLibraryModel.changeCardCount(
                                                  modelData.name, modelData.setCode,
                                                  modelData.collectorNumber, false, -1)
                        onCommanderRequested: root.deckLibraryModel.setCommander(modelData.name)
                        onPrintingRequested: root.printingRequested(modelData)
                        onCustomArtRequested: root.customArtRequested(modelData)
                    }
                }

                Text {
                    textFormat: Text.PlainText
                    anchors.centerIn: parent
                    visible: root.cards.length === 0
                    width: parent.width - Theme.size(24)
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    text: root.searchActive
                          ? qsTr("No cards match this deck search.")
                          : qsTr("Add cards from search or move them back from the sideboard or Consider.")
                    color: Theme.textMuted
                    font.pixelSize: Theme.fontSize(12)
                }
            }

            RowLayout {
                spacing: Theme.size(14)

                Loader {
                    id: galleryLoader
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    active: root.viewModeIndex === 1
                    sourceComponent: groupedGalleryComponent
                }
            }
        }
    }

    function copyCount(cards) {
        let total = 0
        for (let index = 0; index < cards.length; ++index)
            total += Number(cards[index].count || 0)
        return total
    }

    function editorCategory(card) {
        const categories = {Land: "Lands", Creature: "Creatures", Planeswalker: "Planeswalkers",
            Battle: "Battles", Artifact: "Artifacts", Enchantment: "Enchantments",
            Instant: "Instants", Sorcery: "Sorceries"}
        for (const type of Object.keys(categories))
            if (CardTypes.hasType(card || {}, type)) return categories[type]
        return "Other"
    }

    function typeRank(category) {
        const order = ["Creatures", "Planeswalkers", "Battles", "Artifacts",
                       "Enchantments", "Instants", "Sorceries", "Lands", "Other"]
        const index = order.indexOf(category)
        return index < 0 ? order.length : index
    }

    function manaRank(card) {
        if (!card || Number(card.manaValue) < 0)
            return 1000
        return Number(card.manaValue)
    }

    function compareCards(left, right) {
        if (sortModeIndex === 1) {
            const manaDifference = manaRank(left) - manaRank(right)
            if (manaDifference !== 0)
                return manaDifference
        } else if (sortModeIndex === 2) {
            const typeDifference = typeRank(editorCategory(left)) - typeRank(editorCategory(right))
            if (typeDifference !== 0)
                return typeDifference
        }
        return String(left.displayName || left.name)
               .localeCompare(String(right.displayName || right.name))
    }

    function groupKey(card) {
        if (groupModeIndex === 0)
            return editorCategory(card)
        if (groupModeIndex === 1) {
            if (editorCategory(card) === "Lands")
                return "mana-land"
            const mana = manaRank(card)
            if (mana >= 1000)
                return "mana-unknown"
            if (mana >= 7)
                return "mana-7+"
            return "mana-" + Math.floor(mana)
        }
        return "all"
    }

    function groupLabel(key) {
        if (key === "all")
            return qsTr("All cards")
        if (key === "mana-land")
            return qsTr("Lands")
        if (key === "mana-unknown")
            return qsTr("Mana value unknown")
        if (key.indexOf("mana-") === 0)
            return qsTr("Mana value %1").arg(key.substring(5))
        switch (key) {
        case "Instants":
            return qsTr("Instants")
        case "Sorceries":
            return qsTr("Sorceries")
        case "Battles":
            return qsTr("Battles")
        default:
            return I18n.cardCategory(key)
        }
    }

    function groupRank(key) {
        if (groupModeIndex === 0)
            return typeRank(key)
        if (groupModeIndex === 1) {
            if (key === "mana-land")
                return 8
            if (key === "mana-unknown")
                return 9
            const value = key.substring(5)
            return value === "7+" ? 7 : Number(value)
        }
        return 0
    }

    function buildGroups() {
        const byKey = ({})
        for (let index = 0; index < cards.length; ++index) {
            const card = cards[index]
            const key = groupKey(card)
            if (!byKey[key])
                byKey[key] = []
            byKey[key].push(card)
        }
        const keys = Object.keys(byKey)
        keys.sort((left, right) => groupRank(left) - groupRank(right))
        const result = []
        for (let index = 0; index < keys.length; ++index) {
            const key = keys[index]
            const groupCards = byKey[key]
            groupCards.sort((left, right) => compareCards(left, right))
            result.push({"key": key,
                         "label": groupLabel(key) + " (" + copyCount(groupCards) + ")",
                         "cards": groupCards})
        }
        return result
    }

    function flattenGroups() {
        const result = []
        for (let groupIndex = 0; groupIndex < groups.length; ++groupIndex) {
            const group = groups[groupIndex]
            for (let cardIndex = 0; cardIndex < group.cards.length; ++cardIndex) {
                const source = group.cards[cardIndex]
                const card = ({})
                for (const key in source)
                    card[key] = source[key]
                card.groupKey = group.key
                result.push(card)
            }
        }
        return result
    }

    function galleryRows(columns) {
        const rows = []
        for (const group of groups) {
            for (let index = 0; index < group.cards.length; index += columns)
                rows.push({groupKey: group.key, heading: index === 0,
                           cards: group.cards.slice(index, index + columns)})
        }
        return rows
    }

    function groupTitle(key) {
        for (let index = 0; index < groups.length; ++index) {
            if (groups[index].key === key)
                return groups[index].label
        }
        return groupLabel(key)
    }

    function effectivePreviewCard() {
        if (previewCard)
            return previewCard
        return flatCards.length > 0 ? flatCards[0] : null
    }

    function effectivePreviewImage() {
        if (previewCard && previewImageSource.length > 0)
            return previewImageSource
        const card = effectivePreviewCard()
        if (!card)
            return ""
        if (card.imageSource)
            return card.imageSource
        if (!catalogModel || typeof catalogModel.imageSource !== "function")
            return ""
        if (typeof catalogModel.imageRevision !== "undefined")
            void catalogModel.imageRevision
        return catalogModel.imageSource(card.name || "", card.setCode || "",
                                        card.collectorNumber || "")
    }

    function captureScrollPosition(view) {
        let index = -1
        for (let y = 1; view.count > 0 && y < view.height; y += Theme.size(8)) {
            index = view.indexAt(1, view.contentY + y)
            if (index >= 0)
                break
        }
        const item = index >= 0 ? view.itemAtIndex(index) : null
        return {index: index, offset: item ? view.contentY - item.y : 0,
                atEnd: view.atYEnd && !view.atYBeginning}
    }

    function saveVisibleScrollPosition() {
        if (viewModeIndex === 0) {
            savedListPosition = captureScrollPosition(mainList)
        } else {
            const gallery = galleryLoader.item as ListView
            if (gallery)
                savedGalleryPosition = captureScrollPosition(gallery)
        }
    }

    function switchView(index) {
        if (index === viewModeIndex)
            return
        saveVisibleScrollPosition()
        viewModeIndex = index
        Qt.callLater(root.restoreScrollPositions)
    }

    function restoreScrollPosition(view, position) {
        view.forceLayout()
        if (position.atEnd) {
            view.positionViewAtEnd()
        } else if (position.index >= 0 && view.count > 0) {
            const index = Math.min(position.index, view.count - 1)
            view.positionViewAtIndex(index, ListView.Beginning)
            const item = view.itemAtIndex(index)
            if (item) {
                const maximum = Math.max(view.originY,
                    view.originY + view.contentHeight - view.height)
                view.contentY = Math.max(view.originY,
                    Math.min(item.y + position.offset, maximum))
            }
        } else {
            view.positionViewAtBeginning()
        }
    }

    function restoreScrollPositions() {
        if (viewModeIndex === 0) {
            restoreScrollPosition(mainList, savedListPosition)
        } else {
            const gallery = galleryLoader.item as ListView
            if (gallery)
                restoreScrollPosition(gallery, savedGalleryPosition)
        }
        scrollRestorePending = false
    }
}
