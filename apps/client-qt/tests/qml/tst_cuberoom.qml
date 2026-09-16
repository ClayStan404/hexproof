// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic
import QtTest
import "../../qml/screens"

TestCase {
    id: testCase
    name: "CubeRoom"
    when: windowShown
    property var page
    ApplicationWindow {
        id: window
        width: 1280
        height: 800
        visible: true
    }
    Component {
        id: roomComponent
        CubeRoom {
            anchors.fill: parent
            tournamentModel: roomState
            limitedModel: limitedState
            wsModel: connection
            cardCatalogModel: catalog
        }
    }
    QtObject {
        id: roomState
        signal snapshotChanged()
        signal chatChanged()
        signal inTournamentChanged()
        property string tournamentId: "CUBE01"
        property string name: "Friday Cube"
        property string role: "organizer"
        property string participantId: "a"
        property string coordinator: "casual"
        property string stage: "registration"
        property string status: "registration"
        property string eventType: "cube_draft"
        property string format: "Cube"
        property string matchMode: "bo3"
        property var draftSettings: ({packsPerPlayer: 3, packsPerBatch: 1})
        property string organizerName: "Alice"
        property int maxPlayers: 4
        property var participants: []
        property var pairings: []
        property var chatMessages: []
    }
    QtObject {
        id: limitedState
        signal snapshotChanged()
        property string tournamentId: roomState.tournamentId
        property string eventType: "cube_draft"
        property string stage: roomState.stage
        property int packRound: 1
        property int direction: 1
        property var currentPack: []
        property var pool: []
        property var basicLands: []
        property var mainboardInstanceIds: []
        property bool deckSubmitted: false
        property bool allDecksSubmitted: false
        property var participants: []
    }
    QtObject {
        id: connection
        signal commandFailed(string requestId, string commandType, var payload, string error)
        signal welcomeReceived()
        property bool connected: true
        property bool inRoom: false
        property bool reconnecting: false
        property string serverUrl: "ws://127.0.0.1:57320/ws"
        property string lastError: ""
        property var calls: []
        function record(name, args) { calls = calls.concat([{name: name, args: args}]) }
        function setTournamentCheckedIn(value) { record("ready", [value]) }
        function startTournament() { record("start", []) }
        function leaveTournament() { record("leave", []) }
        function createLimitedCasualMatch(a, b) { record("invite", [a, b]) }
        function cancelLimitedCasualMatch(a, b) { record("cancel", [a, b]) }
        function openTournamentMatch(id) { record("open", [id]) }
        function joinRoom(id, spectator, password) { record("watch", [id, spectator, password]) }
        function sendTournamentChat(text) { record("chat", [text]); return "request" }
        function submitLimitedDeck(name, ids, lands) { record("deck", [name, ids, lands]) }
        function pickLimitedCard(id) { record("pick", [id]); return "request" }
        function inviteCommanderCubePlayers(ids) { record("groupinvite", ids) }
        function respondCommanderCubeInvitation(id, accepted) { record("groupresponse", [id, accepted]) }
        function setLimitedDraftControl(id, automatic) { record("draftcontrol", [id, automatic]) }
        function setLimitedParticipation(participating) { record("participation", [participating]) }
    }
    QtObject {
        id: catalog
        property int imageRevision: 0
        function cacheCardsIncrementally(cards) { }
        function imageSource(name, set, collector) { return "" }
        function tableImageSource(name, set, collector) { return "" }
        function enrichLimitedCards(cards) { return cards }
    }
    function player(id, ready = true, online = true) {
        return {participantId: id, displayName: id === "a" ? "Alice" : "Bob",
                checkedIn: ready, online: online, competing: true}
    }
    function pairing(a, b, status = "invited", roomId = "") {
        return {pairingId: "casual-1", playerAId: a, playerBId: b, status: status,
                playerAName: a === "a" ? "Alice" : "Bob",
                playerBName: b === "a" ? "Alice" : "Bob", roomId: roomId}
    }
    function init() {
        testTranslations.setLanguage("en")
        window.width = 1280
        window.height = 800
        roomState.stage = "registration"
        roomState.eventType = "cube_draft"
        roomState.draftSettings = {packsPerPlayer: 3, packsPerBatch: 1}
        roomState.status = "registration"
        roomState.role = "organizer"
        roomState.participantId = "a"
        roomState.maxPlayers = 4
        roomState.participants = [player("a"), player("b")]
        roomState.pairings = []
        connection.connected = true
        connection.inRoom = false
        connection.reconnecting = false
        connection.calls = []
        limitedState.tournamentId = Qt.binding(() => roomState.tournamentId)
        limitedState.stage = Qt.binding(() => roomState.stage)
        limitedState.pool = []
        limitedState.participants = []
        limitedState.currentPack = []
        limitedState.deckSubmitted = false
        limitedState.allDecksSubmitted = false
        limitedState.mainboardInstanceIds = []
        limitedState.basicLands = []
        page = createTemporaryObject(roomComponent, window.contentItem)
        verify(page)
    }
    function competition() {
        roomState.status = "running"
        roomState.stage = "competition"
    }
    function editSubmittedDeck() {
        competition()
        limitedState.pool = [{instanceId: "physical-1", name: "First spell", typeLine: "Instant"},
                             {instanceId: "physical-2", name: "Second spell", typeLine: "Sorcery"}]
        limitedState.mainboardInstanceIds = ["physical-1"]
        limitedState.basicLands = [{name: "Island", count: 39}]
        limitedState.deckSubmitted = true
        limitedState.snapshotChanged()
        page.editingDeck = true
        const builder = findChild(page, "cubeDeckWorkspace")
        verify(!builder.hasUnsubmittedChanges)
        builder.moveToMainDeck("physical-2")
        builder.adjustBasic("Island", -1)
        verify(builder.hasUnsubmittedChanges)
        return builder
    }
    function test_seatsAndReadyReplaceRegistration() {
        compare(findChild(page, "cubeRoomSeats").count, 4)
        verify(findChild(page, "cubeReadyButton").visible)
        verify(!findChild(page, "registerLimitedPlayerButton"))
        verify(!findChild(page, "tournamentStandingList"))
        verify(findChild(page, "cubeRoomSummary").text.indexOf("CUBE01") >= 0)
        page.setReady()
        compare(connection.calls[0].name, "ready")
        compare(connection.calls[0].args[0], false)
    }
    function test_explicitDraftControlAndStaleConfirmation() {
        roomState.stage = "draft"
        roomState.status = "running"
        const offline = Object.assign(player("b", true, false),
            {disconnectedAt: "2026-09-10T00:00:00.123456789Z"})
        roomState.participants = [player("a"), offline]
        page.currentTime = Date.parse("2026-09-10T00:03:00.123Z")
        verify(!page.canEnableAutoDraft("b"), "Exactly three minutes still waits")
        page.currentTime += 1
        verify(page.canEnableAutoDraft("b"), "Fractional server timestamps remain parseable")
        page.requestAutoDraft("b")
        const dialog = findChild(page, "cubeAutoDraftDialog")
        tryVerify(() => dialog.opened)
        roomState.participants = [player("a"), player("b")]
        findChild(dialog, "confirmButton").clicked()
        compare(connection.calls.length, 0, "Returning seat cannot be taken over from stale dialog")
        roomState.role = "participant"
        verify(!page.canEnableAutoDraft("b"))
        verify(page.canEnableAutoDraft("a"))
        page.requestAutoDraft("a")
        tryVerify(() => dialog.opened)
        findChild(dialog, "confirmButton").clicked()
        compare(connection.calls[0].args, ["a", true])
        limitedState.participants = [{participantId: "a", displayName: "Alice", autoDraft: true}]
        verify(page.automaticDraft)
        page.reclaimDraft()
        compare(connection.calls[1].args, ["a", false])
        connection.connected = false
        page.reclaimDraft()
        compare(connection.calls.length, 2)
    }
    function test_sitOutPreservesEditsAndRejoinRequiresSubmittedDeck() {
        const builder = editSubmittedDeck()
        roomState.stage = "deck_building"
        page.changeParticipation()
        const dialog = findChild(page, "cubeSitOutDialog")
        tryVerify(() => dialog.opened)
        findChild(dialog, "confirmButton").clicked()
        compare(connection.calls[0].args, [false])
        verify(builder.hasUnsubmittedChanges)
        limitedState.participants = [{participantId: "a", displayName: "Alice", withdrawn: true},
            {participantId: "b", displayName: "Bob", deckSubmitted: true}]
        verify(page.sittingOut)
        compare(builder.submissionProgress(), "1 / 1")
        competition()
        verify(!page.canInvitePlayer("b"))
        limitedState.deckSubmitted = false
        verify(!page.canChangeParticipation(true))
        limitedState.deckSubmitted = true
        verify(page.canChangeParticipation(true))
        page.changeParticipation()
        compare(connection.calls[1].args, [true])
        verify(builder.hasUnsubmittedChanges)
        roomState.pairings = [pairing("a", "b")]
        verify(!page.canChangeParticipation(true))
    }
    function test_rulesAreScrollableAtNarrowSize() {
        window.width = 900
        window.height = 620
        findChild(page, "cubeRoomInfoButton").clicked()
        const popup = findChild(page, "cubeRoomInfoPopup")
        tryVerify(() => popup.opened)
        compare(findChild(popup, "cubeRoomInfoTabs").options.length, 3)
        page.roomInfoTab = 2
        const rules = findChild(popup, "cubeRoomRules")
        tryVerify(() => rules.visible && rules.height > 100)
        verify(popup.y + popup.height <= window.height)
        tryVerify(() => rules.contentItem.contentHeight > rules.height)
        popup.close()
    }
    function test_rulesUseCurrentLanguage() {
        findChild(page, "cubeRoomInfoButton").clicked()
        const popup = findChild(page, "cubeRoomInfoPopup")
        tryVerify(() => popup.opened)
        page.roomInfoTab = 2
        const rules = findChild(popup, "cubeRoomRules")
        tryVerify(() => findChild(rules, "cubeRule-0") !== null)
        testTranslations.setLanguage("zh")
        tryCompare(findChild(rules, "cubeRule-0"), "text", "Cube 规则")
        roomState.eventType = "commander_cube"
        tryCompare(findChild(rules, "cubeRule-0"), "text", "Commander Cube 规则")
        roomState.draftSettings = {packsPerPlayer: 6, packsPerBatch: 2, cardsPerPack: 25}
        verify(findChild(rules, "cubeRule-1").text.indexOf("每人 6 包") >= 0)
        verify(findChild(rules, "cubeRule-1").text.indexOf("每包 25 张") >= 0)
        verify(findChild(rules, "cubeRule-1").text.indexOf("每次开 2 包，各选 2 张") >= 0)
        verify(findChild(rules, "cubeRule-4").text.indexOf("阳光戒、指挥塔、秘法印记") >= 0)
        testTranslations.setLanguage("en")
        popup.close()
    }
    function test_allOnlineOccupiedSeatsMustBeReady() {
        verify(page.canStart)
        page.startDraft()
        compare(connection.calls.length, 1)
        roomState.participants = [player("a"), player("b", false)]
        verify(!page.canStart)
        page.startDraft()
        compare(connection.calls.length, 1)
        roomState.participants = [player("a"), player("b", true, false)]
        verify(!page.canStart)
        roomState.participants = [player("a")]
        verify(!page.canStart)
        roomState.participants = [player("a"), player("b")]
        roomState.role = "participant"
        verify(!page.canStart)
        verify(!findChild(page, "cubeStartDraftButton").visible)
    }
    function test_leavingHostRequiresConfirmationGuestsLeaveDirectly() {
        page.leaveRoom()
        compare(connection.calls.length, 0)
        const confirm = findChild(page, "cubeCloseRoomDialog")
        tryVerify(() => confirm.opened)
        findChild(confirm, "confirmButton").clicked()
        compare(connection.calls[0].name, "leave")
        roomState.role = "participant"
        page.leaveRoom()
        compare(connection.calls.length, 2)
    }
    function test_draftAndBuilderReuseWorkspacesAndKeepUnsubmittedEdits() {
        limitedState.pool = [{instanceId: "physical-1", name: "First spell", typeLine: "Instant"}]
        roomState.status = "running"
        roomState.stage = "draft"
        verify(findChild(page, "cubeDraftWorkspace").visible)
        verify(page.focusedWorkspace)
        roomState.stage = "deck_building"
        const builder = findChild(page, "cubeDeckWorkspace")
        verify(builder.visible)
        builder.initialPoolChosen = true
        builder.moveToMainDeck("not-in-pool")
        verify(!builder.cardSelected("not-in-pool"))
        builder.moveToMainDeck("physical-1")
        roomState.stage = "competition"
        verify(builder.visible, "Automatic free play must not dismiss the active deck editor")
        verify(builder.cardSelected("physical-1"))
        findChild(page, "cubeDeckModeButton").clicked()
        verify(!builder.visible)
        verify(findChild(page, "cubeFreePlayWorkspace").visible)
        findChild(page, "cubeDeckModeButton").clicked()
        verify(builder.visible)
        verify(builder.cardSelected("physical-1"))
        limitedState.snapshotChanged()
        verify(builder.cardSelected("physical-1"))
    }
    function test_invitationRequiresConsentBeforeOpening() {
        competition()
        page.invitePlayer("b")
        compare(connection.calls[0].name, "invite")
        compare(connection.calls[0].args[0], "a")
        compare(connection.calls[0].args[1], "b")
        roomState.pairings = [pairing("a", "b")]
        verify(!findChild(page, "cubeAcceptInviteButton").visible)
        verify(!findChild(page, "cubeOpenMatchButton").visible)
        page.openMatch()
        page.invitePlayer("b")
        compare(connection.calls.length, 1)
        page.cancelInvitation()
        compare(connection.calls[1].name, "cancel")
        roomState.pairings = [pairing("b", "a")]
        verify(findChild(page, "cubeAcceptInviteButton").visible)
        findChild(page, "cubeAcceptInviteButton").clicked()
        compare(connection.calls[2].name, "invite")
        compare(connection.calls[2].args[0], "a")
        compare(connection.calls[2].args[1], "b")
        roomState.pairings = [pairing("b", "a", "open")]
        verify(findChild(page, "cubeOpenMatchButton").visible)
        page.openMatch()
        compare(connection.calls[3].name, "open")
        compare(connection.calls[3].args[0], "casual-1")
    }
    function submittedDeckSnapshot() {
        limitedState.pool = [{instanceId: "physical-1", name: "First spell", typeLine: "Instant"}]
        limitedState.mainboardInstanceIds = ["physical-1"]
        limitedState.basicLands = [{name: "Island", count: 39}]
        limitedState.deckSubmitted = true
        limitedState.allDecksSubmitted = true
        limitedState.snapshotChanged()
    }
    function automaticPairing(ids = ["a", "b"]) {
        return Object.assign(roomState.eventType === "commander_cube"
            ? group(ids, ids, "open") : pairing(ids[0], ids[1], "open"), {autoEnter: true})
    }
    function test_automaticTableOpensOnceWithoutInvitation_data() {
        return [{tag: "ordinary Cube", commander: false, ids: ["a", "b"]},
            {tag: "Commander two", commander: true, ids: ["a", "b"]},
            {tag: "Commander three", commander: true, ids: ["a", "b", "c"]},
            {tag: "Commander four", commander: true, ids: ["a", "b", "c", "d"]}]
    }
    function test_automaticTableOpensOnceWithoutInvitation(data) {
        roomState.eventType = data.commander ? "commander_cube" : "cube_draft"
        roomState.participants = data.ids.map(id => player(id))
        roomState.participantId = data.ids[data.ids.length - 1]
        competition()
        submittedDeckSnapshot()
        roomState.pairings = [automaticPairing(data.ids)]
        tryCompare(connection, "calls", [{name: "open", args: [data.commander ? "group-1" : "casual-1"]}])
        verify(!findChild(page, "cubeDiscardDeckDialog").opened)
        roomState.snapshotChanged()
        limitedState.snapshotChanged()
        roomState.pairings = [automaticPairing(data.ids)]
        wait(0)
        compare(connection.calls.length, 1, "Repeated snapshots must not repeat the open command")
        connection.commandFailed("open-request", "tournament.open_match", {}, "Test failure")
        limitedState.snapshotChanged()
        wait(0)
        compare(connection.calls.length, 1, "Errors do not trigger an automatic retry loop")
        page.openMatch()
        compare(connection.calls.length, 2, "An explicit retry remains available")
    }
    function test_automaticTableWaitsForPrivateDeckAcknowledgement() {
        roomState.status = "running"
        roomState.stage = "deck_building"
        limitedState.stage = "deck_building"
        const builder = findChild(page, "cubeDeckWorkspace")
        limitedState.pool = [{instanceId: "physical-1", name: "First spell", typeLine: "Instant"}]
        builder.chooseInitialPool(true)
        builder.adjustBasic("Island", 39)
        builder.submit()
        roomState.stage = "competition"
        roomState.pairings = [automaticPairing()]
        wait(0)
        compare(connection.calls.length, 1, "The public pairing is not a private submission acknowledgement")
        verify(!findChild(page, "cubeDiscardDeckDialog").opened)
        limitedState.stage = "competition"
        submittedDeckSnapshot()
        tryCompare(connection, "calls", [connection.calls[0], {name: "open", args: ["casual-1"]}])
        verify(!builder.hasUnsubmittedChanges)
        verify(!findChild(page, "cubeDiscardDeckDialog").opened,
            "The builder must reconcile its own acknowledgement before checking for later edits")
    }
    function test_automaticTableDoesNotDiscardLaterDeckEdits() {
        const builder = editSubmittedDeck()
        limitedState.allDecksSubmitted = true
        roomState.pairings = [automaticPairing()]
        const dialog = findChild(page, "cubeDiscardDeckDialog")
        tryVerify(() => dialog.opened)
        compare(connection.calls.length, 0)
        verify(builder.hasUnsubmittedChanges)
        findChild(dialog, "cancelButton").clicked()
        limitedState.snapshotChanged()
        roomState.pairings = [automaticPairing()]
        wait(0)
        verify(!dialog.opened)
        compare(connection.calls.length, 0)
        verify(builder.cardSelected("physical-2"))
        page.openMatch()
        tryVerify(() => dialog.opened)
        findChild(dialog, "confirmButton").clicked()
        compare(connection.calls, [{name: "open", args: ["casual-1"]}])
        verify(!builder.hasUnsubmittedChanges)
    }
    function test_automaticTableOnlyEntersForCurrentEligibleParticipant_data() {
        return [{tag: "spectator"}, {tag: "sitting out"}, {tag: "offline"},
            {tag: "already in a room"}, {tag: "different Limited event"},
            {tag: "not all submitted"}, {tag: "closed"}, {tag: "not auto assigned"}]
    }
    function test_automaticTableOnlyEntersForCurrentEligibleParticipant(data) {
        competition()
        submittedDeckSnapshot()
        if (data.tag === "spectator") {
            roomState.participantId = ""
            roomState.role = "observer"
        } else if (data.tag === "sitting out") {
            limitedState.participants = [{participantId: "a", displayName: "Alice", withdrawn: true}]
        } else if (data.tag === "offline") connection.connected = false
        else if (data.tag === "already in a room") connection.inRoom = true
        else if (data.tag === "different Limited event") limitedState.tournamentId = "OTHER1"
        else if (data.tag === "not all submitted") limitedState.allDecksSubmitted = false
        else if (data.tag === "closed") roomState.status = "cancelled"
        roomState.pairings = [data.tag === "not auto assigned" ? pairing("a", "b", "open") : automaticPairing()]
        wait(0)
        compare(connection.calls.length, 0)
        verify(!findChild(page, "cubeDiscardDeckDialog").opened)
    }
    function test_returningToCubeDoesNotReenterConsumedTable() {
        competition()
        submittedDeckSnapshot()
        roomState.pairings = [automaticPairing()]
        tryCompare(connection, "calls", [{name: "open", args: ["casual-1"]}])
        connection.inRoom = true
        roomState.pairings = [pairing("a", "b", "open", "TABLE1")]
        page.destroy()
        wait(0)
        connection.inRoom = false
        connection.calls = []
        page = createTemporaryObject(roomComponent, window.contentItem)
        wait(0)
        compare(connection.calls.length, 0)
    }
    function test_reconnectedParticipantEntersStillPendingTable() {
        competition()
        submittedDeckSnapshot()
        connection.connected = false
        roomState.pairings = [automaticPairing()]
        page.destroy()
        wait(0)
        connection.connected = true
        page = createTemporaryObject(roomComponent, window.contentItem)
        tryCompare(connection, "calls", [{name: "open", args: ["casual-1"]}])
        verify(!findChild(page, "cubeDiscardDeckDialog").opened)
    }
    function test_lostAutoEntryRetriesOnlyAfterFreshSessionProjections_data() {
        return [{tag: "new welcome, unconsumed", consumed: false, welcome: true},
            {tag: "new welcome, consumed", consumed: true, welcome: true},
            {tag: "tournament-only reconnect, unconsumed", consumed: false, welcome: false},
            {tag: "tournament-only reconnect, consumed", consumed: true, welcome: false}]
    }
    function test_lostAutoEntryRetriesOnlyAfterFreshSessionProjections(data) {
        competition()
        submittedDeckSnapshot()
        roomState.pairings = [automaticPairing()]
        tryCompare(connection, "calls", [{name: "open", args: ["casual-1"]}])
        connection.connected = false
        connection.reconnecting = true
        if (data.welcome) connection.welcomeReceived()
        connection.connected = true
        wait(0)
        compare(connection.calls.length, 1)
        limitedState.snapshotChanged()
        wait(0)
        compare(connection.calls.length, 1, "An old public autoEnter flag cannot be reused yet")
        roomState.pairings = [data.consumed ? pairing("a", "b", "open", "TABLE1") : automaticPairing()]
        roomState.snapshotChanged()
        wait(0)
        compare(connection.calls.length, 1, "Room/session restoration must complete first")
        connection.reconnecting = false
        if (data.consumed) {
            wait(0)
            compare(connection.calls.length, 1)
        } else {
            tryVerify(() => connection.calls.length === 2)
            compare(connection.calls[1], {name: "open", args: ["casual-1"]})
            roomState.snapshotChanged()
            limitedState.snapshotChanged()
            wait(0)
            compare(connection.calls.length, 2)
        }
    }
    function test_automaticEntryRechecksEligibilityAfterQueuing() {
        competition()
        submittedDeckSnapshot()
        roomState.pairings = [automaticPairing()]
        connection.inRoom = true
        wait(0)
        compare(connection.calls.length, 0, "Another room acquired before the queued action wins")
    }
    function test_autoEntryConfirmationDoesNotDiscardAfterTableExpires() {
        const builder = editSubmittedDeck()
        limitedState.allDecksSubmitted = true
        roomState.pairings = [automaticPairing()]
        const dialog = findChild(page, "cubeDiscardDeckDialog")
        tryVerify(() => dialog.opened)
        roomState.pairings = []
        findChild(dialog, "confirmButton").clicked()
        compare(connection.calls.length, 0)
        verify(builder.hasUnsubmittedChanges)
    }
    function test_assignedPlayersCannotEditOrInviteOthers() {
        competition()
        page.editingDeck = true
        roomState.pairings = [pairing("a", "b")]
        verify(!page.editingDeck)
        verify(!findChild(page, "cubeDeckModeButton").enabled)
        verify(!findChild(page, "cubeDeckWorkspace").visible)
        roomState.pairings = [pairing("a", "b", "open", "TABLE1")]
        verify(!findChild(page, "cubeCancelInviteButton").visible)
        page.cancelInvitation()
        compare(connection.calls.length, 0)
        roomState.pairings = []
        verify(findChild(page, "cubeDeckModeButton").enabled)
    }
    function test_roomChatRemainsAvailableInNarrowDraftWorkspace() {
        window.width = 760
        window.height = 620
        roomState.status = "running"
        roomState.stage = "draft"
        verify(!page.showInlineChat)
        findChild(page, "cubeRoomInfoButton").clicked()
        const popup = findChild(page, "cubeRoomInfoPopup")
        tryVerify(() => popup.opened)
        page.roomInfoTab = 1
        const input = findChild(popup.contentItem, "tournamentChatInput")
        verify(input.visible)
        compare(input.placeholderText, "Message this room…")
        input.text = "Hello room"
        findChild(popup.contentItem, "tournamentChatSendButton").clicked()
        compare(connection.calls[0].name, "chat")
        compare(connection.calls[0].args[0], "Hello room")
        tryVerify(() => popup.height <= window.height)
        popup.close()
        verify(findChild(page, "cubeDraftWorkspace").visible)
    }
    function test_offlineActionsDisabled() {
        connection.connected = false
        verify(!page.canStart)
        page.setReady()
        page.startDraft()
        competition()
        page.invitePlayer("b")
        roomState.pairings = [pairing("b", "a", "open")]
        page.openMatch()
        page.cancelInvitation()
        compare(connection.calls.length, 0)
    }
    function test_eightSeatsScrollWithoutClippingReadyControls() {
        window.width = 900
        window.height = 620
        roomState.maxPlayers = 8
        roomState.participants = [player("a"), player("b"), player("c"), player("d"),
                                  player("e"), player("f"), player("g"), player("h")]
        const seats = findChild(page, "cubeRoomSeats")
        const ready = findChild(page, "cubeReadyButton")
        tryCompare(seats, "count", 8)
        tryVerify(() => seats.contentHeight > seats.height)
        seats.positionViewAtEnd()
        tryVerify(() => seats.contentY > 0)
        const bottom = ready.mapToItem(window.contentItem, 0, ready.height)
        verify(bottom.y <= window.height)
        verify(ready.visible)
        verify(findChild(page, "cubeStartDraftButton").enabled)
    }
    function test_observerSeesOnlyPublicSeatProgress() {
        roomState.participantId = ""
        roomState.role = "observer"
        roomState.status = "running"
        for (const stage of ["draft", "deck_building"]) {
            roomState.stage = stage
            verify(findChild(page, "cubeRoomSeats").visible)
            verify(!findChild(page, "cubeDraftWorkspace").visible)
            verify(!findChild(page, "cubeDeckWorkspace").visible)
            compare(limitedState.pool.length, 0)
        }
        compare(connection.calls.length, 0)
    }
    function test_onlyOpenedAcceptedMatchesCanBeWatched() {
        competition()
        roomState.participantId = "observer"
        roomState.role = "observer"
        roomState.pairings = [pairing("a", "b")]
        page.watchMatch("TABLE1")
        compare(connection.calls.length, 0)
        roomState.pairings = [pairing("a", "b", "open")]
        page.watchMatch("TABLE1")
        compare(connection.calls.length, 0)
        roomState.pairings = [pairing("a", "b", "open", "TABLE1")]
        page.watchMatch("TABLE1")
        compare(connection.calls[0].name, "watch")
        compare(connection.calls[0].args[0], "TABLE1")
        compare(connection.calls[0].args[1], true)
    }
    function test_pendingInvitationPreservesDirtyEditsUntilExplicitDiscard() {
        const builder = editSubmittedDeck()
        roomState.pairings = [pairing("b", "a")]
        verify(page.hasUnsubmittedDeckChanges)
        verify(builder.cardSelected("physical-2"))
        verify(findChild(page, "cubeUnsubmittedDeckNotice").visible)
        page.invitePlayer("b")
        const dialog = findChild(page, "cubeDiscardDeckDialog")
        tryVerify(() => dialog.opened)
        compare(connection.calls.length, 0)
        findChild(dialog, "cancelButton").clicked()
        verify(builder.cardSelected("physical-2"))
        compare(builder.basicValue("Island"), 38)
        page.cancelInvitation()
        compare(connection.calls[0].name, "cancel")
        roomState.pairings = []
        findChild(page, "cubeDeckModeButton").clicked()
        verify(builder.visible)
        verify(builder.cardSelected("physical-2"))
        roomState.pairings = [pairing("b", "a")]
        page.invitePlayer("b")
        tryVerify(() => dialog.opened)
        findChild(dialog, "confirmButton").clicked()
        compare(connection.calls[1].name, "invite")
        verify(!builder.cardSelected("physical-2"))
        compare(builder.basicValue("Island"), 39)
        verify(!builder.hasUnsubmittedChanges)
    }
    function test_outgoingInvitationRequiresExplicitDiscard() {
        const builder = editSubmittedDeck()
        page.editingDeck = false
        verify(builder.hasUnsubmittedChanges)
        page.invitePlayer("b")
        compare(connection.calls.length, 0)
        const dialog = findChild(page, "cubeDiscardDeckDialog")
        tryVerify(() => dialog.opened)
        findChild(dialog, "confirmButton").clicked()
        compare(connection.calls[0].name, "invite")
        verify(!builder.hasUnsubmittedChanges)
    }
    function test_openAndWatchRequireExplicitDiscard() {
        const builder = editSubmittedDeck()
        roomState.pairings = [pairing("a", "b", "open")]
        page.openMatch()
        const dialog = findChild(page, "cubeDiscardDeckDialog")
        tryVerify(() => dialog.opened)
        compare(connection.calls.length, 0)
        findChild(dialog, "cancelButton").clicked()
        roomState.pairings = [pairing("c", "d", "open", "TABLE2")]
        page.watchMatch("TABLE2")
        tryVerify(() => dialog.opened)
        compare(connection.calls.length, 0)
        findChild(dialog, "confirmButton").clicked()
        compare(connection.calls[0].name, "watch")
        verify(!builder.hasUnsubmittedChanges)
    }
    function test_expiredInvitationConfirmationDoesNotDiscardEdits() {
        const builder = editSubmittedDeck()
        roomState.pairings = [pairing("b", "a")]
        page.invitePlayer("b")
        const dialog = findChild(page, "cubeDiscardDeckDialog")
        tryVerify(() => dialog.opened)
        roomState.pairings = []
        findChild(dialog, "confirmButton").clicked()
        compare(connection.calls.length, 0)
        verify(builder.hasUnsubmittedChanges)
        verify(builder.cardSelected("physical-2"))
    }
    function test_leavingWithDirtyEditsRequiresConfirmation() {
        const builder = editSubmittedDeck()
        roomState.role = "participant"
        page.leaveRoom()
        const dialog = findChild(page, "cubeDiscardDeckDialog")
        tryVerify(() => dialog.opened)
        compare(connection.calls.length, 0)
        findChild(dialog, "cancelButton").clicked()
        verify(builder.hasUnsubmittedChanges)
        roomState.role = "organizer"
        page.leaveRoom()
        const hostDialog = findChild(page, "cubeCloseRoomDialog")
        tryVerify(() => hostDialog.opened)
        verify(hostDialog.message.indexOf("unsubmitted") >= 0)
        findChild(hostDialog, "cancelButton").clicked()
        verify(builder.hasUnsubmittedChanges)
        page.leaveRoom()
        tryVerify(() => hostDialog.opened)
        findChild(hostDialog, "confirmButton").clicked()
        compare(connection.calls[0].name, "leave")
        verify(!builder.hasUnsubmittedChanges)
    }
    function test_submissionAcknowledgementClearsDirtyWithoutResettingSelection() {
        const builder = editSubmittedDeck()
        limitedState.mainboardInstanceIds = ["physical-2", "physical-1"]
        limitedState.basicLands = [{name: "Island", count: 38}]
        limitedState.snapshotChanged()
        verify(!builder.hasUnsubmittedChanges)
        verify(builder.cardSelected("physical-2"))
        builder.adjustBasic("Island", 1)
        verify(builder.hasUnsubmittedChanges)
        builder.adjustBasic("Island", -1)
        verify(!builder.hasUnsubmittedChanges)
    }
    function group(ids, accepted = [ids[0]], status = "invited", roomId = "") {
        return {pairingId: "group-1", playerAId: ids[0], playerBId: ids[1],
            playerIds: ids, playerNames: ids, acceptedPlayerIds: accepted, status: status, roomId: roomId}
    }
    function commanderCompetition() {
        roomState.eventType = "commander_cube"
        roomState.participants = [player("a"), player("b"), player("c"), player("d"), player("e")]
        competition()
        page.editingDeck = false
    }
    function test_commanderSelectsUpToThreeOpponentsAndReservesWholeGroup() {
        commanderCompetition()
        const workspace = findChild(page, "commanderCubeFreePlayWorkspace")
        verify(workspace.visible)
        verify(!findChild(page, "cubeFreePlayWorkspace").visible)
        const invite = findChild(page, "commanderCubeInviteGroupButton")
        verify(!invite.enabled)
        workspace.toggleOpponent("b")
        verify(invite.enabled)
        workspace.toggleOpponent("c")
        workspace.toggleOpponent("d")
        workspace.toggleOpponent("e")
        compare(workspace.selectedOpponents.length, 3)
        invite.clicked()
        compare(connection.calls[0].name, "groupinvite")
        compare(connection.calls[0].args.join(","), "a,b,c,d")
        roomState.pairings = [group(["a", "b", "c", "d"])]
        compare(workspace.selectedOpponents.length, 0)
        compare(page.pairingFor("d").pairingId, "group-1")
        verify(!page.canInviteGroup(["a", "e"]))
        page.invitePlayer("e")
        page.openMatch()
        compare(connection.calls.length, 1)
    }
    function test_fourthPlayerAcceptsOnlyForSelfAndWaitsForEveryone() {
        commanderCompetition()
        roomState.participantId = "d"
        roomState.role = "participant"
        roomState.pairings = [group(["a", "b", "c", "d"], ["a", "b"])]
        verify(page.ownPairing)
        const accept = findChild(page, "commanderCubeAcceptButton")
        verify(accept.visible)
        accept.clicked()
        compare(connection.calls[0].name, "groupresponse")
        compare(connection.calls[0].args[0], "group-1")
        compare(connection.calls[0].args[1], true)
        roomState.pairings = [group(["a", "b", "c", "d"], ["a", "b", "d"])]
        verify(!accept.visible)
        verify(!findChild(page, "commanderCubeOpenButton").visible)
        page.acceptGroup()
        page.openMatch()
        compare(connection.calls.length, 1)
        roomState.pairings = [group(["a", "b", "c", "d"], ["a", "b", "c", "d"], "open")]
        findChild(page, "commanderCubeOpenButton").clicked()
        compare(connection.calls[1].name, "open")
        page.cancelInvitation()
        compare(connection.calls[2].name, "groupresponse")
        compare(connection.calls[2].args[1], false)
    }
    function test_groupSelectionDropsUnavailableOpponentsWithoutBlockingNewInvites() {
        commanderCompetition()
        const workspace = findChild(page, "commanderCubeFreePlayWorkspace")
        workspace.toggleOpponent("b")
        workspace.toggleOpponent("c")
        roomState.pairings = [group(["b", "d"])]
        compare(workspace.selectedOpponents.join(","), "c")
        verify(findChild(page, "commanderCubeInviteGroupButton").enabled)
        roomState.participants = [player("a"), player("b"), player("c", true, false), player("d"), player("e")]
        compare(workspace.selectedOpponents.length, 0)
        workspace.toggleOpponent("e")
        findChild(page, "commanderCubeInviteGroupButton").clicked()
        compare(connection.calls[0].args.join(","), "a,e")
    }
    function test_groupGuardRevalidatesAvailabilityBeforeDiscardingEdits() {
        const builder = editSubmittedDeck()
        commanderCompetition()
        page.inviteGroup(["a", "b", "c", "d"])
        const dialog = findChild(page, "cubeDiscardDeckDialog")
        tryVerify(() => dialog.opened)
        roomState.pairings = [group(["c", "e"])]
        findChild(dialog, "confirmButton").clicked()
        compare(connection.calls.length, 0)
        verify(builder.hasUnsubmittedChanges)
        roomState.pairings = [group(["b", "c", "a"])]
        page.acceptGroup()
        tryVerify(() => dialog.opened)
        findChild(dialog, "confirmButton").clicked()
        compare(connection.calls[0].name, "groupresponse")
        verify(!builder.hasUnsubmittedChanges)
    }
    function test_groupInviteFooterRemainsReachableAtMinimumSize() {
        window.width = 900
        window.height = 620
        commanderCompetition()
        const workspace = findChild(page, "commanderCubeFreePlayWorkspace")
        const invite = findChild(page, "commanderCubeInviteGroupButton")
        workspace.toggleOpponent("b")
        waitForRendering(workspace)
        const bottom = invite.mapToItem(window.contentItem, 0, invite.height)
        verify(invite.visible && invite.enabled)
        verify(bottom.y <= window.height)
    }
}
