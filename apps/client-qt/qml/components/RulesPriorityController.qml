// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

pragma ComponentBehavior: Bound

import QtQuick

Item {
    id: root

    required property var tableController
    readonly property var session: tableController.rulesSession
    required property var settings
    readonly property bool fullControl: settings.forgeFullControl
    property string yieldMode: ""
    readonly property var phaseStops: settings.forgePhaseStops
    property var previousPhaseStops: ({})
    property int promptRevision: 0
    property string lastAutomaticPrompt: ""
    property string acknowledgedStop: ""
    property string heldPrompt: ""
    property bool holdNextPriority: false
    property string yieldGame: ""
    property int yieldTurn: -1
    property int yieldSeat: -1
    property var yieldedStack: []
    property bool ready: false
    property bool passMenuOpen: false

    readonly property bool active: tableController.roomConnected && tableController.hostingPaused !== true
        && tableController.localSeat >= 0 && !tableController.sideboarding
        && session.active && !session.gameOver
    readonly property bool isPriorityPrompt: active && session.promptPending
        && session.promptSupported && session.promptKind === "chooseAction"
    readonly property int decidingSeat: {
        void session.snapshotRevision
        return typeof session.controllingSeat === "function"
            ? session.controllingSeat(session.prioritySeat) : session.prioritySeat
    }
    readonly property int actingSeat: decidingSeat === tableController.localSeat
        ? session.prioritySeat : tableController.localSeat
    readonly property bool inputBlocked: passMenuOpen || tableController.priorityInputBlocked === true
        || (tableController.cardActionPicker && tableController.cardActionPicker.opened === true)
    readonly property var options: {
        void promptRevision
        return isPriorityPrompt && typeof session.promptOptionItems === "function"
                ? session.promptOptionItems() : []
    }
    readonly property var stackIds: {
        void session.snapshotRevision
        return typeof session.stackObjectIds === "function" ? session.stackObjectIds() : []
    }
    readonly property bool ownStack: {
        void session.snapshotRevision
        return stackIds.length > 0 && typeof session.cardForInspection === "function"
            && stackIds.every(id => {
                const card = session.cardForInspection(id)
                return card.zone === "stack" && card.controllerSeat === root.actingSeat
            })
    }
    readonly property bool quietPhase: stackIds.length === 0
        && (["upkeep", "draw", "end_combat", "cleanup"].includes(session.step)
            || (session.activeSeat !== actingSeat && ["main1", "main2"].includes(session.step))
            || (session.activeSeat === actingSeat && session.step === "end"))
    readonly property bool canAct: isPriorityPrompt && !inputBlocked
        && !tableController.rulesResponsePending && decidingSeat === tableController.localSeat
    readonly property bool canPass: canAct && options.some(option => option.responseId === "$pass")
    readonly property string promptKey: session.gameId + ":" + session.promptId
    readonly property string phaseKey: session.gameId + ":" + session.turn + ":"
        + session.activeSeat + ":" + session.step
    readonly property bool stopped: active && hasStop(session.step, session.activeSeat === actingSeat)
        && acknowledgedStop !== phaseKey
    readonly property bool automaticallyPassing: passTimer.running
    readonly property bool canStartYield: active && !inputBlocked
        && (!session.promptPending || isPriorityPrompt)

    visible: false

    function hasStop(step, ownTurn) {
        return phaseStops[(ownTurn ? "own:" : "other:") + step] === true
    }

    function toggleStop(step, ownTurn) {
        settings.toggleForgePhaseStop(step, ownTurn)
    }

    function setFullControl(value) {
        settings.forgeFullControl = value
        // Reselecting the saved mode also ends an explicit temporary yield.
        if (settings.forgeFullControl === value)
            applyPriorityMode()
    }

    function applyPriorityMode() {
        cancelYield(false)
        heldPrompt = ""
        holdNextPriority = false
        schedule()
    }

    function cancelYield(hold = true) {
        yieldMode = ""
        yieldedStack = []
        if (hold && isPriorityPrompt && !tableController.rulesResponsePending
                && lastAutomaticPrompt !== promptKey) {
            heldPrompt = promptKey
            holdNextPriority = false
        } else if (hold) {
            holdNextPriority = true
        }
        if (ready)
            passTimer.stop()
    }

    function resetTransient() {
        cancelYield(false)
        lastAutomaticPrompt = ""
        heldPrompt = ""
        holdNextPriority = false
        acknowledgedStop = ""
    }

    function beginYield(mode) {
        if (!canStartYield || !["response", "turn", "stack"].includes(mode)
                || (mode === "stack" && stackIds.length === 0))
            return false
        yieldGame = session.gameId
        yieldTurn = session.turn
        yieldSeat = session.activeSeat
        yieldedStack = stackIds.slice()
        yieldMode = mode
        heldPrompt = ""
        holdNextPriority = false
        // Starting a deliberate yield acknowledges the current phase's stop.
        acknowledgedStop = phaseKey
        schedule()
        return true
    }

    function validateYield() {
        if (!yieldMode)
            return
        if (!active || yieldGame !== session.gameId || yieldTurn !== session.turn
                || yieldSeat !== session.activeSeat) {
            cancelYield(false)
            return
        }
        if (stopped) {
            cancelYield()
            return
        }
        // Bounded stack/response yields stop on a new spell or trigger, even
        // if the number of stack objects did not change.
        if (yieldMode !== "turn" && stackIds.some(id => !yieldedStack.includes(id))) {
            cancelYield()
            return
        }
        if (yieldMode === "stack" && stackIds.length === 0)
            cancelYield()
    }

    function shouldPassAutomatically() {
        return canPass && (!fullControl || yieldMode.length > 0) && !stopped && !holdNextPriority && heldPrompt !== promptKey
            && lastAutomaticPrompt !== promptKey
            && (yieldMode.length > 0 || quietPhase || ownStack || session.promptAutoPassEligible === true)
    }

    function schedule() {
        if (!ready)
            return
        validateYield()
        passTimer.stop()
        if (holdNextPriority && canAct && lastAutomaticPrompt !== promptKey) {
            heldPrompt = promptKey
            holdNextPriority = false
        }
        if (shouldPassAutomatically())
            passTimer.start()
    }

    function passOnce() {
        if (!canPass)
            return false
        passTimer.stop()
        acknowledgedStop = phaseKey
        heldPrompt = ""
        holdNextPriority = false
        // A rejected/republished response is never automatically retried.
        lastAutomaticPrompt = promptKey
        tableController.wsModel.respondRulesPrompt(session.promptId, "$pass")
        return true
    }

    function respondAction(responseId) {
        if (!canAct || !options.some(option => option.responseId === responseId
                && !option.responseId.startsWith("$")))
            return false
        cancelYield(false)
        tableController.wsModel.respondRulesPrompt(session.promptId, responseId)
        return true
    }

    Timer {
        id: passTimer
        interval: 80
        onTriggered: {
            root.validateYield()
            if (root.shouldPassAutomatically())
                root.passOnce()
        }
    }

    onCanPassChanged: schedule()
    onFullControlChanged: applyPriorityMode()
    onPhaseStopsChanged: {
        // Only a newly enabled stop for this phase reopens an acknowledged window.
        const key = (session.activeSeat === actingSeat ? "own:" : "other:") + session.step
        if (phaseStops[key] === true && previousPhaseStops[key] !== true) {
            acknowledgedStop = ""
            if (active)
                cancelYield()
        }
        previousPhaseStops = phaseStops
        schedule()
    }
    onInputBlockedChanged: schedule()
    onStoppedChanged: schedule()
    onActiveChanged: {
        if (!active)
            resetTransient()
        schedule()
    }
    Component.onCompleted: { ready = true; schedule() }
    Component.onDestruction: { ready = false; passTimer.stop() }

    Connections {
        target: root.session
        function onPromptChanged() {
            root.promptRevision++
            // Required decisions always remain manual. Choosing a new action
            // after one also requires a fresh explicit continuous yield.
            if (root.yieldMode && root.session.promptPending && root.session.promptKind !== "chooseAction")
                root.cancelYield(false)
            root.schedule()
        }
        function onSnapshotChanged() { root.schedule() }
    }
    Connections {
        target: root.tableController
        function onLocalSeatChanged() { root.resetTransient() }
    }
    Connections {
        target: root.tableController.wsModel
        ignoreUnknownSignals: true
        function onLastErrorChanged() {
            if (root.tableController.wsModel.lastError)
                root.cancelYield()
        }
    }
}
