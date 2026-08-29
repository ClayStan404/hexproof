// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick

Shortcut {
    id: root

    required property string actionId
    property bool available: true

    enabled: root.available && !preferences.shortcutCaptureActive
    sequences: {
        // Re-evaluate the binding even when the resulting sequence list is unchanged.
        const revision = preferences.shortcutRevision
        return preferences.shortcutSequences(root.actionId)
    }
}
