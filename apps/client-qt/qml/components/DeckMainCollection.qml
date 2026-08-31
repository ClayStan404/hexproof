// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

Item {
    id: root

    required property var cards
    required property var deckLibraryModel
    required property var catalogModel
    property bool commanderFormat: false
    property bool cubeFormat: false
    property bool searchActive: false
    property Item sideboardDropTarget: null
    property int viewModeIndex: 0
    property int groupModeIndex: 0
    property int sortModeIndex: 0
    property var previewCard: null
    property string previewImageSource: ""
    property real savedListContentY: 0
    property real savedGalleryContentY: 0
    property bool scrollRestorePending: false
    readonly property var viewOptions: [qsTr("List"), qsTr("Visual")]
    readonly property var groupOptions: [qsTr("Card type"), qsTr("Mana value"), qsTr("None")]
    readonly property var sortOptions: [qsTr("Name"), qsTr("Mana value"), qsTr("Card type")]
    readonly property var groups: buildGroups()
    readonly property var flatCards: flattenGroups()
    signal printingRequested(var card)

    Connections {
        target: root.deckLibraryModel

        function onCurrentDeckCardsAboutToChange() {
            root.savedListContentY = mainList.contentY
            root.savedGalleryContentY = galleryFlick.contentY
            root.scrollRestorePending = true
        }

        function onCurrentDeckCardsChanged() {
            if (root.scrollRestorePending)
                Qt.callLater(root.restoreScrollPositions)
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: Theme.size(9)

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.size(7)

            AppComboBox {
                objectName: "deckEditorViewMode"
                Layout.preferredWidth: Theme.size(126)
                model: root.viewOptions
                currentIndex: root.viewModeIndex
                displayText: qsTr("View: %1").arg(currentText)
                onActivated: index => root.viewModeIndex = index
            }

            AppComboBox {
                objectName: "deckEditorGroupMode"
                Layout.preferredWidth: Theme.size(166)
                model: root.groupOptions
                currentIndex: root.groupModeIndex
                displayText: qsTr("Group: %1").arg(currentText)
                onActivated: index => root.groupModeIndex = index
            }

            AppComboBox {
                objectName: "deckEditorSortMode"
                Layout.preferredWidth: Theme.size(166)
                model: root.sortOptions
                currentIndex: root.sortModeIndex
                displayText: qsTr("Sort: %1").arg(currentText)
                onActivated: index => root.sortModeIndex = index
            }

            Item { Layout.fillWidth: true }

            Text {
                textFormat: Text.PlainText
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
                    model: root.flatCards
                    spacing: Theme.size(7)
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    section.property: "groupKey"
                    section.criteria: ViewSection.FullString
                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

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
                        catalogModel: root.catalogModel
                        incrementEnabled: root.deckLibraryModel.canAddCard(
                                              modelData.name, modelData.typeLine)
                        dropTarget: root.sideboardDropTarget
                        onMoveRequested: root.deckLibraryModel.moveCard(modelData.name, true)
                        onConsiderRequested: root.deckLibraryModel.moveCardToConsider(
                                                 modelData.name, modelData.setCode,
                                                 modelData.collectorNumber)
                        onIncrementRequested: root.deckLibraryModel.changeCardCount(
                                                  modelData.name, false, 1)
                        onDecrementRequested: root.deckLibraryModel.changeCardCount(
                                                  modelData.name, false, -1)
                        onCommanderRequested: root.deckLibraryModel.setCommander(modelData.name)
                        onPrintingRequested: root.printingRequested(modelData)
                    }
                }

                Text {
                    textFormat: Text.PlainText
                    anchors.centerIn: parent
                    visible: root.cards.length === 0
                    text: root.searchActive
                          ? qsTr("No cards match this deck search.")
                          : qsTr("Add cards from search or move them back from the sideboard or Consider.")
                    color: Theme.textMuted
                    font.pixelSize: Theme.fontSize(12)
                }
            }

            RowLayout {
                spacing: Theme.size(14)

                Surface {
                    Layout.preferredWidth: Theme.size(238)
                    Layout.fillHeight: true
                    visible: root.width >= Theme.size(760)
                    color: Theme.surfaceMuted

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: Theme.size(10)
                        spacing: Theme.size(8)

                        Image {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            source: root.effectivePreviewImage()
                            fillMode: Image.PreserveAspectFit
                            asynchronous: true
                            smooth: true
                            mipmap: false
                        }

                        Text {
                            textFormat: Text.PlainText
                            Layout.fillWidth: true
                            text: root.effectivePreviewCard()
                                  ? root.effectivePreviewCard().displayName : ""
                            color: Theme.text
                            font.pixelSize: Theme.fontSize(13)
                            font.weight: Font.DemiBold
                            horizontalAlignment: Text.AlignHCenter
                            elide: Text.ElideRight
                        }

                        Text {
                            textFormat: Text.PlainText
                            Layout.fillWidth: true
                            text: root.effectivePreviewCard()
                                  ? root.effectivePreviewCard().typeLine : ""
                            color: Theme.textMuted
                            font.pixelSize: Theme.fontSize(10)
                            horizontalAlignment: Text.AlignHCenter
                            elide: Text.ElideRight
                        }
                    }
                }

                Flickable {
                    id: galleryFlick
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    contentWidth: width
                    contentHeight: galleryColumn.height
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                    Column {
                        id: galleryColumn
                        width: galleryFlick.width
                        spacing: Theme.size(13)

                        Repeater {
                            model: root.groups

                            delegate: Column {
                                id: visualGroup
                                required property var modelData
                                width: galleryColumn.width
                                spacing: Theme.size(7)

                                Text {
                                    textFormat: Text.PlainText
                                    width: parent.width
                                    text: visualGroup.modelData.label.toUpperCase()
                                    color: Theme.primary
                                    font.pixelSize: Theme.fontSize(11)
                                    font.weight: Font.Bold
                                    font.letterSpacing: 0.8
                                }

                                Flow {
                                    width: visualGroup.width
                                    height: childrenRect.height
                                    spacing: Theme.size(8)

                                    Repeater {
                                        model: visualGroup.modelData.cards

                                        delegate: DeckVisualCard {
                                            required property var modelData
                                            width: Theme.size(184)
                                            height: Theme.size(284)
                                            card: modelData
                                            catalogModel: root.catalogModel
                                            incrementEnabled: root.deckLibraryModel.canAddCard(
                                                                  modelData.name,
                                                                  modelData.typeLine)
                                            commanderEnabled: root.commanderFormat
                                            printingEnabled: root.catalogModel.installed
                                            considerEnabled: true
                                            moveText: !root.commanderFormat && !root.cubeFormat
                                                      ? qsTr("To side") : ""
                                            onPreviewRequested: (card, source) => {
                                                root.previewCard = card
                                                root.previewImageSource = source
                                            }
                                            onMoveRequested: root.deckLibraryModel.moveCard(
                                                                 modelData.name, true)
                                            onConsiderRequested: root.deckLibraryModel.moveCardToConsider(
                                                                     modelData.name,
                                                                     modelData.setCode,
                                                                     modelData.collectorNumber)
                                            onIncrementRequested: root.deckLibraryModel.changeCardCount(
                                                                      modelData.name, false, 1)
                                            onDecrementRequested: root.deckLibraryModel.changeCardCount(
                                                                      modelData.name, false, -1)
                                            onCommanderRequested: root.deckLibraryModel.setCommander(
                                                                      modelData.name)
                                            onPrintingRequested: root.printingRequested(modelData)
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

    function copyCount(cards) {
        let total = 0
        for (let index = 0; index < cards.length; ++index)
            total += Number(cards[index].count || 0)
        return total
    }

    function editorCategory(card) {
        const typeLine = String(card && card.typeLine || "").toLocaleLowerCase()
        const frontType = typeLine.split(" // ")[0]
        if (frontType.includes("land") || frontType.includes("地"))
            return "Lands"
        if (frontType.includes("creature") || frontType.includes("生物"))
            return "Creatures"
        if (frontType.includes("planeswalker") || frontType.includes("鹏洛客")
                || frontType.includes("旅法师"))
            return "Planeswalkers"
        if (frontType.includes("battle") || frontType.includes("战役"))
            return "Battles"
        if (frontType.includes("artifact") || frontType.includes("神器"))
            return "Artifacts"
        if (frontType.includes("enchantment") || frontType.includes("结界"))
            return "Enchantments"
        if (frontType.includes("instant") || frontType.includes("瞬间"))
            return "Instants"
        if (frontType.includes("sorcery") || frontType.includes("法术"))
            return "Sorceries"
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
            const groupCards = byKey[key].slice()
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

    function restoreScrollPositions() {
        const listMaximum = Math.max(mainList.originY,
                                     mainList.originY + mainList.contentHeight
                                     - mainList.height)
        mainList.contentY = Math.max(mainList.originY,
                                     Math.min(savedListContentY, listMaximum))
        const galleryMaximum = Math.max(0, galleryFlick.contentHeight - galleryFlick.height)
        galleryFlick.contentY = Math.max(0,
                                        Math.min(savedGalleryContentY, galleryMaximum))
        scrollRestorePending = false
    }
}
