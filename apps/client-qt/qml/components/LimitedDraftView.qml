// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

pragma ComponentBehavior: Bound
pragma Translator: "TournamentLobby"

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

Item {
    id: root

    required property var limitedModel
    required property var tournamentModel
    required property var wsModel
    required property var cardCatalogModel
    property string selectedInstanceId: ""
    property int pickedRarityFilterIndex: 0
    property var inspectedCard: ({})
    property var inspectedSource: null
    property bool hoverPreviewVisible: false
    property real hoverPreviewX: 0
    property real hoverPreviewY: 0
    readonly property string participantId: tournamentModel.participantId || ""
    readonly property var rarityFilterKeys: ["all", "common", "uncommon", "rare",
                                              "mythic", "unknown"]
    readonly property var rarityFilterOptions: [qsTr("All rarities"), qsTr("Common"),
                                                 qsTr("Uncommon"), qsTr("Rare"),
                                                 qsTr("Mythic rare"), qsTr("Unknown")]
    readonly property string pickedRarityFilter:
        rarityFilterKeys[pickedRarityFilterIndex]
    readonly property var visiblePickedCards: filterPickedCards()

    Component.onCompleted: root.cacheVisibleCards()

    Connections {
        target: root.limitedModel
        function onSnapshotChanged() {
            root.hideCardPreview()
            root.cacheVisibleCards()
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: Theme.size(10)

        RowLayout {
            Layout.fillWidth: true

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Theme.size(2)
                Text {
                    textFormat: Text.PlainText
                    text: qsTr("Draft pack %1 · %2")
                          .arg(root.limitedModel.packRound)
                          .arg(root.limitedModel.direction > 0
                               ? qsTr("pass left") : qsTr("pass right"))
                    color: Theme.text
                    font.pixelSize: Theme.fontSize(18)
                    font.weight: Font.DemiBold
                }
                Text {
                    textFormat: Text.PlainText
                    text: root.participantId.length > 0
                          ? qsTr("Choose one card. The rest of this pack goes to %1.")
                            .arg(seatMap.outgoingName)
                          : qsTr("Draft progress is private to participants.")
                    color: Theme.textMuted
                    font.pixelSize: Theme.fontSize(11)
                }
            }

            AppButton {
                objectName: "limitedConfirmPickButton"
                variant: "primary"
                text: qsTr("Confirm pick")
                enabled: root.selectedInstanceId.length > 0
                onClicked: {
                    root.hideCardPreview()
                    root.wsModel.pickLimitedCard(root.selectedInstanceId)
                    root.selectedInstanceId = ""
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: Theme.size(12)

            Surface {
                Layout.fillWidth: true
                Layout.fillHeight: true
                color: Theme.surfaceMuted

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: Theme.size(12)
                    spacing: Theme.size(8)

                    RowLayout {
                        Layout.fillWidth: true

                        Text {
                            textFormat: Text.PlainText
                            Layout.fillWidth: true
                            text: qsTr("Current pack · %1 cards")
                                  .arg(root.limitedModel.currentPack.length)
                            color: Theme.text
                            font.pixelSize: Theme.fontSize(14)
                            font.weight: Font.DemiBold
                        }

                        Text {
                            textFormat: Text.PlainText
                            visible: root.limitedModel.currentPack.length > 0
                            text: qsTr("Click a card to select it")
                            color: Theme.textMuted
                            font.pixelSize: Theme.fontSize(10)
                        }
                    }

                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true

                        Text {
                            textFormat: Text.PlainText
                            anchors.centerIn: parent
                            visible: root.limitedModel.currentPack.length === 0
                            text: root.limitedModel.participants.length > 0
                                  ? qsTr("Waiting for the next pack…")
                                  : qsTr("Draft progress is private to participants.")
                            color: Theme.textMuted
                            font.pixelSize: Theme.fontSize(13)
                        }

                        ScrollView {
                            anchors.fill: parent
                            visible: root.limitedModel.currentPack.length > 0
                            contentWidth: availableWidth
                            ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

                            Flow {
                                objectName: "limitedCurrentPackGrid"
                                width: parent.width
                                spacing: Theme.size(10)

                                Repeater {
                                    model: root.limitedModel.currentPack

                                    delegate: LimitedCardTile {
                                        id: packCard

                                        required property var modelData
                                        objectName: "limitedDraftPackCard-"
                                                    + modelData.instanceId
                                        width: Theme.size(142)
                                        height: Theme.size(204)
                                        card: modelData
                                        catalogModel: root.cardCatalogModel
                                        emphasized: root.selectedInstanceId
                                                    === modelData.instanceId
                                        actionText: emphasized ? "✓" : "+"
                                        onActivated: root.selectedInstanceId = modelData.instanceId
                                        onInspectionRequested:
                                            root.inspectCard(modelData, packCard)
                                        onInspectionEnded:
                                            root.hideCardPreview(packCard)
                                    }
                                }
                            }
                        }
                    }
                }
            }

            ColumnLayout {
                Layout.preferredWidth: Math.min(Theme.size(370), root.width * 0.34)
                Layout.minimumWidth: Theme.size(300)
                Layout.fillHeight: true
                spacing: Theme.size(12)

                LimitedDraftSeatMap {
                    id: seatMap
                    objectName: "limitedDraftSeatMap"
                    Layout.fillWidth: true
                    participants: root.limitedModel.participants
                    participantId: root.participantId
                    direction: root.limitedModel.direction
                }

                Surface {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    color: Theme.surfaceMuted

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: Theme.size(12)
                        spacing: Theme.size(8)

                        RowLayout {
                            Layout.fillWidth: true

                            Text {
                                textFormat: Text.PlainText
                                Layout.fillWidth: true
                                text: qsTr("Your picks")
                                color: Theme.text
                                font.pixelSize: Theme.fontSize(14)
                                font.weight: Font.DemiBold
                            }

                            AppComboBox {
                                id: pickedRarityFilterControl

                                objectName: "limitedDraftPickedRarityFilter"
                                Layout.preferredWidth: Theme.size(132)
                                implicitHeight: Theme.size(36)
                                model: root.rarityFilterOptions
                                currentIndex: root.pickedRarityFilterIndex
                                displayText: qsTr("Rarity: %1").arg(currentText)
                                onActivated: index =>
                                    root.pickedRarityFilterIndex = index
                            }

                            StatusPill {
                                objectName: "limitedPickedCount"
                                text: String(root.limitedModel.pool.length)
                                statusColor: Theme.primary
                            }
                        }

                        Text {
                            textFormat: Text.PlainText
                            Layout.fillWidth: true
                            visible: root.limitedModel.pool.length === 0
                            text: qsTr("Cards you draft will remain visible here.")
                            color: Theme.textMuted
                            font.pixelSize: Theme.fontSize(10)
                            wrapMode: Text.WordWrap
                        }

                        Text {
                            textFormat: Text.PlainText
                            Layout.fillWidth: true
                            visible: root.limitedModel.pool.length > 0
                                     && root.visiblePickedCards.length === 0
                            text: qsTr("No picked cards match this rarity.")
                            color: Theme.textMuted
                            font.pixelSize: Theme.fontSize(10)
                            wrapMode: Text.WordWrap
                        }

                        ScrollView {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            visible: root.visiblePickedCards.length > 0
                            contentWidth: availableWidth
                            ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

                            Flow {
                                objectName: "limitedPickedCardGrid"
                                width: parent.width
                                spacing: Theme.size(7)

                                Repeater {
                                    model: root.visiblePickedCards

                                    delegate: LimitedCardTile {
                                        id: pickedCard

                                        required property var modelData
                                        objectName: "limitedDraftPickedCard-"
                                                    + modelData.instanceId
                                        width: Theme.size(92)
                                        height: Theme.size(132)
                                        card: modelData
                                        catalogModel: root.cardCatalogModel
                                        onInspectionRequested:
                                            root.inspectCard(modelData, pickedCard)
                                        onInspectionEnded:
                                            root.hideCardPreview(pickedCard)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    Item {
        id: hoverPreview

        objectName: "limitedDraftCardHoverPreview"
        x: root.hoverPreviewX
        y: root.hoverPreviewY
        width: Math.min(Theme.size(340), root.width * 0.3)
        height: Math.round(width * 88 / 63)
        z: 500
        visible: root.hoverPreviewVisible && !!root.inspectedCard.name
        enabled: false

        Image {
            id: hoverPreviewArt

            objectName: "limitedDraftCardHoverPreviewArt"
            anchors.fill: parent
            source: root.previewImageSource(root.inspectedCard)
            fillMode: Image.PreserveAspectFit
            asynchronous: true
            smooth: true
        }

        Rectangle {
            anchors.fill: parent
            visible: hoverPreviewArt.status !== Image.Ready
            color: Theme.backgroundRaised
            radius: Theme.radiusMedium
            border.width: 1
            border.color: Theme.borderStrong

            Text {
                textFormat: Text.PlainText
                anchors.centerIn: parent
                width: parent.width - Theme.size(24)
                text: root.inspectedCard.name ? root.inspectedCard.name : ""
                color: Theme.textSecondary
                font.pixelSize: Theme.fontSize(15)
                font.weight: Font.DemiBold
                wrapMode: Text.WordWrap
                horizontalAlignment: Text.AlignHCenter
            }
        }
    }

    function rarityKey(card) {
        const rarity = card && card.rarity
                       ? String(card.rarity).toLowerCase() : ""
        if (rarity === "common" || rarity === "uncommon"
                || rarity === "rare" || rarity === "mythic") {
            return rarity
        }
        return "unknown"
    }

    function filterPickedCards() {
        const cards = limitedModel.pool || []
        if (pickedRarityFilter === "all")
            return cards
        const result = []
        for (let index = 0; index < cards.length; ++index) {
            if (rarityKey(cards[index]) === pickedRarityFilter)
                result.push(cards[index])
        }
        return result
    }

    function previewImageSource(card) {
        if (!card || !card.name || !cardCatalogModel
                || typeof cardCatalogModel.imageSource !== "function") {
            return ""
        }
        void cardCatalogModel.imageRevision
        return cardCatalogModel.imageSource(
                    card.name, card.setCode || "",
                    card.collectorNumber || "")
    }

    function inspectCard(card, sourceItem) {
        if (!card || !card.name || !sourceItem)
            return
        inspectedCard = card
        inspectedSource = sourceItem
        const previewWidth = Math.min(Theme.size(340), root.width * 0.3)
        const previewHeight = Math.round(previewWidth * 88 / 63)
        const margin = Theme.size(12)
        const right = sourceItem.mapToItem(root, sourceItem.width, 0)
        const left = sourceItem.mapToItem(root, 0, 0)
        let x = right.x + margin
        if (x + previewWidth > root.width - margin)
            x = left.x - previewWidth - margin
        hoverPreviewX = Math.max(
                            margin,
                            Math.min(root.width - previewWidth - margin, x))
        hoverPreviewY = Math.max(
                            margin,
                            Math.min(root.height - previewHeight - margin,
                                     left.y))
        hoverPreviewVisible = true
    }

    function hideCardPreview(sourceItem) {
        if (sourceItem && inspectedSource && sourceItem !== inspectedSource)
            return
        hoverPreviewVisible = false
        inspectedSource = null
    }

    function cacheVisibleCards() {
        if (!root.cardCatalogModel
                || typeof root.cardCatalogModel.cacheCardsIncrementally
                   !== "function") {
            return
        }
        root.cardCatalogModel.cacheCardsIncrementally(
                    (root.limitedModel.currentPack || [])
                    .concat(root.limitedModel.pool || []))
    }
}
