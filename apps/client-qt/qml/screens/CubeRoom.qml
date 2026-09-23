// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import "../components"

Page {
    id: root
    objectName: "cubeRoomScreen"
    property var tournamentModel: tournament
    property var limitedModel: limited
    property var wsModel: ws
    property var cardCatalogModel: cardCatalog
    property bool editingDeck: false
    property int roomInfoTab: 0
    property string guardedAction: ""
    property string guardedTarget: ""
    property string guardedPairingId: ""
    property string autoDraftTarget: ""
    property string attemptedAutoEnterKey: ""
    property bool componentReady: false
    property bool awaitingTournamentRefresh: false
    property bool awaitingLimitedRefresh: false
    property double currentTime: Date.now()
    readonly property var appWindow: ApplicationWindow.window
    readonly property bool connected: wsModel.connected !== false
    readonly property bool isHost: tournamentModel.role === "organizer"
    readonly property bool isParticipant: !!tournamentModel.participantId
    readonly property bool commanderCube: tournamentModel.eventType === "commander_cube"
    readonly property var selfParticipant: participantFor(tournamentModel.participantId)
    readonly property var selfProgress: progressFor(tournamentModel.participantId)
    readonly property bool sittingOut: !!selfProgress.withdrawn
    readonly property bool automaticDraft: !!selfProgress.autoDraft
    readonly property bool selfReady: !!selfParticipant && !!selfParticipant.checkedIn
    readonly property var ownPairing: pairingFor(tournamentModel.participantId)
    readonly property bool hasUnsubmittedDeckChanges: builder.hasUnsubmittedChanges
    readonly property string roomStage: tournamentModel.stage
    readonly property bool closed: tournamentModel.status === "cancelled" || tournamentModel.status === "completed"
    readonly property string autoEnterKey: ownPairing
        ? JSON.stringify([wsModel.serverUrl || "", tournamentModel.tournamentId,
            tournamentModel.participantId, ownPairing.pairingId]) : ""
    readonly property bool autoEnterReady: componentReady && visible && connected && !closed
        && !awaitingTournamentRefresh && !awaitingLimitedRefresh && wsModel.reconnecting !== true
        && isParticipant && !!selfParticipant && !!selfParticipant.competing && !selfParticipant.dropped
        && !sittingOut && wsModel.inRoom !== true && roomStage === "competition"
        && limitedModel.tournamentId === tournamentModel.tournamentId
        && limitedModel.stage === "competition" && limitedModel.deckSubmitted === true
        && limitedModel.allDecksSubmitted === true && !!ownPairing
        && ownPairing.status === "open" && ownPairing.autoEnter === true
    readonly property bool canStart: connected && isHost && roomStage === "registration"
        && tournamentModel.participants.length >= 2
        && tournamentModel.participants.every(player => !!player.online && !!player.checkedIn)
    readonly property bool focusedWorkspace: !closed && isParticipant
        && (roomStage === "draft" || roomStage === "deck_building"
            || (roomStage === "competition" && editingDeck && !ownPairing))
    readonly property bool showInlineChat: !focusedWorkspace && width >= Theme.size(1050)
    readonly property string stageLabel: closed ? qsTr("Room closed")
        : roomStage === "registration" ? qsTr("Waiting for players")
        : roomStage === "draft" ? qsTr("Drafting")
        : roomStage === "deck_building" ? qsTr("Deck building") : qsTr("Free play")

    onRoomStageChanged: {
        if (roomStage === "deck_building")
            editingDeck = true
    }
    onOwnPairingChanged: {
        if (ownPairing)
            editingDeck = false
    }
    onAutoEnterReadyChanged: Qt.callLater(tryAutomaticallyOpenMatch)
    onAutoEnterKeyChanged: Qt.callLater(tryAutomaticallyOpenMatch)
    onConnectedChanged: {
        // Tournament-only reconnects intentionally do not emit welcomeReceived.
        // Observe this bound property, whose source uses connectionStateChanged.
        if (!connected) awaitAutoEntrySessionRefresh()
    }
    Component.onCompleted: {
        editingDeck = roomStage === "deck_building"
        componentReady = true
        Qt.callLater(tryAutomaticallyOpenMatch)
    }
    Connections {
        target: root.limitedModel
        ignoreUnknownSignals: true
        function onSnapshotChanged() {
            root.awaitingLimitedRefresh = false
            // Reconcile the builder's submitted-deck baseline before consulting
            // its dirty guard; tournament and private Limited snapshots differ.
            Qt.callLater(root.tryAutomaticallyOpenMatch)
        }
    }
    Connections {
        target: root.tournamentModel
        ignoreUnknownSignals: true
        function onSnapshotChanged() { root.awaitingTournamentRefresh = false }
    }
    Connections {
        target: root.wsModel
        ignoreUnknownSignals: true
        function onWelcomeReceived() {
            // A command lost with the old connection may be retried once after
            // fresh projections confirm this participant still needs to enter.
            root.awaitAutoEntrySessionRefresh()
        }
    }
    background: AppBackground { }
    Timer {
        interval: 1000
        running: roomPopup.visible && root.roomStage === "draft"
        repeat: true
        onTriggered: root.currentTime = Date.now()
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.topMargin: Theme.size(16)
        anchors.bottomMargin: Theme.size(20)
        anchors.leftMargin: Theme.pageMargin
        anchors.rightMargin: Theme.pageMargin
        spacing: Theme.size(12)

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.size(12)
            AppButton {
                objectName: "cubeLeaveRoomButton"
                variant: "ghost"
                compact: true
                text: qsTr("Leave room")
                leadingText: "‹"
                onClicked: root.leaveRoom()
            }
            ColumnLayout {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                spacing: Theme.size(3)
                Text {
                    textFormat: Text.PlainText
                    Layout.fillWidth: true
                    text: root.tournamentModel.name || qsTr("Cube room")
                    color: Theme.text
                    font.pixelSize: Theme.fontSize(23)
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }
                Text {
                    textFormat: Text.PlainText
                    objectName: "cubeRoomSummary"
                    Layout.fillWidth: true
                    text: qsTr("Room code: %1").arg(root.tournamentModel.tournamentId)
                          + " · " + root.stageLabel
                          + " · " + (root.tournamentModel.matchMode === "bo3" ? qsTr("BO 3") : qsTr("BO 1"))
                          + " · " + (root.tournamentModel.rulesMode === "forge" ? qsTr("Forge rules") : qsTr("Manual tabletop"))
                    color: Theme.textMuted
                    font.pixelSize: Theme.fontSize(12)
                    elide: Text.ElideRight
                }
            }
            AppButton {
                objectName: "cubeDeckModeButton"
                visible: !root.closed && root.roomStage === "competition"
                compact: true
                text: root.editingDeck ? qsTr("Choose opponent") : qsTr("Edit deck")
                enabled: root.isParticipant && !root.ownPairing
                onClicked: root.editingDeck = !root.editingDeck
            }
            AppButton {
                objectName: "cubeRoomInfoButton"
                compact: true
                text: qsTr("Room / chat")
                onClicked: roomPopup.open()
            }
        }

        InfoBanner {
            Layout.fillWidth: true
            message: root.wsModel.lastError ? I18n.status(root.wsModel.lastError)
                     : !root.connected ? qsTr("Connection lost. Your draft and deck are preserved while reconnecting.") : ""
            tone: root.wsModel.lastError ? "error" : "warning"
        }

        RowLayout {
            Layout.fillWidth: true
            visible: !root.closed && (root.roomStage === "draft" && root.automaticDraft || root.sittingOut)
            Text {
                textFormat: Text.PlainText
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                text: root.automaticDraft && root.roomStage === "draft"
                    ? qsTr("Auto-draft is active. Your seat and pool remain private.")
                    : qsTr("You are sitting out. Your seat, pool and deck are preserved.")
                color: Theme.warning
                font.pixelSize: Theme.fontSize(12)
                wrapMode: Text.WordWrap
            }
            AppButton {
                objectName: "cubeReclaimControlButton"
                compact: true
                visible: root.roomStage === "draft" && root.automaticDraft
                enabled: root.connected
                text: qsTr("Reclaim control")
                onClicked: root.reclaimDraft()
            }
        }

        RowLayout {
            Layout.fillWidth: true
            visible: !root.closed && root.roomStage === "competition" && !root.focusedWorkspace
            Text {
                textFormat: Text.PlainText
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                text: root.editingDeck
                      ? qsTr("Everyone has a deck ready. Submit any changes before choosing an opponent.")
                      : qsTr("Use your drafted deck to play anyone in this room.")
                color: Theme.textSecondary
                font.pixelSize: Theme.fontSize(12)
                wrapMode: Text.WordWrap
            }
        }

        InfoBanner {
            objectName: "cubeUnsubmittedDeckNotice"
            Layout.fillWidth: true
            tone: "warning"
            message: !root.focusedWorkspace && root.roomStage === "competition" && root.hasUnsubmittedDeckChanges
                     ? root.ownPairing
                       ? qsTr("Your unsubmitted deck edits are preserved. Decline or cancel this invitation or match to continue editing, or explicitly discard the edits before playing.")
                       : qsTr("You have unsubmitted deck edits. Submit them in Edit deck before playing, or explicitly discard them to use your last submitted deck.")
                     : ""
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumHeight: 0
            spacing: Theme.size(14)

            Surface {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumWidth: 0
                Layout.minimumHeight: 0
                color: Theme.surfaceMuted
                Item {
                    anchors.fill: parent
                    anchors.margins: Theme.size(16)
                    CubeRoomSeats {
                        anchors.fill: parent
                        visible: !root.closed && (root.roomStage === "registration"
                                 || (!root.isParticipant && (root.roomStage === "draft"
                                                            || root.roomStage === "deck_building")))
                        roomController: root
                        tournamentModel: root.tournamentModel
                        limitedModel: root.limitedModel
                        showControls: root.isParticipant
                    }
                    LimitedDraftView {
                        objectName: "cubeDraftWorkspace"
                        anchors.fill: parent
                        visible: !root.closed && root.roomStage === "draft" && root.isParticipant
                        limitedModel: root.limitedModel
                        tournamentModel: root.tournamentModel
                        wsModel: root.wsModel
                        cardCatalogModel: root.cardCatalogModel
                    }
                LimitedDeckBuilder {
                    id: builder
                    cubeFreePlay: true
                        objectName: "cubeDeckWorkspace"
                        anchors.fill: parent
                        visible: !root.closed && root.isParticipant && !root.ownPairing
                                 && (root.roomStage === "deck_building"
                                     || (root.roomStage === "competition" && root.editingDeck))
                        enabled: root.connected
                        participantId: root.tournamentModel.participantId
                        limitedModel: root.limitedModel
                        wsModel: root.wsModel
                        cardCatalogModel: root.cardCatalogModel
                    }
                    CubeRoomMatches {
                        objectName: "cubeFreePlayWorkspace"
                        anchors.fill: parent
                        visible: !root.commanderCube && !root.closed && root.roomStage === "competition"
                                 && (!root.editingDeck || !!root.ownPairing)
                        roomController: root
                        tournamentModel: root.tournamentModel
                    }
                    CommanderCubeMatches {
                        objectName: "commanderCubeFreePlayWorkspace"
                        anchors.fill: parent
                        visible: root.commanderCube && !root.closed && root.roomStage === "competition"
                                 && (!root.editingDeck || !!root.ownPairing)
                        roomController: root
                        tournamentModel: root.tournamentModel
                    }
                    Text {
                        textFormat: Text.PlainText
                        anchors.centerIn: parent
                        width: parent.width
                        visible: root.closed
                        text: qsTr("This Cube room is closed.")
                        color: Theme.textMuted
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WordWrap
                        font.pixelSize: Theme.fontSize(18)
                    }
                }
            }

            TournamentChat {
                Layout.preferredWidth: Theme.size(300)
                Layout.fillHeight: true
                Layout.minimumHeight: 0
                visible: root.showInlineChat
                tournamentModel: root.tournamentModel
                wsModel: root.wsModel
                caption: qsTr("Room chat · visible to everyone in this room")
                placeholderText: qsTr("Message this room…")
            }
        }
    }

    Popup {
        id: roomPopup
        objectName: "cubeRoomInfoPopup"
        parent: Overlay.overlay
        width: Math.min(Theme.size(420), parent ? parent.width - Theme.size(24) : 420)
        height: Math.min(Theme.size(680), parent ? parent.height - Theme.size(32) : 680)
        x: parent ? parent.width - width - Theme.size(16) : 0
        y: Theme.size(16)
        modal: true
        focus: true
        padding: Theme.size(14)
        background: Surface { elevated: true }
        onOpened: root.currentTime = Date.now()
        contentItem: ColumnLayout {
            spacing: Theme.size(12)
            RowLayout {
                Layout.fillWidth: true
                Text {
                    textFormat: Text.PlainText
                    Layout.fillWidth: true
                    text: qsTr("Room code: %1").arg(root.tournamentModel.tournamentId)
                    color: Theme.accent
                    font.pixelSize: Theme.fontSize(16)
                }
                AppButton {
                    compact: true
                    variant: "ghost"
                    text: qsTr("Close")
                    objectName: "cubeRoomInfoCloseButton"
                    onClicked: roomPopup.close()
                }
            }
            Text {
                textFormat: Text.PlainText
                Layout.fillWidth: true
                text: qsTr("Host: %1").arg(root.tournamentModel.organizerName)
                color: Theme.textMuted
                font.pixelSize: Theme.fontSize(12)
                elide: Text.ElideRight
            }
            SegmentedControl {
                Layout.fillWidth: true
                objectName: "cubeRoomInfoTabs"
                options: [qsTr("Seats"), qsTr("Chat"), qsTr("Rules")]
                currentIndex: root.roomInfoTab
                onActivated: index => root.roomInfoTab = index
            }
            CubeRoomSeats {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumHeight: 0
                visible: root.roomInfoTab === 0
                roomController: root
                tournamentModel: root.tournamentModel
                limitedModel: root.limitedModel
                showControls: false
            }
            TournamentChat {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumHeight: 0
                visible: root.roomInfoTab === 1
                tournamentModel: root.tournamentModel
                wsModel: root.wsModel
                caption: qsTr("Room chat · visible to everyone in this room")
                placeholderText: qsTr("Message this room…")
            }
            CubeRoomRules {
                objectName: "cubeRoomRules"
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumHeight: 0
                visible: root.roomInfoTab === 2
                commanderCube: root.commanderCube
                matchMode: root.tournamentModel.matchMode
                draftSettings: root.tournamentModel.draftSettings || ({packsPerPlayer: 3, packsPerBatch: 1})
            }
        }
    }

    ConfirmDialog {
        id: autoDraftDialog
        objectName: "cubeAutoDraftDialog"
        titleText: qsTr("Enable auto-draft for %1?").arg((root.participantFor(root.autoDraftTarget) || {}).displayName || "")
        message: qsTr("The server will pick randomly for this seat without revealing its pool. The player can reclaim control when they return.")
        confirmText: qsTr("Enable auto-draft")
        onConfirmed: {
            if (root.canEnableAutoDraft(root.autoDraftTarget))
                root.wsModel.setLimitedDraftControl(root.autoDraftTarget, true)
        }
    }
    ConfirmDialog {
        id: sitOutDialog
        objectName: "cubeSitOutDialog"
        titleText: qsTr("Sit out of free play?")
        message: qsTr("Your seat, pool, submitted deck and local edits are kept. Others can continue without waiting for your deck. You can submit and rejoin later. This does not close the room.")
        confirmText: qsTr("Sit out")
        onConfirmed: {
            if (root.canChangeParticipation(false)) root.wsModel.setLimitedParticipation(false)
        }
    }

    ConfirmDialog {
        id: leaveDialog
        objectName: "cubeCloseRoomDialog"
        titleText: qsTr("Close Cube room?")
        message: qsTr("Leaving as host closes this room for everyone. No new drafts or matches can be started.")
                 + (root.hasUnsubmittedDeckChanges ? "\n\n" + qsTr("Your unsubmitted deck edits will also be discarded.") : "")
        confirmText: qsTr("Close room")
        dangerous: true
        onConfirmed: {
            builder.discardUnsubmittedChanges()
            root.wsModel.leaveTournament()
        }
    }

    ConfirmDialog {
        id: discardDialog
        objectName: "cubeDiscardDeckDialog"
        titleText: qsTr("Discard unsubmitted deck edits?")
        message: root.guardedAction === "leave"
                 ? qsTr("Your deck has unsubmitted edits. Discard them and leave the room?")
                 : qsTr("This action uses your last submitted deck. Discard your unsubmitted edits and continue, or cancel to keep editing.")
        confirmText: qsTr("Discard and continue")
        dangerous: true
        onConfirmed: root.confirmGuardedAction()
        onCancelled: root.clearGuardedAction()
    }

    function participantFor(id) {
        if (!id) return null
        for (const player of tournamentModel.participants || []) {
            if (player.participantId === id) return player
        }
        return null
    }
    function progressFor(id) {
        return (limitedModel.participants || []).find(player => player.participantId === id) || {}
    }
    function canEnableAutoDraft(id) {
        if (!connected || closed || roomStage !== "draft" || !id || progressFor(id).autoDraft) return false
        const player = participantFor(id)
        if (!player) return false
        if (id === tournamentModel.participantId) return true
        // The timestamp only drives the affordance. The server rechecks elapsed
        // offline time and authorization when the command arrives.
        const disconnected = Date.parse(player.disconnectedAt || "")
        return isHost && !player.online && isFinite(disconnected) && currentTime - disconnected > 180000
    }
    function requestAutoDraft(id) {
        if (!canEnableAutoDraft(id)) return
        autoDraftTarget = id
        autoDraftDialog.open()
    }
    function reclaimDraft() {
        if (connected && !closed && roomStage === "draft" && automaticDraft && isParticipant)
            wsModel.setLimitedDraftControl(tournamentModel.participantId, false)
    }
    function canChangeParticipation(participating) {
        return connected && !closed && isParticipant && !ownPairing
            && (roomStage === "deck_building" || roomStage === "competition")
            && participating === sittingOut
            && (!participating || roomStage !== "competition" || !!limitedModel.deckSubmitted)
    }
    function changeParticipation() {
        if (!canChangeParticipation(sittingOut)) return
        if (sittingOut) wsModel.setLimitedParticipation(true)
        else sitOutDialog.open()
    }
    function pairingFor(id) {
        if (!id) return null
        for (const pairing of tournamentModel.pairings || []) {
            if (pairing.playerIds && pairing.playerIds.length > 0) {
                if (pairing.playerIds.indexOf(id) >= 0) return pairing
            } else if (pairing.playerAId === id || pairing.playerBId === id) return pairing
        }
        return null
    }
    function leaveRoom() {
        if (isHost && !closed) leaveDialog.open()
        else if (guardDeckEdits("leave", "")) wsModel.leaveTournament()
    }
    function setReady() {
        if (connected && isParticipant && roomStage === "registration")
            wsModel.setTournamentCheckedIn(!selfReady)
    }
    function startDraft() {
        if (canStart) wsModel.startTournament()
    }
    function canInvitePlayer(id) {
        if (commanderCube || !connected || closed || sittingOut || roomStage !== "competition" || !isParticipant || id === tournamentModel.participantId)
            return false
        const player = participantFor(id)
        if (!player || !player.online || player.dropped) return false
        const assignment = pairingFor(id)
        if (assignment && (!ownPairing || assignment.pairingId !== ownPairing.pairingId)) return false
        if (ownPairing && !(ownPairing.status === "invited"
                           && ownPairing.playerBId === tournamentModel.participantId
                           && ownPairing.playerAId === id)) return false
        return true
    }
    function invitePlayer(id) {
        if (canInvitePlayer(id) && guardDeckEdits("invite", id))
            wsModel.createLimitedCasualMatch(tournamentModel.participantId, id)
    }
    function cancelInvitation() {
        if (connected && ownPairing && !ownPairing.roomId) {
            if (commanderCube) wsModel.respondCommanderCubeInvitation(ownPairing.pairingId, false)
            else wsModel.cancelLimitedCasualMatch(ownPairing.playerAId, ownPairing.playerBId)
        }
    }
    function canInviteGroup(ids) {
        if (!commanderCube || !connected || closed || sittingOut || roomStage !== "competition"
                || !isParticipant || ownPairing || ids.length < 2 || ids.length > 4
                || ids[0] !== tournamentModel.participantId) return false
        for (let index = 0; index < ids.length; ++index) {
            const player = participantFor(ids[index])
            if (!player || !player.online || player.dropped || !player.competing
                    || pairingFor(ids[index]) || ids.indexOf(ids[index]) !== index) return false
        }
        return true
    }
    function inviteGroup(ids) {
        if (canInviteGroup(ids) && guardDeckEdits("groupinvite", JSON.stringify(ids)))
            wsModel.inviteCommanderCubePlayers(ids)
    }
    function canAcceptGroup(id) {
        return commanderCube && connected && !closed && roomStage === "competition"
            && !!ownPairing && ownPairing.pairingId === id && ownPairing.status === "invited"
            && (ownPairing.acceptedPlayerIds || []).indexOf(tournamentModel.participantId) < 0
    }
    function acceptGroup() {
        if (ownPairing && canAcceptGroup(ownPairing.pairingId)
                && guardDeckEdits("groupaccept", ownPairing.pairingId))
            wsModel.respondCommanderCubeInvitation(ownPairing.pairingId, true)
    }
    function canOpenMatch() {
        return connected && !closed && wsModel.inRoom !== true && wsModel.reconnecting !== true
            && roomStage === "competition"
            && !!ownPairing && ownPairing.status === "open"
    }
    function tryAutomaticallyOpenMatch() {
        if (!autoEnterReady || attemptedAutoEnterKey === autoEnterKey || guardedAction) return
        // A rejected command or cancelled dirty-edit confirmation must not loop.
        // The existing Open match action remains available for an explicit retry.
        attemptedAutoEnterKey = autoEnterKey
        openMatch()
    }
    function awaitAutoEntrySessionRefresh() {
        awaitingTournamentRefresh = true
        awaitingLimitedRefresh = true
        attemptedAutoEnterKey = ""
    }
    function openMatch() {
        if (!canOpenMatch()) return
        if (ownPairing.autoEnter === true) attemptedAutoEnterKey = autoEnterKey
        if (guardDeckEdits("open", ownPairing.pairingId)) wsModel.openTournamentMatch(ownPairing.pairingId)
    }
    function canWatchMatch(roomId) {
        if (!connected || !roomId || ownPairing || closed || roomStage !== "competition") return false
        for (const pairing of tournamentModel.pairings || []) {
            if (pairing.roomId === roomId && pairing.status === "open") return true
        }
        return false
    }
    function watchMatch(roomId) {
        if (canWatchMatch(roomId) && guardDeckEdits("watch", roomId))
            wsModel.joinRoom(roomId, true, "")
    }
    function guardDeckEdits(action, target) {
        if (!hasUnsubmittedDeckChanges) return true
        guardedAction = action
        guardedTarget = target
        guardedPairingId = ownPairing ? ownPairing.pairingId : ""
        discardDialog.open()
        return false
    }
    function clearGuardedAction() {
        guardedAction = ""
        guardedTarget = ""
        guardedPairingId = ""
        Qt.callLater(tryAutomaticallyOpenMatch)
    }
    function confirmGuardedAction() {
        const action = guardedAction
        const target = guardedTarget
        const pairingId = guardedPairingId
        clearGuardedAction()
        // An invitation may be withdrawn while the confirmation is open.
        // Never discard edits for an action that is no longer available.
        if (action !== "leave" && (ownPairing ? ownPairing.pairingId : "") !== pairingId) return
        if (action === "invite" && !canInvitePlayer(target)) return
        const group = action === "groupinvite" ? JSON.parse(target) : []
        if (action === "groupinvite" && !canInviteGroup(group)) return
        if (action === "groupaccept" && !canAcceptGroup(target)) return
        if (action === "open" && (!canOpenMatch() || ownPairing.pairingId !== target)) return
        if (action === "watch" && !canWatchMatch(target)) return
        if (["invite", "groupinvite", "groupaccept", "open", "watch", "leave"].indexOf(action) < 0) return
        builder.discardUnsubmittedChanges()
        if (action === "invite") invitePlayer(target)
        else if (action === "groupinvite") inviteGroup(group)
        else if (action === "groupaccept") acceptGroup()
        else if (action === "open") openMatch()
        else if (action === "watch") watchMatch(target)
        else wsModel.leaveTournament()
    }
}
