// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors
import QtQuick
import QtQuick.Controls.Basic

Item {
    id: root
    required property var cards
    property string assetRoot: ""
    property real unit: 1
    property bool canCast: true
    signal castRequested()
    signal inspected(var card)
    signal previewed(var card)
    signal previewEnded()
    readonly property real cardWidth: 132 * unit
    readonly property bool crowded: cards.length > 9
    readonly property real step: crowded ? 88 * unit : Math.min(103 * unit, (width - cardWidth) / Math.max(1, cards.length - 1))
    readonly property Item scrollArea: handViewport
    readonly property real fanWidth: cardWidth + step * Math.max(0, cards.length - 1)
    function itemFor(id) {
        for (let i = 0; i < cards.length; ++i) {
            if (cards[i].id === id) return handRepeater.itemAt(i)
        }
        return null
    }
    function reveal(id) {
        const item = itemFor(id)
        if (!item) return false
        if (crowded) handViewport.contentX = Math.max(0, Math.min(item.x - 8 * unit,
            handViewport.contentWidth - handViewport.width))
        return true
    }
    onCardsChanged: handViewport.contentX = 0
    StudyLabel {
        visible: root.crowded
        x: 4 * root.unit
        y: -22 * root.unit
        text: root.cards.length + " CARDS  /  SCROLL HAND"
        pointSize: 9
        unit: root.unit
        color: "#a7bbc6"
    }
    Flickable {
        id: handViewport
        y: -36 * root.unit
        width: root.width
        height: root.height + 36 * root.unit
        contentWidth: Math.max(width, root.fanWidth + 16 * root.unit)
        contentHeight: height
        clip: root.crowded
        interactive: root.crowded && contentWidth > width
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.HorizontalFlick
        ScrollBar.horizontal: ScrollBar {
            objectName: "studyHandScroll"
            policy: root.crowded ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
        }
        Repeater {
            id: handRepeater
            model: root.cards
            delegate: Item {
                id: slot
                required property int index
                required property var modelData
                readonly property Item surface: cardSurface
                objectName: "studyHand-" + modelData.id
                activeFocusOnTab: true
                onActiveFocusChanged: if (activeFocus) root.reveal(modelData.id)
                function activate() {
                    if (root.canCast && modelData.id === "bolt") root.castRequested()
                    else root.inspected(modelData)
                }
                Keys.onReturnPressed: activate()
                Keys.onSpacePressed: activate()
                readonly property real distance: index - (root.cards.length - 1) / 2
                x: (root.crowded ? 8 * root.unit : (root.width - root.fanWidth) / 2) + index * root.step
                y: 36 * root.unit + (root.crowded ? 0 : Math.abs(distance) * 3 * root.unit)
                width: root.cardWidth
                height: root.cardWidth * 1.394
                z: pointer.containsMouse ? 30 : index
                StudyCard {
                    id: cardSurface
                    card: slot.modelData
                    assetRoot: root.assetRoot
                    unit: root.unit
                    width: slot.width
                    height: slot.height
                    fullFace: true
                    pointerEnabled: false
                    focusRing: slot.activeFocus
                    y: pointer.containsMouse ? -28 * root.unit : 0
                    rotation: pointer.containsMouse || root.crowded ? 0 : slot.distance * 2.5
                    scale: pointer.containsMouse ? 1.08 : 1
                    actionable: root.canCast && card.id === "bolt"
                    actionHint: ""
                    onActivated: root.castRequested()
                    onInspected: card => root.inspected(card)
                    onPreviewed: card => root.previewed(card)
                    onPreviewEnded: root.previewEnded()
                    Behavior on y { NumberAnimation { duration: 120 } }
                    Behavior on rotation { NumberAnimation { duration: 120 } }
                    Behavior on scale { NumberAnimation { duration: 120 } }
                }
                // The input surface and its mouse grab stay stationary while art lifts.
                MouseArea {
                    id: pointer
                    anchors.fill: parent
                    z: 100
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    cursorShape: root.canCast && slot.modelData.id === "bolt" ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onEntered: root.previewed(slot.modelData)
                    onExited: root.previewEnded()
                    onClicked: event => {
                        if (event.button === Qt.LeftButton) slot.activate()
                        else root.inspected(slot.modelData)
                    }
                }
            }
        }
    }
}
