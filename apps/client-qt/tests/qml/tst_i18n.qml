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

    function test_translatesManualLogActions_data() {
        return [
            {tag: "token", kind: "create_token", source: "Alice created a Goblin token.",
             expected: "Alice 创建了衍生物：Goblin。"},
            {tag: "remove-token", kind: "remove_token", source: "Alice removed token Goblin from the battlefield.",
             expected: "Alice 从战场移除了衍生物：Goblin。"},
            {tag: "remove-hidden-token", kind: "remove_token", source: "Alice removed a face-down token from the battlefield.",
             expected: "Alice 从战场移除了一个牌面朝下的衍生物。"},
            {tag: "face-down", kind: "face_down", source: "Alice turned a battlefield card face down.",
             expected: "Alice 将一张战场上的牌翻为牌面朝下。"},
            {tag: "face-up", kind: "face_down", source: "Alice turned a battlefield card face up.",
             expected: "Alice 将一张战场上的牌翻为牌面朝上。"},
            {tag: "discard-hand", kind: "discard_hand", source: "Alice discarded their hand (7 cards).",
             expected: "Alice 弃掉了全部手牌（7 张）。"},
            {tag: "discard-random", kind: "discard_random", source: "Alice randomly discarded Lightning Bolt.",
             expected: "Alice 随机弃掉了 Lightning Bolt。"},
            {tag: "library-top", kind: "move_library_cards", source: "Alice put 3 card(s) from the top of their library into graveyard.",
             expected: "Alice 将自己牌库顶的 3 张牌置入墓地。"},
            {tag: "recall", kind: "recall_revealed", source: "Alice returned 2 revealed card(s) to hand.",
             expected: "Alice 将 2 张展示的牌移回手牌。"},
            {tag: "reorder", kind: "library_reorder", source: "Alice reordered the top 3 card(s) of their library.",
             expected: "Alice 重新排列了自己牌库顶的 3 张牌。"},
            {tag: "draw-game", kind: "draw", source: "Alice declared Game 2 a draw.",
             expected: "Alice 宣告第 2 局平局。"},
            {tag: "restart", kind: "restart", source: "Alice restarted Game 2.",
             expected: "Alice 重新开始了第 2 局。"},
            {tag: "roll", kind: "roll", source: "Alice %2 rolled [3, 6] on 2d6 (total 9).",
             expected: "Alice %2 掷出 2 个 6 面骰：[3, 6]（合计 9）。"},
            {tag: "next-game-roll", kind: "roll", source: "Alice won the roll for Game 2.",
             expected: "Alice 赢得了第 2 局的先手掷骰。"},
            {tag: "heads", kind: "coin", source: "Alice flipped heads.",
             expected: "Alice 掷硬币得到正面。"},
            {tag: "tails", kind: "coin", source: "Alice flipped tails.",
             expected: "Alice 掷硬币得到反面。"},
            {tag: "random-player", kind: "random_select", source: "Alice randomly selected Bob %2.",
             expected: "Alice 随机选中了 Bob %2。"},
            {tag: "random-hidden-card", kind: "random_select", source: "Alice randomly selected a face-down card.",
             expected: "Alice 随机选中了 一张牌面朝下的牌。"},
            {tag: "no-players", kind: "result", source: "The Commander game ended with no remaining players.",
             expected: "指挥官对局结束，没有剩余玩家。"},
            {tag: "attack-permanent", kind: "combat", source: "Alice declared 2 attacker(s) toward a battlefield permanent controlled by Bob.",
             expected: "Alice 宣告了 2 个攻击者，攻击 Bob 操控的战场永久物。"},
            {tag: "hidden-move", kind: "move_card", source: "Alice moved a face-down card from battlefield to exile.",
             expected: "Alice 将 一张牌面朝下的牌 从战场移至放逐区。"},
            {tag: "number-counter", kind: "card_counter", source: "Alice set number on a face-down card to 2.",
             expected: "Alice 将 一张牌面朝下的牌 上的 数量指示物 设为 2。"},
            {tag: "player-counter", kind: "counter", source: "Alice set counter-2 to 7 (+1).",
             expected: "Alice 将 计数器 2 设为 7（+1）。"},
            {tag: "rename-counter", kind: "counter", source: "Alice renamed counter counter-2 to Charge %2.",
             expected: "Alice 将 计数器 2 重命名为 Charge %2。"},
            {tag: "rename-custom-counter", kind: "counter", source: "Alice renamed counter Charge %2 to Goblin.",
             expected: "Alice 将 Charge %2 重命名为 Goblin。"}
        ]
    }

    function test_translatesManualLogActions(data) {
        compare(I18n.gameLog(data.kind, data.source), data.expected)
        compare(I18n.gameLog("chat", data.source), data.source)
        testTranslations.setLanguage("en")
        compare(I18n.gameLog(data.kind, data.source), data.source)
    }

    function test_localizesOnlyPublicCardNames_data() {
        return [
            {tag: "move", kind: "move_card", source: "Bolt %2 moved Bolt from hand to graveyard.",
             expected: "Bolt %2 将 闪电击 从手牌移至墓地。", names: ["Bolt"]},
            {tag: "token", kind: "create_token", source: "Bolt created a Goblin token.",
             expected: "Bolt 创建了衍生物：地精。", names: ["Goblin"]},
            {tag: "emblem", kind: "create_emblem", source: "Bolt created a Test Emblem emblem for Goblin.",
             expected: "Bolt 为 Goblin 创建了徽记：测试徽记。", names: ["Test Emblem"]},
            {tag: "remove-emblem", kind: "remove_emblem", source: "Bolt removed their Test Emblem emblem.",
             expected: "Bolt 移除了自己的徽记：测试徽记。", names: ["Test Emblem"]},
            {tag: "commander", kind: "commander_cast", source: "Goblin cast Bolt from the command zone; the next additional cost is +2.",
             expected: "Goblin 从指挥官区施放了 闪电击；下次额外费用为 +2。", names: ["Bolt"]},
            {tag: "land", kind: "land_play", source: "Bolt recorded Island as land play 1 this turn.",
             expected: "Bolt 将 海岛 记录为本回合第 1 次地牌使用。", names: ["Island"]},
            {tag: "hidden", kind: "move_card", source: "Bolt moved a face-down card from battlefield to exile.",
             expected: "Bolt 将 一张牌面朝下的牌 从战场移至放逐区。", names: []},
            {tag: "private", kind: "move_card", source: "Bolt moved a card from library to hand.",
             expected: "Bolt 将 一张牌 从牌库移至手牌。", names: []},
            {tag: "count", kind: "move_cards", source: "Bolt moved 2 card(s) from hand to graveyard.",
             expected: "Bolt 将 2 张牌 从手牌移至墓地。", names: []},
            {tag: "top-reveal", kind: "library_view", source: "Bolt revealed Goblin from the top 5 card(s) of their library and put them into hand.",
             expected: "Bolt 展示了自己的牌库顶 5 张牌中的 地精，并将这些牌置入手牌。", names: ["Goblin"]},
            {tag: "remote-top-reveal", kind: "library_view", source: "Bolt revealed Island from the top 5 card(s) of Goblin's library and put them into hand.",
             expected: "Bolt 展示了Goblin 的牌库顶 5 张牌中的 海岛，并将这些牌置入手牌。", names: ["Island"]},
            // Card names can contain commas; unresolved name lists stay canonical.
            {tag: "top-reveal-list", kind: "library_view", source: "Bolt revealed Goblin, Island from the top 5 card(s) of their library and put them into hand.",
             expected: "Bolt 展示了自己的牌库顶 5 张牌中的 Goblin, Island，并将这些牌置入手牌。", names: ["Goblin, Island"]},
            {tag: "top-reveal-tokens", kind: "library_view", source: "Bolt %2 revealed Unknown %5 from the top 5 card(s) of Goblin %3's library and put them into Bolt %4's hand.",
             expected: "Bolt %2 展示了Goblin %3 的牌库顶 5 张牌中的 Unknown %5，并将这些牌置入Bolt %4 的手牌。", names: ["Unknown %5"]},
            {tag: "top-hidden", kind: "library_view", source: "Bolt resolved the top 5 card(s) of their library and put 2 card(s) into hand.",
             expected: "Bolt 查看了自己的牌库顶的 5 张牌，并将 2 张牌置入手牌。", names: []},
            {tag: "combat", kind: "combat", source: "Bolt declared 2 attacker(s) toward Goblin.",
             expected: "Bolt 声明 2 个攻击者攻击 Goblin。", names: []},
            {tag: "custom-counter", kind: "counter", source: "Bolt set Goblin to 2 (+1).",
             expected: "Bolt 将 Goblin 设为 2（+1）。", names: []},
            {tag: "random-player", kind: "random_select", source: "Bolt randomly selected Goblin.",
             expected: "Bolt 随机选中了 Goblin。", names: []},
            {tag: "chat", kind: "chat", source: "Bolt moved Bolt from hand to graveyard.",
             expected: "Bolt moved Bolt from hand to graveyard.", names: []},
            {tag: "unknown", kind: "move_card", source: "Bolt moved Unknown %2 from hand to graveyard.",
             expected: "Bolt 将 Unknown %2 从手牌移至墓地。", names: ["Unknown %2"]},
            {tag: "rules", kind: "rules_card", source: "Bolt: %2: Bolt in battlefield.",
             actor: "Bolt: %2", expected: "Bolt: %2: 闪电击 位于战场。", names: ["Bolt"]},
            {tag: "rules-hidden", kind: "rules_card", source: "Bolt: %2: a face-down card in battlefield.",
             actor: "Bolt: %2", expected: "Bolt: %2: 一张牌面朝下的牌 位于战场。", names: []}
        ]
    }

    function test_localizesOnlyPublicCardNames(data) {
        const names = []
        const translations = {Bolt: "闪电击", Goblin: "地精", Island: "海岛", "Test Emblem": "测试徽记"}
        function resolve(name) {
            names.push(name)
            return translations[name] || name
        }
        compare(I18n.gameLog(data.kind, data.source, resolve, data.actor || ""), data.expected)
        compare(names, data.names)
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

    function test_translatesPrivateForgeStartDetailsWithoutLosingIdentities() {
        const failure = {reason:"deck_rejected", truncated:true, issues:[
            {deck:"player", section:"mainboard", code:"printing_unavailable",
                cardName:"Forest <literal> %2", setCode:"M21", collectorNumber:"999999"},
            {deck:"ai", section:"sideboard", code:"card_unavailable", cardName:"AI fixture"},
            {deck:"player", section:"commanders", code:"commander_missing", cardName:"Commander"},
            {deck:"player", section:"mainboard", code:"java_exception", cardName:"private trace"}]}
        const chinese = I18n.rulesStartFailureDetails(failure)
        verify(chinese.indexOf("Forest <literal> %2 (M21 999999)") >= 0)
        verify(chinese.indexOf("当前 Forge 运行包无法识别此牌或所选印刷。") >= 0)
        verify(chinese.indexOf("AI 牌组") >= 0)
        verify(chinese.indexOf("private trace") < 0)
        verify(chinese.indexOf("已省略部分详细信息。") >= 0)
        testTranslations.setLanguage("en")
        const english = I18n.rulesStartFailureDetails(failure)
        verify(english.indexOf("Your deck · Main deck: Forest <literal> %2 (M21 999999)") >= 0)
        verify(english.indexOf("AI deck · Sideboard: AI fixture") >= 0)
        verify(english.indexOf("usable main-deck cards") >= 0)
        verify(english.indexOf("private trace") < 0)
        const publicFailure = I18n.rulesStartFailureDetails({reason:"deck_rejected"})
        verify(publicFailure.indexOf("Forest") < 0 && publicFailure.indexOf("AI fixture") < 0)
    }

    function test_translatesForgeFailureReasons_data() {
        return [
            {tag:"capacity", reason:"capacity", phrase:"对局名额"},
            {tag:"unavailable", reason:"runtime_unavailable", phrase:"运行包不可用"},
            {tag:"timeout", reason:"runtime_timeout", phrase:"规定时间"},
            {tag:"failed", reason:"runtime_failed", phrase:"停止运行"},
            {tag:"unknown", reason:"start_rejected", phrase:"具体原因"}
        ]
    }

    function test_translatesForgeFailureReasons(data) {
        verify(I18n.rulesStartFailureReason(data.reason).indexOf(data.phrase) >= 0)
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
            I18n.gameLog("library_view",
                "Alice resolved the top 1 card(s) of their library and put 1 card(s) into hand."),
            "Alice 查看了自己的牌库顶的 1 张牌，并将 1 张牌置入手牌。")
        compare(
            I18n.gameLog("library_view",
                "Alice resolved the top 1 card(s) of Bob's library and put 1 card(s) into hand."),
            "Alice 查看了Bob 的牌库顶的 1 张牌，并将 1 张牌置入手牌。")
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

    function test_translatesTopLibraryRevealLogs_data() {
        return [
            {tag: "own-top-card", source: "Alice revealed Lightning Bolt from the top 1 card(s) of their library and put them into hand.",
             expected: "Alice 展示了自己的牌库顶 1 张牌中的 Lightning Bolt，并将这些牌置入手牌。"},
            {tag: "multiple-cards", source: "Alice revealed Lightning Bolt, Island from the top 5 card(s) of their library and put them into hand.",
             expected: "Alice 展示了自己的牌库顶 5 张牌中的 Lightning Bolt, Island，并将这些牌置入手牌。"},
            {tag: "remote-bottom", source: "Alice revealed Island from the top 3 card(s) of Bob's library and put them on bottom of their library.",
             expected: "Alice 展示了Bob 的牌库顶 3 张牌中的 Island，并将这些牌置于自己的牌库底。"},
            {tag: "face-down", source: "Alice revealed Island from the top 3 card(s) of their library and put them face down onto battlefield.",
             expected: "Alice 展示了自己的牌库顶 3 张牌中的 Island，并将这些牌牌面朝下置入战场。"}
        ]
    }

    function test_translatesTopLibraryRevealLogs(data) {
        compare(I18n.gameLog("library_view", data.source), data.expected)
        compare(I18n.gameLog("chat", data.source), data.source)
        testTranslations.setLanguage("en")
        compare(I18n.gameLog("library_view", data.source), data.source)
    }
}
