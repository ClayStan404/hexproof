// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

pragma ComponentBehavior: Bound

import QtQuick

Surface {
    id: root

    required property var tableController
    property bool inspectionOpened: false
    property bool verticalInspection: false
    property bool externalHoverPreview: false
    readonly property bool externalPreviewActive: externalHoverPreview && inspector.previewCardId.length > 0
    readonly property bool opened: inspectionOpened || tableController.showGameLogRail
    property alias inspector: inspector
    property alias logRail: gameLogRail

    objectName: "rulesInspectionHost"
    color: Theme.tableRailFill
    radius: 0
    border.width: 0
    clip: true

    Connections {
        target: root.tableController
        function onRoomConnectedChanged() {
            if (!root.tableController.roomConnected)
                inspector.clear()
        }
        function onSideboardingChanged() {
            if (root.tableController.sideboarding)
                inspector.clear()
        }
    }

    RulesCardInspector {
        id: inspector
        anchors.fill: parent
        anchors.margins: Theme.size(6)
        rulesSession: root.tableController.rulesSession
        cardCatalogModel: root.tableController.cardCatalogModel
        cardBackSource: root.tableController.cardBackSource
        showEmptyCloseButton: root.inspectionOpened
        preferVertical: root.verticalInspection
        visible: !root.externalPreviewActive && (hasCard || !root.tableController.showGameLogRail)
        onHasCardChanged: {
            if (hasCard)
                root.inspectionOpened = true
        }
        onCleared: root.inspectionOpened = false
    }

    TableGameLogRail {
        id: gameLogRail
        anchors.fill: parent
        anchors.margins: Theme.size(6)
        tableController: root.tableController
        visible: root.tableController.showGameLogRail && (!inspector.hasCard || root.externalPreviewActive)
    }
}
