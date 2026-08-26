// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick

QtObject {
    id: root

    readonly property var groups: [
        {
            "id": "application",
            "name": qsTr("Application"),
            "actions": [
                action("app.fullscreen", qsTr("Toggle full screen"))
            ]
        },
        {
            "id": "table-view",
            "name": qsTr("Table view and turn"),
            "actions": [
                action("table.help", qsTr("Show or hide shortcut help")),
                action("table.openSettings", qsTr("Open table settings")),
                action("table.toggleGameLog", qsTr("Show or hide game log")),
                action("table.toggleShared", qsTr("Show or hide stack / reveal tray")),
                action("table.advancePhase", qsTr("Advance phase")),
                action("table.advanceTurn", qsTr("Advance turn")),
                action("table.counter.rename", qsTr("Rename the selected player counter")),
                action("table.counter.set", qsTr("Set the selected player counter value")),
                action("table.counter.decrease", qsTr("Decrease the selected player counter")),
                action("table.counter.increase", qsTr("Increase the selected player counter"))
            ]
        },
        {
            "id": "library",
            "name": qsTr("Library and zones"),
            "actions": [
                action("table.library.drawX", qsTr("Draw X cards")),
                action("table.library.drawOne", qsTr("Draw one card")),
                action("table.library.search", qsTr("Search own library")),
                action("table.library.viewTopX", qsTr("View the top X library cards")),
                action("table.library.viewTop", qsTr("View the top library card")),
                action("table.sideboard.view", qsTr("View sideboard")),
                action("table.library.millX", qsTr("Put top X library cards into graveyard")),
                action("table.library.exileX", qsTr("Put top X library cards into exile")),
                action("table.library.shuffle", qsTr("Confirm shuffle of own library"))
            ]
        },
        {
            "id": "game",
            "name": qsTr("Game actions"),
            "actions": [
                action("table.untapAll", qsTr("Untap all own permanents")),
                action("table.arrangeBattlefield", qsTr("Arrange own battlefield")),
                action("table.createToken", qsTr("Create token")),
                action("table.mulligan", qsTr("Confirm mulligan")),
                action("table.toggleHandReveal", qsTr("Reveal or recall hand")),
                action("table.discardRandom", qsTr("Discard a random card")),
                action("table.discardAll", qsTr("Confirm discard entire hand")),
                action("table.rollDice", qsTr("Roll dice")),
                action("table.flipCoin", qsTr("Flip a coin")),
                action("table.randomPlayer", qsTr("Select a random player")),
                action("table.randomBattlefield", qsTr("Select a random battlefield card")),
                action("table.declareDraw", qsTr("Confirm declare draw")),
                action("table.restartGame", qsTr("Confirm restart game")),
                action("table.setLife", qsTr("Set life total")),
                action("table.life.decrease", qsTr("Decrease own life")),
                action("table.life.increase", qsTr("Increase own life")),
                action("table.commanderDamage", qsTr("Open commander damage")),
                action("table.concede", qsTr("Concede")),
                action("table.leave", qsTr("Leave room or end playtest")),
                action("table.returnToRoom", qsTr("Return to room after the match"))
            ]
        },
        {
            "id": "selection",
            "name": qsTr("Selected cards"),
            "actions": [
                action("table.selection.playLand", qsTr("Play selected hand card as land")),
                action("table.selection.battlefieldFaceUp", qsTr("Move selected hand card to battlefield face up")),
                action("table.selection.battlefieldFaceDown", qsTr("Move selected hand card to battlefield face down")),
                action("table.selection.moveHand", qsTr("Move selected card(s) to hand")),
                action("table.selection.moveGraveyard", qsTr("Move selected card(s) to graveyard")),
                action("table.selection.moveExile", qsTr("Move selected card(s) to exile")),
                action("table.selection.moveLibraryTop", qsTr("Move selected card(s) to library top")),
                action("table.selection.moveLibraryBottom", qsTr("Move selected card(s) to library bottom")),
                action("table.selection.randomLibraryTop", qsTr("Move selected battlefield cards to library top in random order")),
                action("table.selection.randomLibraryBottom", qsTr("Move selected battlefield cards to library bottom in random order")),
                action("table.selection.toggleTap", qsTr("Tap or untap selected permanents")),
                action("table.selection.toggleFaceDown", qsTr("Turn selected permanent face down or up")),
                action("table.selection.chooseFace", qsTr("Choose selected permanent face")),
                action("table.selection.attach", qsTr("Attach selected permanent")),
                action("table.selection.detach", qsTr("Detach selected permanent")),
                action("table.selection.target", qsTr("Choose target for selected cards")),
                action("table.selection.clearTarget", qsTr("Clear target for selected cards")),
                action("table.selection.attack", qsTr("Attack a player or permanent")),
                action("table.selection.block", qsTr("Block an attacker")),
                action("table.selection.clearCombat", qsTr("Clear selected combat declaration")),
                action("table.selection.addNumberCounter", qsTr("Add a number counter to selected permanent")),
                action("table.selection.numberCounterDecrease", qsTr("Decrease selected permanent's number counter")),
                action("table.selection.numberCounterIncrease", qsTr("Increase selected permanent's number counter")),
                action("table.selection.addAbilityCounter", qsTr("Add an ability counter to selected permanent")),
                action("table.selection.setNumberCounter", qsTr("Set selected permanent's number counter")),
                action("table.selection.createTokenCopy", qsTr("Create a token copy of selected permanent"))
            ]
        },
        {
            "id": "replay",
            "name": qsTr("Replay"),
            "actions": [
                action("replay.playPause", qsTr("Play or pause replay")),
                action("replay.previous", qsTr("Show previous replay event")),
                action("replay.next", qsTr("Show next replay event")),
                action("replay.reset", qsTr("Return to first replay event")),
                action("replay.speedHalf", qsTr("Set replay speed to 0.5×")),
                action("replay.speedNormal", qsTr("Set replay speed to 1×")),
                action("replay.speedDouble", qsTr("Set replay speed to 2×")),
                action("replay.speedQuadruple", qsTr("Set replay speed to 4×"))
            ]
        }
    ]

    readonly property var tableActions: flattenedActions(false)

    function action(actionId, label) {
        return {"id": actionId, "label": label}
    }

    function flattenedActions(includeReplay) {
        const result = []
        for (const group of root.groups) {
            if (!includeReplay && group.id === "replay")
                continue
            for (const item of group.actions)
                result.push(item)
        }
        return result
    }

    function labelFor(actionId) {
        for (const group of root.groups) {
            for (const item of group.actions) {
                if (item.id === actionId)
                    return item.label
            }
        }
        return actionId
    }
}
