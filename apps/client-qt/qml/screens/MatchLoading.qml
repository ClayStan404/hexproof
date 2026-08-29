// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import "../components"

Page {
    id: root

    required property var wsModel
    required property var loaderModel
    readonly property var roomSession: wsModel.roomSession

    background: AppBackground { }

    ColumnLayout {
        anchors.centerIn: parent
        width: Math.min(Theme.size(760), parent.width - Theme.size(48))
        spacing: Theme.size(18)

        BrandMark {
            Layout.alignment: Qt.AlignHCenter
            markSize: Theme.size(54)
        }

        Text {
            textFormat: Text.PlainText
            Layout.alignment: Qt.AlignHCenter
            text: root.loaderModel.ready
                  ? (root.roomSession.playtest
                     ? qsTr("Opening playtest table")
                     : qsTr("Waiting for other players"))
                  : qsTr("Preparing the match")
            color: Theme.text
            font.pixelSize: Theme.fontSize(25)
            font.weight: Font.DemiBold
        }

        Text {
            textFormat: Text.PlainText
            Layout.alignment: Qt.AlignHCenter
            Layout.maximumWidth: Theme.size(620)
            text: root.loaderModel.ready
                  ? (root.roomSession.playtest
                     ? qsTr("Your card assets are ready. The playtest table is opening.")
                     : qsTr("Your card assets are ready. The table opens when every player finishes loading."))
                  : qsTr("Downloading missing card information and art for this match.")
            color: Theme.textSecondary
            font.pixelSize: Theme.fontSize(13)
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
        }

        Surface {
            Layout.fillWidth: true
            implicitHeight: loadingContent.implicitHeight + Theme.size(44)
            elevated: true

            ColumnLayout {
                id: loadingContent
                anchors.fill: parent
                anchors.margins: Theme.size(22)
                spacing: Theme.size(14)

                RowLayout {
                    Layout.fillWidth: true
                    Text {
                        textFormat: Text.PlainText
                        text: qsTr("Match assets")
                        color: Theme.text
                        font.pixelSize: Theme.fontSize(15)
                        font.weight: Font.DemiBold
                    }
                    Item { Layout.fillWidth: true }
                    Text {
                        textFormat: Text.PlainText
                        text: root.loaderModel.completed + " / " + root.loaderModel.total
                        color: Theme.textMuted
                        font.pixelSize: Theme.fontSize(12)
                    }
                }

                ProgressBar {
                    id: loadProgress
                    objectName: "matchLoadProgress"
                    Layout.fillWidth: true
                    implicitHeight: Theme.size(12)
                    from: 0
                    to: 1
                    value: root.loaderModel.progress

                    background: Rectangle {
                        color: Theme.disabled
                        radius: height / 2
                    }
                    contentItem: Item {
                        Rectangle {
                            width: parent.width * loadProgress.visualPosition
                            height: parent.height
                            radius: height / 2
                            color: root.loaderModel.failed > 0 ? Theme.warning : Theme.primary
                        }
                    }
                }

                Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Theme.divider }

                Repeater {
                    model: root.roomSession.seats

                    delegate: RowLayout {
                        id: seatRow
                        required property var modelData
                        required property int index
                        Layout.fillWidth: true
                        Layout.preferredHeight: Theme.size(34)

                        Text {
                            textFormat: Text.PlainText
                            text: (seatRow.index + 1) + ". "
                                  + (seatRow.modelData.displayName || qsTr("Open seat"))
                            color: seatRow.modelData.occupied ? Theme.text : Theme.textMuted
                            font.pixelSize: Theme.fontSize(13)
                        }
                        Item { Layout.fillWidth: true }
                        StatusPill {
                            visible: seatRow.modelData.occupied
                            text: seatRow.modelData.loaded ? qsTr("Loaded") : qsTr("Loading")
                            statusColor: seatRow.modelData.loaded ? Theme.success : Theme.warning
                        }
                    }
                }

                InfoBanner {
                    Layout.fillWidth: true
                    message: I18n.status(root.loaderModel.lastError)
                }
            }
        }

        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: Theme.size(10)

            AppButton {
                objectName: "retryMatchLoadButton"
                visible: root.loaderModel.failed > 0
                variant: "primary"
                text: qsTr("Retry failed downloads")
                onClicked: root.loaderModel.retry()
            }

            AppButton {
                visible: root.roomSession.role === "player"
                variant: "ghost"
                text: qsTr("Cancel ready")
                onClicked: root.wsModel.setReady(false)
            }

            AppButton {
                objectName: "matchLoadingLeaveRoomButton"
                variant: "ghost"
                text: root.roomSession.playtest
                      ? qsTr("End playtest")
                      : qsTr("Leave room")
                onClicked: leaveRoomConfirmation.open()
            }
        }
    }

    ConfirmDialog {
        id: leaveRoomConfirmation
        objectName: "matchLoadingLeaveConfirmation"
        titleText: root.roomSession.playtest
                   ? qsTr("End this playtest?")
                   : (root.roomSession.host
                      ? qsTr("Disband the room?")
                      : qsTr("Leave this room?"))
        message: root.roomSession.playtest
                 ? qsTr("This ends the current playtest and returns to the main menu.")
                 : (root.roomSession.host
                    ? qsTr("Leaving as host disbands the room for every player and spectator.")
                    : qsTr("Your seat will be freed and match loading will be cancelled."))
        confirmText: root.roomSession.playtest
                     ? qsTr("End playtest")
                     : (root.roomSession.host
                        ? qsTr("Disband")
                        : qsTr("Leave room"))
        dangerous: true
        onConfirmed: root.wsModel.leaveRoom()
    }
}
