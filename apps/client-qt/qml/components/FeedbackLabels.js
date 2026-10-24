// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors
.pragma library

function state(value) {
    switch (value) {
    case "queued": return qsTranslate("Feedback", "Queued")
    case "sending": return qsTranslate("Feedback", "Sending…")
    case "unconfirmed": return qsTranslate("Feedback", "Receipt unconfirmed")
    case "accepted": return qsTranslate("Feedback", "Accepted")
    case "received": return qsTranslate("Feedback", "Received")
    case "needs_attention": return qsTranslate("Feedback", "Needs attention")
    default: return qsTranslate("Feedback", "Draft")
    }
}

function category(value) {
    switch (value) {
    case "suggestion": return qsTranslate("Feedback", "Suggestion")
    case "other": return qsTranslate("Feedback", "Other")
    default: return qsTranslate("Feedback", "Problem")
    }
}

function recordState(record) {
    if (record.isPublic !== true) return state(record.state)
    switch (record.removalState) {
    case "requested": return qsTranslate("Feedback", "Removal request queued")
    case "pending": return qsTranslate("Feedback", "Removal pending")
    case "stalled": return qsTranslate("Feedback", "Removal delayed")
    case "removed": return qsTranslate("Feedback", "Removed from project-controlled locations")
    }
    if (record.closureRequestState === "requested") return qsTranslate("Feedback", "Close request queued")
    if (record.closureRequestState === "stalled") return qsTranslate("Feedback", "Close request delayed")
    if (record.caseState === "closed") {
        if (record.closurePublicationState === "pending") return qsTranslate("Feedback", "Closed · public sync pending")
        if (record.closurePublicationState === "stalled") return qsTranslate("Feedback", "Closed · public sync delayed")
        return qsTranslate("Feedback", "Closed")
    }
    switch (record.publicationState) {
    case "pending": return qsTranslate("Feedback", "Accepted · publication pending")
    case "stalled": return qsTranslate("Feedback", "Accepted · publication delayed")
    case "partial": return qsTranslate("Feedback", "Partially published")
    case "published": return qsTranslate("Feedback", "Published")
    case "rejected": return qsTranslate("Feedback", "Publication rejected")
    }
    return (record.state === "received" || record.state === "accepted") ? qsTranslate("Feedback", "Accepted") : state(record.state)
}

function publicationDescription(value) {
    switch (value) {
    case "pending": return qsTranslate("Feedback", "Saved by the service. Publication is pending; do not submit another copy.")
    case "stalled": return qsTranslate("Feedback", "Publication is delayed. The service retains this submission for bounded recovery; do not submit another copy.")
    case "partial": return qsTranslate("Feedback", "Some approved content is public, but publication is incomplete. Assessment waits for all attachments and text.")
    case "published": return qsTranslate("Feedback", "The complete approved content is published. This does not confirm a bug, accepted request or released fix.")
    case "rejected": return qsTranslate("Feedback", "The service rejected publication. Review the reason before preparing a corrected draft.")
    default: return ""
    }
}

function removalDescription(value) {
    switch (value) {
    case "requested": return qsTranslate("Feedback", "Your removal request is saved on this device and will be delivered. Keep this record to check progress.")
    case "pending": return qsTranslate("Feedback", "The service received your removal request. External writes are still being settled; removal is not yet confirmed.")
    case "stalled": return qsTranslate("Feedback", "Removal is delayed and not yet confirmed. Keep this record and refresh its status later.")
    case "removed": return qsTranslate("Feedback", "Removal from project-controlled locations is confirmed. Third-party copies, GitHub history and notifications may remain.")
    default: return ""
    }
}

function closureDescription(record) {
    if (record.closureRequestState === "requested") return qsTranslate("Feedback", "Your close request is saved on this device. Follow-up will stop after the service receives it; history and attachments will remain.")
    if (record.closureRequestState === "stalled") return qsTranslate("Feedback", "Closing could not be confirmed. Retry closing or refresh the receipt; history and attachments remain.")
    if (record.caseState !== "closed") return ""
    if (record.closurePublicationState === "pending") return qsTranslate("Feedback", "Feedback is closed. Public issue closure is pending. History and attachments remain; existing tasks may still be stopping.")
    if (record.closurePublicationState === "stalled") return qsTranslate("Feedback", "Feedback is closed. Public issue closure is delayed. History and attachments remain; existing tasks may still be stopping.")
    return qsTranslate("Feedback", "The service accepted closure and stopped new replies. Existing tasks may still be stopping. History and attachments remain.")
}

function attachment(value) {
    if (value === "forge_crash" || value === "crash")
        return qsTranslate("Feedback", "Forge crash report")
    if (value === "hosting" || value === "hosting_diagnostics")
        return qsTranslate("Feedback", "Hosting diagnostics")
    return qsTranslate("Feedback", "Screenshot")
}

function workState(value) {
    switch (value) {
    case "assessing": return qsTranslate("Feedback", "Assessing the report")
    case "needs-information": return qsTranslate("Feedback", "Waiting for your information")
    case "ready":
    case "implementing":
    case "verifying":
    case "verified-awaiting-review":
    case "reviewing":
    case "verifying-integration":
    case "merge-ready":
    case "merging": return qsTranslate("Feedback", "The AI team is working on this")
    case "merged-awaiting-release":
    case "source-published-awaiting-release": return qsTranslate("Feedback", "Awaiting release")
    case "released": return qsTranslate("Feedback", "Released")
    case "duplicate": return qsTranslate("Feedback", "Related to an existing report")
    case "declined": return qsTranslate("Feedback", "Not adopted · see the assessment")
    case "deferred": return qsTranslate("Feedback", "Deferred · see the assessment")
    case "blocked": return qsTranslate("Feedback", "Assessment blocked")
    case "removed": return qsTranslate("Feedback", "Removal requested")
    default: return qsTranslate("Feedback", "Awaiting assessment")
    }
}

