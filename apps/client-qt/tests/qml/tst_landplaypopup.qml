// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic
import QtTest
import "../../qml/components"

TestCase {
    name: "LandPlayPopup"
    when: windowShown
    ApplicationWindow {
        id: window
        width: 900
        height: 620
        visible: true
        LandPlayPopup { id: popup }
    }
    function cleanup() {
        popup.close()
        Theme.uiScale = 1
        testTranslations.setLanguage("en")
    }
    function test_warningActionsRemainInsidePopup_data() {
        return [
            {tag: "en-large", language: "en", scale: 1.5},
            {tag: "zh-large", language: "zh", scale: 1.5},
            {tag: "en-maximum", language: "en", scale: 1.8}
        ]
    }
    function test_warningActionsRemainInsidePopup(data) {
        Theme.uiScale = data.scale
        testTranslations.setLanguage(data.language)
        popup.showFor({name: "Front // Back"}, [
            {faceName: "", displayName: "Front", typeLine: "Legendary Artifact Enchantment Creature — Phyrexian Shapeshifter"},
            {faceName: "Back", displayName: "Back", typeLine: "Land"}
        ], 2147483647, "combat", 3)
        tryVerify(() => popup.opened)
        waitForRendering(popup.contentItem)
        compare(popup.warnings.length, 5)
        const button = findChild(popup, "confirmLandPlayButton")
        const origin = button.mapToItem(window.contentItem, 0, 0)
        verify(origin.y >= popup.y)
        verify(origin.y + button.height <= popup.y + popup.height)
        verify(origin.y + button.height <= window.height)
        verify(!button.enabled)
    }
}
