// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import Hexproof.Native 1.0

Rectangle {
    id: root
    required property var tableController
    readonly property var appWindow: ApplicationWindow.window
    property alias inspectionDock: inspectionPanel
    property alias decisionDock: decisionPanel
    property alias gameLogRail: floatingLog
    readonly property bool suppressHoverDuringDecision: false
    readonly property bool cardChoiceActive: cardChoiceDialog.requested
    readonly property bool damageChoiceActive: damageDialog.requested
    readonly property bool decisionDialogActive: cardChoiceActive || damageChoiceActive
    readonly property bool inspectingDecision:
        (cardChoiceActive && cardChoiceDialog.inspectingBattlefield)
        || (damageChoiceActive && damageDialog.inspectingBattlefield)
    readonly property bool modalOpen: gameMenu.opened || zonePopup.opened || hostingOptions.opened || phaseOverview.opened
        || cardChoiceDialog.visible || damageDialog.visible
        || tableController.feedbackInteractionOpen === true
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
    readonly property bool hasVisibleArrows: {
        if ((combatAimArrow.visible && combatAimArrow.validAnchors)
            || (stackTargetArrow.visible && stackTargetArrow.validAnchors)) return true
        for (const repeater of [relationshipArrows, combatArrows, replayArrows]) {
            for (let index = 0; index < repeater.count; ++index) {
                const arrow = repeater.itemAt(index) as ForgeArrow
                if (arrow && arrow.visible && arrow.validAnchors) return true
            }
        }
        return false
    }
    // One geometry cache for every relationship, including pointer aiming.
    // Idle tables do not walk cards, and moving an arrow does not rescan text.
    property var arrowTextRects: []
    readonly property var pendingArrowTextRects: collectArrowReadouts()
    property bool arrowReadoutsDirty: false
    function collectArrowReadouts() {
        if (!root.hasVisibleArrows) return []
        let rects = multiplayerBoard.readoutRects(root)
        // Preserve the transparent public phase strip without drawing a
        // relationship through its labels or changing the curve's targets.
        if (phaseTrack.visible) {
            const painted = phaseTrack.compactMode ? currentPhase : phaseTrack
            void phaseTrack.x; void phaseTrack.y; void painted.x; void painted.y
            void painted.width; void painted.height
            rects.push(painted.mapToItem(root, 0, 0, painted.width, painted.height))
        }
        for (const lane of root.permanentLanes)
            rects = rects.concat(lane.readoutRects(root))
        return rects
    }
    // Transform notifications can precede their updated scene coordinates.
    // Keep intermediate changes out of every curve, then read the complete
    // painted geometry during polish, including immediately requested frames.
    onPendingArrowTextRectsChanged: {
        arrowReadoutsDirty = true
        readoutPolish.request()
    }
    FramePolish {
        id: readoutPolish
        onReady: {
            if (root.arrowReadoutsDirty) {
                root.arrowReadoutsDirty = false
                root.arrowTextRects = root.collectArrowReadouts()
            }
        }
    }
    readonly property bool commanderFormat: ["duel", "edh"].includes(tableController.roomSession.format)
    readonly property bool commandZoneAvailable: commanderFormat
        || playerSeats.some(seat => tableController.zoneCount(seat, "command") > 0)
    readonly property var browsableZones: commandZoneAvailable
        ? ["library", "graveyard", "exile", "command"] : ["library", "graveyard", "exile"]
    readonly property bool sidePanelOpen: !tableController.sideboarding
        && inspectionPanel.inspector.pinned
    readonly property real sidePanelWidth: Math.min(width * 0.4, Math.max(284 * unit, Theme.size(240)))
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
    // The duel phase/status overlays never subtract space from either field.
    // Multiplayer retains its original narrow phase seam, sized only for the
    // readable phase strip rather than an additional status row.
    readonly property real centerBandHeight: !multiplayer ? 12 * unit
        : phaseTrackVisible ? Math.max(22 * unit, phaseTrack.height + 4 * unit) : 6 * unit
    readonly property real ownBattlefieldTop: battlefieldMiddle + centerBandHeight / 2
    readonly property real laneHeight: (battlefieldBottom - battlefieldTop - centerBandHeight) / 2
    readonly property real landFaceWidth: 108 * unit
    readonly property real otherFaceWidth: 108 * unit
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
    readonly property int actionClockRunningSeat: tableController.roomSession.actionClockRunning === undefined
        ? -1 : tableController.roomSession.actionClockRunning
    onActionClockRunningSeatChanged: actionClockMarked = Date.now()
    readonly property var actionClockBasis: tableController.roomSession.actionClockEnabled === false
        ? [] : tableController.roomSession.actionClockMs || []
    // The center strip is the same public log as the rail. Localize it here so
    // a phase reads "Begin combat" instead of the engine step id.
    function recentLogLine(entry) {
        if (!entry || !entry.text)
            return ""
        const seat = entry.seat !== undefined ? Number(entry.seat) : -1
        const actor = seat >= 0 && tableController.matchUi
                ? tableController.matchUi.playerName(seat) : ""
        const resolve = name => tableController.cardDisplayName
                ? tableController.cardDisplayName(name) : name
        return I18n.gameLog(String(entry.kind || ""), String(entry.text), resolve, actor)
    }
    function actionClockText(seat) {
        void actionClockTick
        const basis = actionClockBasis
        if (!basis || seat < 0 || seat >= basis.length)
            return ""
        let remaining = Number(basis[seat])
        if (!Number.isFinite(remaining))
            return ""
        if (actionClockRunningSeat === seat && actionClockMarked > 0)
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
    readonly property bool stagingMotion: motionOverlay.staging
    readonly property var opponentChangeIds: motionOverlay.changedIds
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

    property bool pinnedHoverGuard: false
    property point pinnedPointerPosition: Qt.point(0, 0)
    property var deferredHover: null
    function preparePinnedInspection() {
        pinnedPointerPosition = inspectionPointer.point.scenePosition
        pinnedHoverGuard = true
        deferredHover = null
    }
    function clearPinnedHoverGuard() {
        pinnedHoverGuard = false
        deferredHover = null
    }
    function pointerMovedSincePin() {
        const point = inspectionPointer.point.scenePosition
        return Math.abs(point.x - pinnedPointerPosition.x) > 0.5
            || Math.abs(point.y - pinnedPointerPosition.y) > 0.5
    }
    function acceptCardPreview(cardId, source, keyboardFocus) {
        if (!pinnedHoverGuard || keyboardFocus === true) return true
        if (pointerMovedSincePin()) {
            pinnedHoverGuard = false
            deferredHover = null
            return true
        }
        // Reserving the inspection column can move another card underneath
        // a stationary pointer. That enter is layout, not an inspection intent.
        deferredHover = {cardId:cardId, source:source}
        return false
    }
    function resumePointerInspection() {
        if (!pinnedHoverGuard || !pointerMovedSincePin()) return
        pinnedHoverGuard = false
        const pending = deferredHover
        deferredHover = null
        if (!pending || !pending.source || !pending.source.visible
                || pending.source.pointerPreviewActive === false) return
        // A child may have received enter before this passive root tracker.
        // Resume its current hover without requiring a second leave/enter.
        const scene = inspectionPointer.point.scenePosition
        const point = pending.source.mapFromItem(null, scene.x, scene.y)
        if (pending.source.contains(point))
            tableController.previewCard(pending.cardId, pending.source)
    }
    HoverHandler {
        id: inspectionPointer
        objectName: "forgeInspectionPointer"
        blocking: false
        onPointChanged: root.resumePointerInspection()
    }
    Connections {
        target: inspectionPanel.inspector
        function onPinnedCardIdChanged() {
            if (!inspectionPanel.inspector.pinnedCardId.length)
                root.clearPinnedHoverGuard()
        }
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

    // Only the resting controls reserve battlefield space. Longer choices
    // expand as a hideable overlay without moving permanent rows. Reserving
    // their maximum height while idle leaves a large empty right-hand corner.
    readonly property bool reservesDock: !multiplayer
    readonly property real dockReservedHeight: Math.max(0, Math.min(height - 24 * unit, Theme.size(120)))
    readonly property real boardDecisionHeight: Math.max(0, Math.min(height - 24 * unit, Theme.size(268)))
    readonly property rect dockReservation: Qt.rect(decisionPanel.x, height - 12 * unit - dockReservedHeight,
        decisionPanel.width, dockReservedHeight)
    // Battlefield decisions retain their readable scrolling budget. The user
    // can hide the choice while selecting cards under its expanded portion.
    readonly property bool boardDecision: !decisionPanel.expanded || (!decisionPanel.actionPicker.opened
        && !decisionPanel.listChoiceShown
        && ["chooseAction", "payManaCost", "chooseBoardTargets", "chooseAttackers", "chooseBlockers"]
            .includes(session.promptKind))
    readonly property bool modelOpponent: ["local", "online"].includes(tableController.roomSession.aiSource || "")
    readonly property bool modelPaused: modelOpponent && (tableController.roomSession.aiStatus || ({})).state === "paused"
    readonly property bool modelStatusShown: modelOpponent && !session.gameOver
        && (!decisionPanel.showsBody || modelPaused)
    readonly property bool modelRecoveryShown: modelPaused && tableController.roomSession.host && !session.gameOver
    readonly property bool dockTurnShown: !tableController.sideboarding && !decisionPanel.showsBody
    readonly property bool decisionCollapsible: decisionPanel.visible
        && (decisionPanel.collapsed
            || decisionPanel.expanded && decisionPanel.targetHeight > dockReservedHeight)
    property Item bottomPlayerPlate: null
    property Item topPlayerPlate: null
    readonly property var permanentLanes: [ownCreatures, opponentCreatures, ownLands, opponentLands,
        ownPlaneswalkers, opponentPlaneswalkers, ownOther, opponentOther]
    // Preserve the actual holes between controls instead of truncating each
    // horizontal band at its first obstacle. All rectangles include a margin.
    readonly property var battlefieldObstacles: {
        const panels = [settingsButton, matchSummary]
        if (decisionPanel.visible) panels.push(root.dockReservation)
        if (!root.multiplayer) panels.push(root.bottomPlayerPlate, root.topPlayerPlate)
        const rects = [], margin = 12 * root.unit
        for (const panel of panels) {
            if (!panel || panel.visible === false || panel.width <= 0 || panel.height <= 0) continue
            rects.push(Qt.rect(panel.x - margin, panel.y - margin,
                panel.width + 2 * margin, panel.height + 2 * margin))
        }
        return rects
    }
    function fieldObstacles(originX, originY) {
        return root.battlefieldObstacles.map(rect => Qt.rect(rect.x - originX, rect.y - originY,
            rect.width, rect.height))
    }

    function unobscuredRight(top, extent, occupiedLeft, occupiedRight) {
        let right = root.boardRight
        // Keep native decision controls clear of cards. The movable stack
        // floats over the battlefield and never reserves a column.
        const panels = settingsButton.visible ? [settingsButton] : []
        if (matchSummary.visible) panels.push(matchSummary)
        // Multiplayer fields keep their width. The dock covers the corner
        // instead of pushing cards aside.
        if (decisionPanel.visible && root.reservesDock) panels.push(root.dockReservation)
        // Reserve both complete player plates, including the permanent life
        // change gap. Taller translated identities can reach the far support row.
        if (!root.multiplayer)
            for (const plate of [root.bottomPlayerPlate, root.topPlayerPlate])
                if (plate && plate.visible) panels.push(plate)
        for (const panel of panels) {
            if (occupiedLeft !== undefined && occupiedRight !== undefined
                    && (occupiedRight <= panel.x - 12 * root.unit
                        || occupiedLeft >= panel.x + panel.width + 12 * root.unit))
                continue
            if (top < panel.y + panel.height && top + extent > panel.y)
                right = Math.min(right, panel.x - 12 * root.unit)
        }
        return right
    }
    function laneWidth(top, laneHeight, occupiedLeft, occupiedRight) {
        return Math.max(0, unobscuredRight(top, laneHeight,
            occupiedLeft === undefined ? undefined : root.boardLeft + occupiedLeft,
            occupiedRight === undefined ? undefined : root.boardLeft + occupiedRight) - root.boardLeft)
    }

    // Overlay avoidance reads painted cards directly, including when no hover
    // or arrow is active. None of these bounds feed back into field allocation.
    readonly property var overlayControlRects: {
        if (!phaseTrackVisible) return []
        const items = [opponentZoneStrip, ownZoneStrip, settingsButton, matchSummary,
            errorBanner, decisionPanel, stackPanel, floatingLog, inspectionPanel,
            opponentDecidingBanner]
        for (const item of root.children)
            if ((item as PlayerPlate) || (item as ForgeManaPool)) items.push(item)
        const rects = []
        for (const item of items) {
            if (!item.visible || item.width <= 0 || item.height <= 0) continue
            void item.x; void item.y
            rects.push(item.mapToItem(root, 0, 0, item.width, item.height))
        }
        return rects
    }
    readonly property var overlayCardRects: {
        if (!recentActions.requested) return []
        let rects = multiplayerBoard.inspectionRects(root).concat(overlayControlRects)
        for (const lane of root.permanentLanes)
            rects = rects.concat(lane.inspectionRects(root))
        return rects
    }
    // Observe every readout dependency without traversing all cards for each
    // individual geometry notification. Evaluate only when the frame polishes.
    readonly property var overlayCardReadoutRects: overlayReadoutPolish.value || []
    FramePolish {
        id: overlayReadoutPolish
        expression: root.collectOverlayReadouts()
    }
    function collectOverlayReadouts() {
        if (!turnCallout.visible) return []
        let rects = multiplayerBoard.readoutRects(root)
        for (const lane of root.permanentLanes)
            rects = rects.concat(lane.readoutRects(root))
        return rects
    }
    function clearOverlayTop(left, width, height, preferred, rects, minimumTop = battlefieldTop) {
        const gap = 2 * unit
        const relevant = rects.filter(rect => left < rect.x + rect.width + gap
            && left + width > rect.x - gap)
        const candidates = [preferred]
        for (const rect of relevant)
            candidates.push(rect.y - height - gap, rect.y + rect.height + gap)
        let best = NaN, distance = Infinity
        for (const y of new Set(candidates)) {
            if (y < minimumTop || y + height > battlefieldBottom) continue
            if (relevant.some(rect => y < rect.y + rect.height + gap
                && y + height > rect.y - gap)) continue
            if (y === preferred) return y
            if (Math.abs(y - preferred) < distance) {
                best = y
                distance = Math.abs(y - preferred)
            }
        }
        return best
    }
    function clearOverlayLeft(width, top, height, rects) {
        const gap = 2 * unit
        const preferred = boardLeft + (boardWidth - width) / 2
        const relevant = rects.filter(rect => top < rect.y + rect.height + gap
            && top + height > rect.y - gap)
        const candidates = [preferred, boardLeft, boardRight - width]
        for (const rect of relevant)
            candidates.push(rect.x - width - gap, rect.x + rect.width + gap)
        let best = NaN, distance = Infinity
        for (const x of new Set(candidates)) {
            if (x < boardLeft || x + width > boardRight) continue
            if (relevant.some(rect => x < rect.x + rect.width + gap
                && x + width > rect.x - gap)) continue
            if (x === preferred) return x
            if (Math.abs(x - preferred) < distance) {
                best = x
                distance = Math.abs(x - preferred)
            }
        }
        return best
    }

    function centralCalloutGeometry(width, textHeight, center) {
        const left = (root.width - width) / 2
        const fullHeight = Math.min(textHeight + 36 * unit, root.height - 24 * unit)
        const fullTop = center - fullHeight / 2
        const rects = overlayCardReadoutRects
        const gap = 2 * unit
        const clear = !rects.some(rect => left < rect.x + rect.width + gap
            && left + width > rect.x - gap && fullTop < rect.y + rect.height + gap
            && fullTop + fullHeight > rect.y - gap)
        if (clear) return Qt.point(fullTop, fullHeight)
        // Keep the original headline and central composition. Only reduce its
        // background padding when the restored field seam leaves less space.
        const height = Math.min(textHeight + 4 * unit, fullHeight)
        const preferred = center - height / 2
        const top = clearOverlayTop(left, width, height, preferred, rects, preferred - 12 * unit)
        return Qt.point(Number.isFinite(top) && Math.abs(top - preferred) <= 12 * unit
            ? top : preferred, height)
    }

    function arrivalDelay(id) { return motionOverlay.arrivalDelay(id) }
    function pointFor(id) {
        if (multiplayer) return multiplayerBoard.pointFor(id, root)
        const lanes = root.permanentLanes
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
        for (const lane of root.permanentLanes) {
            if (lane.reveal(id)) return true
        }
        return false
    }
    function uncoverRevealedCard(item) {
        if (!item || !decisionPanel.visible || !decisionPanel.showsBody
                || decisionPanel.targetHeight <= dockReservedHeight) return
        const face = item.mapToItem(root, 0, 0, item.width, item.height)
        if (face.x < decisionPanel.x + decisionPanel.width && face.x + face.width > decisionPanel.x
                && face.y < decisionPanel.y + decisionPanel.height && face.y + face.height > decisionPanel.y) {
            // Exact-object navigation and keyboard focus must expose the card
            // immediately. Hiding preserves the current decision and draft.
            decisionPanel.collapsed = true
            decisionPanel.settleHeight()
        }
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
                phaseOverview.close()
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
        function onLocalSeatChanged() { zonePopup.close(); phaseOverview.close(); stackPanel.clearSelection(); inspectionPanel.inspector.clear() }
        function onHandOwnerSeatChanged() { inspectionPanel.inspector.clear() }
        function onRoomConnectedChanged() {
            if (!root.tableController.roomConnected) { gameMenu.close(); zonePopup.close(); phaseOverview.close() }
        }
        function onSideboardingChanged() {
            if (root.tableController.sideboarding) { gameMenu.close(); zonePopup.close(); phaseOverview.close() }
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
    Rectangle {
        id: matchSummary
        objectName: "forgeMatchSummary"
        visible: !root.replayMode && !root.tableController.sideboarding
            && !root.multiplayer && root.tableController.roomSession.matchMode === "bo3"
            && root.session.active
        x: root.width - width - 16 * root.unit
        y: settingsButton.y + settingsButton.height + 6 * root.unit
        width: Math.min(root.width * 0.3, matchSummaryLabel.implicitWidth + 20 * root.unit)
        height: matchSummaryLabel.implicitHeight + 12 * root.unit
        radius: height / 2
        z: 85
        color: Theme.surface
        border.width: 1
        border.color: Theme.withAlpha(Theme.primary, 0.25)
        Text {
            id: matchSummaryLabel
            objectName: "forgeMatchSummaryText"
            anchors.fill: parent
            anchors.leftMargin: 10 * root.unit
            anchors.rightMargin: 10 * root.unit
            textFormat: Text.PlainText
            text: qsTranslate("RulesTableActionRail", "Game %1 · %2")
                .arg(root.tableController.gameSession.gameNumber)
                .arg(root.tableController.matchUi.scoreSummary())
            color: Theme.textSecondary
            font.pixelSize: 11 * root.unit
            font.weight: Font.DemiBold
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
        }
    }
    InfoBanner {
        id: errorBanner
        objectName: "rulesErrorBanner"
        x: 20 * root.unit
        y: 3 * root.unit
        width: 300 * root.unit
        z: 85
        message: root.replayMode ? "" : I18n.status(root.tableController.wsModel.lastError || "")
        Rectangle {
            anchors.fill: parent
            z: -1
            radius: Theme.useGlass ? Theme.radiusLarge : Theme.radiusMedium
            color: Theme.surface
        }
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
        onIsBottomChanged: {
            if (isBottom) root.bottomPlayerPlate = plate
            else if (root.bottomPlayerPlate === plate) root.bottomPlayerPlate = null
            if (!isBottom) root.topPlayerPlate = plate
            else if (root.topPlayerPlate === plate) root.topPlayerPlate = null
        }
        Component.onCompleted: {
            if (isBottom) root.bottomPlayerPlate = plate
            else root.topPlayerPlate = plate
        }
        Component.onDestruction: {
            if (root.bottomPlayerPlate === plate) root.bottomPlayerPlate = null
            if (root.topPlayerPlate === plate) root.topPlayerPlate = null
        }
        readonly property bool activeTurn: root.session.activeSeat === seat && root.session.active && root.session.turn > 0
        readonly property bool offered: root.tableController.combatInteraction.active
            ? root.tableController.combatInteraction.seatOffered(seat) : root.tableController.interaction.seatOffered(seat)
        readonly property bool actionable: offered && (root.tableController.combatInteraction.active
            ? root.tableController.combatInteraction.canAct : root.tableController.interaction.canRespond)
        readonly property bool waiting: offered && root.tableController.interaction.waitingForResponse
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
        readonly property real restingX: root.replayMode ? root.boardRight - root.replayInfoWidth + 20 * root.unit
            : root.centerLeft + (root.centerWidth - width) / 2
        readonly property real restingY: isBottom
            ? root.handTop - identity.height - lifeReadout.deltaClearance - discSize + 4 * root.unit
            : 4 * root.unit
        readonly property bool avoidsDecision: isBottom && !root.replayMode && decisionPanel.visible
            && restingX < decisionPanel.x + decisionPanel.width && restingX + width > decisionPanel.x
            && restingY < decisionPanel.y + decisionPanel.height && restingY + height > decisionPanel.y
        readonly property bool fitsAboveDecision: decisionPanel.y - height - 12 * root.unit >= root.ownBattlefieldTop
        x: avoidsDecision && !fitsAboveDecision
            ? Math.max(root.boardLeft, decisionPanel.x - width - 12 * root.unit) : restingX
        // The near name sits above the life disc. The disc crosses the hand
        // edge normally; an open inspector can move the decision dock across
        // that position. Keep the complete plate above or beside that dock.
        y: avoidsDecision && fitsAboveDecision ? decisionPanel.y - height - 12 * root.unit : restingY
        width: 168 * root.unit
        // The identity can gain an action-clock row. Keep a permanent gap for
        // the life change's full rise below every public identity row.
        height: identity.height + lifeReadout.deltaClearance + discSize + (isBottom ? 2 : 0) * root.unit
        z: 85
        visible: !root.tableController.sideboarding
        activeFocusOnTab: actionable || activeFocus
        function activate() {
            if (!actionable) {
                if (waiting) root.tableController.interaction.responseBlocked("player", "" + seat)
                return
            }
            if (root.tableController.combatInteraction.active) root.tableController.combatInteraction.activateSeat(seat)
            else root.tableController.interaction.activateSeat(seat)
        }
        Keys.onReturnPressed: activate()
        Keys.onSpacePressed: activate()
        Accessible.role: Accessible.Button
        Accessible.name: displayName + ", " + qsTr("Life %1").arg(life)
        Accessible.onPressAction: activate()
        Rectangle {
            objectName: "forgePlayerIdentityBackdrop-" + plate.seat
            x: identity.x - 4 * root.unit
            y: identity.y - 2 * root.unit
            width: identity.width + 8 * root.unit
            height: identity.height + 4 * root.unit
            radius: 4 * root.unit
            color: Theme.surface
        }
        Column {
            id: identity
            anchors.horizontalCenter: parent.horizontalCenter
            y: 0
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
            objectName: "forgeLifeDisc-" + plate.seat
            width: plate.discSize
            height: width
            radius: width / 2
            anchors.horizontalCenter: parent.horizontalCenter
            y: identity.height + lifeReadout.deltaClearance
            antialiasing: true
            color: Theme.withAlpha(Theme.surface, plate.selected || plate.offered ? 0.88 : 0.62)
            border.width: plate.combatHovered || plate.underAttack ? 4
                          : plate.selected || plate.activeFocus || plate.offered || plate.activeTurn ? 2 : 0
            border.color: plate.underAttack ? "#d4654f"
                          : plate.combatHovered ? Theme.primary : plate.selected || plate.activeFocus ? Theme.accent
                          : plate.offered ? Theme.withAlpha(Theme.primary, plate.waiting ? 0.5 : 1) : Theme.warning
            ForgeLifeReadout {
                id: lifeReadout
                anchors.fill: parent
                life: plate.life
                seat: plate.seat
                unit: root.unit
            }
        }
        TapHandler { enabled: plate.offered; onTapped: plate.activate() }
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
    Item {
        id: phaseTrack
        objectName: "forgePhaseTrack"
        // Probe the maximum two-line strip independently of its actual height,
        // so choosing the compact mode cannot feed back into its own width.
        // Wide tables retain the original single-line phase-strip density.
        readonly property real twoLineHeight: Math.max(18 * root.unit,
            Math.ceil(phaseMetrics.height) * 2 + Theme.size(4))
        readonly property real probeTop: opponentDecidingBanner.visible
            ? Math.min(opponentDecidingBanner.y + opponentDecidingBanner.height + 4 * root.unit,
                       root.battlefieldBottom - twoLineHeight)
            : root.battlefieldMiddle - twoLineHeight / 2
        x: root.boardLeft
        readonly property real preferredTop: opponentDecidingBanner.visible
            ? Math.min(opponentDecidingBanner.y + opponentDecidingBanner.height + 4 * root.unit,
                       root.battlefieldBottom - height)
            : root.battlefieldMiddle - height / 2
        readonly property bool narrowDisclosure: compactMode
        readonly property real disclosureWidth: Math.min(width,
            Math.max(...steps.map(step => labelWidth(step))) + Theme.size(20))
        readonly property point disclosurePlacement: Qt.point(
            x + (width - disclosureWidth) / 2, preferredTop)
        // Match the public overlay anchor. Cards and status changes never
        // push this strip into a separately allocated row or a free pocket.
        y: preferredTop
        width: root.laneWidth(probeTop, twoLineHeight)
        height: compactMode ? twoLineHeight
            : Math.max(18 * root.unit, Math.ceil(phaseMetrics.height) + Theme.size(4))
        z: 45
        visible: root.phaseTrackVisible
        onVisibleChanged: if (!visible) phaseOverview.close()
        readonly property real gap: 2 * root.unit
        readonly property var steps: [
            "untap", "upkeep", "draw", "main1", "begin_combat", "declare_attackers",
            "declare_blockers", "combat_damage", "end_combat", "main2", "end", "cleanup"
        ]
        readonly property bool compactMode: width < Math.max(...steps.map(step => labelWidth(step))) * steps.length
            + gap * (steps.length - 1)
        function labelWidth(step) {
            void phaseMetrics.font.pixelSize
            return Math.ceil(phaseMetrics.advanceWidth(I18n.gamePhaseLabel(step))) + Theme.size(12)
        }
        FontMetrics {
            id: phaseMetrics
            font.pixelSize: Theme.fontSize(11)
            font.weight: Font.DemiBold
        }
        Row {
            anchors.fill: parent
            spacing: phaseTrack.gap
            visible: !phaseTrack.compactMode
            enabled: false
            Repeater {
                model: phaseTrack.steps
                delegate: Rectangle {
                    required property string modelData
                    required property int index
                    objectName: "forgePhase-" + modelData
                    readonly property bool current: root.session.step === modelData
                    readonly property bool past: phaseTrack.steps.indexOf(root.session.step) > index
                    width: Math.max(0, (phaseTrack.width - phaseTrack.gap * 11) / 12)
                    height: phaseTrack.height
                    radius: 3 * root.unit
                    color: current ? Theme.accent : past ? Theme.withAlpha(Theme.accent, 0.28) : Theme.withAlpha("#101820", 0.55)
                    Text {
                        objectName: "forgePhaseLabel-" + modelData
                        anchors.fill: parent
                        anchors.margins: 1
                        textFormat: Text.PlainText
                        text: I18n.gamePhaseLabel(modelData)
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        color: current ? Theme.primaryInk : Theme.text
                        font: phaseMetrics.font
                    }
                }
            }
        }
        Button {
            id: currentPhase
            objectName: "forgeCurrentPhase"
            x: phaseTrack.narrowDisclosure ? phaseTrack.disclosurePlacement.x - phaseTrack.x : 0
            width: phaseTrack.narrowDisclosure ? phaseTrack.disclosureWidth : phaseTrack.width
            height: phaseTrack.height
            visible: phaseTrack.compactMode
            padding: Theme.size(2)
            focusPolicy: Qt.StrongFocus
            hoverEnabled: true
            Accessible.name: qsTranslate("RulesTableActionRail", "Phases") + ": "
                + root.tableController.stepLabel(root.session.step)
            ToolTip.text: root.tableController.stepLabel(root.session.step)
            ToolTip.visible: hovered && !phaseOverview.visible
            ToolTip.delay: 400
            onClicked: phaseOverview.open()
            Keys.onReturnPressed: phaseOverview.open()
            Keys.onEnterPressed: phaseOverview.open()
            background: Rectangle {
                radius: 3 * root.unit
                color: Theme.accent
                border.width: currentPhase.activeFocus ? 2 : 0
                border.color: Theme.text
            }
            contentItem: Item {
                Text {
                    id: currentPhaseLabel
                    objectName: "forgeCurrentPhaseLabel"
                    anchors.fill: parent
                    anchors.rightMargin: Theme.size(16)
                    text: I18n.gamePhaseLabel(root.session.step)
                    textFormat: Text.PlainText
                    color: Theme.primaryInk
                    font: phaseMetrics.font
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    wrapMode: Text.Wrap
                }
                Text {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: "▾"
                    textFormat: Text.PlainText
                    color: Theme.primaryInk
                    font.pixelSize: Theme.fontSize(12)
                }
            }
        }
    }
    AppPopup {
        id: phaseOverview
        objectName: "forgePhaseOverview"
        width: Math.min(Theme.size(360), root.width - Theme.size(24))
        height: Math.min(phaseOverviewContent.implicitHeight + padding * 2, root.height - Theme.size(24))
        padding: Theme.size(12)
        onOpened: phaseList.positionViewAtIndex(phaseList.currentIndex, ListView.Contain)
        contentItem: ColumnLayout {
            id: phaseOverviewContent
            spacing: Theme.size(8)
            AppPopupHeader {
                titleText: qsTranslate("RulesTableActionRail", "Phases")
                showClose: true
                closeObjectName: "forgePhaseOverviewClose"
                onCloseRequested: phaseOverview.close()
            }
            ListView {
                id: phaseList
                objectName: "forgePhaseOverviewList"
                Layout.fillWidth: true
                Layout.fillHeight: true
                implicitHeight: contentHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                model: phaseTrack.steps
                currentIndex: phaseTrack.steps.indexOf(root.session.step)
                onCurrentIndexChanged: if (phaseOverview.opened) positionViewAtIndex(currentIndex, ListView.Contain)
                ScrollBar.vertical: AppScrollBar {}
                delegate: Rectangle {
                    required property string modelData
                    required property int index
                    width: phaseList.width
                    height: Math.max(Theme.size(30), phaseFullLabel.implicitHeight + Theme.size(8))
                    radius: Theme.radiusSmall
                    color: index === phaseList.currentIndex ? Theme.accent
                        : index < phaseList.currentIndex ? Theme.withAlpha(Theme.accent, 0.18) : "transparent"
                    Text {
                        id: phaseFullLabel
                        objectName: "forgePhaseOverviewLabel-" + modelData
                        anchors.fill: parent
                        anchors.margins: Theme.size(4)
                        text: root.tableController.stepLabel(modelData)
                        textFormat: Text.PlainText
                        color: index === phaseList.currentIndex ? Theme.primaryInk : Theme.text
                        font: phaseMetrics.font
                        wrapMode: Text.WordWrap
                        verticalAlignment: Text.AlignVCenter
                    }
                }
            }
        }
    }
    FontMetrics { id: recentActionMetrics; font: actionLabel.font }
    Rectangle {
        id: recentActions
        objectName: "forgeRecentActions"
        readonly property var logEntries: root.tableController.tableGameLog || []
        readonly property string actionText: {
            const log = logEntries
            if (!log.length)
                return ""
            const textOf = entry => root.recentLogLine(entry)
            const latest = textOf(log[log.length - 1])
            const previous = log.length > 1 ? textOf(log[log.length - 2]) : ""
            if (previous && latest && previous !== latest)
                return previous + "   ·   " + latest
            return latest || previous
        }
        readonly property bool requested: actionText.length > 0 && root.phaseTrackVisible
            && !root.modalOpen && !root.tableController.showGameLogRail && !opponentDecidingBanner.visible
        readonly property var placement: {
            if (!requested) return null
            const painted = phaseTrack.compactMode ? currentPhase : phaseTrack
            const phase = painted.mapToItem(root, 0, 0, painted.width, painted.height)
            const rects = root.overlayCardRects.concat([phase])
            const gap = 8 * root.unit
            for (const top of [phase.y + phase.height + gap, phase.y - height - gap]) {
                if (top < root.battlefieldTop || top + height > root.battlefieldBottom) continue
                const left = root.clearOverlayLeft(width, top, height, rects)
                if (Number.isFinite(left)) return Qt.point(left, top)
            }
            return null
        }
        x: placement ? placement.x : root.boardLeft
        y: placement ? placement.y : phaseTrack.y + phaseTrack.height + 8 * root.unit
        z: 85
        width: Math.min(root.boardWidth * 0.72, actionLabel.implicitWidth + 20 * root.unit)
        height: recentActionMetrics.height + 8 * root.unit
        radius: height / 2
        color: Theme.surface
        border.width: 1
        border.color: Theme.borderStrong
        visible: requested && placement !== null
        Text {
            id: actionLabel
            objectName: "forgeRecentActionText"
            anchors.centerIn: parent
            width: Math.min(implicitWidth, root.boardWidth * 0.72 - 20 * root.unit)
            textFormat: Text.PlainText
            text: recentActions.actionText
            color: Theme.text
            font.pixelSize: Theme.fontSize(12)
            elide: Text.ElideRight
            horizontalAlignment: Text.AlignHCenter
        }
        MouseArea {
            anchors.fill: parent
            onClicked: root.tableController.setGameLogVisible(true)
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
            color: Theme.surface
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
        z: 100
        enabled: false
        opacity: 0
        visible: opacity > 0 && !root.modalOpen
        clip: true
        anchors.horizontalCenter: parent.horizontalCenter
        // The full-width near field in a three-seat game has its own seam.
        readonly property real preferredCenter: root.multiplayer && root.playerSeats.length === 3
            ? root.battlefieldMiddle : root.height / 2
        readonly property point placement: root.centralCalloutGeometry(width,
            calloutLabel.implicitHeight, preferredCenter)
        y: placement.x
        width: Math.min(root.width * 0.72, calloutLabel.implicitWidth + 72 * root.unit)
        height: placement.y
        property string message: ""
        property string shownGame: ""
        property int shownSeat: -1
        function present(message) {
            fade.stop()
            fadeIn.stop()
            turnCallout.message = message
            if (Theme.motionEnabled && !Theme.motionSnap) {
                turnCallout.opacity = 0
                fadeIn.start()
            } else {
                turnCallout.opacity = 1
            }
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
            id: fadeIn
            target: turnCallout
            property: "opacity"
            to: 1
            duration: Theme.motionFast
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
        preferCenteredRows: true
        creatureLane: opponentCreatures; landLane: opponentLands; otherLane: opponentOther
        planeswalkerLane: opponentPlaneswalkers
        obstacles: root.fieldObstacles(root.boardLeft, root.battlefieldTop)
    }
    ForgeFieldLayout {
        id: ownFieldLayout
        width: root.boardWidth; height: root.laneHeight; unit: root.unit; nearSide: true
        preferCenteredRows: true
        creatureLane: ownCreatures; landLane: ownLands; otherLane: ownOther
        planeswalkerLane: ownPlaneswalkers
        obstacles: root.fieldObstacles(root.boardLeft, root.ownBattlefieldTop)
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
        id: opponentPlaneswalkers
        objectName: "forgeOpponentPlaneswalkers"
        x: root.boardLeft + opponentFieldLayout.placement.planeswalkers.x
        y: root.battlefieldTop + opponentFieldLayout.placement.planeswalkers.y
        width: opponentFieldLayout.placement.planeswalkers.width
        height: opponentFieldLayout.placement.planeswalkers.height
        tableController: root.tableController
        unit: root.unit
        ownerSeat: root.multiplayer ? -1 : root.topSeat
        category: "planeswalker"
        showCaption: false
        maxFaceWidth: root.otherFaceWidth
        alignRight: true
        alignBottom: true
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
        alignRight: true
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
        y: root.ownBattlefieldTop + ownFieldLayout.placement.creatures.y
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
        id: ownPlaneswalkers
        objectName: "forgeOwnPlaneswalkers"
        x: root.boardLeft + ownFieldLayout.placement.planeswalkers.x
        y: root.ownBattlefieldTop + ownFieldLayout.placement.planeswalkers.y
        width: ownFieldLayout.placement.planeswalkers.width
        height: ownFieldLayout.placement.planeswalkers.height
        tableController: root.tableController
        unit: root.unit
        ownerSeat: root.multiplayer ? -1 : root.bottomSeat
        category: "planeswalker"
        showCaption: false
        maxFaceWidth: root.otherFaceWidth
        alignRight: true
        alignBottom: false
        locatedId: root.locatedId
        visible: !root.multiplayer && !root.tableController.sideboarding
    }
    ForgeCardLane {
        id: ownOther
        objectName: "forgeOwnOther"
        x: root.boardLeft + ownFieldLayout.placement.others.x
        y: root.ownBattlefieldTop + ownFieldLayout.placement.others.y
        width: ownFieldLayout.placement.others.width
        height: ownFieldLayout.placement.others.height
        tableController: root.tableController
        unit: root.unit
        ownerSeat: root.multiplayer ? -1 : root.bottomSeat
        category: "other"
        alignRight: true
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
        y: root.ownBattlefieldTop + ownFieldLayout.placement.lands.y
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
        y: root.ownBattlefieldTop
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
        id: relationshipArrows
        model: root.session.battlefieldRelationships || []
        delegate: ForgeArrow {
            required property var modelData
            objectName: "forgeRelationship-" + modelData.kind + "-" + modelData.sourceId + "-" + modelData.targetId
            anchors.fill: parent
            z: 60
            unit: root.unit
            excludedRects: root.arrowTextRects
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
        id: combatArrows
        model: root.tableController.combatInteraction.links
        delegate: ForgeArrow {
            required property var modelData
            objectName: "forgeCombatArrow-" + modelData.from + "-" + (modelData.player ? "seat-" + modelData.seat : modelData.to)
            anchors.fill: parent
            z: 70
            unit: root.unit
            excludedRects: root.arrowTextRects
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
        excludedRects: root.arrowTextRects
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
        id: hand
        objectName: "forgeHand"
        showCount: !root.multiplayer
        x: root.handLeft
        y: root.handTop
        z: 30
        width: Math.max(0, (root.replayMode ? root.boardRight - root.replayInfoWidth : decisionPanel.x) - x - 20 * root.unit)
        height: root.handBandHeight - 4 * root.unit
        tableController: root.tableController
        unit: root.unit
        visible: !root.tableController.sideboarding
    }
    Rectangle {
        objectName: "forgeHandPriorityGlow"
        x: root.handLeft
        y: root.handTop - 14 * root.unit
        z: 29
        width: Math.max(0, decisionPanel.x - x - 20 * root.unit)
        height: 18 * root.unit
        visible: opacity > 0 && !root.replayMode && !root.tableController.sideboarding
        opacity: root.localPriority ? 1 : 0
        gradient: Gradient {
            GradientStop { position: 0; color: "transparent" }
            GradientStop { position: 1; color: Theme.withAlpha(Theme.primary, 0.5) }
        }
        Behavior on opacity { enabled: Theme.motionEnabled; NumberAnimation { duration: Theme.motionFast } }
    }
    // Live tables never show it, so they do not build its cards.
    Loader {
        id: replayHand
        active: root.replayMode
        x: root.handLeft
        y: 24 * root.unit
        width: Math.max(0, root.boardRight - root.replayInfoWidth - x - 20 * root.unit)
        height: root.handBandHeight - 20 * root.unit
        z: 30
        sourceComponent: ForgeHand {
            objectName: "forgeReplayOpponentHand"
            tableController: root.tableController
            ownerSeat: root.topSeat
            unit: root.unit
        }
    }
    Repeater {
        id: replayArrows
        model: root.replayMode ? root.tableController.replayFrame.combat || [] : []
        delegate: ForgeArrow {
            required property var modelData
            anchors.fill: parent
            z: 55
            unit: root.unit
            excludedRects: root.arrowTextRects
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
        transformOrigin: Item.Center
        readonly property int dialogMotion: Theme.motionEnabled && !Theme.motionSnap ? Theme.motionFast : 0
        // No exit transition: a closing modal popup would swallow clicks.
        enter: Transition {
            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: zonePopup.dialogMotion; easing.type: Easing.OutCubic }
            NumberAnimation { property: "scale"; from: 0.97; to: 1; duration: zonePopup.dialogMotion; easing.type: Easing.OutCubic }
        }
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
        id: decisionPanel
        x: root.width - width - 16 * root.unit
           - (root.sidePanelOpen ? root.sidePanelWidth + 16 * root.unit : 0)
        y: root.height - height - 12 * root.unit
        width: root.multiplayer ? Math.min(root.width * 0.3, Math.max(330 * root.unit, Theme.size(280)))
            : Math.min(root.width * 0.42, Math.max(420 * root.unit, Theme.size(340)))
        readonly property real targetHeight: Math.min(implicitHeight, root.boardDecision
            ? root.boardDecisionHeight : root.height - 24 * root.unit)
        Component.onCompleted: settleHeight()
        function settleHeight() {
            dockHeightAnim.stop()
            height = targetHeight
        }
        // New decisions must expose their enabled controls immediately. Only
        // contraction glides; animating growth clips live choices mid-flight.
        onTargetHeightChanged: {
            if (targetHeight >= height || dockResizeHold.running || !visible
                    || !Theme.motionEnabled || Theme.motionSnap) {
                settleHeight()
                return
            }
            dockHeightAnim.stop()
            dockHeightAnim.from = height
            dockHeightAnim.to = targetHeight
            dockHeightAnim.start()
        }
        NumberAnimation {
            id: dockHeightAnim
            target: decisionPanel
            property: "height"
            duration: Theme.motionNormal
            easing.type: Easing.OutCubic
        }
        Timer { id: dockResizeHold; interval: 250 }
        Connections {
            target: root
            function onWidthChanged() { dockResizeHold.restart(); decisionPanel.settleHeight() }
            function onHeightChanged() { dockResizeHold.restart(); decisionPanel.settleHeight() }
        }
        Connections {
            target: Theme
            function onMotionEpochChanged() { decisionPanel.settleHeight() }
        }
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
        contextControlsShown: root.inspectingDecision || root.tableController.controlledTurnSeat >= 0
            || root.modelStatusShown || root.modelRecoveryShown || root.tableController.hostingPaused === true
            || root.dockTurnShown
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
                    visible: root.modelStatusShown
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
                    visible: root.modelRecoveryShown
                    text: qsTr("Retry model decision")
                    compact: true
                    enabled: root.tableController.roomConnected
                    onClicked: root.tableController.wsModel.retryModelOpponent()
                }
                AppButton {
                    objectName: "modelOpponentSettings"
                    Layout.fillWidth: true
                    visible: root.modelRecoveryShown
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
                    // The phase strip and active-player border still show the
                    // turn while a decision uses the dock.
                    visible: root.dockTurnShown
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
    AppButton {
        id: decisionCollapse
        objectName: "forgeDecisionCollapse"
        // Move this overlay around public controls, never the field or its
        // cards. The collapsed dock's adjacent space can contain a seat header.
        readonly property point placement: {
            const gap = 8 * root.unit
            const preferred = Qt.point(decisionPanel.x - width - gap, decisionPanel.y)
            if (!root.multiplayer || !visible) return preferred
            const obstacles = [Qt.rect(decisionPanel.x, decisionPanel.y,
                decisionPanel.width, decisionPanel.height)]
            for (const seat of root.playerSeats) {
                const field = multiplayerBoard.fieldFor(seat)
                if (field && field.visible) obstacles.push(field.headerRect(root))
            }
            const xs = [preferred.x, decisionPanel.x + decisionPanel.width - width]
            const ys = [preferred.y]
            for (const rect of obstacles)
                ys.push(rect.y - height - gap, rect.y + rect.height + gap)
            let best = preferred, distance = Infinity
            for (const x of xs) {
                if (x < gap || x + width > root.width - gap) continue
                for (const y of ys) {
                    if (y < gap || y + height > root.height - gap) continue
                    if (obstacles.some(rect => x < rect.x + rect.width + gap
                            && x + width > rect.x - gap && y < rect.y + rect.height + gap
                            && y + height > rect.y - gap)) continue
                    const cost = Math.abs(x - preferred.x) + Math.abs(y - preferred.y)
                    if (cost < distance) { best = Qt.point(x, y); distance = cost }
                }
            }
            return best
        }
        x: placement.x
        y: placement.y
        z: 181
        visible: root.decisionCollapsible
        compact: true
        text: decisionPanel.collapsed ? qsTr("Show choice") : qsTr("Hide choice")
        onClicked: decisionPanel.collapsed = !decisionPanel.collapsed
    }
    ForgeMotionOverlay {
        id: motionOverlay
        objectName: "forgeMotionOverlay"
        tableController: root.tableController
        surface: root
    }
    // Any press finishes running motion first. The handler only observes, so
    // the press still reaches whatever is underneath.
    Item {
        anchors.fill: parent
        z: 2000
        enabled: Theme.motionEnabled
        PointHandler {
            acceptedButtons: Qt.AllButtons
            onActiveChanged: if (active) Theme.finishMotion()
        }
    }
    Rectangle {
        id: waitingCue
        objectName: "forgeWaitingCue"
        property bool shown: false
        x: decisionPanel.x + (decisionPanel.width - width) / 2
        y: Math.max(8 * root.unit, decisionPanel.y - height - 8 * root.unit)
        z: 182
        width: waitingCueText.implicitWidth + 24 * root.unit
        height: waitingCueText.implicitHeight + 12 * root.unit
        radius: height / 2
        color: Theme.withAlpha(Theme.surface, 0.94)
        border.width: 1
        border.color: Theme.primary
        visible: opacity > 0
        opacity: shown ? 1 : 0
        Behavior on opacity { enabled: Theme.motionEnabled; NumberAnimation { duration: Theme.motionFast } }
        property string message: qsTranslate("RulesActionBar", "Waiting for the game")
        Text {
            id: waitingCueText
            objectName: "forgeWaitingCueText"
            anchors.centerIn: parent
            textFormat: Text.PlainText
            text: waitingCue.message
            color: Theme.text
            font.pixelSize: Theme.fontSize(12)
            font.weight: Font.DemiBold
        }
        Timer {
            id: waitingCueTimer
            interval: 1500
            onTriggered: waitingCue.shown = false
        }
        Connections {
            target: root.tableController.interaction
            function onResponseBlocked() {
                waitingCue.message = qsTranslate("RulesActionBar", "Waiting for the game")
                waitingCue.shown = true
                waitingCueTimer.restart()
            }
            function onPaymentQueueCleared() {
                waitingCue.message = qsTr("Queued mana was cleared")
                waitingCue.shown = true
                waitingCueTimer.restart()
            }
            function onWaitingForResponseChanged() {
                if (!root.tableController.interaction.waitingForResponse)
                    waitingCue.shown = false
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
        defaultX: decisionPanel.visible && defaultY + height > decisionPanel.y
            ? Math.max(root.boardLeft, decisionPanel.x - width - 12 * root.unit) : root.boardRight - width
        defaultY: Math.min(Math.max(80 * root.unit, matchSummary.visible
            ? matchSummary.y + matchSummary.height + 8 * root.unit : 0),
            Math.max(12 * root.unit, decisionPanel.y - height - 12 * root.unit))
        movementBounds: Qt.rect(root.boardLeft, 12 * root.unit, root.boardWidth,
            Math.max(0, root.handTop - 24 * root.unit))
        width: collapsed ? Math.min(180 * root.unit, decisionPanel.width) : decisionPanel.width
        height: collapsed ? headerHeight : Math.min(implicitHeight, 365 * root.unit, movementBounds.height)
        z: 140
        tableController: root.tableController
        unit: root.unit
        locatedId: root.stackTarget && root.stackTarget.kind === "spell" ? root.stackTarget.objectId : ""
        onTargetRequested: target => {
            inspectionPanel.inspector.hidePreview(null)
            if (target.kind === "card" && !root.reveal(target.objectId)) root.tableController.openCardDetails(target.objectId)
            else if (target.kind === "spell") stackPanel.reveal(target.objectId)
        }
        visible: count > 0 && !root.tableController.sideboarding
    }
    ForgeArrow {
        id: stackTargetArrow
        objectName: "forgeStackTargetArrow"
        anchors.fill: parent
        z: 80
        unit: root.unit
        excludedRects: root.arrowTextRects
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
        id: inspectionPanel
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
        floatingAvoidItem: inspectionPanel
        z: 150
    }
    function hoverContentRects() {
        // Read only live presentation geometry. No catalog lookups or private
        // identities are needed, and idle tables do not collect these bounds.
        if (!inspectionPanel.inspector.previewCardId.length) return []
        let rects = multiplayerBoard.inspectionRects(root)
        for (const lane of root.permanentLanes)
            rects = rects.concat(lane.inspectionRects(root))
        const items = [opponentZoneStrip, ownZoneStrip,
            phaseTrack.compactMode ? currentPhase : phaseTrack, recentActions,
            opponentDecidingBanner, matchSummary, settingsButton, errorBanner,
            stackPanel, floatingLog, inspectionPanel, decisionCollapse, waitingCue, turnCallout]
        if (replayHand.active && replayHand.item) items.push(replayHand)
        // Two-player identity/life plates and mana readouts are direct children.
        // Multiplayer headers come from their field's explicit geometry above.
        for (const item of root.children) {
            if ((item as PlayerPlate) || (item as ForgeManaPool))
                items.push(item)
        }
        for (const item of items) {
            if (!item.visible || item.width <= 0 || item.height <= 0) continue
            void item.x; void item.y
            rects.push(item.mapToItem(root, 0, 0, item.width, item.height))
        }
        return rects
    }
    function hoverProtectedRects() {
        const rects = []
        // Arrow items span the table; protect their actual curve hull rather
        // than that full item rectangle. The quadratic control point lies in
        // the endpoint hull, so this also protects its bend and arrowhead.
        for (const item of root.children) {
            if (!item.visible || !item.objectName
                    || !(item.objectName.startsWith("forgeRelationship-")
                         || item.objectName.startsWith("forgeCombatArrow-")
                         || item.objectName === "forgeCombatAimArrow")) continue
            const arrow = item as ForgeArrow
            if (!arrow || !arrow.validAnchors) continue
            const start = arrow.startPoint, end = arrow.endPoint
            const pad = 14 * root.unit
            rects.push(Qt.rect(Math.min(start.x, end.x) - pad, Math.min(start.y, end.y) - pad,
                Math.abs(start.x - end.x) + 2 * pad, Math.abs(start.y - end.y) + 2 * pad))
        }
        return rects
    }
    RulesCardHoverPreview {
        tableController: root.tableController
        inspector: inspectionPanel.inspector
        obstacle: decisionPanel.visible
            ? Qt.rect(decisionPanel.x, decisionPanel.y, decisionPanel.width, decisionPanel.height)
            : Qt.rect(0, 0, 0, 0)
        contentRects: root.hoverContentRects()
        protectedRects: root.hoverProtectedRects()
        avoidRects: hand.visible && hand.visibleCards.length
            ? [Qt.rect(hand.x, hand.y - 20 * root.unit, hand.width,
                       root.height - hand.y + 20 * root.unit)] : []
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
