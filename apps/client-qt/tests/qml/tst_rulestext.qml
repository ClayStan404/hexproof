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
            {tag:"order-first", source:"First", expected:"最先"},
            {tag:"order-after", source:"After Lightning Bolt", expected:"排在 Lightning Bolt 之后"},
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
        compare(RulesText.choice("chooseFromSelection", "Cancel", "Choose options", ""), "取消")
        compare(RulesText.choice("chooseBoolean", "Unknown mode {R}", "Confirm decision", ""), "Unknown mode {R}")
    }
    function test_damageOrderChoiceRequiresNativeContext() {
        const title = "Assign Generous Ent combat damage now?"
        compare(RulesText.choice("chooseBoolean", "Assign now", title, ""), "先分配这只生物")
        compare(RulesText.choice("chooseBoolean", "Assign later", title, ""), "先分配其他生物")
        compare(RulesText.choice("chooseBoolean", "Assign later", "Assign Card %1 %2's combat damage now?", ""), "先分配其他生物")
        compare(RulesText.choice("chooseFromSelection", "Assign now", title, ""), "先分配这只生物")
        compare(RulesText.choice("chooseFromSelection", "Assign later", title, ""), "先分配其他生物")
        compare(RulesText.choice("chooseBoolean", "Assign now", "Confirm decision", title), "Assign now")
        compare(RulesText.choice("chooseBoolean", "Assign later", "Assign damage now?", ""), "Assign later")
        compare(RulesText.choice("chooseBoolean", "Assign later", "Assign Generous Ent combat damage now? Extra text", ""), "Assign later")
        compare(RulesText.choice("chooseBoolean", "Unknown mode %1", title, ""), "Unknown mode %1")
    }

    function test_modalPromptNamesTheCurrentEffect() {
        const english = "Choose two —\n"
                + "• Target player creates X 0/1 colorless Eldrazi Spawn creature tokens.\n"
                + "• Target player scries X, then draws a card.\n"
                + "• Exile target creature with mana value X or less.\n"
                + "• Exile up to X target cards from graveyards."
        const chinese = "选择两项～\n"
                + "• 目标牌手派出衍生生物。\n"
                + "• 目标牌手占卜 X，然后抓一张牌。\n"
                + "• 放逐目标生物。\n"
                + "• 放逐坟墓场中的牌。"
        const title = "claystan activated Kozilek's Command - Choose a mode"
        compare(RulesText.text(title), "claystan 起动了 Kozilek's Command — 选择模式")
        compare(RulesText.modalChoice("chooseFromSelection", title,
                    "Target player scries X, then draws a card.", 1, 4, english, chinese),
                "目标牌手占卜 X，然后抓一张牌。")
        compare(RulesText.modalChoice("chooseFromSelection", title,
                    "Exile up to X target cards from graveyards.", 3, 4, "", chinese), "")
        compare(RulesText.modalChoice("chooseFromSelection", title,
                    "Target player creates X 0/1 colorless Eldrazi Spawn creature tokens with \"Sacrifice this creature: Add {C}.\"",
                    0, 4, english, chinese),
                "目标牌手派出衍生生物。")
        compare(RulesText.modalChoice("chooseFromSelection", "Choose an ability", "Flying", 0, 2, english, chinese), "")
        const both = "Kozilek's Command (5) - Target player creates X 0/1 colorless Eldrazi Spawn creature tokens. "
                + "Target player scries X, then draws a card.\nSelect target player"
        compare(RulesText.currentEffectTitle(both, english, chinese), "当前效果：目标牌手派出衍生生物。")
        compare(RulesText.targetInstructionTitle(both), "选择目标牌手")
        const second = "Kozilek's Command (5) - Target player scries X, then draws a card.\nSelect target player"
        compare(RulesText.currentEffectTitle(second, english, chinese), "当前效果：目标牌手占卜 X，然后抓一张牌。")
        compare(RulesText.text("Choose target creature with mana value X or less"),
                "选择法术力值等于或小于 X 的目标生物")
        compare(RulesText.text("Choose target card in a graveyard"), "选择坟墓场中的目标牌")
        compare(RulesText.currentEffectTitle("Lightning Bolt deals 3 damage.\nSelect target creature or player",
                                             "Lightning Bolt deals 3 damage to any target.", chinese), "")
        const englishCard = "You may reveal this card from your opening hand. If you do, at the beginning of your first upkeep, look at the top four cards.\n\nWhen you cast this spell, exile target permanent."
        const chineseCard = "你可以从开局手牌展示此牌。若如此做，在你的第一个维持开始时，检视牌库顶四张牌。\n\n当你施放此咒语时，放逐目标永久物。"
        compare(RulesText.localizedAbility(
                    "At the beginning of your first upkeep, look at the top four cards.",
                    englishCard, chineseCard),
                "你可以从开局手牌展示此牌。若如此做，在你的第一个维持开始时，检视牌库顶四张牌。")
        compare(RulesText.localizedAbility("Deal 3 damage", "", "闪电击对任意目标造成3点伤害。"),
                "闪电击对任意目标造成3点伤害。")
        compare(RulesText.localizedAbility("Deal 3 damage", "", ""), "Deal 3 damage")
    }
}
