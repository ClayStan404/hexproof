// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic
import QtTest
import "../../qml/components"

TestCase {
    name: "DeckPicker"
    when: windowShown

    ApplicationWindow {
        width: 900
        height: 700
        visible: true

        DeckPicker {
            id: picker
            requiredFormat: "modern"
            decks: [{
                "deckId": "ready-deck",
                "deckName": "Burn",
                "mainCount": 60,
                "sideboardCount": 15,
                "ready": true,
                "artReady": true,
                "status": "Playable"
            }, {
                "deckId": "incomplete-deck",
                "deckName": "Work in progress",
                "mainCount": 20,
                "sideboardCount": 0,
                "ready": false,
                "artReady": false,
                "status": "3 images missing"
            }]
        }
    }

    SignalSpy {
        id: selectedSpy
        target: picker
        signalName: "selected"
    }

    SignalSpy {
        id: openLibrarySpy
        target: picker
        signalName: "openDeckLibraryRequested"
    }

    function init() {
        picker.close()
        picker.decks = [{
            "deckId": "ready-deck",
            "deckName": "Burn",
            "mainCount": 60,
            "sideboardCount": 15,
            "ready": true,
            "artReady": true,
            "status": "Playable"
        }, {
            "deckId": "incomplete-deck",
            "deckName": "Work in progress",
            "mainCount": 20,
            "sideboardCount": 0,
            "ready": false,
            "artReady": false,
            "status": "3 images missing"
        }]
        selectedSpy.clear()
        openLibrarySpy.clear()
    }

    function cleanup() {
        picker.close()
    }

    function test_onlyReadyDeckCanBeSelected() {
        picker.open()
        tryVerify(() => picker.opened)

        const list = findChild(picker, "matchDeckOptions")
        verify(list !== null)
        compare(list.count, 2)
        tryVerify(() => list.itemAtIndex(0) !== null)
        const readyButton = findChild(list.itemAtIndex(0), "selectMatchDeckButton")
        verify(readyButton !== null)
        verify(readyButton.enabled)
        const availability = findChild(list.itemAtIndex(0), "deckAvailabilityStatus")
        verify(availability !== null)
        compare(availability.text, "Playable")

        tryVerify(() => list.itemAtIndex(1) !== null)
        const incompleteButton = findChild(list.itemAtIndex(1), "selectMatchDeckButton")
        verify(incompleteButton !== null)
        verify(!incompleteButton.enabled)

        mouseClick(readyButton, readyButton.width / 2, readyButton.height / 2)
        compare(selectedSpy.count, 1)
        compare(selectedSpy.signalArguments[0][0], "ready-deck")
        compare(selectedSpy.signalArguments[0][1], "Burn")
    }

    function test_emptyStateCanOpenDeckLibrary() {
        picker.decks = []
        picker.open()
        tryVerify(() => picker.opened)
        const button = findChild(picker, "openDeckLibraryButton")
        verify(button !== null)
        mouseClick(button)
        compare(openLibrarySpy.count, 1)
        verify(!picker.opened)
    }
}
