// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick

SegmentedControl {
    id: root
    objectName: "rulesPriorityMode"
    required property var settings
    signal modeSelected(bool fullControl)
    options: [qsTr("Smart priority"), qsTr("Full control")]
    currentIndex: settings.forgeFullControl ? 1 : 0
    onActivated: index => {
        settings.forgeFullControl = index === 1
        if (settings.forgeFullControl === (index === 1))
            modeSelected(index === 1)
        currentIndex = Qt.binding(function() { return root.settings.forgeFullControl ? 1 : 0 })
    }
}
