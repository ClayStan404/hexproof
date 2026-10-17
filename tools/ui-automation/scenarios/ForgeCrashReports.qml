// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors
import QtQuick

// Inject only the shared safe wire fixtures through WsClient's production
// dispatcher. Native failure capture and recipient privacy have separate tests.
Item {
    id: driver
    readonly property bool restarting: Number(auditProbe.environment("HEXPROOF_AUDIT_STAGE")) > 1
    readonly property string fixtureDirectory: auditProbe.environment("HEXPROOF_AUDIT_CRASH_FIXTURES")
    readonly property string reportId: "0123456789abcdef0123456789abcdef"
    readonly property string partialId: "fedcba9876543210fedcba9876543210"
    property var complete: ({})
    property var partial: ({})
    property var steps: []
    property var assertions: []
    property var screenshots: []
    property int index: 0
    property bool acted: false
    property bool dispatching: false
    property bool finished: false
    property double stepStarted: Date.now()

    function require(value, message) {
        if (!value) throw new Error(message + (auditProbe.lastError ? "; " + auditProbe.lastError : ""))
    }
    function find(name) { return auditProbe.find(auditWindow, name, ({})) }
    function click(name) { require(auditProbe.click(find(name)), "Cannot click " + name) }
    function add(name, action, check) { steps.push({name:name, action:action, check:check || (() => true)}) }
    function waited(ms) { return Date.now() - stepStarted >= ms }
    function capture(name) {
        require(auditProbe.capture(auditWindow, name), "Cannot capture " + name)
        screenshots.push(name + ".png")
    }
    function plan() {
        add("Dismiss first-launch notices", () => {
            for (const name of ["dismissSponsorsButton", "laterCardArtRepairButton"]) {
                if (find(name)) { click(name); return false }
            }
            return !!find("mainMenuForgeCrashReportsButton")
        })
        add("Verify maximized isolated offline window", () => {
            require(auditProbe.observe(auditWindow).windowMode === "maximized", "Expected maximized window")
            require(!ws.connected, "Expected an offline profile")
            auditProbe.fixture("forge-crash-report-dispatch", {liveEngineGame:false,
                setup:"Shared four-player and partial error fixtures via production WsClient dispatcher; native capture and hub privacy tested separately"})
            preferences.uiLanguage = "zh_CN"
        }, () => waited(400))
        if (restarting) {
            add("Restore two reports without repeating their notices", () => {
                require(ws.crashReports.entries.length === 2 && !ws.crashReports.noticeId,
                        "History was lost or a dismissed notice reopened")
                require(ws.crashReports.report(reportId).revision === 2, "Final report revision was lost")
                click("mainMenuForgeCrashReportsButton")
            }, () => !!find("forgeCrashReportsScreen"))
            add("Copy persisted report offline after restart", () => click("forgeCrashCopy"),
                () => ws.crashReports.operationStatus === "copied")
            add("Capture restored offline report history", () => capture("history-after-restart"))
            return
        }
        add("Deliver a collecting four-player EDH report", () => {
            complete = JSON.parse(auditProbe.readText(fixtureDirectory + "/error-forge-crash-edh.json")).payload.rulesCrashReport
            complete.occurredAt = new Date().toISOString()
            const initial = JSON.parse(JSON.stringify(complete))
            initial.revision = 1
            initial.collectionState = "collecting"
            initial.completeness.exitEvidence = false
            delete initial.failure.exitCode
            require(auditProbe.applyRulesCrashReportFixture(initial), "Cannot deliver report fixture")
        }, () => !!find("forgeCrashDismiss"))
        add("Check visible notice and copy complete diagnostic text", () => {
            require(ws.crashReports.entries.length === 1, "Expected one incident")
            capture("edh-crash-notice")
            click("forgeCrashCopy")
        }, () => ws.crashReports.operationStatus === "copied")
        add("Read detailed report", () => click("forgeCrashToggleDetails"),
            () => !!find("forgeCrashReportDetails"))
        add("Inspect public source and native evidence", () => {
            const text = find("forgeCrashReportDetails").text
            require(text.indexOf("Rhystic Study") >= 0 && text.indexOf("CopySpellAbility") >= 0
                && text.indexOf("IllegalStateException") >= 0, "Incomplete diagnostic details")
            capture("edh-crash-details")
            click("forgeCrashDismiss")
        }, () => !ws.crashReports.noticeId)
        add("Enrich and redeliver without duplicate notice", () => {
            require(auditProbe.applyRulesCrashReportFixture(complete), "Cannot enrich report")
            require(auditProbe.applyRulesCrashReportFixture(complete), "Cannot redeliver report")
        }, () => waited(400) && !find("forgeCrashDismiss"))
        add("Open offline history from the main menu", () => {
            require(ws.crashReports.entries.length === 1
                && ws.crashReports.report(reportId).revision === 2, "Revision did not replace same incident")
            click("mainMenuForgeCrashReportsButton")
        }, () => !!find("forgeCrashReportsScreen"))
        add("Inspect history and open native save chooser", () => {
            capture("edh-crash-history")
            click("forgeCrashSave")
        }, () => waited(800) && auditProbe.fileDialogState("forgeCrashSaveDialog").visible)
        add("Save full JSON through the real file chooser", () => {
            require(auditProbe.chooseFile("forgeCrashSaveDialog",
                auditProbe.environment("HEXPROOF_AUDIT_OUTPUT") + "/exported-crash-report.json"), "Cannot save JSON")
        }, () => ws.crashReports.operationStatus === "saved")
        add("Verify the saved file and return to main menu", () => {
            const saved = JSON.parse(auditProbe.readText(auditProbe.environment("HEXPROOF_AUDIT_OUTPUT")
                + "/exported-crash-report.json"))
            require(saved.reportId === reportId && saved.revision === 2 && saved.environment.participants === 4
                && saved.context.sources.length === 2 && saved.failure.causes.length === 1,
                "Saved report lost diagnostic evidence")
            click("forgeCrashBack")
        }, () => !!find("mainMenuForgeCrashReportsButton"))
        add("Deliver a process exit with explicitly missing evidence", () => {
            partial = JSON.parse(auditProbe.readText(fixtureDirectory + "/error-forge-crash-partial.json")).payload.rulesCrashReport
            partial.reportId = partialId
            partial.occurredAt = new Date().toISOString()
            require(auditProbe.applyRulesCrashReportFixture(partial), "Cannot deliver partial fixture")
        }, () => !!find("forgeCrashDismiss"))
        add("Capture partial diagnosis without naming a culprit", () => {
            require(ws.crashReports.entries.length === 2
                && ws.crashReports.report(partialId).context.sources.length === 0, "Partial report invented a source")
            require(!find("forgeCrashOperationFeedback"), "Another report's save feedback leaked into this incident")
            capture("partial-crash-notice")
            click("forgeCrashDismiss")
        }, () => !ws.crashReports.noticeId)
    }
    function finish(error) {
        if (finished) return
        finished = true
        if (error && auditProbe.capture(auditWindow, "failure")) screenshots.push("failure.png")
        const geometry = auditProbe.observe(auditWindow)
        auditProbe.record("window-geometry", geometry)
        auditProbe.record("result", {status:error ? "failed" : "passed", scenario:"forge-crash-reports",
            evidence:"native-qt-input", setup:"shared-wire-fixture-through-production-dispatch", liveEngineGame:false,
            restarted:restarting, error:error || "", pendingStep:index < steps.length ? steps[index].name : "",
            assertions:assertions, requiredScreenshots:screenshots, windowMode:geometry.windowMode,
            width:geometry.width, height:geometry.height, dpr:geometry.dpr, screenGeometry:geometry.screenGeometry})
        auditProbe.finish(error ? 1 : 0)
    }
    Component.onCompleted: plan()
    Timer {
        interval: 80
        repeat: true
        running: !driver.finished
        onTriggered: {
            if (driver.dispatching || auditWindow.stack.busy) return
            driver.dispatching = true
            try {
                if (driver.index >= driver.steps.length) { driver.finish(""); return }
                const step = driver.steps[driver.index]
                if (!driver.acted) {
                    if (step.action() === false) {
                        driver.require(Date.now() - driver.stepStarted < 20000, "Cannot reach " + step.name)
                        return
                    }
                    driver.acted = true
                }
                if (step.check()) {
                    driver.assertions.push({step:step.name, elapsedMs:Date.now() - driver.stepStarted})
                    driver.index++
                    driver.acted = false
                    driver.stepStarted = Date.now()
                } else driver.require(Date.now() - driver.stepStarted < 20000, "Timed out: " + step.name)
            } catch (error) { driver.finish(String(error)) }
            finally { driver.dispatching = false }
        }
    }
}
