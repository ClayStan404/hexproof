// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors
pragma ComponentBehavior: Bound
import QtQuick

Item {
    id: root
    required property var tableController
    readonly property var session: tableController.rulesSession
    readonly property bool active: tableController.interaction.contextActive
        && ["chooseAttackers", "chooseBlockers"].includes(session.promptKind)
    readonly property bool canAct: active && tableController.interaction.canRespond
    readonly property bool attacking: session.promptKind === "chooseAttackers"
    readonly property var sources: {
        void tableController.interaction.promptRevision
        return active && typeof session.promptCombat.sourceItems === "function" ? session.promptCombat.sourceItems() : []
    }
    property var assignments: ({})
    property string selectedSource: ""
    readonly property var links: {
        const result = []
        for (const source of sources) {
            for (const targetId of selectedTargets(source.responseId)) {
                const target = source.validTargets.find(value => value.responseId === targetId)
                if (target) result.push({from:source.objectId, to:target.objectId || "", player:target.kind === "player", seat:target.seat})
            }
        }
        return result
    }
    visible: false
    function resetAssignments() { assignments = ({}); selectedSource = "" }
    onActiveChanged: if (!active) resetAssignments()
    Connections {
        target: root.session
        function onPromptChanged() { root.resetAssignments() }
        function onSnapshotChanged() { if (!root.active) root.resetAssignments() }
    }
    Connections {
        target: root.tableController
        function onLocalSeatChanged() { root.resetAssignments() }
    }
    function selectedTargets(sourceId) {
        const value = assignments[sourceId]
        return Array.isArray(value) ? value : value ? [value] : []
    }
    function setAssignment(sourceId, targetId) {
        if (!canAct) return
        const source = sources.find(value => value.responseId === sourceId)
        if (!source || (targetId && !source.validTargets.some(value => value.responseId === targetId))) return
        const next = Object.assign({}, assignments)
        if (targetId) next[sourceId] = targetId
        else delete next[sourceId]
        assignments = next
    }
    function toggleAssignment(sourceId, targetId, maximum) {
        if (!canAct) return
        const source = sources.find(value => value.responseId === sourceId)
        if (!source || !source.validTargets.some(value => value.responseId === targetId)) return
        const next = selectedTargets(sourceId).slice()
        const index = next.indexOf(targetId)
        if (index >= 0) next.splice(index, 1)
        else if (next.length < source.maxAssignments) next.push(targetId)
        else return
        const result = Object.assign({}, assignments)
        if (next.length) result[sourceId] = next
        else delete result[sourceId]
        assignments = result
    }
    function sourceFor(id) { return sources.find(value => value.objectId === id) || null }
    function seatTarget(seat) {
        const chosen = sources.find(value => value.responseId === selectedSource)
        return chosen ? chosen.validTargets.find(target => target.kind === "player" && target.seat === seat) : null
    }
    function seatActionable(seat) { return canAct && !!seatTarget(seat) }
    function seatSelected(seat) {
        return links.some(link => link.player && link.seat === seat)
    }
    function activateSeat(seat) {
        const target = seatTarget(seat)
        if (!canAct || !target) return false
        setAssignment(selectedSource, target.responseId)
        selectedSource = ""
        return true
    }
    function actionable(id) {
        if (!canAct) return false
        const source = sourceFor(id)
        if (source && source.maxAssignments > 0) return true
        const chosen = sources.find(value => value.responseId === selectedSource)
        return !!chosen && chosen.validTargets.some(target => target.objectId === id)
    }
    function selected(id) {
        const source = sourceFor(id)
        return !!source && (source.responseId === selectedSource || selectedTargets(source.responseId).length > 0)
    }
    function labelFor(id) {
        const source = sourceFor(id)
        if (source && selectedTargets(source.responseId).length) return attacking ? qsTr("Attacking") : qsTr("Blocking")
        return source && source.responseId === selectedSource
            ? attacking ? qsTr("Choose a defender") : qsTr("Choose an attacker") : ""
    }
    function activate(id) {
        if (!canAct) return false
        const source = sourceFor(id)
        if (source && source.maxAssignments > 0) {
            if (attacking && source.validTargets.length === 1)
                setAssignment(source.responseId, selectedTargets(source.responseId).length ? "" : source.validTargets[0].responseId)
            else selectedSource = selectedSource === source.responseId ? "" : source.responseId
            return true
        }
        const chosen = sources.find(value => value.responseId === selectedSource)
        const target = chosen ? chosen.validTargets.find(value => value.objectId === id) : null
        if (!target) return false
        if (chosen.maxAssignments > 1) toggleAssignment(chosen.responseId, target.responseId, chosen.maxAssignments)
        else setAssignment(chosen.responseId, selectedTargets(chosen.responseId).includes(target.responseId) ? "" : target.responseId)
        selectedSource = ""
        return true
    }
}
