// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

pragma ComponentBehavior: Bound

import QtQuick

Item {
    id: root

    required property var tableController
    readonly property var session: tableController.rulesSession
    readonly property string currentGameId: session.gameId
    property int promptRevision: 0
    property int promptSeat: -1
    property var selectedTargetIds: ({})
    readonly property int selectedCount: Object.keys(selectedTargetIds).length
    readonly property bool contextActive: tableController.roomConnected && tableController.hostingPaused !== true
        && tableController.localSeat >= 0 && promptSeat === tableController.localSeat
        && !tableController.sideboarding
        && session.active && !session.gameOver
        && session.promptPending && session.promptSupported
    readonly property bool canRespond: contextActive && !tableController.rulesResponsePending
    // Offered objects stay marked while an answer is in flight, but nothing is
    // actionable until the game replies.
    readonly property bool waitingForResponse: contextActive && tableController.rulesResponsePending === true
    property string submittedKind: ""
    property string submittedId: ""
    property var paymentQueue: []
    property string queuedPaymentId: ""
    property int queuedPromptId: 0
    property int lastPromptId: 0
    // Most recent last. The tapped strip prefers the member used last.
    property var recentActivations: []
    // The lane whose member fan is open, so Escape can close it.
    property var fanOwner: null
    readonly property bool choosingTargets: contextActive && session.promptKind === "chooseBoardTargets"
    readonly property bool validTargets: choosingTargets
        && selectedCount >= session.promptMinSelections
        && selectedCount <= session.promptMaxSelections
    readonly property var targetCandidates: {
        void promptRevision
        return choosingTargets && typeof session.boardTargetCandidates === "function"
                ? session.boardTargetCandidates() : []
    }
    readonly property var fallbackTargets: targetCandidates.filter(candidate => !targetOnTable(candidate))
    readonly property var nativeSelectedTargetIds: {
        const selected = ({})
        for (const candidate of targetCandidates)
            if (candidate.nativeSelected === true) selected[candidate.responseId] = true
        return selected
    }
    readonly property int nativeSelectedCount: Object.keys(nativeSelectedTargetIds).length
    readonly property var zoneActions: {
        void promptRevision
        void session.snapshotRevision
        if (!contextActive || session.promptKind !== "chooseAction"
                || typeof session.promptOptionItems !== "function") return []
        return session.promptOptionItems().filter(action => action.cardId
            && ["cast", "playLand", "activateAbility", "undoMana"].includes(action.kind)
            && !objectOnTable("card", action.cardId)).map(action => {
                const card = session.cardPlacement(action.cardId)
                return card.visibleIdentity === true
                    ? Object.assign({}, action, {zone: card.zone, zoneOwnerSeat: card.zoneOwnerSeat}) : null
            }).filter(action => action !== null)
    }

    visible: false
    Component.onCompleted: {
        promptSeat = tableController.localSeat
        lastPromptId = session.promptId
    }

    // Emitted when an offered object is activated while an answer is in flight.
    signal responseBlocked(string kind, string objectId)
    signal paymentQueueCleared()

    function resetSelection() {
        selectedTargetIds = ({})
        clearSubmitted()
    }

    function clearSubmitted() {
        submittedKind = ""
        submittedId = ""
    }

    function clearPaymentQueue() {
        paymentQueue = []
        queuedPaymentId = ""
        queuedPromptId = 0
    }

    onContextActiveChanged: {
        if (!contextActive) {
            clearPaymentQueue()
            resetSelection()
        }
    }
    onWaitingForResponseChanged: {
        if (waitingForResponse)
            return
        clearSubmitted()
        if (paymentQueue.length)
            Qt.callLater(dropStalePaymentQueue)
    }
    // An error or timeout releases the guard without a new prompt; the queued
    // intent belonged to that answer and is dropped. Checked a turn later,
    // because a new prompt may be applied just after the guard releases.
    function dropStalePaymentQueue() {
        if (waitingForResponse || !paymentQueue.length || session.promptId !== queuedPromptId)
            return
        clearPaymentQueue()
        paymentQueueCleared()
    }
    onCurrentGameIdChanged: {
        clearPaymentQueue()
        recentActivations = []
        resetSelection()
    }

    Connections {
        target: root.session
        function onPromptChanged() {
            // A republication of the pending prompt is the same decision. The
            // answer, its submitted ring and any queued intent stay.
            const republished = root.waitingForResponse && root.session.promptPending
                && root.session.promptId === root.lastPromptId
            root.lastPromptId = root.session.promptId
            root.promptSeat = root.tableController.localSeat
            root.promptRevision++
            if (republished)
                return
            const queued = root.paymentQueue.slice()
            const previousPayment = root.queuedPaymentId
            root.resetSelection()
            root.consumePaymentQueue(queued, previousPayment)
        }
        function onSnapshotChanged() {
            // Snapshot-only changes can revoke visible identities or end a game.
            if (!root.contextActive)
                root.resetSelection()
        }
        ignoreUnknownSignals: true
    }
    Connections {
        target: root.tableController
        function onLocalSeatChanged() { root.resetSelection() }
    }

    function offeredActionsForCard(cardId) {
        void promptRevision
        if (!contextActive || !cardId || typeof session.cardActionsForCard !== "function")
            return []
        return session.cardActionsForCard(cardId)
    }

    function actionsForCard(cardId) {
        return canRespond ? offeredActionsForCard(cardId) : []
    }

    function submitCardAction(cardId, responseId) {
        const actions = actionsForCard(cardId)
        if (!actions.some(action => action.responseId === responseId))
            return false
        if (tableController.priority)
            tableController.priority.cancelYield(false)
        tableController.wsModel.respondRulesPrompt(session.promptId, responseId)
        const recent = recentActivations.filter(id => id !== cardId)
        recent.push(cardId)
        recentActivations = recent.slice(-16)
        if (waitingForResponse) {
            submittedKind = "card"
            submittedId = cardId
        }
        return true
    }

    function objectTargetIds(kind, objectId) {
        void promptRevision
        if (!choosingTargets || !objectId
                || typeof session.targetResponseIdsForObject !== "function")
            return []
        return session.targetResponseIdsForObject(kind, objectId)
    }

    function seatTargetIds(seat) {
        void promptRevision
        if (!choosingTargets || seat < 0
                || typeof session.targetResponseIdsForSeat !== "function")
            return []
        return session.targetResponseIdsForSeat(seat)
    }

    function objectOffered(kind, objectId) {
        if (!contextActive)
            return false
        if (choosingTargets)
            return objectTargetIds(kind, objectId).length === 1
        return kind === "card" && offeredActionsForCard(objectId).length > 0
    }

    function objectActionable(kind, objectId) {
        return canRespond && objectOffered(kind, objectId)
    }

    function objectSelected(kind, objectId) {
        return objectTargetIds(kind, objectId).some(id => targetSelected(id))
    }

    function nativeObjectSelected(kind, objectId) {
        return objectTargetIds(kind, objectId).some(id => nativeSelectedTargetIds[id] === true)
    }

    function targetSelected(responseId) {
        return selectedTargetIds[responseId] === true || nativeSelectedTargetIds[responseId] === true
    }

    function seatOffered(seat) {
        return contextActive && seatTargetIds(seat).length === 1
    }

    function seatActionable(seat) {
        return canRespond && seatOffered(seat)
    }

    function seatSelected(seat) {
        return seatTargetIds(seat).some(id => targetSelected(id))
    }

    function paymentSourceActions(cardId) {
        // cardActionsForCard already selects this object. Its maps omit cardId.
        return offeredActionsForCard(cardId).filter(action => action.kind === "activateAbility")
    }

    function paymentQueueable(kind, objectId) {
        if (kind !== "card" || !waitingForResponse || !objectId || objectId === submittedId)
            return false
        if (session.promptKind !== "payManaCost" || !session.promptPaymentId)
            return false
        void session.snapshotRevision
        if (session.cardPlacement(objectId).zone !== "battlefield")
            return false
        return paymentSourceActions(objectId).length === 1
    }

    // True when activating the object would add it to the queue.
    function canQueuePayment(kind, objectId) {
        return paymentQueueable(kind, objectId) && paymentQueue.indexOf(objectId) < 0
            && paymentQueue.length < 8
    }

    function tryQueuePayment(kind, objectId) {
        if (!paymentQueueable(kind, objectId))
            return false
        const next = paymentQueue.slice()
        const index = next.indexOf(objectId)
        if (index >= 0) {
            next.splice(index, 1)
            paymentQueue = next
            if (!next.length)
                clearPaymentQueue()
            SoundEffects.play("cancel")
            return true
        }
        if (next.length >= 8)
            return false
        next.push(objectId)
        paymentQueue = next
        queuedPaymentId = session.promptPaymentId
        queuedPromptId = session.promptId
        SoundEffects.play("select")
        return true
    }

    function dismissQueuedPayment(cardId) {
        if (!paymentQueue.length)
            return false
        const next = paymentQueue.slice()
        let index = next.length - 1
        if (cardId) {
            index = next.indexOf(cardId)
            if (index < 0)
                return false
        }
        next.splice(index, 1)
        paymentQueue = next
        if (!next.length)
            clearPaymentQueue()
        SoundEffects.play("cancel")
        return true
    }

    function consumePaymentQueue(queued, previousPayment) {
        if (!queued.length)
            return
        const samePayment = canRespond && session.promptKind === "payManaCost"
                && session.promptPaymentId === previousPayment && previousPayment.length > 0
        const actions = samePayment ? paymentSourceActions(queued[0]) : []
        if (actions.length === 1 && submitCardAction(queued[0], actions[0].responseId)) {
            const rest = queued.slice(1)
            if (rest.length) {
                paymentQueue = rest
                queuedPaymentId = previousPayment
                queuedPromptId = session.promptId
            } else {
                clearPaymentQueue()
            }
            return
        }
        clearPaymentQueue()
        paymentQueueCleared()
    }

    function activateObject(kind, objectId, name) {
        if (!canRespond)
            return tryQueuePayment(kind, objectId)
        if (choosingTargets) {
            const ids = objectTargetIds(kind, objectId)
            if (ids.length !== 1)
                return false
            toggleTarget(ids[0])
            return true
        }
        const actions = kind === "card" ? actionsForCard(objectId) : []
        if (actions.length === 0)
            return false
        if (actions.length === 1)
            return submitCardAction(objectId, actions[0].responseId)
        SoundEffects.play("select")
        tableController.cardActionPicker.showFor(objectId, name, actions)
        return true
    }

    function activateSeat(seat) {
        if (!canRespond)
            return false
        const ids = seatTargetIds(seat)
        if (ids.length !== 1)
            return false
        toggleTarget(ids[0])
        return true
    }

    function toggleTarget(responseId) {
        if (!canRespond || !targetCandidates.some(target => target.responseId === responseId))
            return false
        const next = Object.assign({}, selectedTargetIds)
        if (next[responseId]) {
            delete next[responseId]
        } else {
            if (selectedCount >= session.promptMaxSelections)
                return false
            next[responseId] = true
        }
        selectedTargetIds = next
        if (next[responseId] && session.promptMaxSelections === 1)
            submitTargets("$submit")
        else
            SoundEffects.play(next[responseId] ? "select" : "cancel")
        return true
    }

    function submitTargets(responseId) {
        if (!canRespond || !choosingTargets)
            return false
        if (responseId === "$cancel") {
            if (!session.promptCancellable)
                return false
        } else if (responseId !== "$submit" || !validTargets) {
            return false
        }
        const selected = Object.keys(selectedTargetIds)
        if (selected.some(id => !targetCandidates.some(target => target.responseId === id)))
            return false
        tableController.wsModel.respondRulesPromptWithTargets(
            session.promptId, responseId, responseId === "$submit" ? selected : [])
        return true
    }

    function objectOnTable(kind, objectId) {
        void session.snapshotRevision
        if (!objectId || typeof session.cardPlacement !== "function")
            return false
        const card = session.cardPlacement(objectId)
        if (kind === "spell")
            return tableController.stackTargetsVisible === true && card.zone === "stack"
        if (kind !== "card")
            return false
        return card.zone === "battlefield" || (card.zone === "hand"
            && card.zoneOwnerSeat === tableController.handOwnerSeat && card.visibleIdentity === true)
    }

    function targetOnTable(candidate) {
        if (candidate.kind === "player")
            return candidate.seat >= 0 && seatTargetIds(candidate.seat).length === 1
        return objectOnTable(candidate.kind, candidate.objectId)
            && objectTargetIds(candidate.kind, candidate.objectId).length === 1
    }

    function actionOnTable(cardId, kind) {
        void promptRevision
        // Called only for a current promptOptions row. Avoid querying that model
        // recursively while its delegates are being inserted. Submission still
        // revalidates the exact response through actionsForCard().
        return contextActive && (session.promptKind === "chooseAction"
                || session.promptKind === "payManaCost"
                || (session.promptKind === "mulligan" && kind === "activateAbility"))
            && ["cast", "playLand", "activateAbility", "undoMana"].includes(kind)
            && objectOnTable("card", cardId)
    }
}
