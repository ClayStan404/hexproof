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
            {tag:"starting-hand", source:"Starting hand 2 of 3", expected:"起手牌 2 / 3"},
            {tag:"mulligan", source:"Mulligans taken: 2", expected:"已调度 2 次"},
            {tag:"mana-ability", source:"Choose a mana ability:", expected:"选择法术力异能"},
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
}
