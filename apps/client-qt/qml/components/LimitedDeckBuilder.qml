// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

pragma ComponentBehavior: Bound
pragma Translator: "TournamentLobby"

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

Item {
    id: root

    required property var limitedModel
    required property var wsModel
    required property var cardCatalogModel
    property var selectedCards: ({})
    property int selectionRevision: 0
    property var basics: ({"Plains": 0, "Island": 0, "Swamp": 0,
                           "Mountain": 0, "Forest": 0})
    property int basicsRevision: 0
    property bool restoredSubmittedDeck: false
    property int groupingModeIndex: 0
    property int colorFilterIndex: 0
    property int typeFilterIndex: 0
    property int manaFilterIndex: 0
    property int metadataRevision: 0
    property bool basicLandsExpanded: false
    readonly property var basicNames: ["Plains", "Island", "Swamp",
                                       "Mountain", "Forest"]
    readonly property var groupingModes: ["mana", "color", "type", "name"]
    readonly property var groupingOptions: [qsTr("Mana value"), qsTr("Color"),
                                            qsTr("Card type"), qsTr("Name")]
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
    readonly property string groupingMode: groupingModes[groupingModeIndex]
    readonly property string colorFilter: colorFilterKeys[colorFilterIndex]
    readonly property string typeFilter: typeFilterKeys[typeFilterIndex]
    readonly property string manaFilter: manaFilterKeys[manaFilterIndex]
    readonly property bool filtersActive: colorFilterIndex !== 0
                                          || typeFilterIndex !== 0
                                          || manaFilterIndex !== 0
    readonly property var enrichedPool: enrichPoolCards()
    readonly property int selectedPoolCount: countSelected()
    readonly property int selectedCount: selectedPoolCount + countBasics()
    readonly property var mainDeckCards: cardsForSelection(true)
    readonly property var sideboardCards: cardsForSelection(false)
    readonly property var visibleSideboardCards: grouping.filterCards(
                                                    sideboardCards, colorFilter,
                                                    typeFilter, manaFilter)
    readonly property var mainDeckGroups: grouping.groupCards(mainDeckCards)
    readonly property var sideboardGroups: grouping.groupCards(visibleSideboardCards)
    readonly property int selectedLandCount: countSelectedLands()
    readonly property int selectedNonlandCount: selectedCount - selectedLandCount

    Component.onCompleted: {
        restoreSubmission()
        cachePoolCards()
    }

    Connections {
        target: root.limitedModel
        ignoreUnknownSignals: true
        function onSnapshotChanged() {
            root.restoreSubmission()
            root.cachePoolCards()
        }
    }

    Connections {
        target: root.cardCatalogModel
        ignoreUnknownSignals: true
        function onCatalogChanged() { root.metadataRevision++ }
    }

    LimitedCardGrouping {
        id: grouping
        mode: root.groupingMode
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: Theme.size(10)

        RowLayout {
            Layout.fillWidth: true

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Theme.size(2)
                Text {
                    textFormat: Text.PlainText
                    text: qsTr("Build your limited deck")
                    color: Theme.text
                    font.pixelSize: Theme.fontSize(18)
                    font.weight: Font.DemiBold
                }
                Text {
                    textFormat: Text.PlainText
                    text: qsTr("%1 main · %2 sideboard · unlimited basic lands")
                          .arg(root.selectedCount)
                          .arg(root.sideboardCards.length)
                    color: root.selectedCount >= 40 ? Theme.success : Theme.warning
                    font.pixelSize: Theme.fontSize(11)
                }
            }

            StatusPill {
                visible: root.limitedModel.deckSubmitted
                text: qsTr("Deck submitted")
                statusColor: Theme.success
            }

            AppButton {
                objectName: "limitedSubmitDeckButton"
                variant: "primary"
                text: root.limitedModel.deckSubmitted
                      ? qsTr("Update deck") : qsTr("Submit deck")
                enabled: root.selectedCount >= 40
                         && root.limitedModel.pool.length > 0
                onClicked: root.submit()
            }
        }

        Surface {
            id: organizationToolbar
            Layout.fillWidth: true
            implicitHeight: Theme.size(54)
            color: Theme.surfaceMuted

            RowLayout {
                anchors.fill: parent
                anchors.margins: Theme.size(7)
                spacing: Theme.size(7)

                AppComboBox {
                    id: groupingControl
                    objectName: "limitedGroupingControl"
                    Layout.preferredWidth: Theme.size(142)
                    implicitHeight: Theme.size(40)
                    model: root.groupingOptions
                    currentIndex: root.groupingModeIndex
                    displayText: qsTr("Group: %1").arg(currentText)
                    onActivated: index => root.groupingModeIndex = index
                }

                AppComboBox {
                    id: colorFilterControl
                    objectName: "limitedColorFilter"
                    Layout.preferredWidth: Theme.size(132)
                    implicitHeight: Theme.size(40)
                    model: root.colorFilterOptions
                    currentIndex: root.colorFilterIndex
                    displayText: qsTr("Color: %1").arg(currentText)
                    onActivated: index => root.colorFilterIndex = index
                }

                AppComboBox {
                    id: typeFilterControl
                    objectName: "limitedTypeFilter"
                    Layout.preferredWidth: Theme.size(148)
                    implicitHeight: Theme.size(40)
                    model: root.typeFilterOptions
                    currentIndex: root.typeFilterIndex
                    displayText: qsTr("Type: %1").arg(currentText)
                    onActivated: index => root.typeFilterIndex = index
                }

                AppComboBox {
                    id: manaFilterControl
                    objectName: "limitedManaFilter"
                    Layout.preferredWidth: Theme.size(126)
                    implicitHeight: Theme.size(40)
                    model: root.manaFilterOptions
                    currentIndex: root.manaFilterIndex
                    displayText: qsTr("Mana: %1").arg(currentText)
                    onActivated: index => root.manaFilterIndex = index
                }

                AppButton {
                    visible: root.filtersActive
                    compact: true
                    variant: "ghost"
                    text: qsTr("Clear filters")
                    onClicked: root.clearFilters()
                }

                Item { Layout.fillWidth: true }

                AppButton {
                    id: basicLandsButton
                    objectName: "limitedBasicLandsButton"
                    compact: true
                    variant: root.basicLandsExpanded ? "highlight" : "secondary"
                    text: qsTr("Basic lands · %1").arg(root.countBasics())
                    onClicked: root.basicLandsExpanded = !root.basicLandsExpanded
                }
            }
        }

        Surface {
            id: basicLandsPanel
            Layout.fillWidth: true
            visible: root.basicLandsExpanded
            implicitHeight: Theme.size(62)
            color: Theme.surfaceMuted

            RowLayout {
                anchors.fill: parent
                anchors.margins: Theme.size(9)
                spacing: Theme.size(6)

                Text {
                    textFormat: Text.PlainText
                    text: qsTr("Basic lands")
                    color: Theme.text
                    font.pixelSize: Theme.fontSize(11)
                    font.weight: Font.DemiBold
                }

                Repeater {
                    model: root.basicNames

                    delegate: Surface {
                        id: basicControl
                        required property string modelData
                        Layout.fillWidth: true
                        implicitHeight: Theme.size(48)
                        color: Theme.surfaceElevated

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: Theme.size(5)
                            spacing: Theme.size(3)
                            Text {
                                textFormat: Text.PlainText
                                Layout.fillWidth: true
                                text: root.basicLabel(basicControl.modelData) + " "
                                      + root.basicValue(basicControl.modelData)
                                color: Theme.textSecondary
                                font.pixelSize: Theme.fontSize(9)
                                elide: Text.ElideRight
                            }
                            AppButton {
                                compact: true
                                implicitWidth: Theme.size(34)
                                text: "−"
                                enabled: root.basicValue(basicControl.modelData) > 0
                                onClicked: root.adjustBasic(basicControl.modelData, -1)
                            }
                            AppButton {
                                compact: true
                                implicitWidth: Theme.size(34)
                                text: "+"
                                onClicked: root.adjustBasic(basicControl.modelData, 1)
                            }
                        }
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: Theme.size(12)

            Surface {
                id: mainDeckSurface
                objectName: "limitedMainDeckSurface"
                Layout.preferredWidth: Math.min(Theme.size(470), root.width * 0.35)
                Layout.minimumWidth: Theme.size(320)
                Layout.fillHeight: true
                color: Theme.surfaceMuted

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: Theme.size(12)
                    spacing: Theme.size(8)

                    RowLayout {
                        Layout.fillWidth: true

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: Theme.size(2)
                            Text {
                                textFormat: Text.PlainText
                                text: qsTr("Main deck")
                                color: Theme.text
                                font.pixelSize: Theme.fontSize(15)
                                font.weight: Font.DemiBold
                            }
                            Text {
                                textFormat: Text.PlainText
                                text: qsTr("%1 cards · %2 lands · %3 nonlands")
                                      .arg(root.selectedCount)
                                      .arg(root.selectedLandCount)
                                      .arg(root.selectedNonlandCount)
                                color: root.selectedCount >= 40
                                       ? Theme.success : Theme.warning
                                font.pixelSize: Theme.fontSize(9)
                            }
                        }

                        StatusPill {
                            objectName: "limitedMainDeckCount"
                            text: String(root.selectedCount)
                            statusColor: root.selectedCount >= 40
                                         ? Theme.success : Theme.warning
                        }
                    }

                    LimitedCardGroupView {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        objectName: "limitedMainDeckGrid"
                        groups: root.mainDeckGroups
                        catalogModel: root.cardCatalogModel
                        emptyText: qsTr("Add cards from the sideboard to build your deck.")
                        emphasized: true
                        actionText: "−"
                        cardWidth: Theme.size(108)
                        cardHeight: Theme.size(156)
                        onCardActivated: instanceId => root.moveToSideboard(instanceId)
                    }
                }
            }

            Surface {
                id: sideboardSurface
                objectName: "limitedSideboardSurface"
                Layout.fillWidth: true
                Layout.minimumWidth: Theme.size(480)
                Layout.fillHeight: true
                color: Theme.surfaceMuted

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: Theme.size(12)
                    spacing: Theme.size(8)

                    RowLayout {
                        Layout.fillWidth: true

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: Theme.size(2)
                            Text {
                                textFormat: Text.PlainText
                                text: qsTr("Sideboard / available pool")
                                color: Theme.text
                                font.pixelSize: Theme.fontSize(15)
                                font.weight: Font.DemiBold
                            }
                            Text {
                                textFormat: Text.PlainText
                                text: root.filtersActive
                                      ? qsTr("Showing %1 of %2 cards · filters combine")
                                        .arg(root.visibleSideboardCards.length)
                                        .arg(root.sideboardCards.length)
                                      : qsTr("Click a card to add it to the main deck")
                                color: Theme.textMuted
                                font.pixelSize: Theme.fontSize(9)
                            }
                        }

                        StatusPill {
                            objectName: "limitedSideboardCount"
                            text: root.filtersActive
                                  ? root.visibleSideboardCards.length + " / "
                                    + root.sideboardCards.length
                                  : String(root.sideboardCards.length)
                            statusColor: Theme.accent
                        }
                    }

                    LimitedCardGroupView {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        objectName: "limitedSideboardGrid"
                        groups: root.sideboardGroups
                        catalogModel: root.cardCatalogModel
                        emptyText: root.filtersActive && root.sideboardCards.length > 0
                                   ? qsTr("No cards match all active filters.")
                                   : qsTr("Every drafted card is currently in the main deck.")
                        actionText: "+"
                        cardWidth: Theme.size(128)
                        cardHeight: Theme.size(185)
                        onCardActivated: instanceId => root.moveToMainDeck(instanceId)
                    }
                }
            }
        }

        Text {
            textFormat: Text.PlainText
            Layout.fillWidth: true
            text: root.limitedModel.allDecksSubmitted
                  ? qsTr("Every deck is submitted. The organizer can publish round one.")
                  : qsTr("Waiting for all participants: %1")
                    .arg(root.submissionProgress())
            color: root.limitedModel.allDecksSubmitted
                   ? Theme.success : Theme.textMuted
            font.pixelSize: Theme.fontSize(11)
        }
    }

    function cardSelected(instanceId) {
        const revision = selectionRevision
        return !!selectedCards[instanceId] || revision < 0
    }

    function cardsForSelection(wantSelected) {
        const revision = selectionRevision
        const result = []
        for (let index = 0; index < enrichedPool.length; ++index) {
            const card = enrichedPool[index]
            if (!!selectedCards[card.instanceId] === wantSelected)
                result.push(card)
        }
        result.sort((left, right) => grouping.compareCards(left, right))
        return revision < 0 ? [] : result
    }

    function enrichPoolCards() {
        const revision = metadataRevision
        const pool = limitedModel.pool || []
        if (cardCatalogModel
                && typeof cardCatalogModel.enrichLimitedCards === "function") {
            const enriched = cardCatalogModel.enrichLimitedCards(pool)
            return revision < 0 ? [] : enriched
        }
        return revision < 0 ? [] : pool
    }

    function countSelectedLands() {
        let count = countBasics()
        for (let index = 0; index < mainDeckCards.length; ++index) {
            if (grouping.typeKey(mainDeckCards[index]) === "land")
                count++
        }
        return count
    }

    function moveToMainDeck(instanceId) {
        const changed = Object.assign({}, selectedCards)
        changed[instanceId] = true
        selectedCards = changed
        selectionRevision++
    }

    function moveToSideboard(instanceId) {
        const changed = Object.assign({}, selectedCards)
        delete changed[instanceId]
        selectedCards = changed
        selectionRevision++
    }

    function countSelected() {
        const revision = selectionRevision
        return Object.keys(selectedCards).length + (revision < 0 ? 0 : 0)
    }

    function basicValue(name) {
        const revision = basicsRevision
        return Number(basics[name] || 0) + (revision < 0 ? 0 : 0)
    }

    function countBasics() {
        let total = 0
        for (let index = 0; index < basicNames.length; ++index)
            total += basicValue(basicNames[index])
        return total
    }

    function basicLabel(name) {
        const labels = {
            "Plains": qsTr("Plains"), "Island": qsTr("Island"),
            "Swamp": qsTr("Swamp"), "Mountain": qsTr("Mountain"),
            "Forest": qsTr("Forest")
        }
        return labels[name] || name
    }

    function adjustBasic(name, amount) {
        const changed = Object.assign({}, basics)
        changed[name] = Math.max(0, Number(changed[name] || 0) + amount)
        basics = changed
        basicsRevision++
    }

    function clearFilters() {
        colorFilterIndex = 0
        typeFilterIndex = 0
        manaFilterIndex = 0
    }

    function cachePoolCards() {
        if (root.cardCatalogModel
                && typeof root.cardCatalogModel.cacheCardsIncrementally
                   === "function") {
            root.cardCatalogModel.cacheCardsIncrementally(
                        root.limitedModel.pool || [])
        }
    }

    function submit() {
        const ids = Object.keys(selectedCards)
        const lands = []
        for (let index = 0; index < basicNames.length; ++index) {
            const count = basicValue(basicNames[index])
            if (count > 0)
                lands.push({"name": basicNames[index], "count": count})
        }
        wsModel.submitLimitedDeck(qsTr("Limited deck"), ids, lands)
    }

    function submissionProgress() {
        let submitted = 0
        for (let index = 0; index < limitedModel.participants.length; ++index) {
            if (limitedModel.participants[index].deckSubmitted)
                submitted++
        }
        return submitted + " / " + limitedModel.participants.length
    }

    function restoreSubmission() {
        if (restoredSubmittedDeck || !limitedModel.deckSubmitted)
            return
        const restoredCards = {}
        for (let index = 0;
                index < limitedModel.mainboardInstanceIds.length; ++index) {
            restoredCards[limitedModel.mainboardInstanceIds[index]] = true
        }
        const restoredBasics = {"Plains": 0, "Island": 0, "Swamp": 0,
                                "Mountain": 0, "Forest": 0}
        for (let index = 0; index < limitedModel.basicLands.length; ++index) {
            const land = limitedModel.basicLands[index]
            if (restoredBasics[land.name] !== undefined)
                restoredBasics[land.name] = Number(land.count || 0)
        }
        selectedCards = restoredCards
        basics = restoredBasics
        selectionRevision++
        basicsRevision++
        restoredSubmittedDeck = true
    }
}
