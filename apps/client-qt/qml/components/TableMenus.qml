// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic

Item {
    id: root

    required property var tableController
    required property var drawCardsEditorPopup
    required property var publicZoneBrowserPopup
    required property var libraryTopCountEditorPopup
    required property var tokenPickerPopup
    required property var handLibraryPositionEditorPopup
    required property var cardCounterEditorPopup
    required property var libraryPositionEditorPopup
    required property var discardHandConfirmation

    readonly property alias ownLibraryMenu: ownLibraryMenu
    readonly property alias opponentLibraryMenu: opponentLibraryMenu
    readonly property alias battlefieldAreaMenu: battlefieldAreaMenu
    readonly property alias handAreaMenu: handAreaMenu
    readonly property alias handCardMenu: handCardMenu
    readonly property alias cardToolsMenu: cardToolsMenu

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

    Menu {
        id: ownLibraryMenu
        width: Math.min(root.width - Theme.size(24), Theme.size(420))

        MenuItem {
            objectName: "drawCardsAction"
            text: qsTr("Draw X cards") + " · Ctrl+D"
            enabled: root.tableController.ownSeatData.libraryCount > 0
            onTriggered: root.drawCardsEditorPopup.showFor(2)
        }
        MenuItem {
            objectName: "shuffleLibraryAction"
            text: qsTr("Shuffle") + " · Ctrl+Shift+S"
            onTriggered: root.tableController.shuffleConfirmation.open()
        }
        MenuSeparator { }
        MenuItem {
            text: qsTr("Search library") + " · Ctrl+F"
            enabled: root.tableController.ownSeatData.libraryCount > 0
            onTriggered: root.tableController.wsModel.dumpLibrary(
                             root.tableController.roomSession.seatIndex)
        }
        MenuItem {
            objectName: "viewSideboardAction"
            text: qsTr("View sideboard") + " · Ctrl+B · "
                  + (root.tableController.ownSeatData.sideboardCount
                     ? root.tableController.ownSeatData.sideboardCount : 0)
            enabled: root.tableController.canAct
                     && root.tableController.ownSeatData.sideboardCount > 0
            onTriggered: root.publicZoneBrowserPopup.showZone(
                             root.tableController.ownSeatData.displayName,
                             root.tableController.roomSession.seatIndex,
                             "sideboard")
        }
        MenuSeparator { }
        MenuItem {
            objectName: "viewLibraryTopCardAction"
            text: qsTr("View top card") + " · Ctrl+Shift+L"
            enabled: root.tableController.ownSeatData.libraryCount > 0
            onTriggered: root.tableController.wsModel.dumpLibrary(
                             root.tableController.roomSession.seatIndex, 1)
        }
        MenuItem {
            objectName: "viewLibraryTopCardsAction"
            text: qsTr("View top X cards…") + " · Ctrl+L"
            enabled: root.tableController.ownSeatData.libraryCount > 0
            onTriggered: root.libraryTopCountEditorPopup.showForLibrary(
                             root.tableController.roomSession.seatIndex,
                             root.tableController.ownSeatData.libraryCount,
                             Math.min(
                                 5,
                                 root.tableController.ownSeatData.libraryCount))
        }
        MenuItem {
            objectName: "moveLibraryTopToGraveyardAction"
            text: qsTr("Put top X cards into graveyard…")
                  + " · Ctrl+Shift+G"
            enabled: root.tableController.ownSeatData.libraryCount > 0
            onTriggered:
                root.tableController.sessionUi.showLibraryMoveCardsEditor("graveyard")
        }
        MenuItem {
            objectName: "moveLibraryTopToExileAction"
            text: qsTr("Put top X cards into exile…")
                  + " · Ctrl+Shift+E"
            enabled: root.tableController.ownSeatData.libraryCount > 0
            onTriggered:
                root.tableController.sessionUi.showLibraryMoveCardsEditor("exile")
        }
    }

    Menu {
        id: opponentLibraryMenu
        objectName: "opponentLibraryMenu"
        property int sourceSeat: -1
        property int sourceLibraryCount: 0

        MenuItem {
            objectName: "opponentLibrarySearchAction"
            text: qsTr("Search library")
            enabled: root.tableController.canAct
                     && opponentLibraryMenu.sourceSeat >= 0
                     && opponentLibraryMenu.sourceLibraryCount > 0
            onTriggered: root.tableController.wsModel.dumpLibrary(
                             opponentLibraryMenu.sourceSeat)
        }
        MenuSeparator { }
        MenuItem {
            objectName: "opponentLibraryViewTopCardAction"
            text: qsTr("View top card")
            enabled: root.tableController.canAct
                     && opponentLibraryMenu.sourceSeat >= 0
                     && opponentLibraryMenu.sourceLibraryCount > 0
            onTriggered: root.tableController.wsModel.dumpLibrary(
                             opponentLibraryMenu.sourceSeat, 1)
        }
        MenuItem {
            objectName: "opponentLibraryViewTopCardsAction"
            text: qsTr("View top X cards…")
            enabled: root.tableController.canAct
                     && opponentLibraryMenu.sourceSeat >= 0
                     && opponentLibraryMenu.sourceLibraryCount > 0
            onTriggered: root.libraryTopCountEditorPopup.showForLibrary(
                             opponentLibraryMenu.sourceSeat,
                             opponentLibraryMenu.sourceLibraryCount,
                             Math.min(
                                 5,
                                 opponentLibraryMenu.sourceLibraryCount))
        }
    }

    Menu {
        id: battlefieldAreaMenu
        objectName: "battlefieldAreaMenu"

        MenuItem {
            objectName: "untapAllBattlefieldAction"
            text: qsTr("Untap all") + " · Ctrl+U"
            enabled: root.tableController.canAct
                     && root.tableController.gameValues.hasTappedOwnPermanent()
            onTriggered: root.tableController.gameValues.untapOwnBattlefield()
        }
        MenuItem {
            objectName: "arrangeBattlefieldAction"
            text: qsTr("Arrange battlefield") + " · Ctrl+Shift+A"
            enabled: root.tableController.canAct
                     && root.tableController.zoneState.zoneCardCount(
                         root.tableController.roomSession.seatIndex,
                         "battlefield") > 0
            onTriggered:
                root.tableController.cardMoveCommands.arrangeOwnBattlefield()
        }
        MenuSeparator { }
        MenuItem {
            objectName: "createTokenAction"
            text: qsTr("Create token") + " · Ctrl+T"
            enabled: root.tableController.canAct
            onTriggered: root.tokenPickerPopup.open()
        }
        Menu {
            title: qsTr("Random tools")
            enabled: root.tableController.canAct

            MenuItem {
                objectName: "rollDiceAction"
                text: qsTr("Roll dice…") + " · Ctrl+R"
                onTriggered: root.tableController.diceRollPopup.showFor(20, 1)
            }
            MenuItem {
                objectName: "flipCoinAction"
                text: qsTr("Flip a coin") + " · Ctrl+Shift+C"
                onTriggered: root.tableController.wsModel.flipCoin()
            }
            MenuItem {
                objectName: "randomPlayerAction"
                text: qsTr("Random player") + " · Ctrl+Alt+P"
                onTriggered:
                    root.tableController.wsModel.randomSelectPlayer()
            }
            MenuItem {
                objectName: "randomBattlefieldCardAction"
                text: qsTr("Random battlefield card") + " · Ctrl+Alt+R"
                enabled:
                    root.tableController.selection.allCardIds().length > 0
                onTriggered: root.tableController.wsModel.randomSelectCards(
                                 root.tableController.selection.allCardIds())
            }
        }
        MenuSeparator {
            visible: !root.tableController.isPlaytest
        }
        MenuItem {
            objectName: "declareDrawAction"
            visible: !root.tableController.isPlaytest
            text: qsTr("Declare draw") + " · Ctrl+Shift+D"
            enabled: root.tableController.canAct
            onTriggered: root.tableController.drawConfirmation.open()
        }
        MenuItem {
            objectName: "restartGameAction"
            text: qsTr("Restart game") + " · Ctrl+Shift+R"
            enabled: root.tableController.canAct
                     && root.tableController.roomSession.host
            onTriggered: root.tableController.restartConfirmation.open()
        }
        MenuItem {
            objectName: "concedeAction"
            visible: !root.tableController.isPlaytest
            text: qsTr("Concede") + " · Ctrl+Shift+Q"
            enabled: !root.tableController.gameFinished
                     && !root.tableController.ownEliminated
                     && !root.tableController.gameSession.sideboarding
            onTriggered: root.tableController.concedeConfirmation.open()
        }
    }

    Menu {
        id: handAreaMenu
        objectName: "handAreaMenu"

        MenuItem {
            objectName: "revealHandAction"
            text: (root.tableController.ownRevealedCards.length > 0
                   ? qsTr("Recall hand")
                   : qsTr("Reveal hand")) + " · Ctrl+H"
            enabled: root.tableController.canAct
                     && (root.tableController.projectionSync.visibleOwnHandCount() > 0
                         || root.tableController.ownRevealedCards.length > 0)
                     && !root.tableController.zoneState.handRevealTransitionPending()
            onTriggered: root.tableController.cardActions.toggleHandReveal()
        }
        MenuSeparator { }
        MenuItem {
            objectName: "discardRandomHandCardAction"
            text: qsTr("Discard a random card") + " · Ctrl+Alt+X"
            enabled: root.tableController.canAct
                     && root.tableController.projectionSync.visibleOwnHandCount() > 0
            onTriggered: root.tableController.wsModel.discardHand(false)
        }
        MenuItem {
            objectName: "discardEntireHandAction"
            text: qsTr("Discard entire hand…") + " · Ctrl+Shift+X"
            enabled: root.tableController.canAct
                     && root.tableController.projectionSync.visibleOwnHandCount() > 0
            onTriggered: root.discardHandConfirmation.open()
        }
        MenuSeparator { }
        MenuItem {
            objectName: "mulliganAction"
            text: qsTr("Mulligan") + " · Ctrl+M"
            enabled: root.tableController.canAct
                     && root.tableController.authoritativeSeats.length > 0
            onTriggered: root.tableController.mulliganConfirmation.open()
        }
    }

    Menu {
        id: handCardMenu
        objectName: "handCardMenu"

        MenuItem {
            objectName: "playLandAction"
            text: qsTr("Play land…") + " · P"
            enabled: root.tableController.isActivePlayer
                     && !!root.tableController.selectedHandCard
                     && !!root.tableController.selectedHandCard.id
            onTriggered:
                root.tableController.landPlay.requestSelectedHandCard()
        }
        MenuSeparator { }
        MenuItem {
            text: qsTr("Move to battlefield") + " · Alt+B"
            enabled: root.tableController.canAct
                     && !!root.tableController.selectedHandCard
                     && !!root.tableController.selectedHandCard.id
            onTriggered:
                root.tableController.cardMoveCommands.moveSelectedHandCard("battlefield")
        }
        MenuItem {
            text: qsTr("Move to battlefield face down") + " · Alt+Shift+B"
            enabled: root.tableController.canAct
                     && !!root.tableController.selectedHandCard
                     && !!root.tableController.selectedHandCard.id
            onTriggered:
                root.tableController.cardMoveCommands.moveSelectedHandCard("battlefield", true)
        }
        MenuItem {
            text: qsTr("Move to graveyard") + " · Alt+G"
            enabled: root.tableController.canAct
                     && !!root.tableController.selectedHandCard
                     && !!root.tableController.selectedHandCard.id
            onTriggered:
                root.tableController.cardMoveCommands.moveSelectedHandCard("graveyard")
        }
        MenuItem {
            text: qsTr("Move to exile") + " · Alt+E"
            enabled: root.tableController.canAct
                     && !!root.tableController.selectedHandCard
                     && !!root.tableController.selectedHandCard.id
            onTriggered: root.tableController.cardMoveCommands.moveSelectedHandCard("exile")
        }
        MenuSeparator { }
        MenuItem {
            text: qsTr("Move to top of library") + " · Alt+Up"
            enabled: root.tableController.canAct
                     && !!root.tableController.selectedHandCard
                     && !!root.tableController.selectedHandCard.id
            onTriggered:
                root.tableController.cardMoveCommands.moveSelectedHandToLibrary("top", -1)
        }
        MenuItem {
            text: qsTr("Move to library position…")
            enabled: root.tableController.canAct
                     && !!root.tableController.selectedHandCard
                     && !!root.tableController.selectedHandCard.id
            onTriggered: root.handLibraryPositionEditorPopup.showFor(
                             root.tableController.selectedHandCard.name)
        }
        MenuItem {
            text: qsTr("Move to bottom of library") + " · Alt+Down"
            enabled: root.tableController.canAct
                     && !!root.tableController.selectedHandCard
                     && !!root.tableController.selectedHandCard.id
            onTriggered:
                root.tableController.cardMoveCommands.moveSelectedHandToLibrary("bottom", -1)
        }
    }

    Menu {
        id: cardToolsMenu
        objectName: "cardToolsMenu"

        MenuItem {
            objectName: "chooseCardFaceAction"
            visible: root.tableController.selection.selectedCount() === 1
                     && root.tableController.selectedBattlefieldFaces.length > 1
            text: qsTr("Choose card face…") + " · V"
            enabled: root.tableController.cardMoveCommands.canControlSelectedBattlefield()
            onTriggered:
                root.tableController.cardMoveCommands.requestBattlefieldFaceSelection()
        }
        MenuItem {
            objectName: "toggleCardFaceDownAction"
            visible: root.tableController.selection.selectedCount() === 1
            text: (root.tableController.selectedBattlefieldCard.faceDown === true
                   ? qsTr("Turn face up")
                   : qsTr("Turn face down")) + " · F"
            enabled: root.tableController.cardMoveCommands.canControlSelectedBattlefield()
            onTriggered: {
                root.tableController.wsModel.setCardFaceDown(
                            root.tableController.selectedBattlefieldCard.id,
                            root.tableController.selectedBattlefieldCard
                                .faceDown !== true)
                root.tableController.selection.clear()
            }
        }
        MenuSeparator {
            visible: root.tableController.selection.selectedCount() === 1
        }
        MenuItem {
            objectName: "attachToAction"
            text: qsTr("Attach to…") + " · A"
            visible: root.tableController.selection.selectedCount() === 1
            enabled: root.tableController.attachmentUi
                     && root.tableController.attachmentUi.canAttachSelected()
            onTriggered: root.tableController.attachmentUi.beginAttach()
        }
        MenuItem {
            objectName: "detachAttachmentAction"
            text: qsTr("Detach") + " · Shift+A"
            visible: root.tableController.selection.selectedCount() === 1
            enabled: root.tableController.attachmentUi
                     && root.tableController.attachmentUi.canDetachSelected()
            onTriggered: root.tableController.attachmentUi.detachSelected()
        }
        MenuSeparator {
            visible: root.tableController.selection.selectedCount() === 1
        }
        Menu {
            objectName: "chooseTargetMenu"
            title: qsTr("Choose target")
            enabled: root.tableController.canAct
                     && root.selectedSourcesControlledByLocal()

            MenuItem {
                objectName: "targetSeat0Action"
                visible: root.eligibleTargetSeat(0)
                text: qsTr("Target %1").arg(root.combatTargetLabel(0))
                onTriggered: root.targetPlayer(0)
            }
            MenuItem {
                objectName: "targetSeat1Action"
                visible: root.eligibleTargetSeat(1)
                text: qsTr("Target %1").arg(root.combatTargetLabel(1))
                onTriggered: root.targetPlayer(1)
            }
            MenuItem {
                objectName: "targetSeat2Action"
                visible: root.eligibleTargetSeat(2)
                text: qsTr("Target %1").arg(root.combatTargetLabel(2))
                onTriggered: root.targetPlayer(2)
            }
            MenuItem {
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
        MenuItem {
            objectName: "declareAttackAgainstSeat0Action"
            visible: root.eligibleCombatTarget(0)
            text: root.attackPlayerText(0)
            enabled: root.canDeclareAttacks()
            onTriggered: root.declareAttacks(0)
        }
        MenuItem {
            objectName: "declareAttackAgainstSeat1Action"
            visible: root.eligibleCombatTarget(1)
            text: root.attackPlayerText(1)
            enabled: root.canDeclareAttacks()
            onTriggered: root.declareAttacks(1)
        }
        MenuItem {
            objectName: "declareAttackAgainstSeat2Action"
            visible: root.eligibleCombatTarget(2)
            text: root.attackPlayerText(2)
            enabled: root.canDeclareAttacks()
            onTriggered: root.declareAttacks(2)
        }
        MenuItem {
            objectName: "declareAttackAgainstSeat3Action"
            visible: root.eligibleCombatTarget(3)
            text: root.attackPlayerText(3)
            enabled: root.canDeclareAttacks()
            onTriggered: root.declareAttacks(3)
        }
        MenuItem {
            objectName: "declareAttackAgainstPermanentAction"
            visible: root.hasEligibleCombatTarget()
            text: qsTr("Attack a battlefield permanent…") + " · X"
            enabled: root.canDeclareAttacks()
            onTriggered:
                root.tableController.selection.beginRelationTarget("attack")
        }
        MenuItem {
            objectName: "declareBlockAction"
            text: qsTr("Block an attacker…") + " · Shift+X"
            enabled: root.tableController.canAct
                     && root.selectedSourcesControlledByLocal()
                     && root.tableController.gameSession.currentPhase
                        === "declare_blockers"
                     && root.hasIncomingAttacker()
            onTriggered:
                root.tableController.selection.beginRelationTarget("block")
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
                text: qsTr("Number counter") + " · N"
                onTriggered: root.tableController.cardActions.addNumberCounter()
            }
            MenuItem {
                text: qsTr("Ability counter…") + " · Shift+N"
                onTriggered: root.cardCounterEditorPopup.showNewAbility(
                                 root.tableController
                                     .selectedBattlefieldCard.name)
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
                                 root.tableController
                                     .selectedBattlefieldCard.name,
                                 root.tableController.cardActions.numberCounterValue(
                                     root.tableController
                                         .selectedBattlefieldCard.counters
                                     ? root.tableController
                                           .selectedBattlefieldCard.counters
                                     : []))
            }
            MenuItem {
                text: qsTr("Ability counter…")
                enabled: root.tableController.cardActions.abilityCounters(
                             root.tableController.selectedBattlefieldCard
                                 .counters
                             ? root.tableController.selectedBattlefieldCard
                                   .counters
                             : []).length > 0
                onTriggered: root.cardCounterEditorPopup.showAbility(
                                 root.tableController
                                     .selectedBattlefieldCard.name,
                                 root.tableController.cardActions.abilityCounters(
                                     root.tableController
                                         .selectedBattlefieldCard.counters
                                     ? root.tableController
                                           .selectedBattlefieldCard.counters
                                     : []))
            }
        }
        MenuSeparator {
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
        MenuItem {
            objectName: "randomSelectedBattlefieldCardAction"
            text: qsTr("Randomly select one")
            visible: root.tableController.selection.selectedCount() > 1
            enabled: root.tableController.canAct
            onTriggered: {
                root.tableController.wsModel.randomSelectCards(
                            Object.keys(
                                root.tableController
                                    .selectedBattlefieldCardIds))
                root.tableController.selection.clear()
            }
        }
        MenuItem {
            objectName: "moveBattlefieldCardToHand"
            text: qsTr("Move to hand") + " · Alt+H"
            visible: root.tableController.selection.selectedCount() === 1
            enabled: root.tableController.cardMoveCommands.canManageSelectedBattlefield()
            onTriggered:
                root.tableController.cardMoveCommands.moveSelectedBattlefieldToZone("hand")
        }
        MenuItem {
            objectName: "moveBattlefieldCardToGraveyard"
            text: qsTr("Move to graveyard") + " · Alt+G"
            visible: root.tableController.selection.selectedCount() === 1
            enabled: root.tableController.cardMoveCommands.canManageSelectedBattlefield()
            onTriggered:
                root.tableController.cardMoveCommands.moveSelectedBattlefieldToZone(
                    "graveyard")
        }
        MenuItem {
            objectName: "moveBattlefieldCardToExile"
            text: qsTr("Move to exile") + " · Alt+E"
            visible: root.tableController.selection.selectedCount() === 1
            enabled: root.tableController.cardMoveCommands.canManageSelectedBattlefield()
            onTriggered:
                root.tableController.cardMoveCommands.moveSelectedBattlefieldToZone("exile")
        }
        MenuItem {
            objectName: "moveBattlefieldCardToLibraryTop"
            text: qsTr("Move to top of library") + " · Alt+Up"
            visible: root.tableController.selection.selectedCount() === 1
            enabled: root.tableController.cardMoveCommands.canManageSelectedBattlefield()
            onTriggered:
                root.tableController.cardMoveCommands.moveSelectedBattlefieldToLibrary(
                    "top", -1)
        }
        MenuItem {
            objectName: "moveBattlefieldCardToLibraryPosition"
            text: qsTr("Move to library position…")
            visible: root.tableController.selection.selectedCount() === 1
            enabled: root.tableController.cardMoveCommands.canManageSelectedBattlefield()
            onTriggered: root.libraryPositionEditorPopup.showFor(
                             root.tableController
                                 .selectedBattlefieldCard.name)
        }
        MenuItem {
            objectName: "moveBattlefieldCardToLibraryBottom"
            text: qsTr("Move to bottom of library") + " · Alt+Down"
            visible: root.tableController.selection.selectedCount() === 1
            enabled: root.tableController.cardMoveCommands.canManageSelectedBattlefield()
            onTriggered:
                root.tableController.cardMoveCommands.moveSelectedBattlefieldToLibrary(
                    "bottom", -1)
        }
        MenuItem {
            text: qsTr("Create token copy") + " · Alt+C"
            visible: root.tableController.selection.selectedCount() === 1
            enabled: root.tableController.canAct
            onTriggered: root.tableController.cardActions.createSelectedTokenCopy()
        }
    }
}
