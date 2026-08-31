// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

Item {
    id: root

    required property var cardCatalogModel
    required property var sourceCardModel
    required property var targetModel
    required property string contextText
    readonly property bool hasContext: sourceList.count > 0
                                               || targetList.count > 0
                                               || contextText.length > 0
    readonly property int sourceCount: sourceList.count
    readonly property int targetCount: targetList.count

    objectName: "rulesPromptContext"
    visible: hasContext
    implicitHeight: visible ? Theme.size(112) : 0

    RowLayout {
        anchors.fill: parent
        spacing: Theme.size(9)

        ListView {
            id: sourceList

            Layout.preferredWidth: count > 0 ? Theme.size(76) : 0
            Layout.fillHeight: true
            orientation: ListView.Horizontal
            interactive: false
            model: root.sourceCardModel
            visible: count > 0

            delegate: Rectangle {
                id: sourceCard

                required property string name
                required property string setCode
                required property string collectorNumber

                width: sourceList.width
                height: sourceList.height
                radius: Theme.radiusSmall
                color: Theme.surfaceMuted
                border.width: 1
                border.color: Theme.primary
                clip: true

                Image {
                    id: sourceArt

                    anchors.fill: parent
                    anchors.margins: Theme.size(2)
                    asynchronous: true
                    fillMode: Image.PreserveAspectFit
                    source: {
                        if (!root.cardCatalogModel || !sourceCard.name
                                || typeof root.cardCatalogModel.tableImageSource
                                !== "function") {
                            return ""
                        }
                        void root.cardCatalogModel.imageRevision
                        return root.cardCatalogModel.tableImageSource(
                                    sourceCard.name, sourceCard.setCode,
                                    sourceCard.collectorNumber)
                    }
                }

                Text {
                    textFormat: Text.PlainText
                    anchors.centerIn: parent
                    width: parent.width - Theme.size(8)
                    visible: sourceArt.status !== Image.Ready
                    text: sourceCard.name
                    color: Theme.textSecondary
                    font.pixelSize: Theme.fontSize(8)
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                }

                ToolTip.visible: sourceHover.hovered
                ToolTip.delay: 350
                ToolTip.text: sourceCard.name
                HoverHandler { id: sourceHover }
            }
        }

        Text {
            textFormat: Text.PlainText
            objectName: "rulesPromptContextText"
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.contextText.length > 0
            text: root.contextText
            color: Theme.textSecondary
            font.pixelSize: Theme.fontSize(9)
            verticalAlignment: Text.AlignVCenter
            wrapMode: Text.Wrap
            maximumLineCount: 5
            elide: Text.ElideRight
        }

        ColumnLayout {
            Layout.preferredWidth: targetList.count > 0
                                   ? Math.min(Theme.size(360),
                                              targetList.contentWidth) : 0
            Layout.fillHeight: true
            visible: targetList.count > 0
            spacing: Theme.size(3)

            Text {
                textFormat: Text.PlainText
                Layout.fillWidth: true
                text: qsTr("Affects")
                color: Theme.textMuted
                font.pixelSize: Theme.fontSize(8)
                font.capitalization: Font.AllUppercase
            }

            ListView {
                id: targetList

                Layout.fillWidth: true
                Layout.fillHeight: true
                orientation: ListView.Horizontal
                spacing: Theme.size(6)
                clip: true
                model: root.targetModel

                delegate: Rectangle {
                    id: contextTarget

                    required property string kind
                    required property string label
                    required property string name
                    required property string setCode
                    required property string collectorNumber

                    width: Theme.size(72)
                    height: targetList.height
                    radius: Theme.radiusSmall
                    color: Theme.surfaceMuted
                    border.width: 1
                    border.color: Theme.border
                    clip: true

                    Image {
                        id: targetArt

                        anchors.fill: parent
                        anchors.margins: Theme.size(2)
                        asynchronous: true
                        fillMode: Image.PreserveAspectFit
                        visible: contextTarget.kind !== "player"
                        source: {
                            if (!visible || !root.cardCatalogModel
                                    || !contextTarget.name
                                    || typeof root.cardCatalogModel.tableImageSource
                                    !== "function") {
                                return ""
                            }
                            void root.cardCatalogModel.imageRevision
                            return root.cardCatalogModel.tableImageSource(
                                        contextTarget.name, contextTarget.setCode,
                                        contextTarget.collectorNumber)
                        }
                    }

                    Text {
                        textFormat: Text.PlainText
                        anchors.centerIn: parent
                        width: parent.width - Theme.size(8)
                        visible: contextTarget.kind === "player"
                                 || targetArt.status !== Image.Ready
                        text: contextTarget.label
                        color: Theme.textSecondary
                        font.pixelSize: Theme.fontSize(8)
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.Wrap
                    }

                    ToolTip.visible: targetHover.hovered
                    ToolTip.delay: 350
                    ToolTip.text: contextTarget.label
                    HoverHandler { id: targetHover }
                }
            }
        }
    }
}
