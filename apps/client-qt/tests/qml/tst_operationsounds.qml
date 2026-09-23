// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtTest
import "../../qml/components"

TestCase {
    id: testCase
    name: "OperationSounds"
    property var previousBackend: null

    QtObject {
        id: recorder
        property var cues: []
        function play(cue) { cues = cues.concat([cue]) }
    }
    QtObject {
        id: room
        property string roomId: "SOUND01"
        property string rulesMode: "manual"
        property string phase: "started"
        property int seatIndex: 0
    }
    QtObject {
        id: rules
        property bool active: true
        property bool promptPending: true
        property bool promptSupported: true
        property int promptId: 42
        property string promptKind: "chooseAction"
        property var options: []
        property string gameId: "sound-game"
        property int turn: 1
        property int activeSeat: 0
        property bool gameOver: false
        function promptOptionItems() { return options }
        signal snapshotChanged()
    }
    QtObject {
        id: transport
        property var roomSession: room
        property var rulesSession: rules
        property bool inRoom: true
        property bool connected: true
        property bool reconnecting: false
        signal commandQueued(string requestId, string commandType, var payload)
        signal commandSucceeded(string requestId, string commandType, var payload)
        signal commandFailed(string requestId, string commandType, var payload, string error)
        signal gameRestarted()
        signal gameSnapshotDataChanged(var snapshot)
    }
    QtObject {
        id: gameTable
        function seatData(seat) { return {seat:seat, life:20} }
    }
    OperationSounds {
        wsModel: transport
        gameTableModel: gameTable
    }

    function init() {
        previousBackend = SoundEffects.backend
        SoundEffects.backend = recorder
        transport.inRoom = false
        transport.connected = true
        transport.reconnecting = false
        room.roomId = "SOUND01"
        room.rulesMode = "manual"
        room.phase = "started"
        room.seatIndex = 0
        rules.active = true
        rules.gameId = "sound-game"
        rules.turn = 1
        rules.activeSeat = 0
        rules.gameOver = false
        rules.promptPending = true
        rules.promptSupported = true
        rules.promptId = 42
        rules.promptKind = "chooseAction"
        rules.options = []
        transport.inRoom = true
        recorder.cues = []
    }
    function cleanup() { SoundEffects.backend = previousBackend }

    function test_backendMayBeAbsent() {
        SoundEffects.backend = null
        transport.commandQueued("1", "game.draw", {count:1})
        compare(recorder.cues.length, 0)
    }

    function test_manualCommands_data() {
        return [
            {tag:"draw-many-once", type:"game.draw", payload:{count:7}, cue:"draw"},
            {tag:"shuffle", type:"game.shuffle_library", payload:{}, cue:"shuffle"},
            {tag:"mulligan", type:"game.mulligan", payload:{}, cue:"shuffle"},
            {tag:"tap", type:"game.set_tapped", payload:{cardId:"card", tapped:true}, cue:"tap"},
            {tag:"untap", type:"game.set_tapped", payload:{cardId:"card", tapped:false}, cue:"tap"},
            {tag:"play-land", type:"game.play_land", payload:{cardId:"land"}, cue:"play"},
            {tag:"cast", type:"game.move_card", payload:{fromZone:"hand", toZone:"stack"}, cue:"cast"},
            {tag:"resolve", type:"game.move_card", payload:{fromZone:"stack", toZone:"battlefield"}, cue:"resolve"},
            {tag:"move-many-once", type:"game.move_cards", payload:{fromZone:"battlefield", toZone:"graveyard", cardIds:["a", "b"]}, cue:"play"},
            {tag:"attack", type:"game.set_arrow", payload:{kind:"attack", sourceCardIds:["a"], targetSeat:1}, cue:"attack"},
            {tag:"block", type:"game.set_arrow", payload:{kind:"block", sourceCardIds:["a"], targetCardId:"b"}, cue:"block"},
            {tag:"clear-arrows", type:"game.set_arrow", payload:{}, cue:"cancel"},
            {tag:"life-decrease", type:"game.set_counter", payload:{counter:"life", value:18}, cue:"damage"},
            {tag:"life-delta", type:"game.set_counter", payload:{counter:"life", delta:-1}, cue:"damage"},
            {tag:"life-increase", type:"game.set_counter", payload:{counter:"life", value:21}, cue:"click"},
            {tag:"counter", type:"game.set_counter", payload:{counter:"counter-1", delta:1}, cue:"click"}
        ]
    }
    function test_manualCommands(data) {
        transport.commandQueued("1", data.type, data.payload)
        compare(recorder.cues, [data.cue])
        transport.commandSucceeded("1", data.type, data.payload)
        compare(recorder.cues, [data.cue])
    }

    function test_dragLayoutChatAndSnapshotRefreshAreQuiet() {
        transport.commandQueued("1", "game.arrange_battlefield", {cards:[{id:"a", x:0.4, y:0.5}]})
        transport.commandQueued("2", "game.move_card", {fromZone:"battlefield", toZone:"battlefield"})
        transport.commandQueued("3", "game.say", {message:"Hello"})
        manualSnapshot(1, 0, 2)
        manualSnapshot(1, 0, 2)
        compare(recorder.cues, [])
    }

    function test_errorsDoNotReplayOnAcknowledgementOrDisconnect() {
        transport.commandQueued("1", "game.draw", {count:1})
        transport.commandFailed("1", "game.draw", {count:1}, "Rejected")
        transport.commandFailed("1", "game.draw", {count:1}, "Repeated")
        tryCompare(recorder, "cues", ["draw", "error"])
        transport.commandFailed("", "game.set_tapped", {cardId:"a"}, "Not queued")
        tryCompare(recorder, "cues", ["draw", "error", "error"])
        transport.commandQueued("2", "game.draw", {count:1})
        transport.inRoom = false
        transport.commandFailed("2", "game.draw", {count:1}, "Disconnected")
        compare(recorder.cues, ["draw", "error", "error", "draw"])
    }

    function test_teardownFailuresPrecedeConnectionState_data() {
        return [{tag:"disconnect"}, {tag:"leave-room"}, {tag:"replace-connection"}]
    }
    function test_teardownFailuresPrecedeConnectionState(data) {
        transport.commandQueued("1", "game.draw", {count:1})
        // WsClient fails pending requests while its old connection/room state
        // is still visible, then clears that state in the same event loop turn.
        transport.commandFailed("1", "game.draw", {count:1}, "Connection ended")
        if (data.tag === "leave-room") transport.inRoom = false
        else transport.connected = false
        // Even an immediate replacement connection must discard the old error.
        if (data.tag === "replace-connection") transport.connected = true
        wait(1)
        compare(recorder.cues, ["draw"])
    }

    function test_forgeUsesTypedChoicesAndKeepsAutomaticPriorityQuiet() {
        room.rulesMode = "forge"
        rules.options = [{responseId:"opaque-land", kind:"playLand"},
                         {responseId:"opaque-spell", kind:"cast"},
                         {responseId:"opaque-ability", kind:"activateAbility"}]
        transport.commandQueued("1", "rules.respond", {promptId:42, responseId:"opaque-land"})
        transport.commandQueued("2", "rules.respond", {promptId:42, responseId:"opaque-spell"})
        transport.commandQueued("3", "rules.respond", {promptId:42, responseId:"opaque-ability"})
        transport.commandQueued("4", "rules.respond", {promptId:42, responseId:"$pass"})
        rules.promptKind = "payManaCost"
        transport.commandQueued("5", "rules.respond", {promptId:42, responseId:"opaque-ability"})
        transport.commandQueued("6", "rules.respond", {promptId:42, responseId:"$cancel"})
        rules.promptKind = "mulligan"
        transport.commandQueued("7", "rules.respond", {promptId:42, responseId:"$mulligan"})
        transport.commandQueued("8", "rules.respond", {promptId:42, responseId:"$keep"})
        rules.promptKind = "chooseAttackers"
        transport.commandQueued("9", "rules.respond", {promptId:42, responseId:"$submit", assignments:[]})
        compare(recorder.cues, ["play", "cast", "cast", "tap", "cancel", "shuffle", "confirm", "confirm"])
    }

    function test_forgeIgnoresStaleAndUnsupportedPrompts() {
        room.rulesMode = "forge"
        transport.commandQueued("1", "rules.respond", {promptId:41, responseId:"$keep"})
        rules.promptSupported = false
        transport.commandQueued("2", "rules.respond", {promptId:42, responseId:"$keep"})
        rules.promptSupported = true
        rules.promptPending = false
        transport.commandQueued("3", "rules.respond", {promptId:42, responseId:"$keep"})
        compare(recorder.cues, [])
    }

    function manualSnapshot(game, seat, turnCount) {
        transport.gameSnapshotDataChanged({gameNumber:game, activeSeat:seat,
            seats:[{seat:seat, turnCount:turnCount}], sideboard:{}, result:{}})
    }
    function test_manualTurnCuesOnlyAfterBaselineAndOnlyForLocalTurn() {
        manualSnapshot(1, 0, 2)
        manualSnapshot(1, 1, 2)
        manualSnapshot(1, 1, 2)
        compare(recorder.cues, [])
        manualSnapshot(1, 0, 3)
        compare(recorder.cues, ["turn"])
        transport.connected = false
        transport.connected = true
        manualSnapshot(1, 0, 4)
        manualSnapshot(2, 0, 1)
        transport.gameRestarted()
        manualSnapshot(2, 0, 1)
        compare(recorder.cues, ["turn"])
        room.seatIndex = -1
        manualSnapshot(2, 1, 2)
        manualSnapshot(2, 0, 3)
        compare(recorder.cues, ["turn"])
    }

    function test_forgeTurnCuesIgnoreRepeatedSnapshotsNewGameAndReconnect() {
        room.rulesMode = "forge"
        rules.snapshotChanged()
        rules.snapshotChanged()
        rules.activeSeat = 1
        rules.turn = 2
        rules.snapshotChanged()
        compare(recorder.cues, [])
        rules.activeSeat = 0
        rules.turn = 3
        rules.snapshotChanged()
        compare(recorder.cues, ["turn"])
        transport.reconnecting = true
        transport.reconnecting = false
        rules.turn = 5
        rules.snapshotChanged()
        rules.gameId = "new-game"
        rules.turn = 1
        rules.snapshotChanged()
        rules.gameOver = true
        rules.turn = 3
        rules.snapshotChanged()
        compare(recorder.cues, ["turn"])
    }
}
