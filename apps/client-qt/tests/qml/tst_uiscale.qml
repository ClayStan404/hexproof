// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtTest
import "../../qml/components"

TestCase {
    name: "UiScale"

    property real previousScale: 1.0

    AppTextField {
        id: utf8Field
        visible: false
        maximumUtf8Bytes: 72
    }

    function init() {
        previousScale = Theme.uiScale
    }

    function cleanup() {
        Theme.uiScale = previousScale
    }

    function test_scalesComponentSizesAndFontsTogether() {
        Theme.uiScale = 1.25
        compare(Theme.size(40), 50)
        compare(Theme.fontSize(16), 20)
        compare(Theme.radiusMedium, 15)
    }

    function test_combinesAutomaticAndUserScaleWithinSafeBounds() {
        compare(Theme.effectiveScale(1280, 800, 1.0), 1.0)
        compare(Theme.effectiveScale(1280, 800, 1.25), 1.25)
        compare(Theme.effectiveScale(2560, 1600, 1.5), 1.8)
        compare(Theme.effectiveScale(900, 620, 0.75), 0.75)
    }

    function test_detectsCompactViewportWidth() {
        verify(Theme.isCompactWidth(900))
        verify(Theme.isCompactWidth(1099))
        verify(!Theme.isCompactWidth(1100))
        verify(!Theme.isCompactWidth(1400))
        compare(Theme.compactWidthThreshold, 1100)
    }

    function test_enforcesUtf8ByteLimits() {
        utf8Field.text = "a".repeat(72)
        compare(utf8Field.utf8ByteLength, 72)
        verify(utf8Field.withinUtf8ByteLimit)

        utf8Field.text = "你".repeat(24)
        compare(utf8Field.utf8ByteLength, 72)
        verify(utf8Field.withinUtf8ByteLimit)

        utf8Field.text += "你"
        compare(utf8Field.utf8ByteLength, 75)
        verify(!utf8Field.withinUtf8ByteLimit)

        utf8Field.text = "😀".repeat(18)
        compare(utf8Field.utf8ByteLength, 72)
        verify(utf8Field.withinUtf8ByteLimit)
    }
}
