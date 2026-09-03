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
