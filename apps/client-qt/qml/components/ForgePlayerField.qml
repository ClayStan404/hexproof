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
    readonly property bool offered: combat.active ? combat.seatOffered(seat) : tableController.interaction.seatOffered(seat)
    readonly property bool actionable: offered && (combat.active ? combat.canAct : tableController.interaction.canRespond)
    readonly property bool waiting: offered && tableController.interaction.waitingForResponse
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
    // The existing top inset already contributes to the delta's clearance.
    readonly property real lifeDeltaClearance: Math.max(0, lifeReadout.deltaClearance - inset)
    readonly property real identityHeight: zoneHeight + 2 * inset + lifeDeltaClearance
    readonly property real minimumHeaderWidth: Math.max(162 * unit,
        viewHand.visible ? viewHand.implicitWidth + 2 * inset : 0)
    readonly property bool headerAboveDock: nearSide && presentation.decisionDock
        && presentation.decisionDock.visible && sideHeaderWidth < minimumHeaderWidth
    readonly property real headerAvailableWidth: headerAboveDock
        ? availableWidth(height - identityHeight, identityHeight) : sideHeaderWidth
    // Header wrapping is structural, as in the original single-row layout.
    // A transient pool may wrap inside that row; it never adds battlefield height.
    readonly property bool stackedHeader: headerAvailableWidth < 162 * unit + 226 * unit + inset
        + (viewHand.visible ? viewHand.implicitWidth + inset : 0)
    readonly property real inlineManaWidth: 6 * (20 * unit + manaDigits.advanceWidth) + 46 * unit
    readonly property bool compactInlineMana: !stackedHeader && inlineManaWidth
        > zoneRow.x - 2 * inset - identity.x - 24 * unit
          - (viewHand.visible ? viewHand.implicitWidth + inset : 0)
    // Public mana is transient. It uses the original inline space on a wide
    // header, or one fixed row in an already narrow header; neither gaining
    // nor spending it may resize the battlefield above this metadata.
    readonly property real manaRowHeight: 28 * unit
    TextMetrics {
        id: manaDigits
        text: "99"
        font.pixelSize: 13 * root.unit
        font.bold: true
    }
    readonly property real headerHeight: stackedHeader
        ? identityHeight + zoneRow.height + inset
          + manaRowHeight + inset
          + (viewHand.visible ? viewHand.implicitHeight + inset : 0)
        : identityHeight
    readonly property real headerTop: {
        if (!nearSide) return 0
        let top = height - headerHeight
        if (headerAboveDock) {
            void root.y
            if (root.parent) void root.parent.y
            const origin = root.mapToItem(presentation, 0, 0)
            top = Math.min(top, presentation.dockReservation.y - origin.y - headerHeight - inset)
        }
        return Math.max(0, top)
    }
    readonly property real boardTop: nearSide ? inset : headerHeight
    readonly property real boardHeight: Math.max(0, nearSide ? headerTop - inset : height - headerHeight - inset)
    readonly property real infoRight: stackedHeader ? headerAvailableWidth - inset : zoneRow.x - inset
        - (mana.visible ? mana.width + inset : 0) - (viewHand.visible ? viewHand.width + inset : 0)
    readonly property string clockText: presentation.actionClockText(seat)
    objectName: "forgeField-" + seat
    radius: 12 * unit
    color: Theme.withAlpha("#0d171b", eliminated ? 0.25 : 0.55)
    border.width: activeTurn || hasPriority || selected || offered || underAttack ? 2 : 1
    border.color: underAttack ? "#d4654f" : selected ? Theme.accent
        : offered ? Theme.withAlpha(Theme.primary, waiting ? 0.5 : 1)
        : hasPriority ? Theme.primary : activeTurn ? Theme.warning : Theme.withAlpha(Theme.borderStrong, 0.4)
    function activateSeat() {
        if (!actionable) {
            if (waiting) tableController.interaction.responseBlocked("player", "" + seat)
            return
        }
        if (combat.active) combat.activateSeat(seat)
        else tableController.interaction.activateSeat(seat)
    }
    function availableWidth(top, extent) {
        void root.x; void root.y
        if (root.parent) { void root.parent.x; void root.parent.y }
        const origin = root.mapToItem(root.presentation, 0, top)
        return Math.max(0, Math.min(root.width, root.presentation.unobscuredRight(origin.y, extent) - origin.x))
    }
    readonly property real sideHeaderWidth: {
        // Probe the fixed outside identity row, independently of wrapping, to
        // avoid a height/width binding cycle when an inspector narrows the field.
        const top = nearSide ? height - identityHeight : 0
        let available = availableWidth(top, identityHeight)
        const dock = presentation.decisionDock
        if (!dock || !dock.visible)
            return available
        const origin = root.mapToItem(presentation, 0, top)
        const reservation = presentation.dockReservation
        // Keep the metadata beside the dock's stable reservation. The card
        // lanes still use the full field width, independent of decisions.
        if (origin.y < reservation.y + reservation.height && origin.y + identityHeight > reservation.y)
            available = Math.min(available, reservation.x - 12 * unit - origin.x)
        return Math.max(0, available)
    }
    function pointFor(id, target) {
        void root.x; void root.y; void root.width; void root.height
        if (root.parent) { void root.parent.x; void root.parent.y }
        for (const lane of [creatures, lands, planeswalkers, others]) {
            const point = lane.pointFor(id, target)
            if (point.x !== 0) return point
        }
        return Qt.point(0, 0)
    }
    function headerRect(target) {
        void x; void y; void width; void height
        if (parent) { void parent.x; void parent.y }
        void header.x; void header.y; void header.height
        return header.mapToItem(target, 0, 0, headerAvailableWidth, header.height)
    }
    function inspectionRects(target) {
        if (!visible) return []
        void x; void y; void width; void height
        const rects = creatures.inspectionRects(target).concat(lands.inspectionRects(target), planeswalkers.inspectionRects(target), others.inspectionRects(target))
        // Include wrapped metadata and the optional row above a narrow dock.
        rects.push(headerRect(target))
        return rects
    }
    function readoutRects(target) {
        if (!visible) return []
        void x; void y; void width; void height
        if (parent) { void parent.x; void parent.y }
        const rects = creatures.readoutRects(target).concat(lands.readoutRects(target), planeswalkers.readoutRects(target), others.readoutRects(target))
        // Header items are reparented above the field. Subscribe to their
        // actual layout and preserve only public painted text, not the empty
        // header or the life-disc target area around its number.
        void header.x; void header.y; void identity.x; void identity.y
        void playerTarget.x; void playerTarget.y; void lifeReadout.x; void lifeReadout.y
        void zoneRow.x; void zoneRow.y
        function append(item, textOnly) {
            if (!item.visible || item.opacity <= 0 || item.width <= 0 || item.height <= 0) return
            void item.x; void item.y; void item.scale
            const width = textOnly ? Math.min(item.width, item.paintedWidth) : item.width
            const height = textOnly ? Math.min(item.height, item.paintedHeight) : item.height
            if (width <= 0 || height <= 0) return
            const x = textOnly && item.horizontalAlignment === Text.AlignHCenter ? (item.width - width) / 2
                : textOnly && item.horizontalAlignment === Text.AlignRight ? item.width - width : 0
            const y = textOnly && item.verticalAlignment === Text.AlignVCenter ? (item.height - height) / 2
                : textOnly && item.verticalAlignment === Text.AlignBottom ? item.height - height : 0
            rects.push(item.mapToItem(target, x, y, width, height))
        }
        for (const label of [nameLabel, zonesLabel, statusLabel].concat(lifeReadout.readoutItems))
            append(label, true)
        for (let index = 0; index < zonePiles.count; ++index) {
            const pile = zonePiles.itemAt(index) as ForgeZonePile
            if (!pile || !pile.visible) continue
            void pile.x; void pile.y; void pile.width; void pile.height
            for (const label of pile.readoutItems) append(label, true)
        }
        // These compact controls contain only their public mana symbols/counts
        // or the View hand label. Their surrounding header stays transparent.
        append(mana, false)
        void viewHand.x; void viewHand.y
        if (viewHand.visible) append(viewHand.contentItem, false)
        return rects
    }
    function playerPoint(target) {
        // mapToItem does not subscribe a bound arrow to ancestor movement.
        // Wrapping metadata can move the life disc without resizing the field.
        void header.x; void header.y; void playerTarget.x; void playerTarget.y
        return playerTarget.mapToItem(target, playerTarget.width / 2, playerTarget.height / 2)
    }
    function reveal(id) {
        for (const lane of [creatures, lands, planeswalkers, others])
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
        x: root.inset; y: root.lifeDeltaClearance + root.inset
        width: 36 * root.unit; height: width
        radius: width / 2
        color: Theme.withAlpha(root.eliminated ? Theme.textMuted : Theme.accent, 0.12)
        border.width: root.offered || root.selected || root.combatHovered ? 3 : 1
        border.color: root.combatHovered ? Theme.primary : root.selected ? Theme.accent
            : root.offered ? Theme.withAlpha(Theme.accent, root.waiting ? 0.5 : 1) : Theme.borderStrong
        activeFocusOnTab: root.actionable
        Accessible.role: Accessible.Button
        Accessible.name: root.name + ", " + qsTr("Life %1").arg(root.life)
        Accessible.onPressAction: root.activateSeat()
        Keys.onReturnPressed: root.activateSeat()
        Keys.onSpacePressed: root.activateSeat()
        ForgeLifeReadout {
            id: lifeReadout
            anchors.fill: parent
            life: root.life
            seat: root.seat
            unit: root.unit
            numberColor: root.eliminated ? Theme.textMuted : Theme.accent
            // A large signed change can be wider than the small life disc.
            // Start at its left edge, inside the reserved header band.
            alignDeltaLeft: true
        }
        TapHandler { enabled: root.offered; onTapped: root.activateSeat() }
        HoverHandler {
            enabled: root.combat.canAct && root.actionable
            cursorShape: root.actionable ? Qt.PointingHandCursor : Qt.ArrowCursor
            onHoveredChanged: root.combat.hoverSeat(root.seat, hovered)
        }
    }
    Column {
        id: identity
        parent: header
        x: playerTarget.x + playerTarget.width + 10 * root.unit
        y: root.lifeDeltaClearance + root.inset
        width: Math.max(0, root.infoRight - x)
        spacing: 2 * root.unit
        HoverHandler { id: identityHover }
        ToolTip.visible: identityHover.hovered
        ToolTip.text: [root.name, zonesLabel.text, statusLabel.text].filter(text => text.length).join("\n")
        Text {
            id: nameLabel
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
            id: zonesLabel
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
            id: statusLabel
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
        width: Math.max(0, root.width - 2 * root.inset)
        height: root.boardHeight
        unit: root.unit; nearSide: root.nearSide
        preferCenteredRows: true
        creatureLane: creatures; landLane: lands; otherLane: others
        planeswalkerLane: planeswalkers
        obstacles: {
            void root.x; void root.y
            if (root.parent) { void root.parent.x; void root.parent.y }
            const origin = root.mapToItem(root.presentation, root.inset, root.boardTop)
            return root.presentation.fieldObstacles(origin.x, origin.y)
        }
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
        category: "land"; showCaption: false; maxFaceWidth: 108 * unit
        alignBottom: root.nearSide
        locatedId: root.presentation.locatedId
    }
    ForgeCardLane {
        id: planeswalkers
        objectName: "forgePlaneswalkers-" + root.seat
        x: root.inset + fieldLayout.placement.planeswalkers.x
        y: root.boardTop + fieldLayout.placement.planeswalkers.y
        width: fieldLayout.placement.planeswalkers.width; height: fieldLayout.placement.planeswalkers.height
        tableController: root.tableController
        unit: root.unit; ownerSeat: root.seat
        category: "planeswalker"; showCaption: false; maxFaceWidth: 108 * unit
        alignBottom: !root.nearSide
        alignRight: true
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
        category: "other"; showCaption: false; maxFaceWidth: 108 * unit
        alignBottom: root.nearSide
        alignRight: true
        locatedId: root.presentation.locatedId
    }
    Grid {
        id: zoneRow
        parent: header
        objectName: "forgeSeatZones-" + root.seat
        x: root.stackedHeader ? root.inset : root.headerAvailableWidth - width - root.inset
        y: root.stackedHeader ? root.identityHeight : root.lifeDeltaClearance + root.inset
        width: Math.min(226 * root.unit, Math.max(0, root.headerAvailableWidth
            - (root.stackedHeader ? 2 * root.inset : 60 * root.unit)))
        columns: !root.stackedHeader || width >= 226 * root.unit ? 4
            : width >= 110 * root.unit ? 2 : 1
        height: Math.ceil(4 / columns) * root.zoneHeight + (Math.ceil(4 / columns) - 1) * spacing
        spacing: 6 * root.unit
        Repeater {
            id: zonePiles
            model: ["library", "graveyard", "exile", "command"]
            delegate: ForgeZonePile {
                required property string modelData
                objectName: "forgeSeatZone-" + root.seat + "-" + modelData
                width: Math.min(52 * root.unit, Math.max(0,
                    (zoneRow.width - (zoneRow.columns - 1) * zoneRow.spacing) / zoneRow.columns))
                height: root.zoneHeight
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
        x: root.stackedHeader ? root.inset : zoneRow.x - root.inset - width
            - (viewHand.visible ? viewHand.width + root.inset : 0)
        y: root.stackedHeader ? zoneRow.y + zoneRow.height + root.inset
            : root.lifeDeltaClearance + (root.headerHeight - root.lifeDeltaClearance - height) / 2
        manaPool: root.manaPool
        maximumColumns: root.compactInlineMana ? 3 : 0
        seat: root.seat; unit: root.unit
        visible: root.visible && root.manaPool.length > 0
    }
    AppButton {
        id: viewHand
        parent: header
        objectName: "forgeViewHand-" + root.seat
        visible: root.tableController.canViewSpectatorHands
        x: root.stackedHeader ? root.inset : zoneRow.x - width - root.inset
        y: root.stackedHeader ? zoneRow.y + zoneRow.height + root.inset
            + root.manaRowHeight + root.inset
            : root.lifeDeltaClearance + (root.headerHeight - root.lifeDeltaClearance - height) / 2
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
