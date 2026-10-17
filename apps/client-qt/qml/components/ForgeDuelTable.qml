// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

Rectangle {
    id: root
    required property var tableController
    readonly property var appWindow: ApplicationWindow.window
    property alias inspectionDock: inspectionDock
    property alias decisionDock: decisionDock
    property alias gameLogRail: floatingLog
    readonly property bool suppressHoverDuringDecision: false
    readonly property bool cardChoiceActive: cardChoiceDialog.requested
    readonly property bool damageChoiceActive: damageDialog.requested
    readonly property bool decisionDialogActive: cardChoiceActive || damageChoiceActive
    readonly property bool inspectingDecision:
        (cardChoiceActive && cardChoiceDialog.inspectingBattlefield)
        || (damageChoiceActive && damageDialog.inspectingBattlefield)
    readonly property bool modalOpen: gameMenu.opened || zonePopup.opened || hostingOptions.opened
        || cardChoiceDialog.visible || damageDialog.visible
    readonly property real unit: Math.min(width / 1600, height / 1000)
    property var playerSeats: []
    readonly property bool multiplayer: playerSeats.length > 2
    readonly property int bottomSeat: playerSeats.includes(tableController.handOwnerSeat)
        ? tableController.handOwnerSeat : playerSeats.length ? playerSeats[0] : 0
    readonly property int topSeat: playerSeats.find(seat => seat !== bottomSeat) ?? (bottomSeat === 0 ? 1 : 0)
    readonly property var session: tableController.rulesSession
    readonly property bool replayMode: tableController.replayMode === true
    readonly property real replayInfoWidth: 240 * unit
    readonly property var combat: tableController.combatInteraction
    readonly property bool combatAiming: combat.canAct && !!combat.chosenSource
        && combatPointer.hovered && !modalOpen && (!appWindow || appWindow.active)
    readonly property bool commanderFormat: ["duel", "edh"].includes(tableController.roomSession.format)
    readonly property bool commandZoneAvailable: commanderFormat
        || playerSeats.some(seat => tableController.zoneCount(seat, "command") > 0)
    readonly property var browsableZones: commandZoneAvailable
        ? ["library", "graveyard", "exile", "command"] : ["library", "graveyard", "exile"]
    readonly property bool sidePanelOpen: !tableController.sideboarding
        && inspectionDock.inspector.pinned
    readonly property real sidePanelWidth: Math.min(width * 0.22, Math.max(284 * unit, Theme.size(240)))
    readonly property real boardLeft: 20 * unit
    readonly property real boardRight: width - 24 * unit
        - (sidePanelOpen ? sidePanelWidth + 16 * unit : 0)
    readonly property real boardWidth: Math.max(0, boardRight - boardLeft)
    readonly property real zonePileWidth: 104 * unit
    readonly property real zonePileHeight: 120 * unit
    readonly property real zoneRowGap: 8 * unit
    readonly property real zoneRowWidth: browsableZones.length * zonePileWidth
        + Math.max(0, browsableZones.length - 1) * zoneRowGap
    readonly property real handLeft: multiplayer ? boardLeft : boardLeft + zoneRowWidth + 10 * unit
    readonly property real centerLeft: boardLeft
    readonly property real centerWidth: boardWidth
    readonly property real handBandHeight: 126 * unit
    readonly property real opponentZoneTop: 6 * unit
    readonly property real handTop: root.height - handBandHeight
    readonly property real battlefieldTop: multiplayer ? 12 * unit : opponentZoneTop + zonePileHeight + 6 * unit
    readonly property real battlefieldBottom: handTop - 6 * unit
    readonly property real battlefieldMiddle: (battlefieldTop + battlefieldBottom) / 2
    readonly property real laneHeight: (battlefieldBottom - battlefieldTop - 12 * unit) / 2
    readonly property real landFaceWidth: 108 * unit
    readonly property real otherFaceWidth: 110 * unit
    readonly property string turnOwner: !session.active || session.turn < 1 || session.activeSeat < 0 ? qsTr("Preparing game")
        : session.activeSeat === tableController.localSeat ? qsTr("Your turn")
        : qsTr("%1's turn").arg(tableController.matchUi.playerName(session.activeSeat))
    readonly property bool turnReady: session.active && session.turn > 0 && session.activeSeat >= 0 && !session.gameOver
    readonly property bool phaseTrackVisible: turnReady && !tableController.sideboarding
    readonly property bool ownTurn: turnReady && session.activeSeat === tableController.localSeat
    readonly property bool localPriority: tableController.priority
        && tableController.priority.isPriorityPrompt
        && !tableController.priority.automaticallyPassing
        && !tableController.priority.yieldMode
    readonly property bool opponentDeciding: turnReady && !tableController.sideboarding
        && !session.gameOver && !localPriority
        && session.prioritySeat >= 0 && session.prioritySeat !== tableController.localSeat
        && !(session.promptPending && session.prioritySeat === tableController.localSeat)
    property double actionClockMarked: 0
    property int actionClockTick: 0
    onActionClockBasisChanged: actionClockMarked = Date.now()
    readonly property var actionClockBasis: tableController.roomSession.actionClockMs || []
    function actionClockText(seat) {
        void actionClockTick
        const basis = actionClockBasis
        if (!basis || seat < 0 || seat >= basis.length)
            return ""
        let remaining = Number(basis[seat])
        if (!Number.isFinite(remaining))
            return ""
        if (tableController.roomSession.actionClockRunning === seat && actionClockMarked > 0)
            remaining -= Date.now() - actionClockMarked
        remaining = Math.max(0, remaining)
        const total = Math.ceil(remaining / 1000)
        const minutes = Math.floor(total / 60)
        const seconds = total % 60
        return minutes + ":" + (seconds < 10 ? "0" : "") + seconds
    }
    Timer {
        interval: 250
        running: (root.actionClockBasis || []).length > 0
        repeat: true
        onTriggered: root.actionClockTick++
    }
    readonly property string turnCalloutText: !turnReady ? ""
        : session.activeSeat === tableController.localSeat ? qsTr("My turn")
        : tableController.localSeat < 0 || multiplayer ? turnOwner : qsTr("Opponent's turn")
    readonly property var stackTarget: stackPanel.currentTarget
    readonly property string locatedId: stackTarget && stackTarget.kind === "card" ? stackTarget.objectId : ""
    readonly property int locatedSeat: stackTarget && stackTarget.kind === "player" ? stackTarget.seat : -1
    property string displayedGame: ""
    objectName: "forgeDuelTable"
    color: "transparent"

    function refreshSeats() {
        const seats = []
        for (let index = 0; index < roster.count; ++index) {
            const item = roster.itemAt(index) as SeatEntry
            if (item) seats.push(item.seat)
        }
        playerSeats = seats
    }
    component SeatEntry: Item {
        required property int seat
        required property var commanders
        visible: false
    }
    function commandersFor(seat) {
        for (let index = 0; index < roster.count; ++index) {
            const player = roster.itemAt(index) as SeatEntry
            if (player && player.seat === seat) return player.commanders
        }
        return []
    }
    Repeater {
        id: roster
        model: root.session.players
        onItemAdded: Qt.callLater(root.refreshSeats)
        onItemRemoved: Qt.callLater(root.refreshSeats)
        delegate: SeatEntry {}
    }
    ForgeMultiplayerBattlefield {
        id: multiplayerBoard
        presentation: root
        x: root.boardLeft; y: root.battlefieldTop
        width: root.boardWidth; height: root.battlefieldBottom - y
        z: 1
        visible: root.multiplayer && !root.tableController.sideboarding
    }

    HoverHandler {
        id: combatPointer
        objectName: "forgeCombatPointer"
        enabled: root.combat.canAct && !root.modalOpen
        blocking: false
    }

    onCommandZoneAvailableChanged: {
        if (zonePopup && !commandZoneAvailable && zonePopup.zone === "command")
            zonePopup.zone = "graveyard"
    }

    function unobscuredRight(top, extent) {
        let right = root.boardRight
        // Keep native decision controls clear of cards. The movable stack
        // floats over the battlefield and never reserves a column.
        for (const panel of [decisionDock, settingsButton]) {
            if (panel.visible && top < panel.y + panel.height && top + extent > panel.y)
                right = Math.min(right, panel.x - 12 * root.unit)
        }
        return right
    }
    function laneWidth(top, laneHeight) { return Math.max(0, unobscuredRight(top, laneHeight) - root.boardLeft) }

    function pointFor(id) {
        if (multiplayer) return multiplayerBoard.pointFor(id, root)
        const lanes = [ownCreatures, opponentCreatures, ownLands, opponentLands, ownOther, opponentOther]
        for (const lane of lanes) {
            const point = lane.pointFor(id, root)
            if (point.x !== 0) return point
        }
        return Qt.point(0, 0)
    }
    function playerPoint(seat) {
        if (multiplayer) return multiplayerBoard.playerPoint(seat, root)
        for (let i = 0; i < plates.count; ++i) {
            const plate = plates.itemAt(i) as PlayerPlate
            if (plate && plate.seat === seat) {
                void plate.x; void plate.y
                return plate.mapToItem(root, plate.width / 2, plate.lifeCenterY)
            }
        }
        return Qt.point(0, 0)
    }
    function reveal(id) {
        if (multiplayer) return multiplayerBoard.reveal(id)
        for (const lane of [ownCreatures, opponentCreatures, ownLands, opponentLands, ownOther, opponentOther]) {
            if (lane.reveal(id)) return true
        }
        return false
    }
    function openZone(seat, zone) {
        zonePopup.ownerSeat = seat
        zonePopup.zone = zone
        zonePopup.open()
    }
    function resumeDecision() {
        zonePopup.close()
        cardChoiceDialog.resumeDecision()
        damageDialog.resumeDecision()
    }
    function zoneOwnerTitle(seat) {
        if (seat === root.tableController.localSeat)
            return qsTr("You")
        const name = root.tableController.matchUi.playerName(seat)
        return name && name.length ? name : qsTr("Opponent")
    }
    Connections {
        target: root.session
        function onPromptChanged() {
            stackPanel.clearSelection()
        }
        function onSnapshotChanged() {
            Qt.callLater(root.refreshSeats)
            if (root.displayedGame !== root.session.gameId) {
                root.displayedGame = root.session.gameId
                gameMenu.close()
                zonePopup.close()
                stackPanel.clearSelection()
                stackPanel.resetPosition()
                stackPanel.collapsed = false
            }
            root.scheduleTurnCallout()
        }
    }
    Component.onCompleted: { displayedGame = session.gameId; refreshSeats(); announceTurn() }
    function scheduleTurnCallout() {
        Qt.callLater(root.announceTurn)
    }
    function announceTurn() {
        if (!turnReady || tableController.sideboarding) {
            turnCallout.shownGame = session.gameId
            turnCallout.shownSeat = -1
            turnCallout.opacity = 0
            return
        }
        if (turnCallout.shownGame === session.gameId && turnCallout.shownSeat === session.activeSeat)
            return
        turnCallout.shownGame = session.gameId
        turnCallout.shownSeat = session.activeSeat
        turnCallout.present(turnCalloutText)
    }
    Connections {
        target: root.tableController
        function onLocalSeatChanged() { zonePopup.close(); stackPanel.clearSelection(); inspectionDock.inspector.clear() }
        function onHandOwnerSeatChanged() { inspectionDock.inspector.clear() }
        function onRoomConnectedChanged() {
            if (!root.tableController.roomConnected) { gameMenu.close(); zonePopup.close() }
        }
        function onSideboardingChanged() {
            if (root.tableController.sideboarding) { gameMenu.close(); zonePopup.close() }
        }
        function onRulesResponsePendingChanged() {
            if (root.tableController.rulesResponsePending) zonePopup.close()
        }
    }
    Item {
        id: playmatAtmosphere
        anchors.fill: parent

        Rectangle {
            objectName: "forgePlaymatVeil"
            anchors.fill: parent
            gradient: Gradient {
                orientation: Gradient.Vertical
                GradientStop { position: 0.0; color: TableBackgrounds.hasImage ? "#26060A0C" : "#4D060A0C" }
                GradientStop { position: 0.18; color: TableBackgrounds.hasImage ? "#00000000" : "#14060A0C" }
                GradientStop { position: 0.82; color: TableBackgrounds.hasImage ? "#00000000" : "#14060A0C" }
                GradientStop { position: 1.0; color: TableBackgrounds.hasImage ? "#33060A0C" : "#66060A0C" }
            }
        }

        Rectangle {
            objectName: "forgeBoardWell"
            x: Math.max(0, root.boardLeft - 8 * root.unit)
            y: Math.max(0, root.battlefieldTop - 4 * root.unit)
            width: root.boardWidth + 16 * root.unit
            height: Math.max(0, root.battlefieldBottom - y + 4 * root.unit)
            radius: 18 * root.unit
            antialiasing: true
            color: Theme.withAlpha("#05080A", 0.16)
            visible: !root.tableController.sideboarding
        }

        Rectangle {
            y: root.battlefieldMiddle - 12 * root.unit
            width: parent.width
            height: 24 * root.unit
            visible: !root.tableController.sideboarding
            gradient: Gradient {
                orientation: Gradient.Vertical
                GradientStop { position: 0.0; color: "#00000000" }
                GradientStop { position: 0.5; color: Theme.withAlpha(Theme.accent, 0.14) }
                GradientStop { position: 1.0; color: "#00000000" }
            }
        }
    }

    Drawer {
        id: gameMenu
        objectName: "forgeGameDrawer"
        width: Math.min(300 * root.unit, root.width * 0.3)
        height: root.height
        edge: Qt.RightEdge
        background: Rectangle {
            color: Theme.withAlpha(Theme.backgroundRaised, 0.98)
        }
        RulesTableActionRail {
            anchors.fill: parent
            tableController: root.tableController
            compactChrome: true
            hostingDialog: hostingOptions
            onAudioSettingsRequested: gameMenu.close()
        }
    }
    ForgeHostingDialog {
        id: hostingOptions
        service: root.tableController.wsModel.forgeHost || null
        wsModel: root.tableController.wsModel
    }
    AppButton {
        id: settingsButton
        visible: !root.replayMode
        objectName: "forgeGameMenu"
        z: 200
        x: root.width - width - 16 * root.unit
        y: 10 * root.unit
        compact: true
        variant: gameMenu.opened ? "highlight" : "ghost"
        implicitHeight: Theme.size(32)
        font.pixelSize: Theme.fontSize(12)
        text: qsTr("Settings")
        onClicked: gameMenu.opened ? gameMenu.close() : gameMenu.open()
    }
    InfoBanner {
        objectName: "rulesErrorBanner"
        x: 20 * root.unit
        y: 3 * root.unit
        width: 300 * root.unit
        z: 40
        message: root.replayMode ? "" : I18n.status(root.tableController.wsModel.lastError || "")
    }
    component PlayerPlate: Item {
        id: plate
        required property int seat
        required property string name
        required property int life
        required property string countersSummary
        required property string manaSummary
        required property var manaPool
        readonly property var roomSeat: root.tableController.roomSession.seats
            ? root.tableController.roomSession.seats[seat] || ({}) : ({})
        readonly property string displayName: roomSeat.controller === "forgeAi"
            ? qsTr("Forge AI · %1").arg(I18n.aiDifficultyLabel(roomSeat.aiDifficulty))
            : roomSeat.controller === "modelAi" ? I18n.aiSourceLabel(root.tableController.roomSession.aiSource) : name
        readonly property bool isBottom: seat === root.bottomSeat
        readonly property bool activeTurn: root.session.activeSeat === seat && root.session.active && root.session.turn > 0
        readonly property bool actionable: root.tableController.combatInteraction.active
            ? root.tableController.combatInteraction.seatActionable(seat) : root.tableController.interaction.seatActionable(seat)
        readonly property bool selected: root.locatedSeat === seat || (root.tableController.combatInteraction.active
            ? root.tableController.combatInteraction.seatSelected(seat) : root.tableController.interaction.seatSelected(seat))
        readonly property bool combatHovered: root.combat.hoveredTarget
            && root.combat.hoveredTarget.kind === "player" && root.combat.hoveredTarget.seat === seat
        readonly property bool underAttack: (root.session.battlefieldRelationships || []).some(
            link => link.kind === "attack" && !link.targetId && link.targetSeat === seat)
        readonly property string clockText: root.actionClockText(seat)
        readonly property real discSize: 52 * root.unit
        readonly property real lifeCenterY: lifeDisc.y + lifeDisc.height / 2
        objectName: "rulesPlayerTarget" + seat
        x: root.replayMode ? root.boardRight - root.replayInfoWidth + 20 * root.unit
            : root.centerLeft + (root.centerWidth - width) / 2
        y: root.replayMode ? (isBottom ? root.handTop : 4 * root.unit)
            : isBottom ? root.handTop - discSize * 0.58 : 4 * root.unit
        width: 168 * root.unit
        height: discSize + 30 * root.unit
        z: 35
        visible: !root.tableController.sideboarding
        activeFocusOnTab: actionable || activeFocus
        function activate() {
            if (!actionable) return
            if (root.tableController.combatInteraction.active) root.tableController.combatInteraction.activateSeat(seat)
            else root.tableController.interaction.activateSeat(seat)
        }
        Keys.onReturnPressed: activate()
        Keys.onSpacePressed: activate()
        Accessible.role: Accessible.Button
        Accessible.name: displayName + ", " + qsTr("Life %1").arg(life)
        Accessible.onPressAction: activate()
        Column {
            anchors.horizontalCenter: parent.horizontalCenter
            y: plate.isBottom ? plate.discSize + 2 * root.unit : 0
            width: parent.width
            spacing: 1 * root.unit
            Text {
                textFormat: Text.PlainText
                width: parent.width
                objectName: "forgePlayerName-" + plate.seat
                text: plate.displayName
                elide: Text.ElideRight
                horizontalAlignment: Text.AlignHCenter
                color: Theme.text
                style: Text.Outline
                styleColor: Theme.withAlpha("#000000", 0.7)
                font.pixelSize: 12 * root.unit
                font.weight: Font.DemiBold
            }
            Text {
                objectName: "forgeActionClock-" + plate.seat
                visible: plate.clockText.length > 0
                textFormat: Text.PlainText
                width: parent.width
                text: plate.clockText
                horizontalAlignment: Text.AlignHCenter
                color: root.tableController.roomSession.actionClockRunning === plate.seat
                       ? "#f0c7bc" : Theme.textSecondary
                font.pixelSize: 13 * root.unit
                font.weight: Font.Bold
            }
            Text {
                objectName: "forgePlayerZones-" + plate.seat
                textFormat: Text.PlainText
                width: parent.width
                text: [qsTr("Hand · %1").arg(root.tableController.zoneCount(plate.seat, "hand")),
                    qsTr("Library · %1").arg(root.tableController.zoneCount(plate.seat, "library")),
                    plate.countersSummary].filter(v => v.length).join(" · ")
                elide: Text.ElideRight
                horizontalAlignment: Text.AlignHCenter
                color: Theme.textSecondary
                style: Text.Outline
                styleColor: Theme.withAlpha("#000000", 0.65)
                font.pixelSize: 10 * root.unit
            }
        }
        ForgeManaPool {
            objectName: "forgeManaPool-" + plate.seat
            // Keep public floating mana readable above hand cards and their
            // hover previews. Reparenting removes the player plate's z limit.
            parent: root
            z: 1001
            x: Math.min(root.width - width - 8 * root.unit,
                        plate.x + (root.replayMode ? 0 : plate.width) + 10 * root.unit)
            y: plate.y + (root.replayMode ? plate.height + 4 * root.unit
                : lifeDisc.y + (lifeDisc.height - height) / 2)
            visible: plate.visible && plate.manaPool.length > 0
            manaPool: plate.manaPool
            seat: plate.seat
            unit: root.unit
        }
        Rectangle {
            id: lifeDisc
            width: plate.discSize
            height: width
            radius: width / 2
            anchors.horizontalCenter: parent.horizontalCenter
            y: plate.isBottom ? 0 : parent.height - height
            antialiasing: true
            color: Theme.withAlpha(Theme.surface, plate.selected || plate.actionable ? 0.88 : 0.62)
            border.width: plate.combatHovered || plate.underAttack ? 4
                          : plate.selected || plate.activeFocus || plate.actionable || plate.activeTurn ? 2 : 0
            border.color: plate.underAttack ? "#d4654f"
                          : plate.combatHovered ? Theme.primary : plate.selected || plate.activeFocus ? Theme.accent
                          : plate.actionable ? Theme.primary : Theme.warning
            Text {
                textFormat: Text.PlainText
                anchors.centerIn: parent
                text: plate.life
                color: Theme.accent
                font.pixelSize: 22 * root.unit
                font.weight: Font.DemiBold
            }
        }
        TapHandler { enabled: plate.actionable; onTapped: plate.activate() }
        HoverHandler {
            enabled: root.combat.canAct && plate.actionable
            cursorShape: plate.actionable ? Qt.PointingHandCursor : Qt.ArrowCursor
            onHoveredChanged: root.combat.hoverSeat(plate.seat, hovered)
        }
        AppButton {
            visible: !root.replayMode && root.tableController.canViewSpectatorHands
            anchors.left: parent.right
            anchors.leftMargin: 8 * root.unit
            anchors.verticalCenter: lifeDisc.verticalCenter
            compact: true
            text: qsTr("View hand")
            onClicked: root.tableController.spectatedHandSeat = plate.seat
        }
    }
    Repeater {
        id: plates
        model: root.multiplayer ? null : root.session.players
        delegate: PlayerPlate {}
    }
    Row {
        id: phaseTrack
        objectName: "forgePhaseTrack"
        // Multiplayer fields reserve this strip only while it is visible.
        // In 1v1 it overlays the lanes and drops below the deciding banner.
        x: root.boardLeft
        y: {
            const centered = root.battlefieldMiddle - height / 2
            if (!opponentDecidingBanner.visible)
                return centered
            return Math.min(opponentDecidingBanner.y + opponentDecidingBanner.height + 4 * root.unit,
                             root.battlefieldBottom - height)
        }
        width: root.laneWidth(y, height)
        height: 18 * root.unit
        z: 45
        spacing: 2 * root.unit
        enabled: false
        visible: root.phaseTrackVisible
        readonly property var steps: [
            "untap", "upkeep", "draw", "main1", "begin_combat", "declare_attackers",
            "declare_blockers", "combat_damage", "end_combat", "main2", "end", "cleanup"
        ]
        function shortLabel(step) {
            switch (step) {
            case "untap": return qsTr("Untap")
            case "upkeep": return qsTr("Upkeep")
            case "draw": return qsTr("Draw")
            case "main1": return qsTr("Main")
            case "begin_combat": return qsTr("Combat")
            case "declare_attackers": return qsTr("Attack")
            case "declare_blockers": return qsTr("Block")
            case "combat_damage": return qsTr("Damage")
            case "end_combat": return qsTr("Combat end")
            case "main2": return qsTr("Main")
            case "end": return qsTr("End")
            case "cleanup": return qsTr("Cleanup")
            default: return step
            }
        }
        Repeater {
            model: phaseTrack.steps
            delegate: Rectangle {
                required property string modelData
                required property int index
                objectName: "forgePhase-" + modelData
                readonly property bool current: root.session.step === modelData
                readonly property bool past: phaseTrack.steps.indexOf(root.session.step) > index
                width: Math.max(0, (phaseTrack.width - phaseTrack.spacing * 11) / 12)
                height: phaseTrack.height
                radius: 3 * root.unit
                color: current ? Theme.accent : past ? Theme.withAlpha(Theme.accent, 0.28) : Theme.withAlpha("#101820", 0.55)
                Text {
                    anchors.fill: parent
                    anchors.margins: 1
                    textFormat: Text.PlainText
                    text: phaseTrack.shortLabel(modelData)
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    elide: Text.ElideRight
                    color: current ? Theme.primaryInk : Theme.text
                    font.pixelSize: 8 * root.unit
                    font.weight: current ? Font.Bold : Font.Normal
                }
            }
        }
    }
    Item {
        id: opponentDecidingBanner
        objectName: "forgeOpponentDeciding"
        x: root.boardLeft + (root.boardWidth - width) / 2
        y: root.battlefieldMiddle - height / 2
        z: 90
        enabled: false
        visible: !root.multiplayer && root.opponentDeciding && !root.modalOpen
        width: Math.min(root.boardWidth, decidingLabel.implicitWidth + 28 * root.unit)
        height: decidingLabel.implicitHeight + 14 * root.unit
        Rectangle {
            anchors.fill: parent
            radius: 8 * root.unit
            color: Theme.withAlpha("#101820", 0.82)
            border.width: 1
            border.color: "#d4654f"
        }
        Text {
            id: decidingLabel
            objectName: "forgeOpponentDecidingText"
            anchors.centerIn: parent
            width: parent.width - 28 * root.unit
            textFormat: Text.PlainText
            text: root.multiplayer ? root.tableController.matchUi.playerName(root.session.prioritySeat)
                + " · " + qsTranslate("RulesBattlefieldView", "Priority") : qsTr("Opponent is deciding")
            color: "#f0c7bc"
            font.pixelSize: 18 * root.unit
            font.weight: Font.Bold
            elide: Text.ElideRight
            horizontalAlignment: Text.AlignHCenter
        }
    }
    Rectangle {
        objectName: "forgeActiveBattlefield"
        visible: !root.multiplayer && root.turnReady && !root.tableController.sideboarding
        x: root.boardLeft
        y: root.session.activeSeat === root.bottomSeat ? root.battlefieldMiddle : root.battlefieldTop
        width: root.boardWidth
        height: root.session.activeSeat === root.bottomSeat
               ? Math.max(0, root.battlefieldBottom - root.battlefieldMiddle)
               : Math.max(0, root.battlefieldMiddle - root.battlefieldTop)
        radius: 10 * root.unit
        color: Theme.withAlpha(root.ownTurn ? Theme.accent : "#d4654f", 0.14)
        border.width: 2
        border.color: Theme.withAlpha(root.ownTurn ? Theme.accent : "#d4654f", 0.9)
    }
    Item {
        id: turnCallout
        objectName: "forgeTurnCallout"
        anchors.centerIn: parent
        z: 100
        enabled: false
        opacity: 0
        visible: opacity > 0 && !root.modalOpen
        width: Math.min(root.width * 0.72, calloutLabel.implicitWidth + 72 * root.unit)
        height: calloutLabel.implicitHeight + 36 * root.unit
        property string message: ""
        property string shownGame: ""
        property int shownSeat: -1
        function present(message) {
            fade.stop()
            turnCallout.message = message
            turnCallout.opacity = 1
            hold.restart()
        }
        Rectangle {
            anchors.fill: parent
            radius: 12 * root.unit
            color: Theme.withAlpha("#101820", 0.88)
            border.width: 2
            border.color: root.ownTurn ? Theme.accent : "#d4654f"
        }
        Text {
            id: calloutLabel
            objectName: "forgeTurnCalloutText"
            anchors.centerIn: parent
            width: parent.width - 72 * root.unit
            textFormat: Text.PlainText
            text: turnCallout.message
            color: root.ownTurn ? Theme.accent : "#f0c7bc"
            font.pixelSize: 44 * root.unit
            font.weight: Font.Black
            elide: Text.ElideRight
            horizontalAlignment: Text.AlignHCenter
        }
        Timer {
            id: hold
            interval: 1400
            onTriggered: fade.start()
        }
        NumberAnimation {
            id: fade
            target: turnCallout
            property: "opacity"
            to: 0
            duration: 420
        }
    }
    ForgeFieldLayout {
        id: opponentFieldLayout
        width: root.boardWidth; height: root.laneHeight; unit: root.unit; nearSide: false
        creatureLane: opponentCreatures; landLane: opponentLands; otherLane: opponentOther
        widthForBand: (top, extent) => root.laneWidth(root.battlefieldTop + top, extent)
    }
    ForgeFieldLayout {
        id: ownFieldLayout
        width: root.boardWidth; height: root.laneHeight; unit: root.unit; nearSide: true
        creatureLane: ownCreatures; landLane: ownLands; otherLane: ownOther
        widthForBand: (top, extent) => root.laneWidth(root.battlefieldMiddle + 6 * root.unit + top, extent)
    }
    ForgeCardLane {
        id: opponentLands
        objectName: "forgeOpponentLands"
        x: root.boardLeft + opponentFieldLayout.placement.lands.x
        y: root.battlefieldTop + opponentFieldLayout.placement.lands.y
        width: opponentFieldLayout.placement.lands.width
        height: opponentFieldLayout.placement.lands.height
        tableController: root.tableController
        unit: root.unit
        ownerSeat: root.multiplayer ? -1 : root.topSeat
        category: "land"
        showCaption: false
        maxFaceWidth: root.landFaceWidth
        locatedId: root.locatedId
        visible: !root.multiplayer && !root.tableController.sideboarding
    }
    ForgeCardLane {
        id: opponentOther
        objectName: "forgeOpponentOther"
        x: root.boardLeft + opponentFieldLayout.placement.others.x
        y: root.battlefieldTop + opponentFieldLayout.placement.others.y
        width: opponentFieldLayout.placement.others.width
        height: opponentFieldLayout.placement.others.height
        tableController: root.tableController
        unit: root.unit
        ownerSeat: root.multiplayer ? -1 : root.topSeat
        category: "other"
        showCaption: false
        maxFaceWidth: root.otherFaceWidth
        locatedId: root.locatedId
        visible: !root.multiplayer && !root.tableController.sideboarding
    }
    ForgeCardLane {
        id: opponentCreatures
        objectName: "forgeOpponentCreatures"
        x: root.boardLeft + opponentFieldLayout.placement.creatures.x
        y: root.battlefieldTop + opponentFieldLayout.placement.creatures.y
        width: opponentFieldLayout.placement.creatures.width
        height: opponentFieldLayout.placement.creatures.height
        tableController: root.tableController
        unit: root.unit
        ownerSeat: root.multiplayer ? -1 : root.topSeat
        showCaption: false
        maxFaceWidth: 200 * unit
        alignBottom: true
        combatForward: 1
        locatedId: root.locatedId
        visible: !root.multiplayer && !root.tableController.sideboarding
    }
    ForgeCardLane {
        id: ownCreatures
        objectName: "forgeOwnCreatures"
        x: root.boardLeft + ownFieldLayout.placement.creatures.x
        y: root.battlefieldMiddle + 6 * root.unit + ownFieldLayout.placement.creatures.y
        width: ownFieldLayout.placement.creatures.width
        height: ownFieldLayout.placement.creatures.height
        tableController: root.tableController
        unit: root.unit
        ownerSeat: root.multiplayer ? -1 : root.bottomSeat
        showCaption: false
        maxFaceWidth: 200 * unit
        combatForward: -1
        locatedId: root.locatedId
        visible: !root.multiplayer && !root.tableController.sideboarding
    }
    ForgeCardLane {
        id: ownOther
        objectName: "forgeOwnOther"
        x: root.boardLeft + ownFieldLayout.placement.others.x
        y: root.battlefieldMiddle + 6 * root.unit + ownFieldLayout.placement.others.y
        width: ownFieldLayout.placement.others.width
        height: ownFieldLayout.placement.others.height
        tableController: root.tableController
        unit: root.unit
        ownerSeat: root.multiplayer ? -1 : root.bottomSeat
        category: "other"
        showCaption: false
        alignBottom: true
        maxFaceWidth: root.otherFaceWidth
        locatedId: root.locatedId
        visible: !root.multiplayer && !root.tableController.sideboarding
    }
    ForgeCardLane {
        id: ownLands
        objectName: "forgeOwnLands"
        x: root.boardLeft + ownFieldLayout.placement.lands.x
        y: root.battlefieldMiddle + 6 * root.unit + ownFieldLayout.placement.lands.y
        width: ownFieldLayout.placement.lands.width
        height: ownFieldLayout.placement.lands.height
        tableController: root.tableController
        unit: root.unit
        ownerSeat: root.multiplayer ? -1 : root.bottomSeat
        category: "land"
        showCaption: false
        alignBottom: true
        maxFaceWidth: root.landFaceWidth
        locatedId: root.locatedId
        visible: !root.multiplayer && !root.tableController.sideboarding
    }
    DropArea {
        objectName: "forgeHandDropArea"
        x: root.boardLeft
        y: root.battlefieldMiddle + 6 * root.unit
        width: root.boardWidth
        height: Math.max(0, root.battlefieldBottom - ownCreatures.y)
        enabled: !root.multiplayer && !root.tableController.sideboarding && root.tableController.localSeat >= 0
        keys: ["hexproof/rules-card"]
        onDropped: drop => {
            if (root.tableController.playDraggedHandCardSource(drop.source)) drop.acceptProposedAction()
            else drop.accepted = false
        }
    }
    Repeater {
        model: root.session.battlefieldRelationships || []
        delegate: ForgeArrow {
            required property var modelData
            objectName: "forgeRelationship-" + modelData.kind + "-" + modelData.sourceId + "-" + modelData.targetId
            anchors.fill: parent
            z: 60
            unit: root.unit
            dashed: false
            lineColor: modelData.kind === "attack" ? "#d4654f" : "#7ebcca"
            visible: !root.tableController.sideboarding && !root.modalOpen
                && modelData.kind !== "attachment"
                && !(modelData.kind === "block" && (root.combat.active || root.replayMode))
            startPoint: root.pointFor(modelData.sourceId)
            endPoint: modelData.targetId ? root.pointFor(modelData.targetId)
                      : root.playerPoint(modelData.targetSeat)
        }
    }
    Repeater {
        model: root.tableController.combatInteraction.links
        delegate: ForgeArrow {
            required property var modelData
            objectName: "forgeCombatArrow-" + modelData.from + "-" + (modelData.player ? "seat-" + modelData.seat : modelData.to)
            anchors.fill: parent
            z: 70
            unit: root.unit
            opacity: root.combat.chosenSource && root.combat.chosenSource.objectId === modelData.from ? 0.25 : 1
            lineColor: root.tableController.combatInteraction.attacking ? "#e1bd7f" : "#7ebcca"
            startPoint: {
                void ownCreatures.visibleCards; void ownCreatures.scrollArea.contentY; void root.width; void root.height
                return root.pointFor(modelData.from)
            }
            endPoint: {
                void opponentCreatures.visibleCards; void opponentCreatures.scrollArea.contentY; void root.width; void root.height
                return modelData.player ? root.playerPoint(modelData.seat) : root.pointFor(modelData.to)
            }
        }
    }
    ForgeArrow {
        id: combatAimArrow
        objectName: "forgeCombatAimArrow"
        anchors.fill: parent
        z: 80
        unit: root.unit
        preview: true
        visible: root.combatAiming && startPoint.x !== 0
        readonly property var target: root.combat.hoveredTarget
        readonly property point targetPoint: !target ? Qt.point(0, 0)
            : target.kind === "player" ? root.playerPoint(target.seat) : root.pointFor(target.objectId)
        readonly property bool snapped: targetPoint.x !== 0
        lineColor: snapped ? Theme.primary : root.combat.attacking ? "#e1bd7f" : "#7ebcca"
        startPoint: root.combat.chosenSource ? root.pointFor(root.combat.chosenSource.objectId) : Qt.point(0, 0)
        endPoint: {
            if (snapped) return targetPoint
            const pointer = combatPointer.point.position
            // Make the initial arrow visible even when the click is at its origin.
            if (Math.hypot(pointer.x - startPoint.x, pointer.y - startPoint.y) < 8 * root.unit)
                return Qt.point(startPoint.x, startPoint.y - 24 * root.unit)
            return pointer
        }
    }
    ForgeHand {
        objectName: "forgeHand"
        showCount: !root.multiplayer
        x: root.handLeft
        y: root.handTop - (root.localPriority ? 18 * root.unit : 0)
        z: 30
        width: Math.max(0, (root.replayMode ? root.boardRight - root.replayInfoWidth : decisionDock.x) - x - 20 * root.unit)
        height: root.handBandHeight - 4 * root.unit
        tableController: root.tableController
        unit: root.unit
        visible: !root.tableController.sideboarding
    }
    ForgeHand {
        objectName: "forgeReplayOpponentHand"
        visible: root.replayMode
        x: root.handLeft
        y: 24 * root.unit
        width: Math.max(0, root.boardRight - root.replayInfoWidth - x - 20 * root.unit)
        height: root.handBandHeight - 20 * root.unit
        tableController: root.tableController
        ownerSeat: root.topSeat
        unit: root.unit
        z: 30
    }
    Repeater {
        model: root.replayMode ? root.tableController.replayFrame.combat || [] : []
        delegate: ForgeArrow {
            required property var modelData
            anchors.fill: parent
            z: 55
            unit: root.unit
            startPoint: root.pointFor(modelData.sourceId)
            endPoint: modelData.targetSeat !== undefined
                ? root.playerPoint(modelData.targetSeat) : root.pointFor(modelData.targetId)
            lineColor: modelData.kind === "block" ? Theme.success : Theme.accent
        }
    }
    Item {
        id: opponentZoneStrip
        objectName: "forgeOpponentZoneStrip"
        x: root.boardLeft
        y: root.opponentZoneTop
        width: root.zoneRowWidth
        height: root.zonePileHeight
        visible: !root.multiplayer && !root.tableController.sideboarding
        z: 20
        Item {
            objectName: "forgeOpponentZones"
            anchors.fill: parent
            Accessible.role: Accessible.Button
            Accessible.name: qsTr("Opponent's zones")
            MouseArea {
                anchors.fill: parent
                onClicked: root.openZone(root.topSeat, "graveyard")
            }
        }
        Row {
            spacing: root.zoneRowGap
            Repeater {
                model: root.browsableZones
                delegate: ForgeZonePile {
                    required property string modelData
                    objectName: "forgeOpponentZone-" + modelData
                    width: Math.round(root.zonePileWidth)
                    height: Math.round(root.zonePileHeight)
                    tableController: root.tableController
                    unit: root.unit
                    ownerSeat: root.multiplayer ? -1 : root.topSeat
                    zone: modelData
                    compact: true
                    onActivated: root.openZone(root.topSeat, zone)
                }
            }
        }
    }
    Item {
        id: ownZoneStrip
        objectName: "forgeOwnZoneStrip"
        x: root.boardLeft
        y: root.handTop
        width: root.zoneRowWidth
        height: root.handBandHeight
        visible: !root.multiplayer && !root.tableController.sideboarding
        z: 20
        Row {
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 4 * root.unit
            spacing: root.zoneRowGap
            Repeater {
                model: root.browsableZones
                delegate: ForgeZonePile {
                    required property string modelData
                    objectName: "forgeZone-" + modelData
                    width: Math.round(root.zonePileWidth)
                    height: Math.round(root.zonePileHeight)
                    tableController: root.tableController
                    unit: root.unit
                    ownerSeat: root.multiplayer ? -1 : root.bottomSeat
                    zone: modelData
                    compact: true
                    onActivated: root.openZone(root.bottomSeat, zone)
                }
            }
        }
    }
    Popup {
        id: zonePopup
        objectName: "forgeZonePopup"
        property int ownerSeat: 0
        property string zone: "graveyard"
        readonly property real headerHeight: Math.max(36 * root.unit,
            zoneHeaderActions.implicitHeight + Theme.size(8))
        parent: Overlay.overlay
        width: Math.min(760 * root.unit, root.width - 40 * root.unit)
        height: Math.min(440 * root.unit, root.height - 80 * root.unit)
        x: (parent.width - width) / 2
        y: (parent.height - height) / 2
        modal: true; focus: true
        padding: 0
        background: Rectangle {
            radius: 14 * root.unit
            antialiasing: true
            color: Theme.withAlpha(Theme.surface, 0.94)
        }
        Item {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: zonePopup.headerHeight
            Text {
                textFormat: Text.PlainText
                anchors.left: parent.left
                anchors.right: zoneHeaderActions.left
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: 16 * root.unit
                anchors.rightMargin: 8 * root.unit
                text: qsTr("%1 · %2").arg(root.zoneOwnerTitle(zonePopup.ownerSeat))
                      .arg(root.tableController.zoneLabel(zonePopup.zone))
                color: Theme.text
                font.pixelSize: 15 * root.unit
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }
            Row {
                id: zoneHeaderActions
                anchors.right: parent.right
                anchors.rightMargin: 10 * root.unit
                anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.size(6)
                AppButton {
                    objectName: "rulesResumeDecisionFromZone"
                    visible: root.inspectingDecision
                    text: qsTranslate("RulesDecisionDialog", "Return to choice")
                    compact: true
                    onClicked: root.resumeDecision()
                }
                AppButton {
                    objectName: "forgeCloseZonePopup"
                    compact: true
                    variant: "ghost"
                    text: qsTr("Close")
                    onClicked: zonePopup.close()
                }
            }
        }
        Row {
            id: zoneTabs
            objectName: "forgeZoneTabs"
            x: 14 * root.unit
            y: zonePopup.headerHeight + 4 * root.unit
            spacing: 4 * root.unit
            Repeater {
                model: root.browsableZones
                delegate: AppButton {
                    required property string modelData
                    objectName: "forgeZoneTab-" + modelData
                    compact: true
                    variant: zonePopup.zone === modelData ? "highlight" : "ghost"
                    text: root.tableController.zoneLabel(modelData)
                    onClicked: zonePopup.zone = modelData
                }
            }
        }
        Column {
            id: commanderHistory
            objectName: "forgeCommanderHistory"
            x: 14 * root.unit
            y: zoneTabs.y + zoneTabs.height + 8 * root.unit
            width: parent.width - 28 * root.unit
            spacing: 4 * root.unit
            visible: zonePopup.zone === "command"
            Repeater {
                model: commanderHistory.visible ? root.commandersFor(zonePopup.ownerSeat) : []
                delegate: Text {
                    required property var modelData
                    required property int index
                    readonly property string commanderName: root.tableController.cardDisplayName(modelData.name)
                    readonly property string summary: qsTr("Casts %1 · Tax +%2 · %3").arg(modelData.casts).arg(modelData.tax)
                        .arg(modelData.zone === "hidden" ? qsTr("Hidden zone") : root.tableController.zoneLabel(modelData.zone))
                    objectName: "forgeCommanderHistory-" + zonePopup.ownerSeat + "-" + index
                    width: commanderHistory.width
                    textFormat: Text.PlainText
                    text: commanderName + " · " + summary
                    color: Theme.textSecondary
                    font.pixelSize: 12 * root.unit
                    wrapMode: Text.WordWrap
                }
            }
        }
        ForgeCardLane {
            objectName: "forgeZoneCards"
            anchors.fill: parent
            anchors.topMargin: commanderHistory.y + (commanderHistory.visible ? commanderHistory.height : 0) + 8 * root.unit
            anchors.margins: 12 * root.unit
            tableController: root.tableController
            unit: root.unit
            ownerSeat: zonePopup.ownerSeat
            zone: zonePopup.zone
            category: "zone"
            caption: root.tableController.zoneLabel(zonePopup.zone)
        }
    }
    RulesDecisionDock {
        id: decisionDock
        x: root.width - width - 16 * root.unit
           - (root.sidePanelOpen ? root.sidePanelWidth + 16 * root.unit : 0)
        y: root.height - height - 12 * root.unit
        width: root.multiplayer ? Math.min(root.width * 0.3, Math.max(330 * root.unit, Theme.size(280)))
            : Math.min(root.width * 0.42, Math.max(420 * root.unit, Theme.size(340)))
        height: Math.min(implicitHeight, root.height - 24 * root.unit)
        z: 180
        contentMargins: Theme.size(10)
        hideIdlePriorityStatus: true
        tableController: root.tableController
        // Dialog ownership is permanent. Losing authority closes the dialog;
        // it must never transfer the stale private prompt back to the dock.
        externalCardChoices: true
        externalDamageChoices: true
        showZoneActions: true
        showActions: !root.tableController.sideboarding && root.tableController.hostingPaused !== true
        visible: !root.replayMode && (!root.tableController.sideboarding || root.tableController.hostingPaused === true)
        radius: 16 * root.unit
        elevated: true
        color: Theme.useGlass ? "transparent" : Theme.withAlpha(Theme.surface, 0.90)
        border.width: Theme.useGlass ? 1 : 0
        border.color: "transparent"
        contextControls: Component {
            ColumnLayout {
                id: tableControls
                objectName: "forgeTableControls"
                spacing: Theme.size(5)

                AppButton {
                    objectName: "rulesResumeDecision"
                    Layout.fillWidth: true
                    visible: root.inspectingDecision
                    text: qsTranslate("RulesDecisionDialog", "Return to choice")
                    variant: "primary"
                    onClicked: root.resumeDecision()
                }

                Text {
                    objectName: "forgePlayerControlStatus"
                    Layout.fillWidth: true
                    textFormat: Text.PlainText
                    visible: root.tableController.controlledTurnSeat >= 0
                    text: qsTr("You control %1's turn").arg(root.tableController.matchUi.playerName(root.tableController.controlledTurnSeat))
                    color: Theme.primary
                    font.pixelSize: Theme.fontSize(12)
                    wrapMode: Text.WordWrap
                }
                Text {
                    objectName: "modelOpponentStatus"
                    Layout.fillWidth: true
                    visible: ["local", "online"].includes(root.tableController.roomSession.aiSource || "")
                             && !root.session.gameOver
                    textFormat: Text.PlainText
                    text: {
                        const status = root.tableController.roomSession.aiStatus || ({})
                        return I18n.modelStatusLabel(status.state || "waiting", status.code || "")
                    }
                    color: (root.tableController.roomSession.aiStatus || ({})).state === "paused"
                           ? Theme.warning : Theme.textSecondary
                    font.pixelSize: Theme.fontSize(12)
                    wrapMode: Text.WordWrap
                }
                AppButton {
                    objectName: "modelOpponentRetry"
                    Layout.fillWidth: true
                    visible: ["local", "online"].includes(root.tableController.roomSession.aiSource || "")
                             && (root.tableController.roomSession.aiStatus || ({})).state === "paused"
                             && root.tableController.roomSession.host && !root.session.gameOver
                    text: qsTr("Retry model decision")
                    compact: true
                    enabled: root.tableController.roomConnected
                    onClicked: root.tableController.wsModel.retryModelOpponent()
                }
                AppButton {
                    objectName: "modelOpponentSettings"
                    Layout.fillWidth: true
                    visible: ["local", "online"].includes(root.tableController.roomSession.aiSource || "")
                             && (root.tableController.roomSession.aiStatus || ({})).state === "paused"
                             && root.tableController.roomSession.host && !root.session.gameOver
                    text: qsTr("Model connection settings")
                    variant: "ghost"
                    compact: true
                    onClicked: root.appWindow.pushScreen("screens/ModelSettings.qml",
                        {source:root.tableController.roomSession.aiSource})
                }

                Text {
                    objectName: "forgeHostConnectionStatus"
                    Layout.fillWidth: true
                    visible: root.tableController.hostingPaused === true
                    textFormat: Text.PlainText
                    text: root.tableController.roomSession.hostStatus && root.tableController.roomSession.hostStatus.migrating === true
                        ? qsTr("Verifying host transfer… The game is paused.")
                        : qsTr("Waiting for the host to reconnect… The game is paused.")
                    color: Theme.warning
                    font.pixelSize: Theme.fontSize(11)
                    wrapMode: Text.WordWrap
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Theme.size(2)
                    visible: !root.tableController.sideboarding
                    Text {
                        objectName: "forgeTurnIndicator"
                        textFormat: Text.PlainText
                        Layout.fillWidth: true
                        text: root.session.gameOver ? qsTr("Game finished") : root.turnOwner
                        color: root.session.activeSeat === root.tableController.localSeat ? Theme.accent : Theme.text
                        font.pixelSize: Theme.fontSize(16)
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }
                    Text {
                        objectName: "forgeTurnPhase"
                        textFormat: Text.PlainText
                        Layout.fillWidth: true
                        text: qsTr("Turn %1 · %2").arg(root.session.turn).arg(root.tableController.stepLabel(root.session.step))
                        color: Theme.textSecondary
                        font.pixelSize: Theme.fontSize(12)
                        elide: Text.ElideRight
                    }
                }
            }
        }
    }
    RulesCardChoiceDialog {
        id: cardChoiceDialog
        tableController: root.tableController
    }
    RulesDamageDialog {
        id: damageDialog
        tableController: root.tableController
    }
    ForgeStack {
        id: stackPanel
        objectName: "forgeStack"
        defaultX: decisionDock.visible && defaultY + height > decisionDock.y
            ? Math.max(root.boardLeft, decisionDock.x - width - 12 * root.unit) : root.boardRight - width
        defaultY: Math.min(80 * root.unit, Math.max(12 * root.unit, decisionDock.y - height - 12 * root.unit))
        movementBounds: Qt.rect(root.boardLeft, 12 * root.unit, root.boardWidth,
            Math.max(0, root.handTop - 24 * root.unit))
        width: collapsed ? Math.min(180 * root.unit, decisionDock.width) : decisionDock.width
        height: collapsed ? headerHeight : Math.min(implicitHeight, 365 * root.unit, movementBounds.height)
        z: 140
        tableController: root.tableController
        unit: root.unit
        locatedId: root.stackTarget && root.stackTarget.kind === "spell" ? root.stackTarget.objectId : ""
        onTargetRequested: target => {
            inspectionDock.inspector.hidePreview(null)
            if (target.kind === "card" && !root.reveal(target.objectId)) root.tableController.openCardDetails(target.objectId)
            else if (target.kind === "spell") stackPanel.reveal(target.objectId)
        }
        visible: count > 0 && !root.tableController.sideboarding
    }
    ForgeArrow {
        objectName: "forgeStackTargetArrow"
        anchors.fill: parent
        z: 80
        unit: root.unit
        visible: startPoint.x !== 0 && endPoint.x !== 0 && !root.tableController.sideboarding && !root.modalOpen
        startPoint: stackPanel.activeEntry ? stackPanel.pointFor(stackPanel.activeEntry.objectId, root) : Qt.point(0, 0)
        endPoint: {
            const target = root.stackTarget
            if (!target) return Qt.point(0, 0)
            if (target.kind === "player") return root.playerPoint(target.seat)
            if (target.kind === "spell") return stackPanel.pointFor(target.objectId, root)
            return root.pointFor(target.objectId)
        }
    }
    RulesInspectionDock {
        id: inspectionDock
        verticalInspection: true
        externalHoverPreview: true
        embedGameLog: false
        x: root.width - width - 24 * root.unit
        y: settingsButton.y + settingsButton.height + 8 * root.unit
        width: root.sidePanelWidth
        height: root.height - y - 16 * root.unit
        tableController: root.tableController
        visible: inspector.pinned && !inspector.previewCardId.length
            && !root.tableController.sideboarding
        radius: 10 * root.unit
        border.width: 0
        z: 100
    }
    TableGameLogRail {
        id: floatingLog
        floating: true
        tableController: root.tableController
        floatingDefaultY: settingsButton.y + settingsButton.height + 8 * root.unit
        floatingDefaultWidth: root.sidePanelWidth
        floatingDefaultHeight: Math.max(Theme.size(280),
                                        root.height - floatingDefaultY
                                        - 16 * root.unit)
        floatingAvoidItem: inspectionDock
        z: 150
    }
    RulesCardHoverPreview {
        tableController: root.tableController
        inspector: inspectionDock.inspector
    }
    Loader {
        objectName: "rulesSideboardLoader"
        anchors.fill: parent
        active: root.tableController.sideboarding
        visible: active
        sourceComponent: Component {
            SideboardPanel {
                objectName: "rulesSideboardPanel"
                enabled: root.tableController.roomConnected
                wsModel: root.tableController.wsModel
                rulesSession: root.session
                gameTableModel: root.tableController.gameTableModel
                tableModel: root.tableController.sideboardTableModel
                cardCatalogModel: root.tableController.cardCatalogModel
                trailingChromeWidth: settingsButton.width + 24 * root.unit
            }
        }
    }
}
