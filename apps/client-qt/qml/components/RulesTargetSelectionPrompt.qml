// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

Item {
    id: root

    required property var wsModel
    required property var cardCatalogModel
    required property var targetModel
    required property int promptId
    required property int minimumSelections
    required property int maximumSelections
    required property bool cancellable
    property var selectedIds: ({})
    readonly property int selectedCount: Object.keys(selectedIds).length
    readonly property bool validSelection: selectedCount >= minimumSelections
                                                   && selectedCount <= maximumSelections

    implicitHeight: Theme.size(142)

    function resetSelection() {
        selectedIds = ({})
    }

    function toggleTarget(responseId) {
        const next = Object.assign({}, selectedIds)
        if (next[responseId] === true) {
            delete next[responseId]
        } else if (selectedCount < maximumSelections) {
            next[responseId] = true
        }
        selectedIds = next
    }

    function submit(responseId) {
        if (responseId === "$submit" && !validSelection)
            return
        wsModel.respondRulesPromptWithTargets(
                    promptId, responseId,
                    responseId === "$submit" ? Object.keys(selectedIds) : [])
    }

    function kindLabel(kind) {
        switch (kind) {
        case "player": return qsTr("Player")
        case "spell": return qsTr("Spell on stack")
        default: return qsTr("Permanent")
        }
    }

    onPromptIdChanged: resetSelection()

    RowLayout {
        anchors.fill: parent
        spacing: Theme.size(12)

        ListView {
            id: targetList

            Layout.fillWidth: true
            Layout.fillHeight: true
            orientation: ListView.Horizontal
            spacing: Theme.size(8)
            clip: true
            model: root.targetModel

            delegate: Rectangle {
                id: targetTile

                required property string responseId
                required property string kind
                required property string label
                required property string objectId
                required property string name
                required property string setCode
                required property string collectorNumber
                required property bool token
                readonly property bool selected: root.selectedIds[responseId] === true

                width: Theme.size(98)
                height: targetList.height
                radius: Theme.radiusSmall
                color: kind === "player" ? Theme.primaryMuted : Theme.surfaceMuted
                border.width: selected ? 3 : 1
                border.color: selected ? Theme.primary : Theme.border
                clip: true

                Image {
                    id: art

                    anchors.fill: parent
                    anchors.margins: Theme.size(3)
                    asynchronous: true
                    fillMode: Image.PreserveAspectFit
                    visible: targetTile.name.length > 0
                    source: {
                        if (!visible || !root.cardCatalogModel
                                || typeof root.cardCatalogModel.tableImageSource
                                !== "function") {
                            return ""
                        }
                        void root.cardCatalogModel.imageRevision
                        return root.cardCatalogModel.tableImageSource(
                                    targetTile.name, targetTile.setCode,
                                    targetTile.collectorNumber)
                    }
                }

                Column {
                    anchors.centerIn: parent
                    width: parent.width - Theme.size(12)
                    spacing: Theme.size(4)
                    visible: targetTile.kind === "player"
                             || (targetTile.name.length > 0
                                 && art.status !== Image.Ready)

                    Text {
                        textFormat: Text.PlainText
                        width: parent.width
                        text: root.kindLabel(targetTile.kind)
                        color: Theme.textMuted
                        font.pixelSize: Theme.fontSize(9)
                        horizontalAlignment: Text.AlignHCenter
                    }

                    Text {
                        textFormat: Text.PlainText
                        width: parent.width
                        text: targetTile.label
                        color: Theme.text
                        font.pixelSize: Theme.fontSize(10)
                        font.weight: Font.DemiBold
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.Wrap
                    }
                }

                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: Theme.size(28)
                    visible: targetTile.kind !== "player"
                    color: Theme.inactiveSelection

                    Text {
                        textFormat: Text.PlainText
                        anchors.fill: parent
                        anchors.margins: Theme.size(4)
                        text: targetTile.label
                        color: Theme.text
                        font.pixelSize: Theme.fontSize(8)
                        elide: Text.ElideRight
                        verticalAlignment: Text.AlignVCenter
                    }
                }

                Rectangle {
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: Theme.size(5)
                    width: Theme.size(24)
                    height: width
                    radius: width / 2
                    visible: targetTile.selected
                    color: Theme.primary

                    Text {
                        textFormat: Text.PlainText
                        anchors.centerIn: parent
                        text: "✓"
                        color: Theme.primaryInk
                        font.pixelSize: Theme.fontSize(12)
                        font.weight: Font.Bold
                    }
                }

                TapHandler {
                    onTapped: root.toggleTarget(targetTile.responseId)
                }

                HoverHandler { id: hover }
                ToolTip.visible: hover.hovered
                ToolTip.delay: 350
                ToolTip.text: root.kindLabel(targetTile.kind) + " · "
                              + targetTile.label
            }
        }

        ColumnLayout {
            Layout.preferredWidth: Theme.size(190)
            spacing: Theme.size(8)

            Text {
                textFormat: Text.PlainText
                Layout.fillWidth: true
                text: root.minimumSelections === root.maximumSelections
                      ? qsTr("Selected %1 of %2")
                        .arg(root.selectedCount).arg(root.maximumSelections)
                      : qsTr("Selected %1 · choose %2–%3")
                        .arg(root.selectedCount).arg(root.minimumSelections)
                        .arg(root.maximumSelections)
                color: root.validSelection ? Theme.success : Theme.textSecondary
                font.pixelSize: Theme.fontSize(11)
                horizontalAlignment: Text.AlignHCenter
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.size(6)

                AppButton {
                    Layout.fillWidth: true
                    compact: true
                    visible: root.cancellable
                    text: qsTr("Cancel")
                    onClicked: root.submit("$cancel")
                }

                AppButton {
                    Layout.fillWidth: true
                    compact: true
                    variant: "primary"
                    text: qsTr("Confirm targets")
                    enabled: root.validSelection
                    disabledReason: qsTr("Choose a valid number of targets")
                    onClicked: root.submit("$submit")
                }
            }
        }
    }
}
