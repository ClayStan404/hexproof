// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import "../components"

Page {
    id: root
    objectName: "accountScreen"
    property var wsModel: ws
    property var service: wsModel.account
    readonly property var appWindow: ApplicationWindow.window
    readonly property bool ready: wsModel.connected && service.supported && !service.busy && service.pendingClaims === 0
    property bool showCodes: false
    property int entryMode: 0
    background: AppBackground { }

    Component.onCompleted: { if (service.authenticated && root.ready) service.refresh() }

    SettingsPage {
        anchors.fill: parent
        title: qsTr("Official account")
        subtitle: qsTr("One account across official servers. Keep your login and recovery codes private.")

        InfoBanner {
            Layout.fillWidth: true
            visible: !wsModel.connected || !root.service.supported
            tone: "warning"
            message: !wsModel.connected ? qsTr("Connect to an official server to manage your account.")
                                   : qsTr("Accounts are unavailable on this server.")
        }
        InfoBanner {
            Layout.fillWidth: true
            visible: root.service.lastError.length > 0
            tone: "warning"
            message: I18n.status(root.service.lastError)
        }
        InfoBanner {
            Layout.fillWidth: true
            visible: root.service.authenticated && !root.service.vaultAvailable
            tone: "warning"
            message: qsTr("The system credential vault is unavailable. This login is kept only for this application session; back up your login code.")
        }

        ColumnLayout {
            Layout.fillWidth: true
            visible: root.service.supported && !root.service.authenticated
            spacing: Theme.size(12)
            SegmentedControl {
                Layout.fillWidth: true
                options: [qsTr("Log in"), qsTr("Create account"), qsTr("Recover")]
                currentIndex: root.entryMode
                onActivated: index => { root.entryMode = index; accountEntry.text = "" }
            }
            AppTextField {
                id: accountEntry
                objectName: "accountEntry"
                Layout.fillWidth: true
                enabled: root.ready
                maximumLength: root.entryMode === 1 ? 40 : 128
                echoMode: root.entryMode === 1 ? TextInput.Normal : TextInput.Password
                placeholderText: root.entryMode === 1 ? qsTr("Display name")
                                 : root.entryMode === 2 ? qsTr("Recovery code") : qsTr("Private login code")
                onAccepted: root.submitEntry()
            }
            Text {
                textFormat: Text.PlainText
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                color: Theme.textSecondary
                text: root.entryMode === 2
                      ? qsTr("Recovery replaces both codes and signs out every old device.")
                      : qsTr("No email or password is required. Without your codes or a signed-in device, a lost account cannot be recovered.")
            }
            AppButton {
                Layout.fillWidth: true
                objectName: "accountSubmit"
                enabled: root.ready && accountEntry.text.trim().length > 0
                text: root.entryMode === 1 ? qsTr("Create account") : root.entryMode === 2 ? qsTr("Recover account") : qsTr("Log in")
                onClicked: root.submitEntry()
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            visible: root.service.loginCode.length > 0 || root.service.recoveryCode.length > 0
            spacing: Theme.size(10)
            InfoBanner {
                Layout.fillWidth: true
                message: qsTr("Back up these codes now. They are shown only when generated. Anyone with a login code can access the account; keep the recovery code separately.")
                tone: "warning"
            }
            AppTextField {
                objectName: "accountGeneratedLoginCode"
                Layout.fillWidth: true
                visible: root.service.loginCode.length > 0
                text: root.service.loginCode
                readOnly: true
                echoMode: root.showCodes ? TextInput.Normal : TextInput.Password
            }
            AppButton {
                Layout.fillWidth: true
                text: qsTr("Copy login code")
                visible: root.service.loginCode.length > 0
                onClicked: wsModel.copyToClipboard(root.service.loginCode)
            }
            AppTextField {
                objectName: "accountGeneratedRecoveryCode"
                Layout.fillWidth: true
                visible: root.service.recoveryCode.length > 0
                text: root.service.recoveryCode
                readOnly: true
                echoMode: root.showCodes ? TextInput.Normal : TextInput.Password
            }
            AppButton {
                Layout.fillWidth: true
                text: qsTr("Copy recovery code")
                visible: root.service.recoveryCode.length > 0
                onClicked: wsModel.copyToClipboard(root.service.recoveryCode)
            }
            AppButton {
                Layout.fillWidth: true
                variant: "ghost"
                text: root.showCodes ? qsTr("Hide codes") : qsTr("Show codes")
                onClicked: root.showCodes = !root.showCodes
            }
            AppButton {
                objectName: "accountBackupAcknowledged"
                Layout.fillWidth: true
                text: qsTr("I have backed up my codes")
                onClicked: { root.showCodes = false; root.service.acknowledgeBackup() }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            visible: root.service.authenticated
            spacing: Theme.size(14)
            Text {
                Layout.fillWidth: true
                textFormat: Text.PlainText
                wrapMode: Text.WrapAnywhere
                color: Theme.text
                font.pixelSize: Theme.fontSize(18)
                text: root.service.displayName + "\n" + qsTr("Public ID: %1").arg(root.service.accountId)
            }
            AppTextField {
                id: renameField
                objectName: "accountNickname"
                Layout.fillWidth: true
                maximumLength: 40
                placeholderText: qsTr("New display name")
                enabled: root.ready
            }
            AppButton {
                Layout.fillWidth: true
                text: qsTr("Update display name")
                enabled: root.ready && renameField.text.trim().length > 0
                onClicked: { root.service.rename(renameField.text); renameField.text = "" }
            }
            Text {
                textFormat: Text.PlainText
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                color: Theme.textSecondary
                text: wsModel.clusterAvailable ? qsTr("Recoverable rooms and events across official nodes")
                                             : qsTr("Recoverable rooms and events on this server")
            }
            Repeater {
                model: root.service.resources
                AppButton {
                    required property var modelData
                    Layout.fillWidth: true
                    text: modelData.name + " · " + modelData.id
                    enabled: root.ready
                    onClicked: {
                        if (modelData.kind === "room") root.service.resumeRoom(modelData.id)
                        else wsModel.enterTournament(modelData.id)
                    }
                }
            }
            AppButton {
                Layout.fillWidth: true
                text: qsTr("Refresh account resources")
                enabled: root.ready
                onClicked: root.service.refresh()
            }
            AppButton {
                objectName: "accountRestoreReplays"
                Layout.fillWidth: true
                text: qsTr("Restore my replay library")
                enabled: root.ready
                onClicked: root.service.requestReplays()
            }
            AppButton {
                objectName: "accountClaimLocalData"
                Layout.fillWidth: true
                text: root.service.pendingClaims > 0 ? qsTr("Linking saved identities… %1 remaining").arg(root.service.pendingClaims)
                                                     : qsTr("Link saved event and replay identities on this device")
                enabled: root.ready
                onClicked: wsModel.claimLocalAccountData()
            }
            Text {
                textFormat: Text.PlainText
                Layout.fillWidth: true
                color: Theme.text
                font.pixelSize: Theme.fontSize(18)
                text: qsTr("Signed-in devices")
            }
            Repeater {
                model: root.service.devices
                ColumnLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    Text {
                        textFormat: Text.PlainText
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        color: Theme.textSecondary
                        text: modelData.name + (modelData.current ? " · " + qsTr("This device") : "")
                              + "\n" + qsTr("Expires: %1").arg(modelData.expiresAt)
                    }
                    AppButton {
                        Layout.fillWidth: true
                        text: qsTr("Sign out this device")
                        enabled: root.ready
                        onClicked: root.service.revokeSession(modelData.id)
                    }
                }
            }
            AppButton {
                Layout.fillWidth: true
                text: qsTr("Sign out other devices")
                enabled: root.ready
                onClicked: root.service.revokeOtherSessions()
            }
            AppButton {
                Layout.fillWidth: true
                text: qsTr("Replace login code and sign out other devices")
                enabled: root.ready && root.service.loginCode.length === 0
                onClicked: root.service.rotateLoginCode()
            }
            AppButton {
                objectName: "accountLogout"
                Layout.fillWidth: true
                text: qsTr("Sign out of account")
                enabled: root.ready
                onClicked: root.service.logout()
            }
        }
    }

    function submitEntry() {
        if (!root.ready || accountEntry.text.trim().length === 0) return
        const value = accountEntry.text.trim()
        if (root.entryMode === 1) root.service.createAccount(value)
        else if (root.entryMode === 2) root.service.recover(value)
        else root.service.login(value)
        accountEntry.text = ""
    }
}
