// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Window
import QtQuick.Controls.Basic
import QtTest
import "../../../apps/client-qt/qml/components"
import "../../../apps/client-qt/qml/screens"

// Native layout qualification with the real C++ snapshot decoder. This is an
// explicit crowded-board fixture, not evidence of a legal Forge game.
TestCase {
    name: "ForgeStackNativeLayout"
    when: windowShown
    ApplicationWindow {
        id: window
        width: 1600; height: 1000; visible: true
        QtObject {
            id: room
            property int maxSeats: 2
            property string roomId: "LAYOUT"
            property string roomName: "Crowded stack fixture"
            property string role: "player"
            property int seatIndex: 0
            property bool host: true
            property string phase: "started"
            property string matchMode: "bo1"
            property string format: "modern"
            property string deckFormat: "modern"
            property bool spectatorsSeeHands: false
        }
        QtObject {
            id: match
            property int gameNumber: 1
            property var score: [0, 0]
            property var result: ({})
            property var sideboard: ({})
            property bool sideboarding: false
        }
        QtObject {
            id: transport
            property var rulesSession: testRulesPrompt.session
            property var roomSession: room
            property var gameSession: match
            property bool inRoom: true
            property bool rulesResponsePending: false
            property string lastError: ""
        }
        QtObject {
            id: catalog
            property int imageRevision: 0
            function tableImageSource(name, set, number) { return "" }
            function cardTypeLine(name) { return name === "Plains" ? "Basic Land — Plains" : "Creature" }
        }
        RulesTable {
            id: table
            anchors.fill: parent
            wsModel: transport
            cardCatalogModel: catalog
            gameTableModel: testGameTable
            sideboardTableModel: testSideboardTable
        }
    }
    function item(name) {
        const popup = findChild(table, "forgeZonePopup")
        const result = findChild(table, name) || (popup ? findChild(popup.contentItem, name) : null)
        verify(result !== null, name)
        return result
    }
    function card(id, seat, name) {
        return {id:id, ownerSeat:seat, controllerSeat:seat, visible:true, identity:{name:name}, power:"2", toughness:"2"}
    }
    function test_maximizedCrowdedTargets() {
        window.showMaximized()
        tryCompare(window, "visibility", Window.Maximized)
        const own = [], other = [], hand = [], stack = []
        for (let i = 0; i < 26; ++i) own.push(card("own-" + i, 0, "Grizzly Bears"))
        for (let i = 0; i < 22; ++i) other.push(card("other-" + i, 1, "Grizzly Bears"))
        for (let i = 0; i < 18; ++i) hand.push(card("hand-" + i, 0, "Plains"))
        for (let i = 0; i < 9; ++i) stack.push({id:"spell-" + i, controllerSeat:i % 2,
            identity:{name:i === 0 ? "Arc Trail" : "Lightning Bolt"}, text:"Public stack description", targets:i === 0
                ? [{kind:"card", objectId:"own-25", label:"Grizzly Bears"}, {kind:"player", seat:1, label:"Opponent"}]
                : [{kind:"card", objectId:"other-21", label:"Grizzly Bears"}]})
        verify(testRulesPrompt.applySnapshot({roomId:"LAYOUT", gameId:"crowded", turn:10, step:"main1", activeSeat:0, prioritySeat:1,
            players:[{seat:0, name:"You", life:20}, {seat:1, name:"Opponent", life:20}], zones:[
                {zone:"battlefield", ownerSeat:0, count:own.length, cards:own},
                {zone:"battlefield", ownerSeat:1, count:other.length, cards:other},
                {zone:"hand", ownerSeat:0, count:hand.length, cards:hand},
                {zone:"hand", ownerSeat:1, count:4, cards:[]},
                {zone:"library", ownerSeat:0, count:44, cards:[]},
                {zone:"library", ownerSeat:1, count:46, cards:[]}], stack:stack}))
        const lane = item("forgeOwnCreatures"), stackView = item("forgeStack"), arrow = item("forgeStackTargetArrow")
        tryVerify(() => lane.visibleCards.length === 26 && stackView.currentTarget !== null)
        verify(lane.scrollArea.contentHeight <= lane.scrollArea.height,
               "The adaptive grid should fit this crowded creature lane")
        verify(stackView.scrollArea.contentHeight > stackView.scrollArea.height)
        verify(item("forgeHand").scrollArea.contentWidth > item("forgeHand").width)
        const sideCards = []
        for (let seat = 0; seat < 2; ++seat) for (let i = 0; i < 8; ++i) {
            for (const name of ["Plains", "Treasure"]) sideCards.push({id:name + seat + i,
                ownerSeat:seat, controllerSeat:seat, visible:true, identity:{name:name}})
        }
        verify(testRulesPrompt.applySnapshot({roomId:"LAYOUT", gameId:"crowded", turn:10, step:"main1", activeSeat:0, prioritySeat:1,
            players:[{seat:0, name:"You", life:20}, {seat:1, name:"Opponent", life:20}], zones:[
                {zone:"battlefield", ownerSeat:0, count:own.length + 16, cards:own.concat(sideCards.filter(card => card.ownerSeat === 0))},
                {zone:"battlefield", ownerSeat:1, count:other.length + 16, cards:other.concat(sideCards.filter(card => card.ownerSeat === 1))},
                {zone:"hand", ownerSeat:0, count:hand.length, cards:hand},
                {zone:"hand", ownerSeat:1, count:4, cards:[]},
                {zone:"library", ownerSeat:0, count:44, cards:[]},
                {zone:"library", ownerSeat:1, count:46, cards:[]}], stack:stack}))
        for (const name of ["forgeOwnLands", "forgeOpponentLands", "forgeOwnOther", "forgeOpponentOther"]) {
            const support = item(name)
            tryVerify(() => support.visibleCards.length === 8)
            verify(support.scrollArea.contentHeight <= support.scrollArea.height)
        }
        for (const name of ["forgeOwnCreatures", "forgeOpponentCreatures"]) {
            const creatures = item(name)
            verify(creatures.scrollArea.contentHeight <= creatures.scrollArea.height)
            for (const slot of creatures.visibleCards)
                verify(slot.y + slot.height <= creatures.scrollArea.height + 1)
        }
        verify(item("forgeHand").height < item("forgeHand").faceHeight * 0.6)
        compare(item("forgeTurnIndicator").text, "Your turn")
        mouseClick(item("forgeStackTarget-spell-0-0"))
        tryVerify(() => arrow.visible && item("forgeCard-own-25").located)
        verify(!item("forgeCard-own-0").located)
        waitForRendering(table)
        grabImage(table).save("build/forge-layout-review-2026-09-16/crowded-native.png")
        mouseMove(item("forgeCard-Treasure07"), 20, 30)
        tryCompare(item("rulesCardHoverPreview"), "visible", true)
        verify(!item("rulesInspectionHost").visible)
        waitForRendering(table)
        grabImage(table).save("build/forge-layout-review-2026-09-16/crowded-hover-native.png")
        table.setGameLogVisible(true)
        table.gameLogRail.chatInput.text = "Unsent layout-review draft"
        mouseMove(item("forgeCard-own-25"), 20, 30)
        tryCompare(item("rulesCardHoverPreview"), "visible", true)
        verify(table.gameLogRail.visible && !table.inspector.visible)
        compare(table.gameLogRail.chatInput.text, "Unsent layout-review draft")
        const log = item("rulesInspectionHost"), decision = item("rulesDecisionDock")
        verify(log.x >= decision.x + decision.width)
        verify(log.x >= stackView.x + stackView.width)
        for (const name of ["forgeOwnLands", "forgeOpponentLands", "forgeOwnOther", "forgeOpponentOther"]) {
            const support = item(name)
            verify(support.x + support.width <= decision.x)
        }
        waitForRendering(table)
        grabImage(table).save("build/forge-layout-review-2026-09-16/crowded-hover-log-native.png")
        mouseMove(table, 30, 70)
        tryCompare(item("rulesCardHoverPreview"), "visible", false)
        waitForRendering(table)
        grabImage(table).save("build/forge-zone-review-2026-09-16/right-log-native.png")
        table.gameLogRail.chatInput.text = ""
        table.setGameLogVisible(false)
        mouseWheel(stackView.scrollArea, 20, 30, 0, -360)
        tryVerify(() => stackView.scrollArea.contentY > 0 && !arrow.visible)
        mouseWheel(stackView.scrollArea, 20, 30, 0, 720)
        tryCompare(stackView.scrollArea, "contentY", 0)
        mouseClick(item("forgeStackTarget-spell-0-1"))
        tryVerify(() => arrow.visible && item("rulesPlayerTarget1").selected)
        waitForRendering(table)
        grabImage(table).save("build/forge-layout-review-2026-09-16/crowded-player-native.png")
        compare(item("forgeGameMenu").text, "Settings")
        compare(item("forgePlayerZones-0").text, "Hand · 18 · Library · 44")
        compare(item("forgePlayerZones-1").text, "Hand · 4 · Library · 46")
        compare(findChild(table, "forgeZone-command"), null)
        mouseClick(item("forgeOpponentZones"))
        tryCompare(item("forgeZonePopup"), "opened", true)
        waitForRendering(item("forgeZonePopup").contentItem)
        compare(findChild(item("forgeZonePopup").contentItem, "forgeZoneTab-command"), null)
        mouseClick(item("forgeZoneTab-library"))
        compare(item("forgeZoneCardsCount").text, "Library  /  46")
        compare(item("forgeZoneCards").visibleCards.length, 0)
        verify(item("forgeZoneCardsHiddenNotice").visible)
        compare(item("forgeZoneTab-library").variant, "highlight")
        wait(Theme.motionFast + 50)
        waitForRendering(table)
        grabImage(table).save("build/forge-zone-review-2026-09-16/opponent-library-native.png")
        mouseClick(item("forgeCloseZonePopup"))
        tryCompare(item("forgeZonePopup"), "visible", false)
        room.format = "duel"; room.deckFormat = "duel"
        mouseClick(item("forgeZone-command"))
        tryCompare(item("forgeZonePopup"), "opened", true)
        verify(item("forgeZoneTab-command").visible)
        compare(item("forgeZoneTab-command").variant, "highlight")
        wait(Theme.motionFast + 50)
        waitForRendering(table)
        grabImage(table).save("build/forge-zone-review-2026-09-16/duel-command-native.png")
        mouseClick(item("forgeCloseZonePopup"))
        tryCompare(item("forgeZonePopup"), "visible", false)
        console.log(JSON.stringify({evidence:"native-layout-fixture", requestedMode:"maximized", actualMode:window.visibility,
            width:window.width, height:window.height, screenWidth:window.screen.width, screenHeight:window.screen.height,
            dpr:window.screen.devicePixelRatio, creatures:[26,22], lands:[8,8], other:[8,8], hand:18, stack:9}))
        testRulesPrompt.clear()
    }
}
