// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

Surface {
    id: root

    required property var tableController
    property bool externalCardChoices: false
    property bool externalDamageChoices: false
    property bool showZoneActions: false
    property bool showActions: true
    property bool hideIdlePriorityStatus: false
    property real contentMargins: Theme.size(6)
    property Component contextControls: null
    readonly property bool externallyPresented:
        (externalCardChoices && ["chooseCards", "mulliganPutBack", "revealCards", "scry",
            "reorder", "chooseDamageAssignmentOrder"]
            .includes(tableController.rulesSession.promptKind))
        || (externalDamageChoices && tableController.rulesSession.promptKind === "chooseCombatDamageAssignment")
    readonly property bool expanded: showActions && (actionPicker.opened
        || (tableController.rulesSession.promptPending
            && tableController.silentAiDeckAdvisory !== true
            && !tableController.priority.isPriorityPrompt && !externallyPresented)
        || tableController.rulesSession.gameOver)
    property alias actionPicker: actionPicker

    objectName: "rulesDecisionDock"
    implicitHeight: content.implicitHeight + contentMargins * 2
    color: Theme.tableRailFill
    radius: 0
    border.width: 0
    clip: true

    onVisibleChanged: {
        if (!visible)
            actionPicker.close()
    }
    onShowActionsChanged: {
        if (!showActions)
            actionPicker.close()
    }
    Connections {
        target: root.tableController
        function onRoomConnectedChanged() {
            if (!root.tableController.roomConnected)
                actionPicker.close()
        }
    }

    ColumnLayout {
        id: content
        anchors.fill: parent
        anchors.margins: root.contentMargins
        spacing: Theme.size(8)

        Item {
            objectName: "rulesDecisionBody"
            implicitHeight: Math.max(Theme.size(150), actionPicker.opened
                ? actionPicker.implicitHeight : prompt.implicitHeight)
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumWidth: 0
            Layout.minimumHeight: 0
            visible: root.expanded

            RulesPromptPanel {
                id: prompt
                anchors.fill: parent
                enabled: root.tableController.roomConnected
                visible: !actionPicker.opened && root.expanded
                tableController: root.tableController
                externalCardChoices: root.externalCardChoices
                externalDamageChoices: root.externalDamageChoices
            }
            RulesCardActionPicker {
                id: actionPicker
                anchors.fill: parent
                tableController: root.tableController
            }
        }

        RulesZoneActions {
            id: zoneActions
            Layout.fillWidth: true
            Layout.preferredHeight: implicitHeight
            Layout.minimumHeight: implicitHeight
            visible: root.showActions && root.showZoneActions && actions.length > 0 && !actionPicker.opened
                && !root.tableController.priority.yieldMode
            tableController: root.tableController
        }

        Loader {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            Layout.preferredHeight: implicitHeight
            Layout.minimumHeight: implicitHeight
            Layout.maximumHeight: implicitHeight
            sourceComponent: root.contextControls
            visible: sourceComponent !== null
        }

        RulesActionBar {
            id: actionBar
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            Layout.preferredHeight: implicitHeight
            Layout.minimumHeight: implicitHeight
            Layout.maximumHeight: implicitHeight
            visible: root.showActions
            tableController: root.tableController
            hideIdleStatus: root.hideIdlePriorityStatus
            externallyShownActionIds: root.showZoneActions ? zoneActions.actions.map(action => action.responseId) : []
        }
    }
}
