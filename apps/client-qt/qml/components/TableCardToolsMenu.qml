// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick

AppMenu {
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
        text: qsTr("Choose card face…")
        shortcutId: "table.selection.chooseFace"
        enabled: root.tableController.cardMoveCommands.canControlSelectedBattlefield()
        onTriggered:
            root.tableController.cardMoveCommands.requestBattlefieldFaceSelection()
    }
    ConditionalMenuItem {
        objectName: "toggleCardFaceDownAction"
        visible: root.tableController.selection.selectedCount() === 1
        text: (root.tableController.selectedBattlefieldCard.faceDown === true
               ? qsTr("Turn face up")
               : qsTr("Turn face down"))
        shortcutId: "table.selection.toggleFaceDown"
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
        text: qsTr("Attach to…")
        shortcutId: "table.selection.attach"
        visible: root.tableController.selection.selectedCount() === 1
        enabled: root.tableController.attachmentUi
                 && root.tableController.attachmentUi.canAttachSelected()
        onTriggered: root.tableController.attachmentUi.beginAttach()
    }
    ConditionalMenuItem {
        objectName: "detachAttachmentAction"
        text: qsTr("Detach")
        shortcutId: "table.selection.detach"
        visible: root.tableController.selection.selectedCount() === 1
        enabled: root.tableController.attachmentUi
                 && root.tableController.attachmentUi.canDetachSelected()
        onTriggered: root.tableController.attachmentUi.detachSelected()
    }
    ConditionalMenuSeparator {
        visible: root.tableController.selection.selectedCount() === 1
    }
    AppMenu {
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
        AppMenuSeparator { }
        AppMenuItem {
            objectName: "targetBattlefieldCardAction"
            text: qsTr("Target a battlefield card…")
            shortcutId: "table.selection.target"
            onTriggered:
                root.tableController.selection.beginRelationTarget("arrow")
        }
    }
    AppMenuItem {
        objectName: "clearTargetAction"
        text: qsTr("Clear target")
        shortcutId: "table.selection.clearTarget"
        enabled: root.tableController.canAct
                 && root.selectedSourcesControlledByLocal()
                 && root.selectedHasTarget()
        onTriggered: {
            root.tableController.wsModel.clearCombatArrows(
                        root.selectedBattlefieldIds())
            root.tableController.selection.clear()
        }
    }
    AppMenuSeparator { }
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
        text: qsTr("Attack a battlefield permanent…")
        shortcutId: "table.selection.attack"
        enabled: root.canDeclareAttacks()
        onTriggered: root.tableController.selection.beginRelationTarget("attack")
    }
    AppMenuItem {
        objectName: "declareBlockAction"
        text: qsTr("Block an attacker…")
        shortcutId: "table.selection.block"
        enabled: root.tableController.canAct
                 && root.selectedSourcesControlledByLocal()
                 && root.tableController.gameSession.currentPhase
                    === "declare_blockers"
                 && root.hasIncomingAttacker()
        onTriggered: root.tableController.selection.beginRelationTarget("block")
    }
    AppMenuItem {
        objectName: "clearCombatDeclarationAction"
        text: qsTr("Clear combat declaration")
        shortcutId: "table.selection.clearCombat"
        enabled: root.tableController.canAct
                 && root.selectedSourcesControlledByLocal()
                 && root.selectedHasCombatDeclaration()
        onTriggered: {
            root.tableController.wsModel.clearCombatArrows(
                        root.selectedBattlefieldIds())
            root.tableController.selection.clear()
        }
    }
    AppMenuSeparator { }
    AppMenu {
        title: qsTr("Add counter")
        enabled: root.tableController.selection.selectedCount() === 1
                 && root.tableController.selectedBattlefieldOwnerSeat
                    === root.tableController.roomSession.seatIndex

        AppMenuItem {
            text: qsTr("Number counter")
            shortcutId: ["table.selection.addNumberCounter", "table.selection.numberCounterIncrease"]
            onTriggered: root.tableController.cardActions.addNumberCounter()
        }
        AppMenuItem {
            text: qsTr("Ability counter…")
            shortcutId: "table.selection.addAbilityCounter"
            onTriggered: root.cardCounterEditorPopup.showNewAbility(
                             root.tableController.selectedBattlefieldCard.name)
        }
    }
    AppMenu {
        title: qsTr("Set counters")
        enabled: root.tableController.selection.selectedCount() === 1
                 && root.tableController.selectedBattlefieldOwnerSeat
                    === root.tableController.roomSession.seatIndex

        AppMenuItem {
            text: qsTr("Number counter…")
            shortcutId: "table.selection.setNumberCounter"
            onTriggered: root.cardCounterEditorPopup.showNumber(
                             root.tableController.selectedBattlefieldCard.name,
                             root.tableController.cardActions.numberCounterValue(
                                 root.tableController.selectedBattlefieldCard.counters
                                 ? root.tableController.selectedBattlefieldCard.counters
                                 : []))
        }
        AppMenuItem {
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
    AppMenu {
        objectName: "moveSelectedBattlefieldMenu"
        title: qsTr("Move selected") + " · "
               + root.tableController.selection.selectedCount()
        enabled: root.tableController.selection.selectedCount() > 1

        AppMenuItem {
            objectName: "moveSelectedBattlefieldToHand"
            text: qsTr("Move to hand")
            shortcutId: "table.selection.moveHand"
            onTriggered: root.tableController.cardMoveCommands.moveSelectedBattlefieldCards("hand")
        }
        AppMenuItem {
            objectName: "moveSelectedBattlefieldToGraveyard"
            text: qsTr("Move to graveyard")
            shortcutId: "table.selection.moveGraveyard"
            onTriggered:
                root.tableController.cardMoveCommands.moveSelectedBattlefieldCards(
                    "graveyard")
        }
        AppMenuItem {
            objectName: "moveSelectedBattlefieldToExile"
            text: qsTr("Move to exile")
            shortcutId: "table.selection.moveExile"
            onTriggered:
                root.tableController.cardMoveCommands.moveSelectedBattlefieldCards("exile")
        }
        AppMenuSeparator { }
        AppMenuItem {
            objectName: "moveSelectedBattlefieldToLibraryTopOrdered"
            text: qsTr("Top of library · in order")
            shortcutId: "table.selection.moveLibraryTop"
            onTriggered:
                root.tableController.cardMoveCommands.moveSelectedBattlefieldCards(
                    "library", "top", false)
        }
        AppMenuItem {
            objectName: "moveSelectedBattlefieldToLibraryTopRandom"
            text: qsTr("Top of library · random order")
            shortcutId: "table.selection.randomLibraryTop"
            onTriggered:
                root.tableController.cardMoveCommands.moveSelectedBattlefieldCards(
                    "library", "top", true)
        }
        AppMenuItem {
            objectName: "moveSelectedBattlefieldToLibraryBottomOrdered"
            text: qsTr("Bottom of library · in order")
            shortcutId: "table.selection.moveLibraryBottom"
            onTriggered:
                root.tableController.cardMoveCommands.moveSelectedBattlefieldCards(
                    "library", "bottom", false)
        }
        AppMenuItem {
            objectName: "moveSelectedBattlefieldToLibraryBottomRandom"
            text: qsTr("Bottom of library · random order")
            shortcutId: "table.selection.randomLibraryBottom"
            onTriggered:
                root.tableController.cardMoveCommands.moveSelectedBattlefieldCards(
                    "library", "bottom", true)
        }
        AppMenuItem {
            objectName: "moveSelectedBattlefieldShuffleIntoLibrary"
            text: qsTr("Shuffle into library")
            onTriggered: root.tableController.cardMoveCommands.moveSelectedBattlefieldCards("library", "shuffle", false)
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
        text: qsTr("Move to hand")
        shortcutId: "table.selection.moveHand"
        visible: root.tableController.selection.selectedCount() === 1
        enabled: root.tableController.cardMoveCommands.canManageSelectedBattlefield()
        onTriggered:
            root.tableController.cardMoveCommands.moveSelectedBattlefieldToZone("hand")
    }
    ConditionalMenuItem {
        objectName: "moveBattlefieldCardToGraveyard"
        text: qsTr("Move to graveyard")
        shortcutId: "table.selection.moveGraveyard"
        visible: root.tableController.selection.selectedCount() === 1
        enabled: root.tableController.cardMoveCommands.canManageSelectedBattlefield()
        onTriggered: root.tableController.cardMoveCommands.moveSelectedBattlefieldToZone(
                         "graveyard")
    }
    ConditionalMenuItem {
        objectName: "moveBattlefieldCardToExile"
        text: qsTr("Move to exile")
        shortcutId: "table.selection.moveExile"
        visible: root.tableController.selection.selectedCount() === 1
        enabled: root.tableController.cardMoveCommands.canManageSelectedBattlefield()
        onTriggered:
            root.tableController.cardMoveCommands.moveSelectedBattlefieldToZone("exile")
    }
    ConditionalMenuItem {
        objectName: "moveBattlefieldCardToLibraryTop"
        text: qsTr("Move to top of library")
        shortcutId: "table.selection.moveLibraryTop"
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
        text: qsTr("Move to bottom of library")
        shortcutId: "table.selection.moveLibraryBottom"
        visible: root.tableController.selection.selectedCount() === 1
        enabled: root.tableController.cardMoveCommands.canManageSelectedBattlefield()
        onTriggered: root.tableController.cardMoveCommands.moveSelectedBattlefieldToLibrary(
                         "bottom", -1)
    }
    ConditionalMenuItem {
        text: qsTr("Create token copy")
        shortcutId: "table.selection.createTokenCopy"
        visible: root.tableController.selection.selectedCount() === 1
        enabled: root.tableController.canAct
        onTriggered: root.tableController.cardActions.createSelectedTokenCopy()
    }
}
