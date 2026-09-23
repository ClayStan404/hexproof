// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

pragma ComponentBehavior: Bound
import QtQuick

Item {
    id: root

    required property var wsModel
    property var gameTableModel: null
    readonly property var room: wsModel.roomSession
    readonly property var rules: wsModel.rulesSession
    readonly property bool connected: wsModel.inRoom === true
        && wsModel.connected !== false && wsModel.reconnecting !== true
    readonly property int localSeat: room.seatIndex
    readonly property bool active: connected && localSeat >= 0 && room.phase === "started"
    property var pending: ({})
    property string observedGame: ""
    property string observedTurn: ""
    property int observedActiveSeat: -1
    property int contextRevision: 0

    visible: false
    onConnectedChanged: reset()
    onLocalSeatChanged: reset()
    onActiveChanged: if (!active) reset()

    function reset() {
        ++contextRevision
        pending = ({})
        observedGame = ""
        observedTurn = ""
        observedActiveSeat = -1
    }

    function manualCue(type, payload) {
        switch (type) {
        case "game.draw": return "draw"
        case "game.shuffle_library":
        case "game.mulligan": return "shuffle"
        case "game.set_tapped": return "tap"
        case "game.play_land":
        case "game.create_token":
        case "game.create_emblem": return "play"
        case "game.cast_commander": return "cast"
        case "game.move_card":
        case "game.move_cards":
            if (payload.fromZone === payload.toZone) return ""
            if (payload.toZone === "stack") return "cast"
            if (payload.fromZone === "stack") return "resolve"
            if (payload.fromZone === "library" && payload.toZone === "hand") return "draw"
            return "play"
        case "game.move_library_cards":
        case "game.search_library":
        case "game.discard_hand":
        case "game.reveal":
        case "game.recall_revealed": return "play"
        case "game.set_arrow":
            if (payload.kind === "attack" || payload.kind === "block") return payload.kind
            return payload.kind === "target" ? "select" : "cancel"
        case "game.set_counter": {
            if (payload.counter === "life") {
                const life = gameTableModel ? gameTableModel.seatData(localSeat).life : undefined
                if (payload.delta < 0 || (typeof life === "number" && payload.value < life))
                    return "damage"
            }
            return payload.label !== undefined ? "confirm" : "click"
        }
        case "game.set_commander_damage": return payload.delta > 0 ? "damage" : "click"
        case "game.next_turn": return "" // The public turn transition provides the cue.
        case "game.set_card_face":
        case "game.set_face_down":
        case "game.set_card_counter":
        case "game.set_phase":
        case "game.set_response_status":
        case "game.set_attachment": return "click"
        default: return ""
        }
    }

    function rulesCue(payload) {
        if (!rules.active || !rules.promptPending || !rules.promptSupported
                || payload.promptId !== rules.promptId) return ""
        const response = payload.responseId || ""
        // Automatic priority passing must stay quiet, including long yield runs.
        if (response === "$pass") return ""
        if (response === "$cancel") return "cancel"
        if (response === "$mulligan") return "shuffle"
        if (response === "$pass-stack") return "resolve"
        const options = typeof rules.promptOptionItems === "function" ? rules.promptOptionItems() : []
        const option = options.find(value => value.responseId === response)
        if (option) {
            if (option.kind === "cast") return "cast"
            if (option.kind === "playLand") return "play"
            if (option.kind === "activateAbility")
                return rules.promptKind === "payManaCost" ? "tap" : "cast"
            if (option.kind === "undoMana") return "cancel"
            if (option.kind === "pass") return ""
        }
        return "confirm"
    }

    function cueFor(type, payload) {
        return type === "rules.respond" ? rulesCue(payload) : manualCue(type, payload)
    }

    function queued(requestId, type, payload) {
        if (!active) return
        if (type === "game.restart") reset()
        const cue = cueFor(type, payload)
        if (!cue) return
        const next = Object.assign({}, pending)
        // Keep only recent local operations even if a peer stops acknowledging.
        const keys = Object.keys(next)
        if (keys.length >= 256) delete next[keys[0]]
        next[requestId] = true
        pending = next
        SoundEffects.play(cue)
    }

    function completed(requestId, type, payload, failed) {
        const wasAudible = pending[requestId] === true
        const next = Object.assign({}, pending)
        delete next[requestId]
        pending = next
        if (failed && active && (wasAudible || (!requestId && cueFor(type, payload)))) {
            const revision = contextRevision
            // Transport teardown rejects queued commands before publishing its
            // disconnected state. Wait until those synchronous changes settle.
            Qt.callLater(function() {
                if (root.active && root.contextRevision === revision)
                    SoundEffects.play("error")
            })
        }
    }

    function observeTurn(game, turn, activeSeat) {
        if (!active || !game || activeSeat < 0) {
            observedGame = ""
            observedTurn = ""
            observedActiveSeat = -1
            return
        }
        const changed = observedGame === game && observedTurn !== ""
            && (observedTurn !== turn || observedActiveSeat !== activeSeat)
        observedGame = game
        observedTurn = turn
        observedActiveSeat = activeSeat
        if (changed && activeSeat === localSeat) SoundEffects.play("turn")
    }

    function observeManual(snapshot) {
        if (room.rulesMode === "forge") return
        if (!snapshot || !snapshot.gameNumber
                || (snapshot.sideboard && Object.keys(snapshot.sideboard).length > 0)
                || (snapshot.result && Object.keys(snapshot.result).length > 0)) {
            observeTurn("", "", -1)
            return
        }
        const seat = (snapshot.seats || []).find(value => value.seat === snapshot.activeSeat)
        observeTurn(room.roomId + ":" + snapshot.gameNumber,
                    String(seat ? seat.turnCount : 0), snapshot.activeSeat)
    }

    Connections {
        target: root.wsModel
        function onCommandQueued(requestId, commandType, payload) { root.queued(requestId, commandType, payload) }
        function onCommandSucceeded(requestId, commandType, payload) { root.completed(requestId, commandType, payload, false) }
        function onCommandFailed(requestId, commandType, payload, error) { root.completed(requestId, commandType, payload, true) }
        function onGameRestarted() { root.reset() }
        function onGameSnapshotDataChanged(snapshot) { root.observeManual(snapshot) }
    }

    Connections {
        target: root.rules
        function onSnapshotChanged() {
            if (root.room.rulesMode !== "forge") return
            root.observeTurn(root.rules.active && !root.rules.gameOver ? root.rules.gameId : "",
                             String(root.rules.turn), root.rules.activeSeat)
        }
    }
}
