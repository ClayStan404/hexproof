// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic

Item {
    id: root
    required property var tableController
    property real unit: 1
    property int ownerSeat: -1
    property string category: "creature"
    property string zone: "battlefield"
    property string caption: ""
    property bool showCaption: true
    property real startInset: 0
    property real maxFaceWidth: 0
    property string locatedId: ""
    property var visibleCards: []
    property var visibleStackIds: []
    readonly property int stackCount: visibleStackIds.length
    readonly property real headerHeight: showCaption && caption.length ? 20 * unit : 0
    readonly property int cardCount: zone === "battlefield" ? visibleCards.length
        : tableController.zoneCount(ownerSeat, zone)
    readonly property Flickable scrollArea: viewport
    readonly property real gap: 8 * unit
    readonly property bool showFullFace: zone !== "battlefield"
    readonly property real faceRatio: showFullFace ? 1.394 : 0.93
    readonly property real cardWidth: fittedCardWidth()
    readonly property real cardHeight: cardWidth * faceRatio
    readonly property real rowAvailable: Math.max(1, viewport.width - startInset - 6 * unit)
    readonly property int columns: Math.max(1, Math.floor((rowAvailable + gap) / (cardWidth + gap) + 1e-7))
    readonly property bool hasBadges: tableController.combatInteraction.active || visibleCards.some(card =>
        card && (card.attacking || (tableController.rulesSession.battlefieldRelationships || []).some(
            link => link.sourceId === card.cardId || link.targetId === card.cardId)))
    readonly property real cellHeight: cardHeight + (hasBadges ? 22 : 10) * unit
    readonly property real rowLead: {
        const count = stackCount
        if (count <= 0 || category !== "creature")
            return startInset
        const used = count * (cardWidth + gap) - gap
        if (count <= columns)
            return Math.max(startInset, (viewport.width - used) / 2 - 3 * unit)
        return startInset
    }

    // Creatures grow to fill their lane. Lands and other permanents keep a
    // smaller ceiling so two tiles stay in the near corner instead of
    // becoming a centered poster row. Layout uses public piles, not raw
    // object counts, so eight Plains occupy one tile.
    function fittedCardWidth() {
        const count = Math.max(1, stackCount)
        const available = Math.max(1, viewport.width - startInset - 6 * unit)
        const ceiling = maxFaceWidth > 0 ? maxFaceWidth
            : (zone === "battlefield" ? 180 : 120) * unit
        const maximum = Math.min(available, ceiling)
        const minimum = Math.min(maximum, 80 * unit)
        const extra = (hasBadges ? 22 : 10) * unit
        const heightFit = viewport.height > extra + 5 * unit
            ? (viewport.height - extra - 5 * unit) / faceRatio : minimum
        let best = minimum
        for (let cols = 1; cols <= count; ++cols) {
            const candidate = Math.min(maximum, heightFit,
                (available - (cols - 1) * gap) / cols)
            if (candidate < minimum) break
            const rows = Math.ceil(count / cols)
            if (rows * (candidate * faceRatio + extra) + 5 * unit <= viewport.height)
                best = Math.max(best, candidate)
        }
        return best
    }

    RulesBattlefieldLayout { id: grouping }
    function cardStackKey(card) {
        const combat = root.tableController.combatInteraction
        if (combat.active && combat.isCombatant(card.cardId))
            return "combat:" + card.cardId
        const relationships = root.tableController.rulesSession.battlefieldRelationships || []
        if (relationships.some(link => link.sourceId === card.cardId || link.targetId === card.cardId))
            return "related:" + card.cardId
        const reserved = root.tableController.interaction.nativeObjectSelected("card", card.cardId)
        return grouping.stackKey(card, root.zone) + (reserved ? "\u001freserved" : "")
    }
    function collect() {
        const next = []
        for (let i = 0; i < cards.count; ++i) {
            const item = cards.itemAt(i) as CardSlot
            if (item && item.matches) next.push(item)
        }
        next.sort((left, right) => {
            const names = String(left.name || "").localeCompare(String(right.name || ""))
            return names || String(left.cardId).localeCompare(String(right.cardId))
        })
        const stacks = []
        const byKey = ({})
        for (const item of next) {
            const key = root.cardStackKey(item)
            if (!byKey[key]) {
                byKey[key] = []
                stacks.push(byKey[key])
            }
            byKey[key].push(item.cardId)
        }
        visibleCards = next
        visibleStackIds = stacks
    }
    function itemFor(id) { return visibleCards.find(item => item.cardId === id) || null }
    function reveal(id) {
        const item = itemFor(id)
        if (!item) return false
        viewport.contentY = Math.max(0, Math.min(item.y, viewport.contentHeight - viewport.height))
        return true
    }
    function pointFor(id, target) {
        const item = itemFor(id)
        if (!item || item.y < viewport.contentY || item.y + item.height > viewport.contentY + viewport.height)
            return Qt.point(0, 0)
        // mapToItem alone does not notify bindings when an ancestor moves.
        void root.x; void root.y; void root.width; void root.height
        void viewport.x; void viewport.y; void item.x
        return item.mapToItem(target, item.width / 2, item.height / 2)
    }
    Timer { id: refresh; interval: 0; onTriggered: root.collect() }
    Connections {
        target: root.tableController.rulesSession
        function onSnapshotChanged() { refresh.restart() }
    }
    Connections {
        target: root.tableController.interaction
        function onNativeSelectedTargetIdsChanged() { refresh.restart() }
    }
    Connections {
        target: root.tableController.combatInteraction
        function onSourcesChanged() { refresh.restart() }
    }
    onOwnerSeatChanged: { refresh.restart(); viewport.contentY = 0 }
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
        required property int exiledCardCount
        required property var exiledCardIds
        required property var chosenCardIds
        required property var annotations
        readonly property string category: {
            void root.tableController.cardCatalogModel.imageRevision
            return grouping.category(slot, root.tableController.cardCatalogModel)
        }
        readonly property bool matches: root.zone === "battlefield"
            ? controllerSeat === root.ownerSeat && category === root.category
            : zoneOwnerSeat === root.ownerSeat && zone === root.zone
        readonly property string stackKey: root.cardStackKey(slot)
        readonly property int stackIndex: {
            void root.visibleStackIds
            for (let i = 0; i < root.visibleStackIds.length; ++i) {
                if (root.visibleStackIds[i].indexOf(slot.cardId) >= 0)
                    return i
            }
            return -1
        }
        readonly property int stackRank: stackIndex >= 0
            ? root.visibleStackIds[stackIndex].indexOf(slot.cardId) : -1
        readonly property int stackSize: stackIndex >= 0 ? root.visibleStackIds[stackIndex].length : 1
        readonly property bool stackFront: {
            if (stackSize <= 1)
                return true
            const ids = root.visibleStackIds[stackIndex]
            if (root.locatedId && ids.indexOf(root.locatedId) >= 0)
                return slot.cardId === root.locatedId
            return stackRank === stackSize - 1
        }
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
        function stackActivateId() {
            const combat = root.tableController.combatInteraction
            if (!combat || !combat.active || stackSize <= 1 || !stackFront)
                return slot.cardId
            const ids = root.visibleStackIds[stackIndex]
            if (root.locatedId && ids.indexOf(root.locatedId) >= 0)
                return root.locatedId
            for (let i = 0; i < ids.length; ++i) {
                if (combat.actionable(ids[i]) && !stackMemberTaken(ids[i]))
                    return ids[i]
            }
            return slot.cardId
        }
        visible: matches && stackIndex >= 0
        width: root.cardWidth
        height: root.cardHeight
        x: 3 * root.unit + root.rowLead + (stackIndex % root.columns) * (width + root.gap)
           + pileDepth * 4 * root.unit
        y: 3 * root.unit + Math.floor(stackIndex / root.columns) * root.cellHeight
           + pileDepth * 4 * root.unit
        z: (slot.cardId === root.locatedId ? 1000 : 0) + Math.max(0, stackRank)
        onMatchesChanged: refresh.restart()
        ForgeCard {
            objectName: slot.matches ? "forgeCard-" + slot.cardId : ""
            anchors.fill: parent
            tableController: root.tableController
            card: slot
            unit: root.unit
            pointerEnabled: slot.stackFront
            fullFace: root.showFullFace
            located: slot.cardId === root.locatedId
            onActiveFocusChanged: if (activeFocus) root.reveal(slot.cardId)
        }
        Rectangle {
            objectName: slot.stackFront && slot.stackSize > 1 ? "forgeCardStackCount-" + slot.cardId : ""
            visible: slot.stackFront && slot.stackSize > 1
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.margins: 3 * root.unit
            z: 20
            width: stackCountLabel.implicitWidth + 10 * root.unit
            height: 18 * root.unit
            radius: 4 * root.unit
            color: "#d8b56a"
            Text {
                id: stackCountLabel
                objectName: slot.stackFront && slot.stackSize > 1 ? "forgeCardStackCountLabel-" + slot.cardId : ""
                textFormat: Text.PlainText
                anchors.centerIn: parent
                text: "×" + slot.stackSize
                color: "#19232b"
                font.pixelSize: 11 * root.unit
                font.weight: Font.Bold
            }
        }
    }
    Flickable {
        id: viewport
        objectName: root.objectName + "Viewport"
        y: root.headerHeight
        width: root.width
        height: Math.max(0, root.height - y)
        contentWidth: width
        contentHeight: Math.max(height, Math.ceil(root.stackCount / root.columns) * root.cellHeight + 5 * root.unit)
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
        Repeater {
            id: cards
            model: root.zone === "battlefield" ? root.tableController.rulesSession.battlefieldCards : root.tableController.rulesSession.zoneCards
            onItemAdded: refresh.restart()
            onItemRemoved: refresh.restart()
            delegate: CardSlot {}
        }
    }
}
