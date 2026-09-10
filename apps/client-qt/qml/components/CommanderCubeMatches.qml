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
    property var selectedOpponents: []
    readonly property var ownPairing: roomController.ownPairing
    readonly property var invitedIds: [tournamentModel.participantId].concat(selectedOpponents)
    readonly property bool accepted: !!ownPairing
        && (ownPairing.acceptedPlayerIds || []).indexOf(tournamentModel.participantId) >= 0
    readonly property var opponents: (tournamentModel.participants || []).filter(
        player => player.participantId !== tournamentModel.participantId)
    readonly property var availableOpponentIds: opponents.filter(player => player.online
        && player.competing && !player.dropped && !roomController.pairingFor(player.participantId))
        .map(player => player.participantId)
    onAvailableOpponentIdsChanged: selectedOpponents = selectedOpponents.filter(
        id => availableOpponentIds.indexOf(id) >= 0)
    spacing: Theme.size(10)
    onOwnPairingChanged: {
        if (ownPairing) selectedOpponents = []
    }

    Text {
        textFormat: Text.PlainText
        Layout.fillWidth: true
        text: qsTr("Commander Cube · free play")
        color: Theme.text
        font.pixelSize: Theme.fontSize(22)
        font.weight: Font.DemiBold
        wrapMode: Text.WordWrap
    }
    Text {
        textFormat: Text.PlainText
        Layout.fillWidth: true
        text: qsTr("Choose one to three other players. Everyone must accept and enter before the game can start.")
        color: Theme.textSecondary
        font.pixelSize: Theme.fontSize(13)
        wrapMode: Text.WordWrap
    }
    Surface {
        Layout.fillWidth: true
        implicitHeight: invitationContent.implicitHeight + Theme.size(24)
        visible: !!root.ownPairing
        color: Theme.primaryMuted
        ColumnLayout {
            id: invitationContent
            anchors.fill: parent
            anchors.margins: Theme.size(12)
            spacing: Theme.size(8)
            Text {
                textFormat: Text.PlainText
                objectName: "commanderCubeInvitationStatus"
                Layout.fillWidth: true
                text: !root.ownPairing ? "" : root.ownPairing.status === "invited"
                    ? qsTr("Waiting for everyone to accept · %1 / %2")
                      .arg((root.ownPairing.acceptedPlayerIds || []).length)
                      .arg((root.ownPairing.playerIds || []).length)
                    : qsTr("Your table is ready")
                color: Theme.text
                font.pixelSize: Theme.fontSize(15)
                wrapMode: Text.WordWrap
            }
            Text {
                textFormat: Text.PlainText
                Layout.fillWidth: true
                text: root.ownPairing ? (root.ownPairing.playerIds || []).map((id, index) =>
                    ((root.ownPairing.acceptedPlayerIds || []).indexOf(id) >= 0 ? "✓ " : "… ")
                    + ((root.ownPairing.playerNames || [])[index] || id)).join(" · ") : ""
                color: Theme.textSecondary
                font.pixelSize: Theme.fontSize(12)
                wrapMode: Text.WordWrap
            }
            Flow {
                Layout.fillWidth: true
                spacing: Theme.size(8)
                AppButton {
                    objectName: "commanderCubeAcceptButton"
                    visible: !!root.ownPairing && root.ownPairing.status === "invited" && !root.accepted
                    enabled: root.roomController.connected
                    text: qsTr("Accept invitation")
                    variant: "primary"
                    compact: true
                    onClicked: root.roomController.acceptGroup()
                }
                AppButton {
                    objectName: "commanderCubeOpenButton"
                    visible: !!root.ownPairing && root.ownPairing.status === "open"
                    enabled: root.roomController.connected
                    text: root.ownPairing && root.ownPairing.roomId ? qsTr("Return to match") : qsTr("Enter match")
                    variant: "primary"
                    compact: true
                    onClicked: root.roomController.openMatch()
                }
                AppButton {
                    objectName: "commanderCubeCancelButton"
                    visible: !!root.ownPairing && !root.ownPairing.roomId
                    enabled: root.roomController.connected
                    text: root.accepted ? qsTr("Cancel invitation") : qsTr("Decline")
                    compact: true
                    onClicked: root.roomController.cancelInvitation()
                }
            }
        }
    }
    ListView {
        objectName: "commanderCubeOpponentList"
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
            readonly property bool selected: root.selectedOpponents.indexOf(modelData.participantId) >= 0
            readonly property bool available: !!modelData.online && !!modelData.competing
                && !modelData.dropped && !pairing
            width: ListView.view.width
            height: Theme.size(78)
            color: selected ? Theme.primaryMuted : Theme.surfaceElevated
            RowLayout {
                anchors.fill: parent
                anchors.margins: Theme.size(12)
                spacing: Theme.size(10)
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    spacing: Theme.size(4)
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
                        color: opponent.available ? Theme.success : Theme.textMuted
                        font.pixelSize: Theme.fontSize(11)
                        elide: Text.ElideRight
                    }
                }
                AppButton {
                    objectName: "commanderCubeSelect-" + opponent.modelData.participantId
                    visible: !opponent.pairing && root.roomController.isParticipant && !root.ownPairing
                    enabled: root.roomController.connected && !root.roomController.sittingOut && (opponent.selected
                        || (opponent.available && root.selectedOpponents.length < 3))
                    text: opponent.selected ? qsTr("Selected") : qsTr("Select")
                    leadingText: opponent.selected ? "✓" : "+"
                    compact: true
                    variant: opponent.selected ? "primary" : "secondary"
                    onClicked: root.toggleOpponent(opponent.modelData.participantId)
                }
                AppButton {
                    objectName: "commanderCubeWatch-" + opponent.modelData.participantId
                    visible: !!opponent.pairing && !!opponent.pairing.roomId
                        && opponent.pairing.status === "open" && !root.ownPairing
                    enabled: root.roomController.connected
                    text: qsTr("Watch match")
                    compact: true
                    onClicked: root.roomController.watchMatch(opponent.pairing.roomId)
                }
            }
        }
    }
    AppButton {
        objectName: "commanderCubeInviteGroupButton"
        Layout.fillWidth: true
        visible: root.roomController.isParticipant && !root.ownPairing
        enabled: root.roomController.canInviteGroup(root.invitedIds)
        text: qsTr("Invite selected players · %1 / 4 seats").arg(root.invitedIds.length)
        variant: "primary"
        onClicked: root.roomController.inviteGroup(root.invitedIds)
    }

    function toggleOpponent(id) {
        if (selectedOpponents.indexOf(id) >= 0)
            selectedOpponents = selectedOpponents.filter(candidate => candidate !== id)
        else if (selectedOpponents.length < 3) {
            const player = roomController.participantFor(id)
            if (player && player.online && player.competing && !player.dropped && !roomController.pairingFor(id))
                selectedOpponents = selectedOpponents.concat([id])
        }
    }
}
