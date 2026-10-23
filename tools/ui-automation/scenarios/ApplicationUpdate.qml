// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick

Item {
    id: driver
    property int step: 0
    property bool dispatching: false
    property bool finished: false
    property double entered: Date.now()
    property var checks: []
    property var screenshots: []
    property bool sawDownload: false

    function require(value, message) { if (!value) throw new Error(message) }
    function find(name) { return auditProbe.find(auditWindow, name) }
    function click(name, bodyName) {
        const body = bodyName ? find(bodyName) : null
        if (body && (body.moving || (body.contentItem && body.contentItem.moving))) return false
        const target = find(name)
        if (target) { require(auditProbe.click(target), auditProbe.lastError); return true }
        if (body && !body.moving) require(auditProbe.wheel(body, -360), auditProbe.lastError)
        return false
    }
    function capture(name) {
        require(auditProbe.capture(auditWindow, name), auditProbe.lastError)
        screenshots.push(name + ".png")
    }
    function next(label) {
        checks.push({label: label, elapsedMs: Date.now() - entered})
        require(auditProbe.record("progress", checks), auditProbe.lastError)
        step++; entered = Date.now()
    }
    function finish(status, error) {
        finished = true
        auditProbe.record("result", {status: status, scenario: "application-update", message: error || "", checks: checks,
            requiredScreenshots: screenshots, sourceVersion: appUpdater.currentVersion,
            targetVersion: appUpdater.targetVersion, downloadPath: appUpdater.downloadPath,
            downloadReady: appUpdater.downloadReady, sawDownload: sawDownload,
            releaseUrl: appUpdater.releaseUrl, updaterError: appUpdater.lastError,
            coverage: "Native update check, official package download and checksum verification; package installation is a separate runner step"})
        auditProbe.finish(status === "passed" ? 0 : 1)
    }
    Timer {
        interval: 250; repeat: true; running: !driver.finished
        onTriggered: {
            if (driver.dispatching) return
            driver.dispatching = true
            try {
                driver.require(Date.now() - driver.entered < (driver.step === 5 ? 360000 : 45000),
                               "Update stage timed out: " + driver.step)
                if (appUpdater.downloading) driver.sawDownload = true
                if (auditWindow.stack.busy) return
                switch (driver.step) {
                case 0:
                    if (driver.click("mainMenuSettingsButton", "mainMenuBody")) driver.next("Open Settings")
                    break
                case 1:
                    if (driver.find("checkApplicationUpdatesButton")
                            || driver.click("settingsUpdatesModule", "settingsBody"))
                        driver.next("Open application updates")
                    break
                case 2:
                    if (appUpdater.checking) break
                    if (driver.click("checkApplicationUpdatesButton", "settingsBody")) driver.next("Check official application release")
                    break
                case 3:
                    if (appUpdater.checking) break
                    driver.require(!appUpdater.lastError, "Release check failed: " + appUpdater.lastError)
                    driver.require(appUpdater.releaseAvailable && appUpdater.updateAvailable,
                                   "No newer compatible release; package download was not exercised")
                    driver.capture("01-update-available")
                    driver.next("Newer platform package is offered")
                    break
                case 4:
                    if (driver.click("downloadApplicationUpdateButton", "settingsBody")) driver.next("Download through the application UI")
                    break
                case 5:
                    if (appUpdater.downloading) break
                    driver.require(!appUpdater.lastError && appUpdater.downloadReady,
                                   "Package download failed: " + appUpdater.lastError)
                    driver.require(driver.sawDownload, "No download activity was observed")
                    driver.require(appUpdater.downloadPath.startsWith(auditProbe.environment("HEXPROOF_TEST_PROFILE_ROOT") + "/downloads/"),
                                   "Package escaped the isolated download directory")
                    driver.capture("02-package-verified")
                    driver.next("Official archive downloaded and checksum verified")
                    driver.finish("passed", "")
                    break
                }
            } catch (error) {
                auditProbe.record("failure-observation", auditProbe.observe(auditWindow))
                auditProbe.capture(auditWindow, "failure")
                driver.finish("failed", String(error))
            } finally { driver.dispatching = false }
        }
    }
}
