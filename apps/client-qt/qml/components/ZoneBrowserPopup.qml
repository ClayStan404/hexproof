// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

Popup {
    id: root

    property var cards: []
    property var cardCatalogModel: null
    property bool canMoveCards: false
    property int localSeatIndex: -1
    property int seatIndex: -1
    property string ownerDisplayName: ""
    property string zoneKey: ""
    property int selectedIndex: -1
    property var selectedOrder: []
    property string contextCardId: ""
    property string filterQuery: ""
    readonly property var groupedCards: groupCards()
    readonly property var visibleCards: filterCards()
    readonly property int selectedCount: selectedOrder.length
    readonly property bool multiSelectEnabled:
        zoneKey === "graveyard" || zoneKey === "exile"
    readonly property var selectedCard:
        selectedIndex >= 0 && selectedIndex < visibleCards.length
        ? visibleCards[selectedIndex] : ({})
    signal moveRequested(string cardId, string fromZone, int fromSeat,
                         string toZone, int toSeat)
    signal movesRequested(var cardIds, string fromZone, int fromSeat,
                          string toZone, int toSeat)
    signal castCommanderRequested(string commanderId)

    parent: Overlay.overlay
    x: Math.round((parent.width - width) / 2)
    y: Math.round((parent.height - height) / 2)
    width: Math.min(Theme.size(960), parent.width - Theme.size(48))
    height: Math.min(Theme.size(680), parent.height - Theme.size(56))
    padding: Theme.size(22)
    modal: true
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

    Overlay.modal: Rectangle { color: "#A6050B09" }

    function applyFilterQuery() {
        const nextQuery = searchField.text.trim().toLocaleLowerCase()
        const queryChanged = nextQuery !== root.filterQuery
        root.filterQuery = nextQuery
        if (queryChanged)
            root.selectedIndex = root.visibleCards.length > 0 ? 0 : -1
    }

    Timer {
        id: filterTimer
        interval: 120
        repeat: false
        onTriggered: root.applyFilterQuery()
    }

    background: Rectangle {
        color: Theme.surfaceElevated
        radius: Theme.radiusLarge
        border.width: 1
        border.color: Theme.borderStrong
    }

    function zoneLabel() {
        if (zoneKey === "sideboard")
            return qsTr("Sideboard")
        if (zoneKey === "exile")
            return qsTr("Exile")
        if (zoneKey === "command")
            return qsTr("Command")
        return qsTr("Graveyard")
    }

    function showZone(displayName, seat, zone) {
        ownerDisplayName = displayName
        seatIndex = seat
        zoneKey = zone
        filterTimer.stop()
        searchField.text = ""
        filterQuery = ""
        selectedOrder = []
        contextCardId = ""
        selectedIndex = cards.length > 0 ? 0 : -1
        open()
        searchField.forceActiveFocus()
    }

    function filterCards() {
        const query = filterQuery
        if (query.length === 0)
            return groupedCards
        const result = []
        for (let i = 0; i < groupedCards.length; ++i) {
            const card = groupedCards[i]
            if (cardCatalogModel
                && cardCatalogModel.matchesCardQuery(
                    card.name ? card.name : "",
                    card.setCode ? card.setCode : "",
                    card.collectorNumber ? card.collectorNumber : "",
                    query)) {
                result.push(card)
            } else if (!cardCatalogModel
                       && (card.name ? card.name : "")
                       .toLocaleLowerCase().includes(query)) {
                result.push(card)
            }
        }
        return result
    }

    function groupCards() {
        const groups = []
        const byKey = ({})
        for (let i = 0; i < cards.length; ++i) {
            const card = cards[i]
            const key = (card.name ? card.name.toLocaleLowerCase() : "")
                        + "\u001f"
                        + (card.setCode ? card.setCode.toLocaleLowerCase() : "")
                        + "\u001f"
                        + (card.collectorNumber ? card.collectorNumber : "")
            if (byKey[key] !== undefined) {
                const groupIndex = byKey[key]
                groups[groupIndex].quantity += 1
                groups[groupIndex].cardIds.push(card.id)
                continue
            }
            const grouped = Object.assign({}, card, {
                "quantity": 1,
                "cardIds": [card.id]
            })
            byKey[key] = groups.length
            groups.push(grouped)
        }
        return groups
    }

    function cardForId(cardId) {
        for (let i = 0; i < cards.length; ++i) {
            if (cards[i].id === cardId)
                return cards[i]
        }
        return ({})
    }

    function cardSelected(cardId) {
        return selectedOrder.indexOf(cardId) >= 0
    }

    function groupSelected(card) {
        const cardIds = card && card.cardIds ? card.cardIds : []
        if (cardIds.length === 0)
            return false
        for (let i = 0; i < cardIds.length; ++i) {
            if (!cardSelected(cardIds[i]))
                return false
        }
        return true
    }

    function toggleCardGroup(card) {
        if (!multiSelectEnabled || !card)
            return
        const cardIds = card.cardIds ? card.cardIds : []
        const remove = groupSelected(card)
        const next = []
        for (let i = 0; i < selectedOrder.length; ++i) {
            if (!remove || cardIds.indexOf(selectedOrder[i]) < 0)
                next.push(selectedOrder[i])
        }
        if (!remove) {
            for (let i = 0; i < cardIds.length; ++i) {
                if (next.indexOf(cardIds[i]) < 0)
                    next.push(cardIds[i])
            }
        }
        selectedOrder = next
    }

    function allVisibleSelected() {
        if (!multiSelectEnabled || visibleCards.length === 0)
            return false
        for (let i = 0; i < visibleCards.length; ++i) {
            const cardIds = visibleCards[i].cardIds
                            ? visibleCards[i].cardIds : []
            for (let cardIndex = 0; cardIndex < cardIds.length; ++cardIndex) {
                if (!cardSelected(cardIds[cardIndex]))
                    return false
            }
        }
        return true
    }

    function toggleAllVisible() {
        if (!multiSelectEnabled)
            return
        const deselect = allVisibleSelected()
        const visibleIds = ({})
        for (let i = 0; i < visibleCards.length; ++i) {
            const cardIds = visibleCards[i].cardIds
                            ? visibleCards[i].cardIds : []
            for (let cardIndex = 0; cardIndex < cardIds.length; ++cardIndex)
                visibleIds[cardIds[cardIndex]] = true
        }
        const next = []
        for (let i = 0; i < selectedOrder.length; ++i) {
            if (!deselect || !visibleIds[selectedOrder[i]])
                next.push(selectedOrder[i])
        }
        if (!deselect) {
            const ids = Object.keys(visibleIds)
            for (let i = 0; i < ids.length; ++i) {
                if (next.indexOf(ids[i]) < 0)
                    next.push(ids[i])
            }
        }
        selectedOrder = next
    }

    function requestedCardIdList() {
        if (contextCardId && cardSelected(contextCardId))
            return selectedOrder.slice()
        if (contextCardId)
            return [contextCardId]
        if (selectedOrder.length > 0)
            return selectedOrder.slice()
        return selectedCard.id ? [selectedCard.id] : []
    }

    function requestedCardsOwnedLocally() {
        const cardIds = requestedCardIdList()
        if (cardIds.length === 0)
            return false
        for (let i = 0; i < cardIds.length; ++i) {
            const card = cardForId(cardIds[i])
            if (card.ownerSeat !== localSeatIndex
                && !(card.ownerSeat === undefined
                     && seatIndex === localSeatIndex)) {
                return false
            }
        }
        return true
    }

    function selectedSourceMovable() {
        return zoneKey === "graveyard" || zoneKey === "exile"
               || seatIndex === localSeatIndex
    }

    function requestSelectedMove(toZone) {
        const cardIds = requestedCardIdList()
        if (!canMoveCards || cardIds.length === 0
            || !selectedSourceMovable())
            return
        const sourceSeat = zoneKey === "graveyard" || zoneKey === "exile"
                           ? seatIndex : -1
        let destinationSeat = -1
        if (toZone === "battlefield")
            destinationSeat = localSeatIndex
        else if (toZone === "graveyard" || toZone === "exile")
            destinationSeat = seatIndex
        if (cardIds.length === 1) {
            moveRequested(cardIds[0], zoneKey, sourceSeat,
                          toZone, destinationSeat)
        } else {
            movesRequested(cardIds, zoneKey, sourceSeat,
                           toZone, destinationSeat)
        }
        close()
    }

    function requestCommanderCast() {
        const cardIds = requestedCardIdList()
        if (!canMoveCards || zoneKey !== "command"
                || seatIndex !== localSeatIndex || cardIds.length !== 1) {
            return
        }
        const card = cardForId(cardIds[0])
        if (card.commander !== true)
            return
        castCommanderRequested(card.id)
        close()
    }

    onCardsChanged: {
        const validIds = ({})
        for (let i = 0; i < cards.length; ++i)
            validIds[cards[i].id] = true
        const next = []
        for (let i = 0; i < selectedOrder.length; ++i) {
            if (validIds[selectedOrder[i]])
                next.push(selectedOrder[i])
        }
        selectedOrder = next
        selectedIndex = visibleCards.length > 0 ? 0 : -1
    }

    onClosed: {
        filterTimer.stop()
        seatIndex = -1
        ownerDisplayName = ""
        zoneKey = ""
        selectedIndex = -1
        selectedOrder = []
        contextCardId = ""
        filterQuery = ""
        searchField.text = ""
    }

    contentItem: ColumnLayout {
        spacing: Theme.size(14)

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.size(12)

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Theme.size(3)

                Text {
                    textFormat: Text.PlainText
                    Layout.fillWidth: true
                    text: root.ownerDisplayName + " · " + root.zoneLabel()
                    color: Theme.text
                    font.pixelSize: Theme.fontSize(20)
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }
                Text {
                    textFormat: Text.PlainText
                    Layout.fillWidth: true
                    text: root.zoneKey === "sideboard"
                          ? qsTr("Only you can inspect these sideboard cards.")
                          : qsTr("All players and spectators can inspect these cards.")
                    color: Theme.textSecondary
                    font.pixelSize: Theme.fontSize(11)
                    wrapMode: Text.WordWrap
                }
                Text {
                    textFormat: Text.PlainText
                    Layout.fillWidth: true
                    visible: root.canMoveCards
                    text: root.multiSelectEnabled
                          ? qsTr("Use the checkboxes to select cards, then right-click a selected card to move them together.")
                          : qsTr("Right-click a card for move actions.")
                    color: Theme.textMuted
                    font.pixelSize: Theme.fontSize(10)
                }
            }

            StatusPill {
                text: I18n.count("card", root.cards.length)
                statusColor: Theme.primary
            }

            AppButton {
                objectName: "closeZoneBrowserButton"
                compact: true
                variant: "ghost"
                text: "×"
                accessibleName: qsTr("Close")
                Layout.preferredWidth: Theme.size(40)
                onClicked: root.close()
            }
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 1
            color: Theme.divider
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: Theme.size(16)

            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: Theme.size(10)

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.size(8)

                    AppTextField {
                        id: searchField
                        objectName: "zoneBrowserFilter"
                        Layout.fillWidth: true
                        implicitHeight: Theme.size(44)
                        placeholderText: qsTr("Filter this zone…")
                        onTextEdited: filterTimer.restart()
                    }
                    AppButton {
                        objectName: "selectAllZoneCards"
                        visible: root.multiSelectEnabled && root.canMoveCards
                        compact: true
                        text: root.allVisibleSelected()
                              ? qsTr("Deselect all")
                              : qsTr("Select all")
                        onClicked: root.toggleAllVisible()
                    }
                    StatusPill {
                        visible: root.multiSelectEnabled && root.canMoveCards
                        text: qsTr("Selected") + " · "
                              + root.selectedCount
                        statusColor: Theme.primary
                    }
                }

                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    ListView {
                        id: cardList
                        objectName: "zoneBrowserCards"
                        anchors.fill: parent
                        model: root.visibleCards
                        spacing: Theme.size(7)
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                        delegate: Surface {
                            id: cardRow
                            required property var modelData
                            required property int index
                            objectName: "zoneBrowserCard" + index
                            width: ListView.view.width
                            height: Theme.size(76)
                            color: root.groupSelected(modelData)
                                   ? Theme.primaryMuted
                                   : (root.selectedIndex === index
                                      ? Theme.surfaceHover
                                      : Theme.surfaceMuted)
                            border.color: root.groupSelected(modelData)
                                          ? Theme.primary
                                          : (root.selectedIndex === index
                                             ? Theme.borderStrong
                                             : Theme.border)

                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: Theme.size(7)
                                spacing: Theme.size(11)

                                Image {
                                    Layout.preferredWidth: Theme.size(54)
                                    Layout.fillHeight: true
                                    source: root.cardCatalogModel
                                            ? root.cardCatalogModel.imageSource(
                                                  cardRow.modelData.name,
                                                  cardRow.modelData.setCode,
                                                  cardRow.modelData.collectorNumber)
                                            : ""
                                    fillMode: Image.PreserveAspectFit
                                    asynchronous: true
                                }
                                Rectangle {
                                    id: selectionBox
                                    objectName: "zoneSelectBox" + cardRow.index
                                    visible: root.multiSelectEnabled
                                             && root.canMoveCards
                                    Layout.preferredWidth: Theme.size(22)
                                    Layout.preferredHeight: Theme.size(22)
                                    radius: Theme.radiusSmall
                                    color: root.groupSelected(cardRow.modelData)
                                           ? Theme.primary : "transparent"
                                    border.width: 1
                                    border.color:
                                        root.groupSelected(cardRow.modelData)
                                        ? Theme.primary : Theme.borderStrong
                                    Text {
                                        textFormat: Text.PlainText
                                        anchors.centerIn: parent
                                        text: "✓"
                                        visible: root.groupSelected(
                                                     cardRow.modelData)
                                        color: Theme.primaryInk
                                        font.pixelSize: Theme.fontSize(11)
                                        font.weight: Font.Bold
                                    }
                                    TapHandler {
                                        acceptedButtons: Qt.LeftButton
                                        cursorShape: Qt.PointingHandCursor
                                        onTapped: {
                                            root.selectedIndex = cardRow.index
                                            root.toggleCardGroup(
                                                        cardRow.modelData)
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
                                        text: cardRow.modelData.setCode
                                              + " · #"
                                              + cardRow.modelData.collectorNumber
                                        color: Theme.textMuted
                                        font.pixelSize: Theme.fontSize(10)
                                        elide: Text.ElideRight
                                    }
                                }
                                StatusPill {
                                    visible: cardRow.modelData.quantity > 1
                                    text: "×" + cardRow.modelData.quantity
                                    statusColor: Theme.primary
                                }
                            }

                            TapHandler {
                                acceptedButtons: Qt.LeftButton
                                cursorShape: Qt.PointingHandCursor
                                onTapped: root.selectedIndex = cardRow.index
                            }
                            TapHandler {
                                acceptedButtons: Qt.RightButton
                                onTapped: function(point) {
                                    root.selectedIndex = cardRow.index
                                    root.contextCardId = cardRow.modelData.id
                                    const position = cardRow.mapToItem(
                                        root.contentItem,
                                        point.position.x,
                                        point.position.y)
                                    zoneCardMenu.x = position.x
                                    zoneCardMenu.y = position.y
                                    zoneCardMenu.open()
                                }
                            }
                        }
                    }

                    Text {
                        textFormat: Text.PlainText
                        anchors.centerIn: parent
                        visible: cardList.count === 0
                        text: root.cards.length === 0
                              ? qsTr("This zone is empty")
                              : qsTr("No cards match this filter")
                        color: Theme.textMuted
                        font.pixelSize: Theme.fontSize(11)
                    }
                }
            }

            Rectangle {
                Layout.fillHeight: true
                implicitWidth: 1
                color: Theme.divider
            }

            ColumnLayout {
                Layout.preferredWidth: Theme.size(360)
                Layout.fillHeight: true
                spacing: Theme.size(12)

                Surface {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    color: Theme.surfaceMuted
                    clip: true

                    Image {
                        anchors.fill: parent
                        anchors.margins: Theme.size(12)
                        source: root.selectedCard.name && root.cardCatalogModel
                                ? root.cardCatalogModel.imageSource(
                                      root.selectedCard.name,
                                      root.selectedCard.setCode,
                                      root.selectedCard.collectorNumber)
                                : ""
                        fillMode: Image.PreserveAspectFit
                        asynchronous: true
                    }

                    Text {
                        textFormat: Text.PlainText
                        anchors.centerIn: parent
                        visible: !root.selectedCard.name
                        text: qsTr("Select a card")
                        color: Theme.textMuted
                        font.pixelSize: Theme.fontSize(11)
                    }
                }

                Text {
                    textFormat: Text.PlainText
                    Layout.fillWidth: true
                    text: root.selectedCard.name ? root.selectedCard.name
                                                 : root.zoneLabel()
                    color: Theme.text
                    font.pixelSize: Theme.fontSize(15)
                    font.weight: Font.DemiBold
                    wrapMode: Text.WordWrap
                }
                Text {
                    textFormat: Text.PlainText
                    Layout.fillWidth: true
                    visible: root.selectedCard.name !== undefined
                    text: (root.selectedCard.setCode || "") + " · #"
                          + (root.selectedCard.collectorNumber || "")
                    color: Theme.textMuted
                    font.pixelSize: Theme.fontSize(10)
                    elide: Text.ElideRight
                }

                AppButton {
                    objectName: "doneZoneBrowserButton"
                    Layout.fillWidth: true
                    text: qsTr("Done")
                    onClicked: root.close()
                }
            }
        }
    }

    Menu {
        id: zoneCardMenu
        objectName: "zoneCardMenu"
        title: root.requestedCardIdList().length > 1
               ? qsTr("Move selected") + " · "
                 + root.requestedCardIdList().length : ""

        ConditionalMenuItem {
            objectName: "zoneCardCastCommander"
            visible: root.zoneKey === "command"
                     && root.seatIndex === root.localSeatIndex
            text: qsTr("Cast commander")
            enabled: root.canMoveCards
                     && root.requestedCardIdList().length === 1
                     && root.cardForId(
                         root.requestedCardIdList()[0]).commander === true
            onTriggered: root.requestCommanderCast()
        }
        ConditionalMenuSeparator {
            visible: root.zoneKey === "command"
                     && root.seatIndex === root.localSeatIndex
        }

        MenuItem {
            objectName: "zoneCardToBattlefield"
            text: qsTr("Move to battlefield")
            enabled: root.canMoveCards
                     && root.requestedCardIdList().length > 0
                     && root.selectedSourceMovable()
            onTriggered: root.requestSelectedMove("battlefield")
        }
        MenuItem {
            objectName: "zoneCardToHand"
            text: qsTr("Move to hand")
            enabled: root.canMoveCards
                     && root.requestedCardIdList().length > 0
                     && root.selectedSourceMovable()
                     && root.requestedCardsOwnedLocally()
            onTriggered: root.requestSelectedMove("hand")
        }
        ConditionalMenuItem {
            objectName: "zoneCardToLibrary"
            text: qsTr("Move to top of library")
            visible: root.zoneKey === "graveyard" || root.zoneKey === "exile"
            enabled: visible && root.canMoveCards
                     && root.requestedCardIdList().length > 0
                     && root.selectedSourceMovable()
                     && root.requestedCardsOwnedLocally()
            onTriggered: root.requestSelectedMove("library")
        }
        MenuItem {
            objectName: "zoneCardToGraveyard"
            text: qsTr("Move to graveyard")
            enabled: root.canMoveCards
                     && root.requestedCardIdList().length > 0
                     && root.selectedSourceMovable()
                     && root.zoneKey !== "graveyard"
            onTriggered: root.requestSelectedMove("graveyard")
        }
        MenuItem {
            objectName: "zoneCardToExile"
            text: qsTr("Move to exile")
            enabled: root.canMoveCards
                     && root.requestedCardIdList().length > 0
                     && root.selectedSourceMovable()
                     && root.zoneKey !== "exile"
            onTriggered: root.requestSelectedMove("exile")
        }
    }
}
