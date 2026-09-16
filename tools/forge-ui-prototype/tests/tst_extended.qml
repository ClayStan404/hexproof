// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors
import QtQuick
import QtTest
import "../qml"

Item {
    id: testRoot
    width: 1600
    height: 1000
    StudyModel { id: model }
    StudyBoard {
        id: board
        anchors.fill: parent
        controller: model
        assetRoot: ""
    }
    TestCase {
        name: "ForgeUiExtendedStudy"
        when: windowShown

        function init() {
            testRoot.width = 1600
            testRoot.height = 1000
            board.chooseScene("combat")
            waitForRendering(board)
        }
        function control(name) {
            const item = findChild(board, name)
            verify(item !== null, "Missing control: " + name)
            return item
        }
        function click(name) {
            waitForRendering(board)
            mouseClick(control(name))
        }
        function inBoard(item) {
            const p = item.mapToItem(board, 0, 0)
            verify(p.x >= 0 && p.y >= 0, item.objectName + " starts outside the board")
            verify(p.x + item.width <= board.width + 1, item.objectName + " clips horizontally")
            verify(p.y + item.height <= board.height + 1, item.objectName + " clips vertically")
        }
        function test_attack_selection_submission_and_reset() {
            click("studyCard-own-ravager")
            click("studyCard-ragavan")
            click("studyCard-ragavan")
            compare(model.combat.attackers, ["own-ravager"])
            click("studyCombatConfirm")
            verify(model.combat.committed)
            verify(control("studyCard-own-ravager").tapped)
            click("studyCard-guide")
            compare(model.combat.attackers, ["own-ravager"])
            verify(!control("studyCombatConfirm").enabled)
            click("studyCombatClear")
            compare(model.combat.attackers.length, 0)
            verify(!control("studyCard-own-ravager").tapped)
            click("studyCombatConfirm")
            verify(model.combat.committed, "No attackers is a confirmable choice")
        }
        function test_block_relationships_reassign_and_remove() {
            click("studyCombatMode-block")
            click("studyCard-ragavan")
            click("studyCard-ravager")
            click("studyCard-guide")
            click("studyCard-ravager")
            compare(model.combat.blocks.length, 2)
            compare(control("studyCard-ravager").statusText, "2 BLOCKERS")
            click("studyCard-ragavan")
            click("studyCard-ballista")
            compare(model.combat.blocks.length, 2)
            compare(model.combat.blocks.filter(p => p.blocker === "ragavan")[0].attacker, "ballista")
            click("studyCard-ragavan")
            click("studyCard-ballista")
            compare(model.combat.blocks, [{blocker:"guide", attacker:"ravager"}])
            click("studyCombatConfirm")
            click("studyCard-ajani")
            compare(model.combat.selectedBlocker, "")
            compare(model.combat.blocks.length, 1)
        }
        function test_damage_total_blocks_submission_until_complete() {
            click("studyCombatMode-damage")
            click("studyDamageMinus-walker")
            verify(!control("studyCombatConfirm").enabled)
            click("studyCombatConfirm")
            verify(!model.combat.committed)
            click("studyDamagePlus-ballista")
            compare(model.combat.damage, {ballista:3, walker:3})
            verify(control("studyCombatConfirm").enabled)
            click("studyCombatConfirm")
            verify(model.combat.committed)
            verify(!control("studyDamagePlus-ballista").enabled)
            click("studyCombatClear")
            compare(model.combat.damage, {ballista:2, walker:4})
            for (let i = 0; i < 3; ++i) click("studyDamageMinus-ballista")
            compare(model.combat.damage.ballista, 0)
            verify(!control("studyDamageMinus-ballista").enabled)
        }
        function test_commander_reservation_cancel_and_paid_cast() {
            board.chooseScene("commander")
            waitForRendering(board)
            click("studyCommanderOwn")
            compare(model.duel.state, "payment")
            click("studyCard-duel-land-1")
            compare(model.duel.reserved.length, 1)
            compare(model.duel.castCount, 1)
            verify(!control("studyCommanderPrimary").enabled)
            click("studyCommanderCancel")
            compare(model.duel.state, "ready")
            compare(model.duel.location, "command")
            compare(model.duel.reserved.length, 0)
            compare(model.duel.paid.length, 0)
            compare(model.duel.castCount, 1)
            click("studyCommanderPrimary")
            for (const id of [1, 2, 3]) click("studyCard-duel-land-" + id)
            verify(control("studyCommanderPrimary").enabled)
            compare(model.duel.castCount, 1, "Reservation is not a completed cast")
            click("studyCommanderPrimary")
            compare(model.duel.state, "stack")
            compare(model.duel.location, "stack")
            compare(model.duel.paid.length, 3)
            compare(model.duel.castCount, 2)
            compare(model.visibleStack.length, 1)
            compare(model.hand.length, 3)
            click("studyCommanderPrimary")
            compare(model.duel.location, "battlefield")
            compare(model.visibleStack.length, 0)
            verify(board.ownLane.itemFor("isamaru") !== null)
            verify(!control("studyCommanderPrimary").enabled)
        }
        function test_commander_auto_pay_and_destination_choices() {
            board.chooseScene("commander")
            click("studyCommanderPrimary")
            click("studyCommanderAutoPay")
            compare(model.duel.state, "stack")
            compare(model.duel.castCount, 2)
            click("studyDuelReturnExample")
            compare(model.duel.location, "graveyard")
            click("studyCommanderPrimary")
            compare(model.duel.location, "command")
            compare(model.duel.castCount, 2)
            compare(model.duel.nextCost, "4 W")
            verify(!control("studyCommanderOwn").actionable)
            click("studyDuelReturnExample")
            click("studyCommanderCancel")
            compare(model.duel.state, "finished")
            compare(model.duel.location, "graveyard")
            compare(model.duel.castCount, 2)
        }
        function test_crowded_target_reveals_exact_copy_and_stack_scrolls() {
            board.chooseScene("crowded")
            waitForRendering(board)
            compare(model.ownCreatures.length, 24)
            compare(model.opponentCreatures.length, 20)
            compare(model.hand.length, 15)
            compare(model.visibleStack.length, 8)
            verify(!board.ownLane.isCardVisible("token-23"))
            compare(board.pointFor("token-23"), Qt.point(0, 0))
            click("studyStackTarget-busy-ability-7")
            compare(board.locatedCard, "token-23")
            verify(board.ownLane.isCardVisible("token-23"))
            verify(control("studyCard-token-23").selected)
            verify(!control("studyCard-token-22").selected)
            verify(board.pointFor("token-23").y > 0)
            const scroll = board.stackView.scrollArea
            verify(scroll.contentHeight > scroll.height)
            mouseWheel(scroll, scroll.width / 2, scroll.height / 2, 0, -720)
            tryVerify(() => scroll.contentY > 0)
            verify(!control("studyStackArrow").visible, "Do not attach the top object's arrow to a scrolled entry")
            board.chooseScene("response")
            compare(scroll.contentY, 0)
            verify(control("studyStackArrow").visible)
        }
        function test_crowded_hand_scroll_and_inspection_keep_card_identity() {
            board.chooseScene("crowded")
            waitForRendering(board)
            const scroll = board.handView.scrollArea
            verify(scroll.contentWidth > scroll.width)
            mouseDrag(scroll, scroll.width - 80, scroll.height - 25, -360, 0)
            tryVerify(() => scroll.contentX > 0)
            scroll.cancelFlick()
            board.handView.reveal("extra-hand-14")
            mouseClick(control("studyHand-extra-hand-14"))
            compare(board.pinnedCard.id, "extra-hand-14")
            compare(model.stage, "crowded")
            compare(model.hand.length, 15)
        }
        function test_keyboard_focus_reveals_offscreen_copies() {
            board.chooseScene("crowded")
            waitForRendering(board)
            const lastToken = control("studyCard-token-23")
            lastToken.forceActiveFocus()
            verify(board.ownLane.isCardVisible("token-23"))
            keyClick(Qt.Key_Return)
            compare(board.pinnedCard.id, "token-23")
            const lastHand = control("studyHand-extra-hand-14")
            lastHand.forceActiveFocus()
            verify(board.handView.scrollArea.contentX > 0)
            keyClick(Qt.Key_Return)
            compare(board.pinnedCard.id, "extra-hand-14")
        }
        function test_scene_switch_clears_extended_transients() {
            click("studyCard-guide")
            click("studyCombatConfirm")
            board.chooseScene("commander")
            click("studyCommanderPrimary")
            click("studyCard-duel-land-1")
            board.chooseScene("crowded")
            board.revealTarget("token-23")
            board.handView.reveal("extra-hand-14")
            board.chooseScene("combat")
            verify(!model.combat.committed)
            compare(model.combat.attackers.length, 0)
            compare(model.duel.reserved.length, 0)
            compare(model.duel.state, "ready")
            compare(board.locatedCard, "")
            compare(board.ownLane.scrollOffset, 0)
            compare(board.handView.scrollArea.contentX, 0)
        }
        function test_layout_data() {
            return [{tag:"desktop", w:1600, h:1000}, {tag:"compact", w:1280, h:800},
                    {tag:"local-display", w:1920, h:1010}, {tag:"wide", w:2560, h:1408}]
        }
        function test_layout(data) {
            testRoot.width = data.w
            testRoot.height = data.h
            for (const scene of ["combat", "commander", "crowded"]) {
                board.chooseScene(scene)
                waitForRendering(board)
                inBoard(board.ownLane)
                inBoard(board.opponentLane)
                inBoard(board.handView)
                inBoard(board.activeDock.primaryButton)
                verify(board.opponentLane.y + board.opponentLane.height < board.ownLane.y,
                    "Creature lanes overlap in " + scene)
                verify(board.ownLane.y + board.ownLane.height < control("studyYou").y,
                    "Creature lane overlaps player controls in " + scene)
                if (scene === "combat") {
                    click("studyCombatMode-damage")
                    inBoard(control("studyDamagePlus-walker"))
                } else if (scene === "commander") {
                    inBoard(control("studyCommanderOwn"))
                    inBoard(control("studyCommanderOpponent"))
                    click("studyDuelReturnExample")
                    inBoard(control("studyCommanderCancel"))
                } else {
                    inBoard(board.stackView)
                    verify(board.stackView.y + board.stackView.height < board.activeDock.y,
                        "Long stack overlaps action controls")
                    verify(board.ownLane.cardWidth >= 108 * board.unit)
                    click("studyStackTarget-busy-ability-7")
                    verify(board.ownLane.isCardVisible("token-23"))
                }
            }
        }
    }
}
