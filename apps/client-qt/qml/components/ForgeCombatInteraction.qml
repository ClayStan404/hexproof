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
    property string hoveredCard: ""
    property int hoveredSeat: -1
    readonly property var chosenSource: sources.find(source => source.responseId === selectedSource) || null
    readonly property var hoveredTarget: {
        if (!canAct || !chosenSource) return null
        const target = hoveredSeat >= 0 ? seatTarget(hoveredSeat) : targetFor(hoveredCard)
        return target && canAssign(chosenSource, target) ? target : null
    }
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
    function resetAssignments() { assignments = ({}); selectedSource = ""; hoveredCard = ""; hoveredSeat = -1 }
    function hoverCard(id, inside) {
        if (inside) { hoveredCard = id; hoveredSeat = -1 }
        else if (hoveredCard === id) hoveredCard = ""
    }
    function hoverSeat(seat, inside) {
        if (inside) { hoveredSeat = seat; hoveredCard = "" }
        else if (hoveredSeat === seat) hoveredSeat = -1
    }
    function cancelSelection() {
        if (selectedSource) SoundEffects.play("cancel")
        selectedSource = ""
    }
    function clearSelectedAssignment() {
        if (!canAct || !chosenSource) return
        setAssignment(selectedSource, "")
        cancelSelection()
    }
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
    function isCombatant(id) {
        return !!id && sources.some(source => source.objectId === id
            || source.validTargets.some(target => target.objectId === id))
    }
    function canAssign(source, target) {
        const selected = selectedTargets(source.responseId)
        if (selected.includes(target.responseId)) return true
        if (source.maxAssignments <= 0
                || (source.maxAssignments > 1 && selected.length >= source.maxAssignments)) return false
        const count = sources.filter(value => selectedTargets(value.responseId).includes(target.responseId)).length
        return count < target.maxAssignments
    }
    function targetFor(id) {
        return chosenSource && id ? chosenSource.validTargets.find(target => target.objectId === id) : null
    }
    function targetActionable(id) {
        const target = targetFor(id)
        return canAct && !!target && canAssign(chosenSource, target)
    }
    function seatTarget(seat) {
        return chosenSource ? chosenSource.validTargets.find(target => target.kind === "player" && target.seat === seat) : null
    }
    function seatActionable(seat) {
        const target = seatTarget(seat)
        return canAct && !!target && canAssign(chosenSource, target)
    }
    function seatSelected(seat) {
        return links.some(link => link.player && link.seat === seat)
    }
    function activateSeat(seat) {
        const target = seatTarget(seat)
        return activateTarget(target)
    }
    function actionable(id) {
        if (!canAct) return false
        const source = sourceFor(id)
        if (source && source.maxAssignments > 0 && source.validTargets.length > 0) return true
        return targetActionable(id)
    }
    function selected(id) {
        const source = sourceFor(id)
        return !!source && (source.responseId === selectedSource || selectedTargets(source.responseId).length > 0)
    }
    function labelFor(id) {
        const source = sourceFor(id)
        if (source && source.responseId === selectedSource)
            return attacking ? qsTr("Choose attack target") : qsTr("Choose creature to block")
        if (source && selectedTargets(source.responseId).length) return attacking ? qsTr("Attacking") : qsTr("Blocking")
        if (targetActionable(id)) return attacking ? qsTr("Attack here") : qsTr("Block this creature")
        if (attacking && source && source.mustAssignIfAble) return qsTr("Must attack if able")
        if (!attacking && sources.some(value => value.validTargets.some(target => target.objectId === id && target.mustReceiveIfAble)))
            return qsTr("Must be blocked if able")
        return ""
    }
    function activateTarget(target) {
        if (!canAct || !chosenSource || !target || !canAssign(chosenSource, target)) return false
        const removing = selectedTargets(selectedSource).includes(target.responseId)
        if (chosenSource.maxAssignments > 1) toggleAssignment(selectedSource, target.responseId, chosenSource.maxAssignments)
        else setAssignment(selectedSource, selectedTargets(selectedSource).includes(target.responseId) ? "" : target.responseId)
        selectedSource = ""
        SoundEffects.play(removing ? "cancel" : attacking ? "attack" : "block")
        return true
    }
    function activate(id) {
        if (!canAct) return false
        const source = sourceFor(id)
        if (source && source.maxAssignments > 0 && source.validTargets.length > 0) {
            selectedSource = selectedSource === source.responseId ? "" : source.responseId
            SoundEffects.play(selectedSource ? "select" : "cancel")
            return true
        }
        return activateTarget(targetFor(id))
    }
}
