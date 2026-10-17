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
        name: "ForgeUiStudy"
        when: windowShown

        function init() {
            testRoot.width = 1600
            testRoot.height = 1000
            board.chooseScene("board")
            waitForRendering(board)
        }
        function control(name) {
            const item = findChild(board, name)
            verify(item !== null, "Missing control: " + name)
            return item
        }
        function click(name) {
            mouseClick(control(name))
        }
        function test_cast_target_and_payment_controls() {
            click("studyCard-bolt")
            compare(model.stage, "target")
            click("studyCard-ballista")
            compare(model.stage, "payment")
            compare(model.selectedTargetId, "ballista")
            verify(!control("studyPrimary").enabled)
            click("studyCard-plains")
            compare(model.selectedManaId, "")
            click("studyCard-mountain")
            compare(model.selectedManaId, "mountain")
            compare(model.paidManaId, "")
            compare(model.hand.length, 6)
            verify(control("studyPrimary").enabled)
            click("studyPrimary")
            compare(model.stage, "response")
            compare(model.hand.length, 5)
            compare(model.paidManaId, "mountain")
            compare(model.stack.length, 1)
            compare(model.activeStack.targetId, "ballista")
        }
        function test_cancel_reservation_preserves_hand_and_lands() {
            board.chooseScene("payment")
            click("studyCard-foundry")
            compare(model.selectedManaId, "foundry")
            click("studyCancel")
            compare(model.stage, "board")
            compare(model.hand.length, 6)
            compare(model.stack.length, 0)
            compare(model.selectedManaId, "")
            compare(model.paidManaId, "")
            compare(model.selectedTargetId, "")
        }
        function test_hand_click_during_hover_animation() {
            const slot = control("studyHand-bolt")
            mouseMove(slot, slot.width / 2, slot.height / 2)
            mousePress(slot, slot.width / 2, slot.height / 2)
            wait(70)
            mouseRelease(slot, slot.width / 2, slot.height / 2)
            compare(model.stage, "target")
        }
        function test_player_target_and_auto_payment() {
            board.chooseScene("target")
            click("studyOpponent")
            compare(model.stage, "payment")
            compare(model.selectedTargetId, "opponent")
            click("studyAutoPay")
            compare(model.stage, "response")
            compare(model.activeStack.targetId, "opponent")
            click("studyPrimary")
            compare(model.opponentLife, 13)
            compare(model.stack.length, 0)
        }
        function test_change_target_clears_reserved_mana() {
            board.chooseScene("payment")
            model.chooseMana("mountain")
            model.changeTarget()
            compare(model.stage, "target")
            compare(model.selectedTargetId, "")
            compare(model.selectedManaId, "")
            model.chooseTarget("plains", "Plains")
            compare(model.stage, "target")
            model.chooseTarget("you", "You")
            compare(model.stage, "payment")
            compare(model.selectedTargetId, "you")
        }
        function test_scene_reset_discards_transient_selection() {
            board.chooseScene("payment")
            model.chooseMana("mountain")
            board.chooseScene("response")
            compare(model.selectedTargetId, "")
            compare(model.selectedManaId, "")
            compare(model.stack.length, 2)
            board.chooseScene("target")
            compare(model.stack.length, 0)
            compare(model.paidManaId, "")
            compare(model.hand.length, 6)
        }
        function test_stack_resolves_from_top() {
            board.chooseScene("response")
            click("studyPrimary")
            compare(model.stack.length, 1)
            compare(model.activeStack.id, "ballista-ability")
            verify(!model.opponentCreatures.some(c => c.id === "ballista"))
            click("studyPrimary")
            compare(model.stage, "board")
            compare(model.stack.length, 0)
        }
        function test_layout_data() {
            return [{tag:"desktop", w:1600, h:1000}, {tag:"compact", w:1280, h:800},
                    {tag:"wide", w:2560, h:1408}]
        }
        function test_layout(data) {
            testRoot.width = data.w
            testRoot.height = data.h
            for (const scene of ["board", "response", "target", "payment"]) {
                board.chooseScene(scene)
                waitForRendering(board)
                for (const name of ["studyPrimary", "studyCancel", "studyCard-ballista", "studyCard-mountain", "studyYou"]) {
                    const item = control(name)
                    if (!item.visible) continue
                    const point = item.mapToItem(board, 0, 0)
                    verify(point.x >= 0 && point.y >= 0, name + " begins outside " + scene)
                    verify(point.x + item.width <= board.width + 1, name + " clips horizontally")
                    verify(point.y + item.height <= board.height + 1, name + " clips vertically")
                }
                const target = control("studyCard-ballista")
                const dock = control("studyStack")
                if (dock.visible) {
                    const p = target.mapToItem(board, 0, 0)
                    verify(p.x + target.width < dock.x, "Stack covers a legal battlefield target")
                }
            }
        }
    }
}
