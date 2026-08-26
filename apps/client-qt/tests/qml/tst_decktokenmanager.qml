// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic
import QtTest
import "../../qml/components"

TestCase {
    id: testCase
    name: "DeckTokenManager"
    when: windowShown

    readonly property string testImage:
        "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwC"
        + "AAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="

    QtObject {
        id: fakeDeckLibrary
        property var currentTokens: [{
            "name": "Goblin",
            "displayName": "地精",
            "typeLine": "Token Creature — Goblin",
            "setCode": "TNEO",
            "collectorNumber": "12",
            "power": "1",
            "toughness": "1",
            "oracleText": "Haste"
        }]
        function removeToken() {}
    }

    QtObject {
        id: fakeCatalog
        property bool tokenCatalogInstalled: true
        property int imageRevision: -1
        function tokenImageSource() { return testCase.testImage }
    }

    ApplicationWindow {
        id: testWindow
        width: 1100
        height: 760
        visible: true

        DeckTokenManager {
            id: manager
            deckLibraryModel: fakeDeckLibrary
            catalogModel: fakeCatalog
        }
    }

    function init() {
        fakeCatalog.imageRevision = -1
        manager.close()
    }

    function cleanup() {
        manager.close()
    }

    function test_refreshesImageAfterCacheRevisionChanges() {
        manager.open()
        tryVerify(() => manager.opened)
        const grid = findChild(manager, "managedDeckTokenGrid")
        verify(grid !== null)
        tryCompare(grid, "count", 1)
        tryVerify(() => grid.itemAtIndex(0) !== null)
        const image = findChild(grid.itemAtIndex(0),
                                "managedDeckTokenImage")
        verify(image !== null)
        const details = findChild(grid.itemAtIndex(0),
                                  "managedDeckTokenDetails")
        verify(details !== null)
        compare(details.text, "1/1 · Haste")
        compare(image.source, "")

        fakeCatalog.imageRevision = 0
        tryCompare(image, "status", Image.Ready)
        verify(String(image.source).startsWith("data:image/png"))
    }
}
