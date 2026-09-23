// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic
import QtTest
import "../../qml/screens"
import "../../qml/components"

TestCase {
    name: "LimitedNavigation"
    when: windowShown

    ApplicationWindow {
        id: window
        width: 1280
        height: 800
        visible: true
        property string openedScreen: ""
        function pushScreen(url) { openedScreen = url }
        function popScreen() { }
    }
    QtObject {
        id: hub
        property bool connected: false
        property string serverTransportState: ""
        property bool inRoom: false
        property string displayName: "Navigation test"
        property int serverIndex: 0
        property var serverEntries: [
            {id: "server-1", name: "Server 1"},
            {id: "server-2", name: "Server 2"},
            {id: "server-3", name: "Server 3"},
            {id: "custom"}
        ]
        function disconnectFromHub() { connected = false }
    }
    QtObject {
        id: artManager
        property bool repairNeeded: false
    }
    QtObject {
        id: catalog
        signal catalogChanged()
        property bool installed: false
        property bool busy: false
        property bool enhancedIndexInstalled: false
        property bool chineseIndexInstalled: false
        property bool checkingCatalogVersion: false
        property bool catalogUpdateAvailable: false
        property bool latestCatalogKnown: false
        property bool latestCatalogCompatible: false
        property string installedCatalogVersion: ""
        property string latestCatalogVersion: ""
        property int installedCatalogSchemaVersion: 0
        property int latestCatalogSchemaVersion: 0
        property string catalogVersionError: ""
        property string packageName: "default_cards"
        property string status: ""
        property string lastError: ""
        property real progress: 0
        property bool limitedArtCaching: false
        property string limitedArtProductId: ""
        property int limitedArtTotal: 0
        property int limitedArtCompleted: 0
        property int limitedArtFailed: 0
        function clearLastError() { lastError = "" }
        function checkCatalogUpdateIfDue() { }
        function limitedProducts() { return [] }
        function limitedProduct(id) { return ({}) }
        function cacheLimitedProductArt(id) { }
    }
    QtObject {
        id: prefs
        property string cardArtProvider: "auto"
        property string cardLanguage: "en"
    }
    QtObject {
        id: updater
        property bool updateAvailable: false
        property bool releaseAvailable: false
        property bool downloadReady: false
        property bool downloading: false
        property bool checking: false
        property bool exactVersion: false
        property string currentVersion: "1.0.6"
        property string targetVersion: ""
        property string publishedAt: ""
        property string releaseNotes: ""
        property string lastError: ""
        property real progress: 0
    }

    Component {
        id: mainMenuComponent
        MainMenu {
            property bool localTestMode: true
            property var ws: hub
            property var cardCatalog: catalog
            property var cardArtManager: artManager
            property var appUpdater: updater
            property var deckLibrary: ({count: 0})
        }
    }
    Component {
        id: settingsComponent
        Settings {
            property var ws: hub
            property var cardCatalog: catalog
            property var cardArtManager: artManager
            property var appUpdater: updater
        }
    }
    Component {
        id: appearanceSettingsComponent
        AppearanceSettings { }
    }
    Component {
        id: audioSettingsComponent
        AudioSettings {
            music: QtObject {
                readonly property var tracks: [{id: "gitana", title: "Gitana"}]
            }
        }
    }
    Component {
        id: languageSettingsComponent
        LanguageSettings { }
    }
    Component {
        id: catalogSettingsComponent
        CatalogSettings {
            property var cardCatalog: catalog
        }
    }
    Component {
        id: updatesSettingsComponent
        UpdatesSettings {
            property var appUpdater: updater
        }
    }
    Component {
        id: setArtDownloadComponent
        SetArtDownload {
            property var cardCatalog: catalog
            property var preferences: prefs
        }
    }

    function init() {
        window.openedScreen = ""
        window.width = 1280
        window.height = 800
        Theme.uiScale = 1
        Theme.uiTheme = "classic"
        hub.connected = false
        hub.inRoom = false
        hub.displayName = "Navigation test"
        hub.serverIndex = 0
        updater.updateAvailable = false
        updater.targetVersion = ""
        testTranslations.setLanguage("en")
    }
    function cleanup() {
        Theme.uiScale = 1
        Theme.uiTheme = "classic"
        testTranslations.setLanguage("en")
    }
    function createPage(component) {
        const page = createTemporaryObject(component, window.contentItem)
        verify(page !== null)
        page.anchors.fill = window.contentItem
        waitForRendering(page)
        return page
    }
    function containsText(item, text) {
        if (item.text !== undefined && item.text === text)
            return true
        for (const child of item.children) {
            if (containsText(child, text))
                return true
        }
        return false
    }

    function test_wideHomeHeroDescribesManualForgeAndLimited() {
        window.width = 1600
        window.height = 900
        const page = createPage(mainMenuComponent)
        const hero = findChild(page, "mainMenuHero")
        verify(hero.visible)
        compare(findChild(page, "mainMenuHeroManualTitle").text, "Manual")
        compare(findChild(page, "mainMenuHeroForgeTitle").text, "Forge")
        compare(findChild(page, "mainMenuHeroLimitedDetail").text, "Sealed · Draft · Cube")
        verify(!containsText(page, "No rules engine"))
        verify(!containsText(page, "MANUAL TABLETOP · NATIVE DESKTOP"))
        window.width = 900
        window.height = 620
        waitForRendering(page)
        verify(!findChild(page, "mainMenuHero").visible)
    }

    function test_classicHomePanelKeepsAVisibleFrame() {
        Theme.uiTheme = "classic"
        const page = createPage(mainMenuComponent)
        const panel = findChild(page, "mainMenuPanel")
        verify(panel !== null)
        compare(panel.border.width, 2)
        compare(panel.border.color, "#8fb8a4")
        compare(panel.color, Theme.surface)
        hub.connected = true
        waitForRendering(page)
        compare(panel.border.width, 2)
        compare(panel.border.color, "#8fb8a4")
        compare(panel.color, Theme.surface)
    }

    function test_homeUsesEventsInsteadOfSeparateLimitedEntry() {
        const page = createPage(mainMenuComponent)
        verify(!containsText(page, "Limited play"))
        const events = findChild(page, "mainMenuEventsButton")
        verify(events !== null)
        verify(!events.enabled, "Events requires a hub connection")
        hub.connected = true
        verify(events.enabled)
        const body = findChild(page, "mainMenuBody")
        body.contentY = Math.max(0, body.contentHeight - body.height)
        waitForRendering(page)
        mouseClick(events)
        compare(window.openedScreen, "screens/TournamentBrowser.qml")
        hub.inRoom = true
        verify(!events.enabled, "Existing in-room navigation guard is preserved")
    }

    function test_settingsRemainsAccessibleOffline() {
        const page = createPage(mainMenuComponent)
        const settings = findChild(page, "mainMenuSettingsButton")
        verify(settings.enabled)
        mouseClick(settings)
        compare(window.openedScreen, "screens/Settings.qml")
    }

    function test_compactHomeShowsPrimaryActionWithoutScrolling_data() {
        return [{tag: "english", language: "en"}, {tag: "chinese", language: "zh"}]
    }
    function test_compactHomeShowsPrimaryActionWithoutScrolling(data) {
        window.width = 900
        window.height = 620
        Theme.uiScale = 1.5
        hub.connected = true
        testTranslations.setLanguage(data.language)
        const page = createPage(mainMenuComponent)
        const button = findChild(page, "mainMenuCreateRoomButton")
        verify(button.visible && button.enabled)
        const point = button.mapToItem(page, 0, 0)
        verify(point.y >= 0 && point.y + button.height <= page.height,
               "Create room remains visible on the initial compact page")
        mouseClick(button)
        compare(window.openedScreen, "screens/CreateRoom.qml")
    }

    function verifyHeaderGeometry(page) {
        const bar = findChild(page, "mainMenuTopBar")
        const brand = findChild(page, "mainMenuBrand")
        const actions = findChild(page, "mainMenuHeaderActions")
        compare(brand.mapToItem(bar, 0, 0).x, 0, "Brand remains on the left")
        const actionsPoint = actions.mapToItem(bar, 0, 0)
        fuzzyCompare(actionsPoint.x + actions.width, bar.width, 1,
                     "The action group is attached to the right edge")
        const visibleItems = [brand]
        const rowRightEdges = {}
        for (const name of ["mainMenuSettingsButton", "mainMenuUpdateButton",
                            "connectedPlayerStatus", "connectedServerStatus",
                            "mainMenuDisconnectButton"]) {
            const item = findChild(page, name)
            verify(item !== null, name)
            if (!item.visible)
                continue
            visibleItems.push(item)
            const local = item.mapToItem(actions, 0, 0)
            const row = String(Math.round(local.y))
            rowRightEdges[row] = Math.max(rowRightEdges[row] || 0, local.x + item.width)
        }
        for (const row in rowRightEdges)
            fuzzyCompare(rowRightEdges[row], actions.width, 1, "Every wrapped row aligns right")
        for (let i = 0; i < visibleItems.length; ++i) {
            const item = visibleItems[i]
            const point = item.mapToItem(bar, 0, 0)
            verify(item.width > 0 && item.height > 0, item.objectName)
            verify(point.x >= -1 && point.y >= -1, item.objectName)
            verify(point.x + item.width <= bar.width + 1, item.objectName)
            verify(point.y + item.height <= bar.height + 1, item.objectName)
            for (let j = i + 1; j < visibleItems.length; ++j) {
                const other = visibleItems[j]
                const otherPoint = other.mapToItem(bar, 0, 0)
                const overlap = point.x < otherPoint.x + other.width - 1
                             && point.x + item.width > otherPoint.x + 1
                             && point.y < otherPoint.y + other.height - 1
                             && point.y + item.height > otherPoint.y + 1
                verify(!overlap, item.objectName + " overlaps " + other.objectName)
            }
        }
        const body = findChild(page, "mainMenuBody")
        verify(body.y >= bar.y + bar.height, "The menu starts below the complete header")
        verify(body.height > 0, "Wrapped controls leave a usable scrolling body")
    }

    function test_headerKeepsBrandLeftAndControlsRight_data() {
        return [
            {tag: "wide-en", width: 1600, scale: 1, language: "en", inline: true},
            {tag: "wide-zh-scaled", width: 1920, scale: 1.5, language: "zh", inline: true},
            {tag: "narrow-en", width: 900, scale: 1, language: "en", inline: false},
            {tag: "narrow-en-maximum", width: 900, scale: 1.8, language: "en", inline: false},
            {tag: "narrow-zh-maximum", width: 900, scale: 1.8, language: "zh", inline: false}
        ]
    }
    function test_headerKeepsBrandLeftAndControlsRight(data) {
        window.width = data.width
        window.height = 620
        Theme.uiScale = data.scale
        testTranslations.setLanguage(data.language)
        hub.connected = true
        hub.serverIndex = 3
        hub.displayName = "A very long connected player display name"
        updater.updateAvailable = true
        updater.targetVersion = "1.0.7"
        const page = createPage(mainMenuComponent)
        compare(findChild(page, "mainMenuTopBar").inlineActions, data.inline)
        verifyHeaderGeometry(page)
        const disconnect = findChild(page, "mainMenuDisconnectButton")
        const bar = findChild(page, "mainMenuTopBar")
        fuzzyCompare(disconnect.mapToItem(bar, 0, 0).x + disconnect.width, bar.width, 1)
        verify(findChild(page, "connectedServerStatus").visible)
    }

    function test_headerRespondsToConnectionUpdateAndResize() {
        const page = createPage(mainMenuComponent)
        verifyHeaderGeometry(page)
        hub.connected = true
        hub.serverIndex = 2
        hub.displayName = "A very long connected player display name"
        updater.updateAvailable = true
        updater.targetVersion = "1.0.7"
        window.width = 900
        window.height = 620
        Theme.uiScale = 1.8
        waitForRendering(page)
        verifyHeaderGeometry(page)
        compare(findChild(page, "connectedServerStatus").text, "Server 3")
        hub.serverTransportState = "direct"
        compare(findChild(page, "connectedServerStatus").text, "Server 3 · Server · direct")
        hub.serverTransportState = "relay"
        compare(findChild(page, "connectedServerStatus").text, "Server 3 · Server · relay")
        hub.serverTransportState = ""
        mouseClick(findChild(page, "mainMenuDisconnectButton"))
        updater.updateAvailable = false
        waitForRendering(page)
        verifyHeaderGeometry(page)
        verify(!findChild(page, "connectedServerStatus").visible)
        compare(findChild(page, "connectedPlayerStatus").text, "Offline")
        window.width = 1600
        Theme.uiScale = 1
        waitForRendering(page)
        verifyHeaderGeometry(page)
        verify(findChild(page, "mainMenuTopBar").inlineActions)
        mouseClick(findChild(page, "mainMenuSettingsButton"))
        compare(window.openedScreen, "screens/Settings.qml")
    }

    function test_connectedHeaderFitsLongNameAndUpdate_data() {
        return [{tag: "large", scale: 1.5}, {tag: "maximum", scale: 1.8}]
    }
    function test_connectedHeaderFitsLongNameAndUpdate(data) {
        window.width = 900
        window.height = 620
        Theme.uiScale = data.scale
        hub.connected = true
        hub.displayName = "A very long connected player display name"
        hub.serverIndex = 3
        updater.updateAvailable = true
        updater.targetVersion = "1.0.7"
        const page = createPage(mainMenuComponent)
        for (const name of ["mainMenuSettingsButton", "connectedPlayerStatus",
                            "connectedServerStatus", "mainMenuDisconnectButton"]) {
            const item = findChild(page, name)
            const point = item.mapToItem(page, 0, 0)
            verify(point.x >= 0 && point.x + item.width <= page.width + 1, name)
            verify(point.y >= 0 && point.y + item.height <= page.height + 1, name)
        }
        mouseClick(findChild(page, "mainMenuDisconnectButton"))
        verify(!hub.connected)
    }

    function test_connectedMenuOmitsRedundantIntroduction() {
        testTranslations.setLanguage("zh")
        const page = createPage(mainMenuComponent)
        const heading = findChild(page, "mainMenuHeading")
        const intro = findChild(page, "mainMenuIntro")
        compare(heading.text, "开始游戏")
        verify(intro.visible)
        hub.connected = true
        verify(!intro.visible)
        compare(heading.text, "开始游戏")
        verify(!containsText(page, "开始一桌"))
    }

    function test_homeBrowseAndSimulatorMatchPanelButtons() {
        Theme.uiTheme = "glass"
        hub.connected = true
        const page = createPage(mainMenuComponent)
        const join = findChild(page, "mainMenuJoinRoomButton")
        const browse = findChild(page, "mainMenuBrowseHubButton")
        const simulator = findChild(page, "mainMenuPackSimulatorButton")
        const events = findChild(page, "mainMenuEventsButton")
        verify(join !== null && browse !== null && simulator !== null && events !== null)
        compare(browse.compact, false)
        compare(simulator.compact, false)
        compare(browse.variant, join.variant)
        compare(simulator.variant, events.variant)
        compare(browse.height, join.height)
        compare(simulator.height, events.height)
        verify(Theme.useGlass)
        verify(browse.glassVariant && simulator.glassVariant && join.glassVariant)
    }

    function test_homeOpensSimulator_data() {
        return [{tag: "english-offline", language: "en", width: 1280, height: 800, scale: 1,
                 connected: false, inRoom: false},
                {tag: "chinese-offline-scaled", language: "zh", width: 900, height: 620, scale: 1.25,
                 connected: false, inRoom: false},
                {tag: "connected", language: "en", width: 1280, height: 800, scale: 1,
                 connected: true, inRoom: false},
                {tag: "in-room", language: "en", width: 1280, height: 800, scale: 1,
                 connected: true, inRoom: true}]
    }
    function test_homeOpensSimulator(data) {
        window.width = data.width
        window.height = data.height
        Theme.uiScale = data.scale
        testTranslations.setLanguage(data.language)
        hub.connected = data.connected
        hub.inRoom = data.inRoom
        const page = createPage(mainMenuComponent)
        verify(!containsText(page, data.language === "zh" ? "回放" : "Replays"))
        const button = findChild(page, "mainMenuPackSimulatorButton")
        const body = findChild(page, "mainMenuBody")
        verify(button !== null)
        verify(button.enabled, "Opening the local simulator needs neither a server nor a catalog")
        compare(button.text, data.language === "zh" ? "模拟开包" : "Pack simulator")
        body.contentY = Math.min(body.contentHeight - body.height,
                                Math.max(0, button.mapToItem(body.contentItem, 0, 0).y))
        waitForRendering(page)
        const topLeft = button.mapToItem(body, 0, 0)
        verify(topLeft.x >= 0 && topLeft.x + button.width <= body.width + 1)
        verify(topLeft.y >= 0 && topLeft.y + button.height <= body.height + 1)
        mouseClick(button)
        compare(window.openedScreen, "screens/LimitedHub.qml")
    }

    function test_settingsHasNoDuplicateSimulatorEntry() {
        const page = createPage(settingsComponent)
        verify(!containsText(page, "Pack simulator"))
        compare(findChild(page, "settingsPackSimulatorButton"), null)
    }

    function test_settingsHubOpensSeparateModules() {
        const page = createPage(settingsComponent)
        const modules = [
            ["settingsAppearanceModule", "screens/AppearanceSettings.qml"],
            ["settingsAudioModule", "screens/AudioSettings.qml"],
            ["settingsLanguageModule", "screens/LanguageSettings.qml"],
            ["settingsCatalogModule", "screens/CatalogSettings.qml"],
            ["settingsDownloadSetArtButton", "screens/SetArtDownload.qml"],
            ["settingsManageArtButton", "screens/CardArtManager.qml"],
            ["settingsCustomizeShortcutsButton", "screens/ShortcutSettings.qml"],
            ["settingsUpdatesModule", "screens/UpdatesSettings.qml"]
        ]
        compare(findChild(page, "settingsThemeSelector"), null)
        compare(findChild(page, "settingsLanguageSelector"), null)
        compare(findChild(page, "settingsDownloadCatalogButton"), null)
        // The hub lists more modules than fit at this window height, so scroll
        // each row fully into the clipped viewport before clicking it.
        const body = findChild(page, "settingsBody")
        const flick = body.contentItem
        for (const [name, screen] of modules) {
            const row = findChild(page, name)
            verify(row !== null, name)
            const maxScroll = Math.max(0, flick.contentHeight - flick.height)
            flick.contentY = Math.max(0, Math.min(row.mapToItem(flick, 0, 0).y, maxScroll))
            waitForRendering(page)
            window.openedScreen = ""
            mouseClick(row)
            compare(window.openedScreen, screen, name)
        }
    }

    function test_settingsModulesLoadIndependently() {
        const appearance = createPage(appearanceSettingsComponent)
        verify(findChild(appearance, "settingsThemeSelector") !== null)
        verify(findChild(appearance, "settingsIncreaseScaleButton") !== null)
        compare(findChild(appearance, "settingsLanguageSelector"), null)

        const audio = createPage(audioSettingsComponent)
        verify(findChild(audio, "settingsAudioMute") !== null)
        verify(findChild(audio, "settingsAudioVolume") !== null)
        compare(findChild(audio, "settingsThemeSelector"), null)

        const language = createPage(languageSettingsComponent)
        verify(findChild(language, "settingsLanguageSelector") !== null)
        verify(findChild(language, "settingsCardLanguageSelector") !== null)
        compare(findChild(language, "settingsThemeSelector"), null)

        const catalogPage = createPage(catalogSettingsComponent)
        verify(findChild(catalogPage, "settingsDownloadCatalogButton") !== null
               || findChild(catalogPage, "settingsImportCatalogButton") !== null)
        compare(findChild(catalogPage, "settingsThemeSelector"), null)

        const updates = createPage(updatesSettingsComponent)
        verify(findChild(updates, "checkApplicationUpdatesButton") !== null)
        compare(findChild(updates, "settingsThemeSelector"), null)

        const setArt = createPage(setArtDownloadComponent)
        verify(findChild(setArt, "setArtDownloadBody") !== null)
        compare(findChild(setArt, "settingsThemeSelector"), null)
    }
}
