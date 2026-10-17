// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors
pragma ComponentBehavior: Bound
pragma Translator: "ForgeDuelTable"
import QtQuick
import QtQuick.Controls.Basic

Rectangle {
    id: root
    required property var presentation
    required property int seat
    required property string name
    required property string status
    required property int life
    required property string countersSummary
    required property var manaPool
    property bool nearSide: false
    readonly property var tableController: presentation.tableController
    readonly property var session: tableController.rulesSession
    readonly property var combat: tableController.combatInteraction
    readonly property real unit: presentation.unit
    readonly property bool eliminated: status === "lost" || status === "conceded"
    readonly property bool activeTurn: !eliminated && session.activeSeat === seat && presentation.turnReady
    readonly property bool hasPriority: !eliminated && session.prioritySeat === seat && presentation.turnReady
    readonly property bool actionable: combat.active ? combat.seatActionable(seat) : tableController.interaction.seatActionable(seat)
    readonly property bool selected: presentation.locatedSeat === seat
        || (combat.active ? combat.seatSelected(seat) : tableController.interaction.seatSelected(seat))
    readonly property bool underAttack: (session.battlefieldRelationships || []).some(
        link => link.kind === "attack" && !link.targetId && link.targetSeat === seat)
    readonly property bool combatHovered: combat.hoveredTarget
        && combat.hoveredTarget.kind === "player" && combat.hoveredTarget.seat === seat
    readonly property real inset: 8 * unit
    readonly property real zoneHeight: 44 * unit
    // Metadata stays at the outside edge; both rows of upright cards meet
    // at the center phase strip instead of being separated by two headers.
    readonly property real headerHeight: zoneHeight + 2 * inset
    readonly property real headerTop: nearSide ? height - headerHeight : 0
    readonly property real boardTop: nearSide ? inset : headerHeight
    readonly property real boardHeight: Math.max(0, height - headerHeight - inset)
    readonly property string laneFlow: fieldLayout.placement.flow
    readonly property real infoRight: zoneRow.x - inset
        - (mana.visible ? mana.width + inset : 0) - (viewHand.visible ? viewHand.width + inset : 0)
    readonly property string clockText: presentation.actionClockText(seat)
    objectName: "forgeField-" + seat
    radius: 12 * unit
    color: Theme.withAlpha("#0d171b", eliminated ? 0.25 : 0.55)
    border.width: activeTurn || hasPriority || selected || actionable || underAttack ? 2 : 1
    border.color: underAttack ? "#d4654f" : selected ? Theme.accent
        : actionable || hasPriority ? Theme.primary : activeTurn ? Theme.warning : Theme.withAlpha(Theme.borderStrong, 0.4)
    function activateSeat() {
        if (!actionable) return
        if (combat.active) combat.activateSeat(seat)
        else tableController.interaction.activateSeat(seat)
    }
    function availableWidth(top, extent) {
        void root.x; void root.y
        if (root.parent) { void root.parent.x; void root.parent.y }
        const origin = root.mapToItem(root.presentation, 0, top)
        return Math.max(0, Math.min(root.width, root.presentation.unobscuredRight(origin.y, extent) - origin.x))
    }
    function pointFor(id, target) {
        void root.x; void root.y; void root.width; void root.height
        for (const lane of [creatures, lands, others]) {
            const point = lane.pointFor(id, target)
            if (point.x !== 0) return point
        }
        return Qt.point(0, 0)
    }
    function playerPoint(target) { return playerTarget.mapToItem(target, playerTarget.width / 2, playerTarget.height / 2) }
    function reveal(id) {
        for (const lane of [creatures, lands, others])
            if (lane.reveal(id)) return true
        return false
    }

    Item {
        id: header
        parent: root.presentation
        z: 35
        visible: root.visible
        readonly property point fieldOrigin: {
            void root.x; void root.y; void root.width; void root.height
            if (root.parent) { void root.parent.x; void root.parent.y }
            return root.mapToItem(root.presentation, 0, 0)
        }
        x: fieldOrigin.x; y: fieldOrigin.y + root.headerTop
        width: root.width; height: root.headerHeight
    }
    Rectangle {
        id: playerTarget
        parent: header
        objectName: "rulesPlayerTarget" + root.seat
        x: root.inset; y: (root.headerHeight - height) / 2
        width: 36 * root.unit; height: width
        radius: width / 2
        color: Theme.withAlpha(root.eliminated ? Theme.textMuted : Theme.accent, 0.12)
        border.width: root.actionable || root.selected || root.combatHovered ? 3 : 1
        border.color: root.combatHovered ? Theme.primary : root.selected || root.actionable ? Theme.accent : Theme.borderStrong
        activeFocusOnTab: root.actionable
        Accessible.role: Accessible.Button
        Accessible.name: root.name + ", " + qsTr("Life %1").arg(root.life)
        Accessible.onPressAction: root.activateSeat()
        Keys.onReturnPressed: root.activateSeat()
        Keys.onSpacePressed: root.activateSeat()
        Text {
            anchors.centerIn: parent
            textFormat: Text.PlainText
            text: root.life
            color: root.eliminated ? Theme.textMuted : Theme.accent
            font.pixelSize: 22 * root.unit
            font.weight: Font.DemiBold
        }
        TapHandler { enabled: root.actionable; onTapped: root.activateSeat() }
        HoverHandler {
            enabled: root.combat.canAct && root.actionable
            cursorShape: root.actionable ? Qt.PointingHandCursor : Qt.ArrowCursor
            onHoveredChanged: root.combat.hoverSeat(root.seat, hovered)
        }
    }
    Column {
        parent: header
        x: playerTarget.x + playerTarget.width + 10 * root.unit
        y: root.inset
        width: Math.max(0, root.infoRight - x)
        spacing: 2 * root.unit
        Text {
            objectName: "forgePlayerName-" + root.seat
            textFormat: Text.PlainText
            width: parent.width
            text: root.name
            elide: Text.ElideRight
            color: root.eliminated ? Theme.textMuted : Theme.text
            font.pixelSize: 12 * root.unit
            font.weight: Font.DemiBold
        }
        Text {
            objectName: "forgePlayerZones-" + root.seat
            textFormat: Text.PlainText
            width: parent.width
            text: [qsTr("Hand · %1").arg(root.tableController.zoneCount(root.seat, "hand")),
                root.countersSummary, root.clockText].filter(v => v.length).join(" · ")
            elide: Text.ElideRight
            color: Theme.textSecondary
            font.pixelSize: 10 * root.unit
        }
        Text {
            objectName: "forgeSeatStatus-" + root.seat
            textFormat: Text.PlainText
            width: parent.width
            text: root.eliminated ? I18n.rulesPlayerStatusLabel(root.status)
                : [root.activeTurn ? qsTranslate("RulesBattlefieldView", "Current turn") : "",
                    root.hasPriority ? qsTranslate("RulesBattlefieldView", "Priority") : ""].filter(v => v.length).join(" · ")
            elide: Text.ElideRight
            color: root.hasPriority ? Theme.primary : Theme.warning
            font.pixelSize: 10 * root.unit
        }
    }
    ForgeFieldLayout {
        id: fieldLayout
        width: Math.max(0, root.availableWidth(root.boardTop, root.boardHeight) - 2 * root.inset)
        height: root.boardHeight
        unit: root.unit; nearSide: root.nearSide
        creatureLane: creatures; landLane: lands; otherLane: others
    }
    ForgeCardLane {
        id: creatures
        objectName: "forgeCreatures-" + root.seat
        x: root.inset + fieldLayout.placement.creatures.x
        y: root.boardTop + fieldLayout.placement.creatures.y
        width: fieldLayout.placement.creatures.width; height: fieldLayout.placement.creatures.height
        tableController: root.tableController
        unit: root.unit; ownerSeat: root.seat
        maxFaceWidth: 200 * unit
        alignBottom: !root.nearSide
        showCaption: false
        combatForward: root.nearSide ? -1 : 1
        locatedId: root.presentation.locatedId
    }
    ForgeCardLane {
        id: lands
        objectName: "forgeLands-" + root.seat
        x: root.inset + fieldLayout.placement.lands.x
        y: root.boardTop + fieldLayout.placement.lands.y
        width: fieldLayout.placement.lands.width; height: fieldLayout.placement.lands.height
        tableController: root.tableController
        unit: root.unit; ownerSeat: root.seat
        category: "land"; showCaption: false; maxFaceWidth: 112 * unit
        alignBottom: !root.nearSide
        locatedId: root.presentation.locatedId
    }
    ForgeCardLane {
        id: others
        objectName: "forgeOther-" + root.seat
        x: root.inset + fieldLayout.placement.others.x
        y: root.boardTop + fieldLayout.placement.others.y
        width: fieldLayout.placement.others.width; height: fieldLayout.placement.others.height
        tableController: root.tableController
        unit: root.unit; ownerSeat: root.seat
        category: "other"; showCaption: false; maxFaceWidth: 112 * unit
        alignBottom: !root.nearSide
        locatedId: root.presentation.locatedId
    }
    Row {
        id: zoneRow
        parent: header
        objectName: "forgeSeatZones-" + root.seat
        x: root.availableWidth(root.headerTop + y, height) - width - root.inset
        y: root.inset
        width: Math.min(226 * root.unit, Math.max(0, root.availableWidth(root.headerTop + y, height) - 200 * root.unit))
        height: root.zoneHeight
        spacing: 6 * root.unit
        Repeater {
            model: ["library", "graveyard", "exile", "command"]
            delegate: ForgeZonePile {
                required property string modelData
                objectName: "forgeSeatZone-" + root.seat + "-" + modelData
                width: Math.min(52 * root.unit, Math.max(0, (zoneRow.width - 3 * zoneRow.spacing) / 4)); height: root.zoneHeight
                tableController: root.tableController
                unit: root.unit; ownerSeat: root.seat; zone: modelData
                compact: true; summary: true
                onActivated: root.presentation.openZone(root.seat, zone)
            }
        }
    }
    ForgeManaPool {
        id: mana
        objectName: "forgeManaPool-" + root.seat
        parent: header
        x: zoneRow.x - root.inset - width
            - (viewHand.visible ? viewHand.width + root.inset : 0)
        y: (root.headerHeight - height) / 2
        manaPool: root.manaPool
        seat: root.seat; unit: root.unit
        visible: root.visible && root.manaPool.length > 0
    }
    AppButton {
        id: viewHand
        parent: header
        objectName: "forgeViewHand-" + root.seat
        visible: root.tableController.canViewSpectatorHands
        x: zoneRow.x - width - root.inset
        y: (root.headerHeight - height) / 2
        compact: true
        text: qsTr("View hand")
        onClicked: root.tableController.spectatedHandSeat = root.seat
    }
    DropArea {
        objectName: "forgeSeatHandDrop-" + root.seat
        x: root.inset; y: root.boardTop
        width: root.width - 2 * root.inset; height: root.boardHeight
        enabled: root.seat === root.tableController.handOwnerSeat && root.tableController.localSeat >= 0
        keys: ["hexproof/rules-card"]
        onDropped: drop => {
            if (root.tableController.playDraggedHandCardSource(drop.source)) drop.acceptProposedAction()
            else drop.accepted = false
        }
    }
}
