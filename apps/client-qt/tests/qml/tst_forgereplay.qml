// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic
import QtTest
import "../../qml/screens"

TestCase {
    id: testCase
    name: "ForgeReplay"
    when: windowShown
    readonly property string firstReplay: "a".repeat(64)
    readonly property string secondReplay: "c".repeat(64)
    property var gameTable: testGameTable
    property var sideboardTable: testSideboardTable
    QtObject {
        id: ws
        property var roomSession: ({hostingMode:"server", seatIndex:-1})
        property var forgeHost: null
        property string lastError: ""
        property bool inRoom: false
    }
    QtObject {
        id: cardCatalog
        property string language: "en"
        property int imageRevision: 0
        signal catalogChanged()
        function cacheCardsIncrementally(cards) {}
        function cardDisplayName(name) { return name }
        function cardRulesText(name, set, number, language) { return "" }
        function cardTypeLine(name) { return "" }
    }
    ApplicationWindow {
        id: window
        width: 1600
        height: 1000
        visible: true
        property bool feedbackInteractionOpen: false
        function popScreen() { player.sourceComponent = null }
        Loader { id: player; anchors.fill: parent }
    }
    Component { id: playerComponent; ForgeReplay { service: testReplays } }
    function speedMenu() {
        const menu = findChild(player.item, "forgeReplaySpeed")
        verify(menu)
        return menu
    }
    function openReplay(id) {
        verify(testReplays.open(id))
        player.sourceComponent = playerComponent
        tryVerify(() => !!player.item)
        waitForRendering(player.item)
    }
    function chooseSpeed(index) {
        const menu = speedMenu()
        mouseClick(menu, menu.width / 2, menu.height / 2)
        tryCompare(menu.popup, "opened", true)
        const option = menu.popup.contentItem.itemAtIndex(index)
        verify(option)
        mouseClick(option, option.width / 2, option.height / 2)
        tryCompare(menu, "currentIndex", index)
    }
    function init() { testReplays.speed = 1 }
    function cleanup() { player.sourceComponent = null; testReplays.pause(); wait(0) }
    function test_speedReflectsSharedServiceAfterReopening_data() {
        return [{tag:"same recording", replayId:firstReplay}, {tag:"another recording", replayId:secondReplay}]
    }
    function test_speedReflectsSharedServiceAfterReopening(data) {
        openReplay(firstReplay)
        compare(speedMenu().currentText, "1×")
        chooseSpeed(4)
        compare(testReplays.speed, 8)
        const back = findChild(player.item, "forgeReplayBack")
        mouseClick(back, back.width / 2, back.height / 2)
        tryVerify(() => !player.item)
        compare(testReplays.playing, false)
        openReplay(data.replayId)
        compare(testReplays.speed, 8)
        compare(speedMenu().currentText, "8×")
        chooseSpeed(2)
        compare(testReplays.speed, 2)
        compare(speedMenu().currentText, "2×")
        testReplays.speed = 4
        compare(speedMenu().currentText, "4×")
    }
}
