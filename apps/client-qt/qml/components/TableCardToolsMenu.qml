// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic

Menu {
    id: root

    objectName: "cardToolsMenu"

    required property var tableController
    required property var cardCounterEditorPopup
    required property var libraryPositionEditorPopup

    function selectedBattlefieldIds() {
        return Object.keys(tableController.selectedBattlefieldCardIds)
    }

    function selectedSourcesControlledByLocal() {
        const ids = selectedBattlefieldIds()
        if (ids.length === 0)
            return false
        for (let index = 0; index < ids.length; ++index) {
            if (tableController.gameTableModel.visibleZoneSeat(
                        ids[index], "battlefield")
                    !== tableController.roomSession.seatIndex) {
                return false
            }
        }
        return true
    }

    function combatSeatData(seat) {
        const indexed = tableController.gameTableModel.seatData(seat)
        if (indexed && indexed.displayName)
            return indexed
        const seats = tableController.authoritativeSeats
                      ? tableController.authoritativeSeats : []
        for (let index = 0; index < seats.length; ++index) {
            if (Number(seats[index].seat) === seat)
                return seats[index]
        }
        return ({})
    }

    function eligibleCombatTarget(seat) {
        if (seat < 0 || seat === tableController.roomSession.seatIndex)
            return false
        const data = combatSeatData(seat)
        return !!data.displayName && data.eliminated !== true
    }

    function eligibleTargetSeat(seat) {
        if (seat < 0)
            return false
        const data = combatSeatData(seat)
        return !!data.displayName && data.eliminated !== true
    }

    function combatTargetLabel(seat) {
        const data = combatSeatData(seat)
        return data.displayName ? data.displayName : qsTr("Seat") + " " + (seat + 1)
    }

    function hasEligibleCombatTarget() {
        for (let seat = 0; seat < 4; ++seat) {
            if (eligibleCombatTarget(seat))
                return true
        }
        return false
    }

    function canDeclareAttacks() {
        return tableController.canAct
                && selectedSourcesControlledByLocal()
                && tableController.gameSession.activeSeat
                   === tableController.roomSession.seatIndex
                && tableController.gameSession.currentPhase
                   === "declare_attackers"
    }

    function declareAttacks(targetSeat) {
        tableController.rulesAssist.requestCombatDeclaration(
                    "attack", selectedBattlefieldIds(), "", targetSeat)
    }

    function attackPlayerText(seat) {
        return qsTr("Attack %1 · %2 selected")
            .arg(combatTargetLabel(seat))
            .arg(tableController.selection.selectedCount())
    }

    function hasIncomingAttacker() {
        const arrows = tableController.tableArrows
        for (let index = 0; index < arrows.length; ++index) {
            if (arrows[index].kind !== "attack")
                continue
            if (arrows[index].targetSeat
                    === tableController.roomSession.seatIndex) {
                return true
            }
            if (arrows[index].targetCardId
                    && tableController.gameTableModel.visibleZoneSeat(
                        arrows[index].targetCardId, "battlefield")
                       === tableController.roomSession.seatIndex) {
                return true
            }
        }
        return false
    }

    function selectedHasCombatDeclaration() {
        const ids = selectedBattlefieldIds()
        for (let index = 0; index < ids.length; ++index) {
            const arrow = tableController.gameTableModel.arrowForSource(ids[index])
            if (arrow.kind === "attack" || arrow.kind === "block")
                return true
        }
        return false
    }

    function selectedHasTarget() {
        const ids = selectedBattlefieldIds()
        for (let index = 0; index < ids.length; ++index) {
            const arrow = tableController.gameTableModel.arrowForSource(ids[index])
            if (arrow.kind === "target")
                return true
        }
        return false
    }

    function targetPlayer(seat) {
        tableController.wsModel.setCombatArrows(
                    selectedBattlefieldIds(), "target", "", seat)
        tableController.selection.clear()
    }

    ConditionalMenuItem {
        objectName: "chooseCardFaceAction"
        visible: root.tableController.selection.selectedCount() === 1
                 && root.tableController.selectedBattlefieldFaces.length > 1
        text: qsTr("Choose card face…") + " · V"
        enabled: root.tableController.cardMoveCommands.canControlSelectedBattlefield()
        onTriggered:
            root.tableController.cardMoveCommands.requestBattlefieldFaceSelection()
    }
    ConditionalMenuItem {
        objectName: "toggleCardFaceDownAction"
        visible: root.tableController.selection.selectedCount() === 1
        text: (root.tableController.selectedBattlefieldCard.faceDown === true
               ? qsTr("Turn face up")
               : qsTr("Turn face down")) + " · F"
        enabled: root.tableController.cardMoveCommands.canControlSelectedBattlefield()
        onTriggered: {
            root.tableController.wsModel.setCardFaceDown(
                        root.tableController.selectedBattlefieldCard.id,
                        root.tableController.selectedBattlefieldCard.faceDown !== true)
            root.tableController.selection.clear()
        }
    }
    ConditionalMenuSeparator {
        visible: root.tableController.selection.selectedCount() === 1
    }
    ConditionalMenuItem {
        objectName: "attachToAction"
        text: qsTr("Attach to…") + " · A"
        visible: root.tableController.selection.selectedCount() === 1
        enabled: root.tableController.attachmentUi
                 && root.tableController.attachmentUi.canAttachSelected()
        onTriggered: root.tableController.attachmentUi.beginAttach()
    }
    ConditionalMenuItem {
        objectName: "detachAttachmentAction"
        text: qsTr("Detach") + " · Shift+A"
        visible: root.tableController.selection.selectedCount() === 1
        enabled: root.tableController.attachmentUi
                 && root.tableController.attachmentUi.canDetachSelected()
        onTriggered: root.tableController.attachmentUi.detachSelected()
    }
    ConditionalMenuSeparator {
        visible: root.tableController.selection.selectedCount() === 1
    }
    Menu {
        objectName: "chooseTargetMenu"
        title: qsTr("Choose target")
        enabled: root.tableController.canAct
                 && root.selectedSourcesControlledByLocal()

        ConditionalMenuItem {
            objectName: "targetSeat0Action"
            visible: root.eligibleTargetSeat(0)
            text: qsTr("Target %1").arg(root.combatTargetLabel(0))
            onTriggered: root.targetPlayer(0)
        }
        ConditionalMenuItem {
            objectName: "targetSeat1Action"
            visible: root.eligibleTargetSeat(1)
            text: qsTr("Target %1").arg(root.combatTargetLabel(1))
            onTriggered: root.targetPlayer(1)
        }
        ConditionalMenuItem {
            objectName: "targetSeat2Action"
            visible: root.eligibleTargetSeat(2)
            text: qsTr("Target %1").arg(root.combatTargetLabel(2))
            onTriggered: root.targetPlayer(2)
        }
        ConditionalMenuItem {
            objectName: "targetSeat3Action"
            visible: root.eligibleTargetSeat(3)
            text: qsTr("Target %1").arg(root.combatTargetLabel(3))
            onTriggered: root.targetPlayer(3)
        }
        MenuSeparator { }
        MenuItem {
            objectName: "targetBattlefieldCardAction"
            text: qsTr("Target a battlefield card…") + " · R"
            onTriggered:
                root.tableController.selection.beginRelationTarget("arrow")
        }
    }
    MenuItem {
        objectName: "clearTargetAction"
        text: qsTr("Clear target") + " · Shift+R"
        enabled: root.tableController.canAct
                 && root.selectedSourcesControlledByLocal()
                 && root.selectedHasTarget()
        onTriggered: {
            root.tableController.wsModel.clearCombatArrows(
                        root.selectedBattlefieldIds())
            root.tableController.selection.clear()
        }
    }
    MenuSeparator { }
    ConditionalMenuItem {
        objectName: "declareAttackAgainstSeat0Action"
        visible: root.eligibleCombatTarget(0)
        text: root.attackPlayerText(0)
        enabled: root.canDeclareAttacks()
        onTriggered: root.declareAttacks(0)
    }
    ConditionalMenuItem {
        objectName: "declareAttackAgainstSeat1Action"
        visible: root.eligibleCombatTarget(1)
        text: root.attackPlayerText(1)
        enabled: root.canDeclareAttacks()
        onTriggered: root.declareAttacks(1)
    }
    ConditionalMenuItem {
        objectName: "declareAttackAgainstSeat2Action"
        visible: root.eligibleCombatTarget(2)
        text: root.attackPlayerText(2)
        enabled: root.canDeclareAttacks()
        onTriggered: root.declareAttacks(2)
    }
    ConditionalMenuItem {
        objectName: "declareAttackAgainstSeat3Action"
        visible: root.eligibleCombatTarget(3)
        text: root.attackPlayerText(3)
        enabled: root.canDeclareAttacks()
        onTriggered: root.declareAttacks(3)
    }
    ConditionalMenuItem {
        objectName: "declareAttackAgainstPermanentAction"
        visible: root.hasEligibleCombatTarget()
        text: qsTr("Attack a battlefield permanent…") + " · X"
        enabled: root.canDeclareAttacks()
        onTriggered: root.tableController.selection.beginRelationTarget("attack")
    }
    MenuItem {
        objectName: "declareBlockAction"
        text: qsTr("Block an attacker…") + " · Shift+X"
        enabled: root.tableController.canAct
                 && root.selectedSourcesControlledByLocal()
                 && root.tableController.gameSession.currentPhase
                    === "declare_blockers"
                 && root.hasIncomingAttacker()
        onTriggered: root.tableController.selection.beginRelationTarget("block")
    }
    MenuItem {
        objectName: "clearCombatDeclarationAction"
        text: qsTr("Clear combat declaration") + " · Shift+C"
        enabled: root.tableController.canAct
                 && root.selectedSourcesControlledByLocal()
                 && root.selectedHasCombatDeclaration()
        onTriggered: {
            root.tableController.wsModel.clearCombatArrows(
                        root.selectedBattlefieldIds())
            root.tableController.selection.clear()
        }
    }
    MenuSeparator { }
    Menu {
        title: qsTr("Add counter")
        enabled: root.tableController.selection.selectedCount() === 1
                 && root.tableController.selectedBattlefieldOwnerSeat
                    === root.tableController.roomSession.seatIndex

        MenuItem {
            text: qsTr("Number counter") + " · N / ="
            onTriggered: root.tableController.cardActions.addNumberCounter()
        }
        MenuItem {
            text: qsTr("Ability counter…") + " · Shift+N"
            onTriggered: root.cardCounterEditorPopup.showNewAbility(
                             root.tableController.selectedBattlefieldCard.name)
        }
    }
    Menu {
        title: qsTr("Set counters")
        enabled: root.tableController.selection.selectedCount() === 1
                 && root.tableController.selectedBattlefieldOwnerSeat
                    === root.tableController.roomSession.seatIndex

        MenuItem {
            text: qsTr("Number counter…") + " · Ctrl+N"
            onTriggered: root.cardCounterEditorPopup.showNumber(
                             root.tableController.selectedBattlefieldCard.name,
                             root.tableController.cardActions.numberCounterValue(
                                 root.tableController.selectedBattlefieldCard.counters
                                 ? root.tableController.selectedBattlefieldCard.counters
                                 : []))
        }
        MenuItem {
            text: qsTr("Ability counter…")
            enabled: root.tableController.cardActions.abilityCounters(
                         root.tableController.selectedBattlefieldCard.counters
                         ? root.tableController.selectedBattlefieldCard.counters
                         : []).length > 0
            onTriggered: root.cardCounterEditorPopup.showAbility(
                             root.tableController.selectedBattlefieldCard.name,
                             root.tableController.cardActions.abilityCounters(
                                 root.tableController.selectedBattlefieldCard.counters
                                 ? root.tableController.selectedBattlefieldCard.counters
                                 : []))
        }
    }
    ConditionalMenuSeparator {
        visible: root.tableController.selection.selectedCount() === 1
    }
    Menu {
        objectName: "moveSelectedBattlefieldMenu"
        title: qsTr("Move selected") + " · "
               + root.tableController.selection.selectedCount()
        enabled: root.tableController.selection.selectedCount() > 1

        MenuItem {
            objectName: "moveSelectedBattlefieldToGraveyard"
            text: qsTr("Move to graveyard") + " · Alt+G"
            onTriggered:
                root.tableController.cardMoveCommands.moveSelectedBattlefieldCards(
                    "graveyard")
        }
        MenuItem {
            objectName: "moveSelectedBattlefieldToExile"
            text: qsTr("Move to exile") + " · Alt+E"
            onTriggered:
                root.tableController.cardMoveCommands.moveSelectedBattlefieldCards("exile")
        }
        MenuSeparator { }
        MenuItem {
            objectName: "moveSelectedBattlefieldToLibraryTopOrdered"
            text: qsTr("Top of library · in order") + " · Alt+Up"
            onTriggered:
                root.tableController.cardMoveCommands.moveSelectedBattlefieldCards(
                    "library", "top", false)
        }
        MenuItem {
            objectName: "moveSelectedBattlefieldToLibraryTopRandom"
            text: qsTr("Top of library · random order") + " · Alt+Shift+Up"
            onTriggered:
                root.tableController.cardMoveCommands.moveSelectedBattlefieldCards(
                    "library", "top", true)
        }
        MenuItem {
            objectName: "moveSelectedBattlefieldToLibraryBottomOrdered"
            text: qsTr("Bottom of library · in order") + " · Alt+Down"
            onTriggered:
                root.tableController.cardMoveCommands.moveSelectedBattlefieldCards(
                    "library", "bottom", false)
        }
        MenuItem {
            objectName: "moveSelectedBattlefieldToLibraryBottomRandom"
            text: qsTr("Bottom of library · random order") + " · Alt+Shift+Down"
            onTriggered:
                root.tableController.cardMoveCommands.moveSelectedBattlefieldCards(
                    "library", "bottom", true)
        }
    }
    ConditionalMenuItem {
        objectName: "randomSelectedBattlefieldCardAction"
        text: qsTr("Randomly select one")
        visible: root.tableController.selection.selectedCount() > 1
        enabled: root.tableController.canAct
        onTriggered: {
            root.tableController.wsModel.randomSelectCards(
                        Object.keys(
                            root.tableController.selectedBattlefieldCardIds))
            root.tableController.selection.clear()
        }
    }
    ConditionalMenuItem {
        objectName: "moveBattlefieldCardToHand"
        text: qsTr("Move to hand") + " · Alt+H"
        visible: root.tableController.selection.selectedCount() === 1
        enabled: root.tableController.cardMoveCommands.canManageSelectedBattlefield()
        onTriggered:
            root.tableController.cardMoveCommands.moveSelectedBattlefieldToZone("hand")
    }
    ConditionalMenuItem {
        objectName: "moveBattlefieldCardToGraveyard"
        text: qsTr("Move to graveyard") + " · Alt+G"
        visible: root.tableController.selection.selectedCount() === 1
        enabled: root.tableController.cardMoveCommands.canManageSelectedBattlefield()
        onTriggered: root.tableController.cardMoveCommands.moveSelectedBattlefieldToZone(
                         "graveyard")
    }
    ConditionalMenuItem {
        objectName: "moveBattlefieldCardToExile"
        text: qsTr("Move to exile") + " · Alt+E"
        visible: root.tableController.selection.selectedCount() === 1
        enabled: root.tableController.cardMoveCommands.canManageSelectedBattlefield()
        onTriggered:
            root.tableController.cardMoveCommands.moveSelectedBattlefieldToZone("exile")
    }
    ConditionalMenuItem {
        objectName: "moveBattlefieldCardToLibraryTop"
        text: qsTr("Move to top of library") + " · Alt+Up"
        visible: root.tableController.selection.selectedCount() === 1
        enabled: root.tableController.cardMoveCommands.canManageSelectedBattlefield()
        onTriggered: root.tableController.cardMoveCommands.moveSelectedBattlefieldToLibrary(
                         "top", -1)
    }
    ConditionalMenuItem {
        objectName: "moveBattlefieldCardToLibraryPosition"
        text: qsTr("Move to library position…")
        visible: root.tableController.selection.selectedCount() === 1
        enabled: root.tableController.cardMoveCommands.canManageSelectedBattlefield()
        onTriggered: root.libraryPositionEditorPopup.showFor(
                         root.tableController.selectedBattlefieldCard.name)
    }
    ConditionalMenuItem {
        objectName: "moveBattlefieldCardToLibraryBottom"
        text: qsTr("Move to bottom of library") + " · Alt+Down"
        visible: root.tableController.selection.selectedCount() === 1
        enabled: root.tableController.cardMoveCommands.canManageSelectedBattlefield()
        onTriggered: root.tableController.cardMoveCommands.moveSelectedBattlefieldToLibrary(
                         "bottom", -1)
    }
    ConditionalMenuItem {
        text: qsTr("Create token copy") + " · Alt+C"
        visible: root.tableController.selection.selectedCount() === 1
        enabled: root.tableController.canAct
        onTriggered: root.tableController.cardActions.createSelectedTokenCopy()
    }
}
