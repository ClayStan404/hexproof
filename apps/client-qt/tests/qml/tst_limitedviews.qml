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

    readonly property string previewImageSource: "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="

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
                return testCase.previewImageSource
            }
            property int cacheCalls: 0
            function cacheCardsIncrementally(cards) { cacheCalls++ }
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
            property string eventType: "set_sealed"
            property string stage: "deck_building"
            property int direction: 1
            property var currentPack: pool
            property var currentPacks: []
            property int picksRequired: 0
            property int packsPerPlayer: 3
            property int packsThisBatch: 1
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
            signal commandFailed(string requestId, string commandType, var payload, string error)
            property bool connected: true
            property var submittedIds: []
            property string pickedId: ""
            property var pickedIds: []
            property int pickCount: 0
            function submitLimitedDeck(name, ids, lands) { submittedIds = ids }
            function pickLimitedCard(instanceId) { pickedId = instanceId; pickCount++ }
            function pickLimitedCards(ids) { pickedIds = ids; pickCount++ }
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

    function test_previewSurvivesPublicProgress() {
        draftView.visible = true
        waitForRendering(draftView)
        const tile = findChild(draftView, "limitedDraftPackCard-card-1")
        verify(tile !== null)
        draftView.inspectCard(mockLimited.currentPack[0], tile)
        verify(draftView.hoverPreviewVisible)
        const calls = mockCatalog.cacheCalls
        mockLimited.snapshotChanged()
        waitForRendering(draftView)
        verify(draftView.hoverPreviewVisible)
        compare(draftView.inspectedCard.instanceId, "card-1")
        compare(mockCatalog.cacheCalls, calls, "Public progress must not requeue private art")
        draftView.visible = false
        verify(!draftView.hoverPreviewVisible)
    }

    function test_previewClosesWhenInspectedIdentityDisappears() {
        draftView.visible = true
        waitForRendering(draftView)
        const pool = mockLimited.pool
        const tile = findChild(draftView, "limitedDraftPackCard-card-1")
        draftView.inspectCard(pool[0], tile)
        verify(draftView.hoverPreviewVisible)
        mockLimited.currentPack = []
        mockLimited.pool = []
        mockLimited.snapshotChanged()
        const closed = !draftView.hoverPreviewVisible
        mockLimited.pool = pool
        mockLimited.currentPack = pool
        verify(closed)
    }

    function init() {
        mockLimited.currentPacks = []
        mockLimited.picksRequired = 0
        mockLimited.packsPerPlayer = 3
        mockLimited.packsThisBatch = 1
        mockLimited.eventType = "set_sealed"
        mockLimited.stage = "deck_building"
        mockLimited.deckSubmitted = false
        deckBuilder.initialPoolChosen = false
        deckBuilder.restoredSubmittedDeck = false
        deckBuilder.visible = false
        mockWs.pickCount = 0
        mockWs.pickedId = ""
        mockWs.pickedIds = []
        seatMap.direction = 1
        seatMap.participants = testCase.seats
        seatMap.participantId = "p3"
        mockLimited.participants = testCase.seats
        mockLimited.currentPack = mockLimited.pool
        mockWs.connected = true
        deckBuilder.selectedCards = ({})
        deckBuilder.selectionRevision++
        deckBuilder.basics = ({"Plains": 0, "Island": 0, "Swamp": 0,
                               "Mountain": 0, "Forest": 0})
        deckBuilder.basicsRevision++
        deckBuilder.groupingModeIndex = 0
        deckBuilder.clearFilters()
        deckBuilder.basicLandsExpanded = false
        deckBuilder.hoverPreviewVisible = false
        draftView.filters.reset()
        draftView.pendingPickId = ""
        draftView.selectedInstanceId = ""
        draftView.selectedInstanceIds = []
        draftView.hoverPreviewVisible = false
        draftView.visible = false
        Theme.uiScale = 1
        squeezeHost.width = 300
        squeezeHost.height = 640
        squeezedDraftView.compactPaneIndex = 0
        squeezedDraftView.pendingPickId = ""
        squeezedDraftView.selectedInstanceId = ""
        squeezedDraftView.selectedInstanceIds = []
        squeezedDraftView.visible = false
        revealedDraftView.visible = false
    }

    function test_shortCompactDraftKeepsWholeCardsAndPickActionVisible() {
        Theme.uiScale = 1.5
        squeezeHost.width = 740
        squeezeHost.height = 340
        squeezedDraftView.visible = true
        waitForRendering(squeezedDraftView)
        verify(squeezedDraftView.compactTabs)
        const grid = findChild(squeezedDraftView, "limitedCurrentPackGrid")
        verify(grid.height >= 100)
        verify(grid.cellHeight <= grid.height + 1)
        const tabs = findChild(squeezedDraftView, "limitedDraftWorkspaceTabs")
        mouseClick(tabs, tabs.width * 0.75, tabs.height / 2)
        compare(squeezedDraftView.compactPaneIndex, 1)
        verify(findChild(squeezedDraftView, "limitedDraftSideColumn").visible)
        verify(!grid.visible)
        const picks = findChild(squeezedDraftView, "limitedPickedCardGrid")
        const pickedRow = findChild(squeezedDraftView,
                                    "limitedDraftPickedCard-card-1")
        verify(picks.height >= pickedRow.height,
               "The picks viewport must fit a complete card row")
        const picksScroll = findChild(squeezedDraftView,
                                      "limitedDraftPicksScroll")
        verify(picksScroll)
        picksScroll.contentY = picksScroll.contentHeight - picksScroll.height
        waitForRendering(squeezedDraftView)
        const pickedPoint = pickedRow.mapToItem(picksScroll, 0, 0)
        verify(pickedPoint.y >= 0)
        verify(pickedPoint.y + pickedRow.height <= picksScroll.height + 1)
        mouseClick(tabs, tabs.width * 0.25, tabs.height / 2)
        compare(squeezedDraftView.compactPaneIndex, 0)
        const card = findChild(squeezedDraftView, "limitedDraftPackCard-card-1")
        mouseClick(card)
        compare(squeezedDraftView.selectedInstanceId, "card-1")
        const confirm = findChild(squeezedDraftView, "limitedConfirmPickButton")
        const point = confirm.mapToItem(squeezedDraftView, 0, 0)
        verify(point.y + confirm.height <= squeezedDraftView.height + 1)
        mouseClick(confirm)
        compare(mockWs.pickedId, "card-1")
        squeezedDraftView.visible = false
        Theme.uiScale = 1
    }

    function test_doubleClickConfirmsOneCurrentPick() {
        draftView.visible = true
        const tile = findChild(draftView, "limitedDraftPackCard-card-1")
        tryVerify(() => tile && tile.width > 0)
        verify(waitForRendering(draftView))
        mouseDoubleClickSequence(tile, tile.width / 2, tile.height / 2, Qt.LeftButton)
        compare(mockWs.pickCount, 1)
        compare(mockWs.pickedId, "card-1")
        draftView.confirmCard("card-2")
        compare(mockWs.pickCount, 1)
        mockLimited.currentPack = mockLimited.pool.slice(1)
        mockLimited.snapshotChanged()
        draftView.confirmCard("card-1")
        compare(mockWs.pickCount, 1)
        mockWs.connected = false
        draftView.confirmCard("card-2")
        compare(mockWs.pickCount, 1)
    }

    function test_commanderPickRequiresTwoCardsAndDoubleClickConfirmsAtomically() {
        mockLimited.eventType = "commander_cube"
        draftView.visible = true
        tryCompare(draftView, "requiredPicks", 2)
        const first = findChild(draftView, "limitedDraftPackCard-card-1")
        const second = findChild(draftView, "limitedDraftPackCard-card-2")
        verify(waitForRendering(draftView))
        mouseDoubleClickSequence(first, first.width / 2, first.height / 2, Qt.LeftButton)
        compare(mockWs.pickCount, 0)
        compare(draftView.selectedInstanceIds.length, 1)
        mouseDoubleClickSequence(second, second.width / 2, second.height / 2, Qt.LeftButton)
        compare(mockWs.pickCount, 1)
        compare(mockWs.pickedIds.length, 2)
        verify(mockWs.pickedIds.indexOf("card-1") >= 0)
        verify(mockWs.pickedIds.indexOf("card-2") >= 0)
        verify(!draftView.canConfirm)
        mockLimited.currentPack = []
        mockLimited.snapshotChanged()
        compare(draftView.selectedInstanceIds.length, 0)
        compare(draftView.pendingPickId, "")
    }

    function test_commanderPickPreservesSelectionAcrossProgressAndRejectsStaleIds() {
        mockLimited.eventType = "commander_cube"
        draftView.selectCard("card-1")
        mockLimited.snapshotChanged()
        compare(draftView.selectedInstanceIds.join(","), "card-1")
        draftView.selectCard("card-2")
        verify(draftView.canConfirm)
        draftView.selectCard("card-1")
        verify(!draftView.canConfirm)
        draftView.selectCard("not-in-pack")
        compare(draftView.selectedInstanceIds.join(","), "card-2")
        mockLimited.currentPack = mockLimited.pool.slice(0, 1)
        mockLimited.snapshotChanged()
        compare(draftView.selectedInstanceIds.length, 0)
        draftView.selectCard("card-1")
        verify(draftView.canConfirm)
        draftView.confirmPick()
        compare(mockWs.pickedIds.join(","), "card-1")
    }

    function test_pairedPacksKeepIndependentQuotas_data() {
        return [{tag: "desktop", width: 1200}, {tag: "narrow", width: 600}, {tag: "compact", width: 360}]
    }

    function test_pairedPacksKeepIndependentQuotas(data) {
        mockLimited.eventType = "commander_cube"
        mockLimited.picksRequired = 4
        mockLimited.packsPerPlayer = 6
        mockLimited.packsThisBatch = 2
        mockLimited.packRound = 2
        const a = Array.from({length: 20}, (_, i) => ({instanceId: "pack-a-" + i, name: "Card A " + i}))
        const b = Array.from({length: 20}, (_, i) => ({instanceId: "pack-b-" + i, name: "Card B " + i}))
        mockLimited.currentPack = a.concat(b)
        mockLimited.currentPacks = [{packId: "a", cards: a, picksRequired: 2}, {packId: "b", cards: b, picksRequired: 2}]
        squeezeHost.width = data.width
        squeezedDraftView.visible = true
        verify(waitForRendering(squeezedDraftView))
        const first = findChild(squeezedDraftView, "limitedCurrentPackGrid")
        const second = findChild(squeezedDraftView, "limitedCurrentPackGrid-2")
        compare(first.cards.length, 20)
        compare(second.cards.length, 20)
        verify(first.width > 0 && first.height > 0 && second.width > 0 && second.height > 0)
        squeezedDraftView.selectedInstanceIds = [a[0].instanceId, a[1].instanceId, a[2].instanceId, b[0].instanceId]
        verify(!squeezedDraftView.canConfirm)
        squeezedDraftView.selectedInstanceIds = []
        for (const card of [a[0], b[0], a[1], b[1], a[2]]) squeezedDraftView.selectCard(card.instanceId)
        compare(squeezedDraftView.selectedInstanceIds.length, 4)
        verify(squeezedDraftView.selectedInstanceIds.indexOf(a[0].instanceId) < 0)
        verify(squeezedDraftView.selectedInstanceIds.indexOf(b[0].instanceId) >= 0)
        verify(squeezedDraftView.canConfirm)
        mockLimited.snapshotChanged()
        verify(squeezedDraftView.canConfirm)
        squeezedDraftView.confirmPick()
        compare(mockWs.pickedIds.length, 4)
        compare(mockWs.pickCount, 1)
        const last = a.map(card => ({instanceId: "last-" + card.instanceId, name: card.name}))
        mockLimited.currentPack = last
        mockLimited.currentPacks = [{packId: "last", cards: last, picksRequired: 2}]
        mockLimited.picksRequired = 2
        mockLimited.packsThisBatch = 1
        mockLimited.snapshotChanged()
        verify(!squeezedDraftView.pairedPacks)
        compare(squeezedDraftView.requiredPicks, 2)
        compare(squeezedDraftView.pendingPickId, "")
        squeezedDraftView.visible = false
    }

    function test_draftBuildChoiceKeepsOrReleasesExactPool() {
        mockLimited.eventType = "set_draft"
        deckBuilder.visible = true
        const choice = findChild(deckBuilder, "limitedDeckStartChoice")
        tryVerify(() => choice.opened)
        findChild(choice.contentItem, "keepDraftedCardsButton").clicked()
        compare(deckBuilder.selectedPoolCount, mockLimited.pool.length)
        deckBuilder.moveToSideboard("card-1")
        mockLimited.snapshotChanged()
        compare(deckBuilder.selectedPoolCount, mockLimited.pool.length - 1)
        tryVerify(() => !choice.opened)
        deckBuilder.visible = false
        deckBuilder.visible = true
        verify(!choice.visible)
        deckBuilder.initialPoolChosen = false
        tryVerify(() => choice.opened)
        findChild(choice.contentItem, "rebuildFromPoolButton").clicked()
        compare(deckBuilder.selectedPoolCount, 0)
        compare(deckBuilder.sideboardCards.length, mockLimited.pool.length)
    }

    function test_draftBuildChoicePreservesSubmittedDeck() {
        mockLimited.eventType = "cube_draft"
        mockLimited.deckSubmitted = true
        mockLimited.mainboardInstanceIds = ["card-2"]
        mockLimited.basicLands = [{name: "Island", count: 17}]
        deckBuilder.visible = true
        mockLimited.snapshotChanged()
        compare(deckBuilder.selectedPoolCount, 1)
        compare(deckBuilder.basicValue("Island"), 17)
        verify(!findChild(deckBuilder, "limitedDeckStartChoice").visible)
        deckBuilder.chooseInitialPool(false)
        compare(deckBuilder.selectedPoolCount, 1)
    }
    function test_dragMainDeckRowIntoAvailablePool() {
        deckBuilder.visible = true
        deckBuilder.moveToMainDeck("card-2")
        const list = findChild(deckBuilder, "limitedMainDeckGrid")
        const pool = findChild(deckBuilder, "limitedSideboardGrid")
        tryVerify(() => list.itemAtIndex(0) !== null)
        verify(waitForRendering(deckBuilder))
        const row = list.itemAtIndex(0)
        const destination = pool.mapToItem(row, pool.width / 2, pool.height / 2)
        mouseDrag(row, row.width / 2, row.height / 2,
                  destination.x - row.width / 2, destination.y - row.height / 2)
        compare(deckBuilder.selectedPoolCount, 0)
        verify(deckBuilder.sideboardCards.some(card => card.instanceId === "card-2"))
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
        compare(header.text, "Draft pack 1 · 2 cards remaining")

        mockLimited.participants = testCase.twoSeats
        verify(draftView.twoPlayer)
        compare(header.text, "Draft pack 1 · 2 cards remaining")
    }

    function test_deckBuilderMovesVisibleCardsBetweenAreas() {
        deckBuilder.visible = true
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
        deckBuilder.visible = true
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
        deckBuilder.visible = true
        deckBuilder.filters.colors = ["M"]
        deckBuilder.filters.types = ["Creature"]
        deckBuilder.filters.manaValues = ["3"]
        deckBuilder.filters.rarities = ["mythic"]
        compare(deckBuilder.visibleSideboardCards.length, 1)
        compare(deckBuilder.visibleSideboardCards[0].instanceId, "card-2")

        deckBuilder.filters.manaValues = ["2"]
        compare(deckBuilder.visibleSideboardCards.length, 0)

        deckBuilder.clearFilters()
        compare(deckBuilder.visibleSideboardCards.length, 2)
        verify(!deckBuilder.filtersActive)
    }

    function test_mainDeckFiltersStayIndependentAndRemoveOnlyTheVisibleInstance() {
        deckBuilder.visible = true
        deckBuilder.setAutoBasicLands(false)
        deckBuilder.moveToMainDeck("card-1")
        deckBuilder.moveToMainDeck("card-2")
        const before = JSON.stringify(mockLimited.pool)
        const deckCount = deckBuilder.selectedCount
        const landCount = deckBuilder.selectedLandCount
        deckBuilder.filters.types = ["Instant"]
        deckBuilder.mainFilters.colors = ["M"]
        deckBuilder.mainFilters.types = ["Creature"]
        deckBuilder.mainFilters.manaValues = ["3"]
        deckBuilder.mainFilters.rarities = ["mythic"]
        deckBuilder.mainFilters.query = "Test Creature"
        compare(deckBuilder.visibleDeckListCards.map(card => card.instanceId), ["card-2"])
        compare(deckBuilder.selectedCount, deckCount)
        compare(deckBuilder.selectedLandCount, landCount)
        compare(JSON.stringify(mockLimited.pool), before)
        const filters = findChild(deckBuilder, "limitedMainDeckFilters")
        verify(filters.visible)
        const list = findChild(deckBuilder, "limitedMainDeckGrid")
        compare(list.cards.length, 1)
        list.cardActivated(list.cards[0])
        verify(deckBuilder.cardSelected("card-1"))
        verify(!deckBuilder.cardSelected("card-2"))
        compare(deckBuilder.selectedCount, deckCount - 1)
        compare(deckBuilder.visibleSideboardCards.length, 0, "The pool retains its independent instant filter")
        compare(deckBuilder.visibleDeckListCards.length, 0)
        compare(list.emptyText, "No cards match all active filters.")
        deckBuilder.clearFilters()
        compare(deckBuilder.visibleSideboardCards.length, 1)
        compare(deckBuilder.visibleDeckListCards.length, 1)
    }

    function test_mainDeckColorSelectionRequiresBothColors() {
        deckBuilder.visible = true
        deckBuilder.setAutoBasicLands(false)
        deckBuilder.moveToMainDeck("card-1")
        deckBuilder.moveToMainDeck("card-2")
        deckBuilder.mainFilters.colors = ["U"]
        compare(deckBuilder.visibleDeckListCards.length, 2)
        deckBuilder.mainFilters.toggle("colors", "G")
        compare(deckBuilder.visibleDeckListCards.map(card => card.instanceId), ["card-2"])
        compare(deckBuilder.selectedCount, 2)
        deckBuilder.mainFilters.toggle("colors", "U")
        compare(deckBuilder.visibleDeckListCards.map(card => card.instanceId), ["card-2"])
        deckBuilder.mainFilters.reset()
        compare(deckBuilder.visibleDeckListCards.length, 2)
    }

    function test_deckBuilderShowsRarityAndFullCardPreview() {
        deckBuilder.visible = true
        deckBuilder.filters.rarities = ["common"]
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
        compare(previewArt.source.toString(), testCase.previewImageSource)
        tryCompare(previewArt, "status", Image.Ready)
        deckBuilder.hideCardPreview()
        verify(!deckBuilder.hoverPreviewVisible)
        deckBuilder.visible = false
    }

    function test_draftViewFiltersPicksAndPreviewsBothAreas() {
        draftView.visible = true
        draftView.filters.rarities = ["mythic"]
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
        compare(previewArt.source.toString(), testCase.previewImageSource)
        tryCompare(previewArt, "status", Image.Ready)

        draftView.inspectCard(draftView.visiblePickedCards[0], pickedCard)
        verify(preview.visible)
        compare(draftView.inspectedCard.instanceId, "card-2")
        draftView.hideCardPreview()
        verify(!draftView.hoverPreviewVisible)
    }

    function test_draftPickedTypesCombineWithRarityWithoutChangingPack() {
        draftView.visible = true
        draftView.filters.types = ["Land"]
        compare(draftView.visiblePickedCards.length, 1)
        compare(draftView.visiblePickedCards[0].name, "Island")
        draftView.filters.rarities = ["mythic"]
        compare(draftView.visiblePickedCards.length, 0)
        draftView.filters.types = ["Creature"]
        compare(draftView.visiblePickedCards.length, 1)
        compare(draftView.visiblePickedCards[0].name, "Test Creature")
        compare(mockLimited.currentPack.length, 2)
    }

    function test_confirmPickRejectsStaleAndPendingSelections() {
        draftView.selectedInstanceId = "not-in-pack"
        verify(!draftView.canConfirm)
        draftView.selectedInstanceId = "card-1"
        verify(draftView.canConfirm)
        draftView.confirmPick()
        compare(mockWs.pickedId, "card-1")
        draftView.selectedInstanceId = "card-2"
        verify(!draftView.canConfirm)
        draftView.confirmPick()
        compare(mockWs.pickedId, "card-1")
        mockLimited.currentPack = mockLimited.pool.slice(1)
        mockLimited.snapshotChanged()
        compare(draftView.pendingPickId, "")
        verify(draftView.canConfirm)
        draftView.confirmPick()
        mockWs.commandFailed("pick", "limited.pick", {}, "Try again")
        compare(draftView.pendingPickId, "")
        draftView.selectedInstanceId = "card-2"
        mockWs.connected = false
        verify(!draftView.canConfirm)
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
                                      "limitedDraftSideColumn")
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
