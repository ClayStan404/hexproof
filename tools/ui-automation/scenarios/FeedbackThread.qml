// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors
import QtQuick

// Real Qt, receiver and outbox; fake GitHub and deterministic trusted assessment
// projections. This fixture does not invoke AI or write to an external service.
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
    function publish(reply) {
        add("Preview " + (reply ? "reply" : "original") + " without authorizing upload", () => click("feedbackSend"),
            () => !!find("feedbackPublicConsent"))
        add("Verify independent unselected public consent", () => {
            require(!find("feedbackPublicConsent").checked && !find("feedbackPublish")
                    && !feedbackService.draft.uploadAuthorized, "Consent was reused")
            require(find("feedbackPublicDescription").text === (reply ? answer : original), "Preview changed the text")
            capture(reply ? "reply-public-preview" : "original-public-preview")
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
        publish(false)
        add("Read verified clarification inside the client", () => { lastRefresh = 0 },
            () => refreshUntil(() => feedbackService.thread.caseId === caseId && !!feedbackService.thread.question))
        add("Inspect localized public question", () => {
            if (!bodyReveal("feedbackCurrentQuestion")) return false
            require(find("feedbackCurrentQuestion").text.indexOf("公开") >= 0, "Clarification was not localized")
            capture("public-question-chinese")
        })
        add("Inspect Chinese clarification and create reply", () => {
            questionId = feedbackService.thread.question.id
            if (!bodyClick("feedbackAnswerQuestion")) return false
        }, () => feedbackService.draft.isReply && !!find("feedbackDescription"))
        add("Inspect bound reply draft", () => {
            require(feedbackService.draft.parentSubmissionId === caseId && feedbackService.draft.questionId === questionId,
                "Reply lost its case or question identity")
            require(!feedbackService.draft.uploadAuthorized, "Reply creation authorized transmission")
            replyId = feedbackService.draft.id
            capture("question-reply-draft")
            enter("feedbackDescription", answer)
        }, () => feedbackService.draft.description === answer && !feedbackService.saving)
        publish(true)
        add("Return to parent feedback after reply receipt", () => bodyClick("feedbackBackToCase"),
            () => feedbackService.draft.id === caseId && !feedbackService.busy && !feedbackService.saving)
        add("Read published reply and confirmed assessment in client", () => { lastRefresh = 0 },
            () => refreshUntil(() => feedbackService.thread.workState === "ready"
                && feedbackService.thread.items.some(item => item.submissionId === replyId && item.publicationState === "published")))
        add("Inspect complete conversation without GitHub access", () => {
            const composer = find("feedbackComposer")
            if (!find("feedbackAssessmentSummary")) {
                require(auditProbe.wheel(composer, -400), "Cannot reveal assessment")
                return false
            }
            capture("assessment-and-public-reply")
        })
        add("Inspect exact reply text in conversation", () => {
            const name = "feedbackThreadEntry-" + replyId
            if (!bodyReveal(name)) return false
            require(find(name).text === answer, "Conversation changed the public reply")
            capture("public-reply-in-conversation")
        })
        add("Close follow-up independently of content removal", () => bodyClick("feedbackCloseCase"),
            () => !!find("confirmButton"))
        add("Inspect closure confirmation before sending", () => {
            require(feedbackService.draft.caseState === "open" && feedbackService.draft.removalState === "none",
                "Opening close confirmation mutated the case")
            capture("close-feedback-confirmation")
            click("confirmButton")
        }, () => feedbackService.draft.caseState === "closed")
        add("Wait for independently confirmed public issue closure", () => { lastRefresh = 0 },
            () => refreshUntil(() => feedbackService.draft.closurePublicationState === "closed"))
        add("Verify closed history remains readable without new replies", () => { lastRefresh = 0 },
            () => refreshUntil(() => feedbackService.thread.caseState === "closed"
                && feedbackService.thread.items.some(item => item.submissionId === replyId
                    && item.description === answer)))
        add("Inspect closure separately from deletion", () => {
            require(feedbackService.draft.removalState === "none" && !feedbackService.thread.replyAllowed
                && !find("feedbackAddReply") && !find("feedbackAnswerQuestion"),
                "Closing deleted the case or left follow-up enabled")
            capture("closed-feedback-retained-history")
        })
        add("Request removal of complete case", () => bodyClick("feedbackRequestRemoval"), () => !!find("confirmButton"))
        add("Confirm public removal", () => click("confirmButton"), () => feedbackService.draft.removalState !== "none")
        add("Verify removal of original, replies and projections", () => { lastRefresh = 0 },
            () => refreshUntil(() => feedbackService.draft.removalState === "removed"))
        add("Inspect retained receipt and fenced reply action", () => {
            require(!find("feedbackAddReply") && !find("feedbackAnswerQuestion"), "Removed case still accepts replies")
            capture("thread-removed")
            click("feedbackClose")
        }, () => !auditWindow.feedbackInteractionOpen)
    }
    function finish(error) {
        if (finished) return
        finished = true
        if (error && auditProbe.capture(auditWindow, "failure")) screenshots.push("failure.png")
        const geometry = auditProbe.observe(auditWindow)
        auditProbe.record("window-geometry", geometry)
        auditProbe.record("result", {status:error ? "failed" : "passed", scenario:"feedback-thread",
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
