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
    property string locatedId: ""
    property var visibleCards: []
    readonly property int cardCount: zone === "battlefield" ? visibleCards.length
        : tableController.zoneCount(ownerSeat, zone)
    readonly property Flickable scrollArea: viewport
    readonly property real gap: 8 * unit
    readonly property real cardWidth: fittedCardWidth()
    readonly property real cardHeight: cardWidth * (zone === "battlefield" ? 0.93 : 1.394)
    readonly property int columns: Math.max(1, Math.floor((viewport.width - 6 * unit + gap) / (cardWidth + gap) + 1e-7))
    readonly property real cellHeight: cardHeight + (tableController.combatInteraction.active ? 22 : 10) * unit

    // Choose the largest readable grid that fits both dimensions. A fixed
    // minimum-width row used to clip even a few noncreature permanents.
    function fittedCardWidth() {
        const count = Math.max(1, visibleCards.length)
        const available = Math.max(1, viewport.width - 6 * unit)
        const maximum = Math.min(available, (category === "creature" ? 180 : zone === "battlefield" ? 96 : 120) * unit)
        const minimum = Math.min(maximum, (category === "creature" ? 80 : 64) * unit)
        const extra = (tableController.combatInteraction.active ? 22 : 10) * unit
        const ratio = zone === "battlefield" ? 0.93 : 1.394
        let best = minimum
        for (let cols = 1; cols <= count; ++cols) {
            const candidate = Math.min(maximum, (available - (cols - 1) * gap) / cols)
            if (candidate < minimum) break
            const rows = Math.ceil(count / cols)
            if (rows * (candidate * ratio + extra) + 5 * unit <= viewport.height)
                best = Math.max(best, candidate)
        }
        return best
    }

    RulesBattlefieldLayout { id: grouping }
    function collect() {
        const next = []
        for (let i = 0; i < cards.count; ++i) {
            const item = cards.itemAt(i) as CardSlot
            if (item && item.matches) next.push(item)
        }
        visibleCards = next
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
        return item.mapToItem(target, item.width / 2, item.height / 2)
    }
    Timer { id: refresh; interval: 0; onTriggered: root.collect() }
    Connections {
        target: root.tableController.rulesSession
        function onSnapshotChanged() { refresh.restart() }
    }
    onOwnerSeatChanged: { refresh.restart(); viewport.contentY = 0 }
    Text {
        objectName: root.objectName + "Count"
        textFormat: Text.PlainText
        text: root.caption + "  /  " + root.cardCount
        color: "#96adb9"
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
        color: "#96adb9"
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
        required property bool tapped
        required property bool faceDown
        required property bool attacking
        required property string power
        required property string toughness
        required property string countersSummary
        required property int damage
        required property string attachedTo
        required property int exiledCardCount
        readonly property string category: {
            void root.tableController.cardCatalogModel.imageRevision
            return grouping.category(slot, root.tableController.cardCatalogModel)
        }
        readonly property bool matches: root.zone === "battlefield"
            ? controllerSeat === root.ownerSeat && category === root.category
            : zoneOwnerSeat === root.ownerSeat && zone === root.zone
        readonly property int position: root.visibleCards.indexOf(slot)
        visible: matches && position >= 0
        width: root.cardWidth
        height: root.cardHeight
        x: 3 * root.unit + (position % root.columns) * (width + root.gap)
            + (root.category === "creature" && root.visibleCards.length <= root.columns
               ? Math.max(0, (viewport.width - root.visibleCards.length * (width + root.gap) + root.gap) / 2 - 3 * root.unit) : 0)
        y: 3 * root.unit + Math.floor(position / root.columns) * root.cellHeight
        onMatchesChanged: refresh.restart()
        ForgeCard {
            objectName: slot.matches ? "forgeCard-" + slot.cardId : ""
            anchors.fill: parent
            tableController: root.tableController
            card: slot
            unit: root.unit
            fullFace: root.zone !== "battlefield"
            located: slot.cardId === root.locatedId
            onActiveFocusChanged: if (activeFocus) root.reveal(slot.cardId)
        }
    }
    Flickable {
        id: viewport
        objectName: root.objectName + "Viewport"
        y: 20 * root.unit
        width: root.width
        height: Math.max(0, root.height - y)
        contentWidth: width
        contentHeight: Math.max(height, Math.ceil(root.visibleCards.length / root.columns) * root.cellHeight + 5 * root.unit)
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
