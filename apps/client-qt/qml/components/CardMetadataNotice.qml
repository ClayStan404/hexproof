// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

pragma Translator: "CardWorkbench"
import QtQuick

Text {
    textFormat: Text.PlainText
    property var cards: []
    visible: cards.some(card => !card.virtualBasic
        && (card.cardColors === undefined || card.manaCost === undefined))
    text: qsTranslate("CardWorkbench", "Update the local card database for card colors and full mana costs. Missing data is shown neutrally.")
    color: Theme.textMuted
    font.pixelSize: Theme.fontSize(10)
    wrapMode: Text.WordWrap
}
