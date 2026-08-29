// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic
import QtTest
import "../../qml/components"

TestCase {
    id: testCase
    name: "LimitedViews"
    when: windowShown

    readonly property var seats: [
        {"participantId": "p1", "displayName": "Alice"},
        {"participantId": "p2", "displayName": "Bob"},
        {"participantId": "p3", "displayName": "Carol"},
        {"participantId": "p4", "displayName": "Dan"}
    ]

    ApplicationWindow {
        width: 1200
        height: 800
        visible: true

        QtObject {
            id: mockCatalog
            property int imageRevision: 0
            function tableImageSource(name, setCode, collectorNumber) { return "" }
            function cacheCardsIncrementally(cards) {}
            function enrichLimitedCards(cards) {
                const enriched = []
                for (let index = 0; index < cards.length; ++index) {
                    const card = Object.assign({}, cards[index])
                    card.limitedMetadataResolved = true
                    card.manaValue = card.instanceId === "card-1" ? 0 : 3
                    card.colors = card.instanceId === "card-1" ? "U" : "GU"
                    enriched.push(card)
                }
                return enriched
            }
        }

        QtObject {
            id: mockLimited
            property var pool: [
                {"instanceId": "card-1", "name": "Island",
                 "setCode": "TST", "collectorNumber": "1",
                 "typeLine": "Basic Land — Island"},
                {"instanceId": "card-2", "name": "Test Creature",
                 "setCode": "TST", "collectorNumber": "2",
                 "typeLine": "Creature — Test"}
            ]
            property var participants: testCase.seats
            property bool deckSubmitted: false
            property bool allDecksSubmitted: false
            property var mainboardInstanceIds: []
            property var basicLands: []
        }

        QtObject {
            id: mockWs
            property var submittedIds: []
            function submitLimitedDeck(name, ids, lands) { submittedIds = ids }
        }

        LimitedDraftSeatMap {
            id: seatMap
            width: 520
            participants: testCase.seats
            participantId: "p3"
            direction: 1
        }

        LimitedDeckBuilder {
            id: deckBuilder
            anchors.fill: parent
            visible: false
            limitedModel: mockLimited
            wsModel: mockWs
            cardCatalogModel: mockCatalog
        }
    }

    function init() {
        seatMap.direction = 1
        deckBuilder.selectedCards = ({})
        deckBuilder.selectionRevision++
        deckBuilder.basics = ({"Plains": 0, "Island": 0, "Swamp": 0,
                               "Mountain": 0, "Forest": 0})
        deckBuilder.basicsRevision++
        deckBuilder.groupingModeIndex = 0
        deckBuilder.clearFilters()
        deckBuilder.basicLandsExpanded = false
    }

    function test_seatMapUsesViewerRelativePhysicalOrder() {
        compare(seatMap.selfIndex, 2)
        compare(seatMap.viewerRelativeSeats.length, 4)
        compare(seatMap.viewerRelativeSeats[0].participantId, "p3")
        compare(seatMap.viewerRelativeSeats[0].seatNumber, 3)
        verify(seatMap.viewerRelativeSeats[0].isSelf)
        compare(seatMap.outgoingName, "Dan")
        compare(seatMap.incomingName, "Bob")

        seatMap.direction = -1
        compare(seatMap.outgoingName, "Bob")
        compare(seatMap.incomingName, "Dan")
    }

    function test_deckBuilderMovesVisibleCardsBetweenAreas() {
        compare(deckBuilder.mainDeckCards.length, 0)
        compare(deckBuilder.sideboardCards.length, 2)

        deckBuilder.moveToMainDeck("card-1")
        compare(deckBuilder.mainDeckCards.length, 1)
        compare(deckBuilder.mainDeckCards[0].instanceId, "card-1")
        compare(deckBuilder.sideboardCards.length, 1)

        deckBuilder.adjustBasic("Island", 2)
        compare(deckBuilder.selectedCount, 3)

        deckBuilder.moveToSideboard("card-1")
        compare(deckBuilder.mainDeckCards.length, 0)
        compare(deckBuilder.sideboardCards.length, 2)
    }

    function test_deckBuilderGroupsByManaColorTypeAndName() {
        compare(deckBuilder.sideboardGroups.length, 2)
        compare(deckBuilder.sideboardGroups[0].key, "3")
        compare(deckBuilder.sideboardGroups[1].key, "land")

        deckBuilder.groupingModeIndex = 1
        compare(deckBuilder.sideboardGroups.length, 2)
        compare(deckBuilder.sideboardGroups[0].key, "multicolor")
        compare(deckBuilder.sideboardGroups[1].key, "land")

        deckBuilder.groupingModeIndex = 2
        compare(deckBuilder.sideboardGroups[0].key, "creature")
        compare(deckBuilder.sideboardGroups[1].key, "land")

        deckBuilder.groupingModeIndex = 3
        compare(deckBuilder.sideboardGroups.length, 1)
        compare(deckBuilder.sideboardGroups[0].key, "all")
        compare(deckBuilder.sideboardGroups[0].cards[0].name, "Island")
    }

    function test_deckBuilderCombinesPoolFilters() {
        deckBuilder.colorFilterIndex = 6
        deckBuilder.typeFilterIndex = 1
        deckBuilder.manaFilterIndex = 4
        compare(deckBuilder.visibleSideboardCards.length, 1)
        compare(deckBuilder.visibleSideboardCards[0].instanceId, "card-2")

        deckBuilder.manaFilterIndex = 3
        compare(deckBuilder.visibleSideboardCards.length, 0)

        deckBuilder.clearFilters()
        compare(deckBuilder.visibleSideboardCards.length, 2)
        verify(!deckBuilder.filtersActive)
    }
}
