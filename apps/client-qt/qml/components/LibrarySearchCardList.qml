// SPDX-License-Identifier: GPL-2.0-only
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

    function resetFilter() {
        searchField.text = "";
    }

    function focusFilter() {
        searchField.forceActiveFocus();
    }

    Timer {
        id: filterTimer
        interval: 120
        repeat: false
        onTriggered: {
            root.popupController.filterQuery = searchField.text.trim().toLocaleLowerCase();
            root.popupController.selectedIndex = root.popupController.visibleCards.length > 0 ? 0 : -1;
        }
    }
    Layout.fillWidth: true
    Layout.fillHeight: true
    spacing: Theme.size(10)

    RowLayout {
        Layout.fillWidth: true
        visible: !root.popupController.reorderMode && !root.popupController.topCardMode
        spacing: Theme.size(8)

        AppTextField {
            id: searchField
            objectName: "librarySearchFilter"
            Layout.fillWidth: true
            implicitHeight: Theme.size(44)
            placeholderText: qsTr("Card name or type, in Chinese or English…")
            onTextEdited: filterTimer.restart()
        }
        AppButton {
            objectName: "selectAllLibraryCards"
            visible: !root.popupController.reorderMode && !root.popupController.topCardMode
            compact: true
            text: qsTr("Select all")
            onClicked: root.popupController.selectAllVisible()
        }
    }

    Item {
        Layout.fillWidth: true
        Layout.fillHeight: true

        ListView {
            id: cardList
            objectName: "librarySearchCards"
            anchors.fill: parent
            model: root.popupController.visibleCards
            spacing: Theme.size(7)
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar {
                policy: ScrollBar.AsNeeded
            }

            delegate: Surface {
                id: cardRow
                required property var modelData
                required property int index
                objectName: "librarySearchCard" + index
                width: ListView.view.width
                height: Theme.size(76)
                color: root.popupController.cardSelected(modelData.id) ? Theme.primaryMuted : Theme.surfaceMuted
                border.color: root.popupController.cardSelected(modelData.id) ? Theme.primary : Theme.border

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: Theme.size(7)
                    spacing: Theme.size(11)

                    Image {
                        Layout.preferredWidth: Theme.size(54)
                        Layout.fillHeight: true
                        source: root.popupController.cardCatalogModel ? root.popupController.cardCatalogModel.imageSource(cardRow.modelData.name, cardRow.modelData.setCode, cardRow.modelData.collectorNumber) : ""
                        fillMode: Image.PreserveAspectFit
                        asynchronous: true
                    }
                    Rectangle {
                        id: selectionBox
                        objectName: "librarySelectBox" + cardRow.index
                        visible: !root.popupController.topCardMode
                        Layout.preferredWidth: Theme.size(22)
                        Layout.preferredHeight: Theme.size(22)
                        radius: Theme.radiusSmall
                        color: root.popupController.cardSelected(cardRow.modelData.id) ? Theme.primary : "transparent"
                        border.width: 1
                        border.color: root.popupController.cardSelected(cardRow.modelData.id) ? Theme.primary : Theme.borderStrong
                        Text {
                            textFormat: Text.PlainText
                            anchors.centerIn: parent
                            text: "✓"
                            visible: root.popupController.cardSelected(cardRow.modelData.id)
                            color: Theme.primaryInk
                            font.pixelSize: Theme.fontSize(11)
                            font.weight: Font.Bold
                        }
                        TapHandler {
                            acceptedButtons: Qt.LeftButton
                            cursorShape: Qt.PointingHandCursor
                            onTapped: {
                                root.popupController.selectedIndex = cardRow.index;
                                root.popupController.toggleCard(cardRow.modelData.id);
                            }
                        }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: Theme.size(3)
                        Text {
                            textFormat: Text.PlainText
                            Layout.fillWidth: true
                            text: cardRow.modelData.name
                            color: Theme.text
                            font.pixelSize: Theme.fontSize(13)
                            font.weight: Font.Medium
                            elide: Text.ElideRight
                        }
                        Text {
                            textFormat: Text.PlainText
                            Layout.fillWidth: true
                            text: cardRow.modelData.setCode + " · #" + cardRow.modelData.collectorNumber
                            color: Theme.textMuted
                            font.pixelSize: Theme.fontSize(10)
                            elide: Text.ElideRight
                        }
                    }
                    AppButton {
                        visible: root.popupController.reorderMode
                        compact: true
                        variant: "ghost"
                        text: "↑"
                        enabled: cardRow.index > 0
                        onClicked: root.popupController.moveCardInOrder(cardRow.modelData.id, -1)
                    }
                    AppButton {
                        visible: root.popupController.reorderMode
                        compact: true
                        variant: "ghost"
                        text: "↓"
                        enabled: cardRow.index < root.popupController.visibleCards.length - 1
                        onClicked: root.popupController.moveCardInOrder(cardRow.modelData.id, 1)
                    }
                }

                TapHandler {
                    acceptedButtons: Qt.LeftButton
                    cursorShape: Qt.PointingHandCursor
                    onTapped: {
                        root.popupController.selectedIndex = cardRow.index;
                    }
                }
                TapHandler {
                    acceptedButtons: Qt.RightButton
                    enabled: !root.popupController.reorderMode
                    onTapped: function (point) {
                        root.popupController.selectedIndex = cardRow.index;
                        root.popupController.contextCardId = cardRow.modelData.id;
                        const position = cardRow.mapToItem(root.popupController.contentItem, point.position.x, point.position.y);
                        root.cardMenu.x = position.x;
                        root.cardMenu.y = position.y;
                        root.cardMenu.open();
                    }
                }
            }
        }

        Text {
            textFormat: Text.PlainText
            anchors.centerIn: parent
            visible: cardList.count === 0
            text: root.popupController.cards.length === 0 ? qsTr("Library is empty") : qsTr("No cards match this filter")
            color: Theme.textMuted
            font.pixelSize: Theme.fontSize(11)
        }
    }
}
