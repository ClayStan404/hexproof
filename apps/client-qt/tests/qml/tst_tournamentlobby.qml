// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic
import QtTest
import "../../qml/screens"
import "../../qml/components"

TestCase {
    name: "TournamentLobby"
    when: windowShown
    ApplicationWindow {
        id: window
        width: 1280
        height: 720
        visible: true
        function showBanner(text) { }
        TournamentLobby {
            id: page
            anchors.fill: parent
            tournamentModel: event
            limitedModel: limitedState
            wsModel: connection
            cardCatalogModel: catalog
            preferencesModel: settings
        }
    }
    QtObject {
        id: event
        signal snapshotChanged()
        signal chatChanged()
        signal inTournamentChanged()
        property string tournamentId: "EVENT1"
        property string name: "Community event"
        property string role: "organizer"
        property string participantId: ""
        property string coordinator: "swiss"
        property string stage: "registration"
        property string status: "registration"
        property string eventType: "set_sealed"
        property string format: "Limited"
        property string matchMode: "bo3"
        property string organizerName: "Judge"
        property string roundStartedAt: ""
        property int roundMinutes: 50
        property int currentRound: 0
        property int plannedRounds: 3
        property int registered: 2
        property int checkedIn: 2
        property int minimumPlayers: 2
        property bool canRegister: true
        property bool roundComplete: false
        property var product: ({id: "", name: "Test", authentic: true})
        property var pairings: []
        property var standings: []
        property var chatMessages: [{sequence: 1, displayName: "Alice", text: "<b>Hello</b>"}]
        property var participants: [
            {participantId: "a", displayName: "Alice", checkedIn: true, competing: true, dropped: false, online: true},
            {participantId: "b", displayName: "Bob", checkedIn: true, competing: true, dropped: false, online: true}
        ]
    }
    QtObject {
        id: limitedState
        signal snapshotChanged()
        property string stage: event.stage
        property int packRound: 1
        property int direction: 1
        property var currentPack: []
        property var pool: []
        property var basicLands: []
        property var mainboardInstanceIds: []
        property bool deckSubmitted: false
        property bool allDecksSubmitted: false
        property var participants: [
            {participantId: "a", displayName: "Alice", picked: 15, deckSubmitted: true},
            {participantId: "b", displayName: "Bob", picked: 14, deckSubmitted: false}
        ]
    }
    QtObject {
        id: connection
        property bool connected: true
        property string lastError: ""
        property string sentText: ""
        property int starts: 0
        property string lastWatchedRoom: ""
        function joinRoom(roomId, spectator, password) { lastWatchedRoom = roomId }
        function sendTournamentChat(text) { sentText = text; return "request-1" }
        function startTournament() { ++starts }
    }
    QtObject {
        id: catalog
        property bool installed: false
        property bool limitedArtCaching: false
        property string limitedArtProductId: ""
        property int limitedArtCompleted: 0
        property int limitedArtFailed: 0
        property int limitedArtTotal: 0
        property int imageRevision: 0
        function limitedProduct(id) { return ({}) }
        function cacheCardsIncrementally(cards) { }
        function imageSource(name, set, collector) { return "" }
    }
    QtObject {
        id: settings
        property string cardLanguage: "en"
        property string cardArtProvider: "scryfall"
    }
    function init() {
        event.coordinator = "swiss"
        event.stage = "registration"
        event.status = "registration"
        event.role = "organizer"
        event.participantId = ""
        event.tournamentId = "EVENT1"
        event.pairings = []
        page.selectedTab = 0
        connection.connected = true
        connection.starts = 0
        connection.sentText = ""
    }
    function cleanup() {
        Theme.uiScale = 1
        window.width = 1280
        window.height = 720
        event.standings = []
        findChild(page, "tournamentEventPopup").close()
        findChild(page, "tournamentScoreEditor").close()
    }
    function test_smallWindowKeepsPairingsStandingsAndDeskReachable_data() {
        return [{tag: "large", scale: 1.5}, {tag: "maximum", scale: 1.8}]
    }

    function test_smallWindowKeepsPairingsStandingsAndDeskReachable(data) {
        window.requestActivate()
        tryVerify(() => window.active)
        window.width = 900
        window.height = 620
        Theme.uiScale = data.scale
        event.status = "running"
        event.stage = "competition"
        event.pairings = [{pairingId: "pairing-1", table: 1,
            playerAId: "a", playerBId: "b", playerAName: "A long player name",
            playerBName: "Another player name", bye: false, status: "reported",
            playerAWins: 2, playerBWins: 1, drawnGames: 0, corrected: false,
            roomId: "ABC123", reporterId: "a"}]
        waitForRendering(page)
        const pairings = findChild(page, "tournamentPairingList")
        verify(pairings.width >= page.width - Theme.size(100))
        const watch = findChild(pairings.itemAtIndex(0), "watchTournamentMatchButton")
        const point = watch.mapToItem(page, 0, 0)
        verify(point.x >= 0 && point.x + watch.width <= page.width)
        mouseClick(watch)
        compare(connection.lastWatchedRoom, "ABC123")
        event.standings = [{participantId: "a", rank: 1, displayName: "A long player name",
            wins: 2, losses: 0, draws: 0, matchPoints: 6,
            oppMatchWin: 0.55, gameWin: 0.75, oppGameWin: 0.6}]
        page.selectedTab = 1
        waitForRendering(page)
        const label = findChild(page, "tournamentStandingPlayerName")
        verify(label.width >= Theme.size(80))
        const header = findChild(page, "tournamentStandingHeader")
        const columns = findChild(page, "tournamentStandingColumns")
        verify(header)
        verify(columns)
        compare(header.children.length, columns.children.length)
        for (let index = 0; index < header.children.length; ++index) {
            const heading = header.children[index]
            const value = columns.children[index]
            verify(heading.width > 0)
            verify(heading.x >= 0 && heading.x + heading.width <= header.width + 1)
            fuzzyCompare(heading.x, value.x, 1)
            fuzzyCompare(heading.width, value.width, 1)
        }
        mouseClick(findChild(page, "limitedEventDeskButton"))
        const desk = findChild(page, "tournamentEventPopup")
        tryVerify(() => desk.opened)
        verify(desk.x >= 0 && desk.x + desk.width <= window.width)
        verify(desk.y >= 0 && desk.y + desk.height <= window.height)
        keyClick(Qt.Key_Escape)
        tryVerify(() => !desk.opened)
    }

    function test_correctionUnavailableWhenEventEnds_data() {
        return [
            {tag: "completed", status: "completed"},
            {tag: "cancelled", status: "cancelled"}
        ]
    }
    function test_correctionUnavailableWhenEventEnds(data) {
        event.status = "running"
        event.stage = "competition"
        event.pairings = [{
            pairingId: "pairing-1", table: 1, playerAId: "a", playerBId: "b",
            playerAName: "Alice", playerBName: "Bob", bye: false,
            status: "confirmed", playerAWins: 2, playerBWins: 1,
            drawnGames: 0, corrected: false, roomId: ""
        }]
        const list = findChild(page, "tournamentPairingList")
        tryVerify(() => list.itemAtIndex(0) !== null)
        const correct = findChild(list.itemAtIndex(0), "correctTournamentResultButton")
        verify(correct.visible)
        mouseClick(correct)
        const editor = findChild(page, "tournamentScoreEditor")
        tryVerify(() => editor.opened)
        verify(editor.correction)
        event.status = data.status
        verify(!correct.visible)
        tryVerify(() => !editor.visible)
        verify(!editor.enabled)
    }
    function test_casualLobbyHasNoRoundClockAndClosesDraftDeskAfterBuilding() {
        event.coordinator = "casual"
        event.status = "running"
        event.stage = "deck_building"
        event.participantId = "a"
        const summary = findChild(page, "tournamentLobbySummary")
        verify(summary.text.indexOf("50") < 0)
        const popup = findChild(page, "tournamentEventPopup")
        popup.open()
        tryVerify(() => popup.opened)
        event.stage = "competition"
        tryVerify(() => !popup.visible)
        event.coordinator = "swiss"
        verify(summary.text.indexOf("50") >= 0)
    }
    function test_registrationListsPlayersAndOrganizerCanStartWithoutRegistering() {
        const list = findChild(page, "tournamentParticipantList")
        verify(list.visible)
        compare(list.count, 2)
        compare(list.model[0].displayName, "Alice")
        verify(!page.isParticipant)
        const start = findChild(page, "startTournamentButton")
        verify(start.enabled)
        start.clicked()
        compare(connection.starts, 1)
    }
    function test_sidebarUsesChineseTranslations() {
        testTranslations.setLanguage("zh")
        const tabs = findChild(page, "tournamentSidebarTabs")
        const options = tabs.options.slice()
        testTranslations.setLanguage("en")
        compare(options[0], "赛事控制台")
        compare(options[1], "聊天")
    }
    function test_nonplayingOrganizerSeesPublicProgressDuringLimitedStages() {
        event.status = "running"
        for (const stage of ["draft", "deck_building"]) {
            event.stage = stage
            verify(findChild(page, "limitedEventProgressList").visible)
            compare(limitedState.pool.length, 0)
        }
        event.participantId = "a"
        verify(!findChild(page, "limitedEventProgressList").visible)
    }
    function test_chatSendAndScopeChange() {
        const input = findChild(page, "tournamentChatInput")
        const button = findChild(page, "tournamentChatSendButton")
        input.text = "Hello event"
        verify(button.enabled)
        button.clicked()
        compare(connection.sentText, "Hello event")
        compare(input.text, "")
        input.text = "Unsent draft"
        event.tournamentId = "EVENT2"
        compare(input.text, "")
        connection.connected = false
        input.text = "Offline"
        verify(!button.enabled)
    }
    function test_limitedWorkspaceKeepsEventDeskAccessibleInOverlay() {
        event.status = "running"
        event.stage = "draft"
        event.participantId = "a"
        verify(page.focusedLimited)
        const button = findChild(page, "limitedEventDeskButton")
        verify(button.visible)
        button.clicked()
        const popup = findChild(page, "tournamentEventPopup")
        tryVerify(() => popup.opened)
        const desk = findChild(popup.contentItem, "tournamentEventDeskScroll")
        verify(desk.visible)
        popup.close()
        verify(page.focusedLimited)
    }
}
