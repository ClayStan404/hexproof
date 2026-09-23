// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

pragma ComponentBehavior: Bound
pragma Translator: "LibrarySearchPopup"

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

ColumnLayout {
    id: root

    required property var popupController
    required property var cardMenu
    property string draggedCardId: ""
    property string dropCardId: ""
    property bool dropAfter: false
    property bool dragging: false
    property point dragPoint: Qt.point(0, 0)
    property point pressPoint: Qt.point(0, 0)

    Layout.fillWidth: true
    Layout.fillHeight: true
    Layout.minimumWidth: 0
    spacing: Theme.size(8)

    function rowHeaderHeight(row) {
        return row.groupIndex === 0 ? Theme.size(56) : 0
    }

    function updateDropTarget() {
        dropCardId = ""
        const point = root.mapToItem(cardList, dragPoint.x, dragPoint.y)
        if (point.x < 0 || point.x > cardList.width || point.y < 0 || point.y > cardList.height)
            return
        const index = cardList.indexAt(point.x + cardList.contentX,
                                      point.y + cardList.contentY)
        const row = cardList.itemAtIndex(index)
        const data = popupController.topCardRows[index]
        if (!row || !data || data.card.id === draggedCardId
            || data.destination !== popupController.topCardAssignment(draggedCardId).toZone)
            return
        const local = root.mapToItem(row, dragPoint.x, dragPoint.y)
        const headerHeight = rowHeaderHeight(data)
        if (local.y < headerHeight)
            return
        dropCardId = data.card.id
        dropAfter = local.y > headerHeight + (row.height - headerHeight) / 2
    }

    function cancelDrag() {
        dragging = false
        draggedCardId = ""
        dropCardId = ""
    }

    function finishDrag() {
        const cardId = draggedCardId
        const targetId = dropCardId
        const after = dropAfter
        const move = dragging && targetId.length > 0
        cancelDrag()
        // Let the input handler finish before replacing its delegate model.
        if (move)
            Qt.callLater(() => popupController.moveTopCardRelative(cardId, targetId, after))
    }

    onVisibleChanged: {
        if (!visible)
            cancelDrag()
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: Theme.size(6)

        AppButton {
            objectName: "selectAllTopCards"
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            implicitWidth: Theme.size(68)
            compact: true
            text: qsTr("All")
            accessibleName: qsTr("Select all")
            onClicked: root.popupController.selectAllVisible()
        }
        AppButton {
            objectName: "clearTopCardSelection"
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            implicitWidth: Theme.size(68)
            compact: true
            text: qsTr("None")
            accessibleName: qsTr("Deselect all")
            enabled: root.popupController.selectedCount > 0
            onClicked: {
                root.popupController.selectedOrder = []
                root.popupController.topSelectionAnchor = ""
            }
        }
        AppButton {
            objectName: "invertTopCardSelection"
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            implicitWidth: Theme.size(68)
            compact: true
            text: qsTr("Invert")
            accessibleName: qsTr("Invert selection")
            onClicked: root.popupController.invertTopSelection()
        }
    }

    ListView {
        id: cardList
        objectName: "libraryTopCardsList"
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.minimumHeight: 0
        model: root.popupController.topCardRows
        spacing: Theme.size(5)
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        delegate: Item {
            id: cardRow
            required property var modelData
            readonly property bool compact: width < Theme.size(360)
            readonly property real headerHeight: root.rowHeaderHeight(modelData)
            readonly property bool randomized: root.popupController.topGroupRandomized(modelData.destination)
            width: ListView.view.width
            height: headerHeight + Theme.size(66)

            Column {
                width: parent.width
                height: cardRow.headerHeight
                visible: cardRow.modelData.groupIndex === 0
                topPadding: Theme.size(5)
                spacing: Theme.size(3)

                Text {
                    textFormat: Text.PlainText
                    width: parent.width
                    elide: Text.ElideRight
                    text: root.popupController.topDestinationLabel(cardRow.modelData.destination)
                          + " · " + cardRow.modelData.groupSize
                    color: Theme.text
                    font.pixelSize: Theme.fontSize(12)
                    font.weight: Font.DemiBold
                }
                Text {
                    textFormat: Text.PlainText
                    width: parent.width
                    elide: Text.ElideRight
                    text: cardRow.randomized ? qsTr("Random order")
                          : (cardRow.modelData.destination === "library_top"
                             ? qsTr("First card is drawn next")
                             : (cardRow.modelData.destination === "library_bottom"
                                ? qsTr("Last card is bottommost") : qsTr("In order")))
                    color: Theme.textMuted
                    font.pixelSize: Theme.fontSize(10)
                }
            }

            Surface {
                id: cardSurface
                objectName: "topCardRow_" + cardRow.modelData.card.id
                y: cardRow.headerHeight
                width: parent.width
                height: Theme.size(66)
                color: root.popupController.cardSelected(cardRow.modelData.card.id)
                       ? Theme.primaryMuted : Theme.surfaceMuted
                border.color: root.popupController.selectedCard.id === cardRow.modelData.card.id
                              ? Theme.primary : Theme.border
                opacity: root.dragging && root.draggedCardId === cardRow.modelData.card.id ? 0.4 : 1

                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onClicked: function(mouse) {
                        root.popupController.selectedIndex = cardRow.modelData.sourceIndex
                        if (mouse.button === Qt.RightButton) {
                            root.popupController.contextCardId = cardRow.modelData.card.id
                            const point = mapToItem(root.popupController.contentItem, mouse.x, mouse.y)
                            root.cardMenu.x = point.x
                            root.cardMenu.y = point.y
                            root.cardMenu.open()
                        }
                    }
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: Theme.size(6)
                    spacing: Theme.size(5)

                    CheckBox {
                        id: selectionBox
                        objectName: "topCardSelect_" + cardRow.modelData.card.id
                        Layout.preferredWidth: Theme.size(32)
                        Layout.preferredHeight: Theme.size(40)
                        padding: 0
                        checked: root.popupController.cardSelected(cardRow.modelData.card.id)
                        Accessible.name: cardRow.modelData.card.name
                        onClicked: root.popupController.selectTopCard(cardRow.modelData.card.id, false)
                        indicator: Rectangle {
                            anchors.centerIn: parent
                            width: Theme.size(22)
                            height: width
                            radius: Theme.radiusSmall
                            color: selectionBox.checked ? Theme.primary : "transparent"
                            border.width: 1
                            border.color: selectionBox.activeFocus ? Theme.primary : Theme.borderStrong
                            Text {
                                textFormat: Text.PlainText
                                anchors.centerIn: parent
                                text: selectionBox.checked ? "✓" : ""
                                color: Theme.primaryInk
                                font.pixelSize: Theme.fontSize(11)
                            }
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: function(mouse) {
                                selectionBox.forceActiveFocus()
                                root.popupController.selectedIndex = cardRow.modelData.sourceIndex
                                root.popupController.selectTopCard(cardRow.modelData.card.id,
                                                                    (mouse.modifiers & Qt.ShiftModifier) !== 0)
                            }
                        }
                    }

                    Image {
                        visible: cardRow.width >= Theme.size(450)
                        Layout.preferredWidth: Theme.size(38)
                        Layout.fillHeight: true
                        source: root.popupController.cardCatalogModel
                                ? root.popupController.cardCatalogModel.imageSource(
                                      cardRow.modelData.card.name, cardRow.modelData.card.setCode,
                                      cardRow.modelData.card.collectorNumber) : ""
                        fillMode: Image.PreserveAspectFit
                        asynchronous: true
                    }

                    ColumnLayout {
                        objectName: "topCardIdentity_" + cardRow.modelData.card.id
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        spacing: Theme.size(3)
                        Text {
                            textFormat: Text.PlainText
                            Layout.fillWidth: true
                            text: cardRow.modelData.card.name
                            color: Theme.text
                            font.pixelSize: Theme.fontSize(12)
                            elide: Text.ElideRight
                        }
                        Text {
                            objectName: "topCardStatus_" + cardRow.modelData.card.id
                            readonly property bool assigned:
                                !!root.popupController.topCardAssignments[cardRow.modelData.card.id]
                            readonly property bool faceDown:
                                root.popupController.topCardAssignment(cardRow.modelData.card.id).faceDown === true
                            readonly property bool revealed:
                                !faceDown && root.popupController.topCardAssignment(
                                    cardRow.modelData.card.id).reveal === true
                            textFormat: Text.PlainText
                            Layout.fillWidth: true
                            visible: assigned || faceDown
                            text: [assigned ? qsTr("Assigned") : "",
                                   faceDown ? qsTr("Face down") : "",
                                   revealed ? qsTr("Reveal in log") : ""]
                                  .filter(label => label.length > 0).join(" · ")
                            color: Theme.textMuted
                            font.pixelSize: Theme.fontSize(9)
                            elide: Text.ElideRight
                        }
                    }

                    Text {
                        textFormat: Text.PlainText
                        visible: !cardRow.compact
                        Layout.preferredWidth: Theme.size(22)
                        text: cardRow.randomized ? "–" : cardRow.modelData.groupIndex + 1
                        horizontalAlignment: Text.AlignHCenter
                        color: Theme.textMuted
                        font.pixelSize: Theme.fontSize(10)
                    }
                    GridLayout {
                        columns: cardRow.compact ? 1 : 2
                        rowSpacing: 0
                        columnSpacing: Theme.size(5)
                        AppButton {
                            objectName: "topCardUp_" + cardRow.modelData.card.id
                            implicitWidth: Theme.size(30)
                            implicitHeight: Theme.size(cardRow.compact ? 24 : 38)
                            compact: true
                            variant: "ghost"
                            text: "↑"
                            accessibleName: qsTr("Move card up")
                            enabled: cardRow.modelData.groupIndex > 0 && !cardRow.randomized
                            onClicked: root.popupController.moveTopCardInGroup(cardRow.modelData.card.id, -1)
                        }
                        AppButton {
                            objectName: "topCardDown_" + cardRow.modelData.card.id
                            implicitWidth: Theme.size(30)
                            implicitHeight: Theme.size(cardRow.compact ? 24 : 38)
                            compact: true
                            variant: "ghost"
                            text: "↓"
                            accessibleName: qsTr("Move card down")
                            enabled: cardRow.modelData.groupIndex < cardRow.modelData.groupSize - 1 && !cardRow.randomized
                            onClicked: root.popupController.moveTopCardInGroup(cardRow.modelData.card.id, 1)
                        }
                    }
                    Item {
                        objectName: "topCardDrag_" + cardRow.modelData.card.id
                        Layout.preferredWidth: Theme.size(28)
                        Layout.fillHeight: true
                        Text {
                            textFormat: Text.PlainText
                            anchors.centerIn: parent
                            text: "☰"
                            color: cardRow.modelData.groupSize > 1 && !cardRow.randomized
                                   ? Theme.textSecondary : Theme.textDisabled
                            font.pixelSize: Theme.fontSize(15)
                        }
                    }
                }

                Rectangle {
                    visible: root.dragging && root.dropCardId === cardRow.modelData.card.id
                    width: parent.width
                    height: Theme.size(3)
                    y: root.dropAfter ? parent.height - height : 0
                    color: Theme.primary
                }
            }
        }

        Surface {
            visible: root.dragging
            x: Math.max(0, Math.min(root.width - width, root.dragPoint.x - width + Theme.size(16)))
            y: root.mapToItem(cardList, root.dragPoint.x, root.dragPoint.y).y - height - Theme.size(12)
            width: Math.min(Theme.size(230), root.width)
            height: Theme.size(38)
            z: 10
            opacity: 0.9
            color: Theme.primaryMuted
            border.color: Theme.primary
            Text {
                textFormat: Text.PlainText
                anchors.fill: parent
                anchors.margins: Theme.size(8)
                text: root.popupController.selectedCardForId(root.draggedCardId).name || ""
                color: Theme.text
                font.pixelSize: Theme.fontSize(11)
                elide: Text.ElideRight
                verticalAlignment: Text.AlignVCenter
            }
        }

        // Keep the pointer grab outside recycled delegates during auto-scroll.
        MouseArea {
            objectName: "libraryTopDragArea"
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.right: parent.right
            anchors.rightMargin: Theme.size(6)
            width: Theme.size(28)
            cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
            preventStealing: true
            onPressed: function(mouse) {
                const point = mapToItem(cardList, mouse.x, mouse.y)
                const index = cardList.indexAt(point.x + cardList.contentX, point.y + cardList.contentY)
                const row = cardList.itemAtIndex(index)
                const data = root.popupController.topCardRows[index]
                if (!row || !data || data.groupSize < 2
                    || root.popupController.topGroupRandomized(data.destination)
                    || mapToItem(row, mouse.x, mouse.y).y < root.rowHeaderHeight(data)) {
                    mouse.accepted = false
                    return
                }
                root.draggedCardId = data.card.id
                root.pressPoint = mapToItem(root, mouse.x, mouse.y)
                root.dragPoint = root.pressPoint
            }
            onPositionChanged: function(mouse) {
                if (!pressed)
                    return
                root.dragPoint = mapToItem(root, mouse.x, mouse.y)
                if (Math.abs(root.dragPoint.y - root.pressPoint.y) > Theme.size(6))
                    root.dragging = true
                if (root.dragging)
                    root.updateDropTarget()
            }
            onReleased: root.finishDrag()
            onCanceled: root.cancelDrag()
        }
    }

    Timer {
        interval: 50
        repeat: true
        running: root.dragging
        onTriggered: {
            const point = root.mapToItem(cardList, root.dragPoint.x, root.dragPoint.y)
            if (point.x < 0 || point.x > cardList.width)
                return
            const edge = Theme.size(30)
            const delta = point.y < edge ? -Theme.size(12)
                          : (point.y > cardList.height - edge ? Theme.size(12) : 0)
            if (delta !== 0) {
                cardList.contentY = Math.max(cardList.originY,
                        Math.min(cardList.originY + Math.max(0, cardList.contentHeight - cardList.height),
                                 cardList.contentY + delta))
                root.updateDropTarget()
            }
        }
    }


}
