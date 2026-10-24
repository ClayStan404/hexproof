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
    property string pendingAttacker: ""
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
    readonly property var groupingKeys: {
        const states = new Map()
        function stateFor(id) {
            if (!states.has(id)) states.set(id, {outgoing: [], incoming: []})
            return states.get(id)
        }
        const kind = attacking ? "attack" : "block"
        for (const link of links) {
            stateFor(link.from).outgoing.push(JSON.stringify([
                kind, link.player ? "player" : "card", link.player ? link.seat : link.to]))
            if (link.to) stateFor(link.to).incoming.push(JSON.stringify([kind, link.from]))
        }
        const keys = {}
        for (const [id, state] of states)
            keys[id] = JSON.stringify([state.outgoing.sort(), state.incoming.sort()])
        return keys
    }
    visible: false
    function resetAssignments() {
        assignments = ({})
        selectedSource = ""
        pendingAttacker = ""
        hoveredCard = ""
        hoveredSeat = -1
    }
    function hoverCard(id, inside) {
        if (inside) { hoveredCard = id; hoveredSeat = -1 }
        else if (hoveredCard === id) hoveredCard = ""
    }
    function hoverSeat(seat, inside) {
        if (inside) { hoveredSeat = seat; hoveredCard = "" }
        else if (hoveredSeat === seat) hoveredSeat = -1
    }
    function cancelSelection() {
        if (selectedSource || pendingAttacker) SoundEffects.play("cancel")
        selectedSource = ""
        pendingAttacker = ""
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
    function canAssign(source, target) {
        const selected = selectedTargets(source.responseId)
        if (selected.includes(target.responseId)) return true
        if (source.maxAssignments <= 0
                || (source.maxAssignments > 1 && selected.length >= source.maxAssignments)) return false
        const count = sources.filter(value => selectedTargets(value.responseId).includes(target.responseId)).length
        return count < target.maxAssignments
    }
    function targetOnSource(source, id) {
        return source && id ? source.validTargets.find(target => target.objectId === id) : null
    }
    function targetFor(id) {
        return targetOnSource(chosenSource, id)
    }
    function anyBlockerCanTarget(id) {
        return sources.some(source => {
            const target = targetOnSource(source, id)
            return !!target && canAssign(source, target)
        })
    }
    function targetOffered(id) {
        if (!attacking && !chosenSource)
            return anyBlockerCanTarget(id)
        const target = targetFor(id)
        return !!target && canAssign(chosenSource, target)
    }
    function targetActionable(id) { return canAct && targetOffered(id) }
    function seatTarget(seat) {
        return chosenSource ? chosenSource.validTargets.find(target => target.kind === "player" && target.seat === seat) : null
    }
    function seatOffered(seat) {
        const target = seatTarget(seat)
        return !!target && canAssign(chosenSource, target)
    }
    function seatActionable(seat) { return canAct && seatOffered(seat) }
    function seatSelected(seat) {
        return links.some(link => link.player && link.seat === seat)
    }
    function activateSeat(seat) {
        const target = seatTarget(seat)
        return activateTarget(target)
    }
    function offered(id) {
        const source = sourceFor(id)
        if (source && source.maxAssignments > 0 && source.validTargets.length > 0) return true
        return targetOffered(id)
    }
    function actionable(id) { return canAct && offered(id) }
    function selected(id) {
        const source = sourceFor(id)
        return !!source && (source.responseId === selectedSource || selectedTargets(source.responseId).length > 0)
    }
    function labelFor(id) {
        const source = sourceFor(id)
        if (source && source.responseId === selectedSource)
            return attacking ? qsTr("Choose attack target") : qsTr("Choose creature to block")
        if (source && selectedTargets(source.responseId).length) return attacking ? qsTr("Attacking") : qsTr("Blocking")
        if (!attacking && pendingAttacker === id) return qsTr("Choose a creature to block this")
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
    property var attackAllPlayers: []
    function unassignedSources() {
        return sources.filter(source => source.maxAssignments > 0 && source.validTargets.length > 0
                && selectedTargets(source.responseId).length === 0)
    }
    // Planeswalkers and battles are never chosen implicitly.
    readonly property bool attackAllAvailable: canAct && attacking
        && unassignedSources().some(source => source.validTargets.some(target => target.kind === "player"))
    function soleBlockTarget(source) {
        if (!source || source.validTargets.length !== 1)
            return null
        const target = source.validTargets[0]
        return target.kind === "player" ? null : target
    }
    readonly property bool blockAllAvailable: canAct && !attacking
        && unassignedSources().some(source => {
            const target = soleBlockTarget(source)
            return !!target && canAssign(source, target)
        })
    function blockWithAll() {
        if (!blockAllAvailable)
            return false
        const eligible = unassignedSources()
        for (let i = 0; i < eligible.length; ++i) {
            const source = eligible[i]
            const target = soleBlockTarget(source)
            if (target && canAssign(source, target))
                setAssignment(source.responseId, target.responseId)
        }
        return true
    }
    function attackWithAll(playerResponseId) {
        if (!attackAllAvailable)
            return false
        const eligible = unassignedSources()
        const players = []
        const seen = ({})
        for (let i = 0; i < eligible.length; ++i) {
            const targets = eligible[i].validTargets
            for (let t = 0; t < targets.length; ++t) {
                if (targets[t].kind !== "player" || seen[targets[t].responseId])
                    continue
                seen[targets[t].responseId] = true
                players.push(targets[t])
            }
        }
        let chosen = playerResponseId || ""
        if (!chosen) {
            if (players.length !== 1) {
                attackAllPlayers = players
                return false
            }
            chosen = players[0].responseId
        }
        for (let i = 0; i < eligible.length; ++i) {
            const source = eligible[i]
            const target = source.validTargets.find(value => value.kind === "player" && value.responseId === chosen)
            if (target && canAssign(source, target))
                setAssignment(source.responseId, chosen)
        }
        attackAllPlayers = []
        return true
    }
    function activate(id) {
        if (!canAct) return false
        const source = sourceFor(id)
        if (source && source.maxAssignments > 0 && source.validTargets.length > 0) {
            if (!attacking && pendingAttacker) {
                const armed = targetOnSource(source, pendingAttacker)
                if (armed && canAssign(source, armed)) {
                    const removing = selectedTargets(source.responseId).includes(armed.responseId)
                    if (source.maxAssignments > 1)
                        toggleAssignment(source.responseId, armed.responseId, source.maxAssignments)
                    else
                        setAssignment(source.responseId, removing ? "" : armed.responseId)
                    pendingAttacker = ""
                    selectedSource = ""
                    SoundEffects.play(removing ? "cancel" : "block")
                    return true
                }
                // This click belongs to the armed attacker. Preserve its
                // selection and the draft when this blocker cannot join it.
                return true
            }
            if (source.validTargets.length === 1) {
                const only = source.validTargets[0]
                const assigned = selectedTargets(source.responseId).includes(only.responseId)
                if (!assigned && !canAssign(source, only)) {
                    selectedSource = source.responseId
                    pendingAttacker = ""
                    SoundEffects.play("select")
                    return true
                }
                setAssignment(source.responseId, assigned ? "" : only.responseId)
                selectedSource = ""
                pendingAttacker = ""
                SoundEffects.play(assigned ? "cancel" : attacking ? "attack" : "block")
                return true
            }
            selectedSource = selectedSource === source.responseId ? "" : source.responseId
            pendingAttacker = ""
            SoundEffects.play(selectedSource ? "select" : "cancel")
            return true
        }
        if (!attacking && !chosenSource && anyBlockerCanTarget(id)) {
            pendingAttacker = pendingAttacker === id ? "" : id
            SoundEffects.play(pendingAttacker ? "select" : "cancel")
            return true
        }
        return activateTarget(targetFor(id))
    }
}
