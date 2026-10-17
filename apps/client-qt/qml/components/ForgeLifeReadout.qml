// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors
pragma ComponentBehavior: Bound
import QtQuick

Item {
    id: root
    required property int life
    required property int seat
    property real unit: 1
    property color numberColor: Theme.accent
    property bool alignDeltaLeft: false
    // Reserve the entire rise even while no change is being displayed. The
    // surrounding metadata must not reflow when an animation starts or ends.
    readonly property real deltaClearance: Math.ceil(deltaMetrics.height) + 14 * unit
    property int display: life
    property int counted: life
    property bool ready: false
    property real deltaTravel: 0
    readonly property var readoutItems: [valueLabel, deltaLabel]

    Component.onCompleted: {
        display = life
        counted = life
        ready = true
    }
    onLifeChanged: {
        if (!ready)
            return
        // A running count ignores new endpoints, so always stop it first.
        count.stop()
        const delta = life - counted
        counted = life
        if (delta === 0 && display === life)
            return
        if (!Theme.motionEnabled || Theme.motionSnap) {
            settle()
            return
        }
        count.from = display
        count.to = life
        count.start()
        if (delta === 0)
            return
        deltaLabel.text = (delta > 0 ? "+" : "") + delta
        deltaLabel.color = delta > 0 ? "#7de2b8" : "#e07a72"
        deltaLabel.opacity = 1
        deltaTravel = 0
        deltaFade.restart()
    }
    function settle() {
        count.stop()
        deltaFade.stop()
        deltaLabel.opacity = 0
        display = life
    }
    Connections {
        target: Theme
        function onMotionEpochChanged() { root.settle() }
    }

    Text {
        id: valueLabel
        objectName: "forgeLifeValue-" + root.seat
        anchors.centerIn: parent
        textFormat: Text.PlainText
        text: root.display
        color: root.numberColor
        font.pixelSize: 22 * root.unit
        font.weight: Font.DemiBold
    }
    Text {
        id: deltaLabel
        objectName: "forgeLifeDelta-" + root.seat
        // Stay above the disc. The counting total remains the only digits
        // inside the circle; the signed change must not cover them.
        x: root.alignDeltaLeft ? 0 : (parent.width - width) / 2
        y: -implicitHeight - (2 + root.deltaTravel) * root.unit
        opacity: 0
        textFormat: Text.PlainText
        color: "#e07a72"
        font.pixelSize: 16 * root.unit
        font.weight: Font.Bold
        style: Text.Outline
        styleColor: Theme.withAlpha("#000000", 0.75)
    }
    FontMetrics {
        id: deltaMetrics
        font: deltaLabel.font
    }
    NumberAnimation {
        id: count
        target: root
        property: "display"
        duration: Theme.motionNormal
        easing.type: Easing.OutCubic
    }
    ParallelAnimation {
        id: deltaFade
        NumberAnimation {
            target: root
            property: "deltaTravel"
            to: 10
            duration: 900
            easing.type: Easing.OutCubic
        }
        NumberAnimation {
            target: deltaLabel
            property: "opacity"
            to: 0
            duration: 900
        }
    }
}
