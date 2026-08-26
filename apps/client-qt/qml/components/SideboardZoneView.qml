// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

pragma ComponentBehavior: Bound
pragma Translator: "SideboardPanel"

import QtQuick
import QtQuick.Layouts

Surface {
    id: zone

    required property var panel

    objectName: "sideboardZone-" + zoneName

    required property string title
    required property string zoneName
    required property int totalCount
    required property var groups
    required property string destinationName
    readonly property var categoryGroups: groups

    color: dropArea.containsDrag ? Theme.primaryMuted : Theme.surfaceMuted
    border.width: dropArea.containsDrag ? Theme.size(2) : 1
    border.color: dropArea.containsDrag ? Theme.primary : Theme.border

    DropArea {
        id: dropArea
        anchors.fill: parent
        enabled: zone.enabled && zone.panel.deckChangesAllowed
        keys: ["hexproof/sideboard-card"]
        onDropped: function(drop) {
            if (!drop.source || zone.panel.dragFromZone === zone.zoneName) {
                drop.accepted = false
                return
            }
            zone.panel.moveSideboardCard(zone.panel.dragCard,
                                         zone.panel.dragFromZone,
                                         zone.zoneName)
            drop.acceptProposedAction()
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.size(14)
        spacing: Theme.size(10)

        RowLayout {
            Layout.fillWidth: true

            Text {
                textFormat: Text.PlainText
                Layout.fillWidth: true
                text: zone.title + ": " + zone.totalCount
                color: Theme.text
                font.pixelSize: Theme.fontSize(16)
                font.weight: Font.DemiBold
            }
        }

        Item {
            id: categoryTable

            objectName: "sideboardCategoryTable-" + zone.zoneName
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true

            readonly property real labelWidth: Theme.size(82)
            readonly property real cardGap: Theme.size(5)
            readonly property var tableMetrics:
                zone.panel.categoryTableMetrics(
                    zone.categoryGroups, width, height,
                    labelWidth, cardGap)

            Text {
                textFormat: Text.PlainText
                anchors.centerIn: parent
                visible: zone.categoryGroups.length === 0
                text: zone.zoneName === "mainboard"
                      ? qsTr("No mainboard cards")
                      : qsTr("No sideboard cards")
                color: Theme.textMuted
                font.pixelSize: Theme.fontSize(12)
            }

            Column {
                anchors.fill: parent

                Repeater {
                    // Category delegates stay alive across authoritative
                    // sideboard snapshots. Only a category whose contents
                    // changed receives a new inner card model.
                    model: zone.panel.cardCategories()

                    delegate: Item {
                        id: categoryBand

                        required property string modelData
                        required property int index
                        readonly property int groupIndex:
                            zone.panel.categoryGroupIndex(
                                zone.categoryGroups, modelData)
                        readonly property var groupData:
                            zone.panel.categoryGroup(
                                zone.categoryGroups, modelData)
                        property bool cardModelReady: false

                        objectName: "sideboardCategory-" + zone.zoneName
                                    + "-" + modelData
                        visible: groupIndex >= 0
                        width: parent.width
                        height:
                            visible
                            && categoryTable.tableMetrics.bandHeights[
                                groupIndex]
                            ? categoryTable.tableMetrics.bandHeights[
                                  groupIndex]
                            : 0

                        Rectangle {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            height: 1
                            color: Theme.divider
                        }

                        Item {
                            anchors.left: parent.left
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            width: categoryTable.labelWidth

                            Text {
                                textFormat: Text.PlainText
                                anchors.centerIn: parent
                                width: parent.width - Theme.size(8)
                                text: I18n.cardCategory(
                                          categoryBand.modelData)
                                      + "\n(" + categoryBand.groupData.count
                                      + ")"
                                color: Theme.textSecondary
                                font.pixelSize: Theme.fontSize(11)
                                font.weight: Font.DemiBold
                                horizontalAlignment: Text.AlignHCenter
                            }
                        }

                        Item {
                            id: cardLane

                            anchors.left: parent.left
                            anchors.leftMargin:
                                categoryTable.labelWidth
                                + categoryTable.cardGap
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom

                            readonly property int rowCount:
                                Math.max(1, Math.ceil(
                                    categoryBand.groupData.cards.length
                                    / categoryTable.tableMetrics.columns))
                            readonly property real cardsHeight:
                                rowCount
                                * categoryTable.tableMetrics.cardHeight
                                + Math.max(0, rowCount - 1)
                                  * categoryTable.cardGap
                            readonly property real topOffset:
                                Math.max(0, (height - cardsHeight) / 2)

                            ListModel {
                                id: categoryCardModel
                            }

                            Repeater {
                                model: categoryCardModel

                                delegate: Item {
                                    id: cardTile

                                    required property int index
                                    required property string name
                                    required property int count
                                    required property int pileCount
                                    required property string setCode
                                    required property string collectorNumber
                                    required property string typeLine
                                    required property string category
                                    required property int tableIndex
                                    readonly property var cardData: ({
                                        "name": name,
                                        "count": count,
                                        "pileCount": pileCount,
                                        "setCode": setCode,
                                        "collectorNumber": collectorNumber,
                                        "typeLine": typeLine,
                                        "category": category,
                                        "tableIndex": tableIndex
                                    })
                                    readonly property string zoneName:
                                        zone.zoneName
                                    readonly property real stackInset:
                                        pileCount > 1
                                        ? Math.min(
                                            Theme.size(7),
                                            width * 0.08)
                                        : 0

                                    objectName:
                                        "sideboardCard-" + zone.zoneName
                                        + "-" + tableIndex
                                    x: (index
                                        % categoryTable.tableMetrics.columns)
                                       * (categoryTable.tableMetrics.cardWidth
                                          + categoryTable.cardGap)
                                    y: cardLane.topOffset
                                       + Math.floor(
                                           index
                                           / categoryTable.tableMetrics.columns)
                                         * (categoryTable.tableMetrics.cardHeight
                                            + categoryTable.cardGap)
                                    width:
                                        categoryTable.tableMetrics.cardWidth
                                    height:
                                        categoryTable.tableMetrics.cardHeight

                                    Rectangle {
                                        visible:
                                            cardTile.pileCount > 2
                                        x: cardTile.stackInset
                                        y: cardTile.stackInset
                                        width: parent.width
                                               - cardTile.stackInset
                                        height: parent.height
                                                - cardTile.stackInset
                                        radius: Theme.radiusSmall
                                        color: Theme.surfaceElevated
                                        border.width: 1
                                        border.color: Theme.borderStrong
                                    }

                                    Rectangle {
                                        visible:
                                            cardTile.pileCount > 1
                                        x: cardTile.stackInset / 2
                                        y: cardTile.stackInset / 2
                                        width: parent.width
                                               - cardTile.stackInset
                                        height: parent.height
                                                - cardTile.stackInset
                                        radius: Theme.radiusSmall
                                        color: Theme.surfaceMuted
                                        border.width: 1
                                        border.color: Theme.border
                                    }

                                    Rectangle {
                                        id: topCard

                                        width: parent.width
                                               - cardTile.stackInset
                                        height: parent.height
                                                - cardTile.stackInset
                                        radius: Theme.radiusSmall
                                        color: Theme.surfaceElevated
                                        border.width:
                                            cardHover.hovered
                                            ? Theme.size(2) : 1
                                        border.color:
                                            cardHover.hovered
                                            ? Theme.primary : Theme.border
                                        clip: true

                                        Image {
                                            id: cardArt
                                            objectName:
                                                "sideboardCardArt-"
                                                + zone.zoneName + "-"
                                                + cardTile.tableIndex
                                            anchors.fill: parent
                                            source:
                                                zone.panel.tableCardImageSource(
                                                    cardTile.cardData)
                                            fillMode:
                                                Image.PreserveAspectFit
                                            asynchronous: true
                                            sourceSize.width:
                                                Theme.size(240)
                                        }

                                        Rectangle {
                                            anchors.fill: parent
                                            visible:
                                                cardArt.status
                                                !== Image.Ready
                                            color: Theme.surfaceElevated
                                            Text {
                                                textFormat: Text.PlainText
                                                anchors.centerIn: parent
                                                width:
                                                    parent.width
                                                    - Theme.size(8)
                                                text:
                                                    cardTile.name
                                                color:
                                                    Theme.textSecondary
                                                font.pixelSize:
                                                    Theme.fontSize(8)
                                                wrapMode: Text.WordWrap
                                                horizontalAlignment:
                                                    Text.AlignHCenter
                                            }
                                        }
                                    }

                                    Rectangle {
                                        objectName:
                                            "sideboardPileCount-"
                                            + zone.zoneName + "-"
                                            + cardTile.tableIndex
                                        visible:
                                            cardTile.pileCount > 1
                                        anchors.top: topCard.top
                                        anchors.right: topCard.right
                                        anchors.margins: Theme.size(4)
                                        width: pileCountText.implicitWidth
                                               + Theme.size(10)
                                        height: pileCountText.implicitHeight
                                                + Theme.size(5)
                                        radius: height / 2
                                        color: Theme.backgroundRaised
                                        border.width: 1
                                        border.color: Theme.text

                                        Text {
                                            textFormat: Text.PlainText
                                            id: pileCountText

                                            objectName:
                                                "sideboardPileCountText-"
                                                + zone.zoneName + "-"
                                                + cardTile.tableIndex
                                            anchors.centerIn: parent
                                            text: "×"
                                                  + cardTile.pileCount
                                            color: Theme.text
                                            font.pixelSize:
                                                Theme.fontSize(10)
                                            font.weight: Font.Bold
                                        }
                                    }

                                    Rectangle {
                                        objectName: "sideboardCommanderToggle-"
                                                    + cardTile.tableIndex
                                        anchors.top: topCard.top
                                        anchors.left: topCard.left
                                        anchors.margins: Theme.size(4)
                                        z: 8
                                        visible: !zone.panel.deckChangesAllowed
                                                 && zone.zoneName === "mainboard"
                                        width: Theme.size(28)
                                        height: width
                                        radius: width / 2
                                        color: zone.panel.commanderDesignated(cardTile.name)
                                               ? Theme.primary : Theme.inactiveSelection
                                        border.width: 1
                                        border.color: zone.panel.commanderDesignated(cardTile.name)
                                                      ? Theme.primary : Theme.borderStrong

                                        Text {
                                            textFormat: Text.PlainText
                                            anchors.centerIn: parent
                                            text: "★"
                                            color: zone.panel.commanderDesignated(cardTile.name)
                                                   ? Theme.primaryInk : Theme.text
                                            font.pixelSize: Theme.fontSize(13)
                                        }
                                        TapHandler {
                                            enabled: !zone.panel.ownReady
                                            acceptedButtons: Qt.LeftButton
                                            onTapped: zone.panel.setSideboardCommander(
                                                          cardTile.name,
                                                          !zone.panel.commanderDesignated(cardTile.name))
                                        }
                                    }

                                    HoverHandler {
                                        id: cardHover

                                        onHoveredChanged: {
                                            if (hovered) {
                                                zone.panel.inspectSideboardCard(
                                                    cardTile.cardData,
                                                    cardTile)
                                            } else {
                                                zone.panel.hideSideboardCardPreview()
                                            }
                                        }
                                    }

                                    DragHandler {
                                        id: cardDrag

                                        target: null
                                        enabled: zone.enabled
                                                 && zone.panel.deckChangesAllowed
                                        acceptedButtons: Qt.LeftButton
                                        onActiveChanged: {
                                            if (active) {
                                                zone.panel.beginSideboardDrag(
                                                    cardTile,
                                                    centroid.scenePosition)
                                            } else if (
                                                zone.panel.dragSource
                                                === cardTile) {
                                                zone.panel.finishSideboardDrag()
                                            }
                                        }
                                        onCentroidChanged: {
                                            if (active) {
                                                zone.panel.updateSideboardDrag(
                                                    centroid.scenePosition)
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        Component.onCompleted: {
                            cardModelReady = true
                            syncCardModel()
                        }
                        onGroupDataChanged: {
                            if (cardModelReady)
                                syncCardModel()
                        }

                        function syncCardModel() {
                            zone.panel.syncSideboardCategoryModel(
                                categoryCardModel,
                                groupData.cards)
                        }
                    }
                }
            }
        }
    }
}
