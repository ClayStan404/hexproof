// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic
import QtTest
import "../../qml/components"

TestCase {
    id: testCase
    name: "CommanderDraftPlan"
    when: windowShown
    property var view: null
    readonly property var drafted: [
        {instanceId: "a", name: "Blue Partner", displayName: "蓝色搭档", typeLine: "Legendary Creature — Wizard",
            colors: "UR", cardColors: "U", manaCost: "{2}{U}", oracleText: "Partner"},
        {instanceId: "a2", name: "Blue Partner", displayName: "蓝色搭档", typeLine: "Legendary Creature — Wizard",
            colors: "UR", cardColors: "U", manaCost: "{2}{U}", oracleText: "Partner"},
        {instanceId: "b", name: "Green Partner", typeLine: "Legendary Creature — Elf", colors: "G", cardColors: "G", manaCost: "{G}"},
        {instanceId: "c", name: "House Rule Creature", typeLine: "Creature — Wizard", colors: "W", cardColors: "W", manaCost: "{W}"},
        {instanceId: "d", name: "Eligible Walker", typeLine: "Legendary Planeswalker — Test", colors: "B", cardColors: "B",
            oracleText: "Eligible Walker can be your commander."},
        {instanceId: "e", name: "Background", typeLine: "Legendary Enchantment — Background", colors: "W", cardColors: "W"},
        {instanceId: "u", name: "Missing Data", cardColors: "G"},
        {instanceId: "p", name: "The Prismatic Piper", typeLine: "Legendary Creature — Shapeshifter", colors: "", cardColors: ""},
        {instanceId: "x", name: "Colorless", typeLine: "Legendary Creature — Construct", colors: "", cardColors: ""}
    ]
    ApplicationWindow {
        id: testWindow
        width: 1200
        height: 800
        visible: true
        QtObject {
            id: limited
            signal snapshotChanged()
            property string eventType: "commander_cube"
            property string tournamentId: "cube-1"
            property string stage: "drafting"
            property int packRound: 1
            property int direction: 1
            property var currentPack: []
            property var pool: []
            property var participants: [{participantId: "p1", displayName: "Alice"}, {participantId: "p2", displayName: "Bob"}]
        }
        QtObject { id: tournament; property string participantId: "p1" }
        QtObject {
            id: ws
            property bool connected: true
            property string serverUrl: "ws://127.0.0.1:57320/ws"
            property var picked: []
            property int pickCalls: 0
            function pickLimitedCards(ids) { picked = ids.slice(); pickCalls++ }
            function pickLimitedCard(id) { picked = [id]; pickCalls++ }
        }
        QtObject {
            id: catalog
            property int imageRevision: 0
            function enrichLimitedCards(cards) { return cards.map(card => Object.assign({}, card)) }
            function imageSource(name, setCode, collectorNumber) { return "" }
            function tableImageSource(name, setCode, collectorNumber) { return "" }
        }
        QtObject {
            id: store
            property var entries: ({})
            property int saveCalls: 0
            function key(server, event, participant) { return JSON.stringify([server, event, participant]) }
            function loadDraft(server, event, participant) { return entries[key(server, event, participant)] || ({}) }
            function saveDraft(server, event, participant, draft) {
                entries[key(server, event, participant)] = JSON.parse(JSON.stringify(draft))
                saveCalls++
            }
        }
        Component {
            id: draftComponent
            LimitedDraftView {
                anchors.fill: parent
                limitedModel: limited
                tournamentModel: tournament
                wsModel: ws
                cardCatalogModel: catalog
                draftStore: store
            }
        }
    }
    function createView() {
        view = draftComponent.createObject(testWindow.contentItem)
        verify(view !== null)
        waitForRendering(view)
        tryCompare(view.commanderPlan, "restoredScope", view.commanderPlan.scope)
    }
    function init() {
        Theme.uiScale = 1
        testWindow.width = 1200
        testWindow.height = 800
        store.entries = ({})
        store.saveCalls = 0
        limited.eventType = "commander_cube"
        limited.tournamentId = "cube-1"
        limited.participants = [{participantId: "p1", displayName: "Alice"}, {participantId: "p2", displayName: "Bob"}]
        limited.pool = drafted.slice()
        limited.currentPack = [
            {instanceId: "pack-r", name: "Red Spell", typeLine: "Sorcery", colors: "R", cardColors: "R"},
            {instanceId: "pack-w", name: "White Spell", typeLine: "Sorcery", colors: "W", cardColors: "W"},
            {instanceId: "pack-u", name: "Unknown Spell", typeLine: "Sorcery", cardColors: "G"},
            {instanceId: "pack-g", name: "Green Spell", typeLine: "Sorcery", colors: "G", cardColors: "G"}
        ]
        ws.serverUrl = "ws://127.0.0.1:57320/ws"
        ws.picked = []
        ws.pickCalls = 0
        tournament.participantId = "p1"
        createView()
    }
    function cleanup() {
        if (view) { view.destroy(); view = null }
        wait(0)
        Theme.uiScale = 1
    }
    function test_marksUseOnlyPhysicalPicksAndDoNotPickOrSubmit() {
        const plan = view.commanderPlan
        const originalPool = JSON.stringify(limited.pool)
        const originalPack = JSON.stringify(limited.currentPack)
        plan.toggle("pack-r")
        plan.toggle("foreign")
        compare(plan.selectedIds, [])
        plan.toggle("a")
        plan.toggle("a2")
        compare(plan.selectedIds, ["a", "a2"], "Distinct same-name drafted copies remain distinct")
        plan.toggle("b")
        compare(plan.selectedIds, ["a", "a2"], "Planning is limited to two cards")
        compare(ws.pickCalls, 0)
        compare(JSON.stringify(limited.pool), originalPool)
        compare(JSON.stringify(limited.currentPack), originalPack)
        plan.toggle("a")
        plan.toggle("b")
        compare(plan.selectedIds, ["a2", "b"])
    }
    function test_identityUsesCommanderIdentityNotFaceColors() {
        const plan = view.commanderPlan
        plan.toggle("a")
        compare(plan.identityColors, ["U", "R"])
        verify(plan.identityKnown)
        compare(plan.packGuide.outside, 2)
        compare(plan.packGuide.unknown, 1)
        plan.toggle("b")
        compare(plan.identityColors, ["U", "R", "G"])
        compare(plan.packGuide.outside, 1)
        compare(plan.poolGuide.unknown, 2, "Piper color is intentionally not invented while drafting")
        compare(findChild(view, "commanderDraftPlanNames").text, "★ 蓝色搭档 / ★ Green Partner")
    }
    function test_unknownAndPiperNeverPretendToBeColorless() {
        const plan = view.commanderPlan
        plan.toggle("u")
        verify(!plan.identityKnown)
        compare(plan.packGuide.outside, 0)
        plan.toggle("u")
        plan.toggle("p")
        verify(!plan.identityKnown)
        plan.toggle("p")
        plan.toggle("x")
        verify(plan.identityKnown)
        compare(plan.identityColors, [])
        compare(plan.packGuide.outside, 3)
    }
    function test_candidateShortcutAndUnrestrictedLocalizedSearch() {
        const plan = view.commanderPlan
        verify(plan.visibleCards.some(card => card.instanceId === "u"), "Missing metadata must remain available")
        verify(plan.visibleCards.some(card => card.instanceId === "d"))
        verify(plan.visibleCards.some(card => card.instanceId === "e"))
        verify(!plan.visibleCards.some(card => card.instanceId === "c"))
        plan.searchText = "蓝色"
        compare(plan.visibleCards.map(card => card.instanceId), ["a", "a2"])
        plan.searchText = "House Rule"
        compare(plan.visibleCards.length, 0)
        plan.showAll = true
        compare(plan.visibleCards.map(card => card.instanceId), ["c"])
        plan.toggle("c")
        plan.showAll = false
        compare(plan.visibleCards.map(card => card.instanceId), ["c"], "A house-rule mark remains editable in the shortcut")
        compare(view.enrichedPack.length, limited.currentPack.length)
    }
    function test_marksSurviveSnapshotsVisibilityAndReentryWithoutFinalDraftCollision() {
        const plan = view.commanderPlan
        store.saveDraft(ws.serverUrl, limited.tournamentId, tournament.participantId,
            {mainboardInstanceIds: ["c"], commanderInstanceIds: ["c"]})
        plan.toggle("a")
        limited.currentPack = limited.currentPack.slice(1)
        limited.snapshotChanged()
        wait(0)
        compare(plan.selectedIds, ["a"])
        view.visible = false
        wait(0)
        view.visible = true
        waitForRendering(view)
        compare(plan.selectedIds, ["a"])
        view.destroy()
        view = null
        wait(0)
        createView()
        compare(view.commanderPlan.selectedIds, ["a"])
        compare(store.loadDraft(ws.serverUrl, limited.tournamentId, tournament.participantId),
            {mainboardInstanceIds: ["c"], commanderInstanceIds: ["c"]})
    }
    function test_scopeChangesCannotLeakPlansAcrossParticipantsServersOrEvents() {
        view.commanderPlan.toggle("a")
        tournament.participantId = "p2"
        tryCompare(view.commanderPlan, "selectedIds", [])
        view.commanderPlan.toggle("b")
        tournament.participantId = "p1"
        tryCompare(view.commanderPlan, "selectedIds", ["a"])
        ws.serverUrl = "ws://127.0.0.1:57321/ws"
        tryCompare(view.commanderPlan, "selectedIds", [])
        ws.serverUrl = "ws://127.0.0.1:57320/ws"
        tryCompare(view.commanderPlan, "selectedIds", ["a"])
        limited.tournamentId = "cube-2"
        tryCompare(view.commanderPlan, "selectedIds", [])
    }
    function test_invalidSavedIdsArePrunedAndBounded() {
        view.destroy()
        view = null
        store.saveDraft(ws.serverUrl, JSON.stringify(["commander-draft-plan", limited.tournamentId]), tournament.participantId,
            {plannedCommanderIds: ["pack-r", "foreign", "a", "a", "a2", "b"]})
        createView()
        compare(view.commanderPlan.selectedIds, ["a", "a2"])
        compare(ws.pickCalls, 0)
    }
    function test_nativeDraftStoreRestoresVariantListIds() {
        const eventKey = JSON.stringify(["commander-draft-plan", limited.tournamentId])
        testLimitedDraftStore.removeDraft(ws.serverUrl, eventKey, tournament.participantId)
        view.draftStore = testLimitedDraftStore
        wait(0)
        view.commanderPlan.toggle("a")
        view.commanderPlan.toggle("a2")
        const saved = testLimitedDraftStore.loadDraft(ws.serverUrl, eventKey, tournament.participantId)
        compare(view.commanderPlan.sanitize(saved.plannedCommanderIds), ["a", "a2"])
        view.destroy()
        view = draftComponent.createObject(testWindow.contentItem, {draftStore: testLimitedDraftStore})
        verify(view !== null)
        tryCompare(view.commanderPlan, "selectedIds", ["a", "a2"])
        testLimitedDraftStore.removeDraft(ws.serverUrl, eventKey, tournament.participantId)
    }
    function test_candidateClickAndPreviewStayInsideModalWorkflow() {
        const plan = view.commanderPlan
        findChild(view, "commanderDraftPlanButton").clicked()
        const popup = findChild(view, "commanderDraftPlanPicker")
        tryCompare(popup, "opened", true)
        const list = findChild(view, "commanderDraftPlanCandidates")
        tryVerify(() => list.itemAtIndex(0) !== null)
        const mark = findChild(list.itemAtIndex(0), "commanderDraftMark-a")
        verify(mark !== null)
        mouseClick(mark)
        compare(plan.selectedIds, ["a"])
        const cardRow = mark.parent.children[0]
        mouseMove(cardRow, cardRow.width / 2, cardRow.height / 2)
        tryCompare(plan, "hoverPreviewVisible", true)
        compare(plan.inspectedCard.instanceId, "a")
        const preview = findChild(view, "commanderDraftPlanPreview")
        compare(preview.parent, popup.parent)
        const markPosition = mark.mapToItem(preview.parent, 0, 0)
        verify(preview.x + preview.width <= markPosition.x || preview.x >= markPosition.x + mark.width,
            "Hover art must not obscure the mark/unmark button")
        plan.searchText = "Green"
        verify(!plan.hoverPreviewVisible)
        findChild(view, "commanderDraftPlanDone").clicked()
        tryCompare(popup, "opened", false)
        compare(ws.pickCalls, 0)
    }
    function test_planningAndFiltersDoNotHidePackOrBlockOffIdentityPicks() {
        view.commanderPlan.toggle("a")
        view.commanderPlan.searchText = "no match"
        view.filters.query = "no match"
        compare(view.enrichedPack.length, 4)
        view.selectCard("pack-w")
        view.confirmCard("pack-g")
        compare(ws.picked, ["pack-w", "pack-g"])
        compare(ws.pickCalls, 1)
        compare(view.commanderPlan.selectedIds, ["a"])
    }
    function test_regularCubeIsUnchanged() {
        limited.eventType = "cube_draft"
        verify(!view.commanderPlan.visible)
        view.commanderPlan.toggle("a")
        compare(view.commanderPlan.selectedIds, [])
        compare(store.saveCalls, 0)
        view.confirmCard("pack-w")
        compare(ws.picked, ["pack-w"])
        compare(ws.pickCalls, 1)
    }
    function test_autodraftAndWithdrawnSeatsCannotRaceManualPicks() {
        view.selectCard("pack-r")
        view.selectCard("pack-w")
        verify(view.canConfirm)
        limited.participants = [{participantId: "p1", displayName: "Alice", autoDraft: true}, {participantId: "p2", displayName: "Bob"}]
        verify(!view.canConfirm)
        view.confirmPick()
        view.confirmCard("pack-g")
        view.selectCard("pack-g")
        compare(ws.pickCalls, 0)
        compare(view.selectedInstanceIds, ["pack-r", "pack-w"])
        limited.participants = [{participantId: "p1", displayName: "Alice", withdrawn: true}, {participantId: "p2", displayName: "Bob"}]
        verify(!view.canConfirm)
        view.confirmPick()
        compare(ws.pickCalls, 0)
        limited.participants = [{participantId: "p1", displayName: "Alice"}, {participantId: "p2", displayName: "Bob"}]
        verify(view.canConfirm)
        view.confirmPick()
        compare(ws.pickCalls, 1)
    }
    function test_compactHighScalePopupKeepsDoneAndListReachable() {
        Theme.uiScale = 1.35
        testWindow.width = 900
        testWindow.height = 620
        waitForRendering(view)
        const button = findChild(view, "commanderDraftPlanButton")
        verify(button !== null)
        button.clicked()
        const popup = findChild(view, "commanderDraftPlanPicker")
        tryCompare(popup, "opened", true)
        const list = findChild(view, "commanderDraftPlanCandidates")
        const done = findChild(view, "commanderDraftPlanDone")
        waitForRendering(list)
        verify(list.height >= 80, "Planner preserves a useful scrolling card viewport")
        const point = done.mapToItem(testWindow.contentItem, 0, 0)
        verify(point.y >= 0 && point.y + done.height <= testWindow.height,
            "Done button must stay on screen: y=" + point.y + " h=" + done.height + " window=" + testWindow.height)
        verify(popup.x >= 0 && popup.x + popup.width <= testWindow.width)
        verify(list.contentHeight > list.height)
        list.positionViewAtEnd()
        waitForRendering(list)
        verify(list.contentY > 0)
        done.clicked()
        tryCompare(popup, "opened", false)
    }
}
