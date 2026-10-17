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
    property bool contextControlsShown: true
    readonly property bool externallyPresented:
        (externalCardChoices && ["chooseCards", "mulliganPutBack", "revealCards", "scry",
            "reorder", "chooseDamageAssignmentOrder"]
            .includes(tableController.rulesSession.promptKind))
        || (externalDamageChoices && tableController.rulesSession.promptKind === "chooseCombatDamageAssignment")
    readonly property bool expanded: showActions && (cardActionPicker.opened
        || (tableController.rulesSession.promptPending
            && tableController.silentAiDeckAdvisory !== true
            && !tableController.priority.isPriorityPrompt && !externallyPresented)
        || tableController.rulesSession.gameOver)
    // A temporarily hidden decision returns with the next prompt or the result.
    property bool collapsed: false
    readonly property bool showsBody: expanded && !collapsed
    // Offboard targets need their card list just like an opened combat list.
    // Keep the compact reservation for decisions answered on the battlefield.
    readonly property bool listChoiceShown: showsBody && (prompt.combatListShown
        || (prompt.targetPrompt !== null && prompt.targetPrompt.hasCandidates))
    readonly property bool gameOver: tableController.rulesSession.gameOver === true
    property alias actionPicker: cardActionPicker

    objectName: "rulesDecisionDock"
    implicitHeight: content.implicitHeight + contentMargins * 2
    // Keep the actual action/zone/context controls and layout spacing, replacing
    // only the expanded body's preferred height with its safe minimum budget.
    readonly property real minimumExpandedHeight: implicitHeight + (showsBody
        ? Math.max(Theme.size(150), cardActionPicker.opened ? 0 : prompt.minimumHeight)
          - decisionBody.implicitHeight : 0)
    color: Theme.tableRailFill
    radius: 0
    border.width: 0
    clip: true

    onVisibleChanged: {
        if (!visible)
            cardActionPicker.close()
    }
    onShowActionsChanged: {
        if (!showActions)
            cardActionPicker.close()
    }
    onExpandedChanged: collapsed = false
    onGameOverChanged: collapsed = false
    Connections {
        target: root.tableController
        function onRoomConnectedChanged() {
            if (!root.tableController.roomConnected)
                cardActionPicker.close()
        }
    }
    // A republication of the same decision keeps it hidden.
    property int shownPromptId: 0
    Connections {
        target: root.tableController.rulesSession
        function onPromptChanged() {
            const id = root.tableController.rulesSession.promptId
            if (id !== root.shownPromptId) {
                root.shownPromptId = id
                root.collapsed = false
            }
        }
        ignoreUnknownSignals: true
    }

    ColumnLayout {
        id: content
        anchors.fill: parent
        anchors.margins: root.contentMargins
        spacing: Theme.size(8)

        Item {
            id: decisionBody
            objectName: "rulesDecisionBody"
            implicitHeight: Math.max(Theme.size(150), cardActionPicker.opened
                ? cardActionPicker.implicitHeight : prompt.implicitHeight)
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumWidth: 0
            Layout.minimumHeight: 0
            visible: root.showsBody

            RulesPromptPanel {
                id: prompt
                anchors.fill: parent
                enabled: root.tableController.roomConnected
                visible: !cardActionPicker.opened && root.showsBody
                tableController: root.tableController
                externalCardChoices: root.externalCardChoices
                externalDamageChoices: root.externalDamageChoices
            }
            RulesCardActionPicker {
                id: cardActionPicker
                anchors.fill: parent
                tableController: root.tableController
            }
        }

        RulesZoneActions {
            id: zoneActions
            Layout.fillWidth: true
            Layout.preferredHeight: implicitHeight
            Layout.minimumHeight: implicitHeight
            visible: root.showActions && root.showZoneActions && actions.length > 0 && !cardActionPicker.opened
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
            visible: item !== null && root.contextControlsShown
        }

        RulesActionBar {
            id: actionBar
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            Layout.preferredHeight: implicitHeight
            Layout.minimumHeight: implicitHeight
            Layout.maximumHeight: implicitHeight
            visible: root.showActions && hasContent
            tableController: root.tableController
            hideIdleStatus: root.hideIdlePriorityStatus
            externallyShownActionIds: root.showZoneActions ? zoneActions.actions.map(action => action.responseId) : []
        }
    }
}
