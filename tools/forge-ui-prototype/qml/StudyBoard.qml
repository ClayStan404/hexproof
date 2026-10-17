// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors
import QtQuick
import QtQuick.Layouts
import "FixtureData.js" as Fixtures

Rectangle {
    id: root
    required property var controller
    property string assetRoot: ""
    readonly property real unit: Math.min(width / 1600, height / 1000)
    property var pinnedCard: null
    property var hoveredCard: null
    property bool logOpen: false
    property string locatedCard: ""
    readonly property var inspection: pinnedCard || hoveredCard
    readonly property real laneWidth: width - 690 * unit
    readonly property Item activeDock: controller.combatActive ? combatOverlay
        : controller.duelActive ? commanderOverlay : actionDock
    readonly property Item ownLane: ownRow
    readonly property Item opponentLane: opponentRow
    readonly property Item handView: hand
    readonly property Item stackView: stackPanel
    color: "#0f1923"
    objectName: "studyBoard"

    function inspect(card) { pinnedCard = card }
    function hover(card) { hoveredCard = card }
    function endHover() { hoveredCard = null }
    function selectCreature(card) { controller.chooseTarget(card.id, card.name) }
    function primaryAction() {
        if (controller.combatActive) combatOverlay.primaryAction()
        else if (controller.duelActive) commanderOverlay.primaryAction()
        else if (controller.stage === "payment") controller.pay()
        else if (controller.stack.length) controller.resolve()
    }
    function revealTarget(id) {
        if (ownRow.reveal(id) || opponentRow.reveal(id)) {
            locatedCard = id
            pinnedCard = null
            hoveredCard = null
        }
    }
    function chooseScene(scene) {
        pinnedCard = null
        hoveredCard = null
        logOpen = false
        locatedCard = ""
        controller.reset(scene)
    }
    function centerOf(item) {
        return item ? item.mapToItem(root, item.width / 2, item.height / 2) : Qt.point(0, 0)
    }
    function pointFor(id) {
        if (id === "you") return centerOf(ownPlate)
        if (id === "opponent") return centerOf(opponentPlate)
        if (ownRow.isCardVisible(id)) return centerOf(ownRow.itemFor(id))
        if (opponentRow.isCardVisible(id)) return centerOf(opponentRow.itemFor(id))
        return Qt.point(0, 0)
    }
    function geometryReport() {
        const controls = { ballista: centerOf(opponentRow.itemFor("ballista")),
            mountain: centerOf(ownLands.itemFor("mountain")),
            foundry: centerOf(ownLands.itemFor("foundry")),
            opponent: centerOf(opponentPlate), bolt: centerOf(hand.itemFor("bolt")),
            primary: centerOf(activeDock.primaryButton), cancel: centerOf(activeDock.cancelButton) }
        return { scene: controller.scene, stage: controller.stage, width: width, height: height, controls: controls,
            target: controller.selectedTargetId, reservedMana: controller.selectedManaId,
            paidMana: controller.paidManaId, handCount: controller.hand.length,
            stack: controller.visibleStack.map(entry => entry.id),
            combatMode: controller.combat.mode, combatCommitted: controller.combat.committed,
            attackers: controller.combat.attackers, blocks: controller.combat.blocks,
            damage: controller.combat.damage, commanderState: controller.duel.state,
            commanderLocation: controller.duel.location, commanderCastCount: controller.duel.castCount,
            commanderReserved: controller.duel.reserved, commanderPaid: controller.duel.paid,
            locatedCard: locatedCard, ownScroll: ownRow.scrollOffset,
            opponentScroll: opponentRow.scrollOffset, stackScroll: stackPanel.scrollArea.contentY,
            handScroll: hand.scrollArea.contentX }
    }
    Connections {
        target: root.controller
        function onStageChanged() {
            root.pinnedCard = null
            root.hoveredCard = null
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
    Canvas {
        anchors.fill: parent
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        onPaint: {
            const ctx = getContext("2d")
            ctx.reset()
            ctx.strokeStyle = "#2c4149"
            ctx.lineWidth = 1
            for (let i = 0; i < 3; i++) {
                ctx.beginPath()
                ctx.ellipse(width * 0.15 - i * 25, height * 0.19 - i * 30,
                            width * 0.68 + i * 50, height * 0.59 + i * 60)
                ctx.stroke()
            }
        }
    }
    Rectangle {
        x: 0
        y: root.controller.crowded ? 467 * root.unit : root.height * 0.50
        width: parent.width
        height: 1
        color: "#41515a"
        opacity: 0.45
    }
    Rectangle {
        x: 0
        y: root.height - 249 * root.unit
        width: root.width
        height: root.height - y
        gradient: Gradient {
            GradientStop { position: 0; color: "#00101b26" }
            GradientStop { position: 0.55; color: "#c9101b26" }
            GradientStop { position: 1; color: "#ff0b131d" }
        }
    }

    // The study toolbar stays separate from the proposed in-game composition.
    Rectangle {
        width: parent.width
        height: 55 * root.unit
        color: "#e40c141d"
        Row {
            x: 26 * root.unit
            anchors.verticalCenter: parent.verticalCenter
            spacing: 13 * root.unit
            StudyLabel { text: "⬡"; pointSize: 29; color: "#d6b982"; unit: root.unit }
            StudyLabel { text: "HEXPROOF"; pointSize: 14; font.letterSpacing: 3; color: "#ebebdf"; unit: root.unit; anchors.verticalCenter: parent.verticalCenter }
            StudyLabel { text: root.controller.duelActive ? "FORGE  /  DUEL COMMANDER" : "FORGE  /  MODERN"; pointSize: 10; font.letterSpacing: 1; unit: root.unit; anchors.verticalCenter: parent.verticalCenter }
        }
        Row {
            anchors.right: parent.right
            anchors.rightMargin: 20 * root.unit
            anchors.verticalCenter: parent.verticalCenter
            spacing: 5 * root.unit
            StudyLabel { text: "UI STUDY"; pointSize: 9; color: "#7f929f"; unit: root.unit; anchors.verticalCenter: parent.verticalCenter }
            Repeater {
                model: [{id:"board", name:"1  Table"}, {id:"response", name:"2  Stack"},
                        {id:"target", name:"3  Target"}, {id:"payment", name:"4  Mana"},
                        {id:"combat", name:"5  Combat"}, {id:"commander", name:"6  Duel"},
                        {id:"crowded", name:"7  Crowded"}]
                delegate: StudyButton {
                    required property var modelData
                    objectName: "studyScene-" + modelData.id
                    text: modelData.name
                    unit: root.unit
                    implicitHeight: 32 * root.unit
                    quiet: true
                    checked: root.controller.scene === modelData.id
                    onClicked: root.chooseScene(modelData.id)
                }
            }
        }
    }

    Item {
        x: root.width / 2 - 148 * root.unit
        y: 65 * root.unit
        width: 296 * root.unit
        height: 57 * root.unit
        opacity: root.controller.choosing || root.controller.combatActive || root.controller.duelActive ? 0.12 : 0.8
        Repeater {
            model: 5
            delegate: Rectangle {
                required property int index
                x: index * 46 * root.unit
                y: Math.abs(index - 2) * 3 * root.unit
                width: 72 * root.unit
                height: 55 * root.unit
                rotation: (index - 2) * 5
                radius: 7 * root.unit
                color: "#203540"
                border.color: "#527181"
                StudyLabel { anchors.centerIn: parent; text: "⬡"; color: "#ba9b68"; pointSize: 27; unit: root.unit }
            }
        }
    }
    PlayerPlate {
        id: opponentPlate
        objectName: "studyOpponent"
        x: (root.width - width) / 2
        y: 153 * root.unit
        unit: root.unit
        playerName: "Opponent"
        subtitle: root.controller.duelActive ? "Thalia  ·  5 cards" : "Hardened Scales  ·  5 cards"
        life: root.controller.opponentLife
        actionable: root.controller.stage === "target"
        selected: root.controller.selectedTargetId === "opponent"
        onActivated: root.controller.chooseTarget("opponent", "Opponent")
    }
    BattlefieldLane {
        id: opponentRow
        objectName: "studyOpponentLane"
        x: (root.width - width) / 2
        y: root.controller.crowded ? 218 * root.unit : root.height * 0.325
        width: root.laneWidth
        dense: root.controller.crowded
        caption: "OPPONENT'S CREATURES"
        cards: root.controller.opponentCreatures
        assetRoot: root.assetRoot
        unit: root.unit
        actionableIds: root.controller.combatActive
            ? (root.controller.combat.mode === "block" && root.controller.combat.selectedBlocker && !root.controller.combat.committed
                ? root.controller.combat.incomingAttackers : [])
            : root.controller.stage === "target" ? root.controller.targetIds : []
        selectedIds: root.controller.combatActive && root.controller.combat.mode === "damage"
            ? ["ballista", "walker"] : [root.controller.selectedTargetId, root.locatedCard]
        tappedIds: root.controller.combatActive && root.controller.combat.mode === "block"
            ? root.controller.combat.incomingAttackers : []
        statusLabels: root.controller.combatActive ? root.controller.combat.labels(false) : ({})
        actionHint: root.controller.combatActive ? "BLOCK THIS" : "TARGET"
        onActivated: card => {
            if (root.controller.combatActive) root.controller.combat.selectAttacker(card.id)
            else root.selectCreature(card)
        }
        onInspected: card => root.inspect(card)
        onPreviewed: card => root.hover(card)
        onPreviewEnded: root.endHover()
    }
    BattlefieldLane {
        id: ownRow
        objectName: "studyOwnLane"
        x: (root.width - width) / 2
        y: root.controller.crowded ? 470 * root.unit : root.height * 0.54
        width: root.laneWidth
        dense: root.controller.crowded
        caption: "YOUR CREATURES"
        cards: root.controller.visibleOwnCreatures
        assetRoot: root.assetRoot
        unit: root.unit
        actionableIds: root.controller.combatActive
            ? (!root.controller.combat.committed && root.controller.combat.mode !== "damage" ? root.controller.combat.attackCandidates : [])
            : root.controller.stage === "target" ? root.controller.targetIds : []
        selectedIds: root.controller.combatActive
            ? (root.controller.combat.mode === "attack" ? root.controller.combat.attackers
                : root.controller.combat.mode === "block" ? [root.controller.combat.selectedBlocker] : ["own-ravager"])
            : [root.controller.selectedTargetId, root.locatedCard]
        tappedIds: root.controller.combatActive && root.controller.combat.mode === "attack" && root.controller.combat.committed
            ? root.controller.combat.attackers : []
        statusLabels: root.controller.combatActive ? root.controller.combat.labels(true) : ({})
        actionHint: root.controller.combatActive ? (root.controller.combat.mode === "attack" ? "ATTACK" : "BLOCKER") : "TARGET"
        onActivated: card => {
            if (root.controller.combatActive) root.controller.combat.selectOwn(card.id)
            else root.selectCreature(card)
        }
        onInspected: card => root.inspect(card)
        onPreviewed: card => root.hover(card)
        onPreviewEnded: root.endHover()
    }
    StudyLabel {
        x: 29 * root.unit
        y: (root.controller.duelActive ? 339 * root.unit : root.height * 0.255) - 29 * root.unit
        text: "OPPONENT'S LANDS"
        pointSize: 9
        font.letterSpacing: 1.4
        color: "#8296a1"
        unit: root.unit
    }
    BoardRow {
        x: 29 * root.unit
        y: root.controller.duelActive ? 339 * root.unit : root.height * 0.255
        width: 285 * root.unit
        lands: true
        cards: root.controller.opponentLands
        assetRoot: root.assetRoot
        unit: root.unit
        tappedIds: ["forest-a", "citadel"]
        onInspected: card => root.inspect(card)
        onPreviewed: card => root.hover(card)
        onPreviewEnded: root.endHover()
    }
    StudyLabel {
        x: 29 * root.unit
        y: (root.controller.duelActive ? 650 * root.unit : root.height * 0.625) - 29 * root.unit
        text: root.controller.duelActive ? (root.controller.duel.state === "payment" ? "CHOOSE THREE MANA SOURCES"
                : "YOUR LANDS  /  " + (3 - root.controller.duel.paid.length) + " UNTAPPED")
            : root.controller.stage === "payment" ? "CHOOSE A MANA SOURCE"
                : "YOUR LANDS  /  " + (root.controller.paidManaId ? "2" : "3") + " UNTAPPED"
        pointSize: 9
        font.letterSpacing: 1.4
        color: root.controller.stage === "payment" ? "#dbbd87" : "#8296a1"
        unit: root.unit
    }
    BoardRow {
        id: ownLands
        x: 29 * root.unit
        y: root.controller.duelActive ? 650 * root.unit : root.height * 0.625
        width: 285 * root.unit
        lands: true
        cards: root.controller.ownLands
        assetRoot: root.assetRoot
        unit: root.unit
        actionableIds: root.controller.duelActive ? (root.controller.duel.state === "payment" ? root.controller.duel.sources : [])
            : root.controller.stage === "payment" ? root.controller.redSources.filter(id => id !== root.controller.paidManaId) : []
        selectedId: root.controller.selectedManaId
        selectedIds: root.controller.duelActive ? root.controller.duel.reserved : []
        tappedIds: root.controller.duelActive ? root.controller.duel.paid : root.controller.paidManaId ? [root.controller.paidManaId] : []
        actionHint: root.controller.duelActive ? "ADD W" : "PAY R"
        onActivated: card => {
            if (root.controller.duelActive) root.controller.duel.reserve(card.id)
            else root.controller.chooseMana(card.id)
        }
        onInspected: card => root.inspect(card)
        onPreviewed: card => root.hover(card)
        onPreviewEnded: root.endHover()
    }
    StudyCard {
        visible: !root.controller.duelActive
        x: root.width - width - 32 * root.unit
        y: 162 * root.unit
        width: 141 * root.unit
        height: 107 * root.unit
        unit: root.unit
        assetRoot: root.assetRoot
        card: Fixtures.card("scales", "scales", "Hardened Scales", "Enchantment", "G")
        onInspected: card => root.inspect(card)
        onPreviewed: card => root.hover(card)
        onPreviewEnded: root.endHover()
    }

    PlayerPlate {
        id: ownPlate
        objectName: "studyYou"
        x: (root.width - width) / 2
        y: root.height - 277 * root.unit
        unit: root.unit
        life: root.controller.ownLife
        subtitle: root.controller.duelActive ? "Isamaru" : "Boros Energy"
        priority: true
        actionable: root.controller.stage === "target"
        selected: root.controller.selectedTargetId === "you"
        onActivated: root.controller.chooseTarget("you", "You")
    }
    Row {
        x: ownPlate.x + ownPlate.width + 14 * root.unit
        y: ownPlate.y + 8 * root.unit
        spacing: 5 * root.unit
        Repeater {
            model: ["Upkeep", "Draw", "Main", "Combat", "End"]
            delegate: StudyButton {
                required property var modelData
                required property int index
                text: modelData + (root.controller.phaseStops[index] ? " •" : "")
                unit: root.unit
                implicitHeight: 29 * root.unit
                checked: root.controller.phaseStops[index]
                quiet: true
                onClicked: root.controller.toggleStop(index)
            }
        }
    }
    StudyLabel {
        x: ownPlate.x - 140 * root.unit
        y: ownPlate.y + 20 * root.unit
        text: root.controller.combatActive ? "TURN 4  /  COMBAT" : "TURN 4  /  MAIN 1"
        pointSize: 10
        color: "#c4b08c"
        font.letterSpacing: 1
        unit: root.unit
    }
    StudyHand {
        id: hand
        x: 313 * root.unit
        y: root.height - 208 * root.unit
        width: root.width - 655 * root.unit
        height: 190 * root.unit
        cards: root.controller.hand
        unit: root.unit
        assetRoot: root.assetRoot
        canCast: !root.controller.choosing && !root.controller.combatActive && !root.controller.duelActive
        onCastRequested: root.controller.castBolt()
        onInspected: card => root.inspect(card)
        onPreviewed: card => root.hover(card)
        onPreviewEnded: root.endHover()
    }
    Row {
        x: 28 * root.unit
        y: root.height - 167 * root.unit
        spacing: 17 * root.unit
        Repeater {
            model: [{name:"LIBRARY", count:"46"}, {name:"GRAVEYARD", count:"4"}, {name:"EXILE", count:"0"}]
            delegate: Column {
                required property var modelData
                spacing: 8 * root.unit
                Rectangle {
                    width: 69 * root.unit
                    height: 95 * root.unit
                    radius: 7 * root.unit
                    color: "#1c2d39"
                    border.color: "#435a69"
                    StudyLabel { anchors.centerIn: parent; text: modelData.count; pointSize: 27; unit: root.unit; color: "#abbdc8" }
                }
                StudyLabel { text: modelData.name; pointSize: 8; unit: root.unit; font.letterSpacing: 1 }
            }
        }
    }
    ActionDock {
        id: actionDock
        visible: !root.controller.combatActive && !root.controller.duelActive
        x: root.width - width - 24 * root.unit
        y: root.height - height - 26 * root.unit
        controller: root.controller
        unit: root.unit
    }
    StackPanel {
        id: stackPanel
        x: root.width - width - 26 * root.unit
        y: root.height * 0.32
        entries: root.controller.visibleStack
        assetRoot: root.assetRoot
        unit: root.unit
        onInspected: card => root.inspect(card)
        onTargetRequested: id => root.revealTarget(id)
    }
    StudyArrow {
        objectName: "studyStackArrow"
        anchors.fill: parent
        unit: root.unit
        visible: !!root.controller.activeStack && stackPanel.scrollArea.contentY === 0
        startPoint: Qt.point(stackPanel.x, stackPanel.y + 109 * root.unit)
        endPoint: {
            void root.width; void root.height; void root.controller.opponentCreatures; void root.controller.visibleOwnCreatures
            void ownRow.scrollOffset; void opponentRow.scrollOffset
            return root.controller.activeStack ? root.pointFor(root.controller.activeStack.targetId) : Qt.point(0, 0)
        }
    }

    Rectangle {
        id: instruction
        visible: root.controller.choosing
        x: (root.width - width) / 2
        y: 74 * root.unit
        width: 635 * root.unit
        height: 66 * root.unit
        radius: 10 * root.unit
        color: "#f1192934"
        border.color: "#a28d68"
        Image {
            x: 8 * root.unit
            y: 8 * root.unit
            width: 72 * root.unit
            height: 50 * root.unit
            source: root.assetRoot ? root.assetRoot + "bolt-art.jpg" : ""
            fillMode: Image.PreserveAspectCrop
        }
        Column {
            x: 94 * root.unit
            anchors.verticalCenter: parent.verticalCenter
            spacing: 5 * root.unit
            StudyLabel {
                text: root.controller.stage === "target" ? "Lightning Bolt — choose any target" : "Lightning Bolt — pay R"
                pointSize: 16
                color: "#f0e0bb"
                unit: root.unit
                font.weight: Font.DemiBold
            }
            StudyLabel {
                text: root.controller.stage === "target" ? "Deal 3 damage. Select a creature or player on the battlefield."
                    : "Target locked: " + root.controller.selectedTargetName + ". Choose a highlighted land."
                pointSize: 11
                color: "#b0c2cd"
                unit: root.unit
            }
        }
    }
    StudyArrow {
        anchors.fill: parent
        unit: root.unit
        visible: root.controller.stage === "payment"
        startPoint: Qt.point(instruction.x + 44 * root.unit, instruction.y + instruction.height)
        endPoint: {
            void root.width; void root.height
            return root.pointFor(root.controller.selectedTargetId)
        }
    }

    CombatOverlay {
        id: combatOverlay
        anchors.fill: parent
        visible: root.controller.combatActive
        model: root.controller.combat
        board: root
        assetRoot: root.assetRoot
        unit: root.unit
    }
    CommanderOverlay {
        id: commanderOverlay
        anchors.fill: parent
        visible: root.controller.duelActive
        model: root.controller.duel
        assetRoot: root.assetRoot
        unit: root.unit
        onInspected: card => root.inspect(card)
    }
    Rectangle {
        id: inspector
        visible: !!root.inspection && !root.controller.choosing
        x: 28 * root.unit
        y: 160 * root.unit
        width: 276 * root.unit
        height: 404 * root.unit
        radius: 11 * root.unit
        color: "#f40d1722"
        border.color: "#6c7f8a"
        z: 50
        Image {
            x: 8 * root.unit
            y: 8 * root.unit
            width: parent.width - 16 * root.unit
            height: 362 * root.unit
            source: root.inspection && root.assetRoot ? root.assetRoot + root.inspection.key + "-full.jpg" : ""
            fillMode: Image.PreserveAspectFit
            asynchronous: true
        }
        StudyLabel {
            x: 12 * root.unit
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 10 * root.unit
            text: root.pinnedCard ? "Pinned card" : "Right-click to pin"
            unit: root.unit
            pointSize: 10
        }
        StudyButton {
            visible: !!root.pinnedCard
            x: parent.width - width - 6 * root.unit
            y: parent.height - height - 3 * root.unit
            text: "Close"
            quiet: true
            unit: root.unit
            implicitWidth: 60 * root.unit
            implicitHeight: 30 * root.unit
            onClicked: { root.pinnedCard = null; root.hoveredCard = null }
        }
    }
    StudyButton {
        x: 25 * root.unit
        y: 70 * root.unit
        text: root.logOpen ? "Close log" : "Game log"
        unit: root.unit
        quiet: true
        implicitHeight: 31 * root.unit
        onClicked: root.logOpen = !root.logOpen
    }
    Rectangle {
        visible: root.logOpen
        x: 27 * root.unit
        y: 110 * root.unit
        width: 305 * root.unit
        height: 260 * root.unit
        radius: 10 * root.unit
        color: "#fb13222e"
        border.color: "#506775"
        z: 60
        Column {
            anchors.fill: parent
            anchors.margins: 16 * root.unit
            spacing: 15 * root.unit
            StudyLabel { text: "GAME LOG"; pointSize: 11; font.letterSpacing: 2; unit: root.unit; color: "#ddc795" }
            Repeater {
                model: root.controller.history.slice(-5)
                delegate: StudyLabel {
                    required property var modelData
                    width: parent.width
                    text: modelData
                    wrapMode: Text.WordWrap
                    pointSize: 12
                    unit: root.unit
                }
            }
        }
    }
    StudyLabel {
        x: 28 * root.unit
        y: root.height - 21 * root.unit
        text: "OFFLINE DESIGN PREVIEW  ·  F1–F7 scenes  ·  Esc cancel  ·  Space primary action"
        unit: root.unit
        pointSize: 8
        color: "#728893"
    }
    Rectangle {
        visible: root.controller.notice !== ""
        anchors.horizontalCenter: parent.horizontalCenter
        y: 228 * root.unit
        width: noticeLabel.implicitWidth + 30 * root.unit
        height: 33 * root.unit
        radius: 7 * root.unit
        color: "#f122353f"
        border.color: "#566963"
        StudyLabel { id: noticeLabel; anchors.centerIn: parent; text: root.controller.notice; pointSize: 11; unit: root.unit; color: "#dacbaa" }
    }
}
