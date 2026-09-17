// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic
import QtTest
import "../../qml/components"

TestCase {
    name: "ForgeHostingDialog"
    when: windowShown
    ApplicationWindow { id: testWindow; width: 1000; height: 1000; visible: true }
    QtObject {
        id: host
        property bool ready: true
        property bool busy: false
        property bool hosting: false
        property real progress: 0
        property string status: "Runtime ready"
        property string downloadMirror: ""
        property int preparations: 0
        property int cancellations: 0
        property int cleanups: 0
        property string importedPack: ""
        function prepare() { preparations++; busy = true }
        function importPack(source) { importedPack = source.toString(); busy = true }
        function cancel() { cancellations++; busy = false }
        function clearCache() { cleanups++ }
        function saveDownloadMirror(value) { downloadMirror = value; return true }
    }
    Component { id: component; ForgeHostingDialog { service: host } }
    property var dialog
    function init() {
        host.busy = false; host.hosting = false
        host.preparations = 0; host.cancellations = 0; host.cleanups = 0
        host.importedPack = ""
        dialog = component.createObject(testWindow.contentItem)
        dialog.open()
        tryCompare(dialog, "opened", true)
    }
    function cleanup() { dialog.close(); dialog.destroy() }
    function test_prepareCancelAndActiveHostGuards() {
        const prepare = findChild(dialog, "forgeRuntimePrepare")
        const cleanup = findChild(dialog, "forgeClearCache")
        const importer = findChild(dialog, "forgeRuntimeImport")
        verify(importer.enabled)
        mouseClick(prepare)
        compare(host.preparations, 1)
        verify(!cleanup.enabled)
        verify(!importer.enabled)
        verify(!findChild(dialog, "forgeDownloadMirror").enabled)
        mouseClick(prepare)
        compare(host.cancellations, 1)
        verify(cleanup.enabled)
        verify(importer.enabled)
        host.busy = true; host.hosting = true
        verify(!prepare.enabled)
        verify(!cleanup.enabled)
        verify(!importer.enabled)
        verify(findChild(dialog, "forgeExportDiagnostics").enabled)
    }
    function test_importSelectionAndCancellation() {
        const picker = findChild(dialog, "forgeImportFileDialog")
        verify(picker)
        picker.rejected()
        compare(host.importedPack, "")
        // An existing file exercises URL forwarding without opening a native picker.
        picker.selectedFile = Qt.resolvedUrl("tst_forgehostingdialog.qml")
        picker.accepted()
        verify(host.importedPack.length > 0)
        compare(host.importedPack, picker.selectedFile.toString())
        verify(host.busy)
        verify(!findChild(dialog, "forgeRuntimeImport").enabled)
        mouseClick(findChild(dialog, "forgeRuntimePrepare"))
        compare(host.cancellations, 1)
        verify(findChild(dialog, "forgeRuntimeImport").enabled)
    }
}
