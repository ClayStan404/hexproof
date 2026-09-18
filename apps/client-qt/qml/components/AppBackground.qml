// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Effects

Item {
    id: root
    clip: true

    property string variant: "menu"
    readonly property bool glassLook: Theme.useGlass
    readonly property bool tableLook: variant === "playmat"
    readonly property bool playmatLook: tableLook && TableBackgrounds.hasImage

    function claimBackdrop() {
        if (!root.glassLook)
            return
        Theme.backdropScene = playmatLook ? rawLight : scene
        Theme.backdropBlur = playmatLook ? rawLight : scene
    }

    function releaseBackdrop() {
        if (Theme.backdropScene === scene || Theme.backdropScene === rawLight)
            Theme.backdropScene = null
        if (Theme.backdropBlur === scene || Theme.backdropBlur === rawLight)
            Theme.backdropBlur = null
    }

    Component.onCompleted: claimBackdrop()
    onVisibleChanged: if (visible) claimBackdrop()
    onPlaymatLookChanged: if (visible) claimBackdrop()
    onGlassLookChanged: {
        if (glassLook)
            claimBackdrop()
        else
            releaseBackdrop()
    }
    Component.onDestruction: releaseBackdrop()

    Item {
        id: classicWorld
        anchors.fill: parent
        visible: !root.glassLook && !root.tableLook

        Rectangle {
            anchors.fill: parent
            color: Theme.background
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: Theme.background }
                GradientStop { position: 0.62; color: Theme.backgroundRaised }
                GradientStop { position: 1.0; color: "#0B1B15" }
            }
        }

        Rectangle {
            width: Math.max(520, root.width * 0.52)
            height: width
            radius: width / 2
            x: root.width - width * 0.62
            y: -height * 0.58
            color: "#0D4B37"
            opacity: 0.18
        }

        Rectangle {
            width: Math.max(360, root.width * 0.34)
            height: width
            radius: width / 2
            x: -width * 0.48
            y: root.height - height * 0.42
            color: "#755B2B"
            opacity: 0.07
        }

        Rectangle {
            width: 250
            height: 356
            radius: 22
            x: root.width - 162
            y: root.height * 0.43
            rotation: 13
            color: "transparent"
            border.width: 1
            border.color: "#217557"
            opacity: 0.14
        }

        Rectangle {
            width: 220
            height: 314
            radius: 20
            x: root.width - 255
            y: root.height * 0.56
            rotation: -5
            color: "transparent"
            border.width: 1
            border.color: Theme.accent
            opacity: 0.07
        }
    }

    Item {
        objectName: "tableDefaultBackground"
        anchors.fill: parent
        visible: root.tableLook && !root.glassLook && !root.playmatLook

        Rectangle {
            anchors.fill: parent
            color: Theme.background
            gradient: Gradient {
                orientation: Gradient.Vertical
                GradientStop { position: 0.0; color: "#0A1511" }
                GradientStop { position: 0.42; color: Theme.backgroundRaised }
                GradientStop { position: 1.0; color: "#07110D" }
            }
        }

        Rectangle {
            width: Math.max(620, root.width * 0.58)
            height: width * 0.72
            radius: width / 2
            antialiasing: true
            anchors.horizontalCenter: parent.horizontalCenter
            y: parent.height * 0.06
            color: "#C4A05A"
            opacity: 0.07
        }

        Rectangle {
            width: Math.max(480, root.width * 0.46)
            height: width
            radius: width / 2
            antialiasing: true
            x: root.width - width * 0.58
            y: -height * 0.46
            color: "#0D4B37"
            opacity: 0.16
        }

        Rectangle {
            width: Math.max(360, root.width * 0.34)
            height: width
            radius: width / 2
            antialiasing: true
            x: -width * 0.42
            y: root.height - height * 0.46
            color: "#755B2B"
            opacity: 0.08
        }

        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                orientation: Gradient.Vertical
                GradientStop { position: 0.0; color: "#4D000000" }
                GradientStop { position: 0.22; color: "#00000000" }
                GradientStop { position: 0.78; color: "#00000000" }
                GradientStop { position: 1.0; color: "#66000000" }
            }
        }
    }

    Item {
        id: rawLight
        anchors.fill: parent
        visible: root.glassLook || root.playmatLook

        Rectangle {
            anchors.fill: parent
            visible: !root.playmatLook
            gradient: Gradient {
                orientation: Gradient.Vertical
                GradientStop { position: 0.0; color: "#0B141C" }
                GradientStop { position: 0.45; color: "#081018" }
                GradientStop { position: 1.0; color: "#06080E" }
            }
        }

        Image {
            objectName: "tableBackgroundImage"
            visible: root.playmatLook
            anchors.fill: parent
            source: root.playmatLook ? TableBackgrounds.source : ""
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            cache: true
        }

        Rectangle {
            anchors.fill: parent
            visible: root.playmatLook
            color: "#30000000"
        }

        Rectangle {
            id: cyanBloom
            visible: !root.playmatLook
            width: Math.max(720, root.width * 0.78)
            height: width
            radius: width / 2
            x: root.width - width * 0.50
            y: -height * 0.62
            color: "#3BB8D4"
            opacity: 0.34
        }

        Rectangle {
            id: mintBloom
            visible: !root.playmatLook
            width: Math.max(420, root.width * 0.40)
            height: width
            radius: width / 2
            x: root.width - width * 0.16
            y: root.height * 0.10
            color: "#4CC9A8"
            opacity: 0.14
        }

        Rectangle {
            id: violetBloom
            visible: !root.playmatLook
            width: Math.max(560, root.width * 0.52)
            height: width
            radius: width / 2
            x: -width * 0.48
            y: root.height * 0.16
            color: "#6A5AE0"
            opacity: 0.22
        }

        Rectangle {
            visible: !root.playmatLook
            width: Math.max(380, root.width * 0.36)
            height: width
            radius: width / 2
            x: -width * 0.20
            y: root.height - height * 0.40
            color: "#C4924A"
            opacity: 0.10
        }

        SequentialAnimation {
            running: root.glassLook && !root.playmatLook
            loops: Animation.Infinite
            ParallelAnimation {
                NumberAnimation {
                    target: cyanBloom
                    property: "x"
                    to: root.width - cyanBloom.width * 0.44
                    duration: 22000
                    easing.type: Easing.InOutSine
                }
                NumberAnimation {
                    target: violetBloom
                    property: "y"
                    to: root.height * 0.08
                    duration: 26000
                    easing.type: Easing.InOutSine
                }
            }
            ParallelAnimation {
                NumberAnimation {
                    target: cyanBloom
                    property: "x"
                    to: root.width - cyanBloom.width * 0.56
                    duration: 22000
                    easing.type: Easing.InOutSine
                }
                NumberAnimation {
                    target: violetBloom
                    property: "y"
                    to: root.height * 0.22
                    duration: 26000
                    easing.type: Easing.InOutSine
                }
            }
        }
    }

    MultiEffect {
        id: scene
        anchors.fill: parent
        visible: root.glassLook && !root.playmatLook
        source: rawLight
        autoPaddingEnabled: false
        blurEnabled: true
        blurMax: root.playmatLook ? 8 : 72
        blur: root.playmatLook ? 0.04 : 0.88
        blurMultiplier: 1.1
        saturation: root.playmatLook ? 1.06 : 0.92
        brightness: root.playmatLook ? 0.02 : -0.02
    }

    Rectangle {
        visible: root.playmatLook
        anchors.fill: parent
        z: 1
        gradient: Gradient {
            orientation: Gradient.Vertical
            GradientStop { position: 0.0; color: "#6605080A" }
            GradientStop { position: 0.18; color: "#00000000" }
            GradientStop { position: 0.82; color: "#00000000" }
            GradientStop { position: 1.0; color: "#8805080A" }
        }
    }
}
