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
    readonly property var zoneActions: {
        void promptRevision
        void session.snapshotRevision
        if (!contextActive || session.promptKind !== "chooseAction"
                || typeof session.promptOptionItems !== "function") return []
        return session.promptOptionItems().filter(action => action.cardId
            && ["cast", "playLand", "activateAbility"].includes(action.kind)
            && !objectOnTable("card", action.cardId)).map(action => {
                const card = session.cardForInspection(action.cardId)
                return card.visibleIdentity === true
                    ? Object.assign({}, action, {zone: card.zone, zoneOwnerSeat: card.zoneOwnerSeat}) : null
            }).filter(action => action !== null)
    }

    visible: false
    Component.onCompleted: promptSeat = tableController.localSeat

    function resetSelection() {
        selectedTargetIds = ({})
    }

    onContextActiveChanged: {
        if (!contextActive)
            resetSelection()
    }
    onCurrentGameIdChanged: resetSelection()

    Connections {
        target: root.session
        function onPromptChanged() {
            root.promptSeat = root.tableController.localSeat
            root.promptRevision++
            root.resetSelection()
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

    function actionsForCard(cardId) {
        void promptRevision
        if (!canRespond || !cardId || typeof session.cardActionsForCard !== "function")
            return []
        return session.cardActionsForCard(cardId)
    }

    function submitCardAction(cardId, responseId) {
        const actions = actionsForCard(cardId)
        if (!actions.some(action => action.responseId === responseId))
            return false
        if (tableController.priority)
            tableController.priority.cancelYield(false)
        tableController.wsModel.respondRulesPrompt(session.promptId, responseId)
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

    function objectActionable(kind, objectId) {
        if (!canRespond)
            return false
        if (choosingTargets)
            return objectTargetIds(kind, objectId).length === 1
        return kind === "card" && actionsForCard(objectId).length > 0
    }

    function objectSelected(kind, objectId) {
        return objectTargetIds(kind, objectId).some(id => selectedTargetIds[id] === true)
    }

    function seatActionable(seat) {
        return canRespond && seatTargetIds(seat).length === 1
    }

    function seatSelected(seat) {
        return seatTargetIds(seat).some(id => selectedTargetIds[id] === true)
    }

    function activateObject(kind, objectId, name) {
        if (!canRespond)
            return false
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
        if (!objectId || typeof session.cardForInspection !== "function")
            return false
        const card = session.cardForInspection(objectId)
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
                || session.promptKind === "payManaCost")
            && ["cast", "playLand", "activateAbility"].includes(kind)
            && objectOnTable("card", cardId)
    }
}
