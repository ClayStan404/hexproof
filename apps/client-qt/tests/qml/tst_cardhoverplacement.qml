// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic
import QtTest
import "../../qml/components"

TestCase {
    id: testCase
    name: "CardHoverPlacement"
    when: windowShown

    ApplicationWindow { id: window; width: 1200; height: 800; visible: true }
    Component {
        id: sceneComponent
        Item {
            id: scene
            width: 1200; height: 800
            property int faceCount: 1
            property alias preview: preview
            property alias source: source
            property alias controls: controls
            QtObject {
                id: catalog
                function cardFaces(name, set, number) {
                    return scene.faceCount === 2 ? [{name:"Front"}, {name:"Back"}] : []
                }
                function cardDisplayName(name) { return name }
                function imageSource(name, set, number) { return "" }
            }
            Item { id: source; x: 970; y: 100; width: 100; height: 140 }
            Item { id: controls; x: 650; y: 350; width: 550; height: 450 }
            CardHoverPreview {
                id: preview
                catalogModel: catalog
                avoidItems: [controls]
            }
        }
    }
    function test_readablePreviewStaysBesideSourceInsteadOfLargerRemoteArea_data() {
        return [{tag:"single-face", faces:1}, {tag:"two-faces", faces:2}]
    }
    function test_readablePreviewStaysBesideSourceInsteadOfLargerRemoteArea(data) {
        const scene = createTemporaryObject(sceneComponent, window.contentItem, {faceCount:data.faces})
        verify(scene !== null)
        scene.preview.inspect({name:"Front"}, scene.source)
        tryCompare(scene.preview, "visible", true)
        verify(waitForPolish(window))
        const preview = scene.preview
        const gallery = findChild(preview, "cardHoverPreviewFaces")
        verify(gallery.faceWidth >= Theme.size(180), "Nearby complete faces must remain readable")
        verify(preview.x >= 0 && preview.y >= 0
            && preview.x + preview.width <= scene.width + 0.1
            && preview.y + preview.height <= scene.height + 0.1)
        verify(preview.x + preview.width <= scene.controls.x
            || preview.y + preview.height <= scene.controls.y
            || preview.x >= scene.controls.x + scene.controls.width
            || preview.y >= scene.controls.y + scene.controls.height,
            "The nearby preview must still avoid the controls")
        verify(preview.x + preview.width >= scene.source.x - Theme.size(48),
            "A readable pocket beside the source must beat a larger remote preview: "
            + JSON.stringify({x:preview.x, y:preview.y, width:preview.width, height:preview.height}))
    }
    function test_unreadableNearbySliverDoesNotDisplaceReadableFaces_data() {
        return [{tag:"single-face", faces:1}, {tag:"two-faces", faces:2}]
    }
    function test_unreadableNearbySliverDoesNotDisplaceReadableFaces(data) {
        const scene = createTemporaryObject(sceneComponent, window.contentItem, {faceCount:data.faces})
        scene.controls.y = 220
        scene.controls.height = scene.height - scene.controls.y
        scene.preview.inspect({name:"Front"}, scene.source)
        tryCompare(scene.preview, "visible", true)
        verify(waitForPolish(window))
        const gallery = findChild(scene.preview, "cardHoverPreviewFaces")
        compare(gallery.faceCount, data.faces)
        verify(gallery.faceWidth >= Theme.size(180),
            "Keep complete readable faces when only a small sliver is available beside the source")
        verify(scene.preview.x + scene.preview.width <= scene.controls.x - Theme.size(12) + 0.1)
    }
    function test_unobstructedPreviewRetainsOriginalSidePlacement_data() {
        return [{tag:"right-of-left-source", x:40, right:true},
            {tag:"left-of-right-source", x:970, right:false}]
    }
    function test_unobstructedPreviewRetainsOriginalSidePlacement(data) {
        const scene = createTemporaryObject(sceneComponent, window.contentItem)
        scene.controls.visible = false
        scene.source.x = data.x
        scene.preview.inspect({name:"Front"}, scene.source)
        tryCompare(scene.preview, "visible", true)
        verify(waitForPolish(window))
        fuzzyCompare(scene.preview.y, scene.source.y, 0.1)
        if (data.right)
            fuzzyCompare(scene.preview.x, scene.source.x + scene.source.width + Theme.size(12), 0.1)
        else
            fuzzyCompare(scene.preview.x + scene.preview.width, scene.source.x - Theme.size(12), 0.1)
    }
}
