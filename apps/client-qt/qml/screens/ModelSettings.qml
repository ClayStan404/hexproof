// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import "../components"

Page {
    id: root
    objectName: "modelSettingsScreen"
    property var service: typeof ws !== "undefined" ? ws.modelOpponent : null
    property string source: "local"
    property string savedMessage: ""
    property bool hasKey: false
    property bool profileReady: false
    background: AppBackground { }

    function loadProfile() {
        if (!service) return
        const profile = service.profile(source)
        endpoint.text = profile.endpoint || ""
        model.text = profile.model || ""
        timeout.text = String(profile.timeoutSeconds || 60)
        calls.text = String(profile.maxCalls || 200)
        output.text = String(profile.maxOutputTokens || 1024)
        tokens.text = String(profile.maxTokenBudget || 500000)
        parameter.currentIndex = profile.tokenParameter === "max_completion_tokens" ? 1 : 0
        hasKey = profile.hasKey === true
        key.clear()
        savedMessage = ""
    }
    function saveProfile() {
        if (!service || !timeout.acceptableInput || !calls.acceptableInput
                || !output.acceptableInput || !tokens.acceptableInput) return false
        const config = {endpoint: endpoint.text.trim(), model: model.text.trim(),
            timeoutSeconds: timeout.numberValue(), maxCalls: calls.numberValue(),
            maxOutputTokens: output.numberValue(), maxTokenBudget: tokens.numberValue(),
            tokenParameter: parameter.currentIndex === 1 ? "max_completion_tokens" : "max_tokens"}
        if (!service.saveProfile(source, config, key.text)) {
            savedMessage = qsTr("Check the endpoint, model, and thinking limits.")
            return false
        }
        hasKey = service.profile(source).hasKey === true
        key.clear()
        savedMessage = qsTr("Model connection saved. API keys are kept only until the application closes.")
        return true
    }
    Component.onCompleted: { profileReady = true; loadProfile() }
    onSourceChanged: if (profileReady) loadProfile()

    SettingsPage {
        anchors.fill: parent
        title: qsTr("Model opponents (experimental)")
        subtitle: qsTr("Connect an OpenAI-compatible Chat Completions service")

        SegmentedControl {
            objectName: "modelProfileSource"
            Layout.fillWidth: true
            options: [qsTr("Local model"), qsTr("Online model")]
            currentIndex: root.source === "online" ? 1 : 0
            onActivated: index => root.source = index === 1 ? "online" : "local"
        }
        Text {
            Layout.fillWidth: true
            textFormat: Text.PlainText
            text: qsTr("Experimental feature: model replies may fail and pause the game. Full-game reliability is not yet verified.")
            color: Theme.warning
            font.pixelSize: Theme.fontSize(13)
            wrapMode: Text.WordWrap
        }
        Text {
            Layout.fillWidth: true
            textFormat: Text.PlainText
            text: root.source === "online"
                  ? qsTr("Your chosen provider receives the AI's permitted game view, including its hand. Requests may incur provider charges. API keys stay on this computer.")
                  : qsTr("Run a compatible model service on your computer, then enter its API base URL and model name. A local address may still forward requests to a cloud provider.")
            color: root.source === "online" ? Theme.warning : Theme.textSecondary
            font.pixelSize: Theme.fontSize(13)
            wrapMode: Text.WordWrap
        }
        Text {
            Layout.fillWidth: true
            visible: root.service !== null && root.service.active
            textFormat: Text.PlainText
            text: qsTr("Disconnect the model opponent before editing its connection. The game will pause; after saving, return to the table and retry the model decision to authorize the selected connection.")
            color: Theme.warning
            font.pixelSize: Theme.fontSize(12)
            wrapMode: Text.WordWrap
        }
        AppButton {
            objectName: "modelDisconnect"
            Layout.fillWidth: true
            visible: root.service !== null && root.service.active
            text: qsTr("Disconnect model opponent")
            variant: "ghost"
            onClicked: root.service.stop()
        }
        Surface {
            Layout.fillWidth: true
            implicitHeight: fields.implicitHeight + Theme.size(40)
            ColumnLayout {
                id: fields
                anchors.fill: parent
                anchors.margins: Theme.size(20)
                spacing: Theme.size(10)

                Text { textFormat: Text.PlainText; text: qsTr("API base URL"); color: Theme.text; font.pixelSize: Theme.fontSize(13) }
                AppTextField {
                    id: endpoint
                    objectName: "modelEndpoint"
                    Layout.fillWidth: true
                    maximumLength: 2048
                    placeholderText: root.source === "local" ? "http://127.0.0.1:11434/v1" : "https://api.openai.com/v1"
                    inputMethodHints: Qt.ImhUrlCharactersOnly
                }
                Text { textFormat: Text.PlainText; text: qsTr("Model identifier"); color: Theme.text; font.pixelSize: Theme.fontSize(13) }
                AppTextField { id: model; objectName: "modelIdentifier"; Layout.fillWidth: true; maximumLength: 256 }
                Text {
                    Layout.fillWidth: true
                    textFormat: Text.PlainText
                    text: root.hasKey ? qsTr("API key · set for this session") : qsTr("API key · optional for anonymous services")
                    color: Theme.text
                    font.pixelSize: Theme.fontSize(13)
                    wrapMode: Text.WordWrap
                }
                AppTextField {
                    id: key
                    objectName: "modelApiKey"
                    Layout.fillWidth: true
                    echoMode: TextInput.Password
                    maximumLength: 4096
                    inputMethodHints: Qt.ImhHiddenText | Qt.ImhNoPredictiveText | Qt.ImhSensitiveData
                }
                Text {
                    Layout.fillWidth: true
                    textFormat: Text.PlainText
                    text: qsTr("Re-enter the key when saving changes. Saving an empty key removes it from this session.")
                    color: Theme.textMuted
                    font.pixelSize: Theme.fontSize(11)
                    wrapMode: Text.WordWrap
                }
                Text { textFormat: Text.PlainText; text: qsTr("Decision timeout (seconds)"); color: Theme.text; font.pixelSize: Theme.fontSize(13) }
                AppTextField {
                    id: timeout
                    objectName: "modelTimeout"
                    Layout.fillWidth: true
                    validator: IntValidator { bottom: 5; top: 300 }
                    inputMethodHints: Qt.ImhDigitsOnly
                }
                Text { textFormat: Text.PlainText; text: qsTr("Maximum requests per game"); color: Theme.text; font.pixelSize: Theme.fontSize(13) }
                AppTextField {
                    id: calls
                    objectName: "modelMaxCalls"
                    Layout.fillWidth: true
                    validator: IntValidator { bottom: 1; top: 2000 }
                    inputMethodHints: Qt.ImhDigitsOnly
                }
                Text { textFormat: Text.PlainText; text: qsTr("Maximum output tokens per request"); color: Theme.text; font.pixelSize: Theme.fontSize(13) }
                AppTextField {
                    id: output
                    objectName: "modelMaxOutput"
                    Layout.fillWidth: true
                    validator: IntValidator { bottom: 128; top: 8192 }
                    inputMethodHints: Qt.ImhDigitsOnly
                }
                Text { textFormat: Text.PlainText; text: qsTr("Conservative token budget per game"); color: Theme.text; font.pixelSize: Theme.fontSize(13) }
                AppTextField {
                    id: tokens
                    objectName: "modelTokenBudget"
                    Layout.fillWidth: true
                    validator: IntValidator { bottom: 1024; top: 10000000 }
                    inputMethodHints: Qt.ImhDigitsOnly
                }
                Text {
                    Layout.fillWidth: true
                    textFormat: Text.PlainText
                    text: qsTr("Requests reserve estimated input plus the output allowance. This is a usage limit, not a guaranteed price cap. Model strength is uncalibrated.")
                    color: Theme.textSecondary
                    font.pixelSize: Theme.fontSize(11)
                    wrapMode: Text.WordWrap
                }
                Text { textFormat: Text.PlainText; text: qsTr("Output limit parameter"); color: Theme.text; font.pixelSize: Theme.fontSize(13) }
                AppComboBox {
                    id: parameter
                    objectName: "modelTokenParameter"
                    Layout.fillWidth: true
                    model: ["max_tokens", "max_completion_tokens"]
                }
                Text {
                    Layout.fillWidth: true
                    textFormat: Text.PlainText
                    text: qsTr("Use the parameter supported by your endpoint. Connection tests use synthetic choices and send no game data.")
                    color: Theme.textMuted
                    font.pixelSize: Theme.fontSize(11)
                    wrapMode: Text.WordWrap
                }
                AppButton {
                    objectName: "modelSave"
                    Layout.fillWidth: true
                    text: qsTr("Save connection")
                    enabled: root.service !== null && !root.service.active
                    onClicked: root.saveProfile()
                }
                AppButton {
                    objectName: "modelTest"
                    Layout.fillWidth: true
                    variant: "ghost"
                    text: root.service && root.service.busy ? qsTr("Testing…") : qsTr("Test saved connection")
                    enabled: root.service !== null && !root.service.busy && !root.service.active
                    onClicked: root.service.testProfile(root.source)
                }
                Text {
                    objectName: "modelSettingsFeedback"
                    Layout.fillWidth: true
                    textFormat: Text.PlainText
                    text: root.savedMessage
                    color: Theme.textSecondary
                    font.pixelSize: Theme.fontSize(12)
                    wrapMode: Text.WordWrap
                }
                Text {
                    objectName: "modelTestFeedback"
                    Layout.fillWidth: true
                    textFormat: Text.PlainText
                    text: root.service ? I18n.modelConnectionStatus(root.service.lastError || root.service.testStatus) : ""
                    color: Theme.textSecondary
                    font.pixelSize: Theme.fontSize(12)
                    wrapMode: Text.WordWrap
                }
            }
        }
    }
}
