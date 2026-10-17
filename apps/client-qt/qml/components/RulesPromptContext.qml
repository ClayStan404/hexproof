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
    property int promptId: 0
    property bool contextEnabled: true
    property bool expandedCard: false
    property var previewBoundary: null
    property real cardHeight: Theme.size(280)
    readonly property bool hasContext: sourceList.count > 0
                                               || targetList.count > 0
                                               || contextText.length > 0
    readonly property int sourceCount: sourceList.count
    readonly property int targetCount: targetList.count
    readonly property bool narrowLayout: width < Theme.size(490)
    readonly property bool hasSourceContext: sourceList.count > 0 || contextText.length > 0

    objectName: "rulesPromptContext"
    visible: contextEnabled && hasContext
    implicitHeight: !visible ? 0
                    : expandedCard && sourceCount > 0
                      ? cardHeight + (targetCount > 0 ? Theme.size(121) : 0)
                    : narrowLayout && hasSourceContext && targetList.count > 0
                      ? Theme.size(233) : Theme.size(112)

    onPromptIdChanged: preview.hide()
    onVisibleChanged: if (!visible) preview.hide()
    onContextEnabledChanged: if (!contextEnabled) preview.hide()
    CardHoverPreview {
        id: preview
        objectName: "rulesPromptCardPreview"
        parent: Overlay.overlay
        catalogModel: root.cardCatalogModel
        placementBoundary: root.previewBoundary
        artObjectName: "rulesPromptCardPreviewArt"
    }

    GridLayout {
        anchors.fill: parent
        columns: root.expandedCard || root.narrowLayout ? 2 : 3
        columnSpacing: Theme.size(9)
        rowSpacing: Theme.size(9)

        ListView {
            id: sourceList

            Layout.row: 0
            Layout.column: 0
            Layout.columnSpan: root.expandedCard ? 2 : 1
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredHeight: root.expandedCard ? root.cardHeight : Theme.size(112)
            Layout.preferredWidth: count > 0 ? (root.expandedCard
                ? Math.min(root.width, root.cardHeight * 63 / 88) : Theme.size(76)) : 0
            Layout.fillHeight: true
            orientation: ListView.Horizontal
            interactive: false
            model: root.contextEnabled ? root.sourceCardModel : null
            visible: count > 0

            delegate: Rectangle {
                id: sourceCard

                required property string name
                required property string setCode
                required property string collectorNumber

                objectName: "rulesPromptSourceCard"
                activeFocusOnTab: root.contextEnabled
                Accessible.role: Accessible.StaticText
                Accessible.name: name + "\n" + root.contextText
                function inspect() {
                    if (!root.contextEnabled || !root.visible) return
                    preview.inspect({name:name, setCode:setCode, collectorNumber:collectorNumber,
                                     typeLine:root.contextText}, sourceCard)
                }
                onActiveFocusChanged: activeFocus ? inspect() : preview.hide(sourceCard)
                onNameChanged: preview.hide(sourceCard)
                Component.onDestruction: preview.hide(sourceCard)

                width: sourceList.width
                height: sourceList.height
                radius: Theme.radiusSmall
                color: Theme.surfaceMuted
                border.width: 1
                border.color: Theme.primary
                clip: true

                Image {
                    id: sourceArt
                    objectName: "rulesPromptSourceArt"

                    anchors.fill: parent
                    anchors.margins: Theme.size(2)
                    asynchronous: true
                    fillMode: Image.PreserveAspectFit
                    source: {
                        if (!root.visible || !root.cardCatalogModel || !sourceCard.name
                                || typeof root.cardCatalogModel.tableImageSource
                                !== "function") {
                            return ""
                        }
                        void root.cardCatalogModel.imageRevision
                        if (root.expandedCard && typeof root.cardCatalogModel.imageSource === "function")
                            return root.cardCatalogModel.imageSource(sourceCard.name,
                                sourceCard.setCode, sourceCard.collectorNumber)
                        return root.cardCatalogModel.tableImageSource(
                                    sourceCard.name, sourceCard.setCode,
                                    sourceCard.collectorNumber)
                    }
                }

                Text {
                    objectName: "rulesPromptSourceFallback"
                    textFormat: Text.PlainText
                    anchors.centerIn: parent
                    width: parent.width - Theme.size(12)
                    height: parent.height - Theme.size(12)
                    visible: sourceArt.status !== Image.Ready
                    text: root.expandedCard ? [sourceCard.name, root.contextText].filter(v => v.length).join("\n\n") : sourceCard.name
                    color: Theme.textSecondary
                    font.pixelSize: Theme.fontSize(root.expandedCard ? 14 : 8)
                    fontSizeMode: Text.Fit
                    minimumPixelSize: Theme.fontSize(9)
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    wrapMode: Text.Wrap
                }

                HoverHandler {
                    onHoveredChanged: hovered ? sourceCard.inspect() : preview.hide(sourceCard)
                }
            }
        }

        Text {
            textFormat: Text.PlainText
            objectName: "rulesPromptContextText"
            Layout.row: 0
            Layout.column: sourceList.count > 0 ? 1 : 0
            Layout.columnSpan: sourceList.count > 0 ? 1 : 2
            Layout.preferredHeight: Theme.size(112)
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.contextText.length > 0 && (!root.expandedCard || root.sourceCount === 0)
            text: root.contextText
            color: Theme.textSecondary
            font.pixelSize: Theme.fontSize(9)
            verticalAlignment: Text.AlignVCenter
            wrapMode: Text.Wrap
            maximumLineCount: 5
            elide: Text.ElideRight
        }

        ColumnLayout {
            Layout.row: (root.expandedCard || root.narrowLayout) && root.hasSourceContext ? 1 : 0
            Layout.column: root.expandedCard || root.narrowLayout ? 0 : 2
            Layout.columnSpan: root.expandedCard || root.narrowLayout ? 2 : 1
            Layout.fillWidth: root.expandedCard || root.narrowLayout
            Layout.preferredHeight: Theme.size(112)
            Layout.preferredWidth: root.narrowLayout ? -1 : targetList.count > 0
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

            RulesHorizontalListView {
                id: targetList
                objectName: "rulesPromptContextTargets"

                Layout.fillWidth: true
                Layout.fillHeight: true
                orientation: ListView.Horizontal
                spacing: Theme.size(6)
                clip: true
                model: root.contextEnabled ? root.targetModel : null

                delegate: Rectangle {
                    id: contextTarget

                    required property string kind
                    required property string label
                    required property string name
                    required property string setCode
                    required property string collectorNumber

                    width: Theme.size(72)
                    height: targetList.itemHeight
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
