// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import "../components"

Page {
    id: root
    objectName: "settingsHubScreen"

    readonly property var appWindow: ApplicationWindow.window
    readonly property var hostingService: typeof ws !== "undefined" && ws.forgeHost ? ws.forgeHost : null

    background: AppBackground { }

    ForgeHostingDialog {
        id: hostingOptions
        service: root.hostingService
    }

    SettingsPage {
        anchors.fill: parent
        title: qsTr("Settings")

        SettingsModuleRow {
            objectName: "settingsAppearanceModule"
            Layout.fillWidth: true
            title: qsTr("Appearance")
            subtitle: qsTr("Theme, battlefield background, scale, and motion")
            onActivated: root.appWindow.pushScreen("screens/AppearanceSettings.qml")
        }

        SettingsModuleRow {
            objectName: "settingsAudioModule"
            Layout.fillWidth: true
            title: qsTr("Audio")
            subtitle: qsTr("Operation sounds, volume, and mute")
            onActivated: root.appWindow.pushScreen("screens/AudioSettings.qml")
        }

        SettingsModuleRow {
            objectName: "settingsGameplayModule"
            Layout.fillWidth: true
            title: qsTr("Gameplay")
            subtitle: qsTr("Priority, phase stops, and direct connections")
            onActivated: root.appWindow.pushScreen("screens/GameplaySettings.qml")
        }

        SettingsModuleRow {
            objectName: "settingsLanguageModule"
            Layout.fillWidth: true
            title: qsTr("Language & cards")
            subtitle: qsTr("Menus, card names, and preferred art source")
            onActivated: root.appWindow.pushScreen("screens/LanguageSettings.qml")
        }

        SettingsModuleRow {
            objectName: "settingsCatalogModule"
            Layout.fillWidth: true
            title: qsTr("Card database")
            subtitle: qsTr("Searchable metadata for the deck editor")
            statusText: root.catalogStatusText()
            statusColor: root.catalogStatusColor()
            onActivated: root.appWindow.pushScreen("screens/CatalogSettings.qml")
        }

        SettingsModuleRow {
            objectName: "settingsDownloadSetArtButton"
            Layout.fillWidth: true
            title: qsTr("Download set art")
            subtitle: qsTr("Cache every printing from an installed set product")
            onActivated: root.appWindow.pushScreen("screens/SetArtDownload.qml")
        }

        SettingsModuleRow {
            objectName: "settingsManageArtButton"
            Layout.fillWidth: true
            title: qsTr("Card art storage")
            subtitle: qsTr("View disk usage, remove cached images, or share art packs")
            statusText: cardArtManager.repairNeeded ? qsTr("Repair recommended") : ""
            statusColor: Theme.warning
            onActivated: root.appWindow.pushScreen("screens/CardArtManager.qml")
        }

        SettingsModuleRow {
            objectName: "settingsCustomizeShortcutsButton"
            Layout.fillWidth: true
            title: qsTr("Keyboard shortcuts")
                subtitle: qsTr("Reassign, disable, or restore application and table actions.")
            onActivated: root.appWindow.pushScreen("screens/ShortcutSettings.qml")
        }

        SettingsModuleRow {
            objectName: "settingsUpdatesModule"
            Layout.fillWidth: true
            title: qsTr("Application updates")
            subtitle: qsTr("Check GitHub Releases and install a verified package")
            statusText: appUpdater.updateAvailable
                        ? qsTr("Update %1 available").arg(appUpdater.targetVersion) : ""
            statusColor: Theme.primary
            onActivated: root.appWindow.pushScreen("screens/UpdatesSettings.qml")
        }

        SettingsModuleRow {
            objectName: "settingsForgeHosting"
            Layout.fillWidth: true
            title: qsTr("Local Forge")
            subtitle: qsTr("Download, import, and diagnose the rules engine")
            enabled: root.hostingService !== null
            onActivated: hostingOptions.open()
        }

        SettingsModuleRow {
            objectName: "settingsModelOpponent"
            Layout.fillWidth: true
            title: qsTr("Model opponents")
            subtitle: qsTr("Local and online model connections, credentials, and thinking limits")
            statusText: qsTr("Experimental")
            statusColor: Theme.warning
            onActivated: root.appWindow.pushScreen("screens/ModelSettings.qml")
        }
    }

    function catalogStatusText() {
        if (cardCatalog.checkingCatalogVersion)
            return qsTr("Checking")
        if (!cardCatalog.installed)
            return cardCatalog.latestCatalogKnown ? qsTr("Ready to download")
                                                   : qsTr("Not installed")
        if (!cardCatalog.enhancedIndexInstalled || !cardCatalog.chineseIndexInstalled)
            return qsTr("Update needed")
        if (cardCatalog.catalogUpdateAvailable)
            return qsTr("Update available")
        if (cardCatalog.latestCatalogKnown && cardCatalog.latestCatalogCompatible)
            return qsTr("Up to date")
        return qsTr("Latest unknown")
    }

    function catalogStatusColor() {
        if (cardCatalog.checkingCatalogVersion)
            return Theme.primary
        if (cardCatalog.installed && cardCatalog.latestCatalogKnown
                && cardCatalog.latestCatalogCompatible
                && !cardCatalog.catalogUpdateAvailable
                && cardCatalog.enhancedIndexInstalled
                && cardCatalog.chineseIndexInstalled)
            return Theme.success
        return Theme.warning
    }
}
