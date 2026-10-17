// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors
.pragma library

function state(value) {
    switch (value) {
    case "queued": return qsTranslate("Feedback", "Queued")
    case "sending": return qsTranslate("Feedback", "Sending…")
    case "unconfirmed": return qsTranslate("Feedback", "Receipt unconfirmed")
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

function attachment(value) {
    if (value === "forge_crash" || value === "crash")
        return qsTranslate("Feedback", "Forge crash report")
    if (value === "hosting" || value === "hosting_diagnostics")
        return qsTranslate("Feedback", "Hosting diagnostics")
    return qsTranslate("Feedback", "Screenshot")
}

function error(code) {
    switch (code) {
    case "": return ""
    case "storage_unavailable": return qsTranslate("Feedback", "Could not save locally. Check storage before sending.")
    case "storage_full": return qsTranslate("Feedback", "Local feedback storage is full. Export or delete an older record.")
    case "configuration_invalid":
    case "disabled": return qsTranslate("Feedback", "Online feedback is unavailable. You can keep or export a draft.")
    case "invalid_description": return qsTranslate("Feedback", "Enter a description of up to 8 KiB.")
    case "invalid_email": return qsTranslate("Feedback", "Enter one valid contact email, or leave it empty.")
    case "invalid_attachment":
    case "unsupported_content": return qsTranslate("Feedback", "This attachment or report format is not supported.")
    case "attachment_limit": return qsTranslate("Feedback", "Attach up to two images, one crash report and one hosting report.")
    case "image_too_large": return qsTranslate("Feedback", "Choose a smaller PNG or JPEG image (up to 2 MiB and 16 megapixels).")
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
    default: return qsTranslate("Feedback", "The operation did not finish. Please try again.")
    }
}

function date(value) {
    const parsed = new Date(value || "")
    return isNaN(parsed.getTime()) ? "" : parsed.toLocaleString(Qt.locale(), "yyyy-MM-dd hh:mm")
}
