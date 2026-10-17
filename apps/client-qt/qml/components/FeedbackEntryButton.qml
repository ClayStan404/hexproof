// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors
import QtQuick
import QtQuick.Controls.Basic

AppButton {
    id: root
    objectName: "feedbackEntryButton"
    property var feedbackContext: ({})
    readonly property var appWindow: ApplicationWindow.window
    visible: appWindow && typeof appWindow.openFeedback === "function"
    compact: true
    variant: "ghost"
    text: qsTranslate("Feedback", "Feedback")
    onClicked: root.appWindow.openFeedback(root.feedbackContext)
}
