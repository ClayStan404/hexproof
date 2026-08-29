// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

pragma ComponentBehavior: Bound
pragma Translator: "TournamentLobby"

import QtQuick
import QtQuick.Layouts

Surface {
    id: root

    required property var participants
    required property string participantId
    property int direction: 1
    readonly property int selfIndex: findParticipantIndex(participantId)
    readonly property var viewerRelativeSeats: buildViewerRelativeSeats()
    readonly property string outgoingName: neighborName(direction)
    readonly property string incomingName: neighborName(-direction)

    implicitHeight: Theme.size(218)
    color: Theme.surfaceMuted

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.size(12)
        spacing: Theme.size(6)

        RowLayout {
            Layout.fillWidth: true

            Text {
                textFormat: Text.PlainText
                Layout.fillWidth: true
                text: qsTr("Draft seats")
                color: Theme.text
                font.pixelSize: Theme.fontSize(14)
                font.weight: Font.DemiBold
            }

            StatusPill {
                text: root.direction > 0
                      ? qsTr("Pass left · clockwise")
                      : qsTr("Pass right · counter-clockwise")
                statusColor: Theme.accent
            }
        }

        Item {
            id: seatArea
            Layout.fillWidth: true
            Layout.fillHeight: true

            Rectangle {
                anchors.centerIn: parent
                width: Math.max(Theme.size(120), parent.width - Theme.size(118))
                height: Math.max(Theme.size(64), parent.height - Theme.size(58))
                radius: height / 2
                color: Theme.surface
                border.width: 1
                border.color: Theme.border

                Column {
                    anchors.centerIn: parent
                    width: parent.width - Theme.size(22)
                    spacing: Theme.size(3)

                    Text {
                        textFormat: Text.PlainText
                        width: parent.width
                        text: root.participantId.length > 0
                              ? qsTr("Pass to %1").arg(root.outgoingName)
                              : qsTr("Seat order")
                        color: Theme.primary
                        font.pixelSize: Theme.fontSize(11)
                        font.weight: Font.DemiBold
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                    }

                    Text {
                        textFormat: Text.PlainText
                        width: parent.width
                        visible: root.participantId.length > 0
                        text: qsTr("Receive from %1").arg(root.incomingName)
                        color: Theme.textMuted
                        font.pixelSize: Theme.fontSize(9)
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                    }
                }
            }

            Repeater {
                model: root.viewerRelativeSeats

                delegate: Rectangle {
                    id: seat
                    required property var modelData
                    readonly property real angle: Math.PI / 2
                                                          + 2 * Math.PI
                                                          * modelData.relativeIndex
                                                          / Math.max(1, root.viewerRelativeSeats.length)
                    width: Theme.size(88)
                    height: Theme.size(34)
                    x: seatArea.width / 2
                       + Math.cos(angle) * (seatArea.width / 2 - width / 2 - Theme.size(2))
                       - width / 2
                    y: seatArea.height / 2
                       + Math.sin(angle) * (seatArea.height / 2 - height / 2 - Theme.size(1))
                       - height / 2
                    radius: Theme.radiusMedium
                    color: modelData.isSelf ? Theme.primaryMuted
                           : modelData.isOutgoing ? Theme.accentMuted
                           : Theme.surfaceElevated
                    border.width: modelData.isSelf || modelData.isOutgoing ? 2 : 1
                    border.color: modelData.isSelf ? Theme.primary
                                  : modelData.isOutgoing ? Theme.accent
                                  : Theme.border

                    Column {
                        anchors.fill: parent
                        anchors.margins: Theme.size(4)
                        spacing: 0

                        Text {
                            textFormat: Text.PlainText
                            width: parent.width
                            text: seat.modelData.displayName
                            color: Theme.text
                            font.pixelSize: Theme.fontSize(9)
                            font.weight: seat.modelData.isSelf ? Font.Bold : Font.Medium
                            horizontalAlignment: Text.AlignHCenter
                            elide: Text.ElideRight
                        }

                        Text {
                            textFormat: Text.PlainText
                            width: parent.width
                            text: seat.modelData.isSelf
                                  ? qsTr("Seat %1 · You").arg(seat.modelData.seatNumber)
                                  : qsTr("Seat %1").arg(seat.modelData.seatNumber)
                            color: Theme.textMuted
                            font.pixelSize: Theme.fontSize(7)
                            horizontalAlignment: Text.AlignHCenter
                            elide: Text.ElideRight
                        }
                    }
                }
            }
        }
    }

    function findParticipantIndex(id) {
        for (let index = 0; index < participants.length; ++index) {
            if (participants[index].participantId === id)
                return index
        }
        return -1
    }

    function wrappedIndex(index) {
        const count = participants.length
        return count > 0 ? (index % count + count) % count : -1
    }

    function neighborName(offset) {
        if (selfIndex < 0 || participants.length === 0)
            return ""
        return participants[wrappedIndex(selfIndex + offset)].displayName
    }

    function buildViewerRelativeSeats() {
        const result = []
        const count = participants.length
        const anchor = selfIndex >= 0 ? selfIndex : 0
        const outgoing = selfIndex >= 0 ? wrappedIndex(selfIndex + direction) : -1
        for (let offset = 0; offset < count; ++offset) {
            const absoluteIndex = wrappedIndex(anchor + offset)
            const participant = participants[absoluteIndex]
            result.push({
                "participantId": participant.participantId,
                "displayName": participant.displayName,
                "seatNumber": absoluteIndex + 1,
                "relativeIndex": offset,
                "isSelf": absoluteIndex === selfIndex,
                "isOutgoing": absoluteIndex === outgoing
            })
        }
        return result
    }
}
