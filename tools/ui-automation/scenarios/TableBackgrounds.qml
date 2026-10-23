// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick

Item {
    id: driver

    readonly property bool restarting: Number(auditProbe.environment("AUDIT_STAGE")) > 1
    property var steps: []
    property var assertions: []
    property var screenshots: []
    property int index: 0
    property bool acted: false
    property bool dispatching: false
    property bool finished: false
    property double stepStarted: Date.now()

    function require(value, message) {
        if (!value) throw new Error(message)
    }
    function find(name, identity, scope) {
        return auditProbe.find(scope || auditWindow, name, identity || ({}))
    }
    function click(name, scrollName, scope, scrollDelta) {
        const scroll = scrollName ? find(scrollName) : null
        const body = scroll && scroll.contentItem ? scroll.contentItem : scroll
        if (body && body.moving) return false
        const target = find(name, {}, scope)
        if (target) {
            require(auditProbe.click(target), "Cannot click " + name)
            return true
        }
        if (scroll) require(auditProbe.wheel(scroll, scrollDelta || -300), "Cannot scroll " + scrollName)
        return false
    }
    function add(name, action, check, timeout) {
        steps.push({name: name, action: action, check: check || (() => true), timeout: timeout || 20000})
    }
    function capture(name) {
        require(auditProbe.capture(auditWindow, name), "Cannot capture " + name)
        screenshots.push(name + ".png")
    }
    readonly property var keys: ["dusk", "forest", "astral", "volcanic", "frost", "ink", "woven", "default"]
    readonly property var files: ({dusk: "playmat-dusk.png", forest: "forest.png", astral: "astral.png",
        volcanic: "volcanic.png", frost: "frost.png", ink: "ink.png", woven: "woven.png"})
    property string seatsBefore: ""
    property string backgroundBeforeTheme: ""

    function visual(name, parent) {
        if (!parent) return null
        if (parent.objectName === name) return parent
        for (const child of parent.children || []) {
            const match = visual(name, child)
            if (match) return match
        }
        return null
    }

    function selectBackground(key, scrollName) {
        if (preferences.tableBackground === key) return true
        return click("tableBackgroundChoice-" + key, scrollName, null, key === "default" ? 300 : -300)
    }
    function imageReady(key) {
        const image = visual("tableBackgroundImage", auditWindow.stack.currentItem.background)
        if (key === "default") {
            if (!image || image.status !== Image.Null || String(image.source) !== "" || image.visible)
                return false
            if (preferences.uiTheme === "classic") {
                const plain = visual("tableDefaultBackground", auditWindow.stack.currentItem.background)
                require(plain && plain.visible, "Default table background is missing")
                for (const seat of [0, 1]) {
                    const lane = visual("battlefieldZone" + seat, auditWindow.stack.currentItem)
                    require(lane && lane.color.a === 1, "Default Classic battlefield is not opaque")
                }
            }
            return true
        }
        return image && image.status === Image.Ready && String(image.source).endsWith(files[key])
    }
    function prepareTable() {
        auditProbe.fixture("background-table", {
            description: "Production manual table with a local view fixture; no room or gameplay commands.",
            route: "Main.showTable", seats: 2
        })
        gameTable.applySnapshot({gameId: "background-fixture", log: [], seats: [
            {seat: 0, displayName: "Background preview", life: 20, handCount: 7, libraryCount: 53,
             hand: [], battlefield: [{id:"bg-card-1",name:"",faceDown:true,x:0.35,y:0.4}],
             graveyard: [], exile: [], commandZone: [], counters: []},
            {seat: 1, displayName: "Opponent preview", life: 20, handCount: 7, libraryCount: 53,
             hand: [], battlefield: [{id:"bg-card-2",name:"",faceDown:true,x:0.55,y:0.4}],
             graveyard: [], exile: [], commandZone: [], counters: []}
        ]})
        seatsBefore = JSON.stringify(gameTable.seats)
        auditWindow.showTable()
    }
    function plan() {
        add("Dismiss first-launch notices", () => {
            for (const name of ["dismissSponsorsButton", "laterCardArtRepairButton"]) {
                const item = find(name)
                if (item) { require(auditProbe.click(item), "Cannot dismiss " + name); return false }
            }
            return !!find("mainMenuSettingsButton")
        })
        if (restarting) {
            add("Verify background and theme survive process restart", () => {
                require(preferences.tableBackground === "default", "Default background was not restored")
                require(preferences.uiTheme === "glass", "Theme was not restored")
                prepareTable()
            }, () => imageReady("default"))
            add("Capture restored table", () => capture("restored-glass-default"))
            add("Open restored table settings", () => click("tableSettingsButton"),
                () => !!find("openTableBackgroundButton"))
            add("Open restored background picker", () => click("openTableBackgroundButton"),
                () => !!find("tableBackgroundScroll"))
            add("Verify restored thumbnail selection", () => {
                const picker = find("tableBackgroundScroll")
                if (picker.contentItem.moving) return false
                const selected = find("tableBackgroundChoice-default")
                if (!selected) {
                    require(auditProbe.wheel(picker, -300), "Cannot scroll to restored selection")
                    return false
                }
                require(selected.selected, "Restored thumbnail is not selected")
                capture("restored-picker")
            })
            add("Close restored picker", () => click("closeTableBackgroundButton"),
                () => !find("closeTableBackgroundButton"))
            return
        }
        add("Verify fresh profile uses no background image", () => {
            require(preferences.tableBackground === "default", "New profiles must use the default background")
        })
        add("Open settings", () => click("mainMenuSettingsButton"), () => !!find("settingsBody"))
        add("Open appearance settings", () => click("settingsAppearanceModule", "settingsBody"),
            () => !!find("settingsThemeSelector"))
        add("Choose ink artwork in global settings", () => selectBackground("ink", "settingsBody"),
            () => preferences.tableBackground === "ink")
        add("Capture global picker", () => capture("settings-picker"))
        for (const theme of ["classic", "glass"]) {
            if (theme === "glass") {
                add("Prepare settings route for theme selection", () => {
                    auditProbe.fixture("settings-route", {description: "Navigate to settings while preserving the background preference"})
                    auditWindow.stack.push("qrc:/qml/screens/AppearanceSettings.qml")
                }, () => !!find("settingsThemeSelector"))
            }
            add("Select " + theme + " theme", () => {
                const scroll = find("settingsBody")
                require(scroll, "Cannot find settings scroll area")
                if (scroll.contentItem.moving) return false
                const selector = find("settingsThemeSelector")
                const top = selector ? selector.mapToItem(scroll, 0, 0).y : -1
                if (!selector || top < 0 || top + selector.height > scroll.height) {
                    require(auditProbe.wheel(scroll, 500), "Cannot scroll to theme selector")
                    return false
                }
                backgroundBeforeTheme = preferences.tableBackground
                return auditProbe.click(selector, selector.width * (theme === "glass" ? 0.75 : 0.25), selector.height / 2)
            }, () => {
                require(preferences.tableBackground === backgroundBeforeTheme, "Theme selection changed the background")
                return preferences.uiTheme === theme
            })
            add("Prepare " + theme + " production table", () => prepareTable(),
                () => imageReady(preferences.tableBackground)
                      && !!visual("battlefieldPlayerName0", auditWindow.stack.currentItem))
            for (const key of keys) {
                add("Open table settings " + theme + " " + key, () => click("tableSettingsButton"),
                    () => !!find("openTableBackgroundButton"))
                add("Open background picker " + theme + " " + key, () => click("openTableBackgroundButton"),
                    () => !!find("tableBackgroundScroll"))
                add("Select " + theme + " " + key, () => selectBackground(key, "tableBackgroundScroll"),
                    () => preferences.tableBackground === key)
                add("Close background picker " + theme + " " + key, () => click("closeTableBackgroundButton"),
                    () => !find("closeTableBackgroundButton") && imageReady(key))
                add("Capture " + theme + " " + key, () => {
                    require(preferences.uiTheme === theme, "Background selection changed the theme")
                    require(JSON.stringify(gameTable.seats) === seatsBefore, "Background selection changed the table")
                    capture(theme + "-" + key)
                })
            }
        }
    }
    function finish(error) {
        if (finished) return
        finished = true
        if (error && auditProbe.capture(auditWindow, "failure")) screenshots.push("failure.png")
        auditProbe.record("result", {status: error ? "failed" : "passed", scenario: "table-backgrounds",
            error: error || "", pendingStep: index < steps.length ? steps[index].name : "",
            assertions: assertions, requiredScreenshots: screenshots, restarted: restarting,
            interfaceScale: preferences.interfaceScale,
            coverage: "Native global and in-table background selection, both appearances, model preservation and process persistence"})
        auditProbe.finish(error ? 1 : 0)
    }
    Component.onCompleted: plan()
    Timer {
        interval: 60
        repeat: true
        running: !driver.finished
        onTriggered: {
            if (driver.dispatching) return
            driver.dispatching = true
            try {
                if (driver.index >= driver.steps.length) { driver.finish(""); return }
                if (auditWindow.stack.busy) return
                const step = driver.steps[driver.index]
                if (!driver.acted) {
                    if (step.action() === false) {
                        driver.require(Date.now() - driver.stepStarted < step.timeout, "Cannot reach: " + step.name)
                        return
                    }
                    driver.acted = true
                }
                if (step.check()) {
                    driver.assertions.push({step: step.name, elapsedMs: Date.now() - driver.stepStarted})
                    driver.index++
                    driver.acted = false
                    driver.stepStarted = Date.now()
                } else driver.require(Date.now() - driver.stepStarted < step.timeout, "Timed out: " + step.name)
            } catch (error) {
                driver.finish(String(error))
            } finally {
                driver.dispatching = false
            }
        }
    }
}
