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
    required property var cardModel
    required property var destinations
    required property int promptId
    property var piles: []
    property int visualRevision: 0

    implicitHeight: Theme.size(238)

    function destinationLabel(destination) {
        switch (destination) {
        case "libraryTop": return qsTr("Library top")
        case "libraryBottom": return qsTr("Library bottom")
        case "graveyard": return qsTr("Graveyard")
        case "exile": return qsTr("Exile")
        case "hand": return qsTr("Hand")
        default: return destination
        }
    }

    function destinationLabels() {
        const labels = []
        for (let index = 0; index < destinations.length; ++index)
            labels.push(destinationLabel(destinations[index]))
        return labels
    }

    function copiedCard(card) {
        return {
            "cardId": card.cardId,
            "name": card.name,
            "setCode": card.setCode,
            "collectorNumber": card.collectorNumber,
            "token": card.token
        }
    }

    function resetPiles() {
        const next = []
        for (let index = 0; index < destinations.length; ++index)
            next.push([])
        if (next.length > 0 && cardModel
                && typeof cardModel.items === "function") {
            const cards = cardModel.items()
            for (let index = 0; index < cards.length; ++index)
                next[0].push(copiedCard(cards[index]))
        }
        piles = next
        visualRevision++
    }

    function cardsForPile(pileIndex) {
        void visualRevision
        return pileIndex >= 0 && pileIndex < piles.length
               ? piles[pileIndex] : []
    }

    function moveCard(cardId, fromPile, toPile) {
        if (fromPile < 0 || fromPile >= piles.length || toPile < 0
                || toPile >= piles.length || fromPile === toPile)
            return false
        const next = piles.map(pile => pile.slice())
        const sourceIndex = next[fromPile].findIndex(card => card.cardId === cardId)
        if (sourceIndex < 0)
            return false
        const moved = next[fromPile].splice(sourceIndex, 1)[0]
        next[toPile].push(moved)
        piles = next
        visualRevision++
        return true
    }

    function moveWithinPile(cardId, pileIndex, offset) {
        if (pileIndex < 0 || pileIndex >= piles.length || offset === 0)
            return false
        const next = piles.map(pile => pile.slice())
        const sourceIndex = next[pileIndex].findIndex(card => card.cardId === cardId)
        const destinationIndex = sourceIndex + offset
        if (sourceIndex < 0 || destinationIndex < 0
                || destinationIndex >= next[pileIndex].length)
            return false
        const moved = next[pileIndex].splice(sourceIndex, 1)[0]
        next[pileIndex].splice(destinationIndex, 0, moved)
        piles = next
        visualRevision++
        return true
    }

    function submitPiles() {
        if (piles.length !== destinations.length || piles.length === 0)
            return
        const answer = []
        for (let pileIndex = 0; pileIndex < piles.length; ++pileIndex) {
            answer.push({
                "destination": destinations[pileIndex],
                "cardIds": piles[pileIndex].map(card => card.cardId)
            })
        }
        wsModel.respondRulesPromptWithScry(promptId, answer)
    }

    onPromptIdChanged: resetPiles()
    onDestinationsChanged: resetPiles()
    Component.onCompleted: resetPiles()

    ColumnLayout {
        anchors.fill: parent
        spacing: Theme.size(8)

        ListView {
            id: pileList
            objectName: "rulesScryPileList"

            Layout.fillWidth: true
            Layout.fillHeight: true
            orientation: ListView.Horizontal
            spacing: Theme.size(8)
            clip: true
            model: root.destinations

            delegate: Rectangle {
                id: pile

                required property int index
                required property string modelData
                readonly property int pileIndex: index
                readonly property var pileCards: root.cardsForPile(pileIndex)

                objectName: "rulesScryPile-" + modelData
                width: Math.max(Theme.size(250),
                                (pileList.width - pileList.spacing
                                 * Math.max(0, pileList.count - 1))
                                / Math.min(2, Math.max(1, pileList.count)))
                height: pileList.height
                radius: Theme.radiusSmall
                color: Theme.surfaceMuted
                border.width: 1
                border.color: Theme.border

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: Theme.size(6)
                    spacing: Theme.size(5)

                    RowLayout {
                        Layout.fillWidth: true

                        Text {
                            textFormat: Text.PlainText
                            Layout.fillWidth: true
                            text: root.destinationLabel(pile.modelData)
                            color: Theme.text
                            font.pixelSize: Theme.fontSize(10)
                            font.weight: Font.DemiBold
                        }

                        Text {
                            textFormat: Text.PlainText
                            text: String(pile.pileCards.length)
                            color: Theme.textSecondary
                            font.pixelSize: Theme.fontSize(9)
                        }
                    }

                    ListView {
                        id: cardList

                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        orientation: ListView.Horizontal
                        spacing: Theme.size(6)
                        clip: true
                        model: pile.pileCards

                        delegate: Rectangle {
                            id: cardTile

                            required property int index
                            required property var modelData
                            readonly property string cardId: modelData.cardId

                            objectName: "rulesScryCard-" + cardId
                            width: Theme.size(96)
                            height: cardList.height
                            radius: Theme.radiusSmall
                            color: Theme.surfaceElevated
                            border.width: 1
                            border.color: Theme.borderStrong
                            clip: true

                            Image {
                                id: art

                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.bottom: destinationPicker.top
                                anchors.margins: Theme.size(3)
                                asynchronous: true
                                fillMode: Image.PreserveAspectFit
                                source: {
                                    if (!root.cardCatalogModel || !cardTile.modelData.name
                                            || typeof root.cardCatalogModel.tableImageSource
                                            !== "function") {
                                        return ""
                                    }
                                    void root.cardCatalogModel.imageRevision
                                    return root.cardCatalogModel.tableImageSource(
                                                cardTile.modelData.name,
                                                cardTile.modelData.setCode,
                                                cardTile.modelData.collectorNumber)
                                }
                            }

                            Text {
                                textFormat: Text.PlainText
                                anchors.centerIn: art
                                width: art.width - Theme.size(8)
                                visible: art.status !== Image.Ready
                                text: cardTile.modelData.name.length > 0
                                      ? cardTile.modelData.name : qsTr("Unknown card")
                                color: Theme.textSecondary
                                font.pixelSize: Theme.fontSize(8)
                                horizontalAlignment: Text.AlignHCenter
                                wrapMode: Text.Wrap
                            }

                            AppComboBox {
                                id: destinationPicker

                                objectName: "rulesScryDestination-" + cardTile.cardId
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.bottom: orderControls.top
                                anchors.margins: Theme.size(3)
                                height: Theme.size(28)
                                model: root.destinationLabels()
                                currentIndex: pile.pileIndex
                                font.pixelSize: Theme.fontSize(8)
                                onActivated: selectedIndex => root.moveCard(
                                                 cardTile.cardId, pile.pileIndex,
                                                 selectedIndex)
                            }

                            RowLayout {
                                id: orderControls

                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.bottom: parent.bottom
                                anchors.margins: Theme.size(3)
                                height: Theme.size(26)
                                spacing: Theme.size(3)

                                AppButton {
                                    Layout.fillWidth: true
                                    compact: true
                                    text: "‹"
                                    enabled: cardTile.index > 0
                                    onClicked: root.moveWithinPile(
                                                   cardTile.cardId, pile.pileIndex, -1)
                                }

                                AppButton {
                                    Layout.fillWidth: true
                                    compact: true
                                    text: "›"
                                    enabled: cardTile.index + 1 < pile.pileCards.length
                                    onClicked: root.moveWithinPile(
                                                   cardTile.cardId, pile.pileIndex, 1)
                                }
                            }

                            HoverHandler { id: hover }
                            ToolTip.visible: hover.hovered
                            ToolTip.delay: 350
                            ToolTip.text: cardTile.modelData.name
                        }
                    }

                    Text {
                        textFormat: Text.PlainText
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        visible: pile.pileCards.length === 0
                        text: qsTr("No cards assigned")
                        color: Theme.textMuted
                        font.pixelSize: Theme.fontSize(9)
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true

            Text {
                textFormat: Text.PlainText
                Layout.fillWidth: true
                text: qsTr("Choose a destination for every card. Within each pile, the leftmost card is first.")
                color: Theme.textSecondary
                font.pixelSize: Theme.fontSize(9)
                elide: Text.ElideRight
            }

            AppButton {
                objectName: "confirmScryButton"
                Layout.preferredWidth: Theme.size(150)
                compact: true
                variant: "primary"
                text: qsTr("Confirm placement")
                onClicked: root.submitPiles()
            }
        }
    }
}
