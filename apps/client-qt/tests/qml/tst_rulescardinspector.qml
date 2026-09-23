// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic
import QtTest
import "../../qml/components"

TestCase {
    name: "RulesCardInspector"
    when: windowShown
    property var snapshot

    ApplicationWindow {
        id: testWindow
        width: 1000
        height: 850
        visible: true

        QtObject {
            id: catalog
            property int imageRevision: 0
            property url imageUrl: ""
            property var requestedNames: []
            function imageSource(name, setCode, collectorNumber) {
                requestedNames.push(name)
                return imageUrl
            }
            function tableImageSource(name, setCode, collectorNumber) {
                return ""
            }
        }

        RulesCardSurface {
            id: card
            x: 20; y: 20; width: 100; height: 140
            cardCatalogModel: catalog
            cardBackSource: ""
            visibleIdentity: true
            name: "Walking Ballista"
            setCode: "AER"
            collectorNumber: "181"
            tapped: false
            faceDown: false
            attacking: false
            power: "4"
            toughness: "4"
            countersSummary: "+1/+1 4"
            inspectable: true
            onPreviewRequested: inspector.previewCard("ballista", card)
            onPreviewEnded: inspector.hidePreview(card)
            onInspectRequested: inspector.showCard("ballista")
        }
        Item { id: otherSource; x: 160; y: 20; width: 100; height: 100 }
        RulesCardInspector {
            id: inspector
            x: 300; y: 20; width: 410; height: 700
            rulesSession: testRulesPrompt.session
            cardCatalogModel: catalog
            cardBackSource: ""
        }
    }

    function init() {
        testTranslations.setLanguage("en")
        testWindow.requestActivate()
        tryCompare(testWindow, "active", true)
        Theme.uiScale = 1
        testRulesPrompt.clear()
        inspector.clear()
        inspector.width = 410
        inspector.height = 700
        card.previewEnabled = true
        card.focus = false
        mouseMove(otherSource)
        catalog.requestedNames = []
        catalog.imageUrl = ""
        snapshot = {
            roomId: "INSPECT", gameId: "inspection-game", turn: 4, step: "main1",
            activeSeat: 0, prioritySeat: 0, players: [],
            zones: [{zone: "battlefield", ownerSeat: 0, count: 2, cards: [
                {id: "ballista", visible: true, identity: {name: "Walking Ballista"},
                 ownerSeat: 0, controllerSeat: 0, power: "4", toughness: "4", damage: 2,
                 counters: [{name: "+1/+1", value: 4}], attachedTo: "hidden"},
                {id: "hidden", visible: false, identity: {name: "Secret creature"},
                 faceDown: true, ownerSeat: 0, controllerSeat: 0, power: "2", toughness: "2", damage: 1}
            ]}, {zone: "hand", ownerSeat: 0, count: 1, cards: [
                {id: "hand-card", visible: true, identity: {name: "Lightning Bolt"}}
            ]}, {zone: "hand", ownerSeat: 1, count: 1, cards: [
                {id: "private-hand", visible: false, identity: {name: "Secret hand"}}
            ]}, {zone: "library", ownerSeat: 0, count: 1, cards: [
                {id: "library-card", visible: false, identity: {name: "Secret library"}}
            ]}],
            stack: [{id: "trigger", controllerSeat: 0, ownerSeat: 0,
                     text: "Put a +1/+1 counter on target creature."}]
        }
        verify(testRulesPrompt.applySnapshot(snapshot))
    }

    function test_linkedExileDistinguishesCopiesAndClearsReturnedCards() {
        snapshot.zones[0].cards = [
            {id: "labyrinth-a", visible: true, identity: {name: "Ugin's Labyrinth"},
                ownerSeat: 0, controllerSeat: 0, exiledCardCount: 2, exiledCardIds: ["imprinted"]},
            {id: "labyrinth-b", visible: true, identity: {name: "Ugin's Labyrinth"},
                ownerSeat: 0, controllerSeat: 0}
        ]
        snapshot.zones.push({zone: "exile", ownerSeat: 0, count: 2, cards: [
            {id: "imprinted", visible: true, identity: {name: "Devourer of Destiny"}},
            {id: "face-down-exile", visible: false, faceDown: true}
        ]})
        verify(testRulesPrompt.applySnapshot(snapshot))
        verify(inspector.showCard("labyrinth-a"))
        compare(inspector.card.exiledCardCount, 2)
        verify(inspector.exiledSummary.includes("Devourer of Destiny"))
        verify(inspector.exiledSummary.includes("1 hidden card(s)"))
        verify(inspector.showCard("labyrinth-b"))
        compare(inspector.exiledSummary, "")
        verify(inspector.showCard("labyrinth-a"))
        snapshot.zones[0].cards[0].exiledCardCount = 0
        snapshot.zones[0].cards[0].exiledCardIds = []
        verify(testRulesPrompt.applySnapshot(snapshot))
        compare(inspector.exiledSummary, "")
    }

    function test_revealedChoicesFollowCurrentObjectAndZone() {
        const choices = [{kind:"namedCard", value:"Lightning Bolt"}, {kind:"chosenType", value:"Elf"},
            {kind:"chosenColor", value:"Blue"}, {kind:"chosenColor", value:"Red"},
            {kind:"chosenNumber", value:"0"}, {kind:"chosenMode", value:"Khans"},
            {kind:"classLevel", value:"2"}, {kind:"dungeonRoom", value:"Cave Entrance"}]
        snapshot.zones[0].cards[0].annotations = choices
        snapshot.zones[0].cards[1].annotations = choices
        snapshot.zones[1].cards[0].annotations = choices
        verify(testRulesPrompt.applySnapshot(snapshot))
        verify(inspector.showCard("ballista"))
        compare(inspector.persistentSummary,
            "Named: Lightning Bolt\nType: Elf\nColor: Blue, Red\nNumber: 0\nMode: Khans\nClass level: 2")
        verify(findChild(inspector, "rulesCardInspectorState").text.includes(inspector.persistentSummary))
        verify(inspector.showCard("hidden"))
        compare(inspector.persistentSummary, "")
        verify(inspector.showCard("hand-card"))
        compare(inspector.persistentSummary, "")
        verify(inspector.showCard("ballista"))
        snapshot.zones[0].cards[0].faceDown = true
        verify(testRulesPrompt.applySnapshot(snapshot))
        compare(inspector.persistentSummary, "")
        snapshot.zones[0].cards[0].faceDown = false
        snapshot.zones[0].cards[0].annotations = []
        verify(testRulesPrompt.applySnapshot(snapshot))
        compare(inspector.persistentSummary, "")
    }

    function cleanup() {
        inspector.clear()
        card.focus = false
        mouseMove(otherSource)
        testRulesPrompt.clear()
    }

    function test_hoverAndFocusPreviewWithoutBlockingAndClickPins() {
        mouseMove(card)
        tryCompare(inspector, "hasCard", true)
        compare(inspector.cardId, "ballista")
        verify(!inspector.pinned)
        mouseMove(otherSource)
        tryCompare(inspector, "hasCard", false)
        card.forceActiveFocus()
        tryCompare(card, "activeFocus", true)
        tryCompare(inspector, "hasCard", true)
        keyClick(Qt.Key_Return)
        verify(inspector.pinned)
        otherSource.forceActiveFocus()
        tryCompare(otherSource, "activeFocus", true)
        compare(inspector.cardId, "ballista")
        waitForRendering(inspector)
        mouseClick(findChild(inspector, "clearRulesCardInspectorButton"))
        tryCompare(inspector, "hasCard", false)
        mouseClick(card)
        verify(inspector.pinned)
    }

    function test_newHoverRestoresPinnedCardAndIgnoresOldSourceExit() {
        verify(inspector.showCard("ballista"))
        verify(inspector.previewCard("hand-card", otherSource))
        compare(inspector.card.name, "Lightning Bolt")
        inspector.hidePreview(card)
        compare(inspector.cardId, "hand-card")
        inspector.hidePreview(otherSource)
        compare(inspector.cardId, "ballista")
        verify(inspector.pinned)
        verify(!inspector.previewCard("private-hand", otherSource))
        compare(inspector.cardId, "ballista")
    }

    function test_dragSuspendsHoverWithoutPinning() {
        mouseMove(card)
        tryCompare(inspector, "hasCard", true)
        card.previewEnabled = false
        tryCompare(inspector, "hasCard", false)
        verify(!inspector.pinned)
    }

    function test_currentProjectionUpdatesAndHidesUnavailableIdentity() {
        verify(inspector.showCard("ballista"))
        const state = findChild(inspector, "rulesCardInspectorState")
        verify(state.text.includes("Damage marked: 2"))
        verify(state.text.includes("Attached to another object"))
        snapshot.zones[0].cards[0].damage = 0
        snapshot.zones[0].cards[0].power = "5"
        verify(testRulesPrompt.applySnapshot(snapshot))
        tryVerify(() => state.text.includes("Damage marked: 0"))
        verify(state.text.includes("5 / 4"))
        snapshot.zones[0].cards[0].visible = false
        snapshot.zones[0].cards[0].faceDown = true
        verify(testRulesPrompt.applySnapshot(snapshot))
        compare(inspector.hasIdentity, false)
        compare(findChild(inspector, "rulesCardInspectorTitle").text, "Face-down card")
        compare(findChild(inspector, "rulesCardInspectorArt").source.toString(), "")
        snapshot.zones[0].cards.shift()
        verify(testRulesPrompt.applySnapshot(snapshot))
        tryCompare(inspector, "hasCard", false)
        compare(inspector.pinnedCardId, "")
    }

    function test_hiddenCardsNeverRequestCatalogIdentity() {
        verify(inspector.showCard("hidden"))
        verify(inspector.hasCard)
        verify(!inspector.hasIdentity)
        verify(findChild(inspector, "rulesCardInspectorState").text.includes("Damage marked: 1"))
        verify(!inspector.showCard("private-hand"))
        verify(!inspector.showCard("library-card"))
        verify(!inspector.showCard("missing"))
        compare(catalog.requestedNames.length, 0)
    }

    function test_gameReplacementCannotReusePinnedIdentity() {
        verify(inspector.showCard("ballista"))
        verify(inspector.previewCard("hand-card", otherSource))
        snapshot.gameId = "replacement-game"
        verify(testRulesPrompt.applySnapshot(snapshot))
        tryCompare(inspector, "hasCard", false)
        compare(inspector.pinnedCardId, "")
        compare(inspector.previewCardId, "")
    }

    function test_stackAbilityUsesCurrentTextWithoutLookingUpIdentity() {
        verify(inspector.showCard("trigger"))
        compare(findChild(inspector, "rulesCardInspectorTitle").text, "Stack ability")
        verify(findChild(inspector, "rulesCardInspectorState").text.includes(snapshot.stack[0].text))
        compare(catalog.requestedNames.length, 0)
    }

    function test_fullArtAndStateStayInsideReservedDock_data() {
        return [
            {tag: "tall-dock", dockWidth: 410, dockHeight: 700},
            {tag: "decision-dock", dockWidth: 410, dockHeight: 500},
            {tag: "compact-dock", dockWidth: 300, dockHeight: 240},
            {tag: "wide-short-dock", dockWidth: 660, dockHeight: 260}
        ]
    }

    function test_fullArtAndStateStayInsideReservedDock(data) {
        inspector.width = data.dockWidth
        inspector.height = data.dockHeight
        catalog.imageUrl = "data:image/svg+xml," + encodeURIComponent(
                    '<svg xmlns="http://www.w3.org/2000/svg" width="1344" height="1872"><rect width="100%" height="100%" fill="#41634e"/></svg>')
        verify(inspector.showCard("ballista"))
        const art = findChild(inspector, "rulesCardInspectorArt")
        const scroll = findChild(inspector, "rulesCardInspectorScroll")
        const unpin = findChild(inspector, "clearRulesCardInspectorButton")
        tryCompare(art, "status", Image.Ready)
        compare(art.sourceSize.width, 1344)
        waitForRendering(inspector)
        for (const item of [art, scroll, unpin]) {
            const point = item.mapToItem(inspector, 0, 0)
            verify(item.width > 0 && item.height > 0, item.objectName + " needs nonzero space")
            verify(point.x >= 0 && point.y >= 0, item.objectName + " stays in the dock")
            verify(point.x + item.width <= inspector.width + 1, item.objectName + " fits horizontally")
            verify(point.y + item.height <= inspector.height + 1, item.objectName + " fits vertically")
        }
        verify(scroll.width >= 100)
        verify(scroll.height >= 50)
        mouseClick(unpin)
        tryCompare(inspector, "hasCard", false)
    }
}
