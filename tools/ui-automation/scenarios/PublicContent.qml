// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick

Item {
    id: driver
    property int stage: Number(auditProbe.environment("HEXPROOF_AUDIT_STAGE"))
    property int step: 0
    property bool finished: false
    property bool dispatching: false
    property bool advanced: false
    property double entered: Date.now()
    property var checks: []
    property var screenshots: []
    function require(value, message) { if (!value) throw new Error(message) }
    function find(name) { return auditProbe.find(auditWindow, name, ({})) }
    function click(name, scroller) {
        const target = find(name)
        if (target) { require(auditProbe.click(target), auditProbe.lastError); return true }
        const body = scroller ? find(scroller) : null
        if (body && !body.moving) require(auditProbe.wheel(body, -280), auditProbe.lastError)
        return false
    }
    function next(label) {
        checks.push(label)
        require(auditProbe.record("progress", checks), auditProbe.lastError)
        ++step
        entered = Date.now()
    }
    function capture(name) {
        require(auditProbe.capture(auditWindow, name), auditProbe.lastError)
        screenshots.push(name + ".png")
    }
    function advance(phase) {
        advanced = false
        const request = new XMLHttpRequest()
        request.onreadystatechange = function() {
            if (request.readyState === XMLHttpRequest.DONE && request.status === 200)
                driver.advanced = true
        }
        request.open("GET", auditProbe.environment("HEXPROOF_CONTENT_INDEX_URL").replace("index.json", "advance/" + phase))
        request.send()
    }
    function finish(status, message) {
        finished = true
        auditProbe.record("result", {status: status, scenario: "public-content", stage: stage,
            message: message || "", checks: checks, requiredScreenshots: screenshots,
            sponsors: publicContent.sponsors.length, pendingSponsors: Array.from(publicContent.newSponsorIds),
            unread: publicContent.unreadCount, history: publicContent.historicalAnnouncements.length})
        auditProbe.finish(status === "passed" ? 0 : 1)
    }
    Timer {
        interval: 250
        repeat: true
        running: !driver.finished
        onTriggered: {
            if (driver.dispatching || auditWindow.stack.busy) return
            driver.dispatching = true
            try {
                driver.require(Date.now() - driver.entered < 20000, "Content stage timed out: " + driver.stage + "/" + driver.step)
                if (!publicContent.startupReady || publicContent.refreshing) return
                if (driver.stage === 1) {
                    switch (driver.step) {
                    case 0:
                        driver.require(publicContent.sponsors.length === 2, "Fresh remote roster missing")
                        if (!driver.find("dismissSponsorsButton")) break
                        driver.capture("01-new-sponsors")
                        if (driver.click("dismissSponsorsButton")) driver.next("Acknowledge initial remote supporters")
                        break
                    case 1:
                        driver.require(publicContent.newSponsorIds.length === 0, "Sponsors were not acknowledged")
                        driver.capture("02-unread-menu")
                        if (driver.click("mainMenuAnnouncementsButton", "mainMenuBody")) driver.next("Open visible unread announcement")
                        break
                    case 2:
                        if (driver.click("readAnnouncement_maintenance", "announcementsScroll")) driver.next("Read current announcement")
                        break
                    case 3:
                        driver.require(publicContent.unreadCount === 0, "Reading did not clear unread")
                        driver.capture("03-announcement-details")
                        if (driver.click("historicalAnnouncementsButton")) driver.next("Open history")
                        break
                    case 4:
                        if (driver.click("readAnnouncement_history", "announcementsScroll")) driver.next("Read retained historical body")
                        break
                    case 5:
                        driver.capture("04-history")
                        if (driver.click("screenBackButton")) driver.next("Return to main menu")
                        break
                    case 6:
                        if (driver.click("mainMenuSponsorsButton", "mainMenuBody")) driver.next("Open full sponsor roster")
                        break
                    case 7:
                        driver.advance(2)
                        driver.next("Expire a supporter on the loopback content server")
                        break
                    case 8:
                        if (driver.advanced && driver.click("refreshPublicContentButton")) driver.next("Refresh cached roster through the UI")
                        break
                    case 9:
                        driver.require(publicContent.sponsors.length === 1, "Expired sponsor remains visible")
                        driver.require(publicContent.sponsors[0].avatarSource.toString().startsWith("file:"), "Avatar was not persisted locally")
                        driver.capture("05-expired-sponsor-removed")
                        driver.finish("passed", "")
                        break
                    }
                } else if (driver.stage === 2) {
                    switch (driver.step) {
                    case 0:
                        driver.require(!driver.find("dismissSponsorsButton"), "Acknowledged sponsor popup repeated")
                        driver.require(publicContent.sponsors.length === 1 && publicContent.unreadCount === 0,
                                       "Roster/read state failed to survive restart")
                        driver.capture("01-cached-restart")
                        if (driver.click("mainMenuSponsorsButton", "mainMenuBody")) driver.next("Inspect cached roster after restart")
                        break
                    case 1:
                        driver.advance(3)
                        driver.next("Add a new sponsor during this session")
                        break
                    case 2:
                        if (driver.advanced && driver.click("refreshPublicContentButton")) driver.next("Download changed roster")
                        break
                    case 3:
                        driver.require(publicContent.newSponsorIds.length === 1, "New sponsor was not left pending")
                        driver.require(!driver.find("dismissSponsorsButton"), "Runtime update interrupted the session")
                        driver.capture("02-new-sponsor-pending")
                        driver.finish("passed", "")
                        break
                    }
                } else {
                    if (driver.step === 1) {
                        driver.require(publicContent.newSponsorIds.length === 0, "Newcomer acknowledgement failed")
                        driver.finish("passed", "")
                        return
                    }
                    if (!driver.find("dismissSponsorsButton")) return
                    driver.require(publicContent.newSponsorIds.length === 1, "Previously acknowledged IDs were reset")
                    driver.capture("01-next-launch-new-sponsor")
                    if (driver.click("dismissSponsorsButton")) {
                        driver.next("Next startup announces only the new supporter")
                    }
                }
            } catch (error) {
                auditProbe.capture(auditWindow, "failure")
                driver.finish("failed", String(error))
            } finally { driver.dispatching = false }
        }
    }
}
