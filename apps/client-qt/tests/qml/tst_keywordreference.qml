// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic
import QtTest
import "../../qml/components"

TestCase {
    id: testCase
    name: "KeywordReference"
    when: windowShown
    ApplicationWindow {
        id: window
        width: 1000; height: 850; visible: true
        AppButton {
            id: opener
            property int clicks: 0
            text: "Open"
            onClicked: { ++clicks; popup.showFor(opener) }
        }
        KeywordReferencePopup { id: popup }
    }
    readonly property var search: findChild(popup.contentItem, "keywordSearch")
    readonly property var results: findChild(popup.contentItem, "keywordResults")

    function init() {
        window.requestActivate()
        mouseClick(opener)
        tryCompare(popup, "opened", true)
        tryCompare(search, "activeFocus", true)
    }
    function cleanup() { popup.close() }

    function test_nativeScenarioCompiles() {
        const scenario = Qt.createComponent("../../../../tools/ui-automation/scenarios/KeywordReference.qml")
        compare(scenario.status, Component.Ready, scenario.errorString())
    }

    function test_searchEnglishChineseAndLessCommonTerms_data() {
        return [{tag:"case", query:"  FlYiNg  ", english:"Flying"},
                {tag:"chinese", query:"飞行", english:"Flying"},
                {tag:"traditional-chinese", query:"飛行", english:"Flying"},
                {tag:"old-ability", query:"phasing", english:"Phasing"},
                {tag:"rare-action", query:"planeswalk", english:"Planeswalk"},
                {tag:"symbol", query:"∞", english:"∞ (Infinity)"}]
    }
    function test_searchEnglishChineseAndLessCommonTerms(data) {
        search.text = data.query
        verify(popup.filteredEntries.some(entry => entry.english === data.english))
        verify(popup.filteredEntries.every(entry => entry.summaryEn.length > 20
                                               && entry.summaryZh.length > 8))
    }
    function test_emptyResultsResetAndReopen() {
        search.text = "<b>no such keyword</b>"
        compare(popup.filteredEntries.length, 0)
        verify(findChild(popup.contentItem, "keywordNoResults").visible)
        mouseClick(findChild(popup.contentItem, "resetKeywordSearch"))
        compare(search.text, "")
        compare(popup.filteredEntries.length, 264)
        search.text = "flying"
        keyClick(Qt.Key_Escape)
        tryCompare(popup, "visible", false)
        tryCompare(opener, "activeFocus", true)
        mouseClick(opener)
        tryCompare(popup, "opened", true)
        compare(search.text, "")
        compare(popup.filteredEntries.length, 264)
    }
    function test_modalBlocksPointerOutsideAndKeysAfterSearchLosesFocus() {
        const clicks = opener.clicks
        mouseClick(opener)
        compare(opener.clicks, clicks)
        verify(popup.visible)
        // The reset button takes focus from the editor without leaving the modal.
        const reset = findChild(popup.contentItem, "resetKeywordSearch")
        reset.forceActiveFocus()
        keyClick(Qt.Key_Space)
        verify(popup.visible)
        keyClick(Qt.Key_Escape)
        tryCompare(popup, "visible", false)
        tryCompare(opener, "activeFocus", true)
    }

    function test_browseScrollAndLongExplanationWrap() {
        verify(waitForRendering(results))
        verify(results.contentHeight > results.height)
        results.positionViewAtEnd()
        tryVerify(() => results.contentY > 0)
        search.text = "banding"
        tryVerify(() => results.count > 0 && results.itemAtIndex(0) !== null)
        const row = results.itemAtIndex(0)
        const explanation = findChild(row, "keywordExplanation")
        verify(explanation !== null)
        compare(explanation.textFormat, Text.PlainText)
        compare(explanation.wrapMode, Text.WordWrap)
        verify(explanation.height > explanation.font.pixelSize)
        mouseClick(findChild(popup.contentItem, "closeKeywordReference"))
        tryCompare(popup, "visible", false)
        tryCompare(opener, "activeFocus", true)
    }
}
