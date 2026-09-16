// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic
import QtTest
import "../../qml/components"

TestCase {
    id: testCase
    name: "LimitedBasicLands"
    when: windowShown
    ApplicationWindow { id: window; width: 1200; height: 800; visible: true }
    LimitedBasicLandPlan { id: planner }
    QtObject {
        id: limitedState
        signal snapshotChanged()
        property string tournamentId: "AUTO-LANDS"
        property string eventType: "set_sealed"
        property string stage: "deck_building"
        property bool deckSubmitted: false
        property var mainboardInstanceIds: []
        property var basicLands: []
        property var participants: []
        property var pool: []
    }
    QtObject {
        id: connection
        property string serverUrl: "ws://localhost:57320/ws"
        property bool connected: true
        property var submittedIds: []
        property var submittedBasics: []
        property var submittedCommanders: []
        function submitLimitedDeck(name, ids, lands) {
            submittedIds = ids
            submittedBasics = lands
        }
        function submitLimitedCommanderDeck(name, ids, lands, commanders, choices) {
            submittedIds = ids
            submittedBasics = lands
            submittedCommanders = commanders
        }
    }
    QtObject {
        id: catalog
        property int imageRevision: 0
        function tableImageSource() { return "" }
        function cacheCardsIncrementally() { }
    }
    QtObject {
        id: store
        property var draft: ({})
        property string lastError: ""
        function loadDraft(server, event, participant) { return draft }
        function saveDraft(server, event, participant, value) { draft = JSON.parse(JSON.stringify(value)) }
        function removeDraft(server, event, participant) { draft = ({}) }
    }
    Component {
        id: builderComponent
        LimitedDeckBuilder {
            width: 1200; height: 800
            limitedModel: limitedState
            wsModel: connection
            cardCatalogModel: catalog
            draftStore: store
            participantId: "p-1"
        }
    }
    Component {
        id: builderHostComponent
        Item { width: 1200; height: 800 }
    }

    function init() {
        store.draft = ({})
        limitedState.eventType = "set_sealed"
        limitedState.deckSubmitted = false
        limitedState.mainboardInstanceIds = []
        limitedState.basicLands = []
        limitedState.pool = [
            {instanceId: "u", name: "Blue spell", typeLine: "Instant", manaCost: "{U}"},
            {instanceId: "r", name: "Red spell", typeLine: "Creature", manaCost: "{R}{R}"},
            {instanceId: "land", name: "Island", typeLine: "Basic Land — Island", manaCost: ""}
        ]
        connection.submittedIds = []
        connection.submittedBasics = []
        connection.submittedCommanders = []
    }

    function test_hidingBuilderClosesBasicLandEditor_data() {
        return [{tag: "builder", hideAncestor: false},
                {tag: "ancestor", hideAncestor: true}]
    }

    function test_hidingBuilderClosesBasicLandEditor(data) {
        const host = createTemporaryObject(builderHostComponent, window.contentItem)
        const builder = createTemporaryObject(builderComponent, host)
        verify(builder !== null)
        builder.moveToMainDeck("u")
        builder.adjustBasic("Island", -1)
        const savedSelection = builder.selectionFingerprint()
        const popup = findChild(builder, "limitedBasicLandsPopup")
        verify(popup !== null)
        waitForRendering(builder)
        mouseClick(findChild(builder, "limitedBasicLandsButton"))
        tryVerify(() => popup.opened)

        const hiddenItem = data.hideAncestor ? host : builder
        hiddenItem.visible = false
        tryVerify(() => !popup.visible)
        verify(!builder.basicLandsExpanded)
        hiddenItem.visible = true
        waitForRendering(builder)
        verify(!popup.visible)
        compare(builder.selectionFingerprint(), savedSelection)

        mouseClick(findChild(builder, "limitedBasicLandsButton"))
        tryVerify(() => popup.opened)
        mouseClick(findChild(builder, "limitedBasicLandsDone"))
        tryVerify(() => !popup.visible)
    }

    function test_manaDemand_data() {
        return [
            {tag: "double pips", card: {manaCost: "{2}{U}{U}"}, weights: [0, 2, 0, 0, 0]},
            {tag: "hybrid", card: {manaCost: "{W/U}{B/R}"}, weights: [0.5, 0.5, 0.5, 0.5, 0]},
            {tag: "two hybrid", card: {manaCost: "{2/G}"}, weights: [0, 0, 0, 0, 1]},
            {tag: "phyrexian", card: {manaCost: "{B/P}{G/U/P}"}, weights: [0, 0.5, 1, 0, 0.5]},
            {tag: "generic snow variable colorless", card: {manaCost: "{X}{Y}{Z}{S}{C}{5}"}, weights: [0, 0, 0, 0, 0]},
            {tag: "both split costs", card: {manaCost: "{1}{R} // {W}{W}"}, weights: [2, 0, 0, 1, 0]},
            {tag: "actual colors fallback", card: {cardColors: "RG", colors: "WUBRG"}, weights: [0, 0, 0, 0.5, 0.5]},
            {tag: "color array fallback", card: {cardColors: ["U", "R"]}, weights: [0, 0.5, 0, 0.5, 0]},
            {tag: "null cost fallback", card: {manaCost: null, cardColors: "G"}, weights: [0, 0, 0, 0, 1]},
            {tag: "identity is not color", card: {colors: "U"}, weights: [0, 0, 0, 0, 0]},
            {tag: "known empty cost", card: {manaCost: "", cardColors: "U"}, weights: [0, 0, 0, 0, 0]},
            {tag: "unknown metadata", card: {}, weights: [0, 0, 0, 0, 0]},
            {tag: "invalid color string", card: {cardColors: "unknown"}, weights: [0, 0, 0, 0, 0]},
            {tag: "selected land", card: {typeLine: "Land — Forest", cardColors: "G"}, weights: [0, 0, 0, 0, 0]},
            {tag: "spell with land back", card: {typeLine: "Sorcery // Land", manaCost: "{1}{B}"}, weights: [0, 0, 1, 0, 0]}
        ]
    }
    function test_manaDemand(data) {
        compare(planner.cardDemand(data.card), data.weights)
    }
    function test_ratioCountsCopiesAndPhysicalLands() {
        const cards = [
            {manaCost: "{U}", count: 15},
            {manaCost: "{R}{R}", count: 8},
            {typeLine: "Basic Land — Island", cardColors: "U", count: 2}
        ]
        const original = JSON.stringify(cards)
        const result = planner.recommend(cards, 40)
        compare(result.needed, 15)
        compare(result.weights, [0, 15, 0, 16, 0])
        compare(result.basics, {Plains: 0, Island: 6, Swamp: 0, Mountain: 9, Forest: 0})
        compare(result.sources, [0, 2, 0, 0, 0])
        compare(result.physicalLandCount, 2)
        compare(JSON.stringify(cards), original)
    }
    function test_roundingIsStableAndNeverExceedsTarget() {
        const cards = [{manaCost: "{W/U}"}, {manaCost: "{1}", count: 22}]
        const result = planner.recommend(cards, 40)
        compare(result.basics.Plains, 9)
        compare(result.basics.Island, 8)
        compare(planner.recommend(cards.slice().reverse(), 40).basics, result.basics)
        compare(planner.recommend([{manaCost: "{W}", count: 40}], 40).basics, planner.emptyBasics())
        compare(planner.recommend([{manaCost: "{W}", count: 45}], 40).basics, planner.emptyBasics())
    }
    function test_emptyColorlessAndUnresolvedDoNotInventColors() {
        for (const cards of [[], [{manaCost: "{3}{C}"}], [{colors: "G"}]]) {
            const result = planner.recommend(cards, 40)
            compare(result.basics, planner.emptyBasics())
            verify(!result.hasColors)
        }
    }
    function test_landSources_data() {
        return [
            {tag: "ordinary basic without metadata", card: {name: "Plains"}, land: true, known: true, colors: ["W"]},
            {tag: "localized nonbasic", card: {name: "Karplusan Forest", typeLine: "地", oracleText: "{T}: Add {C}."}, land: true, known: true, colors: []},
            {tag: "localized legendary land", card: {name: "Takenuma, Abandoned Mire", typeLine: "传奇地", oracleText: "{T}: Add {B}."}, land: true, known: true, colors: ["B"]},
            {tag: "localized dual types", card: {typeLine: "地～平原／海岛"}, land: true, known: true, colors: ["W", "U"]},
            {tag: "traditional dual types", card: {typeLine: "地～沼澤／樹林"}, land: true, known: true, colors: ["B", "G"]},
            {tag: "goblin subtype is not land", card: {typeLine: "神器生物～地精／神器师"}, land: false, known: false, colors: []},
            {tag: "localized spell land MDFC", card: {typeLine: "法术 // 地"}, land: false, known: false, colors: []},
            {tag: "localized land front MDFC", card: {typeLine: "地 // 地", producedMana: "G"}, land: true, known: true, colors: ["G"]},
            {tag: "snow basic", card: {name: "Snow-Covered Island"}, land: true, known: true, colors: ["U"]},
            {tag: "typed dual", card: {typeLine: "Land — Plains Island"}, land: true, known: true, colors: ["W", "U"]},
            {tag: "name alone is not a basic subtype", card: {name: "Forest of mystery", typeLine: "Land"}, land: true, known: false, colors: []},
            {tag: "literal mana", card: {typeLine: "Land", oracleText: "This land enters tapped.\n{T}: Add {R} or {G}."}, land: true, known: true, colors: ["R", "G"]},
            {tag: "literal three colors", card: {typeLine: "Land", oracleText: "{T}: Add {W}, {U}, or {B}."}, land: true, known: true, colors: ["W", "U", "B"]},
            {tag: "literal two mana still one source", card: {typeLine: "Land", oracleText: "{T}: Add {G}{G}."}, land: true, known: true, colors: ["G"]},
            {tag: "colorless utility", card: {typeLine: "Land", oracleText: "{T}: Add {C}."}, land: true, known: true, colors: []},
            {tag: "conditional source unknown", card: {typeLine: "Land", oracleText: "{T}: Add {G}. Activate only if you control an Elf."}, land: true, known: false, colors: []},
            {tag: "sacrificed source unknown", card: {typeLine: "Land", oracleText: "{T}, Sacrifice this land: Add {U}{U}."}, land: true, known: false, colors: []},
            {tag: "filter land input is not a free source", card: {typeLine: "Land", oracleText: "{1}, {T}: Add {W}{U}."}, land: true, known: false, colors: []},
            {tag: "colored filter input is not a free source", card: {typeLine: "Land", oracleText: "{W/U}, {T}: Add {W}{W}, {W}{U}, or {U}{U}."}, land: true, known: false, colors: []},
            {tag: "restricted mana unknown", card: {typeLine: "Land", oracleText: "{T}: Add {G}. Spend this mana only to cast creature spells."}, land: true, known: false, colors: []},
            {tag: "conditional second ability not guessed", card: {typeLine: "Land", oracleText: "{T}: Add {C}.\n{T}: Add {U}. Activate only if you control an Island."}, land: true, known: false, colors: []},
            {tag: "any color unknown", card: {typeLine: "Land", oracleText: "{T}: Add one mana of any color."}, land: true, known: false, colors: []},
            {tag: "fetch unknown", card: {typeLine: "Land", oracleText: "{T}, Sacrifice this land: Search your library for a basic land card."}, land: true, known: false, colors: []},
            {tag: "identity is not production", card: {typeLine: "Land", colors: "WUBRG", cardColors: "U"}, land: true, known: false, colors: []},
            {tag: "authoritative source metadata", card: {typeLine: "Land", producedMana: ["W", "U", "C"]}, land: true, known: true, colors: ["W", "U"]},
            {tag: "authoritative source string", card: {typeLine: "Land", producedMana: "UG"}, land: true, known: true, colors: ["U", "G"]},
            {tag: "authoritative no mana", card: {typeLine: "Land", producedMana: []}, land: true, known: true, colors: []},
            {tag: "invalid source metadata", card: {typeLine: "Land", producedMana: "unknown"}, land: true, known: false, colors: []},
            {tag: "spell-land MDFC", card: {typeLine: "Instant // Land", producedMana: ["U"]}, land: false, known: false, colors: []},
            {tag: "land-spell MDFC uses front", card: {typeLine: "Land // Creature", oracleText: "{T}: Add {R}. // Creature rules"}, land: true, known: true, colors: ["R"]}
        ]
    }
    function test_landSources(data) {
        const result = planner.landSources(data.card)
        compare(result.isLand, data.land)
        compare(result.known, data.known)
        compare(result.colors, data.colors)
    }
    function test_commanderBasicsCompensateExistingPlains() {
        const cards = [{manaCost: "{W}", count: 18}, {manaCost: "{U}", count: 18},
            {name: "Plains", count: 12}]
        const result = planner.recommend(cards, 60)
        compare(result.needed, 12)
        compare(result.basics, {Plains: 0, Island: 12, Swamp: 0, Mountain: 0, Forest: 0})
        compare(result.sources, [12, 0, 0, 0, 0])
        compare(planner.recommend(cards.slice().reverse(), 60).basics, result.basics)
    }
    function test_oversuppliedAndOffColorSourcesDoNotConsumeDeficits() {
        const result = planner.recommend([{manaCost: "{W}", count: 6}, {manaCost: "{U}", count: 6},
            {name: "Plains", count: 20}, {name: "Forest", count: 6}], 40)
        compare(result.needed, 2)
        compare(result.basics, {Plains: 0, Island: 2, Swamp: 0, Mountain: 0, Forest: 0})
        compare(result.sources, [20, 0, 0, 0, 0])
    }
    function test_flexibleSourcesShareOneLandAcrossDemandedColors() {
        const cards = [{manaCost: "{W}", count: 12}, {manaCost: "{U}", count: 12},
            {typeLine: "Land — Plains Island", count: 4}, {name: "Plains", count: 4}]
        const result = planner.recommend(cards, 40)
        compare(result.sources, [6, 2, 0, 0, 0])
        compare(result.basics, {Plains: 2, Island: 6, Swamp: 0, Mountain: 0, Forest: 0})
        const blueOnly = planner.recommend([{manaCost: "{U}", count: 23}, cards[2]], 40)
        compare(blueOnly.sources, [0, 4, 0, 0, 0])
        compare(blueOnly.basics.Island, 13)
    }
    function test_unknownAndUtilityLandsAreCountedWithoutInventingColoredSources() {
        const result = planner.recommend([{manaCost: "{W/U}", count: 23},
            {typeLine: "Land", count: 2, colors: "WUBRG"},
            {typeLine: "Land", oracleText: "{T}: Add {C}.", count: 2}], 40)
        compare(result.physicalLandCount, 4)
        compare(result.unknownSourceLandCount, 2)
        compare(result.sources, [0, 0, 0, 0, 0])
        compare(result.basics, {Plains: 7, Island: 6, Swamp: 0, Mountain: 0, Forest: 0})
    }
    function test_lowLandWarningIsNonblockingHeuristicAtTarget() {
        const cards = [{manaCost: "{G}", count: 60}]
        const result = planner.analyze(cards, {}, 60)
        verify(result.lowLandCount)
        compare(result.totalCards, 60)
        compare(result.landCount, 0)
        compare(result.minimumSuggestedLands, 20)
        compare(planner.recommend(cards, 60).basics, planner.emptyBasics())
        verify(!planner.analyze([{manaCost: "{G}", count: 39}], {}, 60).lowLandCount)
        verify(planner.analyze([{manaCost: "{G}", count: 41}], {Forest: 19}, 60).lowLandCount)
        verify(!planner.analyze([{manaCost: "{G}", count: 40}], {Forest: 20}, 60).lowLandCount)
        verify(planner.analyze([{manaCost: "{G}", count: 47}], {Forest: 23}, 60).lowLandCount)
        verify(!planner.analyze([], {}, 40).lowLandCount)
    }
    function test_warningCountsPhysicalLandsAndConservativelyTreatsMdfcs() {
        const result = planner.analyze([{manaCost: "{U}", count: 22},
            {typeLine: "Sorcery // Land", manaCost: "{U}", count: 3},
            {typeLine: "Land", count: 5}], {Island: 10}, 40)
        compare(result.totalCards, 40)
        compare(result.landCount, 15)
        compare(result.unknownSourceLandCount, 5)
        verify(!result.lowLandCount)
    }
    function test_quantityBoundsAndZeroDemand() {
        const cards = [{manaCost: "{W}", count: 2.9}, {name: "Plains", count: -4},
            {manaCost: "{U}", count: Infinity}, {manaCost: "{R}", count: NaN},
            {typeLine: "Land", count: 0}]
        const result = planner.recommend(cards, 40)
        compare(result.physicalCount, 2)
        compare(result.physicalLandCount, 0)
        compare(result.unknownSourceLandCount, 0)
        compare(result.basics.Plains, 38)
        compare(planner.recommend([{manaCost: "{W}", count: 10000}], 60).physicalCount, 1000)
        const noDemand = planner.recommend([{name: "Forest", count: 12}], 40)
        compare(noDemand.basics, planner.emptyBasics())
        verify(!noDemand.hasColors)
    }
    function test_variedDemandAndSourceAllocationsKeepExactTotals() {
        for (let variant = 0; variant < 60; ++variant) {
            const cards = []
            for (let color = 0; color < planner.colors.length; ++color) {
                cards.push({manaCost: "{" + planner.colors[color] + "}", count: (variant + color * 3) % 7})
                cards.push({name: planner.names[color], count: (variant * 3 + color) % 4})
            }
            const result = planner.recommend(cards, 60)
            let total = 0
            for (const name of planner.names) {
                const count = result.basics[name]
                verify(Number.isFinite(count))
                verify(count >= 0)
                compare(count, Math.floor(count))
                total += count
            }
            compare(total, result.needed)
            compare(planner.recommend(cards.slice().reverse(), 60).basics, result.basics)
        }
    }
    function test_selectingCardsRebalancesAndSubmitKeepsExactIds() {
        const builder = createTemporaryObject(builderComponent, window.contentItem)
        verify(builder.autoBasicLands)
        compare(builder.countBasics(), 0)
        builder.moveToMainDeck("u")
        compare(builder.selectedCount, 40)
        compare(builder.basicValue("Island"), 39)
        builder.moveToMainDeck("r")
        compare(builder.selectedCount, 40)
        compare(builder.basicValue("Island"), 13)
        compare(builder.basicValue("Mountain"), 25)
        builder.moveToMainDeck("land")
        compare(builder.selectedPoolCount, 3)
        compare(builder.countBasics(), 37)
        builder.moveToSideboard("u")
        compare(builder.basicValue("Island"), 0)
        compare(builder.basicValue("Mountain"), 38)
        verify(builder.cardSelected("land"))
        builder.submit()
        compare(connection.submittedIds.sort(), ["land", "r"])
        compare(connection.submittedBasics, [{name: "Mountain", count: 38}])
    }
    function test_manualAdjustmentStopsAutomaticChangesAndCanResume() {
        const builder = createTemporaryObject(builderComponent, window.contentItem)
        builder.moveToMainDeck("u")
        builder.adjustBasic("Island", -1)
        verify(!builder.autoBasicLands)
        builder.moveToMainDeck("r")
        compare(builder.basicValue("Island"), 38)
        compare(builder.basicValue("Mountain"), 0)
        builder.setAutoBasicLands(true)
        compare(builder.selectedCount, 40)
        compare(builder.basicValue("Mountain"), 25)
        builder.removeFromMainDeck({name: "Mountain", virtualBasic: true})
        verify(!builder.autoBasicLands)
        compare(builder.basicValue("Mountain"), 24)
        builder.moveToSideboard("r")
        compare(builder.basicValue("Mountain"), 24)
    }
    function test_toggleCanDisableAndReenableAutomaticMode() {
        const builder = createTemporaryObject(builderComponent, window.contentItem)
        builder.moveToMainDeck("u")
        builder.basicLandsExpanded = true
        const control = findChild(builder, "limitedAutoBasicLandsControl")
        tryVerify(() => control.visible)
        mouseClick(control)
        verify(!builder.autoBasicLands)
        builder.moveToMainDeck("r")
        compare(builder.basicValue("Island"), 39)
        mouseClick(control)
        verify(builder.autoBasicLands)
        compare(builder.selectedCount, 40)
        builder.basicLandsExpanded = false
    }
    function test_filtersDoNotChangeRatioAndMetadataRefreshRecalculates() {
        limitedState.pool = [
            {instanceId: "u", name: "Blue spell", typeLine: "Instant", cardColors: "U"},
            {instanceId: "r", name: "Red spell", typeLine: "Creature", cardColors: "R"}
        ]
        const builder = createTemporaryObject(builderComponent, window.contentItem)
        builder.moveToMainDeck("u")
        builder.moveToMainDeck("r")
        compare(builder.basicValue("Island"), 19)
        compare(builder.basicValue("Mountain"), 19)
        builder.filters.query = "Blue spell"
        builder.groupingModeIndex = 2
        wait(0)
        compare(builder.basicValue("Island"), 19)
        compare(builder.basicValue("Mountain"), 19)
        limitedState.pool = [
            {instanceId: "u", name: "Blue spell", typeLine: "Instant", manaCost: "{U}"},
            {instanceId: "r", name: "Red spell", typeLine: "Creature", manaCost: "{R}{R}"}
        ]
        tryCompare(builder, "selectedCount", 40)
        tryVerify(() => builder.basicValue("Island") === 13)
        compare(builder.basicValue("Mountain"), 25)
    }
    function test_hiddenBuilderDoesNotClearSavedBasicLands() {
        const builder = createTemporaryObject(builderComponent, window.contentItem)
        builder.moveToMainDeck("u")
        builder.visible = false
        wait(0)
        compare(builder.basicValue("Island"), 39)
        compare(store.draft.basics.Island, 39)
        builder.visible = true
        wait(0)
        compare(builder.basicValue("Island"), 39)
    }
    function test_draftInitialChoiceAndRestorationKeepAutoMode() {
        limitedState.eventType = "set_draft"
        let builder = builderComponent.createObject(window.contentItem)
        builder.chooseInitialPool(true)
        compare(builder.selectedCount, 40)
        verify(store.draft.autoBasicLands)
        builder.destroy()
        wait(0)
        builder = createTemporaryObject(builderComponent, window.contentItem)
        verify(builder.autoBasicLands)
        compare(builder.selectedCount, 40)
        builder.moveToSideboard("r")
        compare(builder.basicValue("Island"), 38)
        compare(builder.basicValue("Mountain"), 0)
    }
    function test_keepingFortyFiveCubePicksDoesNotAddOrRemoveCards() {
        limitedState.eventType = "cube_draft"
        const cards = []
        for (let index = 0; index < 45; ++index) {
            cards.push({instanceId: "cube-" + index, name: "Cube spell", typeLine: "Creature", manaCost: "{G}"})
        }
        limitedState.pool = cards
        const builder = createTemporaryObject(builderComponent, window.contentItem)
        builder.chooseInitialPool(true)
        compare(builder.selectedPoolCount, 45)
        compare(builder.selectedCount, 45)
        compare(builder.countBasics(), 0)
        for (let index = 0; index < 6; ++index) builder.moveToSideboard("cube-" + index)
        compare(builder.selectedPoolCount, 39)
        compare(builder.basicValue("Forest"), 1)
        compare(builder.selectedCount, 40)
    }
    function test_keepingSixtyCommanderPicksShowsWarningButAllowsSubmission() {
        limitedState.eventType = "commander_cube"
        const cards = []
        for (let index = 0; index < 60; ++index) {
            cards.push({instanceId: "commander-" + index, name: "Commander spell " + index,
                typeLine: "Legendary Creature", manaCost: "{G}", colors: "G"})
        }
        limitedState.pool = cards
        const builder = createTemporaryObject(builderComponent, window.contentItem)
        builder.chooseInitialPool(true)
        builder.toggleCommander("commander-0")
        compare(builder.selectedPoolCount, 60)
        compare(builder.selectedCount, 60)
        compare(builder.countBasics(), 0)
        verify(builder.landAssessment.lowLandCount)
        verify(builder.landWarning.length > 0)
        verify(findChild(builder, "limitedBasicLandsButton").text.indexOf("⚠") >= 0)
        verify(findChild(builder, "limitedSubmitDeckButton").enabled)
        builder.basicLandsExpanded = true
        tryVerify(() => findChild(builder, "limitedLowLandWarning").visible)
        builder.basicLandsExpanded = false
        builder.submit()
        compare(connection.submittedIds.length, 60)
        compare(connection.submittedCommanders, ["commander-0"])
        compare(connection.submittedBasics, [])
        for (let index = 1; index <= 20; ++index) builder.moveToSideboard("commander-" + index)
        compare(builder.selectedCount, 60)
        compare(builder.basicValue("Forest"), 20)
        verify(!builder.landAssessment.lowLandCount)
        compare(builder.landWarning, "")
    }
    function test_unknownSourceNoticeAndManualModeSurviveMetadataRefresh() {
        limitedState.pool = [{instanceId: "u", name: "Blue spell", manaCost: "{U}", typeLine: "Instant"},
            {instanceId: "r", name: "Red spell", manaCost: "{R}", typeLine: "Instant"},
            {instanceId: "land", name: "Unknown land", typeLine: "Land"}]
        const builder = createTemporaryObject(builderComponent, window.contentItem)
        for (const card of limitedState.pool) builder.moveToMainDeck(card.instanceId)
        builder.basicLandsExpanded = true
        tryVerify(() => findChild(builder, "limitedUnknownManaSources").visible)
        compare(builder.landAssessment.unknownSourceLandCount, 1)
        builder.adjustBasic("Island", -1)
        const manual = JSON.stringify(builder.basics)
        limitedState.pool = [{instanceId: "u", name: "Blue spell", manaCost: "{U}", typeLine: "Instant"},
            {instanceId: "r", name: "Red spell", manaCost: "{R}", typeLine: "Instant"},
            {instanceId: "land", name: "Known land", typeLine: "Land", oracleText: "{T}: Add {R}."}]
        tryVerify(() => builder.landAssessment.unknownSourceLandCount === 0)
        verify(!findChild(builder, "limitedUnknownManaSources").visible)
        verify(!builder.autoBasicLands)
        compare(JSON.stringify(builder.basics), manual)
        builder.basicLandsExpanded = false
    }
    function test_metadataChangesPreserveManualBasics() {
        limitedState.pool = [{instanceId: "u", name: "Blue spell", cardColors: "U"}]
        const builder = createTemporaryObject(builderComponent, window.contentItem)
        builder.moveToMainDeck("u")
        builder.adjustBasic("Island", -2)
        limitedState.pool = [{instanceId: "u", name: "Blue spell", manaCost: "{R}{R}"}]
        wait(0)
        verify(!builder.autoBasicLands)
        compare(builder.basicValue("Island"), 37)
        compare(builder.basicValue("Mountain"), 0)
    }
    function test_restoredManualAndSubmittedBasicsAreNotOverwritten() {
        store.draft = {mainboardInstanceIds: ["u"], basics: {Forest: 17}, initialPoolChosen: true}
        const builder = createTemporaryObject(builderComponent, window.contentItem)
        verify(!builder.autoBasicLands)
        compare(builder.basicValue("Forest"), 17)
        builder.moveToMainDeck("r")
        compare(builder.basicValue("Forest"), 17)
        builder.setAutoBasicLands(true)
        limitedState.mainboardInstanceIds = ["u", "land"]
        limitedState.basicLands = [{name: "Swamp", count: 19}]
        limitedState.deckSubmitted = true
        limitedState.snapshotChanged()
        verify(!builder.autoBasicLands)
        compare(builder.basicValue("Swamp"), 19)
        compare(builder.basicValue("Island"), 0)
        wait(0)
        compare(builder.basicValue("Swamp"), 19)
    }
    function test_nativeDraftStorePreservesAutomaticSetting() {
        testLimitedDraftStore.saveDraft(connection.serverUrl, "AUTO-LANDS", "p-1", {
            mainboardInstanceIds: ["u"], basics: {Island: 39},
            initialPoolChosen: true, autoBasicLands: true
        })
        const builder = createTemporaryObject(builderComponent, window.contentItem, {
            draftStore: testLimitedDraftStore
        })
        verify(builder.autoBasicLands)
        compare(builder.basicValue("Island"), 39)
        builder.adjustBasic("Island", -1)
        verify(!testLimitedDraftStore.loadDraft(connection.serverUrl, "AUTO-LANDS", "p-1").autoBasicLands)
        testLimitedDraftStore.removeDraft(connection.serverUrl, "AUTO-LANDS", "p-1")
    }
    function test_unresolvedDeckShowsManualGuidance() {
        limitedState.pool = [{instanceId: "unknown", name: "Unknown spell"}]
        const builder = createTemporaryObject(builderComponent, window.contentItem)
        builder.moveToMainDeck("unknown")
        compare(builder.countBasics(), 0)
        verify(findChild(builder, "limitedAutoBasicLandsGuidance").visible)
        builder.adjustBasic("Forest", 17)
        verify(!findChild(builder, "limitedAutoBasicLandsGuidance").visible)
    }
}
