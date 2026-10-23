// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtTest
import "../scenarios/ForgeLotusBloomStudy.js" as Lotus

TestCase {
    name: "ForgeLotusBloomPlayer"

    function test_startingPlayerChoiceDoesNotBecomeASacrifice_data() {
        return [
            {tag:"owner wins coin toss", player:"Audit Player 1", phase:"opening", source:"", expected:true},
            {tag:"observer wins coin toss", player:"Audit Player 2", phase:"opening", source:"", expected:true},
            {tag:"after suspend setup", player:"Audit Player 1", phase:"wait-bloom", source:"bloom", expected:false},
            {tag:"a selected Bloom", player:"Audit Player 1", phase:"opening", source:"bloom", expected:false}
        ]
    }
    function test_startingPlayerChoiceDoesNotBecomeASacrifice(data) {
        const session = {promptKind:"chooseBoolean", promptTitle:"Confirm decision",
            promptDetail:data.player + ", you have won the coin toss.\n\nWould you like to play or draw?"}
        compare(Lotus.startingPlayerChoice(session, data.phase, data.source), data.expected)
        session.promptDetail = "Do you want to sacrifice Lotus Bloom?"
        verify(!Lotus.startingPlayerChoice(session, data.phase, data.source))
        session.promptDetail = data.player + ", you have won the coin toss.\n\nWould you like to play or draw?"
        session.promptKind = "chooseFromSelection"
        verify(!Lotus.startingPlayerChoice(session, data.phase, data.source))
    }

    function test_paymentColorAndImmediateCompletion_data() {
        return [
            {tag:"sacrifice confirmation still open", phase:"activate", selected:false, source:"battlefield",
                spell:"stack", pending:true, kind:"chooseBoolean", expected:"waiting"},
            {tag:"manual payment color chooser", phase:"activate", selected:false, source:"graveyard",
                spell:"stack", pending:true, kind:"chooseFromSelection", expected:"waiting"},
            {tag:"dedicated color chooser", phase:"activate", selected:false, source:"graveyard",
                spell:"stack", pending:true, kind:"chooseColor", expected:"waiting"},
            {tag:"old payment skips colors and returns priority", phase:"activate", selected:false, source:"graveyard",
                spell:"stack", pending:true, kind:"chooseAction", expected:"missing-color"},
            {tag:"old payment skips colors and hands over priority", phase:"activate", selected:false, source:"graveyard",
                spell:"stack", pending:false, kind:"", blue:2, expected:"missing-color"},
            {tag:"chosen mana immediately finishes complete cost", phase:"after-color", selected:true, source:"graveyard",
                spell:"stack", pending:true, kind:"chooseAction", expected:"paid"},
            {tag:"chosen mana leaves explicit payment open", phase:"after-color", selected:true, source:"graveyard",
                spell:"stack", pending:true, kind:"payManaCost", expected:"payment-open"},
            {tag:"paid spell awaits opponent priority", phase:"after-color", selected:true, source:"graveyard",
                spell:"stack", pending:false, kind:"", blue:2, expected:"paid"},
            {tag:"between cost confirmation and published color chooser", phase:"activate", selected:false, source:"graveyard",
                spell:"stack", pending:false, kind:"", blue:0, expected:"waiting"},
            {tag:"color answer accepted before mana update publishes", phase:"after-color", selected:true, source:"graveyard",
                spell:"stack", pending:false, kind:"", blue:0, expected:"waiting"},
            {tag:"casting still waits for sacrificed source", phase:"after-color", selected:true, source:"battlefield",
                spell:"stack", pending:false, kind:"", expected:"waiting"},
            {tag:"three mana cost zero residue cannot prove an uncommitted cast", phase:"after-color", selected:true,
                source:"graveyard", spell:"stack", pending:false, kind:"", blue:0, surplus:0, expected:"waiting"},
            {tag:"three mana spell is paid at next priority", phase:"after-color", selected:true,
                source:"graveyard", spell:"stack", pending:true, kind:"chooseAction", blue:0, surplus:0, expected:"paid"},
            {tag:"three mana spell resolved during Smart passing", phase:"after-color", selected:true,
                source:"graveyard", spell:"battlefield", pending:false, kind:"", blue:0, surplus:0, expected:"paid"},
            {tag:"three mana payment skipped colors and resolved", phase:"activate", selected:false,
                source:"graveyard", spell:"battlefield", pending:false, kind:"", blue:0, surplus:0, expected:"missing-color"},
            {tag:"paid Opt has popped off stack during scry", phase:"after-color", selected:true,
                source:"graveyard", spell:"", pending:true, kind:"scry", blue:2, surplus:2, name:"Opt", expected:"paid"},
            {tag:"unknown zone scry cannot prove an unrelated spell", phase:"after-color", selected:true,
                source:"graveyard", spell:"", pending:true, kind:"scry", blue:2, surplus:2, name:"Divination", expected:"waiting"},
            {tag:"scry still requires the actual blue surplus", phase:"after-color", selected:true,
                source:"graveyard", spell:"", pending:true, kind:"scry", blue:0, surplus:2, name:"Opt", expected:"waiting"},
            {tag:"scry still requires explicit color choice", phase:"after-color", selected:false,
                source:"graveyard", spell:"", pending:true, kind:"scry", blue:2, surplus:2, name:"Opt", expected:"waiting"}
        ]
    }
    function test_paymentColorAndImmediateCompletion(data) {
        const session = {promptPending:data.pending, promptKind:data.kind}
        compare(Lotus.paymentTransition(session, data.phase, data.selected, data.source, data.spell,
            data.blue || 0, data.surplus === undefined ? 2 : data.surplus, data.name || ""), data.expected)
    }

    function test_paymentManaUsesTheChosenRegisteredSpell() {
        const registration = {mainboard:[{name:"Opt", manaValue:1, manaCost:"{U}"},
            {name:"Spiketail Drakeling", manaValue:3, manaCost:"{1}{U}{U}"},
            {name:"Divination", manaValue:3, manaCost:"{2}{U}"},
            {name:"Plains", manaValue:0, manaCost:""}]}
        compare(Lotus.expectedBlueSurplus(registration, "Opt"), 2)
        compare(Lotus.expectedBlueSurplus(registration, "Spiketail Drakeling"), 0)
        compare(Lotus.expectedBlueSurplus(registration, "Divination"), 0)
        compare(Lotus.expectedBlueSurplus(registration, "Plains"), -1)
        compare(Lotus.expectedBlueSurplus(registration, "Undisclosed card"), -1)
    }

    function test_smartPriorityRequiresAnUnmodifiedDefault() {
        const priority = {fullControl:false, holdNextPriority:false, heldPrompt:"", yieldMode:"", phaseStops:{}}
        verify(Lotus.smartPriority(priority))
        for (const property of ["fullControl", "holdNextPriority"]) {
            priority[property] = true
            verify(!Lotus.smartPriority(priority))
            priority[property] = false
        }
        priority.phaseStops = {"own:end":true}
        verify(!Lotus.smartPriority(priority))
        priority.phaseStops = {"own:end":false}
        verify(Lotus.smartPriority(priority))
        priority.heldPrompt = "game:prompt"
        verify(!Lotus.smartPriority(priority))
        priority.heldPrompt = ""
        priority.yieldMode = "turn"
        verify(!Lotus.smartPriority(priority))
    }

    function test_manaComesFromTheFieldRatherThanItsHitTarget() {
        const pool = [{color:"U", amount:2}]
        const field = {objectName:"forgeField-0", manaPool:pool,
            children:[{objectName:"rulesPlayerTarget0", children:[]}]}
        const presentation = {children:[field]}
        compare(Lotus.manaForPresentation(presentation, 0), pool)
        compare(Lotus.manaForPresentation(presentation, 1), [])
        field.manaPool = []
        compare(Lotus.manaForPresentation(presentation, 0), [])
    }

    function test_manaLegacyFallbackRequiresAnActualCollectionRole() {
        const pool = [{color:"U", amount:3}]
        const target = {objectName:"rulesPlayerTarget0", manaPool:pool, children:[]}
        const presentation = {children:[{objectName:"forgeField-0", children:[target]}]}
        compare(Lotus.manaForPresentation(presentation, 0), pool)
        target.manaPool = {color:"U", amount:3}
        compare(Lotus.manaForPresentation(presentation, 0), [])
        target.manaPool = undefined
        compare(Lotus.manaForPresentation(presentation, 0), [])
    }

    function test_optionalPlainsDoNotHideTheNativeAutomaticPlan() {
        for (const phase of ["wait-bloom", "ready"]) {
            verify(!Lotus.setupLandAllowed("lotus-bloom-auto", phase))
            verify(Lotus.setupLandAllowed("lotus-bloom-payment", phase))
            verify(Lotus.setupLandAllowed("lotus-bloom-manual", phase))
        }
        for (const phase of ["opening", "activate", "pay-spell", "wait-spell", "done"])
            verify(!Lotus.setupLandAllowed("lotus-bloom-manual", phase))
    }

    function test_preFloatedManaCanFinishCastingWithoutAPaymentPrompt_data() {
        return [
            {tag:"actual paid cast reaches stack without further prompt", phase:"pay-spell", produced:3,
                zone:"stack", pool:0, pending:false, kind:"", expected:true},
            {tag:"paid creature already resolved", phase:"pay-spell", produced:3,
                zone:"battlefield", pool:0, pending:true, kind:"chooseAction", expected:true},
            {tag:"paid Divination already resolved", phase:"pay-spell", produced:3,
                zone:"graveyard", pool:0, pending:false, kind:"", expected:true},
            {tag:"empty pool alone does not prove casting", phase:"pay-spell", produced:3,
                zone:"hand", pool:0, pending:false, kind:"", expected:false},
            {tag:"actual remaining payment needs its native controls", phase:"pay-spell", produced:3,
                zone:"stack", pool:0, pending:true, kind:"payManaCost", expected:false},
            {tag:"no verified three mana production", phase:"pay-spell", produced:0,
                zone:"stack", pool:0, pending:false, kind:"", expected:false},
            {tag:"mana has not been spent", phase:"pay-spell", produced:3,
                zone:"stack", pool:3, pending:false, kind:"", expected:false},
            {tag:"a cost confirmation remains open", phase:"pay-spell", produced:3,
                zone:"stack", pool:0, pending:true, kind:"chooseBoolean", expected:false},
            {tag:"unrelated phase cannot advance", phase:"activate", produced:3,
                zone:"stack", pool:0, pending:false, kind:"", expected:false}
        ]
    }
    function test_preFloatedManaCanFinishCastingWithoutAPaymentPrompt(data) {
        const session = {promptPending:data.pending, promptKind:data.kind}
        compare(Lotus.floatedCastPaid(session, data.phase, data.produced, data.zone, data.pool), data.expected)
    }

    function test_standaloneCannotReturnToPriorityWithoutItsColorChoice_data() {
        return [
            {tag:"sacrificed source skipped color and returned priority", phase:"activate", selected:false,
                zone:"graveyard", pending:true, kind:"chooseAction", expected:true},
            {tag:"source has not been sacrificed", phase:"activate", selected:false,
                zone:"battlefield", pending:true, kind:"chooseAction", expected:false},
            {tag:"actual native color chooser remains pending", phase:"activate", selected:false,
                zone:"graveyard", pending:true, kind:"chooseFromSelection", expected:false},
            {tag:"sacrifice confirmation still pending", phase:"activate", selected:false,
                zone:"graveyard", pending:true, kind:"chooseBoolean", expected:false},
            {tag:"color choice already supplied", phase:"activate", selected:true,
                zone:"graveyard", pending:true, kind:"chooseAction", expected:false},
            {tag:"a later phase already observed production", phase:"wait-mana", selected:true,
                zone:"graveyard", pending:true, kind:"chooseAction", expected:false},
            {tag:"no prompt between asynchronous callbacks", phase:"activate", selected:false,
                zone:"graveyard", pending:false, kind:"chooseAction", expected:false}
        ]
    }
    function test_standaloneCannotReturnToPriorityWithoutItsColorChoice(data) {
        const session = {promptPending:data.pending, promptKind:data.kind}
        compare(Lotus.standaloneColorSkipped(session, data.phase, data.selected, data.zone), data.expected)
    }
}
