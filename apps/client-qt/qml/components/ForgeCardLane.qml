// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic
import Hexproof.Native 1.0

Item {
    id: root
    z: fannedStack >= 0 ? 120 : 0
    required property var tableController
    property real unit: 1
    property int ownerSeat: -1
    property string category: "creature"
    property string zone: "battlefield"
    property string caption: ""
    property bool showCaption: true
    property real startInset: 0
    property real maxFaceWidth: 0
    property bool alignBottom: false
    property bool alignRight: false
    property string locatedId: ""
    property int combatForward: 0
    property real combatReadoutClearance: 0
    property int fannedStack: -1
    // The fan follows its members when tapping or combat reorders the slot.
    property var fannedIds: []
    property int fanPromptId: 0
    property int layoutGeneration: 0
    onWidthChanged: layoutGeneration++
    onHeightChanged: layoutGeneration++
    readonly property bool combatPresentation: {
        const step = tableController.rulesSession.step
        return combatForward !== 0 && ["begin_combat", "declare_attackers", "declare_blockers",
            "combat_damage", "end_combat"].includes(step)
    }
    readonly property var slotModel: {
        const session = tableController && tableController.rulesSession
        return session && session.laneSlots ? session.laneSlots(ownerSeat, zone, category) : null
    }
    Binding {
        target: root.slotModel
        property: "combatGroupingKeys"
        when: root.slotModel !== null
        // Lane views share a cached native model. Retiring one view must not
        // restore its earlier combat draft over the current view's value.
        restoreMode: Binding.RestoreNone
        value: {
            const combat = root.tableController.combatInteraction
            return root.zone === "battlefield" && combat && combat.active
                ? combat.groupingKeys || {} : {}
        }
    }
    property bool slotsUpdating: false
    Connections {
        target: root.slotModel
        // Repeater moves require sibling delegates. An open fan temporarily
        // returns to the viewport while its members split into new slots.
        function onStacksAboutToChange() { root.slotsUpdating = true }
        function onStacksChanged() { root.slotsUpdating = false }
    }
    property var visibleCards: []
    readonly property var cardItemsById: {
        const byId = new Map()
        for (const item of visibleCards)
            if (item) byId.set(item.cardId, item)
        return byId
    }
    property bool cardsDirty: false
    readonly property var visibleStackIds: slotModel && slotModel.stacks ? slotModel.stacks : []
    onVisibleStackIdsChanged: {
        if (fannedStack < 0)
            return
        const kept = visibleStackIds.findIndex(ids => ids.length > 1 && ids.some(id => fannedIds.includes(id)))
        if (kept < 0) {
            closeFan()
            return
        }
        fannedStack = kept
        fannedIds = visibleStackIds[kept]
    }
    function openFan(index) {
        const ids = visibleStackIds[index] || []
        if (ids.length < 2)
            return
        const interaction = tableController.interaction
        if (interaction && interaction.fanOwner && interaction.fanOwner !== root)
            interaction.fanOwner.closeFan()
        fannedStack = index
        fannedIds = ids
        fanPromptId = tableController.rulesSession.promptId
        if (interaction)
            interaction.fanOwner = root
    }
    function closeFan() {
        fannedStack = -1
        fannedIds = []
        const interaction = tableController.interaction
        if (interaction && interaction.fanOwner === root)
            interaction.fanOwner = null
    }
    Component.onDestruction: {
        const interaction = tableController.interaction
        if (interaction && interaction.fanOwner === root)
            interaction.fanOwner = null
    }
    Component.onCompleted: syncVisibleCards()
    Connections {
        target: root.tableController.rulesSession
        // Wait for the snapshot's indices and card presentations as well as
        // model rows. Attached rows may not change the public stacks at all.
        function onSnapshotChanged() { root.syncVisibleCards() }
        function onPromptChanged() {
            if (root.fannedStack >= 0 && root.tableController.rulesSession.promptId !== root.fanPromptId)
                root.closeFan()
        }
    }
    readonly property int stackCount: visibleStackIds.length
    readonly property int layoutStackCount: slotModel && typeof slotModel.layoutStackCount === "number"
        ? slotModel.layoutStackCount : Math.max(stackCount, hostCards.length)
    readonly property real headerHeight: showCaption && caption.length ? 20 * unit : 0
    readonly property int cardCount: zone === "battlefield" ? visibleCards.length
        : tableController.zoneCount(ownerSeat, zone)
    readonly property Flickable scrollArea: viewport
    readonly property real gap: 8 * unit
    readonly property bool showFullFace: zone !== "battlefield"
    readonly property real faceRatio: showFullFace ? 1.394 : 0.93
    readonly property var grid: layoutGrid(viewport.width, viewport.height)
    readonly property real cardWidth: grid.face
    readonly property real cardHeight: cardWidth * faceRatio
    // A pile's ready front steps 12 units up and left of its slot (see
    // memberShift). The grid reserves that room while any pile exists, not
    // while a copy is tapped, so tapping never moves the lane.
    readonly property real pileLead: visibleStackIds.some(ids => ids.length > 1) ? 9 * unit : 0
    readonly property real pileShift: visibleStackIds.reduce((shift, ids) =>
        Math.max(shift, Math.min(Math.max(0, ids.length - 1), 2) * 4 * unit), 0)
    // Fit against the same potential decoration depth as the minimum layout.
    // Tapping can repartition 1+3 copies into 2+2, or remove a two-copy pile;
    // neither change releases space for larger card faces.
    readonly property real layoutPileLead: Math.max(stackCount, hostCards.length) > 1 ? 9 * unit : 0
    readonly property real layoutPileShift: Math.min(Math.max(0,
        Math.max(stackCount, hostCards.length) - 1), 2) * 4 * unit
    // Right-aligned piles must fit their rear faces as well as the front.
    // This remains reserved while a pile is fanned or its front changes.
    readonly property real layoutPileTrail: alignRight ? layoutPileShift : 0
    readonly property int columns: grid.columns
    readonly property var hostCards: visibleCards.filter(card => card && !card.attachedTo)
    // Creature lanes reserve both their combat nudge and destination badge
    // before combat starts. These readouts need no extra space when piles split.
    readonly property bool structuralBadge: hostCards.some(card => card && card.structuralLink)
    readonly property int attachmentDepth: {
        let depth = 0
        for (const card of hostCards)
            if (card) depth = Math.max(depth, card.attachmentCount || 0)
        return depth
    }
    readonly property real attachmentPeek: attachmentDepth * 16 * unit
    // Split combat piles expose each front's title. Reserve the caller's
    // overlay clearance before combat so the 14-unit nudge keeps it readable.
    readonly property real combatInset: Math.abs(combatForward) * 14 * unit
        + (combatForward < 0 ? combatReadoutClearance : 0)
    // The upper label is 19 units tall with a two-unit gap. Reserve it in
    // every row before combat or hover begins, including a ready pile front.
    readonly property real upperHintInset: combatForward > 0 ? 21 * unit : 0
    readonly property real layoutCellExtra: Math.max(structuralBadge ? 22 : 10,
        combatForward !== 0 ? 16 : 0) * unit + attachmentPeek + combatInset + upperHintInset
    readonly property real cellExtra: layoutCellExtra
    function slotX(index) {
        return 3 * unit + pileLead + rowLead + (index % columns) * (cardWidth + gap)
    }
    function slotY(index) {
        return rowTop + 3 * unit + pileLead + upperHintInset + (combatForward < 0 ? combatInset : 0)
            + Math.floor(index / columns) * cellHeight
    }
    // A fan stays on its slot's row and inside the lane. Large piles overlap
    // like a hand instead of running past the window edge.
    function fanStep(size) {
        if (size <= 1)
            return 0
        const span = Math.max(cardWidth, viewport.width - 6 * unit)
        return Math.max(0, Math.min(cardWidth + gap, (span - cardWidth) / (size - 1)))
    }
    function fanLeft(index, size) {
        const span = (size - 1) * fanStep(size) + cardWidth
        return Math.max(3 * unit, Math.min(slotX(index), viewport.width - 3 * unit - span))
    }
    // Reserve the full future hint below the last face, including the
    // deepest closed pile member. This pad also feeds the fitter; otherwise
    // it would enlarge the face into newly allocated readout space. Keep it
    // structural so payment, combat and fan changes never refit the row.
    readonly property real edgeSpace: zone !== "battlefield" ? 5 * unit
        : Math.max(5 * unit, 3 * unit + layoutPileShift + combatInset + upperHintInset
            + (attachmentPeek > 0 ? attachmentPeek + 21 * unit : 14 * unit) - layoutCellExtra)
    readonly property real cellHeight: cardHeight + cellExtra
    readonly property real gridHeight: grid.height
    readonly property real rowTop: grid.top
    readonly property real rowLead: grid.lead

    function layoutColumns(laneWidth, face) {
        const available = Math.max(1, laneWidth - startInset - layoutPileLead - layoutPileTrail - 6 * unit)
        return Math.max(1, Math.floor((available + gap) / (face + gap) + 1e-7))
    }
    function layoutMinimumWidth() {
        const count = Math.max(stackCount, hostCards.length)
        if (!count) return 0
        return startInset + layoutPileLead + layoutPileTrail + 6 * unit + 80 * unit
    }
    function layoutMinimumHeight(laneWidth) {
        if (!stackCount) return 0
        // Stable ready/spent slot budgets come from the public pile model.
        // Decoration depth still includes all copies, capped at two steps.
        const count = layoutStackCount
        const face = 80 * unit
        const available = laneWidth - layoutMinimumWidth() + face
        if (available < face - 1e-7
                || (maxFaceWidth > 0 && maxFaceWidth < face - 1e-7))
            return Infinity
        const cols = Math.max(1, Math.floor((available + gap) / (face + gap) + 1e-7))
        return headerHeight + Math.ceil(count / cols) * (face * faceRatio + layoutCellExtra)
            + layoutPileLead + edgeSpace
    }
    function layoutGrid(laneWidth, laneHeight) {
        const face = fittedCardWidth(laneWidth, laneHeight)
        const cols = layoutColumns(laneWidth, face)
        const used = Math.min(stackCount, cols) * (face + gap) - gap
        const lead = alignRight && stackCount > 0
            ? Math.max(startInset, laneWidth - used - 6 * unit - pileLead - pileShift)
            : stackCount > 0 && stackCount <= cols && category === "creature"
                ? Math.max(startInset, (laneWidth - used) / 2 - 3 * unit - pileLead) : startInset
        const extent = Math.ceil(stackCount / cols) * (face * faceRatio + cellExtra) + pileLead + edgeSpace
        return {face:face, columns:cols, lead:lead, height:extent,
            top:alignBottom ? Math.max(0, laneHeight - extent) : 0}
    }
    // Predict a sparse row without reading live delegate positions back into
    // its allocation. Dense/scrolling grids retain the conservative band fit.
    // A pile reserves its entire potential fan, even while collapsed, so
    // opening it never moves the battlefield or spreads cards under controls.
    function layoutFootprint(laneWidth, laneHeight) {
        const availableHeight = Math.max(0, laneHeight - headerHeight)
        const fit = layoutGrid(laneWidth, availableHeight)
        if (stackCount > fit.columns || fit.height > availableHeight + 1e-7)
            return null
        const left = pileLead > 0 ? 0 : 3 * unit + fit.lead
        const extent = pileLead > 0 ? laneWidth : stackCount * (fit.face + gap) - gap
        return Qt.rect(left, headerHeight + fit.top, Math.max(0, extent), fit.height)
    }

    // Creatures grow to fill their lane. Lands and other permanents keep a
    // smaller ceiling so two tiles stay in the near corner instead of
    // becoming a centered poster row. Layout uses public piles, not raw
    // object counts, so eight Plains occupy one tile.
    function fittedCardWidth(laneWidth, laneHeight) {
        const count = Math.max(1, stackCount)
        const available = Math.max(1, laneWidth - startInset - layoutPileLead - layoutPileTrail - 6 * unit)
        const ceiling = maxFaceWidth > 0 ? maxFaceWidth
            : (zone === "battlefield" ? 180 : 120) * unit
        const maximum = Math.min(available, ceiling)
        // A short lane scrolls at readable size. Decorations must never lower
        // the size floor and turn creatures or their attachments into dots.
        const minimum = Math.min(maximum, 80 * unit)
        let best = minimum
        for (let cols = 1; cols <= count; ++cols) {
            const widthFit = (available - (cols - 1) * gap) / cols
            if (widthFit < minimum) break
            const rows = Math.ceil(count / cols)
            const rowHeightFit = ((laneHeight - edgeSpace - layoutPileLead) / rows - cellExtra) / faceRatio
            const candidate = Math.min(maximum, rowHeightFit, widthFit)
            if (candidate < minimum) continue
            if (rows * (candidate * faceRatio + cellExtra) + edgeSpace + layoutPileLead <= laneHeight + 1e-7)
                best = Math.max(best, candidate)
        }
        return best
    }

    function syncVisibleCards() {
        if (!cardsDirty) return
        cardsDirty = false
        const next = []
        for (let i = 0; i < cards.count; ++i) {
            const item = cards.itemAt(i) as CardSlot
            if (item) next.push(item)
        }
        visibleCards = next
    }
    // Snapshots, initial construction and model replacement publish together.
    // Independent catalog changes settle during polish before the next frame.
    FramePolish {
        id: cardsPolish
        onReady: root.syncVisibleCards()
    }
    function itemFor(id) {
        return cardItemsById.get(id) || null
    }
    function reveal(id) {
        const item = itemFor(id)
        if (!item) return false
        // Reveal the complete upper readout with its card when they fit. In
        // a shorter viewport the exact card face retains priority.
        const leading = Math.min(upperHintInset, Math.max(0, viewport.height - item.height))
        viewport.contentY = Math.max(0, Math.min(item.y - leading, viewport.contentHeight - viewport.height))
        const presentation = tableController.presentation
        if (zone === "battlefield" && presentation && typeof presentation.uncoverRevealedCard === "function")
            presentation.uncoverRevealedCard(item)
        return true
    }
    function pointFor(id, target) {
        const item = itemFor(id)
        // The combat nudge can cross the lane edge while the card center
        // stays on screen. Arrows still start there.
        const center = item ? item.y + item.height / 2 : 0
        if (!item || center < viewport.contentY || center > viewport.contentY + viewport.height)
            return Qt.point(0, 0)
        // Follow the painted glide as well as the final slot. Mapping from
        // the viewport avoids reading a Translate matrix before its property
        // notification has finished updating that matrix.
        void root.x; void root.y; void root.width; void root.height
        void viewport.x; void viewport.y; void item.x
        void item.visualDx; void item.visualDy
        return viewport.contentItem.mapToItem(target,
            item.x + item.visualDx + item.width / 2,
            item.y + item.visualDy + item.height / 2)
    }
    // Occupied faces, attachment strips and their status badges only; empty
    // lane space remains available for hover inspection. Bindings follow the
    // existing card list and scroll geometry, without a scene-tree scan.
    function inspectionRects(target) {
        if (!visible) return []
        void x; void y; void width; void height
        void viewport.x; void viewport.y; void viewport.contentX; void viewport.contentY
        const clip = viewport.clip
            ? viewport.mapToItem(target, 0, 0, viewport.width, viewport.height)
            : Qt.rect(0, 0, target.width, target.height)
        const groups = new Map()
        for (const item of visibleCards) {
            if (!item || !item.visible) continue
            // Keep the small status-badge band stable while hover changes its
            // label. Otherwise moving toward an inspection button can move
            // that button away before the pointer reaches it.
            const extent = upperHintInset + item.height + item.hostedAttachments.length * 16 * unit + 21 * unit
            const left = item.x + item.visualDx, top = item.y + item.visualDy - upperHintInset
            const key = item.fanned ? item.cardId : String(item.stackIndex)
            const previous = groups.get(key)
            // All collapsed members share a small public pile. Merge once
            // before the free-area search, even for hundreds of token copies.
            groups.set(key, previous ? {
                left:Math.min(left, previous.left), top:Math.min(top, previous.top),
                right:Math.max(left + item.width, previous.right),
                bottom:Math.max(top + extent, previous.bottom), fanned:item.fanned
            } : {left:left, top:top, right:left + item.width, bottom:top + extent, fanned:item.fanned})
        }
        const rects = []
        for (const group of groups.values()) {
            const rect = viewport.contentItem.mapToItem(target, group.left, group.top,
                group.right - group.left, group.bottom - group.top)
            const bounds = group.fanned ? Qt.rect(0, 0, target.width, target.height) : clip
            const left = Math.max(rect.x, bounds.x), top = Math.max(rect.y, bounds.y)
            const right = Math.min(rect.x + rect.width, bounds.x + bounds.width)
            const bottom = Math.min(rect.y + rect.height, bounds.y + bounds.height)
            if (right > left && bottom > top)
                rects.push(Qt.rect(left, top, right - left, bottom - top))
        }
        return rects
    }
    function readoutRects(target) {
        if (!visible || zone !== "battlefield") return []
        void x; void y; void width; void height
        void viewport.x; void viewport.y; void viewport.contentX; void viewport.contentY
        const clip = viewport.clip
            ? viewport.mapToItem(target, 0, 0, viewport.width, viewport.height)
            : Qt.rect(0, 0, target.width, target.height)
        const result = []
        function append(rect, fanned) {
            const bounds = fanned ? Qt.rect(0, 0, target.width, target.height) : clip
            const left = Math.max(rect.x, bounds.x), top = Math.max(rect.y, bounds.y)
            const right = Math.min(rect.x + rect.width, bounds.x + bounds.width)
            const bottom = Math.min(rect.y + rect.height, bounds.y + bounds.height)
            if (right <= left || bottom <= top) return
            const next = Qt.rect(left, top, right - left, bottom - top)
            // A dense fan has overlapping labels on one baseline. Merge only
            // exact horizontal bands; never include empty art between rows.
            const previous = result.find(item => Math.abs(item.y - next.y) < 0.01
                && Math.abs(item.height - next.height) < 0.01
                && item.x <= next.x + next.width && item.x + item.width >= next.x)
            if (previous) {
                const edge = Math.max(previous.x + previous.width, next.x + next.width)
                previous.x = Math.min(previous.x, next.x)
                previous.width = edge - previous.x
            } else result.push(next)
        }
        for (const slot of visibleCards) {
            if (!slot || !slot.visible || (!slot.stackFront && !slot.fanned)) continue
            void slot.x; void slot.y; void slot.visualDx; void slot.visualDy
            for (const rect of slot.readoutRects(target)) append(rect, slot.fanned)
        }
        return result
    }
    onOwnerSeatChanged: viewport.contentY = 0
    Text {
        objectName: root.objectName + "Count"
        visible: root.headerHeight > 0
        height: root.headerHeight
        textFormat: Text.PlainText
        text: root.caption + "  /  " + root.cardCount
        color: Theme.textMuted
        font.pixelSize: 9 * root.unit
        font.letterSpacing: 1
    }
    Text {
        objectName: root.objectName + "HiddenNotice"
        anchors.centerIn: viewport
        width: viewport.width
        visible: root.zone === "library" && root.cardCount > 0 && root.visibleCards.length === 0
        textFormat: Text.PlainText
        text: qsTr("Library contents are hidden.")
        color: Theme.textMuted
        font.pixelSize: 13 * root.unit
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
    }
    component CardSlot: Item {
        id: slot
        required property string cardId
        required property string zone
        required property int zoneOwnerSeat
        required property int controllerSeat
        required property bool visibleIdentity
        required property string name
        required property string setCode
        required property string collectorNumber
        required property bool token
        required property bool tapped
        required property bool enteredThisTurn
        required property bool summoningSick
        required property bool faceDown
        required property bool attacking
        required property string power
        required property string toughness
        required property string countersSummary
        required property int damage
        required property string attachedTo
        required property string attackingTarget
        required property int attackingSeat
        required property int exiledCardCount
        required property var exiledCardIds
        required property var chosenCardIds
        required property var annotations
        required property int actionCount
        required property string hintKey
        required property int targetCount
        required property bool nativeTargetSelected
        required property int attachmentCount
        required property bool structuralLink
        required property bool linked
        required property var attachmentCards
        required property var links
        required property var blockingIds
        required property var blockedByIds
        required property var attackedByIds
        required property int slotIndex
        required property int memberRank
        required property int slotSize
        readonly property int stackIndex: slotIndex
        readonly property int stackRank: memberRank
        readonly property int stackSize: slotSize > 0 ? slotSize : 1
        readonly property bool stackFront: {
            if (stackSize <= 1)
                return true
            const ids = root.visibleStackIds[stackIndex] || []
            if (root.locatedId && ids.indexOf(root.locatedId) >= 0)
                return slot.cardId === root.locatedId
            return stackRank === stackSize - 1
        }
        readonly property var hostedAttachments:
            slot.slotIndex < 0 || !slot.stackFront ? [] : (slot.attachmentCards || [])
        readonly property int pileDepth: {
            if (stackSize <= 1)
                return 0
            if (slot.cardId === root.locatedId)
                return Math.min(stackSize - 1, 2)
            return Math.min(Math.max(0, stackRank), 2)
        }
        function stackMemberTaken(id) {
            const combat = root.tableController.combatInteraction
            if (!combat)
                return false
            if (combat.selected(id))
                return true
            const links = combat.links
            if (!links)
                return false
            for (let i = 0; i < links.length; ++i) {
                if (links[i].to === id || links[i].from === id)
                    return true
            }
            return false
        }
        readonly property bool fanned: root.fannedStack === stackIndex && stackSize > 1
        // Only the chosen pile leaves the scroll clip. Keep the same live
        // delegates, coordinates and focus while unrelated rows stay clipped.
        parent: fanned && !root.slotsUpdating ? fanLayer : viewport.contentItem
        readonly property var memberIds: slotIndex >= 0 ? (root.visibleStackIds[slotIndex] || []) : []
        readonly property int tappedCount: {
            void root.visibleCards
            return memberIds.filter(id => { const member = root.itemFor(id); return member && member.tapped }).length
        }
        readonly property int newCount: {
            void root.visibleCards
            return memberIds.filter(id => { const member = root.itemFor(id); return member && member.enteredThisTurn }).length
        }
        function memberOffered(id) {
            const combat = root.tableController.combatInteraction
            if (combat && combat.active)
                return combat.offered(id) && !stackMemberTaken(id)
            const interaction = root.tableController.interaction
            return interaction.objectOffered("card", id) && !interaction.objectSelected("card", id)
        }
        function memberEligible(id) {
            const combat = root.tableController.combatInteraction
            if (combat && combat.active)
                return combat.canAct && memberOffered(id)
            const interaction = root.tableController.interaction
            if (interaction.canRespond)
                return memberOffered(id)
            return interaction.canQueuePayment("card", id)
        }
        function sameIds(left, right) {
            const a = (left || []).slice().sort(), b = (right || []).slice().sort()
            return a.length === b.length && a.every((id, index) => id === b[index])
        }
        function actionSignature(id) {
            const combat = root.tableController.combatInteraction
            if (combat && combat.active) {
                const source = combat.sourceFor(id)
                return source ? "source:" + source.maxAssignments + ":"
                        + source.validTargets.map(target => target.responseId).sort().join(",")
                    : "target"
            }
            const interaction = root.tableController.interaction
            if (interaction.choosingTargets)
                return "target"
            // Forge labels may carry the object's own number.
            return interaction.offeredActionsForCard(id)
                .map(action => action.kind + ":" + String(action.label || "").replace(/\s*\(\d+\)/g, ""))
                .sort().join("|")
        }
        // Members are interchangeable when the prompt offers them the same
        // thing and nothing about combat or relationships tells them apart.
        // Targets and combat also compare entry and sickness, which can
        // matter later; for activations the offered set already captures it.
        function interchangeable(left, right) {
            if (!left || !right)
                return false
            if (left.tapped !== right.tapped || left.attacking !== right.attacking
                    || left.attackingSeat !== right.attackingSeat
                    || left.attackingTarget !== right.attackingTarget
                    || !sameIds(left.blockingIds, right.blockingIds)
                    || !sameIds(left.blockedByIds, right.blockedByIds)
                    || !sameIds(left.attackedByIds, right.attackedByIds))
                return false
            const combat = root.tableController.combatInteraction
            if ((combat && combat.active) || root.tableController.interaction.choosingTargets) {
                if (left.enteredThisTurn !== right.enteredThisTurn
                        || left.summoningSick !== right.summoningSick)
                    return false
            }
            return actionSignature(left.cardId) === actionSignature(right.cardId)
        }
        function groupChoice(ids, preferred) {
            if (!ids.length)
                return null
            const first = root.itemFor(ids[0])
            for (let i = 1; i < ids.length; ++i) {
                if (!interchangeable(first, root.itemFor(ids[i])))
                    return {id: "", fan: true}
            }
            return {id: ids.indexOf(preferred) >= 0 ? preferred : ids[0], fan: false}
        }
        // Resolves a click on this delegate to one member, or asks for the
        // fan when the eligible members differ.
        function stackChoice() {
            if (fanned || stackSize <= 1)
                return {id: slot.cardId, fan: false}
            const ids = memberIds
            if (root.locatedId && ids.indexOf(root.locatedId) >= 0)
                return {id: root.locatedId, fan: false}
            const tappedMember = id => { const member = root.itemFor(id); return !!member && member.tapped }
            // An activation acts on the card that was clicked, so its ring
            // shows on the visible card. Combat and targets take members in
            // order and leave the front standing for the rest.
            const combat = root.tableController.combatInteraction
            const assigning = (combat && combat.active) || root.tableController.interaction.choosingTargets
            const preferred = assigning ? "" : slot.cardId
            if (stackFront) {
                const ready = groupChoice(ids.filter(id => !tappedMember(id) && memberEligible(id)), preferred)
                if (ready)
                    return ready
            }
            const spent = ids.filter(id => tappedMember(id) && memberEligible(id))
            const recent = root.tableController.interaction.recentActivations || []
            for (let i = recent.length - 1; i >= 0; --i) {
                if (spent.indexOf(recent[i]) >= 0)
                    return {id: recent[i], fan: false}
            }
            const strip = groupChoice(spent, preferred)
            if (strip)
                return strip
            // Nothing can act now. The clicked card still answers, so a
            // pending decision shows the waiting cue. A queued payment is
            // never toggled off from here.
            const queue = root.tableController.interaction.paymentQueue || []
            const offered = ids.filter(id => memberOffered(id) && queue.indexOf(id) < 0)
            return {id: stackFront && offered.length ? offered[0] : slot.cardId, fan: false}
        }
        function stackActivateId() {
            const choice = stackChoice()
            if (!choice.fan)
                return choice.id
            const offered = memberIds.filter(id => memberOffered(id))
            return offered.length ? offered[0] : slot.cardId
        }
        function stackInteractionCard() {
            void root.tableController.interaction.promptRevision
            const choice = stackChoice()
            return !choice.fan ? root.itemFor(choice.id) || slot : slot
        }
        function openFan() { root.openFan(stackIndex) }
        function closeFan() { root.closeFan() }
        function focusNeighbor(delta) {
            const ids = root.visibleStackIds[stackIndex] || []
            if (ids.length < 2)
                return false
            const index = Math.max(0, ids.indexOf(slot.cardId))
            const next = ids[(index + delta + ids.length) % ids.length]
            const member = root.itemFor(next)
            if (!member || !member.faceItem)
                return false
            member.faceItem.forceActiveFocus()
            return true
        }
        property Item faceItem: face
        function readoutRects(target) {
            let result = face.readoutRects(target)
            if (stackCountBadge.visible)
                result.push(stackCountBadge.mapToItem(target, 0, 0, stackCountBadge.width, stackCountBadge.height))
            for (let index = 0; index < attachments.count; ++index) {
                const item = attachments.itemAt(index) as ForgeCard
                if (item && item.visible && item.publicFace) {
                    void item.x; void item.y
                    result.push(item.mapToItem(target, 0, item.height - 16 * root.unit,
                        item.width, 16 * root.unit))
                }
            }
            return result
        }
        // The item's x/y are the final hit target. visualDx/y only paint the glide.
        property bool motionPrimed: false
        property real motionX: 0
        property real motionY: 0
        property real visualDx: 0
        property real visualDy: 0
        property int seenLayout: 0
        transform: Translate { x: visualDx; y: visualDy }
        ParallelAnimation {
            id: travel
            NumberAnimation {
                target: slot
                property: "visualDx"
                to: 0
                duration: Theme.motionNormal
                easing.type: Easing.OutCubic
            }
            NumberAnimation {
                target: slot
                property: "visualDy"
                to: 0
                duration: Theme.motionNormal
                easing.type: Easing.OutCubic
            }
        }
        function trackMotion() {
            if (!motionPrimed)
                return
            if (seenLayout !== root.layoutGeneration) {
                seenLayout = root.layoutGeneration
                travel.stop()
                visualDx = 0
                visualDy = 0
                motionX = x
                motionY = y
                return
            }
            const dx = motionX - x
            const dy = motionY - y
            motionX = x
            motionY = y
            if (!Theme.motionEnabled || Theme.motionSnap || (dx === 0 && dy === 0)) {
                travel.stop()
                visualDx = 0
                visualDy = 0
                return
            }
            visualDx += dx
            visualDy += dy
            travel.restart()
        }
        onXChanged: trackMotion()
        onYChanged: trackMotion()
        Component.onCompleted: {
            motionX = x
            motionY = y
            seenLayout = root.layoutGeneration
            motionPrimed = true
        }
        Connections {
            target: Theme
            function onMotionEpochChanged() {
                travel.stop()
                slot.visualDx = 0
                slot.visualDy = 0
                slot.motionX = slot.x
                slot.motionY = slot.y
            }
        }
        visible: slotIndex >= 0
        width: root.cardWidth
        height: root.cardHeight
        // A tapped copy stays in the cell. The ready card steps up-left so the
        // spent corner remains inside the lane and can still be clicked.
        readonly property bool tappedBehind: {
            if (fanned || tapped || !stackFront || stackSize <= 1)
                return false
            const ids = root.visibleStackIds[stackIndex] || []
            for (let i = 0; i < ids.length; ++i) {
                if (ids[i] === slot.cardId)
                    continue
                const member = root.itemFor(ids[i])
                if (member && member.tapped)
                    return true
            }
            return false
        }
        readonly property real memberShift: fanned ? 0
                : tappedBehind ? -12 * root.unit : pileDepth * 4 * root.unit
        x: fanned ? root.fanLeft(stackIndex, stackSize) + Math.max(0, stackRank) * root.fanStep(stackSize)
                  : root.slotX(stackIndex) + memberShift
        y: root.slotY(stackIndex) + (fanned ? 0 : memberShift
                    + (root.combatPresentation && slot.attacking ? root.combatForward * 14 * root.unit : 0))
        z: (fanned ? 3000 : 0) + (slot.attacking && root.combatPresentation ? 40 : 0)
           + (slot.cardId === root.locatedId ? 1000 : 0) + Math.max(0, stackRank)
        ForgeCard {
            id: face
            objectName: slot.slotIndex >= 0 && !slot.attachedTo ? "forgeCard-" + slot.cardId : ""
            anchors.fill: parent
            z: 10
            tableController: root.tableController
            card: slot
            unit: root.unit
            // Tapped members behind a ready front are reached through their
            // strip. Overlapping members take an exclusive tap, so only the
            // topmost card under the pointer answers.
            pointerEnabled: slot.stackFront || slot.fanned || slot.tapped
            exclusiveTap: slot.stackSize > 1 || slot.hostedAttachments.length > 0
            hoverPreview: slot.stackFront || slot.fanned
            tabStop: slot.stackFront || slot.fanned || face.activeFocus
            fullFace: root.showFullFace
            hintSide: root.combatForward > 0 ? -1 : 1
            attachmentStripHeight: slot.hostedAttachments.length * 16 * root.unit
            located: slot.cardId === root.locatedId
            onActiveFocusChanged: if (activeFocus) root.reveal(slot.cardId)
        }
        Repeater {
            id: attachments
            // Keyed by position so prompt changes update attachments in place.
            model: slot.hostedAttachments.length
            delegate: ForgeCard {
                id: attachment
                required property int index
                objectName: "forgeCard-" + (attachment.card.cardId || "")
                width: slot.width
                height: slot.height
                x: 0
                y: (attachment.index + 1) * 16 * root.unit
                // Each card extends below the preceding one. Reverse the
                // paint order so every attachment keeps its own visible strip.
                z: -1 - attachment.index
                tableController: root.tableController
                card: slot.hostedAttachments[attachment.index] || ({})
                unit: root.unit
                fullFace: root.showFullFace
                exclusiveTap: true
                // Hover and clicks belong to this exposed strip, never to the
                // covered card behind the host or another attachment.
                containmentMask: QtObject {
                    function contains(point: point): bool {
                        return point.x >= 0 && point.x <= attachment.width
                            && point.y >= attachment.height - 16 * root.unit
                            && point.y <= attachment.height
                    }
                }
                Rectangle {
                    objectName: "forgeAttachmentStrip-" + attachment.objectId
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: 16 * root.unit
                    color: "#ed101a22"
                    Text {
                        objectName: "forgeAttachmentName-" + attachment.objectId
                        anchors.fill: parent
                        anchors.leftMargin: 5 * root.unit
                        anchors.rightMargin: 5 * root.unit
                        textFormat: Text.PlainText
                        visible: attachment.publicFace
                        text: attachment.displayName
                        color: "#f3f1e9"
                        font.pixelSize: 10 * root.unit
                        verticalAlignment: Text.AlignVCenter
                        elide: Text.ElideRight
                    }
                }
            }
        }
        Rectangle {
            id: stackCountBadge
            objectName: slot.stackFront && slot.stackSize > 1 ? "forgeCardStackCount-" + slot.cardId : ""
            visible: slot.stackFront && slot.stackSize > 1
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.margins: 3 * root.unit
            z: 20
            // Small land tiles are narrower than a full count; the label
            // shrinks to stay on the card.
            width: Math.min(parent.width - 6 * root.unit, stackCountMetrics.advanceWidth + 10 * root.unit)
            height: 18 * root.unit
            radius: 4 * root.unit
            color: "#d8b56a"
            MouseArea {
                anchors.fill: parent
                enabled: slot.stackFront && slot.stackSize > 1
                onClicked: {
                    Theme.finishMotion()
                    if (root.fannedStack === slot.stackIndex)
                        root.closeFan()
                    else
                        root.openFan(slot.stackIndex)
                }
            }
            TextMetrics {
                id: stackCountMetrics
                font: stackCountLabel.font
                text: stackCountLabel.text
            }
            Text {
                id: stackCountLabel
                objectName: slot.stackFront && slot.stackSize > 1 ? "forgeCardStackCountLabel-" + slot.cardId : ""
                textFormat: Text.PlainText
                anchors.fill: parent
                anchors.leftMargin: 5 * root.unit
                anchors.rightMargin: 5 * root.unit
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                text: ["×" + slot.stackSize,
                    slot.tappedCount > 0 && slot.tappedCount < slot.stackSize ? qsTr("%1 tapped").arg(slot.tappedCount) : "",
                    slot.newCount > 0 && slot.newCount < slot.stackSize ? qsTr("%1 new").arg(slot.newCount) : ""]
                    .filter(part => part.length).join(" · ")
                color: "#19232b"
                font.pixelSize: 11 * root.unit
                font.weight: Font.Bold
                fontSizeMode: Text.HorizontalFit
                minimumPixelSize: Math.max(1, Math.round(8 * root.unit))
                elide: Text.ElideRight
            }
        }
    }
    Item {
        id: fanLayer
        x: viewport.x - viewport.contentX
        y: viewport.y - viewport.contentY
        width: viewport.contentWidth
        height: viewport.contentHeight
        z: 1
    }
    Flickable {
        id: viewport
        objectName: root.objectName + "Viewport"
        y: root.headerHeight
        width: root.width
        height: Math.max(0, root.height - y)
        contentWidth: width
        contentHeight: Math.max(height, root.gridHeight)
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
        Repeater {
            id: cards
            model: root.slotModel
            onModelChanged: root.syncVisibleCards()
            onItemAdded: {
                root.cardsDirty = true
                cardsPolish.request()
            }
            onItemRemoved: {
                root.cardsDirty = true
                cardsPolish.request()
            }
            delegate: CardSlot {}
        }
    }
}
