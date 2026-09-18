// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic

Item {
    id: root
    required property var tableController
    property real unit: 1
    property var visibleCards: []
    readonly property bool crowded: visibleCards.length > 9
    readonly property real cardWidth: 132 * unit
    readonly property real faceHeight: cardWidth * 1.394
    readonly property real step: crowded ? 88 * unit : Math.min(103 * unit, (width - cardWidth) / Math.max(1, visibleCards.length - 1))
    readonly property real fanWidth: cardWidth + step * Math.max(0, visibleCards.length - 1)
    readonly property Flickable scrollArea: viewport
    function collect() {
        const next = []
        for (let i = 0; i < cards.count; ++i) {
            const card = cards.itemAt(i) as HandSlot
            if (card && card.matches) next.push(card)
        }
        visibleCards = next
    }
    function reveal(card) {
        if (crowded) viewport.contentX = Math.max(0, Math.min(card.x - 8 * unit, viewport.contentWidth - viewport.width))
    }
    Timer { id: refresh; interval: 0; onTriggered: root.collect() }
    Connections {
        target: root.tableController.rulesSession
        function onSnapshotChanged() { refresh.restart() }
    }
    Text {
        textFormat: Text.PlainText
        y: -16 * root.unit
        text: root.tableController.handOwnerSeat < 0 ? qsTr("Hands are hidden from spectators in this room")
            : root.tableController.canViewSpectatorHands ? qsTr("%1 — hand (read only)").arg(root.tableController.matchUi.playerName(root.tableController.handOwnerSeat))
            : qsTr("Hand · %1").arg(root.visibleCards.length)
        color: Theme.textMuted
        font.pixelSize: 10 * root.unit
    }
    component HandSlot: Item {
        id: slot
        required property string cardId
        required property string zone
        required property int zoneOwnerSeat
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
        readonly property bool matches: zone === "hand" && zoneOwnerSeat === root.tableController.handOwnerSeat
        readonly property int position: root.visibleCards.indexOf(slot)
        readonly property real distance: position - (root.visibleCards.length - 1) / 2
        readonly property bool canPlay: root.tableController.canDragHandCard(cardId)
        objectName: "forgeHandCard-" + cardId
        visible: matches && position >= 0
        x: (root.crowded ? 8 * root.unit : (root.width - root.fanWidth) / 2) + position * root.step
        y: 26 * root.unit + (root.crowded ? 0 : Math.abs(distance) * 2 * root.unit)
        width: root.cardWidth
        // Only the exposed upper half receives input. The full face extends
        // below the window; hover inspection supplies readable card text.
        height: Math.max(1, root.height - 8 * root.unit)
        z: pointer.containsMouse || face.activeFocus ? 50 : position
        onMatchesChanged: refresh.restart()
        ForgeCard {
            id: face
            objectName: "forgeHandSurface-" + slot.cardId
            width: slot.width
            height: root.faceHeight
            unit: root.unit
            card: slot
            tableController: root.tableController
            fullFace: true
            pointerEnabled: false
            activeFocusOnTab: true
            onActiveFocusChanged: {
                if (activeFocus) {
                    root.reveal(slot)
                    root.tableController.previewCard(slot.cardId, slot)
                } else root.tableController.endCardPreview(slot)
            }
            y: pointer.containsMouse && !pointer.drag.active ? -18 * root.unit : 0
            rotation: pointer.containsMouse || root.crowded ? 0 : slot.distance * 2.5
            opacity: pointer.drag.active ? 0.4 : 1
            Behavior on y { NumberAnimation { duration: 120 } }
            Behavior on rotation { NumberAnimation { duration: 120 } }
        }
        ForgeCard {
            id: ghost
            readonly property string cardId: slot.cardId
            readonly property string name: slot.name
            parent: root.tableController
            width: slot.width
            height: root.faceHeight
            visible: pointer.drag.active
            z: 1000
            unit: root.unit
            card: slot
            tableController: root.tableController
            fullFace: true
            pointerEnabled: false
            Drag.active: pointer.drag.active
            Drag.source: ghost
            Drag.keys: ["hexproof/rules-card"]
            Drag.hotSpot.x: width / 2
            Drag.hotSpot.y: height / 2
        }
        MouseArea {
            id: pointer
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            cursorShape: face.actionable ? Qt.PointingHandCursor : Qt.ArrowCursor
            drag.target: slot.canPlay ? ghost : null
            drag.threshold: 6 * root.unit
            preventStealing: slot.canPlay
            onEntered: root.tableController.previewCard(slot.cardId, slot)
            onExited: root.tableController.endCardPreview(slot)
            onPressed: event => {
                root.tableController.endCardPreview(slot)
                const point = slot.mapToItem(root.tableController, 0, 0)
                ghost.x = point.x
                ghost.y = point.y
            }
            onReleased: { if (drag.active) ghost.Drag.drop() }
            onCanceled: ghost.Drag.cancel()
            onClicked: event => {
                if (event.button === Qt.LeftButton) face.activate()
                else root.tableController.openCardDetails(slot.cardId)
            }
        }
        Component.onDestruction: root.tableController.endCardPreview(slot)
    }
    Flickable {
        id: viewport
        objectName: "forgeHandViewport"
        y: -26 * root.unit
        width: root.width
        height: root.height + 26 * root.unit
        contentWidth: Math.max(width, root.fanWidth + 16 * root.unit)
        contentHeight: height
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.HorizontalFlick
        ScrollBar.horizontal: ScrollBar { policy: ScrollBar.AsNeeded }
        WheelHandler {
            onWheel: event => {
                viewport.contentX = Math.max(0, Math.min(viewport.contentWidth - viewport.width,
                    viewport.contentX - (event.angleDelta.x || event.angleDelta.y)))
                event.accepted = true
            }
        }
        Repeater {
            id: cards
            model: root.tableController.rulesSession.zoneCards
            onItemAdded: refresh.restart()
            onItemRemoved: refresh.restart()
            delegate: HandSlot {}
        }
    }
}
