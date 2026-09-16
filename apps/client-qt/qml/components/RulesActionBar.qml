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
    readonly property var priority: tableController.priority
    readonly property var session: tableController.rulesSession
    readonly property bool narrowLayout: width < Theme.size(360)
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
                : qsTr("Your action · %1").arg(tableController.stepLabel(session.step))
        return session.promptPending ? tableController.promptTitle(session.promptKind, session.promptTitle)
                                     : qsTr("Waiting for another player")
    }

    ColumnLayout {
        id: content
        width: root.width
        spacing: Theme.size(5)

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.size(8)
            Text {
                objectName: "rulesPriorityStatus"
                textFormat: Text.PlainText
                Layout.fillWidth: true
                text: root.statusText()
                color: root.priority.fullControl || root.priority.stopped ? Theme.accent : Theme.text
                font.pixelSize: Theme.fontSize(11)
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }
            Text {
                textFormat: Text.PlainText
                visible: root.priority.active && !root.priority.fullControl && !root.priority.yieldMode
                text: qsTr("Smart priority enabled")
                color: Theme.textSecondary
                font.pixelSize: Theme.fontSize(10)
                Layout.maximumWidth: root.width * 0.45
                elide: Text.ElideRight
            }
        }

        GridLayout {
            columns: root.narrowLayout ? 2 : 4
            Layout.fillWidth: true
            columnSpacing: Theme.size(7)
            rowSpacing: Theme.size(5)

            AppButton {
                objectName: "rulesFullControl"
                compact: true
                checkable: true
                checked: root.priority.fullControl
                enabled: root.priority.active
                text: qsTr("Full control")
                variant: checked ? "highlight" : "ghost"
                onClicked: root.priority.setFullControl(checked)
            }

            Item { visible: !root.narrowLayout; Layout.fillWidth: true; Layout.minimumWidth: 0 }

            AppButton {
                objectName: "rulesCancelYield"
                visible: root.priority.yieldMode.length > 0
                compact: true
                text: qsTr("Cancel passing")
                onClicked: root.priority.cancelYield()
            }

            AppButton {
                id: yieldButton
                objectName: "rulesYieldMenuButton"
                visible: !root.priority.yieldMode
                enabled: root.priority.canStartYield
                compact: true
                text: qsTr("Pass…")
                onClicked: yieldMenu.open()

                Menu {
                    id: yieldMenu
                    y: -height
                    width: Theme.size(290)
                    onAboutToShow: root.priority.passMenuOpen = true
                    onClosed: root.priority.passMenuOpen = false
                    function choose(mode) {
                        root.priority.passMenuOpen = false
                        root.priority.beginYield(mode)
                    }
                    MenuItem {
                        objectName: "rulesYieldUntilResponse"
                        text: qsTr("Until a response or turn ends")
                        onTriggered: yieldMenu.choose("response")
                    }
                    MenuItem {
                        objectName: "rulesYieldTurn"
                        text: qsTr("Rest of this turn")
                        onTriggered: yieldMenu.choose("turn")
                    }
                    MenuItem {
                        objectName: "rulesYieldStack"
                        text: qsTr("Current stack")
                        enabled: root.priority.stackIds.length > 0
                        onTriggered: yieldMenu.choose("stack")
                    }
                }
            }

            AppButton {
                objectName: "rulesPromptOption-$pass"
                Layout.columnSpan: root.narrowLayout ? 2 : 1
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
