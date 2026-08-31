// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic
import QtTest
import "../../qml/components"

TestCase {
    id: testCase
    name: "DeckMainCollection"
    when: windowShown

    QtObject {
        id: fakeDeckLibrary
        signal currentDeckCardsAboutToChange()
        signal currentDeckCardsChanged()
        function canAddCard() { return true }
        function moveCard() {}
        function moveCardToConsider() {}
        function changeCardCount() {}
        function setCommander() {}
    }

    QtObject {
        id: fakeCatalog
        property bool installed: true
        property int imageRevision: -1
        function imageSource() { return "" }
    }

    ApplicationWindow {
        width: 1100
        height: 720
        visible: true

        DeckMainCollection {
            id: collection
            anchors.fill: parent
            anchors.margins: 20
            deckLibraryModel: fakeDeckLibrary
            catalogModel: fakeCatalog
            cards: [
                {"name": "Wild Nacatl", "displayName": "Wild Nacatl",
                 "category": "Creatures", "typeLine": "Creature — Cat Warrior",
                 "count": 4, "manaValue": 1, "setCode": "ALA",
                 "collectorNumber": "152", "commander": false},
                {"name": "Scion of Draco", "displayName": "Scion of Draco",
                 "category": "Creatures", "typeLine": "Artifact Creature — Dragon",
                 "count": 2, "manaValue": 12, "setCode": "MH2",
                 "collectorNumber": "234", "commander": false},
                {"name": "Lightning Bolt", "displayName": "Lightning Bolt",
                 "category": "Spells", "typeLine": "Instant",
                 "count": 4, "manaValue": 1, "setCode": "M11",
                 "collectorNumber": "149", "commander": false}
            ]
        }
    }

    function init() {
        collection.viewModeIndex = 0
        collection.groupModeIndex = 0
        collection.sortModeIndex = 0
    }

    function test_typeGroupsShowCopyCounts() {
        compare(collection.groups.length, 2)
        compare(collection.groups[0].key, "Creatures")
        compare(collection.groups[0].label, "Creatures (6)")
        compare(collection.groups[1].key, "Instants")
        compare(collection.groups[1].label, "Instants (4)")
    }

    function test_manaGroupingAndSorting() {
        collection.groupModeIndex = 1
        collection.sortModeIndex = 1
        compare(collection.groups.length, 2)
        compare(collection.groups[0].key, "mana-1")
        compare(collection.groups[0].cards.length, 2)
        compare(collection.groups[1].key, "mana-7+")
        compare(collection.groups[1].cards[0].name, "Scion of Draco")
    }

    function test_visualModeIsAvailable() {
        collection.viewModeIndex = 1
        compare(collection.viewModeIndex, 1)
    }
}
