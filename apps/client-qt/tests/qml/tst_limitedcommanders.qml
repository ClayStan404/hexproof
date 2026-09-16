// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic
import QtTest
import "../../qml/components"
import "../../qml/screens" as Screens

TestCase {
    id: testCase
    name: "LimitedCommanders"
    when: windowShown
    ApplicationWindow { id: window; width: 900; height: 620; visible: true }
    QtObject {
        id: limitedState
        signal snapshotChanged()
        property string tournamentId: "COMMANDER"
        property string eventType: "commander_cube"
        property string stage: "deck_building"
        property int minimumDeckCards: 60
        property int packRound: 1
        property int direction: 1
        property var currentPack: []
        property bool deckSubmitted: false
        property bool allDecksSubmitted: false
        property var mainboardInstanceIds: []
        property var commanderInstanceIds: []
        property var commanderColors: []
        property var fallbackCommanders: []
        property var optionalCards: []
        property var basicLands: []
        property var participants: []
        property var pool: []
    }
    QtObject {
        id: connection
        signal commandFailed(string requestId, string commandType, var payload, string message)
        property string serverUrl: "ws://localhost:57320/ws"
        property bool connected: true
        property string lastError: ""
        property var submission: ({})
        property int submitCount: 0
        function submitLimitedCommanderDeck(name, ids, lands, commanders, colors) {
            submitCount++
            submission = {name: name, ids: ids.slice(), lands: lands.slice(), commanders: commanders.slice(), colors: colors.slice()}
        }
        function submitLimitedDeck(name, ids, lands) {
            submitCount++
            submission = {name: name, ids: ids.slice(), lands: lands.slice()}
        }
    }
    QtObject {
        id: catalog
        signal catalogChanged()
        property int imageRevision: 0
        function tableImageSource() { return "" }
        function cacheCardsIncrementally() { }
        function enrichLimitedCards(cards) { return cards }
    }
    QtObject {
        id: store
        property var entry: ({})
        property string lastError: ""
        function loadDraft() { return entry }
        function saveDraft(server, event, seat, draft) { entry = JSON.parse(JSON.stringify(draft)) }
        function removeDraft() { entry = ({}) }
    }
    Component {
        id: builderComponent
        LimitedDeckBuilder {
            width: 900; height: 620
            limitedModel: limitedState
            wsModel: connection
            cardCatalogModel: catalog
            draftStore: store
            participantId: "p-1"
        }
    }
    QtObject {
        id: roomState
        signal snapshotChanged()
        signal chatChanged()
        signal inTournamentChanged()
        property string tournamentId: limitedState.tournamentId
        property string name: "Commander Cube layout regression"
        property string eventType: limitedState.eventType
        property string stage: limitedState.stage
        property string status: "running"
        property string role: "organizer"
        property string participantId: "p-1"
        property string organizerName: "Player"
        property string coordinator: "casual"
        property string matchMode: "bo1"
        property int maxPlayers: 4
        property var participants: [{participantId: "p-1", displayName: "Player", online: true, competing: true}]
        property var pairings: []
        property var chatMessages: []
    }
    Component {
        id: cubeComponent
        Screens.CubeRoom {
            anchors.fill: parent
            tournamentModel: roomState
            limitedModel: limitedState
            wsModel: connection
            cardCatalogModel: catalog
        }
    }
    LimitedCommanderSelection { id: selection }

    function init() {
        Theme.uiScale = 1
        window.width = 900
        window.height = 620
        limitedState.eventType = "commander_cube"
        limitedState.minimumDeckCards = 60
        limitedState.stage = "deck_building"
        limitedState.deckSubmitted = false
        limitedState.mainboardInstanceIds = []
        limitedState.commanderInstanceIds = []
        limitedState.commanderColors = []
        limitedState.fallbackCommanders = []
        limitedState.optionalCards = []
        limitedState.basicLands = []
        limitedState.pool = [
            {instanceId: "a", name: "Captain", displayName: "Captain localized", setCode: "NEW", collectorNumber: "20",
             typeLine: "Legendary Creature — Human", colors: "GU", cardColors: "G", manaCost: "{2}{G}"},
            {instanceId: "a2", name: "Captain", setCode: "OLD", collectorNumber: "1",
             typeLine: "Legendary Creature — Human", colors: "GU", cardColors: "G", manaCost: "{2}{G}"},
            {instanceId: "b", name: "Second Captain", setCode: "NEW", collectorNumber: "21",
             typeLine: "Legendary Creature — Elf", colors: "U", cardColors: "U", manaCost: "{U}"},
            {instanceId: "c", name: "Red Spell", setCode: "NEW", collectorNumber: "22",
             typeLine: "Sorcery", colors: "R", cardColors: "R", manaCost: "{R}"}
        ]
        store.entry = ({})
        connection.submission = ({})
        connection.submitCount = 0
    }

    function cleanup() { Theme.uiScale = 1 }

    function test_optionalStaplesAreOptInAndRestoreWithConstruction() {
        limitedState.optionalCards = [
            {instanceId: "sol", name: "Sol Ring", typeLine: "Artifact", manaCost: "{1}", cardColors: "", colors: ""},
            {instanceId: "tower", name: "Command Tower", typeLine: "Land", cardColors: "", colors: ""},
            {instanceId: "signet", name: "Arcane Signet", typeLine: "Artifact", manaCost: "{2}", cardColors: "", colors: ""}
        ]
        const view = builder()
        view.chooseInitialPool(true)
        view.toggleCommander("a")
        compare(view.selectedOptionalCards.length, 0)
        compare(view.sideboardCards.length, 0)
        verify(!findChild(view, "limitedOptionalCardsPanel").visible)
        findChild(view, "limitedBasicLandsButton").clicked()
        tryCompare(findChild(view, "limitedBasicLandsPopup"), "opened", true)
        verify(findChild(view, "limitedOptionalCardsPanel").visible)
        const popup = findChild(view, "limitedBasicLandsPopup")
        for (const card of limitedState.optionalCards) findVisual(popup, "limitedOptionalCard-" + card.instanceId).clicked()
        compare(view.selectedOptionalCards.length, 3)
        findChild(view, "limitedBasicLandsDone").clicked()
        verify(findChild(view, "limitedCommanderPicker").cards.every(card =>
            !limitedState.optionalCards.some(optional => optional.instanceId === card.instanceId)))
        compare(view.mainDeckCards.length, 7)
        view.moveToMainDeck("sol")
        compare(view.mainDeckCards.length, 7)
        view.moveToMainDeck("forged")
        compare(view.mainDeckCards.length, 7)
        view.toggleCommander("sol")
        compare(view.commanderInstanceIds.join(","), "a")
        const restored = builder()
        compare(restored.selectedOptionalCards.length, 3)
        compare(restored.mainDeckCards.length, 7)
        restored.submit()
        compare(connection.submission.ids.length, 7)
        for (const id of ["sol", "tower", "signet"]) verify(connection.submission.ids.indexOf(id) >= 0)
        limitedState.mainboardInstanceIds = connection.submission.ids
        limitedState.commanderInstanceIds = connection.submission.commanders
        limitedState.basicLands = connection.submission.lands
        limitedState.deckSubmitted = true
        limitedState.snapshotChanged()
        const submitted = builder()
        compare(submitted.selectedOptionalCards.length, 3)
        submitted.moveToSideboard("sol")
        compare(submitted.selectedOptionalCards.length, 2)
        compare(submitted.sideboardCards.length, 0)
        verify(submitted.hasUnsubmittedChanges)
        submitted.discardUnsubmittedChanges()
        compare(submitted.selectedOptionalCards.length, 3)
    }

    function builder() {
        const result = createTemporaryObject(builderComponent, window.contentItem)
        verify(result)
        return result
    }

    function findVisual(item, name) {
        if (item.objectName === name) return item
        if (item.contentItem && item.contentItem !== item) {
            const found = findVisual(item.contentItem, name)
            if (found) return found
        }
        for (const child of item.children || []) {
            const found = findVisual(child, name)
            if (found) return found
        }
        return null
    }

    function test_targetIncludesCommandersOnceAndSubmissionUsesExactIds() {
        const view = builder()
        view.chooseInitialPool(true)
        compare(view.selectedPoolCount, 4)
        compare(view.selectedCount, 60)
        compare(view.countBasics(), 56)
        verify(!view.commandersValid)
        view.submit()
        compare(Object.keys(connection.submission).length, 0)
        view.toggleCommander("a2")
        view.toggleCommander("b")
        compare(view.commanderInstanceIds, ["a2", "b"])
        compare(view.selectedCount, 60)
        compare(view.countBasics(), 56)
        view.submit()
        compare(connection.submission.commanders, ["a2", "b"])
        compare(connection.submission.ids.length, 4)
        compare(connection.submission.ids.filter(id => id === "a2").length, 1)
        verify(view.commanderAdvice.some(message => message.indexOf("outside") >= 0))
    }

    function test_maximumDistinctInstancesAndNoForeignCommander() {
        const view = builder()
        view.chooseInitialPool(true)
        view.toggleCommander("a")
        view.toggleCommander("a2")
        compare(view.commanderInstanceIds, ["a", "a2"])
        view.toggleCommander("b")
        view.toggleCommander("c")
        view.toggleCommander("foreign")
        compare(view.commanderInstanceIds, ["a", "a2"])
        view.moveToSideboard("a")
        compare(view.commanderInstanceIds, ["a2"])
        view.toggleCommander("a")
        compare(view.commanderInstanceIds, ["a2", "a"])
        verify(view.cardSelected("a"))
        view.toggleCommander("a")
        view.toggleCommander("a2")
        compare(view.commanderInstanceIds, [])
        verify(!view.commandersValid)
    }

    function test_commanderCandidatesUseLocalizedTypesAndFiltersBeforeAddingToDeck() {
        limitedState.pool = limitedState.pool.concat([
            {instanceId: "zh", name: "Goblin Captain", displayName: "地精队长", typeLine: "传奇生物～地精／战士",
             colors: "R", cardColors: "R", manaValue: 3, rarity: "mythic"},
            {instanceId: "zh-land", name: "Legendary land", typeLine: "传奇地", colors: "", manaValue: 0},
            {instanceId: "walker", name: "Eligible Walker", typeLine: "传奇鹏洛客～测试",
             oracleText: "Eligible Walker can be your commander.", colors: "U", manaValue: 4},
            {instanceId: "unknown", name: "Unknown metadata"}
        ])
        const view = builder()
        view.chooseInitialPool(false)
        const picker = findChild(view, "limitedCommanderPicker")
        verify(picker.visibleCards.some(card => card.instanceId === "zh"))
        verify(picker.visibleCards.some(card => card.instanceId === "walker"))
        verify(picker.visibleCards.some(card => card.instanceId === "unknown"))
        verify(!picker.visibleCards.some(card => card.instanceId === "zh-land" || card.instanceId === "c"))
        picker.filters.colors = ["R"]
        picker.filters.types = ["Creature"]
        picker.filters.manaValues = ["3"]
        picker.filters.rarities = ["mythic"]
        picker.filters.query = "地精"
        compare(picker.visibleCards.map(card => card.instanceId), ["zh"])
        compare(view.selectedPoolCount, 0)
        picker.toggleRequested("zh")
        compare(view.commanderInstanceIds, ["zh"])
        compare(view.selectedPoolCount, 1)
        compare(view.selectedLandCount, 59)
        verify(!view.commanderAdvice.some(message => message.indexOf("allows") >= 0))
        verify(view.cardSelected("zh"))
        picker.filters.reset()
        picker.filters.query = "Red Spell"
        compare(picker.visibleCards.length, 0)
        picker.showAll = true
        compare(picker.visibleCards.map(card => card.instanceId), ["c"])
        compare(view.selectedPoolCount, 1)
        picker.toggleRequested("c")
        compare(view.commanderInstanceIds, ["zh", "c"])
        verify(view.cardSelected("c"))
        picker.toggleRequested("a")
        verify(!view.cardSelected("a"), "A rejected third commander must not modify the main deck")
    }

    function test_localizedLandCountsIncludeAllLandsAndIgnoreGoblinSubtypes() {
        limitedState.pool = []
        const pool = []
        for (let index = 0; index < 120; ++index) {
            pool.push({instanceId: "mixed-" + index, name: "Mixed " + index,
                typeLine: index < 24 ? (index % 2 ? "地～树林／海岛" : "传奇地") : "生物～地精／战士",
                colors: index < 24 ? "" : "R", cardColors: index < 24 ? "" : "R", manaValue: index < 24 ? 0 : 2,
                manaCost: index < 24 ? "" : "{1}{R}"})
        }
        limitedState.pool = pool
        const view = builder()
        view.chooseInitialPool(true)
        compare(view.selectedCount, 120)
        compare(view.selectedLandCount, 24)
        compare(view.selectedNonlandCount, 96)
        view.mainFilters.types = ["Land"]
        compare(view.visibleDeckListCards.length, 24)
        compare(view.selectedLandCount, 24)
        view.mainFilters.types = ["Creature"]
        compare(view.visibleDeckListCards.length, 96)
        compare(view.selectedLandCount, 24)
        view.adjustBasic("Island", 2)
        compare(view.selectedLandCount, 26)
        compare(view.selectedNonlandCount, 96)
        view.mainFilters.types = ["Land"]
        view.mainFilters.colors = ["U"]
        compare(view.visibleDeckListCards.length, 1)
        verify(view.visibleDeckListCards[0].virtualBasic)
        compare(view.visibleDeckListCards[0].count, 2)
    }

    function test_manualEDHUnusualCommanderAndColorMismatchNeverBlock() {
        const view = builder()
        view.chooseInitialPool(true)
        view.toggleCommander("c")
        verify(view.commandersValid)
        verify(view.commanderAdvice.some(message => message.indexOf("allows") >= 0))
        verify(view.commanderAdvice.some(message => message.indexOf("outside") >= 0))
        verify(findChild(view, "limitedSubmitDeckButton").enabled)
        view.submit()
        compare(connection.submission.commanders, ["c"])
    }

    function test_autoLand60PlusKeepsPhysicalCardsAndManualOverride() {
        const cards = []
        for (let index = 0; index < 61; ++index)
            cards.push({instanceId: "card-" + index, name: "Card " + index, manaCost: "{G}", cardColors: "G"})
        limitedState.pool = cards
        const view = builder()
        view.chooseInitialPool(true)
        view.toggleCommander("card-0")
        compare(view.selectedCount, 61)
        compare(view.countBasics(), 0)
        view.moveToSideboard("card-1")
        compare(view.countBasics(), 0)
        view.moveToSideboard("card-2")
        compare(view.basicValue("Forest"), 1)
        view.adjustBasic("Island", 2)
        verify(!view.autoBasicLands)
        view.moveToSideboard("card-3")
        catalog.catalogChanged()
        wait(0)
        compare(view.basicValue("Forest"), 1)
        compare(view.basicValue("Island"), 2)
    }

    function test_savedDraftIntersectsCommandersWithSelectedPoolAndPersists() {
        store.entry = {mainboardInstanceIds: ["a", "a2", "b"], commanderInstanceIds: ["gone", "c", "a2", "a", "b"],
                       basics: {Island: 57}, initialPoolChosen: true, autoBasicLands: false}
        const view = builder()
        compare(view.commanderInstanceIds, ["a2", "a"])
        compare(view.selectedCount, 60)
        verify(!view.autoBasicLands)
        view.toggleCommander("a2")
        compare(store.entry.commanderInstanceIds, ["a"])
        view.moveToSideboard("a")
        compare(store.entry.commanderInstanceIds, [])
    }

    function test_submittedRestorationDirtyAndDiscardIncludeCommanders() {
        limitedState.deckSubmitted = true
        limitedState.mainboardInstanceIds = ["a", "b", "c"]
        limitedState.commanderInstanceIds = ["a"]
        limitedState.basicLands = [{name: "Forest", count: 57}]
        const view = builder()
        compare(view.commanderInstanceIds, ["a"])
        verify(!view.hasUnsubmittedChanges)
        view.toggleCommander("a")
        view.toggleCommander("b")
        verify(view.hasUnsubmittedChanges)
        limitedState.snapshotChanged()
        compare(view.commanderInstanceIds, ["b"])
        view.visible = false
        compare(view.commanderInstanceIds, ["b"])
        view.visible = true
        view.discardUnsubmittedChanges()
        compare(view.commanderInstanceIds, ["a"])
        verify(!view.hasUnsubmittedChanges)
        verify(!view.autoBasicLands)
    }

    function acknowledge(submission) {
        limitedState.mainboardInstanceIds = submission.ids.slice()
        limitedState.commanderInstanceIds = submission.commanders.slice()
        limitedState.commanderColors = submission.colors.slice()
        limitedState.basicLands = submission.lands.slice()
        limitedState.deckSubmitted = true
        limitedState.snapshotChanged()
    }

    function test_firstSubmissionAcknowledgementPreservesLaterCommanderEdit() {
        const view = builder()
        view.chooseInitialPool(true)
        view.toggleCommander("a")
        view.submit()
        const first = connection.submission
        view.toggleCommander("a")
        view.toggleCommander("b")
        acknowledge(first)
        compare(view.commanderInstanceIds, ["b"])
        verify(view.hasUnsubmittedChanges)
        compare(store.entry.commanderInstanceIds, ["b"])
        limitedState.snapshotChanged()
        compare(view.commanderInstanceIds, ["b"])
        verify(view.hasUnsubmittedChanges)
        compare(store.entry.commanderInstanceIds, ["b"])
        view.submit()
        acknowledge(connection.submission)
        compare(view.commanderInstanceIds, ["b"])
        verify(!view.hasUnsubmittedChanges)
        compare(Object.keys(store.entry).length, 0)
    }

    function test_firstAcknowledgementWithoutLaterEditsClearsLocalDraft() {
        const view = builder()
        view.chooseInitialPool(true)
        view.toggleCommander("a")
        view.submit()
        acknowledge(connection.submission)
        compare(view.commanderInstanceIds, ["a"])
        verify(!view.hasUnsubmittedChanges)
        verify(!view.autoBasicLands)
        compare(Object.keys(store.entry).length, 0)
    }

    function test_reconnectedViewRestoresAuthoritativeFirstSubmission() {
        limitedState.deckSubmitted = true
        limitedState.mainboardInstanceIds = ["a", "b", "c"]
        limitedState.commanderInstanceIds = ["a"]
        limitedState.basicLands = [{name: "Forest", count: 57}]
        store.entry = {mainboardInstanceIds: ["b", "c"], commanderInstanceIds: ["b"],
                       basics: {Island: 58}, initialPoolChosen: true}
        const view = builder()
        compare(view.commanderInstanceIds, ["a"])
        compare(Object.keys(view.selectedCards).sort(), ["a", "b", "c"])
        compare(view.basicValue("Forest"), 57)
        verify(!view.hasUnsubmittedChanges)
        compare(Object.keys(store.entry).length, 0)
    }

    function test_submissionErrorAllowsRetryAndAcceptsLatestUnchangedDraft() {
        const view = builder()
        view.chooseInitialPool(true)
        view.toggleCommander("a")
        view.submit()
        connection.commandFailed("first", "limited.submit_deck", {}, "Test rejection")
        view.toggleCommander("a")
        view.toggleCommander("b")
        verify(findChild(view, "limitedSubmitDeckButton").enabled)
        view.submit()
        compare(connection.submitCount, 2)
        acknowledge(connection.submission)
        compare(view.commanderInstanceIds, ["b"])
        verify(!view.hasUnsubmittedChanges)
        compare(Object.keys(store.entry).length, 0)
    }

    function test_earlierAcknowledgementPreservesEditsAfterRepeatedSubmissions() {
        const view = builder()
        view.chooseInitialPool(true)
        view.toggleCommander("a")
        view.submit()
        const first = connection.submission
        view.toggleCommander("a")
        view.toggleCommander("b")
        view.submit()
        const second = connection.submission
        view.moveToSideboard("c")
        view.adjustBasic("Forest", 1)
        const selected = Object.keys(view.selectedCards).sort()
        const lands = JSON.stringify(view.basics)
        acknowledge(first)
        compare(view.commanderInstanceIds, ["b"])
        compare(Object.keys(view.selectedCards).sort(), selected)
        compare(JSON.stringify(view.basics), lands)
        verify(view.hasUnsubmittedChanges)
        acknowledge(second)
        compare(view.commanderInstanceIds, ["b"])
        compare(Object.keys(view.selectedCards).sort(), selected)
        compare(JSON.stringify(view.basics), lands)
        verify(view.hasUnsubmittedChanges)
    }

    function test_identityUsesCatalogIdentityNotFaceColorsAndUnknownDoesNotInvent() {
        const cards = limitedState.pool.slice(0, 3)
        const warnings = selection.advisory(cards, ["a"], {Island: 57})
        compare(warnings.length, 0)
        const colorless = [{instanceId: "zero", name: "Colorless Captain", typeLine: "Legendary Creature", colors: "", cardColors: "R"}]
        verify(selection.advisory(colorless, ["zero"], {Mountain: 10})[0].indexOf("10") >= 0)
        const unknown = [{instanceId: "unknown", name: "Unknown Captain", typeLine: "Legendary Creature", cardColors: "R"}]
        verify(selection.advisory(unknown, ["unknown"], {Island: 10})[0].indexOf("unavailable") >= 0)
    }

    function piper(id) {
        // Match the wire card shape, deliberately without local catalog metadata.
        return {instanceId: id, name: "The Prismatic Piper", setCode: "CMR", collectorNumber: "1", rarity: "special"}
    }

    function enableFallback() {
        limitedState.fallbackCommanders = [piper("fallback-1"), piper("fallback-2")]
    }

    function test_fallbackAddsOnlySelectedCommandersAndCountsTowardTarget() {
        enableFallback()
        const view = builder()
        view.chooseInitialPool(true)
        compare(view.selectedFallbackCommanders.length, 0)
        view.moveToMainDeck("fallback-1")
        compare(view.selectedPoolCount, 4, "Fallback must not become an ordinary physical pick")
        view.toggleCommander("fallback-1")
        view.toggleCommander("fallback-2")
        view.toggleCommander("a")
        compare(view.commanderInstanceIds, ["fallback-1", "fallback-2"])
        compare(view.selectedFallbackCommanders.length, 2)
        compare(view.mainDeckCards.length, 6)
        compare(view.selectedCount, 60)
        compare(view.countBasics(), 54)
        compare(view.sideboardCards.length, 0)
        verify(!view.commandersValid)
        verify(!findChild(view, "limitedSubmitDeckButton").enabled)
        view.submit()
        compare(connection.submitCount, 0)
        view.setCommanderColor("fallback-1", "U")
        view.setCommanderColor("fallback-2", "G")
        verify(view.commandersValid)
        compare(view.mainDeckCards.filter(card => card.fallbackCommander)[0].cardColors, "")
        compare(view.mainDeckCards.filter(card => card.fallbackCommander)[0].manaCost, "{5}")
        verify(!view.commanderAdvice.some(message => message.indexOf("unavailable") >= 0))
        view.submit()
        compare(connection.submission.ids.sort(), ["a", "a2", "b", "c"])
        compare(connection.submission.colors, [{instanceId: "fallback-1", color: "U"}, {instanceId: "fallback-2", color: "G"}])
        view.removeFromMainDeck(view.selectedFallbackCommanders[0])
        compare(view.commanderInstanceIds, ["fallback-2"])
        compare(view.commanderColors, [{instanceId: "fallback-2", color: "G"}])
        compare(view.sideboardCards.length, 0)
        compare(view.countBasics(), 55)
        compare(view.selectedCount, 60)
    }

    function test_draftedPipersAllowDuplicateNamesAndRequireColorToo() {
        enableFallback()
        limitedState.pool = limitedState.pool.concat([piper("drafted-1"), piper("drafted-2")])
        const view = builder()
        view.chooseInitialPool(true)
        view.toggleCommander("drafted-1")
        view.toggleCommander("drafted-2")
        compare(view.commanderInstanceIds, ["drafted-1", "drafted-2"])
        view.setCommanderColor("drafted-1", "B")
        view.setCommanderColor("drafted-2", "R")
        verify(view.commandersValid)
        compare(view.selectedFallbackCommanders.length, 0)
        compare(view.selectedCount, 60)
        compare(view.countBasics(), 54)
        view.submit()
        compare(connection.submission.ids.length, 6)
        compare(connection.submission.colors.length, 2)
        view.moveToSideboard("drafted-1")
        compare(view.commanderColors, [{instanceId: "drafted-2", color: "R"}])
        compare(view.sideboardCards.length, 1)
        compare(selection.sanitize(["drafted-1", "drafted-1", "drafted-2"], limitedState.pool), ["drafted-1", "drafted-2"])
    }

    function test_colorChoiceChangesIdentityNotPrintedManaDemand() {
        const cards = [piper("p"), {instanceId: "g", name: "Green spell", colors: "G"}]
        verify(selection.advisory(cards, ["p"], {Forest: 58}, [{instanceId: "p", color: "G"}]).length === 0)
        verify(selection.advisory(cards, ["p"], {Forest: 58}, [{instanceId: "p", color: "U"}])
            .some(message => message.indexOf("59") >= 0 && message.indexOf("outside") >= 0))
        const decorated = selection.withColor(cards[0], [{instanceId: "p", color: "G"}])
        compare(decorated.colors, "G")
        compare(decorated.cardColors, "")
        compare(decorated.manaCost, "{5}")
    }

    function test_fallbackRowsStaySeparateFromIdenticalDraftedPrinting() {
        enableFallback()
        limitedState.pool = limitedState.pool.concat([piper("drafted")])
        const view = builder()
        view.chooseInitialPool(true)
        view.toggleCommander("drafted")
        view.toggleCommander("fallback-1")
        view.setCommanderColor("drafted", "G")
        view.setCommanderColor("fallback-1", "G")
        const list = findChild(view, "limitedMainDeckGrid")
        const rows = list.rows.filter(row => row.card.name === "The Prismatic Piper")
        compare(rows.length, 2, "A fallback must not merge with a drafted copy that can move to the sideboard")
        verify(rows.some(row => row.card.fallbackCommander))
        view.removeFromMainDeck(rows.find(row => row.card.fallbackCommander).card)
        compare(view.selectedPoolCount, 5)
        compare(view.selectedFallbackCommanders.length, 0)
        compare(view.commanderInstanceIds, ["drafted"])
        compare(view.sideboardCards.length, 0)
    }

    function test_localFallbackDraftRestoresColorsAndRejectsStaleOrInvalidChoices() {
        enableFallback()
        store.entry = {mainboardInstanceIds: ["a", "b", "c"], commanderInstanceIds: ["gone", "fallback-1", "fallback-2"],
            commanderColors: [null, false, 7, "invalid", {}, {instanceId: "fallback-1", color: "U"}, {instanceId: "fallback-2", color: "UG"},
                {instanceId: "gone", color: "R"}], basics: {Island: 55}, initialPoolChosen: true, autoBasicLands: false}
        const view = builder()
        compare(view.commanderInstanceIds, ["fallback-1", "fallback-2"])
        compare(view.commanderColors, [{instanceId: "fallback-1", color: "U"}])
        compare(view.selectedCount, 60)
        verify(!view.commandersValid)
        view.setCommanderColor("fallback-2", "C")
        view.setCommanderColor("a", "G")
        verify(!view.commandersValid)
        view.setCommanderColor("fallback-2", "G")
        verify(view.commandersValid)
        compare(store.entry.commanderColors, view.commanderColors)
        limitedState.snapshotChanged()
        catalog.catalogChanged()
        wait(0)
        compare(view.commanderColors, [{instanceId: "fallback-1", color: "U"}, {instanceId: "fallback-2", color: "G"}])
        view.discardUnsubmittedChanges()
        compare(view.commanderColors, [])
        compare(view.selectedFallbackCommanders.length, 0)
        compare(Object.keys(store.entry).length, 0)
    }

    function test_colorOnlyEditSurvivesFirstAcknowledgementAndDiscardRestoresSnapshot() {
        enableFallback()
        const view = builder()
        view.chooseInitialPool(true)
        view.toggleCommander("fallback-1")
        view.setCommanderColor("fallback-1", "G")
        view.submit()
        const first = connection.submission
        view.setCommanderColor("fallback-1", "U")
        acknowledge(first)
        compare(view.commanderColors, [{instanceId: "fallback-1", color: "U"}])
        verify(view.hasUnsubmittedChanges)
        limitedState.snapshotChanged()
        compare(view.commanderColors, [{instanceId: "fallback-1", color: "U"}])
        view.discardUnsubmittedChanges()
        compare(view.commanderColors, [{instanceId: "fallback-1", color: "G"}])
        compare(view.selectedFallbackCommanders.length, 1)
        compare(view.selectedPoolCount, 4)
        verify(!view.hasUnsubmittedChanges)
        view.setCommanderColor("fallback-1", "B")
        verify(view.hasUnsubmittedChanges)
        view.submit()
        acknowledge(connection.submission)
        verify(!view.hasUnsubmittedChanges)
    }

    function test_reentryRestoresBothFallbackInstancesAndTheirColors() {
        enableFallback()
        limitedState.deckSubmitted = true
        limitedState.mainboardInstanceIds = ["a", "b", "c"]
        limitedState.commanderInstanceIds = ["fallback-1", "fallback-2"]
        limitedState.commanderColors = [{instanceId: "fallback-2", color: "G"}, {instanceId: "fallback-1", color: "U"}]
        limitedState.basicLands = [{name: "Island", count: 55}]
        const view = builder()
        compare(view.selectedPoolCount, 3)
        compare(view.selectedFallbackCommanders.length, 2)
        compare(view.selectedCount, 60)
        verify(view.commandersValid)
        verify(!view.hasUnsubmittedChanges)
    }

    function test_ordinaryDraftIgnoresFallbackAndKeepsFortyCardSubmission() {
        enableFallback()
        limitedState.eventType = "cube_draft"
        limitedState.minimumDeckCards = 40
        const view = builder()
        view.chooseInitialPool(true)
        view.toggleCommander("fallback-1")
        view.setCommanderColor("fallback-1", "G")
        compare(view.fallbackCommanders.length, 0)
        compare(view.commanderInstanceIds.length, 0)
        compare(view.commanderColors.length, 0)
        compare(view.selectedCount, 40)
        view.submit()
        compare(connection.submitCount, 1)
        verify(connection.submission.commanders === undefined)
    }

    function test_fallbackPickerScrollAndColorControlsFitCompactWindow() {
        enableFallback()
        Theme.uiScale = 1.35
        const view = builder()
        view.chooseInitialPool(true)
        view.toggleCommander("fallback-1")
        view.toggleCommander("fallback-2")
        mouseClick(findChild(view, "limitedCommandersButton"))
        const picker = findChild(view, "limitedCommanderPicker")
        tryCompare(picker, "opened", true)
        const scroll = findChild(picker, "limitedCommanderScroll")
        waitForRendering(picker.contentItem)
        verify(scroll.contentItem.contentHeight > scroll.height)
        const color = findVisual(picker, "limitedCommanderColor-fallback-2-G")
        verify(color)
        const point = color.mapToItem(scroll.contentItem.contentItem, 0, 0)
        scroll.contentItem.contentY = Math.min(point.y, scroll.contentItem.contentHeight - scroll.contentItem.height)
        waitForRendering(color)
        mouseClick(color)
        compare(view.commanderColors, [{instanceId: "fallback-2", color: "G"}])
        const done = findChild(picker, "limitedCommanderDone")
        const donePoint = done.mapToItem(window.contentItem, 0, 0)
        verify(donePoint.y >= 0 && donePoint.y + done.height <= window.height)
        mouseClick(done)
        tryCompare(picker, "opened", false)
    }

    function test_pickerFitsMinimumWindowAndSelectsExactPrinting() {
        const view = builder()
        view.chooseInitialPool(true)
        const open = findChild(view, "limitedCommandersButton")
        mouseClick(open)
        const picker = findChild(view, "limitedCommanderPicker")
        tryCompare(picker, "opened", true)
        waitForRendering(picker.contentItem)
        verify(picker.y >= 0 && picker.y + picker.height <= window.height)
        const done = findChild(picker, "limitedCommanderDone")
        const donePoint = done.mapToItem(window.contentItem, done.width / 2, done.height / 2)
        verify(donePoint.y > 0 && donePoint.y < window.height)
        const choose = findVisual(picker, "limitedCommanderToggle-a2")
        verify(choose)
        waitForRendering(choose)
        mouseClick(choose)
        compare(view.commanderInstanceIds, ["a2"])
        mouseClick(done)
        tryCompare(picker, "opened", false)
    }

    function test_compactScaledWorkspaceKeepsDeckListAndActionsReachable_data() {
        return [{tag: "minimum-scaled", width: 900, height: 620, scale: 1.35, missingMetadata: false},
                {tag: "minimum-scaled-missing-metadata", width: 900, height: 620, scale: 1.35, missingMetadata: true},
                {tag: "minimum-scaled-competition-dirty", width: 900, height: 620, scale: 1.35, competing: true},
                {tag: "wide-two-columns", width: 1280, height: 800, scale: 1, missingMetadata: false}]
    }

    function test_compactScaledWorkspaceKeepsDeckListAndActionsReachable(data) {
        window.width = data.width
        window.height = data.height
        Theme.uiScale = data.scale
        if (data.missingMetadata) {
            limitedState.pool = limitedState.pool.map(card => {
                const copy = Object.assign({}, card)
                delete copy.cardColors
                delete copy.manaCost
                return copy
            })
        }
        if (data.competing) {
            limitedState.stage = "competition"
            limitedState.deckSubmitted = true
            limitedState.mainboardInstanceIds = ["a", "a2", "b", "c"]
            limitedState.commanderInstanceIds = ["a"]
            limitedState.basicLands = [{name: "Forest", count: 56}]
        }
        const page = createTemporaryObject(cubeComponent, window.contentItem)
        verify(page)
        const view = findChild(page, "cubeDeckWorkspace")
        verify(view)
        view.draftStore = store
        view.chooseInitialPool(true)
        if (!data.competing) view.toggleCommander("a")
        else {
            page.editingDeck = true
            view.adjustBasic("Forest", 1)
        }
        waitForRendering(page)
        const tabs = findChild(view, "limitedWorkspaceTabs")
        const available = findChild(view, "limitedSideboardGrid")
        const list = findChild(view, "limitedMainDeckGrid")
        if (data.width === 900) {
            verify(view.width < 800 && view.height < 500, "Use the real CubeRoom workspace after all page chrome")
            verify(tabs.visible)
            compare(view.compactPaneIndex, 0)
            verify(available.visible && available.height >= Theme.size(32),
                   "Pool list=" + available.height + ", workspace=" + view.width + "x" + view.height)
            mouseClick(tabs, tabs.width * 0.75, tabs.height / 2)
            tryCompare(view, "compactPaneIndex", 1)
            compare(list.dropTarget, null, "Dragging to a hidden pool must not silently do nothing")
        } else {
            verify(!tabs.visible)
            verify(available.visible && list.visible)
            verify(list.dropTarget !== null, "Wide layout keeps drag-and-drop to its visible pool")
        }
        waitForRendering(view)
        verify(list.height >= Theme.size(44), "The main deck list collapsed to " + list.height)
        if (data.competing)
            compare(findChild(view, "limitedDeckSubmissionStatus").text, "Unsubmitted deck changes")
        for (const name of ["limitedCommandersButton", "limitedBasicLandsButton", "limitedSubmitDeckButton"]) {
            const action = findChild(view, name)
            verify(action.visible)
            const corner = action.mapToItem(view, 0, 0)
            verify(corner.x >= 0 && corner.x + action.width <= view.width + 1
                   && corner.y >= 0 && corner.y + action.height <= view.height + 1,
                   name + " overflowed: y=" + corner.y + ", height=" + action.height)
        }
        mouseClick(findChild(view, "limitedCommandersButton"))
        const picker = findChild(view, "limitedCommanderPicker")
        tryCompare(picker, "opened", true)
        const done = findChild(picker, "limitedCommanderDone")
        const donePoint = done.mapToItem(window.contentItem, done.width / 2, done.height / 2)
        verify(donePoint.y > 0 && donePoint.y < window.height)
        mouseClick(done)
        tryCompare(picker, "opened", false)
        mouseClick(findChild(view, "limitedBasicLandsButton"))
        tryCompare(view, "basicLandsExpanded", true)
        const basicsPopup = findChild(view, "limitedBasicLandsPopup")
        const basicsDone = findChild(basicsPopup, "limitedBasicLandsDone")
        const basicsDonePoint = basicsDone.mapToItem(window.contentItem, basicsDone.width / 2, basicsDone.height / 2)
        verify(basicsDonePoint.y > 0 && basicsDonePoint.y < window.height)
        mouseClick(basicsDone)
        tryCompare(basicsPopup, "opened", false)
        waitForRendering(view)
        const before = view.selectedPoolCount
        list.positionViewAtBeginning()
        waitForRendering(list)
        verify(list.itemAtIndex(0))
        const first = list.itemAtIndex(0)
        const firstId = first.card.instanceId
        mouseClick(first, first.width / 2, first.height / 2)
        compare(view.selectedPoolCount, before - 1)
        if (tabs.visible) {
            compare(tabs.options[0], "Pool · 1")
            waitForRendering(tabs)
            mouseClick(tabs, tabs.width * 0.25, tabs.height / 2)
            tryCompare(view, "compactPaneIndex", 0)
        }
        waitForRendering(available)
        const tile = findVisual(available, "limitedCardTile-" + firstId)
        verify(tile)
        mouseClick(tile, tile.width / 2, Math.min(tile.height / 2, available.height / 2))
        compare(view.selectedPoolCount, before)
        if (tabs.visible) {
            waitForRendering(tabs)
            mouseClick(tabs, tabs.width * 0.75, tabs.height / 2)
            tryCompare(view, "compactPaneIndex", 1)
        }
        if (view.commanderInstanceIds.length === 0) view.toggleCommander("a")
        if (view.selectedCount < 60) view.adjustBasic("Forest", 60 - view.selectedCount)
        waitForRendering(view)
        const submit = findChild(view, "limitedSubmitDeckButton")
        verify(submit.enabled)
        mouseClick(submit)
        compare(connection.submitCount, 1)
    }
}
