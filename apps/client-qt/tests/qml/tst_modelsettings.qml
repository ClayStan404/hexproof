// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic
import QtTest
import "../../qml/screens"
import "../../qml/components"

TestCase {
    name: "ModelSettings"
    when: windowShown

    ApplicationWindow {
        id: window
        width: 1280
        height: 900
        visible: true
        function popScreen() {}
    }
    QtObject {
        id: connection
        property bool active: false
        property bool busy: false
        property string testStatus: "untested"
        property string lastError: ""
        property var saved: ({})
        property string testedSource: ""
        property var configurations: ({
            local: {endpoint:"http://localhost:11434/v1",model:"local-test",timeoutSeconds:60,maxCalls:200,maxOutputTokens:1024,maxTokenBudget:500000,tokenParameter:"max_tokens",hasKey:false},
            online: {endpoint:"https://models.example/v1",model:"remote-test",timeoutSeconds:90,maxCalls:100,maxOutputTokens:2048,maxTokenBudget:300000,tokenParameter:"max_completion_tokens",hasKey:true}
        })
        function profile(source) { return configurations[source] }
        function saveProfile(source, config, key) {
            saved = {source, config, key}
            configurations[source] = Object.assign({}, config, {hasKey:key.length > 0})
            return true
        }
        function testProfile(source) { testedSource = source; testStatus = "passed" }
        function stop() { active = false }
    }
    Component { id: pageComponent; ModelSettings { service: connection } }
    property var page: null

    function init() {
        testTranslations.setLanguage("en")
        connection.active = false
        connection.busy = false
        connection.testStatus = "untested"
        connection.saved = ({})
        connection.testedSource = ""
        page = pageComponent.createObject(window.contentItem)
        verify(page !== null)
        page.anchors.fill = window.contentItem
        waitForRendering(page)
    }
    function cleanup() {
        page.destroy()
        page = null
        testTranslations.setLanguage("en")
    }
    function test_profilesStaySeparateAndKeysAreClearedAfterSave() {
        compare(findChild(page, "modelIdentifier").text, "local-test")
        findChild(page, "modelProfileSource").activated(1)
        compare(page.source, "online")
        compare(findChild(page, "modelEndpoint").text, "https://models.example/v1")
        compare(findChild(page, "modelApiKey").text, "")
        compare(findChild(page, "modelApiKey").echoMode, TextInput.Password)
        findChild(page, "modelApiKey").text = "session-only-test-key"
        findChild(page, "modelSave").clicked()
        compare(connection.saved.source, "online")
        compare(connection.saved.config.timeoutSeconds, 90)
        compare(connection.saved.config.maxCalls, 100)
        compare(connection.saved.config.tokenParameter, "max_completion_tokens")
        compare(connection.saved.key, "session-only-test-key")
        compare(findChild(page, "modelApiKey").text, "")
        verify(page.hasKey)
        verify(findChild(page, "modelSettingsFeedback").text.length > 0)
    }
    function test_connectionTestUsesSavedProfileAndLocalizesResult() {
        findChild(page, "modelEndpoint").text = "http://unsaved.example/v1"
        findChild(page, "modelTest").clicked()
        compare(connection.testedSource, "local")
        compare(Object.keys(connection.saved).length, 0)
        compare(findChild(page, "modelTestFeedback").text,
                "Connection test passed. The model returned a valid structured choice.")
        testTranslations.setLanguage("zh")
        tryCompare(findChild(page, "modelTest"), "text", "测试已保存的连接")
        verify(findChild(page, "modelTestFeedback").text.includes("测试通过"))
        connection.active = true
        verify(!findChild(page, "modelSave").enabled)
        verify(!findChild(page, "modelTest").enabled)
        verify(findChild(page, "modelDisconnect").visible)
        findChild(page, "modelDisconnect").clicked()
        verify(!connection.active)
        verify(findChild(page, "modelSave").enabled)
    }
}
