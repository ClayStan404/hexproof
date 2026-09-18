// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

Surface {
    id: root

    required property var tableController
    property bool compactChrome: false
    readonly property bool showTurnState: tableController.rulesSession.active
                                          && !tableController.sideboarding
                                          && !tableController.matchUi.matchFinished
    readonly property var phaseSteps: [
        "untap", "upkeep", "draw", "main1", "begin_combat",
        "declare_attackers", "declare_blockers", "combat_damage",
        "end_combat", "main2", "end", "cleanup"
    ]

    objectName: "rulesActionRail"
    Layout.minimumWidth: root.tableController.actionRailWidth
    Layout.preferredWidth: root.tableController.actionRailWidth
    Layout.maximumWidth: root.tableController.actionRailWidth
    Layout.fillHeight: true
    color: compactChrome ? Theme.withAlpha(Theme.backgroundRaised, 0.97)
                         : Theme.tableRailFill
    radius: compactChrome ? Theme.radiusMedium : 0
    border.width: 0

    Rectangle {
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        width: Theme.size(2)
        visible: !root.compactChrome
        color: Theme.tableDivider
    }

    component SectionLabel: Text {
        textFormat: Text.PlainText
        Layout.fillWidth: true
        color: Theme.textMuted
        font.pixelSize: Theme.fontSize(9)
        font.weight: Font.DemiBold
        font.capitalization: Font.AllUppercase
        horizontalAlignment: Text.AlignLeft
        elide: Text.ElideRight
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.size(root.compactChrome ? 12 : 4)
        spacing: Theme.size(root.compactChrome ? 6 : 4)

        Text {
            textFormat: Text.PlainText
            Layout.fillWidth: true
            text: root.tableController.roomSession.roomName
                  || qsTr("Forge rules game")
            color: Theme.text
            font.pixelSize: Theme.fontSize(root.compactChrome ? 13 : 10)
            font.weight: Font.DemiBold
            elide: Text.ElideRight
            horizontalAlignment: root.compactChrome ? Text.AlignLeft : Text.AlignHCenter
        }

        Text {
            textFormat: Text.PlainText
            Layout.fillWidth: true
            visible: root.tableController.roomSession.roomId.length > 0
            text: qsTr("ROOM CODE") + " · "
                  + root.tableController.roomSession.roomId
            color: Theme.textSecondary
            font.pixelSize: Theme.fontSize(9)
            horizontalAlignment: root.compactChrome ? Text.AlignLeft : Text.AlignHCenter
            elide: Text.ElideRight
        }

        Text {
            textFormat: Text.PlainText
            objectName: "rulesTurnSummary"
            Layout.fillWidth: true
            visible: root.showTurnState
            text: qsTr("Turn %1 · %2")
                  .arg(root.tableController.rulesSession.turn)
                  .arg(root.tableController.stepLabel(
                           root.tableController.rulesSession.step))
            color: Theme.textSecondary
            font.pixelSize: Theme.fontSize(9)
            horizontalAlignment: root.compactChrome ? Text.AlignLeft : Text.AlignHCenter
            elide: Text.ElideRight
        }

        SectionLabel {
            text: qsTr("Table")
            visible: root.compactChrome
        }

        AppButton {
            objectName: "rulesBackgroundButton"
            Layout.fillWidth: true
            compact: true
            text: qsTr("Background")
            onClicked: root.tableController.openBackgroundPicker()
        }

        SectionLabel {
            text: qsTr("Match")
            visible: root.compactChrome
        }

        AppButton {
            objectName: "rulesReturnToRoomButton"
            Layout.fillWidth: true
            compact: true
            variant: "primary"
            visible: root.tableController.matchUi.matchFinished
            enabled: root.tableController.matchUi.canReturn
            text: qsTr("Return to room")
            onClicked: root.tableController.matchUi.returnToRoom()
        }

        Text {
            objectName: "rulesMatchScore"
            textFormat: Text.PlainText
            Layout.fillWidth: true
            text: qsTr("Game %1 · %2")
                  .arg(root.tableController.gameSession.gameNumber)
                  .arg(root.tableController.matchUi.scoreSummary())
            color: Theme.textSecondary
            font.pixelSize: Theme.fontSize(10)
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
        }

        AppButton {
            objectName: "rulesRestartGameButton"
            Layout.fillWidth: true
            compact: true
            visible: root.tableController.roomSession.host
                     && !root.tableController.rulesSession.gameOver
                     && !root.tableController.sideboarding
                     && !root.tableController.matchUi.matchFinished
            enabled: root.tableController.matchUi.canRestart
            text: qsTr("Restart game")
            onClicked: root.tableController.matchUi.openRestartConfirmation()
        }

        AppButton {
            objectName: "rulesToggleGameLogButton"
            Layout.fillWidth: true
            compact: true
            text: root.tableController.showGameLogRail
                  ? qsTr("Hide log / chat") : qsTr("Show log / chat")
            onClicked: root.tableController.setGameLogVisible(
                           !root.tableController.showGameLogRail)
        }

        Repeater {
            model: root.tableController.rulesSession.players

            delegate: AppButton {
                required property int seat
                required property string status

                objectName: "rulesConcedeButton-" + seat
                Layout.fillWidth: true
                compact: true
                variant: "danger"
                visible: seat === root.tableController.localSeat
                         && status === "playing"
                         && !root.tableController.rulesSession.gameOver
                         && !root.tableController.sideboarding
                         && !root.tableController.matchUi.matchFinished
                enabled: root.tableController.roomConnected
                text: qsTr("Concede")
                onClicked: root.tableController.openConcedeConfirmation()
            }
        }

        AppButton {
            objectName: "rulesLeaveRoomButton"
            Layout.fillWidth: true
            compact: true
            variant: "secondary"
            text: qsTr("Leave room")
            enabled: root.tableController.roomConnected
            onClicked: root.tableController.matchUi.openLeaveConfirmation()
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 1
            color: Theme.borderStrong
        }

        SectionLabel {
            text: qsTr("Phases")
            visible: root.compactChrome && root.showTurnState
        }

        Text {
            textFormat: Text.PlainText
            objectName: "rulesActiveSeatSummary"
            Layout.fillWidth: true
            visible: root.showTurnState
            text: root.tableController.rulesSession.activeSeat >= 0
                  ? qsTr("Active · Seat %1").arg(
                        root.tableController.rulesSession.activeSeat + 1)
                  : qsTr("Waiting for Forge")
            color: Theme.primary
            font.pixelSize: Theme.fontSize(10)
            font.weight: Font.DemiBold
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
        }

        Text {
            textFormat: Text.PlainText
            Layout.fillWidth: true
            visible: root.showTurnState
                     && root.tableController.rulesSession.prioritySeat >= 0
            text: qsTr("Priority · Seat %1").arg(
                      root.tableController.rulesSession.prioritySeat + 1)
            color: Theme.accent
            font.pixelSize: Theme.fontSize(9)
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 1
            color: Theme.divider
        }

        ScrollView {
            objectName: "rulesPhaseScrollView"
            visible: root.showTurnState
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            contentWidth: availableWidth
            ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
            ScrollBar.vertical.policy: ScrollBar.AsNeeded

            Column {
                width: parent.width
                spacing: Theme.size(3)

                Row {
                    width: parent.width
                    height: Theme.size(22)
                    Text {
                        width: parent.width - Theme.size(56)
                        textFormat: Text.PlainText
                        text: qsTr("Stops")
                        color: Theme.textSecondary
                        font.pixelSize: Theme.fontSize(9)
                    }
                    Repeater {
                        model: [qsTr("You"), qsTr("Others")]
                        delegate: Text {
                            required property string modelData
                            width: Theme.size(28)
                            textFormat: Text.PlainText
                            text: modelData
                            color: Theme.textSecondary
                            font.pixelSize: Theme.fontSize(8)
                            horizontalAlignment: Text.AlignHCenter
                            elide: Text.ElideRight
                        }
                    }
                }

                Repeater {
                    model: root.phaseSteps

                    delegate: Rectangle {
                        id: phaseItem
                        required property string modelData
                        required property int index

                        objectName: "rulesPhaseItem" + index
                        width: parent ? parent.width : 0
                        height: Theme.size(30)
                        radius: Theme.radiusSmall
                        color: root.tableController.rulesSession.step
                               === modelData ? Theme.primaryMuted : "transparent"
                        border.width: root.tableController.rulesSession.step
                                      === modelData ? 1 : 0
                        border.color: Theme.primary

                        Text {
                            textFormat: Text.PlainText
                            anchors.fill: parent
                            anchors.leftMargin: Theme.size(4)
                            anchors.rightMargin: Theme.size(56)
                            text: root.tableController.stepLabel(
                                      phaseItem.modelData)
                            color: root.tableController.rulesSession.step
                                   === phaseItem.modelData
                                   ? Theme.primary : Theme.textDisabled
                            font.pixelSize: Theme.fontSize(9)
                            font.weight: root.tableController.rulesSession.step
                                         === phaseItem.modelData
                                         ? Font.DemiBold : Font.Normal
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            wrapMode: Text.WordWrap
                            maximumLineCount: 2
                            elide: Text.ElideRight
                        }

                        Row {
                            anchors.right: parent.right
                            height: parent.height
                            Repeater {
                                model: [true, false]
                                delegate: Rectangle {
                                    id: stopControl
                                    required property bool modelData
                                    readonly property var priority: root.tableController.priority || null
                                    readonly property bool selected: priority
                                        ? priority.hasStop(phaseItem.modelData, modelData) : false
                                    readonly property bool available: priority && priority.active
                                        && phaseItem.modelData !== "untap"
                                    objectName: "rulesPhaseStop-" + (modelData ? "own-" : "other-")
                                        + phaseItem.modelData
                                    width: Theme.size(28)
                                    height: parent.height
                                    color: selected ? Theme.primaryMuted : "transparent"
                                    radius: Theme.radiusSmall
                                    border.width: activeFocus ? 1 : 0
                                    border.color: Theme.primary
                                    activeFocusOnTab: available
                                    Accessible.role: Accessible.CheckBox
                                    Accessible.checkable: true
                                    Accessible.checked: selected
                                    Accessible.name: modelData
                                        ? qsTr("Stop at %1 on your turns").arg(root.tableController.stepLabel(phaseItem.modelData))
                                        : qsTr("Stop at %1 on other players' turns").arg(root.tableController.stepLabel(phaseItem.modelData))
                                    function toggle() {
                                        if (available)
                                            priority.toggleStop(phaseItem.modelData, modelData)
                                    }
                                    Accessible.onToggleAction: toggle()
                                    Keys.onSpacePressed: toggle()
                                    Keys.onReturnPressed: toggle()
                                    Rectangle {
                                        anchors.centerIn: parent
                                        width: Theme.size(10)
                                        height: width
                                        radius: width / 2
                                        color: stopControl.selected ? Theme.primary : "transparent"
                                        border.width: 1
                                        border.color: stopControl.selected ? Theme.primary : Theme.textMuted
                                        opacity: stopControl.available ? 1 : 0.25
                                    }
                                    TapHandler {
                                        enabled: stopControl.available
                                        onTapped: stopControl.toggle()
                                    }
                                    HoverHandler { id: stopHover }
                                    ToolTip.visible: stopHover.hovered
                                    ToolTip.text: stopControl.Accessible.name
                                    ToolTip.delay: 350
                                }
                            }
                        }
                    }
                }
            }
        }

        Item {
            visible: !root.showTurnState
            Layout.fillHeight: true
        }

        Text {
            textFormat: Text.PlainText
            Layout.fillWidth: true
            text: qsTr("Forge controls phases and legal actions")
            color: Theme.textMuted
            font.pixelSize: Theme.fontSize(8)
            wrapMode: Text.WordWrap
            horizontalAlignment: Text.AlignHCenter
        }
    }
}
