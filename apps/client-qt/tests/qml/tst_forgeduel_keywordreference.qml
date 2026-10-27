// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtTest

ForgeDuelTestCase {
    name: "ForgeKeywordReference"

    function test_referenceEntryIsolatesForgeInput() {
        closeSettings()
        openSettings()
        const button = item("rulesKeywordReferenceButton")
        verify(button !== null)
        mouseClick(button)
        const popup = table.keywordReference
        tryCompare(popup, "opened", true)
        verify(table.priorityInputBlocked)
        verify(table.presentation.modalOpen)
        const search = findChild(popup.contentItem, "keywordSearch")
        tryCompare(search, "activeFocus", true)
        const responses = transport.responses.length
        const revision = testRulesPrompt.session.snapshotRevision
        for (const letter of "FLYING") keyClick(letter.charCodeAt(0))
        keyClick(Qt.Key_Space)
        keyClick(Qt.Key_Return)
        keyClick(Qt.Key_F6)
        compare(transport.responses.length, responses)
        compare(testRulesPrompt.session.snapshotRevision, revision)
        verify(!table.priority.passOnce())
        keyClick(Qt.Key_Escape)
        tryCompare(popup, "visible", false)
        tryCompare(item("forgeGameDrawer"), "visible", false)
        verify(!table.priorityInputBlocked)
        tryCompare(table, "activeFocus", true)
        compare(transport.responses.length, responses)
    }
}
