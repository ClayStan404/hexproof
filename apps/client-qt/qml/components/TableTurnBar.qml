// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

Surface {
    id: root

    required property var tableController

    readonly property var activePlayer:
        tableController.seatState.seatData(
            tableController.gameSession.activeSeat)
    readonly property var phaseSteps: [
        {"id": "untap", "label": "Untap"},
        {"id": "upkeep", "label": "Upkeep"},
        {"id": "draw", "label": "Draw"},
        {"id": "main_1", "label": "Main 1"},
        {"id": "begin_combat", "label": "Begin combat"},
        {"id": "declare_attackers", "label": "Attackers"},
        {"id": "declare_blockers", "label": "Blockers"},
        {"id": "combat_damage", "label": "Damage"},
        {"id": "end_combat", "label": "End combat"},
        {"id": "main_2", "label": "Main 2"},
        {"id": "end", "label": "End"}
    ]
    readonly property bool atEndStep:
        tableController.displayedPhase === "end"
    readonly property var ownPlayer:
        tableController.seatState.seatData(tableController.roomSession.seatIndex)
    readonly property string assistKind:
        !tableController.isActivePlayer ? ""
        : tableController.displayedPhase === "untap" ? "untap"
        : tableController.displayedPhase === "draw" ? "draw"
        : tableController.displayedPhase === "declare_attackers" ? "attack"
        : ""

    function responseStatusLabel() {
        if (ownPlayer.responseStatus === "hold")
            return qsTr("Wait")
        if (ownPlayer.responseStatus === "pass")
            return qsTr("Passed")
        return qsTr("Signal")
    }

    function assistLabel() {
        if (assistKind === "untap")
            return qsTr("Untap all")
        if (assistKind === "draw")
            return qsTr("Draw 1")
        if (assistKind === "attack")
            return qsTr("Tap attackers")
        return ""
    }

    function assistEnabled() {
        if (assistKind === "untap")
            return tableController.gameValues.hasTappedOwnPermanent()
        if (assistKind === "draw")
            return tableController.ownSeatData.libraryCount > 0
        if (assistKind === "attack")
            return tableController.gameValues.hasUntappedDeclaredAttacker()
        return false
    }

    function runAssist() {
        if (assistKind === "untap")
            tableController.gameValues.untapOwnBattlefield()
        else if (assistKind === "draw")
            tableController.wsModel.drawCards(1)
        else if (assistKind === "attack")
            tableController.gameValues.tapDeclaredAttackers()
    }

    objectName: "phaseStrip"
    Layout.fillWidth: true
    Layout.fillHeight: true
    color: "transparent"
    radius: 0
    border.width: 0

    ColumnLayout {
        anchors.fill: parent
        spacing: Theme.size(4)

        Text {
            textFormat: Text.PlainText
            Layout.fillWidth: true
            text: root.activePlayer.displayName
                  ? root.activePlayer.displayName
                  : I18n.tr("No active player")
            color: root.tableController.isActivePlayer
                   ? Theme.primary : Theme.text
            font.pixelSize: Theme.fontSize(11)
            font.weight: Font.DemiBold
            elide: Text.ElideRight
            horizontalAlignment: Text.AlignHCenter
        }
        Text {
            textFormat: Text.PlainText
            Layout.fillWidth: true
            text: root.tableController.isActivePlayer
                  ? I18n.tr("Your turn")
                  : I18n.tr("Current turn")
            color: root.tableController.isActivePlayer
                   ? Theme.primary : Theme.textMuted
            font.pixelSize: Theme.fontSize(9)
            font.weight: Font.DemiBold
            elide: Text.ElideRight
            horizontalAlignment: Text.AlignHCenter
        }
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 1
            color: Theme.divider
        }

        ScrollView {
            id: phaseScroll
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            contentWidth: availableWidth
            ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
            ScrollBar.vertical.policy: ScrollBar.AsNeeded

            Column {
                width: phaseScroll.availableWidth
                spacing: Theme.size(3)

                Repeater {
                    model: root.phaseSteps

                    delegate: Button {
                        id: phaseButton

                        required property var modelData
                        required property int index

                        objectName: "phaseButton" + index
                        width: parent ? parent.width : 0
                        height: Theme.size(30)
                        enabled: root.tableController.isActivePlayer
                        hoverEnabled: true
                        focusPolicy: Qt.StrongFocus
                        Accessible.name: I18n.tr(modelData.label)
                        ToolTip.visible: hovered
                        ToolTip.text: I18n.tr(modelData.label)
                        onClicked:
                            root.tableController.rulesAssist.requestSetPhase(
                                modelData.id)

                        background: Rectangle {
                            radius: Theme.radiusSmall
                            color: root.tableController.displayedPhase
                                   === phaseButton.modelData.id
                                   ? Theme.primaryMuted
                                   : (phaseButton.down || phaseButton.hovered
                                      ? Theme.surfaceHover : "transparent")
                            border.width:
                                root.tableController.displayedPhase
                                === phaseButton.modelData.id ? 1 : 0
                            border.color: Theme.primary
                        }
                        contentItem: Text {
                            textFormat: Text.PlainText
                            text: I18n.tr(phaseButton.modelData.label)
                            color: root.tableController.displayedPhase
                                   === phaseButton.modelData.id
                                   ? Theme.primary
                                   : (phaseButton.enabled
                                      ? Theme.text : Theme.textDisabled)
                            font.pixelSize: Theme.fontSize(9)
                            font.weight:
                                root.tableController.displayedPhase
                                === phaseButton.modelData.id
                                ? Font.DemiBold : Font.Normal
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            elide: Text.ElideRight
                        }
                    }
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 1
            color: Theme.divider
        }

        AppButton {
            id: assistButton
            objectName: "turnAssistButton"
            visible: root.assistKind.length > 0
            Layout.fillWidth: true
            Layout.preferredHeight: visible ? Theme.size(32) : 0
            compact: true
            text: root.assistLabel()
            enabled: root.assistEnabled()
            onClicked: root.runAssist()
            ToolTip.visible: hovered
            ToolTip.text: qsTr("Explicit helper; no card rules are inferred")
        }

        RowLayout {
            objectName: "landPlayCountControls"
            Layout.fillWidth: true
            Layout.preferredHeight: Theme.size(30)
            spacing: Theme.size(2)

            Text {
                textFormat: Text.PlainText
                Layout.fillWidth: true
                text: qsTr("Land · %1").arg(
                          root.tableController.landPlay.displayedCount)
                color: Theme.textSecondary
                font.pixelSize: Theme.fontSize(9)
                font.weight: Font.DemiBold
                elide: Text.ElideRight
                ToolTip.visible: landCountHover.hovered
                ToolTip.text: qsTr("Recorded land plays this turn; this is not a rules limit")

                HoverHandler { id: landCountHover }
            }

            AppButton {
                objectName: "decreaseLandPlayCountButton"
                compact: true
                variant: "ghost"
                Layout.preferredWidth: Theme.size(26)
                Layout.minimumWidth: Theme.size(24)
                implicitHeight: Theme.size(26)
                text: "−"
                accessibleName: qsTr("Decrease recorded land plays")
                enabled: root.tableController.isActivePlayer
                         && root.tableController.landPlay.displayedCount > 0
                onClicked: root.tableController.landPlay.adjustCount(-1)
            }

            AppButton {
                objectName: "increaseLandPlayCountButton"
                compact: true
                variant: "ghost"
                Layout.preferredWidth: Theme.size(26)
                Layout.minimumWidth: Theme.size(24)
                implicitHeight: Theme.size(26)
                text: "+"
                accessibleName: qsTr("Increase recorded land plays")
                enabled: root.tableController.isActivePlayer
                         && root.tableController.landPlay.displayedCount
                            < 2147483647
                onClicked: root.tableController.landPlay.adjustCount(1)
            }
        }

        AppButton {
            id: responseStatusButton
            objectName: "responseStatusButton"
            visible: root.tableController.roomSession.seatIndex >= 0
            Layout.fillWidth: true
            Layout.preferredHeight: visible ? Theme.size(32) : 0
            compact: true
            variant: root.ownPlayer.responseStatus === "hold"
                     ? "highlight"
                     : root.ownPlayer.responseStatus === "pass"
                       ? "primary" : "secondary"
            text: root.responseStatusLabel()
            enabled: root.tableController.canAct
            onClicked: {
                const point = mapToItem(root, root.width, 0)
                responseStatusMenu.x = point.x
                responseStatusMenu.y = Math.max(
                            0, Math.min(root.height - responseStatusMenu.height,
                                        point.y))
                responseStatusMenu.open()
            }
            ToolTip.visible: hovered
            ToolTip.text: qsTr("Coordination signal; resets at each phase")
        }

        AppButton {
            id: nextPhaseButton
            objectName: "nextPhaseButton"
            Layout.fillWidth: true
            Layout.preferredHeight: Theme.size(32)
            compact: true
            text: root.atEndStep
                  ? I18n.tr("Next turn") : I18n.tr("Next phase")
            enabled: root.tableController.isActivePlayer
            onClicked: root.tableController.rulesAssist.requestAdvancePhase()
            ToolTip.visible: hovered
            ToolTip.text: I18n.tr("Advance one step") + " · Ctrl+→"
        }

        AppButton {
            id: nextTurnButton
            objectName: "nextTurnButton"
            Layout.fillWidth: true
            Layout.preferredHeight: Theme.size(32)
            compact: true
            variant: root.tableController.isActivePlayer
                     ? "primary" : "secondary"
            text: I18n.tr("End turn")
            enabled: root.tableController.isActivePlayer
            onClicked: root.tableController.rulesAssist.requestAdvanceTurn()
            ToolTip.visible: hovered
            ToolTip.text: I18n.tr("End turn") + " · Ctrl+Enter"
        }
    }

    Menu {
        id: responseStatusMenu

        MenuItem {
            text: qsTr("No response")
            onTriggered:
                root.tableController.wsModel.setResponseStatus("pass")
        }
        MenuItem {
            text: qsTr("Please wait")
            onTriggered:
                root.tableController.wsModel.setResponseStatus("hold")
        }
        MenuSeparator { }
        MenuItem {
            text: qsTr("Clear signal")
            enabled: root.ownPlayer.responseStatus === "pass"
                     || root.ownPlayer.responseStatus === "hold"
            onTriggered:
                root.tableController.wsModel.setResponseStatus("clear")
        }
    }
}
