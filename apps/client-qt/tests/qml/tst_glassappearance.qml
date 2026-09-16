// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtTest
import "../../qml/components"

TestCase {
    id: testCase
    name: "GlassAppearance"
    when: windowShown
    visible: true
    width: 500
    height: 400

    Component {
        id: sceneComponent

        Item {
            id: coloredScene
            width: 500
            height: 400
            property color topColor: "red"
            property color bottomColor: "blue"
            property alias backdrop: backdrop
            property alias viewport: viewport
            property alias holder: holder
            property alias pane: pane
            property alias button: button

            Item {
                id: backdrop
                anchors.fill: parent
                Rectangle {
                    width: parent.width
                    height: parent.height / 2
                    color: coloredScene.topColor
                }
                Rectangle {
                    width: parent.width
                    height: parent.height / 2
                    y: parent.height / 2
                    color: coloredScene.bottomColor
                }
            }

            Flickable {
                id: viewport
                anchors.fill: parent
                contentWidth: width
                contentHeight: 800
                boundsBehavior: Flickable.StopAtBounds
                interactive: false
                clip: true

                Item {
                    id: holder
                    x: 100
                    y: 40
                    width: 300
                    height: 320

                    LiquidGlass {
                        id: pane
                        anchors.fill: parent
                        radius: 18
                    }
                }
            }

            AppButton {
                id: button
                x: 150
                y: 150
                width: 200
                text: "Open"
                visible: false
            }
        }
    }

    function createScene() {
        const scene = createTemporaryObject(sceneComponent, testCase)
        verify(scene !== null)
        Theme.uiTheme = "glass"
        Theme.backdropScene = scene.backdrop
        scene.pane.syncGrab()
        return scene
    }

    function cleanup() {
        Theme.uiTheme = "classic"
        Theme.backdropScene = null
        Theme.backdropBlur = null
    }

    function test_preservesBackdropOrientation() {
        if (testCase.GraphicsInfo.api === GraphicsInfo.Software
                || testCase.GraphicsInfo.api === GraphicsInfo.Null)
            skip("Shader rendering requires a graphics backend; also run this test in a native window.")

        const scene = createScene()
        verify(waitForRendering(scene))
        const shot = grabImage(scene)
        const x = Math.round(250 * shot.width / scene.width)
        const top = Math.round(100 * shot.height / scene.height)
        const bottom = Math.round(300 * shot.height / scene.height)
        verify(shot.red(x, top) > shot.blue(x, top),
               "The red backdrop must remain above the blue backdrop inside the glass")
        verify(shot.blue(x, bottom) > shot.red(x, bottom),
               "The blue backdrop must remain below the red backdrop inside the glass")
        verify(shot.green(x, top) > 0 && shot.green(x, bottom) > 0,
               "Both samples must include the glass frost, not just the unmodified backdrop")
    }

    function test_brightBackdropPreservesLabelContrast() {
        if (testCase.GraphicsInfo.api === GraphicsInfo.Software
                || testCase.GraphicsInfo.api === GraphicsInfo.Null)
            skip("Shader rendering requires a graphics backend; also run this test in a native window.")

        const scene = createScene()
        scene.topColor = "white"
        scene.bottomColor = "white"
        scene.pane.compact = true
        verify(waitForRendering(scene))
        const shot = grabImage(scene.pane)
        const x = Math.floor(shot.width / 2)
        const y = Math.floor(shot.height / 2)
        verify(shot.red(x, y) < 125 && shot.green(x, y) < 125 && shot.blue(x, y) < 125,
               "Bright artwork must not wash out glass controls that use light labels")
    }

    function test_followsScrolling() {
        const scene = createScene()
        verify(!scene.pane.elevated && !scene.pane.compact)
        const previous = scene.pane.grabRect
        scene.viewport.contentY = 80
        tryCompare(scene.pane, "grabRect",
                   Qt.rect(previous.x, previous.y - 80, previous.width, previous.height))
    }

    function test_followsReparentedPanel() {
        const scene = createScene()
        scene.viewport.contentY = 80
        scene.pane.syncGrab()
        const previous = scene.pane.grabRect
        // Dragged card rows move from the scrolled content to an overlay.
        scene.holder.parent = scene
        scene.holder.x += 30
        scene.holder.y += 20
        tryCompare(scene.pane, "grabRect",
                   Qt.rect(previous.x + 30, previous.y + 100,
                           previous.width, previous.height))
    }

    function test_buttonShowsKeyboardFocus_data() {
        return [
            {tag: "glass-secondary", theme: "glass", variant: "secondary"},
            {tag: "glass-highlight", theme: "glass", variant: "highlight"},
            {tag: "glass-ghost", theme: "glass", variant: "ghost"},
            {tag: "classic-secondary", theme: "classic", variant: "secondary"}
        ]
    }

    function test_buttonShowsKeyboardFocus(data) {
        const scene = createScene()
        Theme.uiTheme = data.theme
        scene.pane.visible = false
        scene.button.variant = data.variant
        scene.button.visible = true
        scene.forceActiveFocus()
        mouseMove(scene, scene.width - 2, scene.height - 2)
        wait(Theme.motionNormal)
        verify(!scene.button.activeFocus)
        const unfocused = grabImage(scene.button)

        scene.button.forceActiveFocus(Qt.TabFocusReason)
        wait(Theme.motionNormal)
        verify(scene.button.activeFocus)
        verify(!unfocused.equals(grabImage(scene.button)),
               "Keyboard focus must visibly change the button")

        scene.forceActiveFocus()
        wait(Theme.motionNormal)
        verify(unfocused.equals(grabImage(scene.button)),
               "The focus indicator must disappear when focus leaves")
    }
}
