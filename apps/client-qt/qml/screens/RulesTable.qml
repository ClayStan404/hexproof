// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls.Basic
import "../components"

Page {
    id: root

    required property var wsModel
    required property var cardCatalogModel
    required property var gameTableModel
    required property var sideboardTableModel
    property var preferencesModel: null
    readonly property var rulesSession: wsModel.rulesSession
    readonly property var gameSession: wsModel.gameSession
    readonly property bool roomConnected: wsModel.inRoom === true
    readonly property bool hostingPaused: roomSession.hostingMode === "player" && (roomSession.hostConnected !== true
        || roomSession.hostStatus && roomSession.hostStatus.migrating === true)
    readonly property bool sideboarding: gameSession.sideboarding === true
    readonly property bool rulesResponsePending: wsModel.rulesResponsePending === true
    readonly property bool canConcede: roomConnected && !hostingPaused && localSeat >= 0
                                       && rulesSession.active && !rulesSession.gameOver
                                       && !sideboarding && !matchUi.matchFinished
    readonly property var matchUi: matchControls
    readonly property var tableGameLog: gameTableModel.gameLog
    readonly property var presentation: tablePresentation.item
    readonly property var inspector: presentation ? presentation.inspectionDock.inspector : null
    readonly property real gameLogRailWidth: gameLogRail ? gameLogRail.width : 0
    readonly property var gameLogRail: presentation ? presentation.inspectionDock.logRail : null
    readonly property var cardActionPicker: presentation ? presentation.decisionDock.actionPicker : null
    readonly property var interaction: tableInteraction
    readonly property var priority: priorityController
    readonly property var combatInteraction: combatInteraction
    readonly property bool priorityInputBlocked: hostingPaused || backgroundPopup.opened
        || rulesConcedeConfirmation.opened || matchUi.modalOpen === true
        || (presentation && presentation.modalOpen === true)
    property bool showGameLogRail: roomSession.maxSeats > 2
        ? (preferencesModel ? preferencesModel.tableShowGameLog : true) : false
    readonly property bool canChat: roomConnected && roomSession.phase === "started"
                                   && (roomSession.role === "player"
                                       || roomSession.role === "spectator")
    readonly property var cardActions: chatActions
    readonly property var roomSession: wsModel.roomSession
    readonly property url cardBackSource:
        Qt.resolvedUrl("../assets/card-back.jpg")
    readonly property int localSeat:
        roomSession.role === "player" ? roomSession.seatIndex : -1
    readonly property bool canViewSpectatorHands:
        roomConnected && rulesSession.active && !sideboarding
        && roomSession.role === "spectator"
        && roomSession.spectatorsSeeHands === true
    property int spectatedHandSeat: 0
    readonly property int handOwnerSeat:
        localSeat >= 0 ? localSeat
                      : canViewSpectatorHands ? spectatedHandSeat : -1

    onCanViewSpectatorHandsChanged: {
        if (!canViewSpectatorHands)
            spectatedHandSeat = 0
    }
    readonly property bool compactLayout: Theme.isCompactWidth(width)
    readonly property bool stackTargetsVisible: !sideboarding && (roomSession.maxSeats <= 2 || !compactLayout)
    readonly property bool persistentInspectionDock: width >= Theme.size(1180)
    readonly property real inspectionDockWidth: Math.min(Theme.size(320),
                                                         Math.max(Theme.size(230), width * 0.2))
    readonly property real maximumDecisionHeight: Math.min(Theme.size(270), height * 0.34)
    readonly property real actionRailWidth:
        Theme.size(compactLayout ? 120 : 144)
    readonly property real sharedZoneRailWidth: Theme.size(92)
    readonly property real battlefieldCardWidth: Theme.size(80)
    readonly property real battlefieldCardHeight:
        Math.round(battlefieldCardWidth * 88 / 63)
    readonly property real handAreaHeight: Theme.size(176)
    readonly property real handCardWidth: Theme.size(86)
    readonly property real handCardHeight:
        Math.round(handCardWidth * 88 / 63)
    readonly property real zoneDockWidth:
        Math.min(Theme.size(270), width * 0.35)

    onRulesResponsePendingChanged: {
        if (rulesResponsePending && cardActionPicker)
            cardActionPicker.close()
    }

    function setGameLogVisible(show) {
        showGameLogRail = show
        if (show && inspector)
            inspector.clear()
        if (preferencesModel && !compactLayout)
            preferencesModel.tableShowGameLog = show
    }

    onCompactLayoutChanged: {
        if (compactLayout) showGameLogRail = false
        else if (roomSession.maxSeats > 2)
            showGameLogRail = preferencesModel ? preferencesModel.tableShowGameLog : true
    }

    QtObject {
        id: chatActions
        function submitChatMessage() {
            if (!gameLogRail) return false
            const message = gameLogRail.chatInput.text.trim()
            if (!root.canChat || message.length === 0)
                return false
            root.wsModel.sayGameMessage(message)
            gameLogRail.chatInput.clear()
            gameLogRail.chatInput.forceActiveFocus()
            return true
        }
    }

    RulesMatchControls {
        id: matchControls
        tableController: root
    }

    RulesTableInteraction {
        id: tableInteraction
        tableController: root
    }

    ForgeCombatInteraction {
        id: combatInteraction
        tableController: root
    }

    RulesPriorityController {
        id: priorityController
        tableController: root
    }

    function zoneCount(ownerSeat, zone) {
        // Q_INVOKABLE calls do not create dependencies on their C++ model data.
        // Observe complete snapshots, including zone-only changes in one turn.
        void rulesSession.snapshotRevision
        return rulesSession.zoneCount(ownerSeat, zone)
    }

    function topPublicZoneCard(ownerSeat, zone) {
        void rulesSession.snapshotRevision
        if (!rulesSession || typeof rulesSession.topPublicZoneCard !== "function")
            return ({})
        return rulesSession.topPublicZoneCard(ownerSeat, zone)
    }

    function zoneLabel(zone) {
        switch (zone) {
        case "library": return qsTr("Library")
        case "hand": return qsTr("Hand")
        case "battlefield": return qsTr("Battlefield")
        case "graveyard": return qsTr("Graveyard")
        case "exile": return qsTr("Exile")
        case "command": return qsTr("Command zone")
        default: return zone
        }
    }

    function stepLabel(step) {
        switch (step) {
        case "untap": return qsTr("Untap")
        case "upkeep": return qsTr("Upkeep")
        case "draw": return qsTr("Draw")
        case "main1": return qsTr("First main phase")
        case "begin_combat": return qsTr("Beginning of combat")
        case "declare_attackers": return qsTr("Declare attackers")
        case "declare_blockers": return qsTr("Declare blockers")
        case "combat_damage": return qsTr("Combat damage")
        case "end_combat": return qsTr("End of combat")
        case "main2": return qsTr("Second main phase")
        case "end": return qsTr("End step")
        case "cleanup": return qsTr("Cleanup")
        default: return step.length > 0 ? step : qsTr("Waiting for Forge")
        }
    }

    function openCardDetails(cardId) {
        if (inspector) inspector.showCard(cardId)
    }

    function previewCard(cardId, source) {
        if (roomConnected && !sideboarding && inspector
                && (!presentation.suppressHoverDuringDecision || !rulesSession.promptPending || priority.isPriorityPrompt))
            inspector.previewCard(cardId, source)
    }

    function endCardPreview(source) {
        if (inspector) inspector.hidePreview(source)
    }

    function cardImage(name, setCode, collectorNumber) {
        if (!name || !cardCatalogModel
                || typeof cardCatalogModel.tableImageSource !== "function")
            return ""
        void cardCatalogModel.imageRevision
        return cardCatalogModel.tableImageSource(
                    name, setCode || "", collectorNumber || "")
    }

    function promptOptionLabel(kind, responseId, label) {
        if (kind === "diceRolled" && responseId === "$ack")
            return qsTr("Roll dice")
        switch (responseId) {
        case "$ack": return qsTr("Continue")
        case "$pass": return qsTr("Pass priority")
        case "$pass-stack": return qsTr("Resolve current stack")
        case "$keep": return qsTr("Keep hand")
        case "$mulligan": return qsTr("Take a mulligan")
        case "$pay": return qsTr("Confirm payment")
        case "$auto-pay": return qsTr("Auto-pay")
        case "$cancel": return qsTr("Cancel")
        default: return RulesText.text(label)
        }
    }

    function promptTitle(kind, title) {
        if (kind === "diceRolled")
            return qsTr("Roll to determine the first player")
        return RulesText.title(kind, title, rulesSession.promptDetail)
    }

    function promptDetail(kind, detail) {
        if (kind === "diceRolled")
            return qsTr("Forge will roll to determine who plays first.")
        return RulesText.text(detail)
    }

    function handCardActions(cardId) {
        return interaction.actionsForCard(cardId).filter(
                    action => action.kind === "cast" || action.kind === "playLand")
    }

    function canDragHandCard(cardId) {
        return cardActionPicker && !cardActionPicker.opened
                && handCardActions(cardId).length > 0
    }

    function playDraggedHandCard(cardId, cardName) {
        const actions = handCardActions(cardId)
        if (actions.length === 0)
            return false
        if (actions.length === 1) {
            return interaction.submitCardAction(cardId, actions[0].responseId)
        } else {
            cardActionPicker.showFor(cardId, cardName, actions)
        }
        return true
    }

    function playDraggedHandCardSource(source) {
        if (!source)
            return false
        return playDraggedHandCard(source.cardId, source.name)
    }

    Keys.onSpacePressed: event => {
        event.accepted = priority.passOnce()
    }

    Keys.onEscapePressed: event => {
        if (priority.yieldMode.length > 0) {
            priority.cancelYield()
            event.accepted = true
        } else if (inspector && presentation.inspectionDock.inspectionOpened) {
            inspector.clear()
            event.accepted = true
        } else {
            event.accepted = false
        }
    }

    function openConcedeConfirmation() {
        if (!canConcede)
            return
        rulesConcedeConfirmation.gameId = rulesSession.gameId
        if (rulesConcedeConfirmation.validForCurrentGame())
            rulesConcedeConfirmation.open()
    }

    function openBackgroundPicker() {
        backgroundPopup.open()
    }

    TableBackgroundPopup {
        id: backgroundPopup
        preferencesModel: root.preferencesModel
    }

    background: AppBackground {
        variant: "playmat"
    }

    Loader {
        id: tablePresentation
        anchors.fill: parent
        sourceComponent: root.roomSession.maxSeats > 2 ? legacyLayout : duelLayout
    }
    Component {
        id: duelLayout
        ForgeDuelTable { tableController: root }
    }
    Component {
        id: legacyLayout
        RulesLegacyLayout { tableController: root }
    }

    ConfirmDialog {
        id: rulesConcedeConfirmation
        property string gameId: ""
        readonly property string liveGameId: root.rulesSession.gameId
        readonly property bool canAct: root.canConcede

        function validForCurrentGame() {
            return canAct && gameId.length > 0 && gameId === liveGameId
        }
        function invalidate() { gameId = ""; close() }
        onLiveGameIdChanged: invalidate()
        onCanActChanged: { if (!canAct) invalidate() }
        onCancelled: gameId = ""

        objectName: "rulesConcedeConfirmation"
        titleText: qsTr("Concede this Forge game?")
        message: qsTr("Forge will apply the concession immediately. This cannot be undone.")
        confirmText: qsTr("Concede")
        dangerous: true
        onConfirmed: {
            const canSend = validForCurrentGame()
            gameId = ""
            if (canSend)
                root.wsModel.concede()
        }
    }
}
