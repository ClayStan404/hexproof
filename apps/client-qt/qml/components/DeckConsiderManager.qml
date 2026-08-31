// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

Popup {
    id: root

    required property var deckLibraryModel
    required property var catalogModel
    property string filterText: ""
    property int sortModeIndex: 0
    readonly property var sortOptions: [qsTr("Name"), qsTr("Mana value"), qsTr("Card type")]
    readonly property var visibleCards: sortedCards()
    signal addRequested()

    parent: Overlay.overlay
    x: Math.round((parent.width - width) / 2)
    y: Math.round((parent.height - height) / 2)
    width: Math.min(Theme.size(1120), parent.width - Theme.size(48))
    height: Math.min(Theme.size(760), parent.height - Theme.size(56))
    padding: Theme.size(24)
    modal: true
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

    Overlay.modal: Rectangle { color: "#A6050B09" }

    background: Rectangle {
        color: Theme.surfaceElevated
        radius: Theme.radiusLarge
        border.width: 1
        border.color: Theme.borderStrong
    }

    contentItem: ColumnLayout {
        spacing: Theme.size(13)

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.size(12)

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Theme.size(3)

                Text {
                    textFormat: Text.PlainText
                    text: qsTr("Consider")
                    color: Theme.text
                    font.pixelSize: Theme.fontSize(22)
                    font.weight: Font.DemiBold
                }

                Text {
                    textFormat: Text.PlainText
                    Layout.fillWidth: true
                    text: qsTr("Keep possible changes here, then move one copy into the main deck when needed.")
                    color: Theme.textSecondary
                    font.pixelSize: Theme.fontSize(12)
                    wrapMode: Text.WordWrap
                }
            }

            StatusPill {
                text: qsTr("%n card(s)", "", root.deckLibraryModel.currentConsiderCount)
                statusColor: root.deckLibraryModel.currentConsiderCount > 0
                             ? Theme.primary : Theme.textMuted
            }

            AppButton {
                objectName: "addConsiderCardButton"
                variant: "primary"
                text: qsTr("Add card")
                enabled: root.catalogModel.installed
                onClicked: root.addRequested()
            }

            AppButton {
                compact: true
                variant: "ghost"
                text: "×"
                accessibleName: qsTr("Close")
                Layout.preferredWidth: Theme.size(40)
                onClicked: root.close()
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.size(10)

            AppTextField {
                objectName: "considerFilterField"
                Layout.fillWidth: true
                placeholderText: qsTr("Search Consider…")
                onTextEdited: root.filterText = text
            }

            AppComboBox {
                objectName: "considerSortMode"
                Layout.preferredWidth: Theme.size(176)
                model: root.sortOptions
                currentIndex: root.sortModeIndex
                displayText: qsTr("Sort: %1").arg(currentText)
                onActivated: index => root.sortModeIndex = index
            }
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 1
            color: Theme.divider
        }

        GridView {
            id: considerGrid
            objectName: "considerCardGrid"
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.visibleCards.length > 0
            model: root.visibleCards
            cellWidth: Theme.size(204)
            cellHeight: Theme.size(304)
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

            delegate: Item {
                id: considerCell
                required property var modelData
                width: considerGrid.cellWidth
                height: considerGrid.cellHeight

                DeckVisualCard {
                    anchors.fill: parent
                    anchors.margins: Theme.size(5)
                    card: considerCell.modelData
                    catalogModel: root.catalogModel
                    incrementEnabled: root.deckLibraryModel.canAddCard(
                                          considerCell.modelData.name,
                                          considerCell.modelData.typeLine)
                    moveText: qsTr("To main")
                    onIncrementRequested: root.deckLibraryModel.changeConsiderCardCount(
                                              considerCell.modelData.name,
                                              considerCell.modelData.setCode,
                                              considerCell.modelData.collectorNumber, 1)
                    onDecrementRequested: root.deckLibraryModel.changeConsiderCardCount(
                                              considerCell.modelData.name,
                                              considerCell.modelData.setCode,
                                              considerCell.modelData.collectorNumber, -1)
                    onMoveRequested: root.deckLibraryModel.moveConsiderCardToMain(
                                         considerCell.modelData.name,
                                         considerCell.modelData.setCode,
                                         considerCell.modelData.collectorNumber)
                }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.visibleCards.length === 0
            spacing: Theme.size(9)

            Item { Layout.fillHeight: true }

            Text {
                textFormat: Text.PlainText
                Layout.alignment: Qt.AlignHCenter
                text: root.filterText.trim().length > 0
                      ? qsTr("No Consider cards match this search")
                      : qsTr("No cards in Consider")
                color: Theme.text
                font.pixelSize: Theme.fontSize(17)
                font.weight: Font.DemiBold
            }

            Text {
                textFormat: Text.PlainText
                Layout.alignment: Qt.AlignHCenter
                Layout.maximumWidth: Theme.size(500)
                text: qsTr("Add cards you may want to try without changing the registered deck.")
                color: Theme.textMuted
                font.pixelSize: Theme.fontSize(12)
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
            }

            AppButton {
                Layout.alignment: Qt.AlignHCenter
                variant: "primary"
                text: qsTr("Add card")
                enabled: root.catalogModel.installed
                onClicked: root.addRequested()
            }

            Item { Layout.fillHeight: true }
        }
    }

    function sortedCards() {
        const query = filterText.trim().toLocaleLowerCase()
        const cards = []
        for (let index = 0; index < deckLibraryModel.considerCards.length; ++index) {
            const card = deckLibraryModel.considerCards[index]
            const haystack = [card.name || "", card.displayName || "",
                              card.typeLine || "", card.setCode || ""]
                             .join(" ").toLocaleLowerCase()
            if (query.length === 0 || haystack.includes(query))
                cards.push(card)
        }
        cards.sort((left, right) => {
            if (sortModeIndex === 1) {
                const leftMana = Number(left.manaValue) < 0 ? 1000 : Number(left.manaValue)
                const rightMana = Number(right.manaValue) < 0 ? 1000 : Number(right.manaValue)
                if (leftMana !== rightMana)
                    return leftMana - rightMana
            } else if (sortModeIndex === 2) {
                const typeDifference = String(left.category || "")
                                       .localeCompare(String(right.category || ""))
                if (typeDifference !== 0)
                    return typeDifference
            }
            return String(left.displayName || left.name)
                   .localeCompare(String(right.displayName || right.name))
        })
        return cards
    }
}
