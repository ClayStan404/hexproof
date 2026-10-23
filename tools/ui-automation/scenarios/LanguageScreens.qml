// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick

// Native evidence for the interface-language work: selects every shipped UI
// language through the visible settings control, captures the language
// settings page, the open language list popup, the main menu, and the
// connection form, and verifies each language's own name is displayed.
Item {
    id: driver
    property var steps: []
    property var assertions: []
    property var screenshots: []
    property int index: 0
    property bool dispatched: false
    property bool dispatching: false
    property bool finished: false
    property double entered: 0
    property double started: Date.now()
    readonly property var nativeNames: ({
        "en": "English", "zh": "简体中文", "ja": "日本語", "fr": "Français",
        "de": "Deutsch", "es": "Español", "it": "Italiano",
        "pt_BR": "Português (Brasil)", "zh_TW": "繁體中文"
    })

    function require(value, message) { if (!value) throw new Error(message) }
    function find(name) { return auditProbe.find(auditWindow, name, ({})) }
    function click(name, scrollName) {
        const target = find(name)
        if (target) {
            require(auditProbe.click(target), "Cannot click " + name)
            return true
        }
        const scroll = scrollName ? find(scrollName) : null
        if (scroll && !scroll.moving)
            require(auditProbe.wheel(scroll, -280), "Cannot scroll " + scrollName)
        return false
    }
    function add(name, action, check) {
        steps.push({name: name, action: action, check: check || (() => true)})
    }
    function capture(name) {
        require(auditProbe.capture(auditWindow, name), "Cannot capture " + name)
        screenshots.push(name + ".png")
    }
    function languageIndex(code) {
        for (let position = 0; position < uiLanguages.length; ++position)
            if (uiLanguages[position].code === code)
                return position
        return -1
    }
    function selector() { return find("settingsLanguageSelector") }

    function plan() {
        add("Activate maximized test window", () => {
            require(auditProbe.activate(), "Cannot activate test window")
            for (const name of ["dismissSponsorsButton", "laterCardArtRepairButton"])
                if (find(name)) { click(name); return false }
            require(auditProbe.observe(auditWindow).windowMode === "maximized", "Expected maximized native window")
            return !!find("mainMenuSettingsButton")
        }, () => !auditWindow.stack.busy)
        add("Open settings", () => click("mainMenuSettingsButton"), () => !!find("settingsBody"))
        add("Open language settings", () => click("settingsLanguageModule", "settingsBody"),
            () => !!find("settingsLanguageSelector"))
        add("Capture English settings page", () => { capture("00-en-language-settings"); return true })
        add("Verify default language selection", () => true,
            () => preferences.uiLanguage === "en" && selector().displayText === "English")
        add("Open the language list popup", () => {
            require(click("settingsLanguageSelector"), "Cannot open language list")
            return true
        }, () => selector().popup.opened && selector().popup.contentItem.count === uiLanguages.length)
        add("Capture open language list popup", () => { capture("01-language-popup"); return true })
        add("Close the language list popup", () => {
            require(auditProbe.key(Qt.Key_Escape), "Cannot close language list")
            return true
        }, () => !selector().popup.opened)
        for (let position = 1; position < uiLanguages.length; ++position) {
            const code = uiLanguages[position].code
            const label = driver.nativeNames[code]
            add("Select " + label + " via the visible control", (position => () => {
                const target = selector()
                if (!target) return false
                require(auditProbe.click(target), "Cannot open language list")
                require(auditProbe.key(Qt.Key_Home), "Cannot reset language list")
                for (let step = 0; step < position; ++step)
                    require(auditProbe.key(Qt.Key_Down), "Cannot navigate language list")
                require(auditProbe.key(Qt.Key_Return), "Cannot confirm language")
                return true
            })(position), (code => () => preferences.uiLanguage === code
                && !selector().popup.opened)(code))
            add("Verify " + label + " shows its own name", (label => () => {
                require(selector().displayText === label,
                        "Combo shows " + selector().displayText + " instead of " + label)
                return true
            })(label))
            add("Capture settings page in " + label,
                (code => () => { capture("0" + (position + 1) + "-settings-" + code); return true })(code))
        }
        add("Return to settings categories", () => click("screenBackButton"), () => !!find("settingsBody"))
        add("Return to main menu", () => click("screenBackButton"), () => !!find("mainMenuConnectButton"))
        add("Capture translated main menu", () => { capture("10-main-menu"); return true })
        add("Open the connection form", () => click("mainMenuConnectButton"),
            () => !!find("serverSelector") && !auditWindow.stack.busy)
        add("Capture translated connection form", () => { capture("11-connect-page"); return true })
    }
    function finish(error) {
        if (finished) return
        finished = true
        if (error && auditProbe.capture(auditWindow, "failure")) screenshots.push("failure.png")
        const geometry = auditProbe.observe(auditWindow)
        auditProbe.record("window-geometry", geometry)
        auditProbe.record("ui-languages", uiLanguages)
        auditProbe.record("result", {
            status: error ? "failed" : "passed", scenario: "language-screens", error: error || "",
            assertions: assertions, pendingStep: index < steps.length ? steps[index].name : "",
            requiredScreenshots: screenshots, elapsedMs: Date.now() - started,
            requestedWindowMode: geometry.requestedWindowMode, windowMode: geometry.windowMode,
            width: geometry.width, height: geometry.height, dpr: geometry.dpr,
            screenGeometry: geometry.screenGeometry,
            coverage: "Native production client selecting every shipped interface language through the visible settings combo, with maximized-window captures of the settings page, language popup, main menu, and connection form."
        })
        auditProbe.finish(error ? 1 : 0)
    }
    Component.onCompleted: { try { plan() } catch (error) { finish(String(error)) } }
    Timer {
        interval: 120
        repeat: true
        running: !driver.finished
        onTriggered: {
            if (driver.dispatching) return
            driver.dispatching = true
            try {
                if (driver.index >= driver.steps.length) { driver.finish(""); return }
                const step = driver.steps[driver.index]
                if (driver.entered === 0) driver.entered = Date.now()
                driver.require(Date.now() - driver.entered < 60000, "Timeout: " + step.name)
                if (!driver.dispatched && !auditWindow.stack.busy)
                    driver.dispatched = step.action() !== false
                if (driver.dispatched && step.check()) {
                    driver.assertions.push({name: step.name, passed: true, elapsedMs: Date.now() - driver.entered})
                    ++driver.index
                    driver.entered = 0
                    driver.dispatched = false
                }
            } catch (error) { driver.finish(String(error)) }
            finally { driver.dispatching = false }
        }
    }
}
