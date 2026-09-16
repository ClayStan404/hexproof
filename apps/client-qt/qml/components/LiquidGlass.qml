// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Effects

Item {
    id: root

    property real radius: Theme.radiusXLarge
    property bool elevated: false
    property bool compact: false
    readonly property bool well: compact
    readonly property bool quiet: !compact && height > 0
                                  && height < Theme.size(200)
    readonly property bool castsPanelShadow: false
    readonly property bool drawn: Theme.useGlass
    readonly property Item backdrop: Theme.backdropScene
                                     ? Theme.backdropScene
                                     : Theme.backdropBlur
    readonly property bool live: root.backdrop !== null
                                 && root.backdrop.width > 1
                                 && root.width > 1
                                 && root.height > 1
    readonly property bool lensReady: lens.status === ShaderEffect.Compiled

    property rect grabRect: Qt.rect(0, 0, 1, 1)
    property real padPx: 16

    function syncGrab() {
        if (!root.backdrop || root.width < 1 || root.height < 1) {
            grabRect = Qt.rect(0, 0, 1, 1)
            padPx = 16
            return
        }
        padPx = Math.max(12, Math.round(Math.min(root.width, root.height)
                                        * (root.quiet ? 0.06 : 0.10)))
        const point = root.mapToItem(root.backdrop, -padPx, -padPx)
        grabRect = Qt.rect(point.x, point.y,
                           root.width + padPx * 2,
                           root.height + padPx * 2)
    }

    Component.onCompleted: syncGrab()
    onWidthChanged: syncGrab()
    onHeightChanged: syncGrab()
    onXChanged: syncGrab()
    onYChanged: syncGrab()
    onBackdropChanged: syncGrab()
    onVisibleChanged: if (visible) syncGrab()

    // Scrolling and reparenting move ancestors without changing our local x/y.
    Timer {
        interval: root.compact ? 100 : 50
        running: root.visible && root.drawn && root.live
        repeat: true
        onTriggered: root.syncGrab()
    }

    ShaderEffectSource {
        id: grab
        visible: false
        sourceItem: root.backdrop
        sourceRect: root.grabRect
        live: root.live && root.drawn
        hideSource: false
        textureMirroring: ShaderEffectSource.MirrorVertically
        smooth: true
    }

    Rectangle {
        id: maskPlate
        width: root.width
        height: root.height
        radius: root.radius
        color: "#FFFFFF"
        visible: false
        layer.enabled: true
        layer.smooth: true
    }

    MultiEffect {
        anchors.fill: parent
        visible: root.drawn && root.live && !root.lensReady
        source: grab
        autoPaddingEnabled: false
        maskEnabled: true
        maskSource: maskPlate
        blurEnabled: true
        blurMax: 48
        blur: 0.85
        brightness: 0.04
        saturation: 1.12
    }

    ShaderEffect {
        id: lens
        objectName: "liquidGlassLens"
        anchors.fill: parent
        visible: root.drawn
        opacity: root.live ? 1 : 0
        fragmentShader: "qrc:/shaders/qml/shaders/liquidglass.frag.qsb"
        property var source: grab
        property vector4d uItem: Qt.vector4d(Math.max(1, root.width),
                                             Math.max(1, root.height),
                                             root.radius,
                                             0)
        property vector4d uPad: Qt.vector4d(
            root.grabRect.width > 1 ? root.padPx / root.grabRect.width : 0.08,
            root.grabRect.height > 1 ? root.padPx / root.grabRect.height : 0.08,
            root.quiet ? 1.0 : 0.0,
            root.well ? 1.0 : 0.0)
    }

    Rectangle {
        anchors.fill: parent
        radius: root.radius
        antialiasing: true
        visible: root.drawn && !root.live
        color: root.elevated ? Theme.glassElevated : Theme.glass
        border.width: 0
    }
}
