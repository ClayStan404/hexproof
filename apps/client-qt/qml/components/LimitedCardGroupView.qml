// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

Item {
    id: root

    required property var groups
    required property var catalogModel
    property string actionText: ""
    property string emptyText: ""
    property bool emphasized: false
    property real cardWidth: Theme.size(116)
    property real cardHeight: Theme.size(168)
    signal cardActivated(string instanceId)
    signal cardInspected(var card, var sourceItem)
    signal cardInspectionEnded(var sourceItem)

    Text {
        textFormat: Text.PlainText
        anchors.centerIn: parent
        width: parent.width - Theme.size(24)
        visible: root.groups.length === 0
        text: root.emptyText
        color: Theme.textMuted
        font.pixelSize: Theme.fontSize(11)
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.Wrap
    }

    ScrollView {
        id: scrollView
        anchors.fill: parent
        visible: root.groups.length > 0
        contentWidth: availableWidth
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

        Column {
            width: scrollView.availableWidth
            spacing: Theme.size(10)

            Repeater {
                model: root.groups

                delegate: Column {
                    id: groupColumn

                    required property var modelData
                    width: parent ? parent.width : 0
                    spacing: Theme.size(6)

                    RowLayout {
                        width: parent.width
                        spacing: Theme.size(7)

                        Text {
                            textFormat: Text.PlainText
                            text: groupColumn.modelData.label
                            color: Theme.textSecondary
                            font.pixelSize: Theme.fontSize(10)
                            font.weight: Font.DemiBold
                        }

                        StatusPill {
                            text: String(groupColumn.modelData.cards.length)
                            statusColor: Theme.accent
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: 1
                            color: Theme.border
                        }
                    }

                    Flow {
                        width: parent.width
                        height: childrenRect.height
                        spacing: Theme.size(8)

                        Repeater {
                            model: groupColumn.modelData.cards

                            delegate: LimitedCardTile {
                                id: cardTile

                                required property var modelData
                                objectName: "limitedCardTile-"
                                            + modelData.instanceId
                                width: root.cardWidth
                                height: root.cardHeight
                                card: modelData
                                catalogModel: root.catalogModel
                                emphasized: root.emphasized
                                actionText: root.actionText
                                onActivated: root.cardActivated(modelData.instanceId)
                                onInspectionRequested:
                                    root.cardInspected(modelData, cardTile)
                                onInspectionEnded:
                                    root.cardInspectionEnded(cardTile)
                            }
                        }
                    }
                }
            }
        }
    }
}
