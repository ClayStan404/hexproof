// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic
import QtTest
import "../../qml/components"

TestCase {
    name: "TournamentScoreEditor"
    when: windowShown

    ApplicationWindow {
        id: testWindow
        width: 900
        height: 700
        visible: true

        QtObject {
            id: mockWs
            property string lastPairingId: ""
            property int lastA: -1
            property int lastB: -1
            property int lastDraw: -1
            function reportTournamentResult(pairingId, playerAWins, playerBWins, drawnGames) {
                lastPairingId = pairingId
                lastA = playerAWins
                lastB = playerBWins
                lastDraw = drawnGames
            }
            function correctTournamentResult(pairingId, playerAWins, playerBWins, drawnGames) {
                reportTournamentResult(pairingId, playerAWins, playerBWins, drawnGames)
            }
        }

        TournamentScoreEditor {
            id: editor
            wsModel: mockWs
        }
    }

    function cleanup() {
        editor.close()
        mockWs.lastPairingId = ""
        mockWs.lastA = -1
        mockWs.lastB = -1
        mockWs.lastDraw = -1
    }

    function test_prefillsOpenPairingFromTabletopScore() {
        editor.openFor({
            "pairingId": "r1-m1",
            "playerAName": "Alice",
            "playerBName": "Bob",
            "status": "open",
            "playerAWins": 0,
            "playerBWins": 0,
            "drawnGames": 0
        }, false, {
            "roomId": "ROOM01",
            "seats": [
                {"displayName": "Bob", "wins": 1},
                {"displayName": "Alice", "wins": 2}
            ],
            "drawnGames": 0
        })
        tryVerify(() => editor.opened)
        const hint = findChild(editor, "scorePrefillHint")
        const playerA = findChild(editor, "playerAWinsField")
        const playerB = findChild(editor, "playerBWinsField")
        verify(hint !== null)
        verify(hint.visible)
        compare(playerA.text, "2")
        compare(playerB.text, "1")
    }

    function test_doesNotOverwriteReportedScores() {
        editor.openFor({
            "pairingId": "r1-m1",
            "playerAName": "Alice",
            "playerBName": "Bob",
            "status": "reported",
            "playerAWins": 2,
            "playerBWins": 0,
            "drawnGames": 0
        }, false, {
            "seats": [
                {"displayName": "Alice", "wins": 1},
                {"displayName": "Bob", "wins": 1}
            ]
        })
        tryVerify(() => editor.opened)
        const hint = findChild(editor, "scorePrefillHint")
        const playerA = findChild(editor, "playerAWinsField")
        const playerB = findChild(editor, "playerBWinsField")
        verify(!hint.visible)
        compare(playerA.text, "2")
        compare(playerB.text, "0")
    }
}
