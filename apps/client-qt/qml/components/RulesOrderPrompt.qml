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
    required property var orderModel
    required property int promptId
    property bool damageOrder: false

    readonly property bool narrowLayout: width < Theme.size(490)

    implicitHeight: narrowLayout
                    ? Theme.size(230) + selectionControls.implicitHeight
                    : Math.max(Theme.size(218), selectionControls.implicitHeight)

    function resetOrder() {
        visualOrder.clear()
        if (!orderModel || typeof orderModel.items !== "function")
            return
        const sourceItems = orderModel.items()
        for (let index = 0; index < sourceItems.length; ++index)
            visualOrder.append(sourceItems[index])
    }

    function moveItem(fromIndex, toIndex) {
        if (fromIndex < 0 || toIndex < 0 || fromIndex >= visualOrder.count
                || toIndex >= visualOrder.count || fromIndex === toIndex)
            return
        visualOrder.move(fromIndex, toIndex, 1)
        Qt.callLater(function() { orderList.positionViewAtIndex(toIndex, ListView.Contain) })
    }

    function submitOrder() {
        const orderedIds = []
        for (let index = 0; index < visualOrder.count; ++index)
            orderedIds.push(visualOrder.get(index).responseId)
        if (damageOrder)
            wsModel.respondRulesPromptWithDamageOrder(promptId, orderedIds)
        else
            wsModel.respondRulesPromptWithOrder(promptId, orderedIds)
    }

    onPromptIdChanged: resetOrder()
    onOrderModelChanged: resetOrder()
    Component.onCompleted: resetOrder()

    ListModel { id: visualOrder }

    GridLayout {
        anchors.fill: parent
        columns: root.narrowLayout ? 1 : 2
        columnSpacing: Theme.size(12)
        rowSpacing: Theme.size(12)

        RulesHorizontalListView {
            id: orderList
            objectName: "rulesOrderCandidates"

            Layout.fillWidth: true
            Layout.preferredHeight: Theme.size(218)
            Layout.fillHeight: true
            spacing: Theme.size(10)
            model: visualOrder
            move: Transition {
                NumberAnimation {
                    properties: "x,y"
                    duration: 150
                    easing.type: Easing.OutCubic
                }
            }
            moveDisplaced: Transition {
                NumberAnimation {
                    properties: "x,y"
                    duration: 150
                    easing.type: Easing.OutCubic
                }
            }

            delegate: Item {
                id: tile

                required property int index
                required property string responseId
                required property string name
                required property string setCode
                required property string collectorNumber
                required property bool token
                required property string oracle

                width: Theme.size(112)
                height: orderList.itemHeight
                z: dragArea.drag.active ? 2 : 0

                Rectangle {
                    anchors.fill: parent
                    radius: Theme.radiusSmall
                    color: Theme.surfaceMuted
                    border.width: dragArea.drag.active ? 3 : 1
                    border.color: dragArea.drag.active ? Theme.primary : Theme.border
                    clip: true

                    Image {
                        id: art

                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.bottom: oraclePanel.top
                        anchors.margins: Theme.size(4)
                        asynchronous: true
                        fillMode: Image.PreserveAspectFit
                        source: {
                            if (!root.cardCatalogModel || !tile.name
                                    || typeof root.cardCatalogModel.tableImageSource
                                    !== "function") {
                                return ""
                            }
                            void root.cardCatalogModel.imageRevision
                            return root.cardCatalogModel.tableImageSource(
                                        tile.name, tile.setCode,
                                        tile.collectorNumber)
                        }
                    }

                    Text {
                        textFormat: Text.PlainText
                        anchors.centerIn: art
                        width: art.width - Theme.size(8)
                        visible: art.status !== Image.Ready
                        text: tile.name.length > 0 ? tile.name : qsTr("Unknown card")
                        color: Theme.textSecondary
                        font.pixelSize: Theme.fontSize(9)
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.Wrap
                    }

                    Rectangle {
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.margins: Theme.size(5)
                        width: Theme.size(24)
                        height: width
                        radius: width / 2
                        color: tile.index === 0 ? Theme.primary : Theme.surfaceElevated

                        Text {
                            textFormat: Text.PlainText
                            anchors.centerIn: parent
                            text: String(tile.index + 1)
                            color: tile.index === 0 ? Theme.primaryInk : Theme.text
                            font.pixelSize: Theme.fontSize(10)
                            font.weight: Font.Bold
                        }
                    }

                    Rectangle {
                        id: oraclePanel

                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: itemControls.top
                        height: visible ? Theme.size(42) : 0
                        visible: tile.oracle.length > 0
                        color: Theme.inactiveSelection

                        Text {
                            textFormat: Text.PlainText
                            anchors.fill: parent
                            anchors.margins: Theme.size(4)
                            text: tile.oracle
                            color: Theme.textSecondary
                            font.pixelSize: Theme.fontSize(7)
                            maximumLineCount: 2
                            elide: Text.ElideRight
                            wrapMode: Text.Wrap
                        }
                    }

                    RowLayout {
                        id: itemControls

                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.margins: Theme.size(4)
                        height: Theme.size(30)
                        spacing: Theme.size(3)

                        AppButton {
                            Layout.preferredWidth: Theme.size(30)
                            compact: true
                            text: "‹"
                            enabled: tile.index > 0
                            onClicked: root.moveItem(tile.index, tile.index - 1)
                        }

                        Text {
                            textFormat: Text.PlainText
                            Layout.fillWidth: true
                            text: tile.name.length > 0 ? tile.name : qsTr("Unknown card")
                            color: Theme.text
                            font.pixelSize: Theme.fontSize(8)
                            horizontalAlignment: Text.AlignHCenter
                            elide: Text.ElideRight
                        }

                        AppButton {
                            Layout.preferredWidth: Theme.size(30)
                            compact: true
                            text: "›"
                            enabled: tile.index + 1 < visualOrder.count
                            onClicked: root.moveItem(tile.index, tile.index + 1)
                        }
                    }
                }

                MouseArea {
                    id: dragArea

                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: Theme.size(38)
                    cursorShape: drag.active ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                    preventStealing: true
                    drag.target: tile
                    drag.axis: Drag.XAxis
                    drag.minimumX: 0
                    drag.maximumX: Math.max(0, orderList.contentWidth - tile.width)
                    onReleased: {
                        const step = tile.width + orderList.spacing
                        const destination = Math.max(0, Math.min(
                            visualOrder.count - 1, Math.round(tile.x / step)))
                        const source = tile.index
                        if (source !== destination)
                            root.moveItem(source, destination)
                        Qt.callLater(function() { orderList.forceLayout() })
                    }
                }

                HoverHandler { id: hover }
                ToolTip.visible: hover.hovered
                ToolTip.delay: 350
                ToolTip.text: tile.oracle.length > 0
                              ? tile.name + "\n" + tile.oracle : tile.name
            }
        }

        ColumnLayout {
            id: selectionControls

            Layout.fillWidth: root.narrowLayout
            Layout.preferredWidth: root.narrowLayout ? -1 : Theme.size(190)
            spacing: Theme.size(8)

            Text {
                textFormat: Text.PlainText
                Layout.fillWidth: true
                text: qsTr("Drag cards or use the arrows to set their order. Item 1 goes first.")
                color: Theme.textSecondary
                font.pixelSize: Theme.fontSize(10)
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
            }

            AppButton {
                objectName: "rulesConfirmOrder"
                Layout.fillWidth: true
                variant: "primary"
                text: qsTr("Confirm order")
                onClicked: root.submitOrder()
            }
        }
    }
}
