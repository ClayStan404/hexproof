// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic
import QtTest
import "../../qml/screens"
import "../../qml/components"

TestCase {
    name: "CreateRoom"
    when: windowShown

    ApplicationWindow {
        id: testWindow
        width: 1280
        height: 720
        visible: true
        property var openedScreen: ({})
        function popScreen() { }
        function pushScreen(url, properties) { openedScreen = {url, properties} }
    }

    QtObject {
        id: mockWs
        property bool forgeRulesAvailable: true
        property bool forgeAIAvailable: true
        property bool aiModelsAvailable: true
        property var modelOpponent: QtObject {
            property bool ready: false
            signal profilesChanged()
            function configured(source) { return ready && ["local", "online"].includes(source) }
        }
        property bool playerHostingAvailable: false
        property var forgeHost: QtObject { property bool ready: false; property bool busy: false; property string status: "Test runtime"; property double progress: 0; function check() {} }
        property bool inRoom: false
        property string lastError: ""
        property int createCount: 0
        property string submittedMatchMode: ""
        property string submittedRulesMode: ""
        property var submittedRoom: ({})
        function createRoom(name, format, deckFormat, spectators, hands, matchMode,
                            loadMode, password, playtest, rulesMode, hostingMode, aiDifficulty, aiSource) {
            ++createCount
            submittedMatchMode = matchMode
            submittedRulesMode = rulesMode
            submittedRoom = {name, format, deckFormat, spectators, hands, matchMode,
                             loadMode, password, playtest, rulesMode, hostingMode, aiDifficulty, aiSource}
        }
        property var submittedLimited: []
        property string submittedCoordinator: ""
        function createLimitedTournament() {
            submittedLimited = Array.from(arguments)
            submittedCoordinator = "swiss"
        }
        function createCasualLimitedEvent() {
            submittedLimited = Array.from(arguments)
            submittedCoordinator = "casual"
        }
    }

    QtObject {
        id: mockDecks
        property int count: 0
        property string currentDeckId: ""
        signal currentDeckChanged()
        property var cubes: []
        function matchDecks() { return cubes }
        function cubeProduct(id) { return ({id: id, productType: "cube"}) }
    }

    property var page: null

    Component {
        id: pageComponent
        CreateRoom {
            wsModel: mockWs
            deckLibraryModel: mockDecks
        }
    }

    function init() {
        mockWs.createCount = 0
        mockWs.forgeRulesAvailable = true
        mockWs.forgeAIAvailable = true
        mockWs.aiModelsAvailable = true
        mockWs.modelOpponent.ready = false
        mockWs.playerHostingAvailable = false
        mockWs.forgeHost.ready = false
        mockWs.forgeHost.busy = false
        mockWs.lastError = ""
        mockWs.submittedLimited = []
        mockWs.submittedCoordinator = ""
        mockDecks.cubes = []
        testWindow.width = 1280
        testWindow.height = 720
        Theme.uiScale = 1
        testTranslations.setLanguage("en")
        page = pageComponent.createObject(testWindow.contentItem)
        verify(page !== null)
        page.anchors.fill = testWindow.contentItem
        waitForRendering(page)
        tryVerify(() => page.layoutReady)
    }

    function waitForFormMotion() {
        wait(Theme.motionNormal + Theme.motionFast)
        waitForRendering(page)
    }

    function cleanup() {
        if (page !== null)
            page.destroy()
        page = null
        Theme.uiScale = 1
        testTranslations.setLanguage("en")
    }

    function test_aiOpponentConfiguresConstructedBo1() {
        page.roomName = "AI practice"
        page.rulesMode = "forge"
        page.matchMode = "bo3"
        const opponent = findChild(page, "roomOpponentControl")
        verify(opponent.visible)
        opponent.activated(1)
        compare(page.matchMode, "bo1")
        const difficulty = findChild(page, "roomAiDifficultyControl")
        difficulty.activated(2)
        compare(page.aiDifficulty, "hard")
        page.submit()
        compare(mockWs.submittedRoom.aiDifficulty, "hard")
        compare(mockWs.submittedRoom.matchMode, "bo1")
        compare(mockWs.submittedRoom.rulesMode, "forge")
        compare(mockWs.submittedRoom.playtest, false)
        compare(findChild(page, "roomMatchModeControl").options.length, 1)
    }

    function test_aiAvailabilityUsesSeparateCapability() {
        page.roomName = "AI practice"
        page.rulesMode = "forge"
        mockWs.forgeAIAvailable = false
        verify(findChild(page, "roomOpponentControl").enabled)
        page.aiOpponent = true
        compare(page.createBlockerReason(), "Forge AI is unavailable with this hosting option.")
        page.hostingMode = "player"
        mockWs.playerHostingAvailable = true
        mockWs.forgeHost.ready = true
        verify(findChild(page, "roomOpponentControl").enabled)
        compare(page.createBlockerReason(), "")
    }

    function test_modelOpponentRequiresConfiguredConnection_data() {
        return [{tag: "local", source: "local", index: 2}, {tag: "online", source: "online", index: 3}]
    }

    function test_modelOpponentRequiresConfiguredConnection(data) {
        page.roomName = "Model practice"
        page.rulesMode = "forge"
        page.matchMode = "bo3"
        findChild(page, "roomOpponentControl").activated(data.index)
        compare(page.aiSource, data.source)
        findChild(page, "roomModelSettingsButton").clicked()
        compare(testWindow.openedScreen.url, "screens/ModelSettings.qml")
        compare(testWindow.openedScreen.properties.source, data.source)
        compare(page.matchMode, "bo1")
        compare(page.createBlockerReason(), "Configure the selected model connection first")
        verify(!findChild(page, "roomAiDifficultyControl").visible)
        mockWs.modelOpponent.ready = true
        mockWs.modelOpponent.profilesChanged()
        compare(page.createBlockerReason(), "")
        page.submit()
        compare(mockWs.submittedRoom.aiSource, data.source)
        compare(mockWs.submittedRoom.aiDifficulty, "")
        mockWs.aiModelsAvailable = false
        compare(page.createBlockerReason(), "Model opponents are unavailable on this server.")
    }

    function test_aiOpponentResetsForUnsupportedModes() {
        page.roomName = "AI practice"
        page.rulesMode = "forge"
        page.aiOpponent = true
        page.deckFormat = "duel"
        page.roomFormat = "duel"
        compare(page.aiOpponentAvailable, false)
        compare(page.aiOpponent, false)
        page.submit()
        compare(mockWs.submittedRoom.aiDifficulty, "")
        page.deckFormat = "modern"
        page.roomFormat = "modern"
        page.aiOpponent = true
        page.rulesMode = "manual"
        compare(page.aiOpponent, false)
        page.playtestMode = true
        page.submit()
        compare(mockWs.submittedRoom.aiDifficulty, "")
        compare(mockWs.submittedRoom.rulesMode, "manual")
    }

    function test_nameStartsEmptyWithoutExample() {
        testWindow.requestActivate()
        tryVerify(() => testWindow.active)
        const field = findChild(page, "roomNameField")
        compare(page.roomName, "")
        compare(field.text, "")
        compare(field.placeholderText, "")
        verify(!findChild(page, "createRoomSubmitButton").enabled)
        mouseClick(field)
        tryVerify(() => field.activeFocus)
        for (const character of "table1")
            keyClick(character)
        compare(page.roomName, "table1")
        verify(findChild(page, "createRoomSubmitButton").enabled)
    }

    function test_firstClickAfterWheelBoundaryCreatesForgeCube() {
        testWindow.height = 400
        mockDecks.cubes = [{deckId:"cube-1", deckName:"Test Cube", mainCount:360,
                           sideboardCount:0, exactPrintings:true}]
        page.selectedCubeDeckId = "cube-1"
        page.roomName = "Wheel boundary Cube"
        page.deckFormat = "cube"
        page.rulesMode = "forge"
        waitForFormMotion()
        const body = findChild(page, "createRoomBody")
        const button = findChild(page, "createRoomSubmitButton")
        verify(button.enabled)
        verify(body.contentHeight > body.height)
        mouseWheel(body, body.width - 10, body.height / 2, 0, -12000)
        tryVerify(() => body.atYEnd && !body.moving)
        mouseClick(button, button.width / 2, button.height / 2)
        compare(mockWs.submittedCoordinator, "casual")
        compare(mockWs.submittedLimited[6], "forge")
    }

    function test_cubeDefaultsToDraftBuildAndFreePlay() {
        mockDecks.cubes = [{deckId: "cube-1", deckName: "Test Cube", mainCount: 360,
                           sideboardCount: 0, exactPrintings: true}]
        page.selectedCubeDeckId = "cube-1"
        page.roomName = "Cube night"
        page.deckFormat = "cube"
        page.matchMode = "bo3"
        // Manual Cube does not require Forge or ordinary room password settings.
        page.rulesMode = "manual"
        mockWs.forgeRulesAvailable = false
        page.roomPassword = "界".repeat(30)
        const button = findChild(page, "createRoomSubmitButton")
        verify(findChild(page, "cubePlayModeControl") === null)
        compare(button.text, "Create Cube room")
        verify(button.enabled)
        button.clicked()
        compare(mockWs.submittedCoordinator, "casual")
        compare(mockWs.submittedLimited.length, 7)
        compare(mockWs.submittedLimited[6], "manual")
        compare(mockWs.submittedLimited[0], "Cube night")
        compare(mockWs.submittedLimited[1], "cube_draft")
        compare(mockWs.submittedLimited[2], "bo3")
        compare(mockWs.submittedLimited[3], 8)
        compare(mockWs.submittedLimited[4].id, "cube-1")
        compare(mockWs.createCount, 0)

        findChild(page, "cubePlayerCapField").text = "9"
        verify(!button.enabled)
    }

    function test_cubeForgeUsesServerAvailabilityAndHidesPlayerHosting() {
        mockDecks.cubes = [{deckId: "cube-1", deckName: "Test Cube", mainCount: 360,
                           sideboardCount: 0, exactPrintings: true}]
        page.selectedCubeDeckId = "cube-1"
        page.roomName = "Forge Cube"
        page.deckFormat = "cube"
        page.hostingMode = "player"
        findChild(page, "forgeRulesMode").activated(1)
        const button = findChild(page, "createRoomSubmitButton")
        verify(findChild(page, "forgeRulesMode").visible)
        verify(!findChild(page, "forgeHostingExtras").expanded)
        mockWs.forgeRulesAvailable = false
        verify(!button.enabled)
        mockWs.forgeRulesAvailable = true
        verify(button.enabled)
        button.clicked()
        compare(mockWs.submittedLimited[6], "forge")
        page.commanderCube = true
        findChild(page, "cubePlayerCapField").text = "2"
        verify(!findChild(page, "forgeRulesMode").visible)
        mockWs.forgeRulesAvailable = false
        verify(button.enabled)
    }

    function test_wideFormFitsOnePage_data() {
        return [{tag: "en-modern", language: "en", format: "modern", rules: "manual"},
                {tag: "zh-modern", language: "zh", format: "modern", rules: "manual"},
                {tag: "en-commander", language: "en", format: "edh", rules: "manual"},
                {tag: "zh-forge", language: "zh", format: "modern", rules: "forge"},
                {tag: "zh-cube", language: "zh", format: "modern", deckFormat: "cube", rules: "manual"}]
    }
    function test_commanderPackOptions_data() {
        const rows = []
        for (const packs of [3, 4, 5, 6, 8])
            for (const batch of [1, 2]) rows.push({tag: packs + " packs, batch " + batch, packs, batch})
        return rows
    }
    function test_commanderPackOptions(data) {
        mockDecks.cubes = [{deckId: "cube-1", deckName: "Commander Cube", mainCount: 960,
                           sideboardCount: 0, exactPrintings: true}]
        page.selectedCubeDeckId = "cube-1"
        page.roomName = "Configured Commander Cube"
        page.deckFormat = "cube"
        findChild(page, "cubeVariantControl").activated(1)
        findChild(page, "cubePlayerCapField").text = "4"
        const packs = findChild(page, "commanderPackCountSelector")
        packs.currentIndex = page.commanderPackOptions.indexOf(data.packs)
        packs.activated(packs.currentIndex)
        page.commanderDoublePacks = data.batch === 2
        compare(page.cubeCardsRequired(), 4 * data.packs * 20)
        findChild(page, "createRoomSubmitButton").clicked()
        compare(mockWs.submittedLimited[5].packsPerPlayer, data.packs)
        compare(mockWs.submittedLimited[5].packsPerBatch, data.batch)
        compare(mockWs.submittedLimited[5].cardsPerPack, 20)
    }
    function test_commanderPackSizeControlsStockAndRequest_data() {
        return [{tag: "minimum", seats: 4, cards: 10, packs: 6},
                {tag: "odd", seats: 4, cards: 25, packs: 6},
                {tag: "maximum", seats: 4, cards: 40, packs: 6},
                {tag: "eight seats", seats: 8, cards: 25, packs: 3}]
    }
    function test_commanderPackSizeControlsStockAndRequest(data) {
        mockDecks.cubes = [{deckId: "cube-1", deckName: "Custom pack Cube", mainCount: 960,
                           sideboardCount: 0, exactPrintings: true}]
        page.selectedCubeDeckId = "cube-1"
        page.roomName = "Custom packs"
        page.deckFormat = "cube"
        findChild(page, "cubeVariantControl").activated(1)
        findChild(page, "cubePlayerCapField").text = String(data.seats)
        const field = findChild(page, "commanderCardsPerPackField")
        verify(field.visible)
        compare(field.text, "20")
        field.text = String(data.cards)
        compare(page.cubeCardsRequired(), data.seats * data.packs * data.cards)
        const button = findChild(page, "createRoomSubmitButton")
        verify(button.enabled)
        button.clicked()
        compare(mockWs.submittedLimited[5].cardsPerPack, data.cards)
        compare(mockWs.submittedLimited[5].packsPerPlayer, data.packs)
        compare(mockWs.submittedLimited[5].packsPerBatch, data.seats > 4 ? 1 : 2)
        const packs = findChild(page, "commanderPackCountSelector")
        if (data.seats === 4) {
            compare(packs.enabledForIndex(4), 4 * 8 * data.cards <= 960)
            page.commanderPackCount = 8
            compare(button.enabled, 4 * 8 * data.cards <= 960)
        }
        for (const value of ["", "9", "41", "1.5", "cards"]) {
            field.text = value
            verify(!button.enabled)
            compare(page.createBlockerReason(), "Choose 10 to 40 cards per pack")
        }
        // An invalid hidden Commander setting does not affect regular Cube.
        findChild(page, "cubeVariantControl").activated(0)
        verify(button.enabled)
        compare(page.cubeCardsRequired(), data.seats * 45)
    }
    function test_commanderPackOptionsRejectInsufficientStock() {
        mockDecks.cubes = [{deckId: "cube-1", deckName: "Small Commander Cube", mainCount: 400,
                           sideboardCount: 0, exactPrintings: true}]
        page.selectedCubeDeckId = "cube-1"
        page.roomName = "Small Commander Cube"
        page.deckFormat = "cube"
        findChild(page, "cubeVariantControl").activated(1)
        findChild(page, "cubePlayerCapField").text = "4"
        const packs = findChild(page, "commanderPackCountSelector")
        const button = findChild(page, "createRoomSubmitButton")
        verify(!button.enabled, "The default six packs require 480 cards")
        compare(page.commanderPackOptions.map((_, index) => packs.enabledForIndex(index)),
            [true, true, true, false, false])
        packs.currentIndex = 2
        packs.activated(2)
        compare(page.commanderPackCount, 5)
        verify(button.enabled)
        packs.currentIndex = 4
        packs.activated(4)
        compare(page.commanderPackCount, 5, "Keyboard activation cannot select an unavailable option")
        compare(packs.currentIndex, 2)
    }
    function test_commanderCubeCapacityAndDraftPresets() {
        mockDecks.cubes = [{deckId: "cube-1", deckName: "Commander Cube", mainCount: 960,
                           sideboardCount: 0, exactPrintings: true}]
        page.selectedCubeDeckId = "cube-1"
        page.roomName = "Commander night"
        page.deckFormat = "cube"
        page.matchMode = "bo3"
        const variant = findChild(page, "cubeVariantControl")
        verify(variant.visible)
        variant.activated(1)
        verify(page.commanderCube)
        compare(page.matchMode, "bo1")
        compare(findChild(page, "roomMatchModeControl").options.length, 1)
        const button = findChild(page, "createRoomSubmitButton")
        const cap = findChild(page, "cubePlayerCapField")
        tryCompare(cap, "text", "4")
        compare(page.cubeCardsRequired(), 480)
        verify(button.enabled)
        button.clicked()
        compare(mockWs.submittedCoordinator, "casual")
        compare(mockWs.submittedLimited[1], "commander_cube")
        compare(mockWs.submittedLimited[2], "bo1")
        compare(mockWs.submittedLimited[3], 4)
        compare(mockWs.submittedLimited[5].packsPerPlayer, 6)
        compare(mockWs.submittedLimited[5].packsPerBatch, 2)
        compare(mockWs.createCount, 0)
        cap.text = "8"
        verify(button.enabled)
        compare(page.cubeCardsRequired(), 480)
        button.clicked()
        compare(mockWs.submittedLimited[3], 8)
        compare(mockWs.submittedLimited[5].packsPerPlayer, 3)
        compare(mockWs.submittedLimited[5].packsPerBatch, 1)
        cap.text = "9"
        verify(!button.enabled)
        compare(page.createBlockerReason(), "Choose a Commander Cube player cap from 2 to 8")
        cap.text = "3"
        verify(button.enabled)
        cap.text = "2"
        verify(button.enabled)
        variant.activated(0)
        variant.activated(1)
        verify(waitForPolish(testWindow))
        compare(cap.text, "2", "Changing variants preserves a valid smaller table")
        cap.text = "4"
        variant.activated(0)
        compare(page.cubeCardsRequired(), 180)
    }
    function test_wideFormFitsOnePage(data) {
        testTranslations.setLanguage(data.language)
        page.roomFormat = data.format
        page.deckFormat = data.deckFormat || (data.format === "edh" ? "commander" : data.format)
        page.rulesMode = data.rules
        waitForFormMotion()
        const details = findChild(page, "createRoomDetails")
        const options = findChild(page, "createRoomOptions")
        const body = findChild(page, "createRoomBody")
        const button = findChild(page, "createRoomSubmitButton")
        compare(findChild(page, "createRoomColumns").columns, 2)
        verify(options.x >= details.x + details.width)
        compare(details.y, options.y)
        verify(Math.abs(details.width - options.width) <= 1)
        verify(body.contentHeight <= body.height + 1,
               "Fields should fit at 1280x720: " + body.contentHeight + "/" + body.height)
        const content = findChild(page, "createRoomContent")
        const actions = findChild(page, "createRoomActions")
        const card = findChild(page, "createRoomCard")
        verify(content.formFits)
        const cardTop = card.mapToItem(page, 0, 0).y
        const cardBottom = card.mapToItem(page, 0, card.height).y
        const actionsTop = actions.mapToItem(page, 0, 0).y
        const buttonBottom = button.mapToItem(page, 0, button.height).y
        verify(buttonBottom <= page.height + 1)
        verify(actionsTop >= cardTop)
        verify(buttonBottom <= cardBottom + 1)
    }

    function test_narrowScaledFormStacksAndScrolls_data() {
        return [{tag: "ordinary", commander: false}, {tag: "commander packs", commander: true}]
    }
    function test_narrowScaledFormStacksAndScrolls(data) {
        if (data.commander) {
            page.deckFormat = "cube"
            page.commanderCube = true
            findChild(page, "commanderCardsPerPackField").text = "25"
        }
        testWindow.requestActivate()
        tryVerify(() => testWindow.active)
        testWindow.width = 900
        testWindow.height = 620
        Theme.uiScale = 1.25
        testTranslations.setLanguage("zh")
        waitForFormMotion()
        const details = findChild(page, "createRoomDetails")
        const options = findChild(page, "createRoomOptions")
        const body = findChild(page, "createRoomBody")
        compare(findChild(page, "createRoomColumns").columns, 1)
        verify(options.y >= details.y + details.height)
        const field = findChild(page, "roomNameField")
        const position = field.mapToItem(body, 0, 0)
        verify(position.x >= 0 && position.x + field.width <= body.width)
        verify(body.contentHeight > body.height)
        mouseWheel(body, 10, 40, 0, -120)
        tryVerify(() => body.contentY > 0, 1000)
        test_createButtonStaysReachableOnLaptopHeight()
    }

    function test_spectatorTogglesKeepPrivacyAndSubmittedSettings() {
        page.roomName = "Spectator test"
        const hands = findChild(page, "spectatorsSeeHandsToggle")
        const spectators = findChild(page, "allowSpectatorsToggle")
        verify(!hands.checked)
        mouseClick(hands)
        verify(page.spectatorsSeeHands)
        mouseClick(spectators)
        verify(!page.allowSpectators)
        verify(!page.spectatorsSeeHands)
        verify(!hands.visible)
        page.submit()
        verify(!mockWs.submittedRoom.spectators)
        verify(!mockWs.submittedRoom.hands)
        mouseClick(spectators)
        verify(hands.visible)
        verify(!hands.checked)
    }

    function test_createButtonStaysReachableOnLaptopHeight() {
        const body = findChild(page, "createRoomBody")
        const button = findChild(page, "createRoomSubmitButton")
        verify(body !== null)
        verify(button !== null)

        const buttonBottom = button.mapToItem(body.contentItem, 0, button.height).y
        verify(body.contentHeight + 0.5 >= buttonBottom)

        body.contentY = Math.max(0, body.contentHeight - body.height)
        waitForRendering(page)
        const buttonTop = button.mapToItem(body, 0, 0).y
        verify(buttonTop + button.height <= body.height + 1)
        verify(buttonTop >= -1)
    }

    function test_rulesModeToggleDoesNotRebuildTheForm() {
        page.rulesMode = "forge"
        page.hostingMode = "player"
        waitForFormMotion()
        const extras = findChild(page, "forgeHostingExtras")
        const card = findChild(page, "createRoomCard")
        verify(extras.height > 1)
        const cardX = card.x
        findChild(page, "forgeRulesMode").activated(0)
        compare(page.rulesMode, "manual")
        wait(Theme.motionFast)
        verify(card.visible)
        compare(card.x, cardX)
        const submit = findChild(page, "createRoomSubmitButton")
        verify(submit.mapToItem(page, 0, submit.height).y
               <= card.mapToItem(page, 0, card.height).y + 1)
        waitForFormMotion()
        findChild(page, "forgeRulesMode").activated(1)
        wait(Theme.motionFast)
        verify(submit.mapToItem(page, 0, submit.height).y
               <= card.mapToItem(page, 0, card.height).y + 1)
        waitForFormMotion()
        verify(submit.mapToItem(page, 0, submit.height).y
               <= card.mapToItem(page, 0, card.height).y + 1)
        findChild(page, "forgeRulesMode").activated(0)
        waitForFormMotion()
        compare(findChild(page, "createRoomColumns").columns, 2)
        verify(findChild(page, "createRoomContent").formFits)
        verify(extras.height <= 1)
    }

    function test_passwordSitsWithJoinOptions() {
        const details = findChild(page, "createRoomDetails")
        const password = findChild(page, "roomPasswordField")
        compare(findChild(page, "createRoomColumns").columns, 2)
        verify(password.mapToItem(page, 0, 0).x
               >= details.mapToItem(page, details.width, 0).x - 1)
    }

    function test_tallWindowCentersTheForm() {
        testWindow.height = 1080
        waitForFormMotion()
        const card = findChild(page, "createRoomCard")
        const content = findChild(page, "createRoomContent")
        verify(content.formFits)
        verify(card.y > Theme.size(24))
        const button = findChild(page, "createRoomSubmitButton")
        const cardBottom = card.mapToItem(page, 0, card.height).y
        const buttonBottom = button.mapToItem(page, 0, button.height).y
        verify(buttonBottom <= cardBottom + 1)
    }

    function test_formatsUsePopularOrderAndCustomLast() {
        compare(page.formatOptions[0].value, "modern")
        compare(page.formatOptions[1].value, "commander")
        compare(page.formatOptions[2].value, "duel")
        compare(page.formatOptions[3].value, "legacy")
        compare(page.formatOptions[page.formatOptions.length - 1].value,
                "custom")
        compare(page.deckFormat, "modern")
    }

    function test_playtestKeepsCustomAndExcludesCube() {
        page.playtestMode = true
        compare(page.selectableFormatOptions.length,
                page.formatOptions.length - 1)
        compare(page.selectableFormatOptions[
                    page.selectableFormatOptions.length - 1].value,
                "custom")
        for (let index = 0;
             index < page.selectableFormatOptions.length; ++index) {
            verify(page.selectableFormatOptions[index].value !== "cube")
        }
    }

    function test_forgeSupportsBo3ButCommanderRemainsBo1() {
        page.roomName = "Forge test"
        page.rulesMode = "forge"
        page.matchMode = "bo3"
        const modes = findChild(page, "roomMatchModeControl")
        compare(modes.options.length, 2)
        page.submit()
        compare(mockWs.submittedMatchMode, "bo3")
        compare(mockWs.submittedRulesMode, "forge")
        page.roomFormat = "edh"
        compare(modes.options.length, 1)
        page.submit()
        compare(mockWs.submittedMatchMode, "bo1")
    }
    function test_playerHostingHasIndependentCapabilityAndReadiness() {
        page.roomName = "Trusted duel"
        page.rulesMode = "forge"
        page.hostingMode = "player"
        mockWs.forgeRulesAvailable = false
        const submit = findChild(page, "createRoomSubmitButton")
        verify(!submit.enabled)
        mockWs.playerHostingAvailable = true
        verify(!submit.enabled)
        mockWs.forgeHost.ready = true
        verify(submit.enabled)
        mockWs.forgeHost.busy = true
        verify(!submit.enabled)
        mockWs.forgeHost.busy = false
        submit.clicked()
        compare(mockWs.submittedRoom.hostingMode, "player")
        page.hostingMode = "server"
        verify(!submit.enabled)
    }
}
