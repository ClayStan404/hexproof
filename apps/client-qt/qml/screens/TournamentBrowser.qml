// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import "../components"

Page {
    id: root

    readonly property var appWindow: ApplicationWindow.window

    background: AppBackground { }
    Component.onCompleted: ws.requestTournamentList()

    ColumnLayout {
        anchors.fill: parent
        anchors.topMargin: Theme.size(22)
        anchors.bottomMargin: Theme.size(28)
        anchors.leftMargin: Theme.pageMargin
        anchors.rightMargin: Theme.pageMargin
        spacing: Theme.size(16)

        ScreenHeader {
            Layout.fillWidth: true
            title: qsTr("Events")
            subtitle: qsTr("Join constructed and Limited Swiss tournaments")
            onBackRequested: root.appWindow.popScreen()
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.size(10)

            AppTextField {
                id: codeField
                Layout.preferredWidth: Theme.size(230)
                placeholderText: qsTr("Event code")
                maximumLength: 16
                onAccepted: root.enterByCode()
            }

            AppButton {
                compact: true
                text: qsTr("Open")
                enabled: codeField.text.trim().length > 0
                onClicked: root.enterByCode()
            }

            Item { Layout.fillWidth: true }

            AppButton {
                objectName: "tournamentHistoryButton"
                compact: true
                text: qsTr("Event history (%1)").arg(
                          tournament.historicalTournamentList.length)
                leadingText: "◷"
                onClicked: historyPopup.open()
            }

            AppButton {
                compact: true
                text: qsTr("Refresh")
                leadingText: "↻"
                onClicked: ws.requestTournamentList()
            }

            AppButton {
                variant: "primary"
                text: qsTr("Create tournament")
                leadingText: "+"
                onClicked: root.appWindow.pushScreen(
                               "screens/TournamentCreate.qml")
            }
        }

        Surface {
            Layout.fillWidth: true
            Layout.fillHeight: true
            color: Theme.surfaceMuted

            ColumnLayout {
                anchors.centerIn: parent
                visible: tournament.activeTournamentList.length === 0
                spacing: Theme.size(10)

                Text {
                    textFormat: Text.PlainText
                    text: qsTr("No active events are available on this hub.")
                    color: Theme.text
                    font.pixelSize: Theme.fontSize(16)
                    font.weight: Font.DemiBold
                    Layout.alignment: Qt.AlignHCenter
                }
                Text {
                    textFormat: Text.PlainText
                    text: qsTr("Create an event, refresh, or open Event history.")
                    color: Theme.textMuted
                    font.pixelSize: Theme.fontSize(12)
                    Layout.alignment: Qt.AlignHCenter
                }
            }

            ListView {
                id: tournamentList
                objectName: "tournamentList"
                anchors.fill: parent
                anchors.margins: Theme.size(14)
                model: tournament.activeTournamentList
                visible: tournament.activeTournamentList.length > 0
                spacing: Theme.size(10)
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                delegate: eventDelegate
            }
        }
    }

    Component {
        id: eventDelegate

        Surface {
            id: tournamentRow
            required property var modelData

            width: ListView.view.width
            height: Theme.size(112)
            color: Theme.surfaceElevated
            interactive: true

            RowLayout {
                anchors.fill: parent
                anchors.margins: Theme.size(16)
                spacing: Theme.size(14)

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Theme.size(5)

                    RowLayout {
                        Layout.fillWidth: true

                        Text {
                            textFormat: Text.PlainText
                            Layout.fillWidth: true
                            text: tournamentRow.modelData.name
                            color: Theme.text
                            font.pixelSize: Theme.fontSize(16)
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                        }

                        StatusPill {
                            text: root.statusLabel(tournamentRow.modelData.status)
                            statusColor: root.statusColor(
                                             tournamentRow.modelData.status)
                        }
                    }

                    Text {
                        textFormat: Text.PlainText
                        Layout.fillWidth: true
                        text: tournamentRow.modelData.tournamentId + " · "
                              + root.coordinatorLabel(
                                  tournamentRow.modelData.coordinator) + " · "
                              + root.eventTypeLabel(
                                  tournamentRow.modelData.eventType,
                                  tournamentRow.modelData.format) + " · "
                              + root.matchLabel(tournamentRow.modelData.matchMode)
                        color: Theme.textSecondary
                        font.pixelSize: Theme.fontSize(12)
                        elide: Text.ElideRight
                    }

                    Text {
                        textFormat: Text.PlainText
                        Layout.fillWidth: true
                        text: tournamentRow.modelData.coordinator === "casual"
                              ? qsTr("%1 registered · %2 checked in · no standings")
                                .arg(tournamentRow.modelData.registered)
                                .arg(tournamentRow.modelData.checkedIn)
                              : qsTr("%1 registered · %2 checked in · %3 rounds")
                                .arg(tournamentRow.modelData.registered)
                                .arg(tournamentRow.modelData.checkedIn)
                                .arg(tournamentRow.modelData.plannedRounds > 0
                                     ? tournamentRow.modelData.plannedRounds
                                     : qsTr("automatic"))
                        color: Theme.textMuted
                        font.pixelSize: Theme.fontSize(11)
                        elide: Text.ElideRight
                    }
                }

                AppButton {
                    variant: "primary"
                    compact: true
                    text: tournamentRow.modelData.registrationOpen
                          ? qsTr("View / register") : qsTr("View")
                    onClicked: root.openEvent(
                                   tournamentRow.modelData.tournamentId)
                }
            }
        }
    }

    Popup {
        id: historyPopup
        objectName: "tournamentHistoryPopup"

        parent: Overlay.overlay
        x: Math.round((parent.width - width) / 2)
        y: Math.round((parent.height - height) / 2)
        width: Math.min(Theme.size(920), parent.width - Theme.size(48))
        height: Math.min(Theme.size(680), parent.height - Theme.size(56))
        padding: Theme.size(22)
        modal: true
        focus: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        Overlay.modal: Rectangle { color: "#A6050B09" }

        background: Rectangle {
            color: Theme.surfaceElevated
            radius: Theme.radiusLarge
            border.width: 1
            border.color: Theme.borderStrong
        }

        contentItem: ColumnLayout {
            spacing: Theme.size(14)

            RowLayout {
                Layout.fillWidth: true

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Theme.size(3)

                    Text {
                        textFormat: Text.PlainText
                        Layout.fillWidth: true
                        text: qsTr("Event history")
                        color: Theme.text
                        font.pixelSize: Theme.fontSize(21)
                        font.weight: Font.DemiBold
                    }

                    Text {
                        textFormat: Text.PlainText
                        Layout.fillWidth: true
                        text: qsTr("Completed and cancelled events retained by this server.")
                        color: Theme.textMuted
                        font.pixelSize: Theme.fontSize(12)
                    }
                }

                AppButton {
                    compact: true
                    variant: "ghost"
                    text: "×"
                    accessibleName: qsTr("Close")
                    Layout.preferredWidth: Theme.size(40)
                    onClicked: historyPopup.close()
                }
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 1
                color: Theme.divider
            }

            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                Text {
                    textFormat: Text.PlainText
                    anchors.centerIn: parent
                    visible: tournament.historicalTournamentList.length === 0
                    text: qsTr("No completed or cancelled events are available.")
                    color: Theme.textMuted
                    font.pixelSize: Theme.fontSize(13)
                }

                ListView {
                    id: tournamentHistoryList
                    objectName: "tournamentHistoryList"
                    anchors.fill: parent
                    model: tournament.historicalTournamentList
                    visible: tournament.historicalTournamentList.length > 0
                    spacing: Theme.size(10)
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                    delegate: eventDelegate
                }
            }
        }
    }

    Connections {
        target: ws
        function onLastErrorChanged() {
            if (ws.lastError)
                root.appWindow.showBanner(I18n.status(ws.lastError))
        }
    }

    function enterByCode() {
        const code = codeField.text.trim()
        if (code.length > 0)
            ws.enterTournament(code)
    }

    function openEvent(tournamentId) {
        historyPopup.close()
        ws.enterTournament(tournamentId)
    }

    function matchLabel(mode) {
        return mode === "bo3" ? qsTr("BO 3") : qsTr("BO 1")
    }

    function eventTypeLabel(eventType, format) {
        if (eventType === "set_sealed")
            return qsTr("Set sealed")
        if (eventType === "set_draft")
            return qsTr("Set draft")
        if (eventType === "cube_draft")
            return qsTr("Cube")
        return I18n.tournamentFormatLabel(format)
    }

    function coordinatorLabel(coordinator) {
        return coordinator === "casual" ? qsTr("Casual room") : qsTr("Swiss tournament")
    }

    function statusLabel(status) {
        if (status === "registration")
            return qsTr("Registration")
        if (status === "running")
            return qsTr("Running")
        if (status === "completed")
            return qsTr("Completed")
        return qsTr("Cancelled")
    }

    function statusColor(status) {
        if (status === "registration")
            return Theme.success
        if (status === "cancelled")
            return Theme.error
        if (status === "completed")
            return Theme.textMuted
        return Theme.accent
    }
}
