// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
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
    readonly property var twoSeats: [
        {"participantId": "p1", "displayName": "Alice"},
        {"participantId": "p2", "displayName": "Bob"}
    ]

    ApplicationWindow {
        width: 1200
        height: 800
        visible: true

        QtObject {
            id: mockCatalog
            property int imageRevision: 0
            function tableImageSource(name, setCode, collectorNumber) { return "" }
            function imageSource(name, setCode, collectorNumber) {
                return "file:///tmp/limited-preview.png"
            }
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
            signal snapshotChanged()
            property int packRound: 1
            property int direction: 1
            property var currentPack: pool
            property var pool: [
                {"instanceId": "card-1", "name": "Island",
                 "setCode": "TST", "collectorNumber": "1",
                 "typeLine": "Basic Land — Island", "rarity": "common"},
                {"instanceId": "card-2", "name": "Test Creature",
                 "setCode": "TST", "collectorNumber": "2",
                 "typeLine": "Creature — Test", "rarity": "mythic"}
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
            property string pickedId: ""
            function submitLimitedDeck(name, ids, lands) { submittedIds = ids }
            function pickLimitedCard(instanceId) { pickedId = instanceId }
        }

        QtObject {
            id: mockTournament
            property string participantId: "p1"
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

        LimitedDraftView {
            id: draftView
            anchors.fill: parent
            visible: false
            limitedModel: mockLimited
            tournamentModel: mockTournament
            wsModel: mockWs
            cardCatalogModel: mockCatalog
        }

        // Mirrors TournamentLobby: the draft view lives in a ColumnLayout
        // and flips from hidden to visible when the draft stage starts.
        Item {
            id: squeezeHost
            width: 300
            height: 640

            ColumnLayout {
                anchors.fill: parent

                LimitedDraftView {
                    id: squeezedDraftView
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    visible: false
                    limitedModel: mockLimited
                    tournamentModel: mockTournament
                    wsModel: mockWs
                    cardCatalogModel: mockCatalog
                }
            }
        }

        // Wide variant of the same hidden-to-visible flip: the pack column
        // must take the fill space, not just survive at its minimum width.
        Item {
            id: wideHost
            width: 1200
            height: 800

            ColumnLayout {
                anchors.fill: parent

                LimitedDraftView {
                    id: revealedDraftView
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    visible: false
                    limitedModel: mockLimited
                    tournamentModel: mockTournament
                    wsModel: mockWs
                    cardCatalogModel: mockCatalog
                }
            }
        }
    }

    function init() {
        seatMap.direction = 1
        seatMap.participants = testCase.seats
        seatMap.participantId = "p3"
        mockLimited.participants = testCase.seats
        deckBuilder.selectedCards = ({})
        deckBuilder.selectionRevision++
        deckBuilder.basics = ({"Plains": 0, "Island": 0, "Swamp": 0,
                               "Mountain": 0, "Forest": 0})
        deckBuilder.basicsRevision++
        deckBuilder.groupingModeIndex = 0
        deckBuilder.clearFilters()
        deckBuilder.basicLandsExpanded = false
        deckBuilder.hoverPreviewVisible = false
        draftView.pickedRarityFilterIndex = 0
        draftView.hoverPreviewVisible = false
        draftView.visible = false
        squeezeHost.width = 300
        squeezedDraftView.visible = false
        revealedDraftView.visible = false
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

    function test_seatMapTwoPlayerDraftHidesPassDirection() {
        const pill = findChild(seatMap, "draftDirectionPill")
        verify(pill)
        compare(pill.text, "Pass left · clockwise")

        seatMap.participants = testCase.twoSeats
        seatMap.participantId = "p1"
        verify(seatMap.twoPlayer)
        compare(pill.text, "Two-player draft")
        // Both neighbors resolve to the same opponent in a two-seat draft.
        compare(seatMap.outgoingName, "Bob")
        compare(seatMap.incomingName, "Bob")

        seatMap.direction = -1
        compare(pill.text, "Two-player draft")
    }

    function test_draftViewTwoPlayerHeaderOmitsDirection() {
        const header = findChild(draftView, "limitedDraftPackHeader")
        verify(header)
        verify(!draftView.twoPlayer)
        compare(header.text, "Draft pack 1 · pass left")

        mockLimited.participants = testCase.twoSeats
        verify(draftView.twoPlayer)
        compare(header.text, "Draft pack 1")
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
        deckBuilder.rarityFilterIndex = 4
        compare(deckBuilder.visibleSideboardCards.length, 1)
        compare(deckBuilder.visibleSideboardCards[0].instanceId, "card-2")

        deckBuilder.manaFilterIndex = 3
        compare(deckBuilder.visibleSideboardCards.length, 0)

        deckBuilder.clearFilters()
        compare(deckBuilder.visibleSideboardCards.length, 2)
        verify(!deckBuilder.filtersActive)
    }

    function test_deckBuilderShowsRarityAndFullCardPreview() {
        deckBuilder.rarityFilterIndex = 1
        compare(deckBuilder.visibleSideboardCards.length, 1)
        compare(deckBuilder.visibleSideboardCards[0].rarity, "common")

        deckBuilder.clearFilters()
        deckBuilder.visible = true
        wait(0)
        const tile = findChild(deckBuilder, "limitedCardTile-card-2")
        verify(tile)
        compare(tile.rarityCode(), "M")
        compare(tile.rarityLabel(), "Mythic rare")

        deckBuilder.inspectCard(deckBuilder.sideboardCards[1], tile)
        verify(deckBuilder.hoverPreviewVisible)
        const preview = findChild(deckBuilder, "limitedCardHoverPreview")
        const previewArt = findChild(deckBuilder, "limitedCardHoverPreviewArt")
        verify(preview)
        verify(previewArt)
        verify(preview.visible)
        compare(previewArt.source.toString(), "file:///tmp/limited-preview.png")
        deckBuilder.hideCardPreview()
        verify(!deckBuilder.hoverPreviewVisible)
        deckBuilder.visible = false
    }

    function test_draftViewFiltersPicksAndPreviewsBothAreas() {
        draftView.pickedRarityFilterIndex = 4
        compare(draftView.visiblePickedCards.length, 1)
        compare(draftView.visiblePickedCards[0].instanceId, "card-2")
        compare(mockLimited.currentPack.length, 2)

        draftView.visible = true
        wait(0)
        const packCard = findChild(draftView, "limitedDraftPackCard-card-1")
        const pickedCard = findChild(
                               draftView,
                               "limitedDraftPickedCard-card-2")
        const preview = findChild(
                            draftView,
                            "limitedDraftCardHoverPreview")
        const previewArt = findChild(
                               draftView,
                               "limitedDraftCardHoverPreviewArt")
        verify(packCard)
        verify(pickedCard)
        verify(preview)
        verify(previewArt)

        draftView.inspectCard(mockLimited.currentPack[0], packCard)
        verify(preview.visible)
        compare(draftView.inspectedCard.instanceId, "card-1")
        compare(previewArt.source.toString(), "file:///tmp/limited-preview.png")

        draftView.inspectCard(draftView.visiblePickedCards[0], pickedCard)
        verify(preview.visible)
        compare(draftView.inspectedCard.instanceId, "card-2")
        draftView.hideCardPreview()
        verify(!draftView.hoverPreviewVisible)
    }

    function test_draftViewKeepsPackColumnVisibleWhenSqueezed() {
        // Regression: the seat/picks column's fixed minimumWidth used to
        // squeeze the pack column to zero width, so dealt cards never
        // rendered even though the snapshot carried them. A narrow view now
        // stacks both columns, and both regions must remain inside its bounds.
        squeezedDraftView.visible = true
        tryVerify(function() {
            const packGrid = findChild(squeezedDraftView,
                                       "limitedCurrentPackGrid")
            return packGrid && packGrid.visible && packGrid.width > 0
        })
        tryVerify(function() {
            return squeezedDraftView.compactColumns
                   && squeezedDraftView.width <= squeezeHost.width
        })

        const packColumn = findChild(squeezedDraftView,
                                     "limitedDraftPackColumn")
        const sideColumn = findChild(squeezedDraftView,
                                     "limitedDraftSideColumn")
        verify(packColumn)
        verify(sideColumn)

        const packTopLeft = packColumn.mapToItem(squeezedDraftView, 0, 0)
        const packBottomRight = packColumn.mapToItem(
                                  squeezedDraftView,
                                  packColumn.width, packColumn.height)
        const sideTopLeft = sideColumn.mapToItem(squeezedDraftView, 0, 0)
        const sideBottomRight = sideColumn.mapToItem(
                                  squeezedDraftView,
                                  sideColumn.width, sideColumn.height)
        verify(packTopLeft.x >= 0)
        verify(packBottomRight.x <= squeezedDraftView.width)
        verify(sideTopLeft.x >= 0)
        verify(sideBottomRight.x <= squeezedDraftView.width)
        verify(sideTopLeft.y >= packBottomRight.y)
        verify(sideBottomRight.y <= squeezedDraftView.height)
        squeezedDraftView.visible = false
    }

    function test_draftViewFirstShowGivesPackColumnTheRow() {
        // Regression companion: in a wide lobby the first hidden-to-visible
        // flip must hand the fill space to the pack column, so it stays
        // clearly wider than the seat column, not just at its minimum.
        revealedDraftView.visible = true
        tryVerify(function() {
            const packGrid = findChild(revealedDraftView,
                                       "limitedCurrentPackGrid")
            const seatMap = findChild(revealedDraftView,
                                      "limitedDraftSeatMap")
            return packGrid && packGrid.visible && seatMap
                   && packGrid.width > seatMap.width
        })
        verify(!revealedDraftView.compactColumns)
        revealedDraftView.visible = false
    }

    function test_draftViewFitsMinimumTwoColumnWidth() {
        squeezeHost.width = squeezedDraftView.horizontalColumnsMinimumWidth
        squeezedDraftView.visible = true
        tryVerify(function() {
            return !squeezedDraftView.compactColumns
                   && squeezedDraftView.width <= squeezeHost.width
        })

        const packColumn = findChild(squeezedDraftView,
                                     "limitedDraftPackColumn")
        const sideColumn = findChild(squeezedDraftView,
                                     "limitedDraftSideColumn")
        verify(packColumn)
        verify(sideColumn)

        const packBottomRight = packColumn.mapToItem(
                                  squeezedDraftView,
                                  packColumn.width, packColumn.height)
        const sideTopLeft = sideColumn.mapToItem(squeezedDraftView, 0, 0)
        const sideBottomRight = sideColumn.mapToItem(
                                  squeezedDraftView,
                                  sideColumn.width, sideColumn.height)
        verify(packBottomRight.x <= squeezedDraftView.width)
        verify(sideTopLeft.x >= packBottomRight.x)
        verify(sideBottomRight.x <= squeezedDraftView.width)
        verify(sideBottomRight.y <= squeezedDraftView.height)
        squeezedDraftView.visible = false
    }
}
