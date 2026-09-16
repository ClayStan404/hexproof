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

    property alias randomizeTop: randomizeTopToggle.checked
    property alias randomizeBottom: randomizeBottomToggle.checked
    property alias reveal: revealToggle.checked

    Layout.preferredWidth: Math.min(Theme.size(340), popupController.availableWidth * 0.44)
    Layout.fillWidth: false
    Layout.minimumWidth: 0
    Layout.fillHeight: true
    spacing: Theme.size(12)

    function resetControls() {
        destinationBox.currentIndex = 0
        inspectorScroll.contentItem.contentY = 0
        randomizeTopToggle.checked = false
        randomizeBottomToggle.checked = false
        revealToggle.checked = root.popupController.topCount === 0
        topControls.resetControls()
    }

    ScrollView {
        id: inspectorScroll
        objectName: "libraryInspectorScroll"
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.minimumHeight: 0
        contentWidth: availableWidth
        clip: true
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

        ColumnLayout {
            width: inspectorScroll.availableWidth
            spacing: Theme.size(12)

            LibraryTopCardsControls {
                id: topControls
                Layout.fillWidth: true
                visible: root.popupController.reorderMode
                popupController: root.popupController
            }
            ColumnLayout {
                Layout.fillWidth: true
                visible: root.popupController.reorderMode
                spacing: Theme.size(7)

                Text {
                    textFormat: Text.PlainText
                    text: qsTr("Library order")
                    color: Theme.textSecondary
                    font.pixelSize: Theme.fontSize(10)
                    font.weight: Font.DemiBold
                }
                AppToggle {
                    id: randomizeTopToggle
                    objectName: "topCardsRandomizeTop"
                    Layout.fillWidth: true
                    text: qsTr("Randomize cards returning to the top")
                }
                AppToggle {
                    id: randomizeBottomToggle
                    objectName: "topCardsRandomizeBottom"
                    Layout.fillWidth: true
                    text: qsTr("Randomize cards returning to the bottom")
                }
            }

            Surface {
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(Theme.size(220),
                        Math.max(1, inspectorScroll.availableHeight - Theme.size(12)))
                color: Theme.surfaceMuted
                clip: true

                Image {
                    anchors.fill: parent
                    anchors.margins: Theme.size(12)
                    source: root.popupController.selectedCard.name
                            && root.popupController.cardCatalogModel
                            ? root.popupController.cardCatalogModel.imageSource(
                                  root.popupController.selectedCard.name,
                                  root.popupController.selectedCard.setCode,
                                  root.popupController.selectedCard.collectorNumber)
                            : ""
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                }
            }

            Text {
                textFormat: Text.PlainText
                Layout.fillWidth: true
                text: root.popupController.selectedCard.name
                      ? root.popupController.selectedCard.name
                      : qsTranslate("LibrarySearchPopup", "Select a card")
                color: Theme.text
                font.pixelSize: Theme.fontSize(14)
                font.weight: Font.DemiBold
                wrapMode: Text.WordWrap
            }

            ColumnLayout {
                Layout.fillWidth: true
                visible: root.popupController.reorderMode
                         && !!(root.popupController.selectedCard.id
                               && root.popupController.topCardAssignment(
                                   root.popupController.selectedCard.id).toZone === "battlefield")
                spacing: Theme.size(7)

                Text {
                    textFormat: Text.PlainText
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    text: qsTranslate("LibrarySearchPopup", "Face-down battlefield placement")
                    color: Theme.textSecondary
                    font.pixelSize: Theme.fontSize(10)
                    font.weight: Font.DemiBold
                }
                AppToggle {
                    objectName: "topCardsFaceDown"
                    Layout.fillWidth: true
                    visible: !!(root.popupController.selectedCard.id
                                && root.popupController.topCardAssignment(
                                    root.popupController.selectedCard.id).toZone
                                   === "battlefield")
                    checked: visible && root.popupController.topCardAssignment(
                                 root.popupController.selectedCard.id).faceDown === true
                    text: qsTranslate("LibrarySearchPopup", "Put this card onto the battlefield face down")
                    onToggled: root.popupController.setTopCardFaceDown(
                                   root.popupController.selectedCard.id, checked)
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                visible: !root.popupController.reorderMode
                         && !root.popupController.topCardMode
                         && root.popupController.selectedCount > 1
                spacing: Theme.size(5)

                Text {
                    textFormat: Text.PlainText
                    Layout.fillWidth: true
                    text: qsTranslate("LibrarySearchPopup", "Selected card order")
                    color: Theme.textSecondary
                    font.pixelSize: Theme.fontSize(10)
                    font.weight: Font.DemiBold
                }
                Text {
                    textFormat: Text.PlainText
                    Layout.fillWidth: true
                    text: qsTranslate("LibrarySearchPopup", "Use the arrows to choose the order sent to the destination.")
                    color: Theme.textMuted
                    font.pixelSize: Theme.fontSize(9)
                    wrapMode: Text.WordWrap
                }
                ListView {
                    objectName: "librarySelectedOrder"
                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.min(Theme.size(150), contentHeight)
                    model: root.popupController.selectedCardIdList()
                    spacing: Theme.size(3)
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    ScrollBar.vertical: ScrollBar {
                        policy: ScrollBar.AsNeeded
                    }

                    delegate: Surface {
                        id: selectedOrderRow
                        required property string modelData
                        required property int index
                        readonly property var card:
                            root.popupController.selectedCardForId(modelData)
                        width: ListView.view.width
                        height: Theme.size(36)
                        radius: Theme.radiusSmall
                        color: Theme.surfaceMuted

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: Theme.size(8)
                            anchors.rightMargin: Theme.size(4)
                            spacing: Theme.size(4)

                            Text {
                                textFormat: Text.PlainText
                                Layout.preferredWidth: Theme.size(22)
                                text: selectedOrderRow.index + 1
                                color: Theme.textMuted
                                font.pixelSize: Theme.fontSize(9)
                            }
                            Text {
                                textFormat: Text.PlainText
                                Layout.fillWidth: true
                                text: selectedOrderRow.card.name
                                      ? selectedOrderRow.card.name : ""
                                color: Theme.text
                                font.pixelSize: Theme.fontSize(10)
                                elide: Text.ElideRight
                            }
                            AppButton {
                                objectName: "librarySelectedMoveUp" + selectedOrderRow.index
                                implicitWidth: Theme.size(32)
                                compact: true
                                variant: "ghost"
                                text: "↑"
                                enabled: selectedOrderRow.index > 0
                                onClicked: root.popupController.moveSelectedCardInOrder(
                                               selectedOrderRow.modelData, -1)
                            }
                            AppButton {
                                objectName: "librarySelectedMoveDown" + selectedOrderRow.index
                                implicitWidth: Theme.size(32)
                                compact: true
                                variant: "ghost"
                                text: "↓"
                                enabled: selectedOrderRow.index
                                         < root.popupController.selectedCount - 1
                                onClicked: root.popupController.moveSelectedCardInOrder(
                                               selectedOrderRow.modelData, 1)
                            }
                        }
                    }
                }
            }

            Text {
                textFormat: Text.PlainText
                text: qsTranslate("LibrarySearchPopup", "Destination")
                visible: !root.popupController.reorderMode
                         && !root.popupController.topCardMode
                color: Theme.textSecondary
                font.pixelSize: Theme.fontSize(10)
                font.weight: Font.DemiBold
            }
            AppComboBox {
                id: destinationBox
                objectName: "libraryDestination"
                ToolTip.visible: hovered
                ToolTip.text: displayText
                Layout.fillWidth: true
                model: root.popupController.destinations
                textRole: "label"
                valueRole: "value"
                visible: !root.popupController.reorderMode
                         && !root.popupController.topCardMode
            }

            AppToggle {
                id: revealToggle
                objectName: "revealLibrarySearch"
                Layout.fillWidth: true
                checked: true
                text: qsTranslate("LibrarySearchPopup", "Reveal card name in the game log")
                visible: !root.popupController.reorderMode
                         && !root.popupController.topCardMode
            }
            Text {
                textFormat: Text.PlainText
                Layout.fillWidth: true
                text: revealToggle.checked
                      ? qsTranslate("LibrarySearchPopup", "Every viewer will see the selected card name in the log.")
                      : qsTranslate("LibrarySearchPopup", "The log will say “a card”; hidden-zone identities stay private.")
                color: Theme.textMuted
                font.pixelSize: Theme.fontSize(9)
                wrapMode: Text.WordWrap
                visible: !root.popupController.reorderMode
                         && !root.popupController.topCardMode
            }
        }
    }

    AppButton {
        objectName: "completeLibrarySearchButton"
        Layout.fillWidth: true
        visible: !root.popupController.topCardMode
        variant: "primary"
        text: root.popupController.reorderMode
              ? qsTranslate("LibrarySearchPopup", "Resolve top cards")
              : qsTranslate("LibrarySearchPopup", "Complete search")
        enabled: root.popupController.reorderMode
                 ? root.popupController.cards.length > 0
                 : root.popupController.selectedCount > 0
        onClicked: {
            if (root.popupController.reorderMode) {
                root.popupController.resolveTopCards()
                return
            }
            const option = root.popupController.destinations[
                               destinationBox.currentIndex]
            if (option)
                root.popupController.completeSearch(option.value, option.seat,
                                                    false)
        }
    }
    StatusPill {
        visible: !root.popupController.reorderMode
                 && !root.popupController.topCardMode
        text: qsTranslate("LibrarySearchPopup", "Selected") + " · " + root.popupController.selectedCount
        statusColor: Theme.primary
    }
}
