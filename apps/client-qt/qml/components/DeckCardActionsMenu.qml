// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic

Menu {
    id: root
    property bool printingEnabled: false
    property bool customArtEnabled: false
    signal printingRequested()
    signal customArtRequested()

    ConditionalMenuItem {
        objectName: "deckCardPrintingAction"
        visible: root.printingEnabled
        text: qsTr("Select printing…")
        onTriggered: root.printingRequested()
    }
    ConditionalMenuItem {
        objectName: "deckCardCustomArtAction"
        visible: root.customArtEnabled
        text: qsTr("Custom art…")
        onTriggered: root.customArtRequested()
    }
}
