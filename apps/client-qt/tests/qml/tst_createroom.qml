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
        function popScreen() { }
        function pushScreen(url) { }
    }

    QtObject {
        id: mockWs
        property bool forgeRulesAvailable: true
        property bool playerHostingAvailable: false
        property var forgeHost: QtObject { property bool ready: false; property bool busy: false; property string status: "Test runtime"; property double progress: 0; function check() {} }
        property bool inRoom: false
        property string lastError: ""
        property int createCount: 0
        property string submittedMatchMode: ""
        property string submittedRulesMode: ""
        property var submittedRoom: ({})
        function createRoom(name, format, deckFormat, spectators, hands, matchMode,
                            loadMode, password, playtest, rulesMode, hostingMode) {
            ++createCount
            submittedMatchMode = matchMode
            submittedRulesMode = rulesMode
            submittedRoom = {name, format, deckFormat, spectators, hands, matchMode,
                             loadMode, password, playtest, rulesMode, hostingMode}
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
    }

    function cleanup() {
        if (page !== null)
            page.destroy()
        page = null
        Theme.uiScale = 1
        testTranslations.setLanguage("en")
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

    function test_cubeDefaultsToDraftBuildAndFreePlay() {
        mockDecks.cubes = [{deckId: "cube-1", deckName: "Test Cube", mainCount: 360,
                           sideboardCount: 0, exactPrintings: true}]
        page.selectedCubeDeckId = "cube-1"
        page.roomName = "Cube night"
        page.deckFormat = "cube"
        page.matchMode = "bo3"
        // Hidden ordinary-room settings must not block the Cube coordinator.
        page.rulesMode = "forge"
        mockWs.forgeRulesAvailable = false
        page.roomPassword = "界".repeat(30)
        const button = findChild(page, "createRoomSubmitButton")
        verify(findChild(page, "cubePlayModeControl") === null)
        compare(button.text, "Create Cube room")
        verify(button.enabled)
        button.clicked()
        compare(mockWs.submittedCoordinator, "casual")
        compare(mockWs.submittedLimited.length, 5)
        compare(mockWs.submittedLimited[0], "Cube night")
        compare(mockWs.submittedLimited[1], "cube_draft")
        compare(mockWs.submittedLimited[2], "bo3")
        compare(mockWs.submittedLimited[3], 8)
        compare(mockWs.submittedLimited[4].id, "cube-1")
        compare(mockWs.createCount, 0)

        findChild(page, "cubePlayerCapField").text = "9"
        verify(!button.enabled)
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
        waitForRendering(page)
        const details = findChild(page, "createRoomDetails")
        const options = findChild(page, "createRoomOptions")
        const body = findChild(page, "createRoomBody")
        const button = findChild(page, "createRoomSubmitButton")
        compare(findChild(page, "createRoomColumns").columns, 2)
        verify(options.x >= details.x + details.width)
        compare(details.y, options.y)
        verify(Math.abs(details.width - options.width) <= 1)
        verify(body.contentHeight <= body.height + 1,
               "All fields and actions should fit at 1280x720: " + body.contentHeight + "/" + body.height)
        const bottom = button.mapToItem(body, 0, button.height)
        verify(bottom.y <= body.height + 1)
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
        waitForRendering(page)
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