function outcome(value) {
    if (!value) return ""
    switch (value.kind) {
    case "duplicate": return qsTranslate("Feedback", "Related public report #%1").arg(value.issueNumber)
    case "source": return qsTranslate("Feedback", "Source change published · awaiting release")
    case "release": return qsTranslate("Feedback", "Released in version %1").arg(value.version)
    default: return ""
    }
}

function question(code, fallback) {
    switch (code) {
    case "reproduction_steps": return qsTranslate("Feedback", "What steps reproduce the problem? Include only information you are willing to publish.")
    case "expected_actual": return qsTranslate("Feedback", "What did you expect, and what happened instead?")
    case "affected_version": return qsTranslate("Feedback", "Which Hexproof version shows the problem?")
    case "platform": return qsTranslate("Feedback", "Which operating system and version are you using?")
    case "minimal_public_example": return qsTranslate("Feedback", "Can you provide a small public example without secrets, hidden cards or other players' data?")
    case "user_goal": return qsTranslate("Feedback", "What are you trying to achieve, and what currently prevents it?")
    default: return String(fallback || "")
    }
}

function error(code) {
    switch (code) {
    case "": return ""
    case "storage_unavailable": return qsTranslate("Feedback", "Could not save locally. Check storage before sending.")
    case "storage_full": return qsTranslate("Feedback", "Local feedback storage is full. Export or delete an older record.")
    case "configuration_invalid": return qsTranslate("Feedback", "Online submission is unavailable because the feedback configuration is invalid. You can save or export a draft.")
    case "disabled": return qsTranslate("Feedback", "Online submission is not enabled in this build. You can save or export a draft.")
    case "invalid_description": return qsTranslate("Feedback", "Enter a description of up to 8 KiB.")
    case "invalid_email": return qsTranslate("Feedback", "Enter one valid contact email, or leave it empty.")
    case "preview_required": return qsTranslate("Feedback", "Review the public preview and confirm publication first.")
    case "preview_changed": return qsTranslate("Feedback", "The draft or publication notice changed. Return to the draft and review a new preview.")
    case "legacy_private": return qsTranslate("Feedback", "This earlier private record cannot be published. Create a new public draft and review it first.")
    case "public_consent_required": return qsTranslate("Feedback", "Review the public preview and confirm publication first.")
    case "content_rejected": return qsTranslate("Feedback", "Publication was rejected. Remove sensitive or unsupported content before creating a new submission.")
    case "removal_requested": return qsTranslate("Feedback", "Removal was requested. This submission will not be sent again.")
    case "invalid_attachment":
    case "unsupported_content": return qsTranslate("Feedback", "This attachment or report format is not supported.")
    case "attachment_limit": return qsTranslate("Feedback", "Attach up to two images, one crash report and one hosting report.")
    case "image_too_large": return qsTranslate("Feedback", "Choose a PNG or JPEG image up to 32 MiB, 8192 pixels per side and 16 megapixels.")
    case "parent_unavailable":
    case "record_unavailable": return qsTranslate("Feedback", "This record is no longer available.")
    case "not_editable": return qsTranslate("Feedback", "Create an editable copy to change this submission.")
    case "endpoint_changed":
    case "endpoint_untrusted": return qsTranslate("Feedback", "The support destination changed. Review an editable copy before sending again.")
    case "stopped": return qsTranslate("Feedback", "Sending stopped. An earlier attempt may already have been received.")
    case "retry_exhausted": return qsTranslate("Feedback", "Automatic retries ended. Check the receipt before sending another copy.")
    case "network_error": return qsTranslate("Feedback", "Support could not be reached. Your feedback remains saved locally.")
    case "content_conflict": return qsTranslate("Feedback", "The receiver already has different content for this submission. Keep this record for reference.")
    case "content_unavailable": return qsTranslate("Feedback", "The receiver no longer retains this submission. It will not be sent again.")
    case "rate_limited": return qsTranslate("Feedback", "Too many requests. Please try again later.")
    case "response_invalid": return qsTranslate("Feedback", "The support response could not be verified. Keep this record and check its receipt later.")
    case "export_failed": return qsTranslate("Feedback", "Could not export. Choose another location.")
    case "copy_failed": return qsTranslate("Feedback", "Could not copy the receipt.")
    case "busy": return qsTranslate("Feedback", "Please wait for the current operation.")
    case "thread_unsupported": return qsTranslate("Feedback", "This service does not yet support conversations. Your feedback receipt remains available.")
    case "question_unavailable":
    case "thread_changed": return qsTranslate("Feedback", "The conversation changed while refreshing. Refresh again to load its current state.")
    default: return qsTranslate("Feedback", "The operation did not finish. Please try again.")
    }
}

function date(value) {
    const parsed = new Date(value || "")
    return isNaN(parsed.getTime()) ? "" : parsed.toLocaleString(Qt.locale(), "yyyy-MM-dd hh:mm")
}
