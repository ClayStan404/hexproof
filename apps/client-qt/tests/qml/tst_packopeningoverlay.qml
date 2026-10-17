// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic
import QtTest
import "../../qml/components"

TestCase {
    name: "PackOpeningOverlay"
    when: windowShown

    ApplicationWindow {
        id: testWindow
        width: 1100
        height: 760
        visible: true

        QtObject {
            id: mockCatalog
            property int imageRevision: 0

            function tableImageSource(cardName, setCode, collectorNumber) {
                return ""
            }
        }

        PackOpeningOverlay {
            id: overlay
            cardCatalogModel: mockCatalog
            reducedMotion: true
            cardBackSource: ""
        }
    }

    readonly property var testPacks: [
        {"cards": [
            {"name": "Rare Card", "rarity": "rare"},
            {"name": "Common Card", "rarity": "common"},
            {"name": "Mythic Card", "rarity": "mythic"},
            {"name": "Uncommon Card", "rarity": "uncommon"}
        ]},
        {"cards": [
            {"name": "Second Pack Card", "rarity": "common"}
        ]}
    ]

    function init() {
        overlay.close()
        overlay.packs = []
        overlay.currentPackIndex = 0
        overlay.revealedCardIndices = []
        overlay.stage = 0
    }

    function cleanup() {
        overlay.close()
        tryVerify(() => !overlay.opened)
        testWindow.width = 1100
        testWindow.height = 760
        Theme.uiScale = 1
        verify(waitForPolish(testWindow))
    }

    function test_boosterFitsSmallWindow_data() {
        return [{tag: "large", scale: 1.5}, {tag: "maximum", scale: 1.8}]
    }
    function test_boosterFitsSmallWindow(data) {
        testWindow.width = 900
        testWindow.height = 620
        Theme.uiScale = data.scale
        overlay.showPacks(testPacks, "Example booster product")
        tryVerify(() => overlay.opened)
        // Geometry and hit testing need polished layouts, not an additional frame
        // that a settled, reduced-motion popup may never schedule.
        verify(waitForPolish(testWindow))
        const booster = findChild(overlay, "packOpeningBooster")
        verify(booster.visible && booster.width > 0 && booster.height > 0)
        verify(booster.y >= 0)
        verify(booster.y + booster.height <= booster.parent.height - Theme.size(40))
        const aura = findChild(overlay, "packOpeningAura")
        const instruction = findChild(overlay, "packOpeningInstruction")
        verify(aura.y >= 0)
        verify(aura.y + aura.height <= instruction.y)
        mouseClick(booster)
        compare(overlay.stage, 1)
    }

    function test_revealsRaresLastAndAdvancesBetweenPacks_data() {
        return [
            {tag: "default", width: 1100, height: 760, scale: 1},
            {tag: "resized", width: 900, height: 620, scale: 1},
            {tag: "scaled", width: 1280, height: 800, scale: 1.35}
        ]
    }

    function test_revealsRaresLastAndAdvancesBetweenPacks(data) {
        testWindow.width = data.width
        testWindow.height = data.height
        Theme.uiScale = data.scale
        overlay.showPacks(testPacks, "Test Booster")
        tryVerify(() => overlay.opened)
        compare(overlay.productName, "Test Booster")
        compare(overlay.currentCards.length, 4)
        compare(overlay.currentCards[0].name, "Common Card")
        compare(overlay.currentCards[1].name, "Uncommon Card")
        compare(overlay.currentCards[2].name, "Rare Card")
        compare(overlay.currentCards[3].name, "Mythic Card")

        overlay.beginCurrentPack()
        compare(overlay.stage, 1)
        const cardGrid = findChild(overlay, "packOpeningCardGrid")
        verify(cardGrid !== null)
        tryCompare(cardGrid, "count", 4)
        // Delegates can already exist while their stage is hidden. Switching
        // stages schedules layout work, so existence alone is not a click barrier.
        verify(waitForPolish(testWindow))
        verify(waitForRendering(cardGrid))
        tryVerify(() => cardGrid.itemAtIndex(3) !== null)
        const mythicCard = cardGrid.itemAtIndex(3)
        const revealTarget = findChild(mythicCard, "packOpeningCard-3")
        verify(revealTarget !== null)
        verify(revealTarget.visible && revealTarget.enabled)
        verify(revealTarget.width > 0 && revealTarget.height > 0)
        const clickPosition = revealTarget.mapToItem(cardGrid,
            revealTarget.width / 2, revealTarget.height / 2)
        verify(clickPosition.x >= 0 && clickPosition.x < cardGrid.width
               && clickPosition.y >= 0 && clickPosition.y < cardGrid.height,
               "The actual reveal control must be inside the grid before clicking")
        mouseClick(revealTarget)
        compare(overlay.revealedCount, 1)
        verify(overlay.isCardRevealed(3))
        verify(!overlay.isCardRevealed(0))

        overlay.revealNext()
        compare(overlay.revealedCount, 2)
        verify(overlay.isCardRevealed(0))
        verify(!overlay.currentPackRevealed)
        overlay.revealAll()
        verify(overlay.currentPackRevealed)

        overlay.advanceOrFinish()
        compare(overlay.currentPackIndex, 1)
        compare(overlay.stage, 0)
        compare(overlay.revealedCount, 0)
        compare(overlay.currentCards.length, 1)

        overlay.revealAll()
        verify(overlay.currentPackRevealed)
        overlay.advanceOrFinish()
        tryVerify(() => !overlay.opened)
    }

    function test_skipLeavesResultsAvailableToTheParent() {
        overlay.showPacks(testPacks, "Test Booster")
        tryVerify(() => overlay.opened)
        overlay.close()
        tryVerify(() => !overlay.opened)
        compare(overlay.packs.length, 2)
    }
}
