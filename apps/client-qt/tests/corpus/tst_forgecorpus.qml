// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Window
import QtQuick.Controls.Basic
import QtTest
import "../../qml/components"
import "../../qml/screens"

TestCase {
    id: test
    name: "ForgeCardCorpus"
    when: windowShown
    property bool nativeWindow: testRulesPrompt.corpusEnvironment("HEXPROOF_FORGE_CORPUS_NATIVE") === "1"
    property string capturePath: testRulesPrompt.corpusEnvironment("HEXPROOF_FORGE_CORPUS_CAPTURES")
    property string captureCards: testRulesPrompt.corpusEnvironment("HEXPROOF_FORGE_CORPUS_CAPTURE_CARDS")
    property int serial: 100000
    ApplicationWindow {
        id: window
        title: "Hexproof isolated Forge corpus replay"
        width: 1600; height: 1000; visible: true
        QtObject {
            id: room
            property int maxSeats: 2
            property string roomId: "CORPUS"
            property string roomName: "Native card resolution replay"
            property string role: "player"
            property int seatIndex: 0
            property bool host: true
            property string phase: "started"
            property string matchMode: "bo1"
            property string format: "modern"
            property string deckFormat: "modern"
            property string hostingMode: "server"
            property bool hostConnected: true
            property var hostStatus: ({migrating:false})
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
            property string peerTransportState: "off"
            property bool peerTransportAvailable: false
            property bool directPeerEnabled: false
            property string lastError: ""
            property var responses: []
            function record(answer) {
                const complete = Object.assign({ResponseID:"", CardIDs:[], TargetIDs:[], Assignments:null,
                    ChoiceIDs:[], OrderedIDs:[], ScryPiles:[], DamageOrderIDs:null, DamageAssignments:null,
                    ChosenNumber:null, Name:""}, answer)
                responses = responses.concat([complete]); rulesResponsePending = true
            }
            function respondRulesPrompt(id, response) { record({ResponseID:response}) }
            function respondRulesPromptWithTargets(id, response, targets) { record({ResponseID:response, TargetIDs:targets}) }
            function respondRulesPromptWithCards(id, response, cards) { record({ResponseID:response, CardIDs:cards}) }
            function respondRulesPromptWithChoices(id, choices) { record({ResponseID:"$submit", ChoiceIDs:choices}) }
            function respondRulesPromptWithNumber(id, value) { record({ResponseID:"$submit", ChosenNumber:value}) }
            function respondRulesPromptWithName(id, value) { record({ResponseID:"$submit", Name:value}) }
            function respondRulesPromptWithOrder(id, value) { record({ResponseID:"$submit", OrderedIDs:value}) }
            function respondRulesPromptWithScry(id, value) {
                record({ResponseID:"$submit", ScryPiles:value.map(p => ({Destination:p.destination, CardIDs:p.cardIds}))})
            }
        }
        QtObject {
            id: catalog
            property int imageRevision: 0
            property bool installed: false
            signal catalogChanged()
            function tableImageSource(name, set, number) { return "" }
            function imageSource(name, set, number) { return "" }
            function cardDisplayName(name) { return name }
            function cardTypeLine(name) {
                if (["Forest", "Island", "Mountain", "Swamp", "Plains", "Wastes"].includes(name)) return "Land"
                return ""
            }
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
    function initTestCase() {
        testTranslations.setLanguage("en")
        if (nativeWindow) {
            window.showMaximized()
            tryCompare(window, "visibility", Window.Maximized)
        }
        window.requestActivate()
        tryCompare(window, "active", true)
        if (nativeWindow) console.info("CORPUS_WINDOW " + JSON.stringify({requested:"maximized",
            actual:window.visibility, width:window.width, height:window.height,
            screenWidth:window.screen.width, screenHeight:window.screen.height,
            dpr:window.screen.devicePixelRatio, evidence:"native-qt-replay", osInputVerified:false}))
        table.priority.setFullControl(true)
    }
    function visibleNamed(root, name) {
        if (!root || !root.visible) return null
        if (root.objectName === name && root.enabled) return root
        const children = root.children || []
        for (let i = 0; i < children.length; ++i) {
            const found = visibleNamed(children[i], name)
            if (found) return found
        }
        return null
    }
    function item(name) {
        const dialog = findChild(table, "rulesCardChoiceDialog")
        const popup = dialog && dialog.visible ? visibleNamed(dialog.contentItem, name) : null
        return popup || visibleNamed(window.contentItem, name)
    }
    function clickNamed(name) {
        let target = null
        tryVerify(() => { target = item(name); return target !== null }, 1500, name)
        const center = target.mapToItem(window.contentItem, target.width / 2, target.height / 2)
        verify(center.x >= 0 && center.y >= 0 && center.x < window.width && center.y < window.height, "Control outside window: " + name)
        mouseClick(target)
    }
    function selectCard(id, cards) {
        const grid = item("rulesCardCandidates")
        const index = cards.findIndex(card => card.id === id)
        if (grid && index >= 0 && typeof grid.positionViewAtIndex === "function") {
            grid.positionViewAtIndex(index, GridView.Contain)
            wait(1)
        }
        clickNamed("rulesCardCandidate-" + id)
    }
    function reply(frame) {
        const answer = frame.answer, prompt = frame.prompt
        switch (prompt.kind) {
        case "payManaCost": clickNamed("rulesPromptOption-" + answer.ResponseID); break
        case "chooseBoolean": case "chooseFromSelection":
            for (const id of answer.ChoiceIDs || []) {
                const list = item("rulesScalarCandidates")
                const index = prompt.choices.findIndex(choice => choice.responseId === id)
                if (list && index >= 0) { list.positionViewAtIndex(index, ListView.Contain); wait(1) }
                clickNamed("rulesScalarChoice-" + id)
            }
            if (!transport.rulesResponsePending) clickNamed("rulesConfirmChoices")
            break
        case "chooseCards":
            for (const id of answer.CardIDs || []) selectCard(id, prompt.cards)
            clickNamed("rulesConfirmCards"); break
        case "revealCards": clickNamed("acknowledgeRevealButton"); break
        case "chooseCardName":
            const input = item("rulesCardNameInput")
            verify(input !== null, "Card name input")
            mouseClick(input); keySequence("Ctrl+A")
            for (const character of answer.Name) keyClick(character)
            clickNamed("confirmCardNameButton"); break
        case "chooseNumber":
            const number = item("rulesNumberInput")
            verify(number !== null, "Number input")
            mouseClick(number.contentItem); keySequence("Ctrl+A")
            for (const character of String(answer.ChosenNumber)) keyClick(character)
            keyClick(Qt.Key_Tab)
            tryCompare(number, "value", answer.ChosenNumber)
            clickNamed("rulesConfirmNumber"); break
        case "chooseBoardTargets":
            for (const id of answer.TargetIDs || []) {
                const target = prompt.targets.find(t => t.responseId === id)
                verify(target !== undefined, "Projected target")
                let candidate = item("rulesTarget-" + id)
                if (!candidate && target.kind === "player") candidate = item("rulesPlayerTarget" + target.seat)
                if (!candidate) candidate = item("forgeCard-" + target.objectId)
                if (!candidate) candidate = item("forgeHandCard-" + target.objectId)
                if (!candidate) candidate = item("forgeStackEntry-" + target.objectId)
                verify(candidate !== null, "Visible legal target " + id + " " + target.objectId)
                mouseClick(candidate)
            }
            if (!transport.rulesResponsePending) clickNamed("rulesConfirmTargets")
            break
        case "reorder": clickNamed("rulesConfirmOrder"); break
        case "scry": clickNamed("confirmScryButton"); break
        default: fail("No UI driver for " + prompt.kind)
        }
    }
    function test_native_frames_data() { return testRulesPrompt.corpusCases() }
    function capture(name) {
        wait(180) // Let hover/color transitions settle for the retained image.
        waitForRendering(window.contentItem)
        const snapshot = grabImage(window.contentItem)
        verify(snapshot.width > 0 && snapshot.height > 0, "Nonempty test-window capture")
        // QtTest save() returns void and throws if the image cannot be saved.
        snapshot.save(capturePath + "/" + name + ".png")
    }
    function assertPersistentState(snapshot, captureTag) {
        for (const zone of snapshot.zones) {
            const stateful = zone.cards.filter(card => (card.annotations || []).length > 0 || card.exiledCardCount > 0)
            if (!stateful.length) continue
            const command = zone.zone === "command"
            if (command) {
                clickNamed(zone.ownerSeat === room.seatIndex || room.seatIndex < 0 && zone.ownerSeat === 0
                    ? "forgeZone-command" : "forgeOpponentZone-command")
                tryCompare(findChild(table, "forgeZonePopup"), "opened", true)
            }
            for (const card of stateful) {
                const popup = findChild(table, "forgeZonePopup")
                const root = command ? popup.contentItem : table
                let tile = null
                tryVerify(() => {
                    tile = findChild(root, "forgeCard-" + card.id)
                    return tile !== null && tile.visible && tile.width > 0 && tile.height > 0
                }, 1500,
                    "Persistent state source " + card.id)
                waitForRendering(tile)
                for (const annotation of card.annotations || [])
                    verify(tile.persistentSummary.includes(annotation.value), "Missing " + annotation.kind + ": " + annotation.value)
                if (card.exiledCardCount > 0)
                    verify(tile.persistentSummary.includes("Exiled:"), "Linked exile missing from the source tile")
                const label = findChild(tile, "forgeCardState-" + card.id)
                verify(label !== null && label.visible && label.height > 0,
                    "Persistent state text is visible: " + card.id)
            }
            if (command) {
                if (captureTag && room.role === "player" && room.seatIndex === zone.ownerSeat)
                    capture(captureTag + "-command")
                mouseClick(findChild(findChild(table, "forgeZonePopup").contentItem, "forgeCloseZonePopup"))
                tryCompare(findChild(table, "forgeZonePopup"), "visible", false)
            }
        }
    }
    function test_native_frames(data) {
        const record = testRulesPrompt.corpusCase(data.index)
        const captureCase = capturePath && (!captureCards || new RegExp(captureCards).test(record.card))
        compare(record.nativeStatus, "resolved", "Native resolution prerequisite")
        testRulesPrompt.clear(); wait(1); room.seatIndex = 0
        for (let index = 0; index < record.frames.length; ++index) {
            const frame = record.frames[index]
            room.seatIndex = frame.actor
            transport.rulesResponsePending = false; transport.responses = []
            verify(testRulesPrompt.applySnapshot(frame.snapshot), "Real native snapshot")
            waitForRendering(table)
            frame.prompt.promptId = ++serial
            verify(testRulesPrompt.applyPrompt(frame.prompt), "Real native prompt")
            waitForRendering(table)
            for (const target of frame.prompt.targets || []) {
                if (target.selected && target.kind === "card") {
                    const tile = item("forgeCard-" + target.objectId)
                    verify(tile !== null && tile.nativeSelected, "Native cost selection is visible")
                }
            }
            for (const card of frame.prompt.cards || []) {
                if (!card.selected) continue
                const list = item("rulesCardCandidates")
                verify(list !== null)
                list.positionViewAtIndex(frame.prompt.cards.indexOf(card), GridView.Contain)
                waitForRendering(list)
                const tile = item("rulesCardCandidate-" + card.id)
                verify(tile !== null && tile.nativeSelected && !tile.selected,
                    "Existing private selection stays visible without becoming a new response")
            }
            if (captureCase && (frame.prompt.targets.some(target => target.selected)
                || frame.prompt.cards.some(card => card.selected)))
                capture(data.index + "-decision-" + index)
            reply(frame)
            tryCompare(transport, "rulesResponsePending", true, 1500, record.card + " frame " + index)
            compare(transport.responses.length, 1, "One UI response")
            compare(transport.responses[0], frame.answer, record.card + " complete response")
            waitForRendering(table)
        }
        verify(testRulesPrompt.applyPrompt({roomId:"CORPUS", gameId:"card-corpus", pending:false, totalDamage:0,
            options:[], choices:[], cards:[], scryDestinations:[], targets:[], contextCards:[],
            contextTargets:[], combatSources:[], combatTargets:[], damageTargets:[]}))
        waitForRendering(table)
        for (let seat = 0; seat < record.after.length; ++seat) {
            room.role = seat === 2 ? "spectator" : "player"; room.seatIndex = seat === 2 ? -1 : seat
            verify(testRulesPrompt.applySnapshot(record.after[seat]), "Resolved viewer snapshot")
            waitForRendering(table)
            assertPersistentState(record.after[seat], captureCase ? String(data.index) : "")
        }
        room.role = "player"; room.seatIndex = 0
        if (record.after.length > 0) verify(testRulesPrompt.applySnapshot(record.after[0]))
        waitForRendering(table)
        if (captureCase) {
            capture(String(data.index))
        }
    }
    function cleanup() {
        const popup = findChild(table, "forgeZonePopup")
        if (popup) popup.close()
        testRulesPrompt.clear(); wait(1); room.role = "player"; transport.rulesResponsePending = false
    }
}
