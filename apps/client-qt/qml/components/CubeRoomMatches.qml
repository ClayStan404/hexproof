// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

pragma ComponentBehavior: Bound
pragma Translator: "CubeRoom"

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

ColumnLayout {
    id: root
    required property var roomController
    required property var tournamentModel
    readonly property var ownPairing: roomController.ownPairing
    readonly property bool incoming: !!ownPairing && ownPairing.status === "invited"
                                     && ownPairing.playerBId === tournamentModel.participantId
    readonly property var opponents: {
        const rows = []
        for (const player of tournamentModel.participants || []) {
            if (player.participantId !== tournamentModel.participantId)
                rows.push(player)
        }
        return rows
    }
    spacing: Theme.size(12)

    Text {
        textFormat: Text.PlainText
        Layout.fillWidth: true
        text: qsTr("Free play")
        color: Theme.text
        font.pixelSize: Theme.fontSize(22)
        font.weight: Font.DemiBold
    }
    Text {
        textFormat: Text.PlainText
        Layout.fillWidth: true
        text: qsTr("Choose an opponent. A match starts only after both players agree.")
        color: Theme.textSecondary
        font.pixelSize: Theme.fontSize(13)
        wrapMode: Text.WordWrap
    }

    Surface {
        objectName: "cubeOwnMatchPanel"
        Layout.fillWidth: true
        implicitHeight: invitationContent.implicitHeight + Theme.size(24)
        visible: !!root.ownPairing
        color: Theme.primaryMuted
        ColumnLayout {
            id: invitationContent
            anchors.fill: parent
            anchors.margins: Theme.size(12)
            spacing: Theme.size(10)
            Text {
                textFormat: Text.PlainText
                objectName: "cubeOwnMatchStatus"
                Layout.fillWidth: true
                text: root.ownPairing ? root.incoming
                      ? qsTr("%1 invited you to play.").arg(root.ownPairing.playerAName)
                      : root.ownPairing.status === "invited"
                      ? qsTr("Waiting for %1 to accept…").arg(root.ownPairing.playerBName)
                      : qsTr("Your match is ready: %1 vs %2")
                        .arg(root.ownPairing.playerAName).arg(root.ownPairing.playerBName) : ""
                color: Theme.text
                font.pixelSize: Theme.fontSize(14)
                wrapMode: Text.WordWrap
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.size(8)
                AppButton {
                    objectName: "cubeAcceptInviteButton"
                    visible: root.incoming
                    enabled: root.roomController.connected
                    text: qsTr("Accept invitation")
                    variant: "primary"
                    compact: true
                    onClicked: root.roomController.invitePlayer(root.ownPairing.playerAId)
                }
                AppButton {
                    objectName: "cubeOpenMatchButton"
                    visible: !!root.ownPairing && root.ownPairing.status !== "invited"
                    enabled: root.roomController.connected
                    text: root.ownPairing && root.ownPairing.roomId ? qsTr("Return to match") : qsTr("Enter match")
                    variant: "primary"
                    compact: true
                    onClicked: root.roomController.openMatch()
                }
                AppButton {
                    objectName: "cubeCancelInviteButton"
                    visible: !!root.ownPairing && !root.ownPairing.roomId
                    enabled: root.roomController.connected
                    text: root.incoming ? qsTr("Decline") : root.ownPairing && root.ownPairing.status === "invited"
                          ? qsTr("Cancel invitation") : qsTr("Cancel match")
                    compact: true
                    onClicked: root.roomController.cancelInvitation()
                }
            }
        }
    }

    ListView {
        objectName: "cubeOpponentList"
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.minimumHeight: 0
        model: root.opponents
        spacing: Theme.size(8)
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { }
        delegate: Surface {
            id: opponent
            required property var modelData
            readonly property var pairing: root.roomController.pairingFor(modelData.participantId)
            width: ListView.view.width
            height: Theme.size(82)
            color: Theme.surfaceElevated
            RowLayout {
                anchors.fill: parent
                anchors.margins: Theme.size(12)
                spacing: Theme.size(12)
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    spacing: Theme.size(5)
                    Text {
                        textFormat: Text.PlainText
                        Layout.fillWidth: true
                        text: opponent.modelData.displayName
                        color: Theme.text
                        font.pixelSize: Theme.fontSize(15)
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }
                    Text {
                        textFormat: Text.PlainText
                        Layout.fillWidth: true
                        text: opponent.modelData.dropped ? qsTr("Sitting out")
                              : !opponent.modelData.online ? qsTr("Offline")
                              : opponent.pairing ? opponent.pairing.status === "invited"
                                ? qsTr("Invitation pending") : qsTr("In a match")
                              : qsTr("Available")
                        color: opponent.modelData.dropped || !opponent.modelData.online || opponent.pairing ? Theme.textMuted : Theme.success
                        font.pixelSize: Theme.fontSize(11)
                        elide: Text.ElideRight
                    }
                }
                AppButton {
                    objectName: "cubeInvite-" + opponent.modelData.participantId
                    visible: !opponent.pairing
                    enabled: root.roomController.canInvitePlayer(opponent.modelData.participantId)
                    text: qsTr("Invite to play")
                    variant: "primary"
                    compact: true
                    onClicked: root.roomController.invitePlayer(opponent.modelData.participantId)
                }
                AppButton {
                    objectName: "cubeWatch-" + opponent.modelData.participantId
                    visible: !!opponent.pairing && !!opponent.pairing.roomId
                             && opponent.pairing.status === "open"
                             && (!root.ownPairing || opponent.pairing.pairingId !== root.ownPairing.pairingId)
                    enabled: root.roomController.connected && !root.ownPairing
                    text: qsTr("Watch match")
                    compact: true
                    onClicked: root.roomController.watchMatch(opponent.pairing.roomId)
                }
            }
        }
    }
}
