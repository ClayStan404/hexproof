// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtTest
import "../../../../tools/ui-automation/scenarios/ForgeFormatStudy.js" as Player
import "../../../../tools/ui-automation/scenarios/ForgeBorosStudy.js" as Choices
import "../../../../tools/ui-automation/scenarios/ForgePeerStudy.js" as Peer

TestCase {
    id: testCase
    name: "ForgeAutomation"
    property int serial: 0
    property var records: []
    QtObject {
        id: auditProbe
        function record(name, value) { testCase.records.push({name:name, value:value}) }
        function wheel() { return true }
    }
    QtObject {
        id: cardCatalog
        function enrichLimitedCards(cards) { return cards }
    }

    function test_peerStudyPreservesDefaultEnabledTransport_data() {
        return [{tag:"direct", state:"direct"}, {tag:"completed fallback", state:"relay"}]
    }
    function test_peerStudyPreservesDefaultEnabledTransport(data) {
        const clicks = []
        const driver = {peerAudit:true, peerDone:false, spectator:false, peerStep:0,
            seat:1, peerExpected:data.state, peerConnectingObserved:false,
            session:{active:true}, table:{presentation:{}},
            require:(value, message) => verify(value, message),
            click:name => { clicks.push(name); return true }, capture:() => {}}
        const transport = {directPeerEnabled:true, peerTransportState:data.state}
        const probe = {readShared:() => ({started:true}), record:() => {}}
        verify(Peer.tick(driver, transport, probe))
        compare(driver.peerStep, 1)
        verify(Peer.tick(driver, transport, probe))
        verify(driver.peerDone)
        compare(clicks.length, 0)
    }

    function test_unplayable_opening_hands_use_bounded_real_mulligan_controls() {
        records = []
        const clicks = []
        let delivered = false
        const cards = Array.from({length:7}, (_, i) => ({cardId:"opening-" + i,
            name:"Opening spell " + (++serial), typeLine:"Sorcery"}))
        const driver = {existingLimitedMatch:false,
            session:{gameId:"opening-" + (++serial), cardForInspection:id => cards.find(c => c.cardId === id)},
            table:{presentation:{children:[{objectName:"forgeHand", visibleCards:cards}]}},
            click:name => { clicks.push(name); return delivered }
        }
        Player.chooseOpeningHand(driver)
        delivered = true
        Player.chooseOpeningHand(driver)
        Player.chooseOpeningHand(driver)
        Player.chooseOpeningHand(driver)
        compare(clicks, ["rulesPromptOption-$mulligan", "rulesPromptOption-$mulligan",
            "rulesPromptOption-$mulligan", "rulesPromptOption-$keep"])
        compare(records.length, 3)
        driver.session.gameId = "opening-" + (++serial)
        driver.existingLimitedMatch = true
        Player.chooseOpeningHand(driver)
        compare(clicks[4], "rulesPromptOption-$keep")
        driver.existingLimitedMatch = false
        driver.session.gameId = "opening-" + (++serial)
        cards[0].name = "Land " + (++serial); cards[0].typeLine = "Basic Land — Plains"
        cards[1].name = "Land " + (++serial); cards[1].typeLine = "Creature // Land"
        Player.chooseOpeningHand(driver)
        compare(clicks[5], "rulesPromptOption-$keep")
    }

    function test_optional_copy_stops_repeating_after_delivered_acceptance() {
        records = []
        const detail = "Apply replacement effect of Mockingbird? You may have it enter as a copy."
        const rows = [{label:"No", responseId:"no"}, {label:"Yes", responseId:"yes"}]
        const clicks = []
        let delivered = false
        const session = {gameId:"copy-" + (++serial), turn:3, promptKind:"chooseBoolean", promptDetail:detail}
        const driver = {
            session:session,
            item:() => ({count:rows.length, itemAtIndex:i => rows[i]}),
            click:name => { clicks.push(name); if (delivered) session.promptDetail = "next prompt"; return delivered },
            require:(ok, message) => verify(ok, message)
        }
        Player.scalar(driver)
        delivered = true
        Player.scalar(driver)
        session.promptDetail = detail
        Player.scalar(driver)
        compare(clicks, ["rulesScalarChoice-yes", "rulesScalarChoice-yes", "rulesScalarChoice-no"])
        compare(records.length, 1)
        compare(records[0].value.detail, detail)
        session.gameId = "copy-" + (++serial)
        session.promptDetail = detail
        Player.scalar(driver)
        compare(clicks[3], "rulesScalarChoice-yes")
    }

    function test_companion_is_selected_before_confirming_optional_choice() {
        records = []
        const clicks = []
        const card = {name:"Yorion, Sky Nomad", objectName:"companion", selected:false, nativeSelected:false, selectable:true}
        const driver = {
            session:{promptTitle:"Choose a companion", promptDetail:"Choose between 0 and 1 card(s).",
                     promptMinCardSelections:0, promptMaxCardSelections:1},
            item:name => name === "rulesCardCandidates" ? {count:1, itemAtIndex:() => card} : {enabled:true},
            click:name => { clicks.push(name); if (name === "companion") card.selected = true; return true },
            capture:() => {}, require:(ok, message) => verify(ok, message)
        }
        Choices.chooseCards(driver)
        Choices.chooseCards(driver)
        compare(clicks, ["companion", "rulesConfirmCards"])
        compare(records[0].value.selected, ["Yorion, Sky Nomad"])
    }
}
