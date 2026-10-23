// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors
import QtQuick

// Real Qt, receiver and native interface; fake GitHub and deterministic AI
// updates. This fixture does not invoke AI or write to an external service.
Item {
    id: driver
    property var steps: []
    property var assertions: []
    property var screenshots: []
    property int index: 0
    property bool acted: false
    property bool dispatching: false
    property bool finished: false
    property double stepStarted: Date.now()
    property double lastRefresh: 0
    property double lastScroll: 0
    property string caseId: ""
    property string replyId: ""
    property string questionId: ""
    property string followupId: ""
    readonly property string followup: "After updating to 3.0.1, the setting still resets when I switch game modes."
    readonly property string original: "Native thread audit: saved room setting is lost after reopening."
    readonly property string answer: "Open room settings, change the value, close and reopen. Expected: the saved value remains."

    function require(value, message) {
        if (!value) throw new Error(message + (auditProbe.lastError ? "; " + auditProbe.lastError : ""))
    }
    function find(name) { return auditProbe.find(auditWindow, name, ({})) }
    function click(name) { require(auditProbe.click(find(name)), "Cannot click " + name) }
    function enter(name, text) {
        click(name)
        require(auditProbe.key(Qt.Key_A, Qt.ControlModifier) && auditProbe.text(text), "Cannot enter " + name)
    }
    function bodyClick(name) {
        const composer = find("feedbackComposer")
        if (Date.now() - lastScroll < 400 || (composer && composer.contentItem.moving)) return false
        if (find(name)) { click(name); return true }
        require(auditProbe.wheel(composer, -480), "Cannot scroll to " + name)
        lastScroll = Date.now()
        return false
    }
    function bodyReveal(name) {
        if (Date.now() - lastScroll < 400) return false
        if (find(name)) return true
        require(auditProbe.wheel(find("feedbackComposer"), -400), "Cannot reveal " + name)
        lastScroll = Date.now()
        return false
    }
    function capture(name) {
        require(auditProbe.capture(auditWindow, name), "Cannot capture " + name)
        screenshots.push(name + ".png")
    }
    function add(name, action, check) { steps.push({name:name, action:action, check:check || (() => true)}) }
    function refreshUntil(check) {
        if (check()) return true
        if (Date.now() - lastRefresh > 6000 && !feedbackService.busy && !feedbackService.saving) {
            click("feedbackCheckReceipt")
            lastRefresh = Date.now()
        }
        return false
    }
    function publish(reply, expected, label) {
        add("Preview " + (reply ? "reply" : "original") + " without authorizing upload", () => click("feedbackSend"),
            () => !!find("feedbackPublicConsent"))
        add("Verify independent unselected public consent", () => {
            require(!find("feedbackPublicConsent").checked && !find("feedbackPublish")
                    && !feedbackService.draft.uploadAuthorized, "Consent was reused")
            require(find("feedbackPublicDescription").text === expected, "Preview changed the text")
            capture(label + "-public-preview")
            click("feedbackPublicConsent")
        }, () => !!find("feedbackPublish"))
        add("Confirm publication", () => click("feedbackPublish"), () => feedbackService.draft.state === "accepted")
        add("Wait for settled publication UI", () => {}, () => !feedbackService.busy && !feedbackService.saving
            && !find("feedbackPublicConsent") && Date.now() - stepStarted > 350)
    }
    function plan() {
        add("Dismiss isolated first-launch notices", () => {
            for (const name of ["dismissSponsorsButton", "laterCardArtRepairButton"]) {
                if (find(name)) { click(name); return false }
            }
            return !!find("mainMenuFeedbackButton") && !feedbackService.busy
        })
        add("Open feedback on actual maximized display", () => {
            require(auditProbe.observe(auditWindow).windowMode === "maximized", "Expected maximized window")
            require(feedbackService.enabled && !ws.connected, "Expected isolated local feedback")
            preferences.uiLanguage = "zh_CN"
            click("mainMenuFeedbackButton")
        }, () => !!find("feedbackDescription"))
        add("Enter original public report", () => enter("feedbackDescription", original),
            () => feedbackService.draft.description === original && !feedbackService.saving)
        add("Record original case identity", () => { caseId = feedbackService.draft.id })
        publish(false, original, "original")
        add("Read a specific AI question inside the client", () => { lastRefresh = 0 },
            () => refreshUntil(() => feedbackService.thread.caseId === caseId && !!feedbackService.thread.question))
        add("Inspect exact Chinese question instead of a generic template", () => {
            if (!bodyReveal("feedbackCurrentQuestion")) return false
            const question = find("feedbackCurrentQuestion").text
            require(question.indexOf("手动模式还是 Forge 规则模式") >= 0
                && question.indexOf("卡牌名称") >= 0, "Specific question was replaced")
            capture("specific-question-chinese")
        })
        add("Create a reply to the current question", () => {
            questionId = feedbackService.thread.question.id
            return bodyClick("feedbackAnswerQuestion")
        }, () => feedbackService.draft.isReply && !!find("feedbackDescription"))
        add("Save an unsubmitted reply draft", () => {
            require(feedbackService.draft.parentSubmissionId === caseId && feedbackService.draft.questionId === questionId,
                "Reply lost its case or question identity")
            require(!feedbackService.draft.uploadAuthorized, "Reply creation authorized transmission")
            replyId = feedbackService.draft.id
            enter("feedbackDescription", answer)
        }, () => feedbackService.draft.description === answer && !feedbackService.saving)
        add("Return to the case before submitting the reply", () => bodyClick("feedbackBackToCase"),
            () => feedbackService.draft.id === caseId && !feedbackService.busy && !feedbackService.saving)
        add("Find and resume the local reply within its case", () => {
            require(feedbackService.cases.length === 1, "Reply became an unrelated case")
            require(feedbackService.thread.localReplies.some(item => item.id === replyId), "Draft reply became inaccessible")
            if (!bodyReveal("feedbackLocalReply-" + replyId)) return false
            capture("local-reply-in-case")
            click("feedbackLocalReply-" + replyId)
        }, () => feedbackService.draft.id === replyId && feedbackService.draft.description === answer
            && !feedbackService.busy && !feedbackService.saving)
        publish(true, answer, "answer")
        add("Return after the first reply receipt", () => bodyClick("feedbackBackToCase"),
            () => feedbackService.draft.id === caseId && !feedbackService.busy && !feedbackService.saving)
        add("Read the verified release and source delivery history", () => { lastRefresh = 0 },
            () => refreshUntil(() => feedbackService.thread.workState === "released"
                && feedbackService.thread.outcome && feedbackService.thread.outcome.version === "3.0.1"
                && feedbackService.thread.deliveryHistory.length === 2))
        add("Inspect the actual version in the conversation", () => {
            if (!bodyReveal("feedbackCurrentOutcome")) return false
            require(find("feedbackCurrentOutcome").text.indexOf("3.0.1") >= 0, "Release version is missing")
            capture("verified-release-version")
        })
        add("Start a follow-up after release", () => bodyClick("feedbackAddReply"),
            () => feedbackService.draft.isReply && feedbackService.draft.id !== replyId && !!find("feedbackDescription"))
        add("Describe a remaining problem", () => {
            followupId = feedbackService.draft.id
            enter("feedbackDescription", followup)
        }, () => feedbackService.draft.description === followup && !feedbackService.saving)
        publish(true, followup, "followup")
        add("Return after the second reply receipt", () => bodyClick("feedbackBackToCase"),
            () => feedbackService.draft.id === caseId && !feedbackService.busy && !feedbackService.saving)
        add("New information invalidates current assessment, preserving deliveries", () => { lastRefresh = 0 },
            () => refreshUntil(() => feedbackService.thread.workState === "assessing"
                && !feedbackService.thread.outcome && feedbackService.thread.deliveryHistory.length === 2
                && feedbackService.thread.items.some(item => item.submissionId === followupId)))
        add("Inspect retained release facts during reassessment", () => {
            const release = feedbackService.thread.deliveryHistory.find(item => item.outcome.kind === "release")
            require(release && release.outcome.version === "3.0.1", "Earlier release fact disappeared")
            if (!bodyReveal("feedbackDelivery-" + release.projectionId)) return false
            require(!find("feedbackCurrentOutcome"), "Stale release still shown as current assessment")
            capture("reassessment-with-delivery-history")
            click("feedbackHistoryButton")
        }, () => !!find("feedbackHistoryCase-" + caseId))
        add("Inspect one history entry for the complete conversation", () => {
            require(feedbackService.cases.length === 1 && feedbackService.records.length === 3,
                "History did not group the original and replies")
            capture("grouped-case-history")
            click("feedbackHistoryCase-" + caseId)
        }, () => feedbackService.draft.id === caseId && !!find("feedbackComposer"))
        add("Close follow-up independently of content removal", () => bodyClick("feedbackCloseCase"),
            () => !!find("confirmButton"))
        add("Confirm closure", () => {
            require(feedbackService.draft.caseState === "open" && feedbackService.draft.removalState === "none",
                "Opening confirmation mutated the case")
            click("confirmButton")
        }, () => feedbackService.draft.caseState === "closed")
        add("Wait for independently confirmed public issue closure", () => { lastRefresh = 0 },
            () => refreshUntil(() => feedbackService.draft.closurePublicationState === "closed"
                && feedbackService.thread.caseState === "closed"))
        add("Verify closed conversation retains delivery history", () => {
            require(feedbackService.draft.removalState === "none" && !feedbackService.thread.replyAllowed
                && feedbackService.thread.deliveryHistory.length === 2
                && !find("feedbackAddReply") && !find("feedbackAnswerQuestion"), "Closure lost history or left replies enabled")
            capture("closed-conversation")
        })
        add("Request content removal separately", () => bodyClick("feedbackRequestRemoval"), () => !!find("confirmButton"))
        add("Confirm public removal", () => click("confirmButton"), () => feedbackService.draft.removalState !== "none")
        add("Verify removal of original, replies and official updates", () => { lastRefresh = 0 },
            () => refreshUntil(() => feedbackService.draft.removalState === "removed"))
        add("Inspect retained receipt without removed conversation", () => {
            require(!find("feedbackAddReply") && !find("feedbackAnswerQuestion")
                && !(feedbackService.thread.deliveryHistory || []).length, "Removed content remains visible")
            capture("conversation-removed")
            click("feedbackClose")
        }, () => !auditWindow.feedbackInteractionOpen)
    }
    function finish(error) {
        if (finished) return
        finished = true
        if (error && auditProbe.capture(auditWindow, "failure")) screenshots.push("failure.png")
        const geometry = auditProbe.observe(auditWindow)
        auditProbe.record("window-geometry", geometry)
        auditProbe.record("result", {status:error ? "failed" : "passed", scenario:"feedback-ai-conversation",
            evidence:"native-qt-real-receiver-fake-github", simulatedCoordinator:true, externalMessages:false,
            error:error || "", pendingStep:index < steps.length ? steps[index].name : "", assertions:assertions,
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
                        driver.require(Date.now() - driver.stepStarted < 30000, "Cannot reach " + step.name)
                        return
                    }
                    driver.acted = true
                }
                if (step.check()) {
                    driver.assertions.push({step:step.name, elapsedMs:Date.now() - driver.stepStarted})
                    driver.index++
                    driver.acted = false
                    driver.stepStarted = Date.now()
                } else driver.require(Date.now() - driver.stepStarted < 30000, "Timed out: " + step.name)
            } catch (error) { driver.finish(String(error)) }
            finally { driver.dispatching = false }
        }
    }
}
