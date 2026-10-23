// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors
import QtQuick

// The receiver is real and local; the game and crash evidence are deterministic
// fixtures. Never run with a production feedback endpoint or GitHub destination.
Item {
    id: driver
    readonly property bool restarting: Number(auditProbe.environment("HEXPROOF_AUDIT_STAGE")) > 1
    readonly property bool offline: restarting && auditProbe.environment("HEXPROOF_AUDIT_FEEDBACK_OFFLINE") === "1"
    readonly property string fixtures: auditProbe.environment("HEXPROOF_AUDIT_FEEDBACK_FIXTURES")
    readonly property string imagePath: auditProbe.environment("HEXPROOF_AUDIT_FEEDBACK_IMAGE")
    readonly property string output: auditProbe.environment("HEXPROOF_AUDIT_OUTPUT")
    readonly property string sentDescription: "Native feedback audit: explicit diagnostic and image selection."
    readonly property string draftDescription: "Unsent restart draft: retain this text on this device."
    property string sentId: ""
    property string draftId: ""
    property string discardedId: ""
    property var selectedReport: ({})
    property var steps: []
    property var assertions: []
    property var screenshots: []
    property int index: 0
    property bool acted: false
    property bool dispatching: false
    property bool finished: false
    property double stepStarted: Date.now()
    property double lastStatusRefresh: 0
    property double lastBodyScroll: 0

    function require(value, message) {
        if (!value) throw new Error(message + (auditProbe.lastError ? "; " + auditProbe.lastError : ""))
    }
    function find(name) { return auditProbe.find(auditWindow, name, ({})) }
    function click(name) { require(auditProbe.click(find(name)), "Cannot click " + name) }
    function clickBody(name) {
        const composer = find("feedbackComposer")
        // A wheel event may leave the owned Flickable moving. Wait for its
        // geometry to settle before resolving a native click target.
        if (Date.now() - lastBodyScroll < 400
                || (composer && composer.contentItem && composer.contentItem.moving)) return false
        if (find(name)) { click(name); return true }
        require(auditProbe.wheel(composer, -480), "Cannot scroll to " + name)
        lastBodyScroll = Date.now()
        return false
    }
    function previewImageReady() {
        const closeButton = find("feedbackPreviewClose")
        if (!closeButton) return false
        // The image is passive. Inspect its visual state via the current preview
        // layout; never use this path as a target for input or to bypass guards.
        for (const visual of closeButton.parent.children) {
            if (visual.objectName === "feedbackPreviewImage")
                return visual.visible && visual.width > 0 && visual.height > 0 && visual.status === Image.Ready
        }
        return false
    }
    function publicationControl() {
        const consent = find("feedbackPublicConsent")
        if (!consent) return null
        // Inspect only this owned preview's footer. Disabled controls are not
        // eligible input targets, so find() intentionally cannot return them.
        // This reference is passive evidence and is never used for input.
        for (const row of consent.parent.children) {
            for (const control of row.children || []) {
                if (control.objectName === "feedbackPublish") return control
            }
        }
        return null
    }
    function enter(name, text) {
        click(name)
        require(auditProbe.key(Qt.Key_A, Qt.ControlModifier) && auditProbe.text(text), "Cannot enter " + name)
    }
    function add(name, action, check) { steps.push({name:name, action:action, check:check || (() => true)}) }
    function waited(ms) { return Date.now() - stepStarted >= ms }
    function attachment(kind) { return (feedbackService.draft.attachments || []).find(item => item.kind === kind) }
    function record(description) { return feedbackService.records.find(item => item.description === description) }
    function fixture(name) { return JSON.parse(auditProbe.readText(fixtures + "/" + name)).payload }
    function capture(name) {
        require(auditProbe.capture(auditWindow, name), "Cannot capture " + name)
        screenshots.push(name + ".png")
    }
    function addPublicationSteps(expectReceipt) {
        add("Review the complete public submission without sending", () => {
            if (!find("feedbackSend")) return false
            if (expectReceipt) sentId = feedbackService.draft.id
            click("feedbackSend")
        }, () => !!find("feedbackPublicConsent"))
        add("Inspect exact public preview and explicitly consent", () => {
            require(feedbackService.draft.state === "draft" && !feedbackService.draft.uploadAuthorized,
                    "Opening publication preview authorized transmission")
            require(find("feedbackPublicDescription").text === feedbackService.draft.description,
                    "Public preview changed the submitted description")
            const publish = publicationControl()
            require(publish && publish.visible && !publish.enabled
                    && !find("feedbackPublicConsent").checked && !find("feedbackPublish"),
                    "Public consent was selected automatically")
            capture("feedback-public-preview")
            click("feedbackPublicConsent")
        }, () => !!find("feedbackPublish") && find("feedbackPublish").enabled)
        add("Publish only after explicit native confirmation", () => click("feedbackPublish"),
            () => expectReceipt ? feedbackService.draft.state === "accepted" && !!feedbackService.draft.receipt
                : feedbackService.draft.uploadAuthorized === true && !!find("feedbackStopSending"))
        add("Wait for the public preview to close and storage to settle", () => {},
            () => waited(350) && !feedbackService.busy && !feedbackService.saving
                && !find("feedbackPublicConsent") && !find("feedbackPublish"))
    }
    function refreshedStatus(check) {
        if (check()) return true
        if (Date.now() - lastStatusRefresh >= 6000 && !feedbackService.busy && !feedbackService.saving) {
            click("feedbackCheckReceipt")
            lastStatusRefresh = Date.now()
        }
        return false
    }
    function addRemovalSteps() {
        add("Refresh until the complete public contribution is verified", () => { lastStatusRefresh = 0 },
            () => refreshedStatus(() => feedbackService.draft.publicationState === "published"))
        add("Inspect publication without opening GitHub", () => {
            require(feedbackService.draft.issueUrl && feedbackService.draft.removalState === "none",
                    "Verified publication lacks its independent issue mapping")
            capture("feedback-published")
            return clickBody("feedbackRequestRemoval")
        }, () => !!find("confirmButton"))
        add("Request authenticated removal through the client", () => click("confirmButton"),
            () => !!feedbackService.draft.removalState && feedbackService.draft.removalState !== "none")
        add("Keep the local receipt while removal is confirmed", () => { lastStatusRefresh = 0 },
            () => refreshedStatus(() => feedbackService.draft.removalState === "removed"))
        add("Capture confirmed removal independently of local deletion", () => {
            require(feedbackService.records.some(item => item.id === sentId), "Public removal deleted the local receipt")
            capture("feedback-removed")
        })
    }
    function addExportSteps(filename) {
        add("Open native export chooser: " + filename, () => clickBody("feedbackExport"),
            () => waited(500) && auditProbe.fileDialogState("feedbackExportDialog").visible)
        add("Save feedback through native chooser: " + filename, () => {
            require(auditWindow.feedbackInteractionOpen, "Input gate dropped in the export chooser")
            require(auditProbe.chooseFile("feedbackExportDialog", output + "/" + filename), "Cannot save feedback")
        }, () => feedbackService.operationCode === "exported"
                && feedbackService.operationRecordId === feedbackService.draft.id)
        add("Inspect visible-content-only export: " + filename, () => {
            const saved = JSON.parse(auditProbe.readText(output + "/" + filename))
            require(saved.id === feedbackService.draft.id && saved.description === feedbackService.draft.description,
                    "Export did not contain the selected record")
            for (const key of ["secret", "endpoint", "destination", "uploadAuthorized", "attempts", "queries"])
                require(saved[key] === undefined, "Export exposed internal " + key)
            auditProbe.record("feedback-export-" + filename, {id:saved.id, state:saved.state,
                attachmentCount:(saved.attachments || []).length, noInternalTransportFields:true})
        })
    }
    function addTableSteps() {
        add("Close feedback before applying manual table fixture", () => click("feedbackClose"),
            () => !auditWindow.feedbackInteractionOpen)
        add("Dismiss the crash notice deferred during feedback", () => {
            if (!find("forgeCrashDismiss")) return false
            click("forgeCrashDismiss")
        }, () => !ws.crashReports.noticeId)
        add("Enter a deterministic manual table", () => {
            const room = fixture("room-snapshot-owner.json")
            room.phase = "started"
            room.role = "player"
            room.seatIndex = 0
            room.host = true
            room.rulesMode = "manual"
            require(auditProbe.applyManualTableFixture(room, fixture("game-snapshot-owner.json")), "Cannot apply manual fixture")
            auditWindow.showTable()
        }, () => !!find("tableFeedbackButton"))
        add("Open feedback from manual table action rail", () => click("tableFeedbackButton"),
            () => !!find("feedbackContextAdd"))
        add("Reuse draft without overwriting manual-table text", () => click("feedbackContextAdd"),
            () => !!find("feedbackDescription") && !find("feedbackContextAdd"))
        add("Verify manual shortcut modal gate", () => {
            const table = auditWindow.stack.currentItem
            require(auditWindow.feedbackInteractionOpen && table.tableModalOpen
                    && table.sessionUi.counterShortcutBlocked(), "Manual shortcuts remained enabled")
            require(feedbackService.draft.description === draftDescription, "Context entry replaced draft text")
            capture("manual-feedback-input-gate")
            click("feedbackClose")
        }, () => !auditWindow.feedbackInteractionOpen)
        add("Enter a deterministic Forge table", () => {
            const room = fixture("room-snapshot-owner.json")
            room.phase = "started"
            room.role = "player"
            room.seatIndex = 0
            room.host = true
            room.rulesMode = "forge"
            room.format = "modern"
            room.forgeHostingMode = "server"
            room.forgeHostConnected = true
            require(auditProbe.applyRulesTableFixture(room, fixture("rules-snapshot-stack-targets.json")), "Cannot apply Forge fixture")
            auditWindow.showTable()
        }, () => !!find("forgeGameMenu"))
        add("Open Forge action menu", () => click("forgeGameMenu"), () => !!find("rulesFeedbackButton"))
        add("Open feedback from Forge action menu", () => click("rulesFeedbackButton"), () => !!find("feedbackContextAdd"))
        add("Reuse draft from Forge table", () => click("feedbackContextAdd"),
            () => !!find("feedbackDescription") && !find("feedbackContextAdd"))
        add("Verify Forge priority gate and preserved preference", () => {
            require(auditWindow.feedbackInteractionOpen && auditWindow.stack.currentItem.priorityInputBlocked,
                    "Forge priority gate did not include feedback")
            require(feedbackService.draft.description === draftDescription, "Forge entry replaced draft text")
            auditProbe.record("feedback-game-input-gates", {manual:true, forge:true,
                setup:"deterministic native table projections", liveEngineGame:false})
            capture("forge-feedback-input-gate")
            click("feedbackClose")
        }, () => !auditWindow.feedbackInteractionOpen && !feedbackService.saving)
    }
    function plan() {
        add("Dismiss first-launch notices", () => {
            for (const name of ["dismissSponsorsButton", "laterCardArtRepairButton"]) {
                if (find(name)) { click(name); return false }
            }
            return !!find("mainMenuFeedbackButton") && !feedbackService.busy
        })
        add("Verify isolated maximized local-receiver setup", () => {
            require(auditProbe.observe(auditWindow).windowMode === "maximized", "Expected maximized window")
            require(!ws.connected && feedbackService.enabled, "Expected offline game hub and enabled local feedback")
            auditProbe.fixture("feedback-native-ui", {liveEngineGame:false, externalMessages:false,
                setup:"real local receiver; deterministic diagnostic/manual/Forge fixtures", offline:offline})
            preferences.uiLanguage = "en"
            click("mainMenuFeedbackButton")
        }, () => !!find("feedbackDescription"))
        if (restarting) {
            add("Inspect persisted received feedback and unsent draft", () => {
                const received = record(sentDescription), draft = record(draftDescription)
                require(received && received.state === "accepted" && received.receipt, "Receipt was lost on restart")
                require(draft && draft.state === "draft" && !draft.uploadAuthorized, "Draft changed state on restart")
                sentId = received.id
                draftId = draft.id
                click("feedbackHistoryButton")
            }, () => !!find("feedbackHistoryCase-" + draftId))
            add("Open restored unsent draft from history", () => click("feedbackHistoryCase-" + draftId),
                () => feedbackService.draft.id === draftId && !!find("feedbackDescription"))
            add("Capture draft retained across restart", () => {
                require(find("feedbackDescription").text === draftDescription, "Draft body was lost")
                capture("draft-after-restart")
            })
            if (offline) {
                addPublicationSteps(false)
                add("Stop further retries without claiming recall", () => click("feedbackStopSending"),
                    () => feedbackService.draft.uploadAuthorized !== true && !feedbackService.saving)
                add("Capture stopped offline feedback", () => {
                    require(feedbackService.draft.state !== "accepted", "Offline submission unexpectedly received")
                    capture("stopped-offline-feedback")
                })
                addExportSteps("stopped-feedback.json")
            }
            add("Open deletion confirmation", () => {
                discardedId = feedbackService.draft.id
                return clickBody("feedbackDelete")
            }, () => !!find("confirmButton"))
            add("Confirm deletion of local draft only", () => click("confirmButton"),
                () => !feedbackService.records.find(item => item.id === discardedId))
            add("Preserve the previously received record after deletion", () => {
                require(feedbackService.records.find(item => item.id === sentId), "Deleting draft removed received history")
                capture("feedback-history-after-deletion")
                click("feedbackClose")
            }, () => !auditWindow.feedbackInteractionOpen)
            return
        }
        add("Type English feedback with native input", () => enter("feedbackDescription", sentDescription),
            () => feedbackService.draft.description === sentDescription && !feedbackService.saving)
        add("Capture English composer before any upload", () => {
            require(feedbackService.draft.state === "draft" && !feedbackService.draft.uploadAuthorized, "Typing authorized transmission")
            capture("feedback-english")
            preferences.uiLanguage = "zh_CN"
        }, () => waited(300))
        add("Deliver safe diagnostic fixture while composer is open", () => {
            selectedReport = fixture("error-forge-crash-edh.json").rulesCrashReport
            selectedReport.occurredAt = new Date().toISOString()
            selectedReport.revision = 1
            selectedReport.collectionState = "collecting"
            require(auditProbe.applyRulesCrashReportFixture(selectedReport), "Cannot deliver diagnostic fixture")
        }, () => ws.crashReports.entries.length > 0 && !find("forgeCrashDismiss"))
        add("Choose an existing crash report explicitly", () => clickBody("feedbackChooseCrash"),
            () => !!find("feedbackSelectCrash-" + selectedReport.reportId))
        add("Attach chosen diagnostic snapshot", () => click("feedbackSelectCrash-" + selectedReport.reportId),
            () => !!attachment("forge_crash") && !feedbackService.busy)
        add("Enrich original without changing selected attachment", () => {
            const updated = JSON.parse(JSON.stringify(selectedReport))
            updated.revision = 2
            updated.collectionState = "complete"
            require(auditProbe.applyRulesCrashReportFixture(updated), "Cannot enrich original report")
            return clickBody("feedbackPreview-" + attachment("forge_crash").id)
        }, () => !!find("feedbackPreviewText"))
        add("Inspect frozen diagnostic preview as plain text", () => {
            const selected = JSON.parse(find("feedbackPreviewText").text)
            require(selected.reportId === selectedReport.reportId && selected.revision === 1,
                    "Selected diagnostic silently changed revision")
            capture("feedback-diagnostic-preview")
            click("feedbackPreviewClose")
        }, () => !find("feedbackPreviewClose"))
        if (imagePath) {
            add("Open native image picker", () => clickBody("feedbackAddImage"),
                () => waited(500) && auditProbe.fileDialogState("feedbackImageDialog").visible)
            add("Choose an explicit image file", () => {
                require(auditWindow.feedbackInteractionOpen, "Input gate dropped in image picker")
                require(auditProbe.chooseFile("feedbackImageDialog", imagePath), "Cannot choose image")
            }, () => !!attachment("screenshot") && !feedbackService.busy)
            add("Preview the encoded attachment", () => clickBody("feedbackPreview-" + attachment("screenshot").id),
                () => previewImageReady())
            add("Capture image preview", () => {
                capture("feedback-image-preview")
                click("feedbackPreviewClose")
            }, () => !find("feedbackPreviewClose"))
        }
        add("Capture Chinese composer", () => capture("feedback-chinese"))
        addPublicationSteps(true)
        add("Inspect received feedback and copy receipt", () => clickBody("feedbackCopyReceipt"),
            () => feedbackService.operationCode === "copied" && feedbackService.operationRecordId === sentId)
        add("Capture durable receipt", () => capture("feedback-received"))
        addExportSteps("received-feedback.json")
        addRemovalSteps()
        add("Open feedback history", () => click("feedbackHistoryButton"), () => !!find("feedbackHistoryCase-" + sentId))
        add("Capture local history", () => {
            capture("feedback-history")
            click("feedbackHistoryButton")
        }, () => feedbackService.draft.state === "draft" && feedbackService.draft.id !== sentId && !!find("feedbackDescription"))
        add("Create unsent draft for restart", () => {
            draftId = feedbackService.draft.id
            enter("feedbackDescription", draftDescription)
        }, () => feedbackService.draft.description === draftDescription && !feedbackService.saving)
        addTableSteps()
    }
    function finish(error) {
        if (finished) return
        finished = true
        if (error && auditProbe.capture(auditWindow, "failure")) screenshots.push("failure.png")
        const geometry = auditProbe.observe(auditWindow)
        auditProbe.record("window-geometry", geometry)
        auditProbe.record("result", {status:error ? "failed" : "passed", scenario:"feedback",
            evidence:"native-qt-input-and-owned-file-chooser", liveEngineGame:false, externalMessages:false,
            restarted:restarting, offline:offline, error:error || "",
            pendingStep:index < steps.length ? steps[index].name : "", assertions:assertions,
            requiredScreenshots:screenshots, windowMode:geometry.windowMode, width:geometry.width,
            height:geometry.height, dpr:geometry.dpr, screenGeometry:geometry.screenGeometry})
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
                        driver.require(Date.now() - driver.stepStarted < 25000, "Cannot reach " + step.name)
                        return
                    }
                    driver.acted = true
                }
                if (step.check()) {
                    driver.assertions.push({step:step.name, elapsedMs:Date.now() - driver.stepStarted})
                    driver.index++
                    driver.acted = false
                    driver.stepStarted = Date.now()
                } else driver.require(Date.now() - driver.stepStarted < 25000, "Timed out: " + step.name)
            } catch (error) { driver.finish(String(error)) }
            finally { driver.dispatching = false }
        }
    }
}
