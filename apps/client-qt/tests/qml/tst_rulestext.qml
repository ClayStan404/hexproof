// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors
import QtQuick
import QtTest
import "../../qml/components"

TestCase {
    name: "RulesText"
    function init() { testTranslations.setLanguage("zh") }
    function cleanup() { testTranslations.setLanguage("en") }

    function test_nativeTemplatesPreserveInsertedValues_data() {
        return [
            {tag:"ai-advisory-heading", source:"AI deck advisory", expected:"AI 套牌提示"},
            {tag:"game-notice", source:"Game notice", expected:"对局提示"},
            {tag:"ai-advisory", source:"AI can't play these cards well from Forge AI's Deck %2\n=== Main Deck ===\nPrismatic Ending\n=== Sideboard ===\nWrath of the Skies\nYou can continue this game. These cards will remain in the deck.",
                expected:"AI 不擅长使用 Forge AI's Deck %2 中的下列卡牌：\n主牌\nPrismatic Ending\n备牌\nWrath of the Skies\n你可以继续对局。这些卡牌仍会保留在套牌中。"},
            {tag:"starting-hand", source:"Starting hand 2 of 3", expected:"起手牌 2 / 3"},
            {tag:"mulligan", source:"Mulligans taken: 2", expected:"已调度 2 次"},
            {tag:"mana-ability", source:"Choose a mana ability:", expected:"选择法术力异能"},
            {tag:"ability", source:"Choose an ability", expected:"选择异能"},
            {tag:"damage-order", source:"Assign Generous Ent combat damage now?", expected:"先为 Generous Ent 分配战斗伤害？"},
            {tag:"damage-order-placeholders", source:"Assign Card %1 %2's combat damage now?", expected:"先为 Card %1 %2's 分配战斗伤害？"},
            {tag:"put-back", source:"Choose exactly 2 card(s) to put on the bottom of your library.",
                expected:"选择恰好 2 张牌置于你的牌库底。"},
            {tag:"selection", source:"Choose between 1 and 3 card(s).", expected:"选择 1 至 3 张牌。"},
            {tag:"trigger", source:"Use triggered ability of Guide of Souls (42)?\n(Gain 1 life.)",
                expected:"是否使用 Guide of Souls (42) 的触发式异能？\n(Gain 1 life.)"},
            {tag:"surveil", source:"Put Troll of Khazad-dûm (38) on the top of library or graveyard?",
                expected:"将 Troll of Khazad-dûm (38) 留在牌库顶，还是置入墓地？"},
            {tag:"activate", source:"Card %2 — activate ability", expected:"Card %2 — 起动异能"},
            {tag:"cast", source:"Lightning Bolt — cast spell", expected:"Lightning Bolt — 施放咒语"},
            {tag:"land", source:"Plains — play land", expected:"Plains — 使用地"},
            {tag:"mana", source:"Pay Mana Cost: {1}{W/P}", expected:"支付法术力费用：{1}{W/P}"},
            {tag:"priority", source:"Priority: Alice %2\nTurn: 3 (Bob %1)\nPhase: Main phase, precombat\nStack: Empty",
                expected:"优先权：Alice %2\n回合：3（Bob %1）\n阶段：战前主阶段\n堆叠：空"},
            {tag:"unknown", source:"Card %2: Pay {X}{R} or draw two cards?", expected:"Card %2: Pay {X}{R} or draw two cards?"}
        ]
    }
    function test_nativeTemplatesPreserveInsertedValues(data) {
        compare(RulesText.text(data.source), data.expected)
    }
    function test_drawChoiceRequiresStartingPlayerContext() {
        const detail = "Alice, you have won the coin toss.\n\nWould you like to play or draw?"
        compare(RulesText.choice("chooseBoolean", "Draw", "Confirm decision", detail), "后手")
        compare(RulesText.choice("chooseBoolean", "Play", "Confirm decision", detail), "先手")
        compare(RulesText.choice("chooseFromSelection", "Draw", "Choose options", detail), "Draw")
        compare(RulesText.choice("chooseBoolean", "Draw", "Confirm decision", "Draw a card?"), "Draw")
        compare(RulesText.choice("chooseFromSelection", "Cancel", "Choose options", ""), "Cancel")
        compare(RulesText.choice("chooseBoolean", "Unknown mode {R}", "Confirm decision", ""), "Unknown mode {R}")
    }
    function test_damageOrderChoiceRequiresNativeContext() {
        const title = "Assign Generous Ent combat damage now?"
        compare(RulesText.choice("chooseBoolean", "Assign now", title, ""), "先分配这只生物")
        compare(RulesText.choice("chooseBoolean", "Assign later", title, ""), "先分配其他生物")
        compare(RulesText.choice("chooseBoolean", "Assign later", "Assign Card %1 %2's combat damage now?", ""), "先分配其他生物")
        compare(RulesText.choice("chooseFromSelection", "Assign now", title, ""), "Assign now")
        compare(RulesText.choice("chooseFromSelection", "Assign later", title, ""), "Assign later")
        compare(RulesText.choice("chooseBoolean", "Assign now", "Confirm decision", title), "Assign now")
        compare(RulesText.choice("chooseBoolean", "Assign later", "Assign damage now?", ""), "Assign later")
        compare(RulesText.choice("chooseBoolean", "Assign later", "Assign Generous Ent combat damage now? Extra text", ""), "Assign later")
        compare(RulesText.choice("chooseBoolean", "Unknown mode %1", title, ""), "Unknown mode %1")
    }
}
