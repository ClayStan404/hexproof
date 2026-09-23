// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

Surface {
    id: root

    required property var tableController
    readonly property var appWindow: ApplicationWindow.window
    property bool compactChrome: false
    property var hostingDialog: null
    signal audioSettingsRequested()
    readonly property bool playerHosted: tableController.roomSession.hostingMode === "player"
    readonly property var priority: tableController.priority || null
    readonly property bool showTurnState: tableController.rulesSession.active
                                          && !tableController.sideboarding
                                          && !tableController.matchUi.matchFinished

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
            objectName: "rulesServerTransport"
            Layout.fillWidth: true
            textFormat: Text.PlainText
            text: I18n.serverTransportLabel(root.tableController.wsModel.serverTransportState)
            visible: text.length > 0
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

        AppButton {
            objectName: "rulesAudioButton"
            Layout.fillWidth: true
            compact: true
            text: qsTr("Audio")
            onClicked: {
                root.audioSettingsRequested()
                const window = root.appWindow
                if (window && typeof window.pushScreen === "function")
                    window.pushScreen("screens/AudioSettings.qml", root.tableController.preferencesModel
                                      ? {settings:root.tableController.preferencesModel} : {})
            }
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
            text: qsTr("Priority")
            visible: root.compactChrome
        }

        RulesPriorityMode {
            Layout.fillWidth: true
            settings: root.priority.settings
            onModeSelected: fullControl => root.priority.setFullControl(fullControl)
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

            RulesPhaseStops {
                width: parent.width
                compact: true
                stops: root.priority ? root.priority.phaseStops : ({})
                currentStep: root.tableController.rulesSession.step
                editable: root.tableController.localSeat >= 0
                onStopToggled: (step, ownTurn) => root.priority.toggleStop(step, ownTurn)
            }
        }

        Item {
            visible: !root.showTurnState
            Layout.fillHeight: true
        }

        SectionLabel {
            text: qsTr("Hosting")
            visible: root.compactChrome && root.playerHosted
        }

        Text {
            objectName: "forgeSettingsHostStatus"
            Layout.fillWidth: true
            visible: root.playerHosted
            textFormat: Text.PlainText
            text: root.tableController.roomSession.hostStatus && root.tableController.roomSession.hostStatus.migrating === true
                ? qsTr("Verifying host transfer… The game is paused.") : root.tableController.hostingPaused === true
                    ? qsTr("Waiting for the host to reconnect… The game is paused.")
                    : root.tableController.wsModel.peerTransportState === "direct" ? qsTr("Player hosted · direct connection")
                    : qsTr("Player hosted · server relay")
            color: root.tableController.hostingPaused === true ? Theme.warning : Theme.textMuted
            font.pixelSize: Theme.fontSize(11)
            wrapMode: Text.WordWrap
        }

        AppButton {
            objectName: "forgeHostingOptions"
            Layout.fillWidth: true
            visible: root.playerHosted && root.hostingDialog
            compact: true
            text: qsTr("Hosting")
            onClicked: root.hostingDialog.open()
        }

        ForgePeerControls {
            objectName: "forgeTablePeerConnection"
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            compact: true
            wsModel: root.tableController.wsModel
        }
    }
}
