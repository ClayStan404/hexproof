// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick

Item {
    id: driver

    readonly property bool catalogInstall: auditProbe.environment("AUDIT_VARIANT") === "catalog"
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
    function click(name, scrollName, scope) {
        const scroll = scrollName ? find(scrollName) : null
        const body = scroll && scroll.contentItem ? scroll.contentItem : scroll
        if (body && body.moving) return false
        const target = find(name, {}, scope)
        if (target) {
            require(auditProbe.click(target), "Cannot click " + name)
            return true
        }
        if (scroll) require(auditProbe.wheel(scroll, -300), "Cannot scroll " + scrollName)
        return false
    }
    function add(name, action, check, timeout) {
        steps.push({name: name, action: action, check: check || (() => true), timeout: timeout || 20000})
    }
    function capture(name) {
        require(auditProbe.capture(auditWindow, name), "Cannot capture " + name)
        screenshots.push(name + ".png")
    }
    function openCapture() {
        const row = find("shortcutAction-app.fullscreen")
        return row ? click("changeShortcutButton", "shortcutSettingsBody", row) : false
    }
    function savedSequenceMatches(expected) {
        return JSON.stringify(Array.from(preferences.shortcutSequences("app.fullscreen")))
            === JSON.stringify([expected])
    }
    function plan() {
        add("Dismiss first-launch notices", () => {
            for (const name of ["dismissSponsorsButton", "laterCardArtRepairButton"]) {
                const item = find(name)
                if (item) {
                    require(auditProbe.click(item), "Cannot dismiss " + name)
                    return false
                }
            }
            return !!find("mainMenuSettingsButton")
        })
        add("Open settings", () => click("mainMenuSettingsButton"), () => !!find("settingsBody"))
        add("Select English using the visible language control", () => {
            if (preferences.uiLanguage === "en") return true
            const item = find("settingsLanguageSelector")
            if (!item) return false
            require(auditProbe.click(item, item.width * 0.25, item.height / 2), "Cannot choose English")
        }, () => preferences.uiLanguage === "en")
        if (catalogInstall) {
            if (!restarting) {
                add("Confirm clean catalog state", () => {
                    require(!cardCatalog.installed && deckLibrary.count === 0, "Expected an empty isolated profile")
                })
                add("Request official catalog download", () => click("settingsDownloadCatalogButton", "settingsBody"),
                    () => !!find("confirmButton"))
                add("Confirm catalog download", () => click("confirmButton"), () => {
                    require(!cardCatalog.lastError, "Catalog installation failed: " + cardCatalog.lastError)
                    return cardCatalog.installed && !cardCatalog.busy
                }, 600000)
            }
            add("Verify installed catalog and persistence", () => {
                require(cardCatalog.installed && cardCatalog.installedCatalogSchemaVersion === 10,
                        "Missing installed schema-10 catalog")
                require(cardCatalog.enhancedIndexInstalled && cardCatalog.chineseIndexInstalled,
                        "Missing offline indexes")
                require(auditProbe.record("catalog", {version: cardCatalog.installedCatalogVersion,
                    schema: cardCatalog.installedCatalogSchemaVersion, restarted: restarting}), "Cannot record catalog")
                capture("installed-catalog")
            })
            return
        }
        add("Verify initial persisted shortcut and scale", () => {
            require(Math.abs(preferences.interfaceScale - (restarting ? 1.5 : 1)) < 0.001,
                    "Unexpected initial interface scale")
            require(preferences.shortcutCustomized("app.fullscreen") === restarting,
                    "Shortcut persistence mismatch")
            require(savedSequenceMatches(restarting ? "Ctrl+F10" : "F11"), "Persisted sequence mismatch")
        })
        if (!restarting) {
            for (let n = 1; n <= 10; ++n) {
                const expected = 1 + n * 0.05
                add("Increase interface scale to " + Math.round(expected * 100) + "%",
                    () => click("settingsIncreaseScaleButton", "settingsBody"),
                    () => Math.abs(preferences.interfaceScale - expected) < 0.001)
            }
        }
        add("Open keyboard customization", () => click("settingsCustomizeShortcutsButton", "settingsBody"),
            () => !!find("shortcutSettingsScreen"))
        add("Open fullscreen shortcut capture", () => openCapture(), () => preferences.shortcutCaptureActive)
        add("Inspect capture controls at 150% scale", () => {
            require(!!find("shortcutCaptureCancelButton"), "Cancel is outside the visible dialog")
            require(!!find("shortcutCaptureDefaultButton"), "Default is outside the visible dialog")
            capture("shortcut-capture-large-scale")
        })
        if (restarting) {
            add("Restore default after restart", () => click("shortcutCaptureDefaultButton"),
                () => !preferences.shortcutCaptureActive && !preferences.shortcutCustomized("app.fullscreen")
                    && savedSequenceMatches("F11"))
            return
        }
        add("Capture a sequence without saving", () => require(auditProbe.key(Qt.Key_F10, Qt.ControlModifier), "Cannot capture shortcut"),
            () => !!find("shortcutCaptureSaveButton"))
        add("Cancel preserves the old binding", () => click("shortcutCaptureCancelButton"),
            () => !preferences.shortcutCaptureActive && savedSequenceMatches("F11"))
        add("Reopen capture for assignment", () => openCapture(), () => preferences.shortcutCaptureActive)
        add("Reject another action's F1 shortcut", () => require(auditProbe.key(Qt.Key_F1), "Cannot capture F1"), () => {
            const focus = find("shortcutCaptureFocus")
            const save = focus && focus.children.length ? findSaveButton(focus) : null
            const conflict = find("shortcutCaptureConflictText")
            return save && !save.enabled
                && conflict && conflict.text === "Already assigned to: Show or hide shortcut help"
        })
        add("Capture Ctrl+F10", () => require(auditProbe.key(Qt.Key_F10, Qt.ControlModifier), "Cannot capture Ctrl+F10"),
            () => !!find("shortcutCaptureSaveButton"))
        add("Save shortcut through the dialog", () => click("shortcutCaptureSaveButton"),
            () => !preferences.shortcutCaptureActive && preferences.shortcutCustomized("app.fullscreen"))
        add("Record saved shortcut", () => {
            require(savedSequenceMatches("Ctrl+F10"), "Wrong shortcut persisted")
            capture("shortcut-saved")
        })
    }
    function findSaveButton(item) {
        if (item.objectName === "shortcutCaptureSaveButton") return item
        for (const child of item.children || []) {
            const found = findSaveButton(child)
            if (found) return found
        }
        return null
    }
    function finish(error) {
        if (finished) return
        finished = true
        if (error && auditProbe.capture(auditWindow, "failure")) screenshots.push("failure.png")
        auditProbe.record("result", {status: error ? "failed" : "passed", scenario: "preferences-lifecycle",
            error: error || "", pendingStep: index < steps.length ? steps[index].name : "",
            assertions: assertions, requiredScreenshots: screenshots, restarted: restarting,
            catalogInstall: catalogInstall, interfaceScale: preferences.interfaceScale,
            coverage: catalogInstall ? "Official catalog installation and process restart"
                : "Native compact settings, scale, shortcut cancel/save/default and process persistence"})
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
