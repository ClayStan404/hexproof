// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic
import QtTest
import "../../qml/components"

TestCase {
    name: "RulesCardState"
    when: windowShown
    property var snapshot

    ApplicationWindow {
        id: testWindow
        width: 900
        height: 700
        visible: true

        QtObject {
            id: catalog
            property int imageRevision: 0
            property url imageUrl: ""
            property var requestedNames: []
            function tableImageSource(name, setCode, collectorNumber) {
                requestedNames.push(name)
                return imageUrl
            }
        }

        Instantiator {
            id: playerRows
            model: testRulesPrompt.session.players
            delegate: QtObject {
                required property string countersSummary
                required property string manaSummary
            }
        }

        RulesCardInspector {
            id: details
            x: 300; y: 20; width: 410; height: 600
            rulesSession: testRulesPrompt.session
            cardCatalogModel: catalog
            cardBackSource: ""
        }
    }
    Component { id: persistentStateComponent; RulesCardPersistentState {} }

    function init() {
        testTranslations.setLanguage("en")
        testRulesPrompt.clear()
        catalog.requestedNames = []
        catalog.imageUrl = ""
        testWindow.width = 900
        testWindow.height = 700
        Theme.uiScale = 1.0
        snapshot = {
            roomId: "STATE1", gameId: "card-state", turn: 4, step: "main1",
            activeSeat: 0, prioritySeat: 0, players: [],
            zones: [{zone: "battlefield", ownerSeat: 0, count: 2, cards: [
                {id: "ballista", visible: true, identity: {name: "Walking Ballista"},
                 ownerSeat: 0, controllerSeat: 0, power: "4", toughness: "4", damage: 2,
                 counters: [{name: "+1/+1", value: 4}], attachedTo: "hidden"},
                {id: "hidden", visible: false, identity: {name: "Secret creature"},
                 faceDown: true, ownerSeat: 1, controllerSeat: 1, power: "2", toughness: "2",
                 damage: 1, counters: [{name: "+1/+1", value: 1}]}
            ]}, {zone: "hand", ownerSeat: 1, count: 1, cards: [
                {id: "private-hand", visible: false, identity: {name: "Secret hand"}}
            ]}, {zone: "library", ownerSeat: 0, count: 1, cards: [
                {id: "library-card", visible: false, identity: {name: "Library identity"}}
            ]}],
            stack: [{id: "trigger", controllerSeat: 0, ownerSeat: 0,
                     text: "Put a +1/+1 counter on target creature."}]
        }
        verify(testRulesPrompt.applySnapshot(snapshot))
    }

    function cleanup() {
        details.clear()
        tryCompare(details, "hasCard", false)
        testRulesPrompt.clear()
        Theme.uiScale = 1.0
        testTranslations.setLanguage("en")
    }

    function test_currentProjectedStateUpdatesInInspector() {
        verify(details.showCard("ballista"))
        tryCompare(details, "hasCard", true)
        compare(findChild(details, "rulesCardInspectorTitle").text, "Walking Ballista")
        const state = findChild(details, "rulesCardInspectorState")
        verify(state.text.includes("Damage marked: 2"))
        verify(state.text.includes("Counters: +1/+1 × 4"))
        compare(state.text.split("Attached to Hidden card").length, 2)
        verify(!state.text.includes("Secret"))
        compare(state.textFormat, Text.PlainText)

        snapshot.zones[0].cards[0].damage = 0
        snapshot.zones[0].cards[0].counters[0].value = 5
        snapshot.zones[0].cards[0].power = "5"
        verify(testRulesPrompt.applySnapshot(snapshot))
        tryVerify(() => state.text.includes("Damage marked: 0"))
        verify(state.text.includes("Counters: +1/+1 × 5"))
    }

    function test_relationshipDetailsDoNotTreatAttacksAsAttachments_data() {
        return [
            {tag:"attacking player", kind:"attack-player", sourceSummary:"", targetSummary:""},
            {tag:"attacking permanent", kind:"attack-card", targetVisible:true, sourceSummary:"", targetSummary:""},
            {tag:"real hidden attachment", kind:"attachment", sourceSummary:"Attached to Hidden card",
             targetSummary:"Attachment: Walking Ballista"},
            {tag:"real visible attachment", kind:"attachment", targetVisible:true, sourceSummary:"Attached to Public host",
             targetSummary:"Attachment: Walking Ballista"},
            {tag:"blocking hidden permanent", kind:"block", sourceSummary:"Blocking Hidden card",
             targetSummary:"Blocked by Walking Ballista"},
            {tag:"empty attachment", kind:"empty", sourceSummary:"", targetSummary:""},
            {tag:"null attachment", kind:"null", sourceSummary:"", targetSummary:""},
            {tag:"missing attachment", kind:"missing", sourceSummary:"", targetSummary:""}
        ]
    }

    function test_relationshipDetailsDoNotTreatAttacksAsAttachments(data) {
        snapshot.players = [{seat:0, life:20}, {seat:1, life:20}]
        if (data.targetVisible) {
            const target = snapshot.zones[0].cards[1]
            target.visible = true
            target.faceDown = false
            target.identity = {name:"Public host"}
        }
        const source = snapshot.zones[0].cards[0]
        source.attachedTo = data.kind === "attachment" ? "hidden" : data.kind === "null" ? null : ""
        if (data.kind === "missing") delete source.attachedTo
        source.attacking = data.kind.startsWith("attack-")
        if (data.kind === "attack-player") source.attackingPlayer = 1
        if (data.kind === "attack-card") source.attackingTarget = "hidden"
        if (data.kind === "block") source.blocking = ["hidden"]
        verify(testRulesPrompt.applySnapshot(snapshot))
        const current = testRulesPrompt.session.cardForInspection("ballista")
        compare(current.attachedTo, data.kind === "attachment" ? "hidden" : "")
        if (source.attacking) {
            compare(current.links.length, 1)
            compare(current.links[0].kind, "attack")
            compare(current.links[0].targetId, data.kind === "attack-player" ? "" : "hidden")
            if (data.kind === "attack-player") compare(current.links[0].targetSeat, 1)
        }
        verify(details.showCard("ballista"))
        compare(details.persistentSummary, data.sourceSummary)
        if (source.attacking) verify(details.stateLines().includes("Attacking"))
        verify(!details.stateLines().includes("Secret"))
        verify(details.showCard("hidden"))
        compare(details.persistentSummary, data.targetSummary)
        verify(!details.stateLines().includes("Secret"))
    }

    function test_unknownRelationshipIsNotAnAttachment() {
        const current = testRulesPrompt.session.cardForInspection("ballista")
        current.links = [{kind:"future-link", sourceId:"ballista", targetId:"hidden"}]
        const state = createTemporaryObject(persistentStateComponent, testWindow,
            {card:current, rulesSession:testRulesPrompt.session, cardCatalogModel:catalog})
        verify(state)
        compare(state.relationshipLines.length, 0)
        compare(state.relationshipBadge, "")
    }

    function test_nativeCounterNamesAreReadable_data() {
        return [
            {tag: "english", language: "en", lore: "Lore", charge: "Charge",
             energy: "Energy", poison: "Poison", loyalty: "Loyalty"},
            {tag: "chinese", language: "zh", lore: "学问", charge: "充电",
             energy: "能量", poison: "中毒", loyalty: "忠诚"}
        ]
    }

    function test_nativeCounterNamesAreReadable(data) {
        testTranslations.setLanguage(data.language)
        snapshot.players = [{seat: 0, name: "Counter owner", life: 20, status: "playing",
                             counters: [{name: "ENERGY", value: 3}, {name: "POISON", value: 1}],
                             manaPool: [{name: "G", value: 2}, {name: "C", value: 1}]}]
        snapshot.zones[0].cards = [
            {id: "zabaz", visible: true, identity: {name: "Zabaz, the Glimmerwasp"},
             ownerSeat: 0, controllerSeat: 0, power: "2", toughness: "2",
             counters: [{name: "P1P1", value: 2}]},
            {id: "saga", visible: true, identity: {name: "Urza's Saga"},
             ownerSeat: 0, controllerSeat: 0, counters: [{name: "LORE", value: 2}]},
            {id: "other-counters", visible: true, identity: {name: "Counter fixture"},
             counters: [{name: "M1M1", value: 1}, {name: "P0P1", value: 2},
                        {name: "M2M2", value: 1}, {name: "CHARGE", value: 3},
                        {name: "LOYALTY", value: 4}, {name: "Future Counter", value: 5},
                        {name: "P9P9", value: 1}, {name: "Zero Counter", value: 0}]}
        ]
        verify(testRulesPrompt.applySnapshot(snapshot))
        verify(details.showCard("zabaz"))
        tryCompare(details, "hasCard", true)
        const state = findChild(details, "rulesCardInspectorState")
        verify(state.text.includes("+1/+1 × 2"))
        verify(!state.text.includes("P1P1"))
        details.clear()
        tryCompare(details, "hasCard", false)

        verify(details.showCard("saga"))
        tryCompare(details, "hasCard", true)
        verify(state.text.includes(data.lore + " × 2"))
        verify(!state.text.includes("LORE"))
        compare(testRulesPrompt.session.cardForInspection("other-counters").countersSummary,
                "-1/-1 × 1 · +0/+1 × 2 · -2/-2 × 1 · " + data.charge + " × 3 · "
                + data.loyalty + " × 4 · Future Counter × 5 · P9P9 × 1")
        tryCompare(playerRows, "count", 1)
        compare(playerRows.objectAt(0).countersSummary, data.energy + " × 3 · " + data.poison + " × 1")
        compare(playerRows.objectAt(0).manaSummary, "G 2 · C 1")
        // Display localization must leave the authoritative snapshot untouched.
        compare(snapshot.zones[0].cards[0].counters[0].name, "P1P1")
        compare(snapshot.zones[0].cards[1].counters[0].name, "LORE")
    }

    function test_faceDownShowsOnlyPublicStateAndDoesNotResolveIdentity() {
        verify(details.showCard("hidden"))
        tryCompare(details, "hasCard", true)
        compare(findChild(details, "rulesCardInspectorTitle").text, "Face-down card")
        verify(findChild(details, "rulesCardInspectorState").text.includes("Damage marked: 1"))
        verify(!catalog.requestedNames.includes("Secret creature"))
        compare(Object.keys(testRulesPrompt.session.cardForInspection("private-hand")).length, 0)
        compare(Object.keys(testRulesPrompt.session.cardForInspection("library-card")).length, 0)
        compare(Object.keys(testRulesPrompt.session.cardForInspection("missing")).length, 0)
    }

    function test_openDetailsAreInvalidatedWhenCardLeavesVisibleProjection() {
        verify(details.showCard("ballista"))
        tryCompare(details, "hasCard", true)
        snapshot.zones[0].cards.shift()
        snapshot.zones[1].cards.push({id: "ballista", visible: false})
        verify(testRulesPrompt.applySnapshot(snapshot))
        tryCompare(details, "hasCard", false)
        verify(!details.showCard("ballista"))
    }

    function test_gameChangeClosesDetailsEvenWhenObjectIdIsReused() {
        verify(details.showCard("ballista"))
        tryCompare(details, "hasCard", true)
        snapshot.gameId = "replacement-game"
        verify(testRulesPrompt.applySnapshot(snapshot))
        tryCompare(details, "hasCard", false)
    }

    function test_stackTextComesFromSnapshot() {
        verify(details.showCard("trigger"))
        tryCompare(details, "hasCard", true)
        compare(findChild(details, "rulesCardInspectorTitle").text, "Stack ability")
        verify(findChild(details, "rulesCardInspectorState").text.includes(snapshot.stack[0].text))
    }
}
