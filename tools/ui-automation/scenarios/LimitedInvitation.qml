// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick

Item {
    id: driver

    readonly property int seat: Number(auditProbe.environment("AUDIT_SEAT"))
    property var steps: []
    property var assertions: []
    property var screenshots: []
    property int index: 0
    property bool acted: false
    property bool acknowledged: false
    property bool dispatching: false
    property bool finished: false
    property bool formatOpened: false
    property double started: Date.now()
    property var workspace: null
    property string editedSelection: ""

    function require(value, message) {
        if (!value) throw new Error(message)
    }
    function find(name) { return auditProbe.find(auditWindow, name) }
    function click(name, scrollName) {
        const scroll = scrollName ? find(scrollName) : null
        const body = scroll && scroll.contentItem ? scroll.contentItem : scroll
        if (body && body.moving) return false
        const target = find(name)
        if (target) {
            require(auditProbe.click(target), "Cannot click " + name)
            return true
        }
        if (scroll) require(auditProbe.wheel(scroll, -300), "Cannot scroll " + scrollName)
        return false
    }
    function typeField(name, value, scrollName) {
        if (!click(name, scrollName)) return false
        require(auditProbe.key(Qt.Key_A, Qt.ControlModifier), "Cannot select " + name)
        require(auditProbe.type(value), "Cannot enter " + name)
        return true
    }
    function add(name, actor, action, check, timeout) {
        steps.push({name: name, actor: actor, action: action,
                       check: check || (() => true), timeout: timeout || 25000})
    }
    function capture(name) {
        require(auditProbe.capture(auditWindow, name), "Cannot capture " + name)
        screenshots.push(name + ".png")
    }
    function shared(name, value) {
        require(auditProbe.share(name, value), "Cannot share " + name)
    }
    function screen() { return auditWindow.stack.currentItem }
    function ownProgress() {
        return Array.from(limited.participants).find(player => player.participantId === tournament.participantId) || ({})
    }
    function chooseCube() {
        if (!formatOpened) {
            if (!click("roomFormatSelector")) return false
            formatOpened = true
            return false
        }
        const options = screen().selectableFormatOptions
        const cubeIndex = options.findIndex(option => option.value === "cube")
        require(cubeIndex >= 0, "Missing Cube format")
        require(auditProbe.key(Qt.Key_Home), "Cannot select first format")
        for (let i = 0; i < cubeIndex; ++i)
            require(auditProbe.key(Qt.Key_Down), "Cannot select Cube format")
        require(auditProbe.key(Qt.Key_Return), "Cannot confirm Cube format")
    }
    function plan() {
        require(Number(auditProbe.environment("AUDIT_PLAYERS")) === 3, "This scenario requires three clients")
        auditProbe.fixture("ordinary-cube", {
            description: "An isolated saved Cube contains 135 copies of one exact basic-land printing with cached art. Each player enables server auto-draft using native controls. No event, pool, deck submission, or invitation is injected.",
            expectedPlayers: 3, expectedPoolCards: 45, format: "cube"
        })
        for (let actor = 1; actor <= 3; ++actor) {
            add("Dismiss first-launch notices for seat " + actor, actor, () => {
                for (const name of ["dismissSponsorsButton", "laterCardArtRepairButton"]) {
                    if (find(name)) { click(name); return false }
                }
                return !!find("mainMenuConnectButton")
            })
            add("Open connection form for seat " + actor, actor,
                () => click("mainMenuConnectButton"), () => !!find("connectSubmitButton"))
            add("Connect seat " + actor, actor, () => click("connectSubmitButton"), () => ws.connected)
        }
        add("Open Cube creation", 1, () => click("mainMenuCreateRoomButton"), () => !!find("createRoomPage"))
        add("Name the Cube room", 1, () => typeField("roomNameField", "Native Limited invitation"),
            () => screen().roomName === "Native Limited invitation")
        add("Select regular Cube", 1, chooseCube, () => screen().isCubeFormat && !screen().commanderCube)
        add("Choose three draft seats", 1, () => typeField("cubePlayerCapField", "3", "createRoomBody"),
            () => screen().cubePlayerCap() === 3)
        add("Create the Cube room", 1, () => click("createRoomSubmitButton", "createRoomBody"),
            () => tournament.inTournament && tournament.cubeRoom && tournament.maxPlayers === 3 && !!find("cubeRoomScreen"))
        add("Share the public room code", 1, () => shared("limited-room", {code: tournament.tournamentId}))
        for (let actor = 2; actor <= 3; ++actor) {
            add("Open room join for seat " + actor, actor, () => click("mainMenuJoinRoomButton"),
                () => !!find("joinRoomCodeField"))
            add("Enter room code for seat " + actor, actor,
                () => typeField("joinRoomCodeField", auditProbe.readShared("limited-room").code),
                () => find("joinRoomCodeField").text === auditProbe.readShared("limited-room").code)
            add("Join Cube seat " + actor, actor, () => click("joinRoomSubmitButton"),
                () => tournament.inTournament && tournament.tournamentId === auditProbe.readShared("limited-room").code
                    && !!find("cubeRoomScreen"))
        }
        add("Observe all three public seats", 0, () => {}, () => tournament.participants.length === 3)
        for (let actor = 1; actor <= 3; ++actor) {
            add("Publish own public participant identity " + actor, actor,
                () => shared("limited-seat-" + seat, {participantId: tournament.participantId}))
            add("Ready Cube seat " + actor, actor, () => click("cubeReadyButton"), () => screen().selfReady)
        }
        add("Host starts the draft", 1, () => click("cubeStartDraftButton"), () => tournament.stage === "draft")
        add("Observe draft stage on every client", 0, () => {}, () => limited.stage === "draft")
        for (let actor = 1; actor <= 3; ++actor) {
            add("Open seat controls " + actor, actor, () => click("cubeRoomInfoButton"),
                () => !!find("cubeSelfDraftControlButton"))
            add("Request own automatic drafting " + actor, actor, () => click("cubeSelfDraftControlButton"),
                () => !!find("confirmButton"))
            add("Confirm own automatic drafting " + actor, actor, () => click("confirmButton"),
                () => ownProgress().autoDraft === true)
        }
        add("Observe complete 45-card local pools", 0, () => {}, () => {
            if (limited.stage !== "deck_building" || limited.pool.length !== 45) return false
            const identities = Array.from(limited.pool).map(card => card.instanceId)
            require(new Set(identities).size === 45, "Duplicate physical identity in own pool")
            require(limited.pool[0].setCode && limited.pool[0].collectorNumber
                && ["Plains", "Island", "Swamp", "Mountain", "Forest"].includes(limited.pool[0].name),
                "Expected an exact ordinary basic-land printing")
            require(Array.from(limited.pool).every(card => card.name === limited.pool[0].name
                && card.setCode === limited.pool[0].setCode && card.collectorNumber === limited.pool[0].collectorNumber),
                "Unexpected Cube fixture printing")
            return true
        }, 60000)
        for (let actor = 1; actor <= 3; ++actor) {
            add("Keep all drafted cards for seat " + actor, actor, () => click("keepDraftedCardsButton"),
                () => !find("keepDraftedCardsButton"))
            add("Close room information for seat " + actor, actor, () => {
                if (find("cubeRoomInfoTabs")) return click("cubeRoomInfoCloseButton")
                else if (!find("limitedSubmitDeckButton")) return false
            }, () => !!find("limitedSubmitDeckButton"))
            add("Submit the 45-card deck for seat " + actor, actor, () => click("limitedSubmitDeckButton"),
                () => limited.deckSubmitted && limited.mainboardInstanceIds.length === 45
                    && JSON.stringify(Array.from(limited.mainboardInstanceIds).sort())
                        === JSON.stringify(Array.from(limited.pool).map(card => card.instanceId).sort()))
        }
        add("Observe free play without automatic pairing", 0, () => {},
            () => tournament.stage === "competition" && limited.stage === "competition"
                && limited.allDecksSubmitted && tournament.pairings.length === 0 && !ws.inRoom)
        add("Keep target's deck editor open", 2, () => screen().editingDeck || click("cubeDeckModeButton"),
            () => !!find("cubeDeckWorkspace") && screen().editingDeck)
        add("Open target's basic-land editor", 2, () => {
            workspace = find("cubeDeckWorkspace")
            if (!workspace) return false
            return click("limitedBasicLandsButton")
        }, () => workspace.basicLandsExpanded && !!find("limitedBasicLandsDone"))
        add("Make a local basic-land edit", 2, () => click("limitedBasicLandAdd-Plains", "limitedBasicLandScroll"),
            () => workspace.basicValue("Plains") === 1 && workspace.selectedCount === 46)
        add("Record the pending edit", 2, () => {
            editedSelection = workspace.selectionFingerprint()
            require(workspace.hasUnsubmittedChanges, "Expected an unsubmitted local edit")
            capture("basic-lands-before-invitation")
        })
        add("Open the inviting player's opponent list", 1, () => !screen().editingDeck || click("cubeDeckModeButton"),
            () => !screen().editingDeck && !!find("cubeOpponentList"))
        add("Send an invitation from another client", 1,
            () => click("cubeInvite-" + auditProbe.readShared("limited-seat-2").participantId, "cubeOpponentList"),
            () => !!screen().ownPairing && screen().ownPairing.status === "invited"
                && screen().ownPairing.playerAId === tournament.participantId
                && screen().ownPairing.playerBId === auditProbe.readShared("limited-seat-2").participantId)
        add("Observe the invitation and closed editor", 2, () => {}, () => {
            const pairing = screen().ownPairing
            if (!pairing || pairing.status !== "invited" || pairing.playerBId !== tournament.participantId
                    || pairing.playerAId !== auditProbe.readShared("limited-seat-1").participantId) return false
            if (workspace.visible || workspace.basicLandsExpanded || find("limitedBasicLandsDone")) return false
            require(workspace.selectionFingerprint() === editedSelection, "Invitation discarded the pending edit")
            return !!find("cubeCancelInviteButton") && !!find("cubeAcceptInviteButton")
        })
        add("Capture the usable invitation controls", 2, () => capture("invitation-closes-basic-lands"))
        add("Decline the invitation through its visible button", 2, () => click("cubeCancelInviteButton"),
            () => !screen().ownPairing)
        add("Observe cancellation on every client", 0, () => {}, () => tournament.pairings.length === 0)
        add("Reopen target's deck editor", 2, () => click("cubeDeckModeButton"),
            () => !!find("cubeDeckWorkspace") && screen().editingDeck)
        add("Reopen basic lands with the preserved edit", 2, () => click("limitedBasicLandsButton"), () => {
            if (!find("limitedBasicLandsDone")) return false
            require(workspace.selectionFingerprint() === editedSelection && workspace.basicValue("Plains") === 1
                && workspace.selectedCount === 46, "Reopening changed the pending edit")
            return true
        })
        add("Capture preserved local editing state", 2, () => capture("basic-lands-after-decline"))
        add("Close the basic-land editor", 2, () => click("limitedBasicLandsDone"),
            () => !workspace.basicLandsExpanded && !find("limitedBasicLandsDone"))
        add("Record final Cube state", 0, () => {
            require(tournament.eventType === "cube_draft" && tournament.participants.length === 3, "Wrong final Cube state")
            capture("limited-invitation-final")
        })
    }
    function finish(error) {
        if (finished) return
        finished = true
        if (error) {
            if (auditProbe.capture(auditWindow, "failure")) screenshots.push("failure.png")
            auditProbe.record("failure-state", auditProbe.observe(auditWindow))
        }
        auditProbe.record("result", {status: error ? "failed" : "passed", scenario: "limited-invitation",
            seat: seat, error: error || "", pendingStep: index < steps.length ? steps[index].name : "",
            assertions: assertions, requiredScreenshots: screenshots,
            coverage: "Three-client regular Cube creation, join, readiness, explicit automatic drafting, initial deck submission and invitation interruption of local basic-land editing; no table-entry or manual-pick coverage."})
        auditProbe.finish(error ? 1 : 0)
    }
    Component.onCompleted: {
        try { plan() } catch (error) { finish(String(error)) }
    }
    Timer {
        interval: 100
        repeat: true
        running: !driver.finished
        onTriggered: {
            if (driver.dispatching) return
            driver.dispatching = true
            try {
                if (driver.index >= driver.steps.length) { driver.finish(""); return }
                const step = driver.steps[driver.index]
                driver.require(Date.now() - driver.started < step.timeout, "Timed out: " + step.name)
                if (auditWindow.stack.busy) return
                // Every seat acknowledges the same phase before any later
                // actor can send input, keeping focus-sensitive bursts serial.
                if (!driver.acknowledged) {
                    if (step.actor === 0 || step.actor === driver.seat) {
                        if (!driver.acted) {
                            if (step.action() === false) return
                            driver.acted = true
                        }
                        if (!step.check()) return
                    }
                    driver.shared("phase-" + driver.index + "-seat-" + driver.seat, {ready: true})
                    driver.acknowledged = true
                }
                for (let actor = 1; actor <= 3; ++actor)
                    if (!(auditProbe.readShared("phase-" + driver.index + "-seat-" + actor) || {}).ready) return
                driver.assertions.push({step: step.name, actor: step.actor, verifiedLocally: step.actor === 0 || step.actor === driver.seat,
                                           elapsedMs: Date.now() - driver.started})
                driver.index++
                driver.acted = false
                driver.acknowledged = false
                driver.started = Date.now()
            } catch (error) {
                driver.finish(String(error))
            } finally {
                driver.dispatching = false
            }
        }
    }
}
