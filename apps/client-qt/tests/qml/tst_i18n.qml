// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtTest
import "../../qml/components"

TestCase {
    name: "I18n"

    function init() {
        testTranslations.setLanguage("zh")
    }

    function cleanup() {
        testTranslations.setLanguage("en")
    }

    function test_translatesStructuredCardCacheFailureWithColonInName() {
        compare(
            I18n.status("Could not cache Aang: Master of Elements: Scryfall English metadata via api.scryfall.com: HTTP 404"),
            "无法缓存 Aang: Master of Elements：Scryfall 英文元数据（api.scryfall.com：HTTP 404）")
    }

    function test_emblemLogsTranslateButChatAndPlaceholdersRemainLiteral() {
        const source = "Alice: %2 created a Teferi, Hero of Dominaria Emblem emblem for Bob."
        compare(I18n.gameLog("create_emblem",source),
                "Alice: %2 为 Bob 创建了徽记：Teferi, Hero of Dominaria Emblem。")
        compare(I18n.gameLog("remove_emblem","Bob removed their Teferi, Hero of Dominaria Emblem emblem."),
                "Bob 移除了自己的徽记：Teferi, Hero of Dominaria Emblem。")
        compare(I18n.gameLog("chat",source),source)
        compare(I18n.gameLog("create_emblem","Unexpected text"),"Unexpected text")
    }

    function test_piperColorLogPreservesPhysicalIdentityAndUserText() {
        compare(I18n.gameLog("commander_color", "Alice chose U for The Prismatic Piper (s0-c1)."),
                "Alice 为 The Prismatic Piper（s0-c1）选择了蓝色。")
        compare(I18n.gameLog("commander_color", "Alice: %2 chose G for The Prismatic Piper (s0-c2)."),
                "Alice: %2 为 The Prismatic Piper（s0-c2）选择了绿色。")
        const chat = "Alice chose U for The Prismatic Piper (s0-c1)."
        compare(I18n.gameLog("chat", chat), chat)
    }

    function test_translatesCurrentBulkDescriptorFailure() {
        compare(
            I18n.status("Scryfall returned an invalid default_cards bulk package descriptor (download URL, compressed size)."),
            "Scryfall 返回了无效的 default_cards 批量数据包信息（download URL, compressed size）。")
    }

    function test_translatesTournamentNotReadyCount() {
        // Mirrors the template WsClientDispatch builds for the
        // tournament_not_ready error; keep both in sync.
        compare(
            I18n.status("tournament_not_ready: at least 2 checked-in players are required"),
            "至少需要 2 名已签到选手。")
        compare(
            I18n.status("tournament_not_ready: server-specific wording"),
            "比赛当前还不能执行该操作。")
    }

    function test_translatesDeckImportWarnings() {
        compare(
            I18n.status("Line 2 was ignored: not a card"),
            "第 2 行已忽略：not a card")
        compare(
            I18n.status("Line 7 did not contain a usable card."),
            "第 7 行没有可用的卡牌记录。")
    }

    function test_translatesCatalogSchemaMismatch() {
        compare(
            I18n.status(
                "The selected card database uses schema version 6, but this Hexproof version requires schema version 10."),
            "所选卡牌数据库使用结构版本 6，但当前 Hexproof 需要结构版本 10。")
    }

    function test_translatesTurnCoordinationLogs() {
        compare(
            I18n.status("Alice advanced to the Attackers step."),
            "Alice 推进到宣攻阶段。")
        compare(
            I18n.status("Bob began their turn."),
            "Bob 开始了自己的回合。")
    }

    function test_manualLogsPreserveLiteralFormattingTokens_data() {
        return [
            {tag: "draw", source: "Alice %2 drew 3 cards.",
             english: "Alice %2 drew 3 cards.", chinese: "Alice %2 抓了 3 张牌。"},
            {tag: "counter", source: "Alice %2 set Charge %3 to 7 (+1).",
             english: "Alice %2 set Charge %3 to 7 (+1).",
             chinese: "Alice %2 将 Charge %3 设为 7（+1）。"},
            {tag: "turn", source: "Alice %2 advanced to the Attackers step.",
             english: "Alice %2 advanced to the Attackers step.",
             chinese: "Alice %2 推进到宣攻阶段。"},
            {tag: "public-zone", source: "Alice moved 2 card(s) from Bob %2's graveyard to battlefield.",
             english: "Alice moved 2 card(s) from Bob %2's graveyard to battlefield.",
             chinese: "Alice 将 2 张牌 从Bob %2 的墓地移至战场。"}
        ]
    }

    function test_manualLogsPreserveLiteralFormattingTokens(data) {
        compare(I18n.status(data.source), data.chinese)
        testTranslations.setLanguage("en")
        compare(I18n.status(data.source), data.english)
    }

    function test_translatesForgeJournal_data() {
        return [
            {tag: "start", kind: "rules_start", source: "Game 2 started (Forge rules).",
             expected: "第 2 局开始（Forge 规则）。"},
            {tag: "phase", kind: "rules_phase", source: "Turn 7: Alice: %3 (main1).",
             expected: "第 7 回合：Alice: %3（战前主阶段）。"},
            {tag: "cleanup", kind: "rules_phase", source: "Turn 7: Alice (cleanup).",
             expected: "第 7 回合：Alice（清除）。"},
            {tag: "life", kind: "rules_life", source: "Alice: %2: life 3 → -2.",
             expected: "Alice: %2：生命 3 → -2。"},
            {tag: "playing", kind: "rules_status", source: "Alice: playing.",
             expected: "Alice：对局中。"},
            {tag: "lost", kind: "rules_status", source: "Alice: lost.",
             expected: "Alice：已落败。"},
            {tag: "concede", kind: "rules_status", source: "Alice: conceded.",
             expected: "Alice：已认输。"},
            {tag: "hand-count", kind: "rules_zone_count", source: "Alice: hand count 7 → 6.",
             expected: "Alice：手牌数量 7 → 6。"},
            {tag: "library-count", kind: "rules_zone_count", source: "Alice: library count 53 → 52.",
             expected: "Alice：牌库数量 53 → 52。"},
            {tag: "public-card-name", kind: "rules_card",
             source: "Alice: %2: Aang: Master of Elements in battlefield.",
             expected: "Alice: %2: Aang: Master of Elements 位于战场。"},
            {tag: "hidden-card", kind: "rules_card", source: "Alice: a face-down card in exile.",
             expected: "Alice: 一张牌面朝下的牌 位于放逐区。"},
            {tag: "card-leaves", kind: "rules_card", source: "Alice: Willbender left graveyard.",
             expected: "Alice: Willbender 离开了墓地。"},
            {tag: "command-zone", kind: "rules_card", source: "Alice: Progenitus in command.",
             expected: "Alice: Progenitus 位于指挥官区。"},
            {tag: "tap", kind: "rules_tap", source: "Alice: Forest tapped.",
             expected: "Alice: Forest 已横置。"},
            {tag: "untap", kind: "rules_tap", source: "Alice: a face-down card untapped.",
             expected: "Alice: 一张牌面朝下的牌 已重置。"},
            {tag: "stack-add", kind: "rules_stack", source: "Alice put a spell or ability on the stack.",
             expected: "Alice 将咒语或异能放入堆叠。"},
            {tag: "stack-remove", kind: "rules_stack", source: "A spell or ability controlled by Alice left the stack.",
             expected: "Alice 操控的咒语或异能离开了堆叠。"},
            {tag: "draw", kind: "rules_result", source: "Game ended without a winner.",
             expected: "本局结束，没有获胜者。"},
            {tag: "winner", kind: "rules_result", source: "Alice: %2 won the game.",
             expected: "Alice: %2 赢得本局。"}
        ]
    }

    function test_translatesForgeJournal(data) {
        compare(I18n.gameLog(data.kind, data.source), data.expected)
    }

    function test_forgeJournalDoesNotTranslateChatOrUnrecognizedEvents() {
        const lookalikes = [
            "Alice: life 20 → 19.",
            "Turn 1: Alice (main1).",
            "Alice won the game.",
            "Alice: 请勿翻译这条聊天，%1 $& <b>hello</b>",
            "Alice advanced to the Attackers step."
        ]
        for (const source of lookalikes)
            compare(I18n.gameLog("chat", source), source)
        compare(I18n.gameLog("rules_future", "Alice won the game."), "Alice won the game.")
        compare(I18n.gameLog("rules_life", "Alice: secret arbitrary text"), "Alice: secret arbitrary text")
        compare(I18n.gameLog("rules_card", "Alice: Forest in hand."), "Alice: Forest in hand.")
        compare(I18n.gameLog("rules_phase", "Turn 1: Alice (unknown_step)."), "Turn 1: Alice (unknown_step).")
        compare(I18n.gameLog("phase", "Alice advanced to the Attackers step."), "Alice 推进到宣攻阶段。")
    }

    function test_forgeJournalEnglishKeepsNames() {
        testTranslations.setLanguage("en")
        compare(I18n.gameLog("rules_life", "Alice: %2: life 20 → 19."), "Alice: %2: life 20 → 19.")
        compare(I18n.gameLog("rules_card", "Alice: Aang: Master of Elements in battlefield."),
                "Alice: Aang: Master of Elements is in battlefield.")
    }

    function test_translatesCommanderOpeningOrderLogs() {
        compare(
            I18n.status("Commander opening roll: Alice 18, Bob 12."),
            "指挥官开局掷骰：Alice 18, Bob 12。")
        compare(
            I18n.status("Commander tie-break roll: Alice 16, Bob 7."),
            "指挥官同点重掷：Alice 16, Bob 7。")
        compare(
            I18n.status("Commander turn order: Alice -> Bob -> Carol."),
            "指挥官行动顺序：Alice -> Bob -> Carol。")
    }

    function test_batchLibraryLogDistinguishesRandomPlacementAndFullShuffle() {
        compare(I18n.gameLog("move_cards", "Alice moved 7 card(s) from graveyard to library (bottom, in random order)."),
                "Alice 将 7 张牌 从墓地移至牌库底（随机顺序）。")
        compare(I18n.gameLog("move_cards", "Alice moved 3 card(s) from hand to library and shuffled the library."),
                "Alice 将 3 张牌 从手牌移至牌库并洗牌。")
        compare(I18n.gameLog("remove_token", "Alice removed 2 token(s) from the battlefield."),
                "Alice 从战场移除了 2 个衍生物。")
    }

    function test_manualMatchOutcomeLogsAreTranslated() {
        compare(I18n.gameLog("concede", "Alice %2 conceded. Bob wins Game 2."),
                "Alice %2 已投降。Bob 赢得第 2 局。")
        compare(I18n.gameLog("concede", "Alice conceded and was eliminated."),
                "Alice 已投降并被淘汰。")
        compare(I18n.gameLog("result", "Bob wins the Commander game."),
                "Bob 赢得指挥官对局。")
        compare(I18n.gameLog("start", "Alice goes first after losing Game 1."),
                "Alice 在第 1 局落败后获得先手。")
    }

    function test_translatesMoveLogsAcrossAllDestinations() {
        compare(
            I18n.status("Alice moved Lightning Bolt from hand to Bob's battlefield."),
            "Alice 将 Lightning Bolt 从手牌移至Bob · 战场。")
        compare(
            I18n.status("Alice moved Atraxa from command to sideboard."),
            "Alice 将 Atraxa 从指挥官区移至备牌。")
        compare(
            I18n.status(
                "Alice moved 2 card(s) from Bob's graveyard to battlefield."),
            "Alice 将 2 张牌 从Bob 的墓地移至战场。")
    }

    function test_translatesRemoteLibraryAndFaceDownResolutionLogs() {
        compare(
            I18n.status(
                "Alice looked at the top 3 card(s) of Bob's library."),
            "Alice 查看了Bob 的牌库顶的 3 张牌。")
        compare(
            I18n.status(
                "Alice searched Bob's library and put 2 card(s) face down onto battlefield."),
            "Alice 搜寻了Bob 的牌库，并将 2 张牌牌面朝下置入战场。")
        compare(
            I18n.status(
                "Alice resolved the top 3 card(s) of Bob's library and put 2 card(s) face down onto battlefield."),
            "Alice 查看了Bob 的牌库顶的 3 张牌，并将 2 张牌牌面朝下置入战场。")
        compare(
            I18n.status(
                "Alice resolved the top 3 card(s) of their library and put 2 card(s) on bottom of their library."),
            "Alice 查看了自己的牌库顶的 3 张牌，并将 2 张牌置于自己的牌库底。")
        compare(
            I18n.status(
                "Alice resolved the top 3 card(s) of Bob's library across 3 destination(s)."),
            "Alice 将Bob 的牌库顶 3 张牌分别置入了 3 个目的区域。")
    }
}
