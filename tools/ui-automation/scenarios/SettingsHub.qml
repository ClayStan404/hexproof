// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick

Item {
    id: driver

    property var steps: []
    property var screenshots: []
    property int index: 0
    property bool acted: false
    property bool dispatching: false
    property bool finished: false
    property double stepStarted: Date.now()

    function require(value, message) {
        if (!value)
            throw new Error(message)
    }
    function find(name, identity, scope) {
        return auditProbe.find(scope || auditWindow, name, identity || ({}))
    }
    function click(name, scrollName) {
        const scroll = scrollName ? find(scrollName) : null
        const body = scroll && scroll.contentItem ? scroll.contentItem : scroll
        if (body && body.moving)
            return false
        const target = find(name)
        if (target) {
            require(auditProbe.click(target), "Cannot click " + name)
            return true
        }
        if (scroll)
            require(auditProbe.wheel(scroll, -300), "Cannot scroll " + scrollName)
        return false
    }
    function add(name, action, check, timeout) {
        steps.push({
            name: name,
            action: action,
            check: check || (() => true),
            timeout: timeout || 20000
        })
    }
    function capture(name) {
        require(auditProbe.capture(auditWindow, name), "Cannot capture " + name)
        screenshots.push(name + ".png")
    }
    function finish(error) {
        if (finished)
            return
        finished = true
        if (error && auditProbe.capture(auditWindow, "failure"))
            screenshots.push("failure.png")
        const geometry = auditProbe.observe(auditWindow)
        auditProbe.record("window-geometry", geometry)
        auditProbe.record("result", {
            status: error ? "failed" : "passed",
            scenario: "settings-hub",
            evidence: "native-qt-input",
            error: error || "",
            pendingStep: index < steps.length ? steps[index].name : "",
            requiredScreenshots: screenshots,
            requestedWindowMode: geometry.requestedWindowMode,
            windowMode: geometry.windowMode,
            width: geometry.width,
            height: geometry.height,
            dpr: geometry.dpr,
            screenGeometry: geometry.screenGeometry
        })
        auditProbe.finish(error ? 1 : 0)
    }

    function plan() {
        add("Dismiss first-launch notices", () => {
            require(auditProbe.activate(), "Cannot activate test window")
            for (const name of ["dismissSponsorsButton", "laterCardArtRepairButton"]) {
                const item = find(name)
                if (item) {
                    require(auditProbe.click(item), "Cannot dismiss " + name)
                    return false
                }
            }
            return !!find("mainMenuSettingsButton")
        })
        add("Open settings categories", () => click("mainMenuSettingsButton"),
            () => !!find("settingsHubScreen") && !!find("settingsBody"))
        add("Verify controls live in separate modules", () => {
            require(find("settingsAppearanceModule"), "Missing appearance category")
            require(find("settingsLanguageModule"), "Missing language category")
            require(find("settingsCatalogModule"), "Missing card database category")
            require(find("settingsManageArtButton"), "Missing card art category")
            require(find("settingsCustomizeShortcutsButton"), "Missing shortcuts category")
            require(find("settingsUpdatesModule"), "Missing updates category")
            require(!find("settingsThemeSelector"), "Theme control leaked onto the hub")
            require(!find("settingsLanguageSelector"), "Language control leaked onto the hub")
            require(!find("settingsDownloadCatalogButton"), "Catalog download leaked onto the hub")
            require(!find("checkApplicationUpdatesButton"), "Update check leaked onto the hub")
            capture("01-settings-hub")
        })
        add("Open appearance settings", () => click("settingsAppearanceModule", "settingsBody"),
            () => !!find("appearanceSettingsScreen") && !!find("settingsThemeSelector"))
        add("Capture appearance module", () => capture("02-appearance"))
        add("Return to categories from appearance", () => click("screenBackButton"),
            () => !!find("settingsHubScreen") && !!find("settingsLanguageModule"))
        add("Open language settings", () => click("settingsLanguageModule", "settingsBody"),
            () => !!find("languageSettingsScreen") && !!find("settingsLanguageSelector"))
        add("Return to categories from language", () => click("screenBackButton"),
            () => !!find("settingsCatalogModule"))
        add("Open card database settings", () => click("settingsCatalogModule", "settingsBody"),
            () => !!find("catalogSettingsScreen")
                  && (!!find("settingsDownloadCatalogButton") || !!find("settingsImportCatalogButton")))
        add("Return to categories from database", () => click("screenBackButton"),
            () => !!find("settingsUpdatesModule"))
        add("Open application updates", () => click("settingsUpdatesModule", "settingsBody"),
            () => !!find("updatesSettingsScreen") && !!find("checkApplicationUpdatesButton"))
        add("Capture updates module", () => capture("03-updates"))
    }

    Timer {
        interval: 80
        repeat: true
        running: !driver.finished
        onTriggered: {
            if (driver.dispatching)
                return
            driver.dispatching = true
            try {
                if (driver.steps.length === 0)
                    driver.plan()
                if (driver.index >= driver.steps.length) {
                    driver.finish("")
                    return
                }
                const step = driver.steps[driver.index]
                if (Date.now() - driver.stepStarted > step.timeout)
                    throw new Error("Timed out: " + step.name)
                if (auditWindow.stack.busy)
                    return
                if (!driver.acted) {
                    if (step.action() === false)
                        return
                    driver.acted = true
                    driver.stepStarted = Date.now()
                }
                if (!step.check())
                    return
                driver.index += 1
                driver.acted = false
                driver.stepStarted = Date.now()
            } catch (error) {
                driver.finish(String(error))
            } finally {
                driver.dispatching = false
            }
        }
    }
}
