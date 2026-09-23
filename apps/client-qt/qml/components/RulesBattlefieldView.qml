// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

Surface {
    id: root

    required property var tableController
    readonly property var interaction: tableController.interaction || null
    readonly property alias layoutState: layoutState

    function laneAt(index: int): var {
        return playerRepeater.itemAt(index)
    }

    RulesBattlefieldLayout {
        id: layoutState
        gameId: String(root.tableController.rulesSession.gameId || "")
    }

    Timer {
        id: prunePositions
        interval: 0
        onTriggered: {
            const keys = ({})
            for (let index = 0; index < playerRepeater.count; ++index) {
                const lane = root.laneAt(index)
                if (lane)
                    lane.collectCardKeys(keys)
            }
            layoutState.retain(keys)
        }
    }

    function relativePosition(seat, index, count) {
        const localSeat = root.tableController.localSeat
        if (localSeat < 0)
            return index
        return (seat - localSeat + count) % count
    }

    function laneRow(seat, index, count) {
        if (count <= 2) {
            if (root.tableController.localSeat < 0)
                return index
            return seat === root.tableController.localSeat ? 1 : 0
        }
        const relative = relativePosition(seat, index, count)
        return relative === 0 || relative === 3 ? 1 : 0
    }

    function laneColumn(seat, index, count) {
        if (count <= 2)
            return 0
        const relative = relativePosition(seat, index, count)
        return relative >= 2 ? 1 : 0
    }

    objectName: "rulesBattlefieldPanel"
    color: Theme.useGlass || TableBackgrounds.hasImage ? "transparent" : Theme.surfaceMuted
    radius: 0
    border.width: 0

    GridLayout {
        id: battlefieldGrid
        objectName: "rulesBattlefieldGrid"
        anchors.fill: parent
        anchors.margins: Theme.size(4)
        columns: playerRepeater.count > 2 ? 2 : 1
        rows: playerRepeater.count > 2 ? 2 : Math.max(1, playerRepeater.count)
        columnSpacing: Theme.size(6)
        rowSpacing: Theme.size(6)

        Repeater {
            id: playerRepeater
            model: root.tableController.rulesSession.players

            delegate: Surface {
                id: lane

                required property int index
                required property int seat
                required property string name
                required property string status
                required property int life
                required property string countersSummary
                required property string manaSummary
                required property var manaPool

                readonly property bool isOwn:
                    seat === root.tableController.localSeat
                readonly property bool isActive:
                    seat === root.tableController.rulesSession.activeSeat
                readonly property bool hasPriority:
                    seat === root.tableController.rulesSession.prioritySeat
                readonly property bool targetActionable:
                    root.interaction ? root.interaction.seatActionable(seat) : false
                readonly property bool targetSelected:
                    root.interaction ? root.interaction.seatSelected(seat) : false
                // Reserve potential controls so priority changes and the first
                // custom placement cannot resize the battlefield under a card.
                readonly property real badgeRowWidth:
                    arrangeAction.implicitWidth + turnBadge.implicitWidth
                    + priorityBadge.implicitWidth + Theme.size(10)
                    + (root.tableController.canViewSpectatorHands
                       ? viewHandAction.implicitWidth + Theme.size(5) : 0)
                readonly property real badgeRowHeight:
                    Math.max(arrangeAction.implicitHeight, viewHandAction.implicitHeight,
                             turnBadge.implicitHeight, priorityBadge.implicitHeight)
                readonly property bool stackedHeader:
                    width < badgeRowWidth + Theme.size(166)
                readonly property real headerHeight:
                    Math.max(playerTarget.y + playerTarget.height,
                             laneBadges.y + badgeRowHeight)
                readonly property bool frontAtTop: Layout.row === 1
                readonly property bool compactLane: height < Theme.size(400)
                readonly property bool footerBesideDock: compactLane && opponentZoneDock.visible
                                                        && width >= Theme.size(460)
                readonly property real cardFootprint: Math.min(
                    root.tableController.battlefieldCardHeight,
                    Math.max(Theme.size(88), Math.floor(
                        (battlefieldViewport.height - Theme.size(56)) / 2)))
                property bool draggingCard: false
                property bool followCombatFront: true
                property var arrangedCards: []
                readonly property var arrangement: layoutState.arrange(arrangedCards,
                    battlefieldViewport.width, battlefieldViewport.height,
                    cardFootprint, Theme.size(8), frontAtTop)

                function cardAt(index: int): var {
                    return cardRepeater.itemAt(index)
                }

                function collectCardKeys(keys) {
                    for (let index = 0; index < cardRepeater.count; ++index) {
                        const card = lane.cardAt(index)
                        if (card && card.controllerSeat === lane.seat)
                            keys[layoutState.key(lane.seat, card.cardId)] = true
                    }
                }

                function arrangeCards() {
                    const cards = []
                    for (let index = 0; index < cardRepeater.count; ++index) {
                        const card = lane.cardAt(index)
                        if (card && card.controllerSeat === lane.seat) {
                            cards.push({cardId: card.cardId, category: card.category,
                                        sortName: card.visibleIdentity && !card.faceDown ? card.name : ""})
                        }
                    }
                    arrangedCards = cards
                    prunePositions.restart()
                }

                onArrangementChanged: {
                    if (!frontAtTop && followCombatFront)
                        battlefieldViewport.contentY = Math.max(0,
                            arrangement.contentHeight - battlefieldViewport.height)
                }

                function requestArrangement() {
                    Qt.callLater(lane.arrangeCards)
                }

                objectName: "rulesBattlefieldLane" + seat
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.row: root.laneRow(
                                seat, index, playerRepeater.count)
                Layout.column: root.laneColumn(
                                   seat, index, playerRepeater.count)
                color: Theme.useGlass
                       ? "transparent"
                       : TableBackgrounds.hasImage
                         ? Theme.withAlpha(isOwn ? Theme.primaryMuted : Theme.surfaceHover, 0.24)
                         : (isOwn ? Theme.primaryMuted : Theme.surfaceHover)
                radius: Theme.useGlass ? Theme.radiusLarge : 0
                border.width: Theme.useGlass
                              ? 0
                              : targetSelected ? Theme.size(3)
                              : targetActionable || isActive ? Theme.size(2) : 1
                border.color: targetSelected ? Theme.primary
                              : targetActionable ? Theme.accent
                              : isActive ? Theme.primary : Theme.border

                Rectangle {
                    anchors.fill: parent
                    radius: lane.radius
                    antialiasing: true
                    visible: Theme.useGlass
                    color: lane.isOwn
                           ? Theme.withAlpha(Theme.primary, 0.06)
                           : "#10000000"
                    border.width: lane.targetSelected ? Theme.size(3)
                                  : lane.targetActionable ? Theme.size(2) : 1
                    border.color: lane.targetSelected ? Theme.primary
                                  : lane.targetActionable ? Theme.accent
                                  : lane.isActive || lane.hasPriority
                                  ? Theme.withAlpha(Theme.primary, 0.55)
                                  : Theme.playmatStitch
                }

                DropArea {
                    id: handCardDrop

                    objectName: "rulesBattlefieldDropArea" + lane.seat
                    anchors.fill: parent
                    z: 15
                    enabled: lane.isOwn
                    keys: ["hexproof/rules-card"]

                    onDropped: function(drop) {
                        const source = drop.source
                        if (!root.tableController.playDraggedHandCardSource(
                                    source)) {
                            drop.accepted = false
                            return
                        }
                        drop.acceptProposedAction()
                    }
                }

                Rectangle {
                    anchors.fill: parent
                    z: 16
                    visible: handCardDrop.containsDrag
                    color: "transparent"
                    border.width: Theme.size(2)
                    border.color: Theme.primary
                }

                Rectangle {
                    id: playerTarget
                    objectName: "rulesPlayerTarget" + lane.seat
                    anchors.left: parent.left
                    anchors.right: lane.stackedHeader ? parent.right : laneBadges.left
                    anchors.top: parent.top
                    anchors.leftMargin: Theme.size(5)
                    anchors.rightMargin: Theme.size(8)
                    anchors.topMargin: Theme.size(5)
                    height: Theme.size(28)
                    z: 20
                    radius: Theme.radiusSmall
                    color: lane.targetSelected ? Theme.primaryMuted
                           : lane.targetActionable ? Theme.surfaceElevated : "transparent"
                    border.width: lane.targetActionable || lane.targetSelected || activeFocus ? Theme.size(2) : 0
                    border.color: lane.targetSelected || activeFocus ? Theme.primary : Theme.accent
                    activeFocusOnTab: lane.targetActionable
                    Keys.onReturnPressed: { if (lane.targetActionable) root.interaction.activateSeat(lane.seat) }
                    Keys.onSpacePressed: { if (lane.targetActionable) root.interaction.activateSeat(lane.seat) }
                    Accessible.role: lane.targetActionable ? Accessible.Button : Accessible.Graphic
                    Accessible.name: playerSummary.text
                    Accessible.onPressAction: { if (lane.targetActionable) root.interaction.activateSeat(lane.seat) }

                    Text {
                        id: playerSummary
                        textFormat: Text.PlainText
                        objectName: "rulesBattlefieldSummary" + lane.seat
                        anchors.fill: parent
                        anchors.leftMargin: Theme.size(4)
                        anchors.rightMargin: Theme.size(4)
                        text: lane.name + " · " + qsTr("Life %1").arg(lane.life)
                              + " · " + root.tableController.zoneCount(
                                  lane.seat, "hand") + qsTr("H")
                              + " / " + root.tableController.zoneCount(
                                  lane.seat, "library") + qsTr("D")
                        color: lane.isOwn ? Theme.primary : Theme.text
                        font.pixelSize: Theme.fontSize(11)
                        font.weight: Font.Bold
                        style: TableBackgrounds.hasImage ? Text.Outline : Text.Normal
                        styleColor: "#B8000000"
                        elide: Text.ElideRight
                        verticalAlignment: Text.AlignVCenter
                    }

                    TapHandler {
                        enabled: lane.targetActionable
                        acceptedButtons: Qt.LeftButton
                        onTapped: root.interaction.activateSeat(lane.seat)
                    }
                    HoverHandler {
                        cursorShape: lane.targetActionable ? Qt.PointingHandCursor : Qt.ArrowCursor
                    }
                }

                RowLayout {
                    id: laneBadges
                    anchors.right: parent.right
                    anchors.top: lane.stackedHeader ? playerTarget.bottom : parent.top
                    anchors.margins: Theme.size(7)
                    anchors.topMargin: lane.stackedHeader ? Theme.size(4) : 0
                    width: Math.min(implicitWidth, Math.max(0, lane.width - Theme.size(14)))
                    height: lane.badgeRowHeight
                    spacing: Theme.size(5)
                    z: 20

                    AppButton {
                        id: arrangeAction
                        objectName: "rulesAutoArrange" + lane.seat
                        visible: layoutState.hasSeatPositions(lane.seat)
                        compact: true
                        text: qsTr("Auto arrange")
                        onClicked: layoutState.reset(lane.seat)
                    }

                    AppButton {
                        id: viewHandAction
                        objectName: "rulesViewHandButton" + lane.seat
                        visible: root.tableController.canViewSpectatorHands
                        compact: true
                        variant: root.tableController.handOwnerSeat === lane.seat
                                 ? "primary" : "secondary"
                        text: qsTr("View hand")
                        onClicked: root.tableController.spectatedHandSeat = lane.seat
                    }


                    StatusPill {
                        id: turnBadge
                        visible: lane.isActive
                        Layout.minimumWidth: 0
                        text: lane.isOwn ? qsTr("Your turn")
                                         : qsTr("Current turn")
                        statusColor: Theme.primary
                    }

                    StatusPill {
                        id: priorityBadge
                        visible: lane.hasPriority
                        Layout.minimumWidth: 0
                        text: qsTr("Priority")
                        statusColor: Theme.accent
                    }
                }

                StatusPill {
                    objectName: "rulesPlayerCounters" + lane.seat
                    visible: lane.countersSummary.length > 0
                    id: playerCounters
                    anchors.left: parent.left
                    anchors.bottom: parent.bottom
                    anchors.margins: Theme.size(5)
                    maximumWidth: lane.footerBesideDock
                                  ? Math.max(0, lane.width - opponentZoneDock.width - Theme.size(25)) * 0.45
                                  : lane.width * 0.45
                    z: 20
                    text: lane.countersSummary
                    statusColor: Theme.primary
                    ToolTip {
                        visible: countersHover.hovered
                        contentItem: Text {
                            textFormat: Text.PlainText
                            text: lane.countersSummary
                            color: Theme.text
                        }
                    }
                    HoverHandler { id: countersHover }
                }

                ForgeManaPool {
                    anchors.left: parent.left
                    anchors.bottom: parent.bottom
                    anchors.margins: Theme.size(8)
                    manaPool: lane.manaPool
                    seat: lane.seat
                    unit: Theme.size(1)
                    z: 21
                }

                Text {
                    textFormat: Text.PlainText
                    objectName: "rulesBattlefieldPlayerStatus" + lane.seat
                    anchors.left: playerCounters.visible ? playerCounters.right : parent.left
                    anchors.right: lane.footerBesideDock ? opponentZoneDock.left : parent.right
                    anchors.bottom: parent.bottom
                    anchors.margins: Theme.size(8)
                    z: 20
                    visible: !lane.manaPool || !(lane.manaPool.length || lane.manaPool.count || 0)
                    text: lane.status
                    color: Theme.textMuted
                    font.pixelSize: Theme.fontSize(9)
                    elide: Text.ElideRight
                }

                RulesOpponentZoneDock {
                    id: opponentZoneDock
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.rightMargin: Theme.size(7)
                    anchors.bottomMargin: Theme.size(lane.footerBesideDock ? 5 : 27)
                    z: 30
                    tableController: root.tableController
                    ownerSeat: lane.seat
                    compact: lane.compactLane
                }

                Text {
                    textFormat: Text.PlainText
                    anchors.centerIn: parent
                    objectName: "rulesBattlefieldEmpty" + lane.seat
                    visible: root.tableController.zoneCount(
                                 lane.seat, "battlefield") === 0
                    text: lane.isOwn
                          && root.tableController.rulesSession.promptPending
                          && root.tableController.rulesSession.promptKind
                             === "chooseAction"
                          ? qsTr("Drag a legal card from your hand here")
                          : qsTr("No permanents on the battlefield")
                    color: Theme.textMuted
                    font.pixelSize: Theme.fontSize(10)
                }

                Flickable {
                    id: battlefieldViewport
                    objectName: "rulesBattlefieldViewport" + lane.seat
                    anchors.fill: parent
                    anchors.topMargin: lane.headerHeight
                    anchors.bottomMargin: opponentZoneDock.visible
                                          ? opponentZoneDock.height + Theme.size(lane.footerBesideDock ? 5 : 32)
                                          : playerCounters.visible ? Theme.size(38) : Theme.size(26)
                    anchors.leftMargin: Theme.size(8)
                    anchors.rightMargin: Theme.size(8)
                    contentWidth: width
                    contentHeight: lane.arrangement.contentHeight
                    interactive: !lane.draggingCard
                    boundsBehavior: Flickable.StopAtBounds
                    clip: true
                    onMovementStarted: lane.followCombatFront = false

                    ScrollBar.vertical: ScrollBar {
                        policy: ScrollBar.AsNeeded
                        onPressedChanged: {
                            if (pressed)
                                lane.followCombatFront = false
                        }
                    }

                    Item {
                        width: battlefieldViewport.width
                        height: battlefieldViewport.contentHeight

                        Repeater {
                            model: lane.arrangement.sections
                            delegate: Text {
                                required property var modelData
                                objectName: "rulesBattlefieldGroup-" + lane.seat + "-" + modelData.category
                                x: modelData.x
                                y: modelData.y
                                width: Math.max(0, modelData.width)
                                height: Theme.size(16)
                                textFormat: Text.PlainText
                                text: modelData.category === "creature" ? qsTr("Creatures")
                                      : modelData.category === "land" ? qsTr("Lands")
                                      : qsTr("Other permanents")
                                color: Theme.textMuted
                                font.pixelSize: Theme.fontSize(8)
                                elide: Text.ElideRight
                            }
                        }

                        Repeater {
                            id: cardRepeater
                            model: root.tableController.rulesSession
                                       .battlefieldCards
                            onItemAdded: lane.requestArrangement()
                            onItemRemoved: lane.requestArrangement()

                            delegate: Item {
                                id: cardSlot
                                required property string cardId
                                required property int controllerSeat
                                required property bool visibleIdentity
                                required property string name
                                required property string setCode
                                required property string collectorNumber
                                required property bool tapped
                                required property bool faceDown
                                required property bool attacking
                                required property string power
                                required property string toughness
                                required property string countersSummary
                                required property int damage
                                required property string attachedTo

                                readonly property string category: {
                                    void root.tableController.cardCatalogModel.imageRevision
                                    return layoutState.category(cardSlot, root.tableController.cardCatalogModel)
                                }
                                readonly property var arrangedPosition: layoutState.position(
                                    lane.seat, cardId, lane.arrangement.positions[cardId],
                                    battlefieldViewport.width - width,
                                    battlefieldViewport.contentHeight - height)
                                property real dragX: 0
                                property real dragY: 0

                                objectName: "rulesBattlefieldPosition-" + lane.seat + "-" + cardId
                                visible: controllerSeat === lane.seat
                                width: lane.cardFootprint
                                height: lane.cardFootprint
                                x: cardDrag.active ? dragX : arrangedPosition.x
                                y: cardDrag.active ? dragY : arrangedPosition.y
                                z: cardDrag.active ? layoutState.latestOrder + 2
                                                   : layoutState.stackingOrder(lane.seat, cardId)
                                onCategoryChanged: lane.requestArrangement()
                                onControllerSeatChanged: lane.requestArrangement()
                                onNameChanged: lane.requestArrangement()

                                RulesCardSurface {
                                    id: cardSurface
                                    objectName: "rulesBattlefieldCard-" + lane.seat + "-" + cardSlot.cardId
                                    anchors.centerIn: parent
                                    width: lane.cardFootprint * root.tableController.battlefieldCardWidth
                                           / root.tableController.battlefieldCardHeight
                                    height: lane.cardFootprint
                                    cardCatalogModel: root.tableController.cardCatalogModel
                                    cardBackSource: root.tableController.cardBackSource
                                    visibleIdentity: cardSlot.visibleIdentity
                                    name: cardSlot.name
                                    setCode: cardSlot.setCode
                                    collectorNumber: cardSlot.collectorNumber
                                    tapped: cardSlot.tapped
                                    faceDown: cardSlot.faceDown
                                    attacking: cardSlot.attacking
                                    power: cardSlot.power
                                    toughness: cardSlot.toughness
                                    countersSummary: cardSlot.countersSummary
                                    damageMarked: cardSlot.damage
                                    attachmentId: cardSlot.attachedTo
                                    inspectable: true
                                    actionable: root.interaction
                                                ? root.interaction.objectActionable("card", cardSlot.cardId) : false
                                    selected: root.interaction
                                              ? root.interaction.objectSelected("card", cardSlot.cardId) : false
                                    exclusiveTap: true
                                    previewEnabled: !cardDrag.active
                                    onActivationRequested: {
                                        if (!root.interaction.activateObject("card", cardSlot.cardId, cardSlot.name))
                                            root.tableController.openCardDetails(cardSlot.cardId)
                                    }
                                    onInspectRequested: root.tableController.openCardDetails(cardSlot.cardId)
                                    onPreviewRequested: {
                                        if (typeof root.tableController.previewCard === "function")
                                            root.tableController.previewCard(cardSlot.cardId, cardSurface)
                                    }
                                    onPreviewEnded: {
                                        if (typeof root.tableController.endCardPreview === "function")
                                            root.tableController.endCardPreview(cardSurface)
                                    }
                                }

                                DragHandler {
                                    id: cardDrag
                                    target: null
                                    acceptedButtons: Qt.LeftButton
                                    cursorShape: active ? Qt.ClosedHandCursor
                                                 : cardSurface.actionable ? Qt.PointingHandCursor : Qt.OpenHandCursor
                                    property real startX: 0
                                    property real startY: 0
                                    property string dragGameId: ""
                                    onActiveChanged: {
                                        lane.draggingCard = active
                                        if (active) {
                                            dragGameId = layoutState.gameId
                                            startX = cardSlot.arrangedPosition.x
                                            startY = cardSlot.arrangedPosition.y
                                            cardSlot.dragX = startX
                                            cardSlot.dragY = startY
                                        } else if (dragGameId === layoutState.gameId) {
                                            layoutState.remember(lane.seat, cardSlot.cardId,
                                                cardSlot.dragX, cardSlot.dragY,
                                                battlefieldViewport.width - cardSlot.width,
                                                battlefieldViewport.contentHeight - cardSlot.height)
                                        }
                                    }
                                    onTranslationChanged: {
                                        if (!active)
                                            return
                                        cardSlot.dragX = layoutState.bounded(startX + translation.x,
                                            battlefieldViewport.width - cardSlot.width)
                                        cardSlot.dragY = layoutState.bounded(startY + translation.y,
                                            battlefieldViewport.contentHeight - cardSlot.height)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
