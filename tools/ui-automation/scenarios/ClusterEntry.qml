// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick

// Three isolated guest profiles, two loopback cluster nodes N1/N2. Give N2
// higher placement weight and delay its handshake to inspect the transition.
Item {
    id: driver
    property var steps: []
    property var assertions: []
    property var screenshots: []
    property int index: 0
    property bool acted: false
    property bool dispatching: false
    property bool finished: false
    property double entered: 0
    property string roomCode: ""
    property var entryPage: null
    property bool observedProgress: false
    property int transferFrames: 0
    readonly property int seat: Number(auditProbe.environment("HEXPROOF_AUDIT_SEAT"))

    function require(value, message) { if (!value) throw new Error(message) }
    function find(name) { return auditProbe.find(auditWindow, name, ({})) }
    function descendant(item, name) {
        if (!item) return null
        if (item.objectName === name) return item
        for (const child of item.children || []) {
            const result = descendant(child, name)
            if (result) return result
        }
        return null
    }
    function click(name, scrollName) {
        const scroll = scrollName ? find(scrollName) : null
        const body = scroll && scroll.contentItem ? scroll.contentItem : scroll
        if (body && body.moving) return false
        const item = find(name)
        if (item) { require(auditProbe.click(item), "Cannot click " + name); return true }
        if (scroll) require(auditProbe.wheel(scroll, -300), "Cannot scroll")
        return false
    }
    function choose(name, selected) {
        if (!click(name)) return false
        require(auditProbe.key(Qt.Key_Home), "Cannot select first option")
        for (let i = 0; i < selected; ++i) require(auditProbe.key(Qt.Key_Down), "Cannot select option")
        require(auditProbe.key(Qt.Key_Return), "Cannot accept option")
        return true
    }
    function type(name, value) {
        if (!click(name)) return false
        require(auditProbe.key(Qt.Key_A, Qt.ControlModifier), "Cannot select text")
        require(auditProbe.type(value), "Cannot type text")
        return true
    }
    function add(name, action, check) { steps.push({name: name, action: action, check: check || (() => true)}) }
    function capture(name) {
        require(auditProbe.capture(auditWindow, name), "Cannot capture test window")
        screenshots.push(name + ".png")
    }
    function observeTransfer() {
        if (!ws.transferring) return
        ++transferFrames
        require(!ws.reconnecting, "A deliberate transfer became seat recovery")
        require(!ws.lastError, "A deliberate transfer displayed an error")
        require(auditWindow.stack.currentItem === entryPage, "Transfer replaced the entry screen")
        if (seat > 1) {
            require(!descendant(entryPage, "roomBrowserConnectButton").visible, "Transfer offered an unnecessary reconnect")
            require(!descendant(entryPage, "emptyHubRoomState").visible, "Transfer displayed the disconnected empty state")
            require(descendant(entryPage, "hubRoomList").visible, "Transfer removed the room list")
            require(descendant(entryPage, "roomSearchField").text === "Transfer", "Transfer lost the search filter")
        }
        if (!observedProgress) {
            // This status is intentionally noninteractive. Inspect its rendered
            // geometry rather than using the pointer-target selector.
            const observation = auditProbe.observe(auditWindow)
            const progress = observation.items.find(item => item.objectName === "serverTransferProgress")
            if (progress && progress.visible && progress.inViewport && progress.rect.height > 0) {
                observedProgress = true
                auditProbe.record("during-transfer", observation)
                capture("entry-progress")
            }
        }
    }
    function plan() {
        add("Dismiss startup notices", () => {
            require(auditProbe.activate(), "Cannot activate test window")
            for (const name of ["dismissSponsorsButton", "laterCardArtRepairButton"])
                if (find(name)) { click(name); return false }
            return !!find("mainMenuConnectButton") && !auditWindow.stack.busy
        })
        add("Open connection screen", () => click("mainMenuConnectButton"),
            () => !!find("serverSelector") && !auditWindow.stack.busy)
        add("Choose N1", () => choose("serverSelector", 0), () => !!find("accountConnectionMode"))
        add("Choose guest", () => choose("accountConnectionMode", 4))
        add("Name isolated guest", () => type("displayNameField", "Entry guest " + seat))
        add("Connect guest", () => click("connectSubmitButton", "connectBody"),
            () => ws.connected && !auditWindow.stack.busy)
        add("Verify entry node", () => require(ws.globalCode("TEST") === "N1:TEST", "Entry was not N1"))
        if (seat === 1) {
            add("Open room creation", () => click("mainMenuCreateRoomButton"),
                () => !!find("roomNameField") && !auditWindow.stack.busy)
            add("Name room", () => type("roomNameField", "Transfer regression room"))
            add("Submit room", () => {
                entryPage = auditWindow.stack.currentItem
                return click("createRoomSubmitButton", "createRoomBody")
            }, () => ws.inRoom && !auditWindow.stack.busy)
            add("Publish local room", () => {
                roomCode = ws.globalCode(ws.roomSession.roomId)
                require(roomCode.indexOf("N2:") === 0, "Room was not placed on N2")
                require(observedProgress, "Creation progress was not inspected")
                require(auditProbe.share("entry-room", {code: roomCode}), "Cannot publish fixture")
                capture("created-room")
            })
        } else {
            add("Wait for room", () => {
                const fixture = auditProbe.readShared("entry-room")
                if (!fixture || !fixture.code) return false
                roomCode = fixture.code
            })
            add("Browse lobby", () => click("mainMenuBrowseHubButton"),
                () => !!find("watchListedRoomButton") && !auditWindow.stack.busy)
            add("Filter lobby", () => type("roomSearchField", "Transfer"))
            add("Inspect entry list", () => {
                require(ws.roomList.some(room => room.roomId === roomCode), "Room is absent")
                capture("entry-list")
            })
            add(seat === 2 ? "Join listed room" : "Watch listed room", () => {
                entryPage = auditWindow.stack.currentItem
                return click(seat === 2 ? "joinListedRoomButton" : "watchListedRoomButton", "roomBrowserBody")
            }, () => ws.inRoom && !auditWindow.stack.busy)
            add("Verify entry", () => {
                require(observedProgress, "Entry progress was not inspected")
                require(ws.roomSession.role === (seat === 2 ? "player" : "spectator"), "Incorrect role")
                require(ws.globalCode(ws.roomSession.roomId) === roomCode, "Incorrect destination")
                require(!ws.transferring && !ws.lastError, "Entry did not finish cleanly")
                require(auditProbe.share("entry-seat-" + seat, {ready: true}), "Cannot publish result")
                capture(seat === 2 ? "joined-room" : "spectated-room")
            })
        }
        add("Wait for both arrivals", () => true,
            () => !!auditProbe.readShared("entry-seat-2") && !!auditProbe.readShared("entry-seat-3"))
    }
    function finish(error) {
        finished = true
        if (error) capture("failure")
        const geometry = auditProbe.observe(auditWindow)
        auditProbe.record("result", {status: error ? "failed" : "passed", message: error || "",
            assertions: assertions, pendingStep: index < steps.length ? steps[index].name : "",
            observedProgress: observedProgress, transferFrames: transferFrames, requiredScreenshots: screenshots,
            requestedWindowMode: geometry.requestedWindowMode, windowMode: geometry.windowMode,
            width: geometry.width, height: geometry.height, dpr: geometry.dpr, screenGeometry: geometry.screenGeometry})
        auditProbe.finish(error ? 1 : 0)
    }
    Component.onCompleted: { try { plan() } catch (error) { finish(String(error)) } }
    Connections {
        target: ws
        function onTransferringChanged() {
            auditProbe.record(ws.transferring ? "transfer-started" : "transfer-finished",
                              {transferring: ws.transferring, connected: ws.connected,
                               connecting: ws.connecting, error: ws.lastError, time: Date.now()})
        }
    }
    Timer {
        interval: 50
        repeat: true
        running: !driver.finished && ws.transferring
        onTriggered: {
            try { driver.observeTransfer() } catch (error) { driver.finish(String(error)) }
        }
    }
    Timer {
        interval: 50
        repeat: true
        running: !driver.finished
        onTriggered: {
            if (driver.dispatching) return
            driver.dispatching = true
            try {
                driver.observeTransfer()
                if (driver.index >= driver.steps.length) { driver.finish(""); return }
                const step = driver.steps[driver.index]
                if (driver.entered === 0) driver.entered = Date.now()
                driver.require(Date.now() - driver.entered < 90000, "Timeout: " + step.name)
                if (!driver.acted) driver.acted = step.action() !== false
                if (driver.acted && step.check()) {
                    driver.assertions.push({name: step.name, passed: true})
                    ++driver.index; driver.entered = 0; driver.acted = false
                }
            } catch (error) { driver.finish(String(error)) }
            driver.dispatching = false
        }
    }
}
