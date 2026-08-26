// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

Item {
    id: root

    required property var wsModel
    required property var cardCatalogModel
    required property var tableModel
    required property var gameTableModel
    readonly property var roomSession: wsModel.roomSession
    readonly property var gameSession: wsModel.gameSession
    property int remainingSeconds: 0
    property var dragSource: null
    property var dragCard: ({})
    property string dragFromZone: ""
    property point dragPosition: Qt.point(0, 0)
    property var inspectedCard: ({})
    property bool hoverPreviewVisible: false
    property real hoverPreviewX: 0
    property real hoverPreviewY: 0
    property var resolvedTypeLineCache: ({})
    readonly property var sideboardData: gameSession.sideboard
                                                   ? gameSession.sideboard : ({})
    readonly property var mainboard: sideboardData.mainboard
                                     ? sideboardData.mainboard : []
    readonly property var sideboard: sideboardData.sideboard
                                    ? sideboardData.sideboard : []
    readonly property var mainboardGroups: tableModel.mainboardGroups
    readonly property var sideboardGroups: tableModel.sideboardGroups
    readonly property bool isPlayer: roomSession.role === "player"
    readonly property bool ownReady: playerReady(roomSession.seatIndex)
    readonly property bool deckChangesAllowed: roomSession.format !== "duel"
    readonly property var commanders: sideboardData.commanders
                                      ? sideboardData.commanders : []

    Binding {
        target: root.tableModel
        property: "mainboardCards"
        value: root.cardsWithResolvedTypes(root.mainboard)
    }

    Binding {
        target: root.tableModel
        property: "sideboardCards"
        value: root.cardsWithResolvedTypes(root.sideboard)
    }

    z: 200

    Rectangle {
        anchors.fill: parent
        color: Theme.modalScrim
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
    }

    Surface {
        anchors.fill: parent
        anchors.margins: Theme.size(16)
        elevated: true

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Theme.size(20)
            spacing: Theme.size(12)

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.size(16)

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Theme.size(3)

                    Text {
                        textFormat: Text.PlainText
                        objectName: "sideboardGameTitle"
                        text: (root.deckChangesAllowed
                               ? qsTr("Sideboard · Game ")
                               : qsTr("Between games · Game "))
                              + root.gameSession.gameNumber
                              + " → " + (root.gameSession.gameNumber + 1)
                        color: Theme.text
                        font.pixelSize: Theme.fontSize(22)
                        font.weight: Font.DemiBold
                    }

                    Text {
                        textFormat: Text.PlainText
                        objectName: "sideboardDeckRulesHint"
                        text: root.deckChangesAllowed
                              ? qsTr("Move only registered cards between main and sideboard.")
                              : qsTr("Choose one or two commanders for the next game; the registered deck stays unchanged.")
                        color: Theme.textSecondary
                        font.pixelSize: Theme.fontSize(12)
                    }

                    Text {
                        textFormat: Text.PlainText
                        text: root.deckChangesAllowed
                              ? qsTr("Every card is laid out at once; drag cards between tables.")
                              : qsTr("Use the star on a mainboard card, then confirm Ready.")
                        color: Theme.textMuted
                        font.pixelSize: Theme.fontSize(10)
                    }
                }

                StatusPill {
                    objectName: "sideboardCountdown"
                    text: root.clockText()
                    statusColor: root.remainingSeconds <= 60
                                 ? Theme.error : Theme.warning
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.size(8)

                Repeater {
                    model: root.sideboardData.seats
                           ? root.sideboardData.seats : []

                    StatusPill {
                        required property var modelData
                        objectName: "sideboardSeatStatus" + modelData.seat
                        text: root.displayName(modelData.seat) + " · "
                              + modelData.mainboardCount + "+"
                              + modelData.sideboardCount + " · "
                              + (modelData.ready
                                 ? qsTr("Ready") : qsTr("Editing"))
                        statusColor: modelData.ready ? Theme.success : Theme.textMuted
                    }
                }

                Item { Layout.fillWidth: true }

                Text {
                    textFormat: Text.PlainText
                    visible: !root.isPlayer
                    text: qsTr("Spectating sideboard readiness")
                    color: Theme.textMuted
                    font.pixelSize: Theme.fontSize(11)
                }
            }

            GridLayout {
                id: boardTables

                objectName: "sideboardTables"
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: root.isPlayer
                columns: root.deckChangesAllowed && sideBySide ? 2 : 1
                columnSpacing: Theme.size(10)
                rowSpacing: Theme.size(10)
                readonly property bool sideBySide:
                    width >= Theme.size(1200)
                    && width >= height * 1.55

                SideboardZoneView {
                    id: mainZone
                    panel: root
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.row: 0
                    Layout.column: 0
                    Layout.horizontalStretchFactor:
                        boardTables.sideBySide
                        ? root.zoneColumnUnits(root.mainboardGroups) : 1
                    Layout.verticalStretchFactor:
                        boardTables.sideBySide
                        ? 1
                        : Math.max(1, Math.round(
                            root.zoneRowUnits(
                                root.mainboardGroups,
                                boardTables.width) * 100))
                    title: qsTr("Mainboard")
                    zoneName: "mainboard"
                    totalCount: root.tableModel.mainboardCount
                    groups: root.mainboardGroups
                    destinationName: "sideboard"
                    enabled: !root.ownReady
                }

                SideboardZoneView {
                    id: sideZone
                    panel: root
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.row: boardTables.sideBySide ? 0 : 1
                    Layout.column: boardTables.sideBySide ? 1 : 0
                    Layout.horizontalStretchFactor:
                        boardTables.sideBySide
                        ? root.zoneColumnUnits(root.sideboardGroups) : 1
                    Layout.verticalStretchFactor:
                        boardTables.sideBySide
                        ? 1
                        : Math.max(1, Math.round(
                            root.zoneRowUnits(
                                root.sideboardGroups,
                                boardTables.width) * 100))
                    title: qsTr("Sideboard")
                    zoneName: "sideboard"
                    totalCount: root.tableModel.sideboardCount
                    groups: root.sideboardGroups
                    destinationName: "mainboard"
                    enabled: root.deckChangesAllowed && !root.ownReady
                    visible: root.deckChangesAllowed
                }
            }

            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: !root.isPlayer

                Text {
                    textFormat: Text.PlainText
                    anchors.centerIn: parent
                    text: qsTr("Spectating sideboard readiness")
                    color: Theme.textMuted
                    font.pixelSize: Theme.fontSize(15)
                }
            }

            RowLayout {
                Layout.fillWidth: true

                Text {
                    textFormat: Text.PlainText
                    Layout.fillWidth: true
                    text: qsTr("Timeout restores the previous game’s deck partition.")
                    color: Theme.textMuted
                    font.pixelSize: Theme.fontSize(11)
                }

                AppButton {
                    objectName: "sideboardReadyButton"
                    visible: root.isPlayer
                    variant: root.ownReady ? "ghost" : "primary"
                    text: root.ownReady ? qsTr("Cancel ready") : qsTr("Ready for next game")
                    onClicked: root.wsModel.setSideboardReady(!root.ownReady)
                }
            }
        }
    }

    SideboardPreviewLayer {
        id: previewLayer
        panel: root
    }

    Timer {
        interval: 1000
        running: root.visible
        repeat: true
        triggeredOnStart: true
        onTriggered: root.updateClock()
    }

    function updateClock() {
        const deadline = Number(sideboardData.deadlineUnixMs
                                ? sideboardData.deadlineUnixMs : 0)
        remainingSeconds = Math.max(0, Math.ceil((deadline - Date.now()) / 1000))
    }

    function clockText() {
        const minutes = Math.floor(remainingSeconds / 60)
        const seconds = remainingSeconds % 60
        return minutes + ":" + (seconds < 10 ? "0" : "") + seconds
    }

    function playerReady(seat) {
        const players = sideboardData.seats ? sideboardData.seats : []
        for (let index = 0; index < players.length; ++index) {
            if (players[index].seat === seat)
                return players[index].ready === true
        }
        return false
    }

    function commanderDesignated(name) {
        for (let index = 0; index < commanders.length; ++index) {
            if (String(commanders[index]).toLocaleLowerCase()
                    === String(name).toLocaleLowerCase())
                return true
        }
        return false
    }

    function moveSideboardCard(card, fromZone, toZone) {
        wsModel.moveSideboardCard(card, fromZone, toZone)
    }

    function setSideboardCommander(name, designated) {
        wsModel.setSideboardCommander(name, designated)
    }

    function displayName(seat) {
        const player = gameTableModel.seatData(seat)
        if (player && player.displayName)
            return player.displayName
        return qsTr("Seat") + " " + (seat + 1)
    }

    function cardCategory(typeLine) {
        return tableModel.cardCategory(typeLine ? typeLine : "")
    }

    function cardCategories() {
        return [
            "Artifact", "Creature", "Enchantment", "Instant", "Land",
            "Planeswalker", "Sorcery", "Other"
        ]
    }

    function categoryGroupIndex(groups, category) {
        for (let index = 0; index < groups.length; ++index) {
            if (groups[index].category === category)
                return index
        }
        return -1
    }

    function categoryGroup(groups, category) {
        const index = categoryGroupIndex(groups, category)
        if (index >= 0)
            return groups[index]
        return {
            "category": category,
            "count": 0,
            "cards": []
        }
    }

    function sideboardCardKey(card) {
        return String(card.name ? card.name : "").trim().toLowerCase()
    }

    function sideboardCardModelEntry(card) {
        const name = String(card.name ? card.name : "")
        const count = Math.max(1, Number(card.count ? card.count : 1))
        const pileCount = Math.max(
                            1,
                            Number(card.pileCount ? card.pileCount : count))
        const setCode = String(card.setCode ? card.setCode : "")
        const collectorNumber = String(
                                    card.collectorNumber
                                    ? card.collectorNumber : "")
        const typeLine = String(card.typeLine ? card.typeLine : "")
        const category = String(card.category ? card.category : "Other")
        const tableIndex = Number(
                               typeof card.tableIndex !== "undefined"
                               ? card.tableIndex : 0)
        return {
            "cardKey": sideboardCardKey(card),
            "contentKey": [
                name, count, pileCount, setCode, collectorNumber, typeLine,
                category, tableIndex
            ].join("\u001f"),
            "name": name,
            "count": count,
            "pileCount": pileCount,
            "setCode": setCode,
            "collectorNumber": collectorNumber,
            "typeLine": typeLine,
            "category": category,
            "tableIndex": tableIndex
        }
    }

    function syncSideboardCategoryModel(model, cards) {
        const targetCards = cards ? cards : []
        const targetKeys = ({})
        for (let index = 0; index < targetCards.length; ++index)
            targetKeys[sideboardCardKey(targetCards[index])] = true

        for (let index = model.count - 1; index >= 0; --index) {
            if (!targetKeys[model.get(index).cardKey])
                model.remove(index)
        }

        for (let targetIndex = 0;
             targetIndex < targetCards.length; ++targetIndex) {
            const entry = sideboardCardModelEntry(targetCards[targetIndex])
            let currentIndex = -1
            for (let index = targetIndex; index < model.count; ++index) {
                if (model.get(index).cardKey === entry.cardKey) {
                    currentIndex = index
                    break
                }
            }
            if (currentIndex < 0) {
                model.insert(targetIndex, entry)
                continue
            }
            if (currentIndex !== targetIndex)
                model.move(currentIndex, targetIndex, 1)
            if (model.get(targetIndex).contentKey !== entry.contentKey)
                model.set(targetIndex, entry)
        }
    }

    function cardsWithResolvedTypes(cards) {
        const result = []
        for (let index = 0; index < cards.length; ++index) {
            const card = Object.assign({}, cards[index])
            card.typeLine = resolvedTypeLine(card)
            result.push(card)
        }
        return result
    }

    function categoryGroups(cards) {
        return tableModel.groupCards(cardsWithResolvedTypes(cards))
    }

    function categoryTableMetrics(groups, width, height, labelWidth, gap) {
        if (groups.length === 0 || width <= 0 || height <= 0) {
            return {
                "columns": 1,
                "cardWidth": Theme.size(80),
                "cardHeight": Theme.size(112),
                "bandHeights": []
            }
        }
        const usableWidth = Math.max(1, width - labelWidth - gap)
        let largestGroup = 1
        for (let groupIndex = 0;
             groupIndex < groups.length; ++groupIndex) {
            largestGroup = Math.max(
                               largestGroup,
                               groups[groupIndex].cards.length)
        }

        let bestColumns = 1
        let bestCardWidth = 1
        const bandPadding = Theme.size(4)
        for (let columns = 1; columns <= largestGroup; ++columns) {
            let totalRows = 0
            let interRowGaps = 0
            for (let groupIndex = 0;
                 groupIndex < groups.length; ++groupIndex) {
                const rows = Math.max(
                                 1, Math.ceil(
                                     groups[groupIndex].cards.length
                                     / columns))
                totalRows += rows
                interRowGaps += Math.max(0, rows - 1) * gap
            }
            const horizontalWidth = Math.max(
                                        1,
                                        (usableWidth
                                         - gap * (columns - 1)) / columns)
            const verticalCardHeight = Math.max(
                                           1,
                                           (height
                                            - interRowGaps
                                            - groups.length * bandPadding)
                                           / totalRows)
            const cardWidth = Math.min(horizontalWidth,
                                       verticalCardHeight * 63 / 88,
                                       Theme.size(190))
            if (cardWidth > bestCardWidth) {
                bestCardWidth = cardWidth
                bestColumns = columns
            }
        }

        const cardHeight = bestCardWidth * 88 / 63
        const baseHeights = []
        let baseHeightTotal = 0
        for (let groupIndex = 0;
             groupIndex < groups.length; ++groupIndex) {
            const rows = Math.max(
                             1, Math.ceil(
                                 groups[groupIndex].cards.length
                                 / bestColumns))
            const bandHeight = rows * cardHeight
                               + Math.max(0, rows - 1) * gap
                               + bandPadding
            baseHeights.push(bandHeight)
            baseHeightTotal += bandHeight
        }
        const extraPerBand = Math.max(
                                 0, height - baseHeightTotal) / groups.length
        const bandHeights = []
        for (let groupIndex = 0;
             groupIndex < baseHeights.length; ++groupIndex) {
            bandHeights.push(baseHeights[groupIndex] + extraPerBand)
        }
        return {
            "columns": bestColumns,
            "cardWidth": bestCardWidth,
            "cardHeight": cardHeight,
            "bandHeights": bandHeights
        }
    }

    function zoneRowUnits(groups, width) {
        if (groups.length === 0)
            return 1
        const columns = Math.max(
                            1, Math.floor(
                                Math.max(1, width - Theme.size(100))
                                / Theme.size(82)))
        let units = 0
        for (let index = 0; index < groups.length; ++index) {
            units += Math.max(
                         1, Math.ceil(groups[index].cards.length / columns))
                     + 0.35
        }
        return units
    }

    function zoneColumnUnits(groups) {
        let largestGroup = 1
        for (let index = 0; index < groups.length; ++index) {
            largestGroup = Math.max(
                               largestGroup, groups[index].cards.length)
        }
        return Math.max(4, largestGroup)
    }

    function cardImageSource(card) {
        if (!card || !card.name || !cardCatalogModel)
            return ""
        return cardCatalogModel.imageSource(
                    card.name,
                    card.setCode ? card.setCode : "",
                    card.collectorNumber ? card.collectorNumber : "")
    }

    function tableCardImageSource(card) {
        if (!card || !card.name || !cardCatalogModel)
            return ""
        if (typeof cardCatalogModel.tableImageSource === "function") {
            return cardCatalogModel.tableImageSource(
                        card.name,
                        card.setCode ? card.setCode : "",
                        card.collectorNumber ? card.collectorNumber : "")
        }
        return cardImageSource(card)
    }

    function resolvedTypeLine(card) {
        if (!card)
            return ""
        const supplied = String(card.typeLine ? card.typeLine : "").trim()
        if (supplied.length > 0)
            return supplied
        if (!cardCatalogModel
                || typeof cardCatalogModel.cardTypeLine !== "function") {
            return ""
        }
        const language = typeof cardCatalogModel.language !== "undefined"
                         ? cardCatalogModel.language : ""
        const key = language + "\u001f"
                    + String(card.name ? card.name : "").toLowerCase()
                    + "\u001f"
                    + String(card.setCode ? card.setCode : "").toUpperCase()
                    + "\u001f"
                    + String(card.collectorNumber
                             ? card.collectorNumber : "")
        if (Object.prototype.hasOwnProperty.call(
                    resolvedTypeLineCache, key)) {
            return resolvedTypeLineCache[key]
        }
        const resolved = cardCatalogModel.cardTypeLine(
                           card.name ? card.name : "",
                           card.setCode ? card.setCode : "",
                           card.collectorNumber
                           ? card.collectorNumber : "")
        resolvedTypeLineCache[key] = resolved
        return resolved
    }

    function inspectSideboardCard(card, sourceItem) {
        if (!card || !card.name || !sourceItem)
            return
        inspectedCard = card
        const previewWidth = Math.min(Theme.size(320), root.width * 0.25)
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

    function hideSideboardCardPreview() {
        hoverPreviewVisible = false
    }

    function beginSideboardDrag(sourceItem, scenePosition) {
        hideSideboardCardPreview()
        dragSource = sourceItem
        dragCard = sourceItem.cardData
        dragFromZone = sourceItem.zoneName
        updateSideboardDrag(scenePosition)
    }

    function updateSideboardDrag(scenePosition) {
        const point = root.mapFromItem(null, scenePosition.x, scenePosition.y)
        dragPosition = Qt.point(point.x, point.y)
    }

    function finishSideboardDrag() {
        previewLayer.finishDrag()
        dragSource = null
        dragCard = ({})
        dragFromZone = ""
    }
}
