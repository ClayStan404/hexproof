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
        wait(1)
    }

    function test_revealsRaresLastAndAdvancesBetweenPacks() {
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
        tryVerify(() => cardGrid.itemAtIndex(3) !== null)
        const mythicCard = cardGrid.itemAtIndex(3)
        mouseClick(mythicCard, mythicCard.width / 2,
                   cardGrid.cardHeight / 2)
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
