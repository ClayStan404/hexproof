// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

pragma Singleton

import QtQuick

QtObject {
    property string currentId: "default"
    readonly property var entries: [
        {key: "default", name: qsTr("Default background"), source: ""},
        {key: "dusk", name: qsTr("Dusk ruins"),
            source: Qt.resolvedUrl("../assets/playmat-dusk.png")},
        {key: "forest", name: qsTr("Emerald sanctuary"),
            source: Qt.resolvedUrl("../assets/backgrounds/forest.png")},
        {key: "astral", name: qsTr("Arcane stars"),
            source: Qt.resolvedUrl("../assets/backgrounds/astral.png")},
        {key: "volcanic", name: qsTr("Obsidian wastes"),
            source: Qt.resolvedUrl("../assets/backgrounds/volcanic.png")},
        {key: "frost", name: qsTr("Silent frostlands"),
            source: Qt.resolvedUrl("../assets/backgrounds/frost.png")},
        {key: "ink", name: qsTr("Ink mountains"),
            source: Qt.resolvedUrl("../assets/backgrounds/ink.png")},
        {key: "woven", name: qsTr("Woven sand"),
            source: Qt.resolvedUrl("../assets/backgrounds/woven.png")}
    ]
    readonly property url source: entry(currentId).source
    readonly property bool hasImage: String(source).length > 0

    function entry(key) {
        return entries.find(candidate => candidate.key === key) || entries[0]
    }
}
