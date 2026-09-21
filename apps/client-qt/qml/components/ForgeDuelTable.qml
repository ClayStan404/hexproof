// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

Rectangle {
    id: root
    required property var tableController
    property alias inspectionDock: inspectionDock
    property alias decisionDock: decisionDock
    property alias gameLogRail: floatingLog
    readonly property bool suppressHoverDuringDecision: false
    readonly property bool cardChoiceActive: cardChoiceDialog.requested
    readonly property bool damageChoiceActive: damageDialog.requested
    readonly property bool decisionDialogActive: cardChoiceActive || damageChoiceActive
    readonly property bool modalOpen: gameMenu.opened || zonePopup.opened || hostingOptions.opened
        || cardChoiceDialog.visible || damageDialog.visible
    readonly property real unit: Math.min(width / 1600, height / 1000)
    readonly property int bottomSeat: tableController.handOwnerSeat >= 0 ? tableController.handOwnerSeat : 0
    readonly property int topSeat: bottomSeat === 0 ? 1 : 0
    readonly property var session: tableController.rulesSession
    readonly property bool commanderFormat: tableController.roomSession.format === "duel"
    readonly property var browsableZones: commanderFormat
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
    readonly property real handLeft: boardLeft + zoneRowWidth + 10 * unit
    readonly property real centerLeft: boardLeft
    readonly property real centerWidth: boardWidth
    readonly property real handBandHeight: 126 * unit
    readonly property real opponentZoneTop: 6 * unit
    readonly property real handTop: root.height - handBandHeight
    readonly property real battlefieldTop: opponentZoneTop + zonePileHeight + 6 * unit
    readonly property real battlefieldBottom: handTop - 6 * unit
    readonly property real battlefieldMiddle: (battlefieldTop + battlefieldBottom) / 2
    readonly property real laneHeight: (battlefieldBottom - battlefieldTop - 12 * unit) / 2
    readonly property real landFaceWidth: 108 * unit
    readonly property real otherFaceWidth: 110 * unit
    readonly property real landRowNeed: 188 * unit
    readonly property real otherRowNeed: 120 * unit
    readonly property real opponentBackHeight: bandFor(opponentLands.stackCount, opponentOther.stackCount)
    readonly property real ownBackHeight: bandFor(ownLands.stackCount, ownOther.stackCount)
    readonly property string turnOwner: !session.active || session.turn < 1 || session.activeSeat < 0 ? qsTr("Preparing game")
        : session.activeSeat === tableController.localSeat ? qsTr("Your turn")
        : qsTr("%1's turn").arg(tableController.matchUi.playerName(session.activeSeat))
    readonly property var stackTarget: stackPanel.currentTarget
    readonly property string locatedId: stackTarget && stackTarget.kind === "card" ? stackTarget.objectId : ""
    readonly property int locatedSeat: stackTarget && stackTarget.kind === "player" ? stackTarget.seat : -1
    property string displayedGame: session.gameId
    objectName: "forgeDuelTable"
    color: "transparent"

    onCommanderFormatChanged: {
        if (zonePopup && !commanderFormat && zonePopup.zone === "command")
            zonePopup.zone = "graveyard"
    }

    function bandFor(landCount, otherCount) {
        return rowNeed(landCount, true) + rowNeed(otherCount, false)
    }
    function rowNeed(count, isLand) {
        if (count <= 0)
            return 0
        const face = isLand ? landFaceWidth : otherFaceWidth
        const gap = 8 * unit
        const extra = 10 * unit
        const tileHeight = face * 0.93 + extra
        const available = Math.max(face, boardWidth - 14 * unit)
        const columns = Math.max(1, Math.floor((available + gap) / (face + gap)))
        const need = Math.ceil(count / columns) * tileHeight + 5 * unit
        const floor = tileHeight + 5 * unit
        const cap = Math.min(laneHeight * (isLand ? 0.48 : 0.24), isLand ? landRowNeed : otherRowNeed)
        return Math.max(floor, Math.min(cap, need))
    }

    function pointFor(id) {
        const lanes = [ownCreatures, opponentCreatures, ownLands, opponentLands, ownOther, opponentOther]
        for (const lane of lanes) {
            const point = lane.pointFor(id, root)
            if (point.x !== 0) return point
        }
        return Qt.point(0, 0)
    }
    function playerPoint(seat) {
        for (let i = 0; i < plates.count; ++i) {
            const plate = plates.itemAt(i) as PlayerPlate
            if (plate && plate.seat === seat)
                return plate.mapToItem(root, plate.width / 2, plate.lifeCenterY)
        }
        return Qt.point(0, 0)
    }
    function reveal(id) {
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
            if (root.displayedGame !== root.session.gameId) {
                root.displayedGame = root.session.gameId
                gameMenu.close()
                zonePopup.close()
                stackPanel.clearSelection()
            }
        }
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
        }
    }
    ForgeHostingDialog {
        id: hostingOptions
        service: root.tableController.wsModel.forgeHost || null
        wsModel: root.tableController.wsModel
    }
    AppButton {
        id: settingsButton
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
        message: I18n.status(root.tableController.wsModel.lastError || "")
    }
    component PlayerPlate: Item {
        id: plate
        required property int seat
        required property string name
        required property int life
        required property string countersSummary
        required property string manaSummary
        readonly property bool isBottom: seat === root.bottomSeat
        readonly property bool activeTurn: root.session.activeSeat === seat && root.session.active && root.session.turn > 0
        readonly property bool actionable: root.tableController.combatInteraction.active
            ? root.tableController.combatInteraction.seatActionable(seat) : root.tableController.interaction.seatActionable(seat)
        readonly property bool selected: root.locatedSeat === seat || (root.tableController.combatInteraction.active
            ? root.tableController.combatInteraction.seatSelected(seat) : root.tableController.interaction.seatSelected(seat))
        readonly property real discSize: 52 * root.unit
        readonly property real lifeCenterY: lifeDisc.y + lifeDisc.height / 2
        objectName: "rulesPlayerTarget" + seat
        x: root.centerLeft + (root.centerWidth - width) / 2
        y: isBottom ? root.handTop - discSize * 0.58 : 4 * root.unit
        width: 168 * root.unit
        height: discSize + 30 * root.unit
        z: 25
        visible: !root.tableController.sideboarding
        activeFocusOnTab: actionable
        function activate() {
            if (!actionable) return
            if (root.tableController.combatInteraction.active) root.tableController.combatInteraction.activateSeat(seat)
            else root.tableController.interaction.activateSeat(seat)
        }
        Keys.onReturnPressed: activate()
        Keys.onSpacePressed: activate()
        Accessible.role: Accessible.Button
        Accessible.name: name + ", " + qsTr("Life %1").arg(life)
        Accessible.onPressAction: activate()
        Column {
            anchors.horizontalCenter: parent.horizontalCenter
            y: plate.isBottom ? plate.discSize + 2 * root.unit : 0
            width: parent.width
            spacing: 1 * root.unit
            Text {
                textFormat: Text.PlainText
                width: parent.width
                text: plate.name
                elide: Text.ElideRight
                horizontalAlignment: Text.AlignHCenter
                color: Theme.text
                style: Text.Outline
                styleColor: Theme.withAlpha("#000000", 0.7)
                font.pixelSize: 12 * root.unit
                font.weight: Font.DemiBold
            }
            Text {
                objectName: "forgePlayerZones-" + plate.seat
                textFormat: Text.PlainText
                width: parent.width
                text: [qsTr("Hand · %1").arg(root.tableController.zoneCount(plate.seat, "hand")),
                    qsTr("Library · %1").arg(root.tableController.zoneCount(plate.seat, "library")),
                    plate.manaSummary, plate.countersSummary].filter(v => v.length).join(" · ")
                elide: Text.ElideRight
                horizontalAlignment: Text.AlignHCenter
                color: Theme.textSecondary
                style: Text.Outline
                styleColor: Theme.withAlpha("#000000", 0.65)
                font.pixelSize: 10 * root.unit
            }
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
            border.width: plate.selected || plate.activeFocus || plate.actionable || plate.activeTurn ? 2 : 0
            border.color: plate.selected || plate.activeFocus ? Theme.accent
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
        AppButton {
            visible: root.tableController.canViewSpectatorHands
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
        model: root.session.players
        delegate: PlayerPlate {}
    }
    Repeater {
        model: root.session.players
        delegate: Column {
            id: commandersPanel
            required property int seat
            required property var commanders
            objectName: "forgeCommanders-" + seat
            x: Math.max(root.boardLeft, root.boardLeft + (root.boardWidth - 176 * root.unit) / 2 - width - 8 * root.unit)
            y: seat === root.bottomSeat ? root.handTop - 50 * root.unit : 6 * root.unit
            z: 26
            width: Math.min(220 * root.unit, (root.centerWidth - 176 * root.unit) / 2 - 10 * root.unit)
            spacing: 4 * root.unit
            visible: root.commanderFormat && !root.tableController.sideboarding
            Repeater {
                model: commandersPanel.commanders
                delegate: Item {
                    id: commanderEntry
                    required property var modelData
                    required property int index
                    readonly property string objectId: modelData.objectId || ""
                    readonly property bool actionable: objectId.length > 0 && root.tableController.interaction.objectActionable("card", objectId)
                    readonly property bool publicFace: !!modelData.name && modelData.zone !== "hidden"
                    readonly property string summary: qsTr("Casts %1 · Tax +%2 · %3").arg(modelData.casts).arg(modelData.tax)
                        .arg(modelData.zone === "hidden" ? qsTr("Hidden zone") : root.tableController.zoneLabel(modelData.zone))
                    objectName: "forgeCommander-" + commandersPanel.seat + "-" + index
                    width: commandersPanel.width
                    height: 44 * root.unit
                    activeFocusOnTab: objectId.length > 0
                    function activate() {
                        if (actionable) root.tableController.interaction.activateObject("card", objectId, modelData.name)
                        else if (objectId.length > 0) root.tableController.openCardDetails(objectId)
                    }
                    Keys.onReturnPressed: activate()
                    Keys.onSpacePressed: activate()
                    Accessible.role: Accessible.Button
                    Accessible.name: (typeof root.tableController.cardDisplayName === "function"
                                      ? root.tableController.cardDisplayName(modelData.name)
                                      : modelData.name) + ", " + summary
                    Accessible.onPressAction: activate()
                    Rectangle {
                        anchors.fill: parent
                        radius: 8 * root.unit
                        antialiasing: true
                        color: Theme.withAlpha(Theme.surface, commanderEntry.actionable || commanderEntry.activeFocus ? 0.78 : 0.48)
                        border.width: commanderEntry.actionable || commanderEntry.activeFocus ? 2 : 0
                        border.color: Theme.accent
                    }
                    Image {
                        x: 4 * root.unit
                        y: 4 * root.unit
                        width: 26 * root.unit
                        height: 36 * root.unit
                        source: commanderEntry.publicFace
                                ? root.tableController.cardImage(commanderEntry.modelData.name, "", "")
                                : root.tableController.cardBackSource
                        sourceSize.width: 80
                        sourceSize.height: 112
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                    }
                    Column {
                        x: 34 * root.unit
                        y: 5 * root.unit
                        width: parent.width - 40 * root.unit
                        spacing: 1 * root.unit
                        Text {
                            objectName: "forgeCommanderName-" + commandersPanel.seat + "-" + commanderEntry.index
                            textFormat: Text.PlainText
                            width: parent.width
                            text: typeof root.tableController.cardDisplayName === "function"
                                  ? root.tableController.cardDisplayName(commanderEntry.modelData.name)
                                  : commanderEntry.modelData.name
                            elide: Text.ElideRight
                            color: Theme.accent
                            font.pixelSize: 11 * root.unit
                            font.weight: Font.DemiBold
                        }
                        Text {
                            textFormat: Text.PlainText
                            width: parent.width
                            text: qsTr("+%1 · %2").arg(commanderEntry.modelData.tax)
                                  .arg(commanderEntry.modelData.zone === "hidden"
                                       ? qsTr("Hidden") : root.tableController.zoneLabel(commanderEntry.modelData.zone))
                            elide: Text.ElideRight
                            color: Theme.textSecondary
                            font.pixelSize: 10 * root.unit
                        }
                    }
                    TapHandler { onTapped: commanderEntry.activate() }
                    ToolTip.visible: commanderHover.hovered
                    ToolTip.text: (typeof root.tableController.cardDisplayName === "function"
                                   ? root.tableController.cardDisplayName(modelData.name)
                                   : modelData.name) + "\n" + summary + "\n" + qsTr("Tax is additional to the spell's cost; Forge calculates payment.")
                    HoverHandler { id: commanderHover }
                }
            }
        }
    }
    ForgeCardLane {
        id: opponentLands
        objectName: "forgeOpponentLands"
        x: root.boardLeft
        y: root.battlefieldTop
        width: Math.max(0, root.boardRight - root.boardLeft)
        height: root.rowNeed(stackCount, true)
        tableController: root.tableController
        unit: root.unit
        ownerSeat: root.topSeat
        category: "land"
        showCaption: false
        maxFaceWidth: root.landFaceWidth
        locatedId: root.locatedId
        visible: !root.tableController.sideboarding
    }
    ForgeCardLane {
        id: opponentOther
        objectName: "forgeOpponentOther"
        x: root.boardLeft
        y: opponentLands.y + opponentLands.height
        width: Math.max(0, root.boardRight - root.boardLeft)
        height: root.rowNeed(stackCount, false)
        tableController: root.tableController
        unit: root.unit
        ownerSeat: root.topSeat
        category: "other"
        showCaption: false
        maxFaceWidth: root.otherFaceWidth
        locatedId: root.locatedId
        visible: !root.tableController.sideboarding
    }
    ForgeCardLane {
        id: opponentCreatures
        objectName: "forgeOpponentCreatures"
        x: root.boardLeft
        y: root.battlefieldTop + root.opponentBackHeight
        width: root.boardWidth
        height: Math.max(0, root.laneHeight - root.opponentBackHeight)
        tableController: root.tableController
        unit: root.unit
        ownerSeat: root.topSeat
        showCaption: false
        locatedId: root.locatedId
        visible: !root.tableController.sideboarding
    }
    ForgeCardLane {
        id: ownCreatures
        objectName: "forgeOwnCreatures"
        x: root.boardLeft
        y: root.battlefieldMiddle + 6 * root.unit
        width: root.boardWidth
        height: Math.max(0, root.laneHeight - root.ownBackHeight)
        tableController: root.tableController
        unit: root.unit
        ownerSeat: root.bottomSeat
        showCaption: false
        locatedId: root.locatedId
        visible: !root.tableController.sideboarding
    }
    ForgeCardLane {
        id: ownOther
        objectName: "forgeOwnOther"
        x: root.boardLeft
        y: ownCreatures.y + ownCreatures.height
        width: Math.max(0, root.boardRight - root.boardLeft)
        height: root.rowNeed(stackCount, false)
        tableController: root.tableController
        unit: root.unit
        ownerSeat: root.bottomSeat
        category: "other"
        showCaption: false
        maxFaceWidth: root.otherFaceWidth
        locatedId: root.locatedId
        visible: !root.tableController.sideboarding
    }
    ForgeCardLane {
        id: ownLands
        objectName: "forgeOwnLands"
        x: root.boardLeft
        y: ownOther.y + ownOther.height
        width: Math.max(0, root.boardRight - root.boardLeft)
        height: root.rowNeed(stackCount, true)
        tableController: root.tableController
        unit: root.unit
        ownerSeat: root.bottomSeat
        category: "land"
        showCaption: false
        maxFaceWidth: root.landFaceWidth
        locatedId: root.locatedId
        visible: !root.tableController.sideboarding
    }
    DropArea {
        objectName: "forgeHandDropArea"
        x: root.boardLeft
        y: ownCreatures.y
        width: root.boardWidth
        height: Math.max(0, root.battlefieldBottom - ownCreatures.y)
        enabled: !root.tableController.sideboarding && root.tableController.localSeat >= 0
        keys: ["hexproof/rules-card"]
        onDropped: drop => {
            if (root.tableController.playDraggedHandCardSource(drop.source)) drop.acceptProposedAction()
            else drop.accepted = false
        }
    }
    Repeater {
        model: root.tableController.combatInteraction.links
        delegate: ForgeArrow {
            required property var modelData
            anchors.fill: parent
            unit: root.unit
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
    ForgeHand {
        objectName: "forgeHand"
        x: root.handLeft
        y: root.handTop
        z: 30
        width: Math.max(0, decisionDock.x - x - 20 * root.unit)
        height: root.handBandHeight - 4 * root.unit
        tableController: root.tableController
        unit: root.unit
        visible: !root.tableController.sideboarding
    }
    Item {
        id: opponentZoneStrip
        objectName: "forgeOpponentZoneStrip"
        x: root.boardLeft
        y: root.opponentZoneTop
        width: root.zoneRowWidth
        height: root.zonePileHeight
        visible: !root.tableController.sideboarding
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
                    ownerSeat: root.topSeat
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
        visible: !root.tableController.sideboarding
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
                    ownerSeat: root.bottomSeat
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
            height: 36 * root.unit
            Text {
                textFormat: Text.PlainText
                anchors.left: parent.left
                anchors.right: closeButton.left
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
            AppButton {
                id: closeButton
                objectName: "forgeCloseZonePopup"
                anchors.right: parent.right
                anchors.rightMargin: 10 * root.unit
                anchors.verticalCenter: parent.verticalCenter
                compact: true
                variant: "ghost"
                text: qsTr("Close")
                onClicked: zonePopup.close()
            }
        }
        Row {
            id: zoneTabs
            x: 14 * root.unit
            y: 40 * root.unit
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
        ForgeCardLane {
            objectName: "forgeZoneCards"
            anchors.fill: parent
            anchors.topMargin: 78 * root.unit
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
        width: Math.min(root.width * 0.42, Math.max(420 * root.unit, Theme.size(340)))
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
        visible: !root.tableController.sideboarding || root.tableController.hostingPaused === true
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
        x: decisionDock.x
        y: 80 * root.unit
        width: decisionDock.width
        height: Math.min(365 * root.unit, Math.max(0, root.handTop - y - 12 * root.unit))
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
                gameTableModel: root.tableController.gameTableModel
                tableModel: root.tableController.sideboardTableModel
                cardCatalogModel: root.tableController.cardCatalogModel
                trailingChromeWidth: settingsButton.width + 24 * root.unit
            }
        }
    }
}
