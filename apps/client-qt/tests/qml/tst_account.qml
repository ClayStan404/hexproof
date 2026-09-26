// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors
import QtQuick
import QtQuick.Controls.Basic
import QtTest
import "../../qml/screens"

TestCase {
    name: "Account"
    when: windowShown
    ApplicationWindow {
        id: host
        width: 1280
        height: 900
        visible: true
        function popScreen() { }
    }
    QtObject {
        id: service
        property bool supported: true
        property bool authenticated: false
        property bool busy: false
        property bool vaultAvailable: true
        property string accountId: "public-test-id"
        property string displayName: "Alice"
        property string loginCode: ""
        property string recoveryCode: ""
        property string lastError: ""
        property var devices: []
        property var resources: []
        property int pendingClaims: 0
        property string submitted: ""
        function refresh() { }
        function login(value) { submitted = value }
        function acknowledgeBackup() { loginCode = ""; recoveryCode = "" }
    }
    QtObject { id: client; property bool connected: true; property var account: service }
    Component { id: screen; Account { wsModel: client } }
    property var page: null
    function init() {
        service.authenticated = false; service.busy = false
        service.loginCode = ""; service.recoveryCode = ""; service.submitted = ""
        page = screen.createObject(host.contentItem)
        verify(page)
        page.anchors.fill = host.contentItem
        waitForRendering(page)
    }
    function cleanup() { page.destroy(); page = null }
    function test_loginIsMaskedAndInputCleared() {
        const input = findChild(page, "accountEntry")
        compare(input.echoMode, TextInput.Password)
        input.text = "private-login"
        mouseClick(findChild(page, "accountSubmit"))
        compare(service.submitted, "private-login")
        compare(input.text, "")
        service.busy = true
        verify(!findChild(page, "accountSubmit").enabled)
    }
    function test_generatedSecretsAreMaskedAndDiscardedAfterBackup() {
        service.authenticated = true
        service.loginCode = "generated-login"
        service.recoveryCode = "generated-recovery"
        waitForRendering(page)
        const login = findChild(page, "accountGeneratedLoginCode")
        const recovery = findChild(page, "accountGeneratedRecoveryCode")
        compare(login.echoMode, TextInput.Password)
        compare(recovery.echoMode, TextInput.Password)
        mouseClick(findChild(page, "accountBackupAcknowledged"))
        compare(service.loginCode, "")
        compare(service.recoveryCode, "")
        verify(!login.visible)
    }
}
