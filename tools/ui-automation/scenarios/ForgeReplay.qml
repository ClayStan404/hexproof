// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick

// --variant is an exported .hpr from the synthetic real-engine match test.
// Import/initial positioning are explicit fixtures; all player interactions
// below use native pointer input on the production UI in a maximized window.
Item {
    id: driver
    property var steps: []
    property var assertions: []
    property var screenshots: []
    property int index: 0
    property int positionBefore: 0
    property int bottomSeat: 0
    property bool acted: false
    property bool dispatching: false
    property bool finished: false
    property double stepStarted: 0
    function require(value, message) {
        if (!value) throw new Error(message + "; " + auditProbe.lastError)
    }
    function find(name) { return auditProbe.find(auditWindow, name) }
    function observed(name, parent) {
        const item = parent || auditWindow.contentItem
        if (item.objectName === name) return item
        for (const child of item.children || []) {
            const found = observed(name, child)
            if (found) return found
        }
        return null
    }
    function click(name) {
        const item = find(name)
        if (!item) return false
        require(auditProbe.click(item), "Cannot click " + name)
        return true
    }
    function add(name, action, check) {
        steps.push({name:name, action:action, check:check || (() => true)})
    }
    function capture(name) {
        require(auditProbe.capture(auditWindow,name), "Cannot capture replay")
        screenshots.push(name + ".png")
    }
    function finish(error) {
        if (finished) return
        finished = true
        const geometry = auditProbe.observe(auditWindow)
        if (error) auditProbe.capture(auditWindow,"failure")
        auditProbe.record("window-geometry",geometry)
        auditProbe.record("result", {status:error ? "failed" : "passed", scenario:"forge-replay",
            error:error || "", pendingStep:index < steps.length ? steps[index].name : "",
            assertions:assertions, requiredScreenshots:screenshots, frameCount:ws.replays.count,
            requestedWindowMode:geometry.requestedWindowMode, windowMode:geometry.windowMode,
            width:geometry.width, height:geometry.height, dpr:geometry.dpr, screenGeometry:geometry.screenGeometry,
            evidence:"Real-engine exported replay fixture; native pointer input and captures; offline viewer"})
        auditProbe.finish(error ? 1 : 0)
    }
    Component.onCompleted: {
        add("Import the real-engine replay as an explicit offline fixture", () => {
            const path = auditProbe.environment("HEXPROOF_AUDIT_VARIANT")
            auditProbe.fixture("private-forge-replay",{path:path, source:"synthetic real-engine BO3 test"})
            require(ws.replays.importFile("file://" + path),ws.replays.error)
            require(ws.replays.count > 100,"Missing engine observations")
            require(!ws.connected,"Replay should work offline")
            return true
        })
        add("Open the replay library through the main menu", () => click("mainMenuForgeReplaysButton"),
            () => auditWindow.stack.currentItem.service === ws.replays)
        add("Open the loaded replay and position it at a recorded spell", () => {
            auditProbe.fixture("replay-initial-position",{reason:"inspect both hands and a meaningful board"})
            auditWindow.stack.currentItem.showReplay()
            const events = ws.replays.events
            const at = events.findIndex(e => e.kind === "SpellAbilityCast" && e.turn >= 3)
            require(at >= 0,"Missing recorded cast")
            ws.replays.seek(at)
            positionBefore = ws.replays.position
        }, () => !!observed("forgeReplayBoard") && !!observed("forgeReplayOpponentHand"))
        add("Inspect both hands and the native maximized layout", () => {
            const own = observed("forgeHand")
            const other = observed("forgeReplayOpponentHand")
            require(own.visibleCards.length > 0 && other.visibleCards.length > 0,"Both hands must show cards")
            require(own.ownerSeat !== other.ownerSeat,"Hands show the same player")
            bottomSeat = own.ownerSeat
            capture("replay-both-hands")
        })
        add("Step to the next event", () => click("forgeReplayNext"), () => ws.replays.position === positionBefore + 1)
        add("Step backwards to exactly the previous board", () => click("forgeReplayPrevious"), () => ws.replays.position === positionBefore)
        add("Jump to the next turn", () => click("forgeReplayNextTurn"), () => ws.replays.position > positionBefore + 1)
        add("Flip both player perspectives", () => click("forgeReplayFlip"), () => observed("forgeHand").ownerSeat !== bottomSeat)
        add("Capture the flipped replay", () => capture("replay-flipped"))
        add("Seek with the native timeline", () => {
            const slider = find("forgeReplayTimeline")
            require(auditProbe.click(slider,slider.width * 0.7,slider.height / 2),"Cannot seek timeline")
        }, () => ws.replays.position > ws.replays.count * 0.6
            && observed("forgeHand").ownerSeat !== bottomSeat)
        add("Start playback", () => { positionBefore = ws.replays.position; return click("forgeReplayPlay") },
            () => ws.replays.playing && ws.replays.position > positionBefore)
        add("Pause playback", () => click("forgeReplayPlay"), () => !ws.replays.playing)
        add("Hide the timeline for a wider board", () => click("forgeReplayToggleTimeline"),
            () => !auditWindow.stack.currentItem.timelineOpen)
        add("Capture the expanded replay", () => capture("replay-expanded"))
    }
    Timer {
        interval:200; repeat:true; running:!driver.finished
        onTriggered: {
            if (driver.dispatching || auditWindow.stack.busy) return
            driver.dispatching = true
            try {
                if (driver.index === driver.steps.length) { driver.finish(""); return }
                const step = driver.steps[driver.index]
                if (!driver.stepStarted) driver.stepStarted = Date.now()
                driver.require(Date.now()-driver.stepStarted < 20000,"Timed out " + step.name)
                if (!driver.acted) driver.acted = step.action() !== false
                if (driver.acted && step.check()) {
                    driver.assertions.push({name:step.name,status:"passed"})
                    driver.index++; driver.acted = false; driver.stepStarted = 0
                }
            } catch(error) { driver.finish(String(error)) }
            finally { driver.dispatching = false }
        }
    }
}
