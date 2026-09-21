// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

Item {
    id: root
    required property var tableController
    property var externallyShownActionIds: []
    property bool hideIdleStatus: false
    readonly property var priority: tableController.priority
    readonly property var session: tableController.rulesSession
    readonly property bool informativeStatus: !tableController.roomConnected
        || session.gameOver
        || priority.yieldMode.length > 0
        || priority.fullControl
        || (priority.stopped && priority.isPriorityPrompt)
        || tableController.rulesResponsePending
        || (priority.isPriorityPrompt && priority.automaticallyPassing)
    readonly property var fallbackActions: priority.yieldMode ? [] : priority.options.filter(option =>
        !option.responseId.startsWith("$") && !externallyShownActionIds.includes(option.responseId)
        && !tableController.interaction.actionOnTable(
            option.cardId || "", option.kind || ""))

    objectName: "rulesActionBar"
    implicitHeight: content.implicitHeight

    function statusText() {
        if (!tableController.roomConnected)
            return qsTr("Disconnected")
        if (session.gameOver)
            return qsTr("Game finished")
        if (priority.yieldMode === "turn")
            return qsTr("Passing for the rest of this turn")
        if (priority.yieldMode === "response")
            return qsTr("Passing until a response")
        if (priority.yieldMode === "stack")
            return qsTr("Resolving the current stack")
        if (priority.fullControl)
            return qsTr("Full control · every priority window pauses")
        if (priority.stopped && priority.isPriorityPrompt)
            return qsTr("Stopped at %1").arg(tableController.stepLabel(session.step))
        if (tableController.rulesResponsePending)
            return qsTr("Waiting for the game")
        if (priority.isPriorityPrompt)
            return priority.automaticallyPassing ? qsTr("Passing priority")
                : qsTr("Your action")
        return session.promptPending ? tableController.promptTitle(session.promptKind, session.promptTitle)
                                     : qsTr("Waiting for another player")
    }

    ColumnLayout {
        id: content
        width: root.width
        spacing: Theme.size(8)

        Text {
            objectName: "rulesPriorityStatus"
            Layout.fillWidth: true
            visible: !root.hideIdleStatus || root.informativeStatus
            textFormat: Text.PlainText
            text: root.statusText()
            color: root.priority.fullControl || root.priority.stopped ? Theme.accent : Theme.text
            font.pixelSize: Theme.fontSize(12)
            font.weight: Font.DemiBold
            wrapMode: Text.WordWrap
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            spacing: Theme.size(10)

            AppButton {
                id: cancelButton
                objectName: "rulesCancelYield"
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                visible: root.priority.yieldMode.length > 0
                compact: true
                text: qsTr("Cancel passing")
                onClicked: root.priority.cancelYield()
            }

            AppButton {
                id: yieldButton
                objectName: "rulesYieldMenuButton"
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                visible: !root.priority.yieldMode
                enabled: root.priority.canStartYield
                compact: true
                text: qsTr("Pass")
                onClicked: yieldMenu.open()

                AppMenu {
                    id: yieldMenu
                    y: -height
                    width: Theme.size(290)
                    onAboutToShow: root.priority.passMenuOpen = true
                    onClosed: root.priority.passMenuOpen = false
                    function choose(mode) {
                        root.priority.passMenuOpen = false
                        root.priority.beginYield(mode)
                    }
                    AppMenuItem {
                        objectName: "rulesYieldUntilResponse"
                        text: qsTr("Until a response or turn ends")
                        onTriggered: yieldMenu.choose("response")
                    }
                    AppMenuItem {
                        objectName: "rulesYieldTurn"
                        text: qsTr("Rest of this turn")
                        onTriggered: yieldMenu.choose("turn")
                    }
                    AppMenuItem {
                        objectName: "rulesYieldStack"
                        text: qsTr("Current stack")
                        enabled: root.priority.stackIds.length > 0
                        onTriggered: yieldMenu.choose("stack")
                    }
                }
            }

            AppButton {
                id: passOnceButton
                objectName: "rulesPromptOption-$pass"
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                visible: root.priority.isPriorityPrompt && !root.priority.yieldMode
                enabled: root.priority.canPass
                compact: true
                variant: "primary"
                text: root.priority.stackIds.length > 0 ? qsTr("Resolve") : qsTr("Next")
                onClicked: root.priority.passOnce()
            }
        }

        RulesHorizontalListView {
            id: fallbackList
            objectName: "rulesPriorityFallbackActions"
            Layout.fillWidth: true
            Layout.preferredHeight: Theme.size(48)
            visible: root.fallbackActions.length > 0
            model: root.fallbackActions
            spacing: Theme.size(7)
            delegate: AppButton {
                required property var modelData
                objectName: "rulesPromptOption-" + modelData.responseId
                compact: true
                enabled: root.priority.canAct
                text: modelData.label
                onClicked: root.priority.respondAction(modelData.responseId)
            }
        }
    }
}
