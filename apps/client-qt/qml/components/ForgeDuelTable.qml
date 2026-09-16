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
    readonly property bool suppressHoverDuringDecision: false
    readonly property bool cardChoiceActive: cardChoiceDialog.requested
    readonly property bool damageChoiceActive: damageDialog.requested
    readonly property bool decisionDialogActive: cardChoiceActive || damageChoiceActive
    readonly property bool modalOpen: gameMenu.opened || zonePopup.opened
        || cardChoiceDialog.visible || damageDialog.visible
    readonly property real unit: Math.min(width / 1600, height / 1000)
    readonly property int bottomSeat: tableController.handOwnerSeat >= 0 ? tableController.handOwnerSeat : 0
    readonly property int topSeat: bottomSeat === 0 ? 1 : 0
    readonly property var session: tableController.rulesSession
    readonly property bool commanderFormat: tableController.roomSession.format === "duel"
    readonly property var browsableZones: commanderFormat
        ? ["library", "graveyard", "exile", "command"] : ["library", "graveyard", "exile"]
    readonly property bool sidePanelOpen: !tableController.sideboarding
        && (tableController.showGameLogRail || inspectionDock.inspector.pinned)
    readonly property real sidePanelWidth: Math.min(width * 0.22, Math.max(284 * unit, Theme.size(240)))
    readonly property real centerLeft: 340 * unit
    readonly property real centerWidth: decisionDock.x - 20 * unit - centerLeft
    readonly property real handTop: root.height - 108 * unit
    readonly property real battlefieldTop: 82 * unit
    readonly property real battlefieldBottom: handTop - 82 * unit
    readonly property real battlefieldMiddle: (battlefieldTop + battlefieldBottom) / 2
    readonly property real laneHeight: (battlefieldBottom - battlefieldTop - 12 * unit) / 2
    readonly property real opponentSupportTop: 52 * unit
    readonly property real ownSupportTop: battlefieldMiddle + 12 * unit
    readonly property real opponentSupportHeight: battlefieldMiddle - opponentSupportTop - 12 * unit
    readonly property real ownSupportHeight: root.height - 92 * unit - ownSupportTop
    readonly property string turnOwner: !session.active || session.turn < 1 || session.activeSeat < 0 ? qsTr("Preparing game")
        : session.activeSeat === tableController.localSeat ? qsTr("Your turn")
        : qsTr("%1's turn").arg(tableController.matchUi.playerName(session.activeSeat))
    readonly property var stackTarget: stackPanel.currentTarget
    readonly property string locatedId: stackTarget && stackTarget.kind === "card" ? stackTarget.objectId : ""
    readonly property int locatedSeat: stackTarget && stackTarget.kind === "player" ? stackTarget.seat : -1
    property string displayedGame: session.gameId
    objectName: "forgeDuelTable"
    color: "#101e29"

    onCommanderFormatChanged: {
        if (zonePopup && !commanderFormat && zonePopup.zone === "command")
            zonePopup.zone = "graveyard"
    }

    function supportHeight(count, peerCount, available) {
        const rows = Math.max(1, Math.ceil(count / 3))
        const peerRows = Math.max(1, Math.ceil(peerCount / 3))
        const minimum = Math.min(96 * unit, available / 2)
        return Math.max(minimum, Math.min(available - minimum, available * rows / (rows + peerRows)))
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
            if (plate && plate.seat === seat) return plate.mapToItem(root, plate.width / 2, plate.height / 2)
        }
        return Qt.point(0, 0)
    }
    function reveal(id) {
        for (const lane of [ownCreatures, opponentCreatures, ownLands, opponentLands, ownOther, opponentOther]) {
            if (lane.reveal(id)) return true
        }
        return false
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
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0; color: "#15252e" }
            GradientStop { position: 0.48; color: "#192c35" }
            GradientStop { position: 1; color: "#101b26" }
        }
    }
    Rectangle { y: ownCreatures.y - 6 * root.unit; width: parent.width; height: 1; color: "#41515a"; opacity: 0.4 }
    Drawer {
        id: gameMenu
        objectName: "forgeGameDrawer"
        width: Math.min(300 * root.unit, root.width * 0.3)
        height: root.height
        edge: Qt.RightEdge
        RulesTableActionRail { anchors.fill: parent; tableController: root.tableController }
    }
    InfoBanner {
        objectName: "rulesErrorBanner"
        x: 20 * root.unit
        y: 3 * root.unit
        width: 300 * root.unit
        z: 40
        message: I18n.status(root.tableController.wsModel.lastError || "")
    }
    component PlayerPlate: Rectangle {
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
        objectName: "rulesPlayerTarget" + seat
        x: root.centerLeft + (root.centerWidth - width) / 2
        y: isBottom ? root.handTop - 74 * root.unit : 8 * root.unit
        width: 285 * root.unit
        height: 62 * root.unit
        radius: 11 * root.unit
        color: "#172832"
        border.width: selected ? 3 : actionable || activeTurn ? 2 : 1
        border.color: selected ? "#e5bd73" : actionable ? "#79b8c5" : activeTurn ? "#b39a6f" : "#3c5665"
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
            x: 13 * root.unit
            y: 10 * root.unit
            spacing: 7 * root.unit
            Text { textFormat: Text.PlainText; text: plate.name; width: 190 * root.unit; elide: Text.ElideRight; color: "#e0e6e5"; font.pixelSize: 14 * root.unit; font.weight: Font.DemiBold }
            Text {
                objectName: "forgePlayerZones-" + plate.seat
                textFormat: Text.PlainText
                width: 208 * root.unit
                text: [qsTr("Hand · %1").arg(root.tableController.zoneCount(plate.seat, "hand")),
                    qsTr("Library · %1").arg(root.tableController.zoneCount(plate.seat, "library")),
                    plate.manaSummary, plate.countersSummary].filter(v => v.length).join(" · ")
                elide: Text.ElideRight
                color: "#9eb4bf"
                font.pixelSize: 10 * root.unit
            }
        }
        Text { textFormat: Text.PlainText; text: plate.life; anchors.right: parent.right; anchors.rightMargin: 13 * root.unit; anchors.verticalCenter: parent.verticalCenter; color: "#e9d3a2"; font.pixelSize: 29 * root.unit }
        TapHandler { enabled: plate.actionable; onTapped: plate.activate() }
        AppButton {
            visible: root.tableController.canViewSpectatorHands
            anchors.left: parent.right
            anchors.leftMargin: 10 * root.unit
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
            x: root.centerLeft
            y: seat === root.bottomSeat ? root.handTop - 82 * root.unit : 8 * root.unit
            width: Math.min(292 * root.unit, (root.centerWidth - 285 * root.unit) / 2 - 10 * root.unit)
            spacing: 3 * root.unit
            visible: root.commanderFormat && !root.tableController.sideboarding
            Repeater {
                model: commandersPanel.commanders
                delegate: Rectangle {
                    id: commanderEntry
                    required property var modelData
                    required property int index
                    readonly property string objectId: modelData.objectId || ""
                    readonly property bool actionable: objectId.length > 0 && root.tableController.interaction.objectActionable("card", objectId)
                    readonly property string summary: qsTr("Casts %1 · Tax +%2 · %3").arg(modelData.casts).arg(modelData.tax)
                        .arg(modelData.zone === "hidden" ? qsTr("Hidden zone") : root.tableController.zoneLabel(modelData.zone))
                    objectName: "forgeCommander-" + commandersPanel.seat + "-" + index
                    width: commandersPanel.width
                    height: 30 * root.unit
                    color: "#1c303c"
                    radius: 5 * root.unit
                    border.color: actionable ? "#d7b273" : "#4c626e"
                    activeFocusOnTab: objectId.length > 0
                    function activate() {
                        if (actionable) root.tableController.interaction.activateObject("card", objectId, modelData.name)
                        else if (objectId.length > 0) root.tableController.openCardDetails(objectId)
                    }
                    Keys.onReturnPressed: activate()
                    Keys.onSpacePressed: activate()
                    Accessible.role: Accessible.Button
                    Accessible.name: modelData.name + ", " + summary
                    Accessible.onPressAction: activate()
                    Column {
                        x: 7 * root.unit; y: 3 * root.unit
                        width: parent.width - 14 * root.unit
                        Text { textFormat: Text.PlainText; text: commanderEntry.modelData.name; width: parent.width; elide: Text.ElideRight; color: "#e2d1ad"; font.pixelSize: 11 * root.unit }
                        Text { textFormat: Text.PlainText; text: commanderEntry.summary; width: parent.width; elide: Text.ElideRight; color: "#abc0ca"; font.pixelSize: 10 * root.unit }
                    }
                    TapHandler { onTapped: commanderEntry.activate() }
                    ToolTip.visible: commanderHover.hovered
                    ToolTip.text: modelData.name + "\n" + summary + "\n" + qsTr("Tax is additional to the spell's cost; Forge calculates payment.")
                    HoverHandler { id: commanderHover }
                }
            }
        }
    }
    ForgeCardLane {
        id: opponentCreatures
        objectName: "forgeOpponentCreatures"
        x: root.centerLeft
        y: ownCreatures.y - height - 12 * root.unit
        width: root.centerWidth
        height: root.laneHeight
        tableController: root.tableController
        unit: root.unit
        ownerSeat: root.topSeat
        caption: qsTr("Opponent's creatures")
        locatedId: root.locatedId
        visible: !root.tableController.sideboarding
    }
    ForgeCardLane {
        id: ownCreatures
        objectName: "forgeOwnCreatures"
        x: root.centerLeft
        y: root.battlefieldMiddle + 6 * root.unit
        width: root.centerWidth
        height: root.laneHeight
        tableController: root.tableController
        unit: root.unit
        ownerSeat: root.bottomSeat
        caption: root.tableController.localSeat < 0 ? qsTr("Creatures") : qsTr("Your creatures")
        locatedId: root.locatedId
        visible: !root.tableController.sideboarding
    }
    ForgeCardLane {
        id: opponentLands
        objectName: "forgeOpponentLands"
        x: 24 * root.unit; y: root.opponentSupportTop; width: 292 * root.unit
        height: root.supportHeight(visibleCards.length, opponentOther.visibleCards.length, root.opponentSupportHeight)
        tableController: root.tableController; unit: root.unit; ownerSeat: root.topSeat
        category: "land"; caption: qsTr("Opponent's lands"); locatedId: root.locatedId
        visible: !root.tableController.sideboarding
    }
    ForgeCardLane {
        id: ownLands
        objectName: "forgeOwnLands"
        x: 24 * root.unit; y: root.ownSupportTop; width: 292 * root.unit
        height: root.supportHeight(visibleCards.length, ownOther.visibleCards.length, root.ownSupportHeight)
        tableController: root.tableController; unit: root.unit; ownerSeat: root.bottomSeat
        category: "land"; caption: qsTr("Your lands"); locatedId: root.locatedId
        visible: !root.tableController.sideboarding
    }
    ForgeCardLane {
        id: opponentOther
        objectName: "forgeOpponentOther"
        x: 24 * root.unit; y: opponentLands.y + opponentLands.height + 12 * root.unit; width: 292 * root.unit
        height: root.opponentSupportHeight - opponentLands.height
        tableController: root.tableController; unit: root.unit; ownerSeat: root.topSeat
        category: "other"; caption: qsTr("Other permanents"); locatedId: root.locatedId
        visible: !root.tableController.sideboarding
    }
    ForgeCardLane {
        id: ownOther
        objectName: "forgeOwnOther"
        x: 24 * root.unit; y: ownLands.y + ownLands.height + 12 * root.unit; width: 292 * root.unit
        height: root.ownSupportHeight - ownLands.height
        tableController: root.tableController; unit: root.unit; ownerSeat: root.bottomSeat
        category: "other"; caption: qsTr("Other permanents"); locatedId: root.locatedId
        visible: !root.tableController.sideboarding
    }
    DropArea {
        objectName: "forgeHandDropArea"
        x: ownCreatures.x; y: ownCreatures.y; width: ownCreatures.width; height: ownCreatures.height
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
        x: 327 * root.unit
        y: root.handTop
        width: decisionDock.x - x - 20 * root.unit
        height: 104 * root.unit
        tableController: root.tableController
        unit: root.unit
        visible: !root.tableController.sideboarding
    }
    Row {
        x: 24 * root.unit
        y: root.height - 68 * root.unit
        spacing: 5 * root.unit
        visible: !root.tableController.sideboarding
        Repeater {
            model: root.browsableZones
            delegate: AppButton {
                id: zoneButton
                required property string modelData
                objectName: "forgeZone-" + modelData
                width: (292 - 5 * (root.browsableZones.length - 1)) * root.unit / root.browsableZones.length
                height: 56 * root.unit
                leftPadding: 4 * root.unit
                rightPadding: 4 * root.unit
                text: root.tableController.zoneLabel(modelData) + "\n" + root.tableController.zoneCount(root.bottomSeat, modelData)
                contentItem: Text {
                    textFormat: Text.PlainText; text: zoneButton.text; color: "#d0dfe5"; font.pixelSize: 11 * root.unit
                    wrapMode: Text.Wrap; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                }
                onClicked: { zonePopup.zone = modelData; zonePopup.ownerSeat = root.bottomSeat; zonePopup.open() }
            }
        }
    }
    AppButton {
        objectName: "forgeOpponentZones"
        x: 24 * root.unit; y: 8 * root.unit
        height: 36 * root.unit
        font.pixelSize: 11 * root.unit
        compact: true; text: qsTr("Opponent's zones")
        visible: !root.tableController.sideboarding
        onClicked: { zonePopup.ownerSeat = root.topSeat; zonePopup.zone = "graveyard"; zonePopup.open() }
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
        background: Rectangle { color: "#152631"; border.color: "#81989f"; radius: 12 * root.unit }
        Row {
            spacing: 5 * root.unit
            Repeater {
                model: root.browsableZones
                delegate: AppButton {
                    required property string modelData
                    objectName: "forgeZoneTab-" + modelData
                    compact: true
                    variant: zonePopup.zone === modelData ? "highlight" : "secondary"
                    text: root.tableController.zoneLabel(modelData)
                    onClicked: zonePopup.zone = modelData
                }
            }
            AppButton { objectName: "forgeCloseZonePopup"; compact: true; text: qsTr("Close"); onClicked: zonePopup.close() }
        }
        ForgeCardLane {
            objectName: "forgeZoneCards"
            anchors.fill: parent
            anchors.topMargin: 48 * root.unit
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
        x: root.width - width - 24 * root.unit - (root.sidePanelOpen ? root.sidePanelWidth + 16 * root.unit : 0)
        y: root.height - height - 16 * root.unit
        width: Math.min(root.width * 0.38, Math.max(330 * root.unit, Theme.size(280)))
        height: Math.min(implicitHeight, root.height - 32 * root.unit)
        tableController: root.tableController
        // Dialog ownership is permanent. Losing authority closes the dialog;
        // it must never transfer the stale private prompt back to the dock.
        externalCardChoices: true
        externalDamageChoices: true
        showZoneActions: true
        showActions: !root.tableController.sideboarding
        radius: 12 * root.unit
        color: "#f114222c"
        contextControls: Component {
            ColumnLayout {
                id: tableControls
                objectName: "forgeTableControls"
                spacing: Theme.size(5)

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.size(8)
                    visible: !root.tableController.sideboarding
                    Text {
                        objectName: "forgeTurnIndicator"
                        textFormat: Text.PlainText
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        text: root.session.gameOver ? qsTr("Game finished") : root.turnOwner
                        color: root.session.activeSeat === root.tableController.localSeat ? "#e9c785" : "#c6dbe4"
                        font.pixelSize: Theme.fontSize(12)
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }
                    Text {
                        objectName: "forgeTurnPhase"
                        textFormat: Text.PlainText
                        Layout.maximumWidth: tableControls.width * 0.6
                        text: qsTr("Turn %1 · %2").arg(root.session.turn).arg(root.tableController.stepLabel(root.session.step))
                        color: "#c6bba5"
                        font.pixelSize: Theme.fontSize(10)
                        elide: Text.ElideRight
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.size(5)
                    AppButton {
                        objectName: "forgeGameMenu"
                        compact: true
                        variant: "ghost"
                        implicitHeight: Theme.size(30)
                        font.pixelSize: Theme.fontSize(11)
                        text: qsTr("Settings")
                        onClicked: gameMenu.open()
                    }
                    AppButton {
                        objectName: "rulesToggleGameLogButton"
                        compact: true
                        variant: root.tableController.showGameLogRail ? "highlight" : "ghost"
                        implicitHeight: Theme.size(30)
                        font.pixelSize: Theme.fontSize(11)
                        enabled: !root.tableController.sideboarding
                        text: root.tableController.showGameLogRail ? qsTr("Hide log / chat") : qsTr("Show log / chat")
                        onClicked: root.tableController.setGameLogVisible(!root.tableController.showGameLogRail)
                    }
                    Item { Layout.fillWidth: true }
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
        height: Math.min(365 * root.unit, Math.max(0, decisionDock.y - y - 12 * root.unit))
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
        x: root.width - width - 24 * root.unit
        y: 12 * root.unit
        width: root.sidePanelWidth
        height: root.height - y - 16 * root.unit
        tableController: root.tableController
        visible: ((inspector.pinned && !inspector.previewCardId.length) || root.tableController.showGameLogRail)
            && !root.tableController.sideboarding
        radius: 10 * root.unit
        z: 100
    }
    RulesCardHoverPreview {
        tableController: root.tableController
        inspector: inspectionDock.inspector
    }
    Loader {
        objectName: "rulesSideboardLoader"
        x: 24 * root.unit; y: 12 * root.unit
        width: root.width - 48 * root.unit
        height: Math.max(0, decisionDock.y - y - 12 * root.unit)
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
            }
        }
    }
}
