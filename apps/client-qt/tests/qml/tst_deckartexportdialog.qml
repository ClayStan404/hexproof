// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic
import QtTest
import "../../qml/components"

TestCase {
    name: "DeckArtExportDialog"
    when: windowShown

    ApplicationWindow {
        id: window
        width: 900
        height: 620
        visible: true

        DeckArtExportDialog {
            id: dialog
            manager: artManager
        }
    }

    QtObject {
        id: artManager
        property bool busy: false
        property int exportCalls: 0
        property string savedUrl: ""
        property var savedRequests: []
        signal deckExportFinished(var result)
        function suggestedDeckExportUrl(name) {
            return "file:///tmp/cube.hexproof-artpack"
        }
        function exportDeckPack(url, requests) {
            ++exportCalls
            savedUrl = String(url)
            savedRequests = requests
            busy = true
        }
    }

    function cards() {
        return [{name: "Archangel Avacyn // Avacyn, the Purifier", setCode: "SOI",
                 collectorNumber: "5", count: 2},
                {name: "Angel", setCode: "TM21", collectorNumber: "1", token: true},
                {name: "Teferi, Hero of Dominaria Emblem", kind: "emblem", token: true}]
    }

    function init() {
        artManager.busy = false
        artManager.exportCalls = 0
        artManager.savedRequests = []
        artManager.savedUrl = ""
        dialog.exporting = false
        dialog.manager = artManager
        dialog.close()
        window.width = 900
        window.height = 620
        Theme.uiScale = 1
    }

    function cleanup() {
        dialog.exporting = false
        dialog.close()
        Theme.uiScale = 1
    }

    function openForDeck(name, requests) {
        verify(dialog.prepare(name, requests))
        tryVerify(() => dialog.opened)
        waitForPolish(window)
    }

    function acceptFile(url) {
        const fileDialog = findChild(dialog, "deckArtExportFileDialog")
        verify(fileDialog !== null)
        compare(fileDialog.defaultSuffix, "hexproof-artpack")
        fileDialog.selectedFile = url
        fileDialog.accepted()
    }

    function complete(result) {
        artManager.busy = false
        artManager.deckExportFinished(result)
        waitForPolish(window)
    }

    function result(url) {
        return {ok: true, fileUrl: url, imageCount: 4, entryCount: 6,
                requestedPrintingCount: 3, requestedFaceCount: 4,
                missingPrintingCount: 0, missingFaceCount: 0,
                skippedEntryCount: 0, faceCoverageVerified: true, bytes: 3145728}
    }

    function test_fileAcceptanceUsesImmutableDeckSnapshot() {
        const requests = cards()
        openForDeck("My Cube", requests)
        requests[0].name = "Changed after opening"
        requests.push({name: "Unrelated new card"})
        acceptFile("file:///tmp/cube.hexproof-artpack")
        compare(artManager.exportCalls, 1)
        compare(artManager.savedRequests.length, 3)
        compare(artManager.savedRequests[0].name,
                "Archangel Avacyn // Avacyn, the Purifier")
        compare(artManager.savedRequests[1].token, true)
        compare(artManager.savedRequests[2].kind, "emblem")
        compare(dialog.deckName, "My Cube")
        verify(dialog.exporting)
        verify(!dialog.prepare("Other deck", []))
        compare(dialog.deckName, "My Cube")
        verify(!findChild(dialog, "saveDeckArtPackButton").enabled)
        verify(!findChild(dialog, "closeDeckArtExportButton").enabled)

        complete(result(artManager.savedUrl))
        verify(!dialog.exporting)
        verify(dialog.opened, "Keep the result visible for sharing")
        verify(findChild(dialog, "saveDeckArtPackButton").enabled)
        const report = findChild(dialog, "deckArtExportResult")
        verify(report.visible)
        compare(report.tone, "success")
        verify(report.message.indexOf("4 image(s)") >= 0)
        verify(report.message.indexOf("Image data: 3.00 MiB") >= 0)
    }

    function test_partialPackReportsMissingInvalidAndUnverifiedFaces() {
        openForDeck("Partial Cube", cards())
        acceptFile("file:///tmp/partial.hexproof-artpack")
        const partial = result(artManager.savedUrl)
        partial.missingPrintingCount = 1
        partial.missingFaceCount = 2
        partial.skippedEntryCount = 3
        partial.faceCoverageVerified = false
        complete(partial)
        const report = findChild(dialog, "deckArtExportResult")
        compare(report.tone, "warning")
        verify(report.message.indexOf("1 printing(s), 2 card face(s)") >= 0)
        verify(report.message.indexOf("Skipped 3") >= 0)
        verify(report.message.indexOf("could not verify every card face") >= 0)
        verify(dialog.opened)
    }

    function test_completionMatchesEncodedChineseDestinationAndIgnoresOtherExport() {
        openForDeck("中文 Cube", cards())
        acceptFile("file:///tmp/%E5%A5%97%E7%89%8C%20cards.hexproof-artpack")
        artManager.deckExportFinished(result("file:///tmp/another.hexproof-artpack"))
        verify(dialog.exporting)
        complete(result("file:///tmp/套牌 cards.hexproof-artpack"))
        verify(!dialog.exporting)
        verify(dialog.exportResult.ok)
    }

    function test_failureIsPersistentAndCanRetry() {
        openForDeck("Cube", cards())
        acceptFile("file:///tmp/full.hexproof-artpack")
        complete({ok: false, fileUrl: artManager.savedUrl, error: "Destination is not writable."})
        verify(!dialog.exporting)
        verify(dialog.opened)
        compare(dialog.errorMessage, "Destination is not writable.")
        verify(findChild(dialog, "deckArtExportError").visible)
        verify(findChild(dialog, "saveDeckArtPackButton").enabled)
        verify(!findChild(dialog, "deckArtExportResult").visible)
        acceptFile("file:///tmp/retry.hexproof-artpack")
        compare(artManager.exportCalls, 2)
        compare(dialog.errorMessage, "")
        verify(dialog.exporting)
    }

    function test_emptyOrBusySelectionDoesNotExportWholeCache() {
        openForDeck("Deleted deck", [])
        verify(!findChild(dialog, "saveDeckArtPackButton").enabled)
        acceptFile("file:///tmp/empty.hexproof-artpack")
        compare(artManager.exportCalls, 0)
        verify(dialog.errorMessage.length > 0)

        openForDeck("Cube", cards())
        artManager.busy = true
        verify(!findChild(dialog, "saveDeckArtPackButton").enabled)
        acceptFile("file:///tmp/busy.hexproof-artpack")
        compare(artManager.exportCalls, 0)
        verify(!dialog.exporting)
        verify(dialog.errorMessage.indexOf("Another card-art operation") >= 0)
        artManager.busy = false
        acceptFile("file:///tmp/ready.hexproof-artpack")
        compare(artManager.exportCalls, 1)
    }

    function test_largeCubeAndScaledControlsRemainUsable_data() {
        return [{tag: "normal", scale: 1}, {tag: "maximum", scale: 1.8}]
    }

    function test_largeCubeAndScaledControlsRemainUsable(data) {
        Theme.uiScale = data.scale
        window.height = 420
        const cube = []
        for (let index = 0; index < 2000; ++index)
            cube.push({name: "Cube card " + index, count: 1})
        openForDeck("A very long Cube name ".repeat(12), cube)
        for (const name of ["saveDeckArtPackButton", "closeDeckArtExportButton"]) {
            const button = findChild(dialog, name)
            const point = button.mapToItem(window.contentItem, 0, 0)
            verify(point.x >= 0 && point.y >= 0)
            verify(point.x + button.width <= window.width)
            verify(point.y + button.height <= window.height)
        }
        const body = findChild(dialog, "deckArtExportBody")
        verify(body.height > 0)
        if (data.scale > 1)
            verify(body.contentHeight > body.height)
        if (body.contentHeight > body.height) {
            const priorY = body.contentY
            mouseWheel(body, body.width / 2, body.height / 2, 0, -120)
            tryVerify(() => body.contentY > priorY)
        }
        acceptFile("file:///tmp/large-cube.hexproof-artpack")
        compare(artManager.savedRequests.length, 2000)
        waitForPolish(window)
        const progress = findChild(dialog, "deckArtExportProgress")
        verify(progress.visible)
        verify(progress.indeterminate)
        const progressPoint = progress.mapToItem(window.contentItem, 0, 0)
        verify(progressPoint.y >= 0 && progressPoint.y + progress.height <= window.height)
        body.contentY = Math.max(0, body.contentHeight - body.height)
        complete(result(artManager.savedUrl))
        compare(body.contentY, 0)
        const report = findChild(dialog, "deckArtExportResult")
        const reportPoint = report.mapToItem(body, 0, 0)
        verify(reportPoint.y >= 0 && reportPoint.y < body.height)
    }
}
