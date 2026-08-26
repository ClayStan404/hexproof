// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "ShortcutRegistry.h"

#include <QHash>

namespace hexproof::client {

const QVector<ShortcutDefinition> &shortcutDefinitions()
{
    static const QVector<ShortcutDefinition> definitions{
        {QStringLiteral("app.fullscreen"), {QStringLiteral("F11")}},
        {QStringLiteral("table.help"), {QStringLiteral("F1"), QStringLiteral("?")}},
        {QStringLiteral("table.advancePhase"), {QStringLiteral("Ctrl+Right")}},
        {QStringLiteral("table.advanceTurn"), {QStringLiteral("Ctrl+Return")}},
        {QStringLiteral("table.openSettings"), {QStringLiteral("Ctrl+,")}},
        {QStringLiteral("table.toggleGameLog"), {QStringLiteral("Ctrl+G")}},
        {QStringLiteral("table.toggleShared"), {QStringLiteral("Ctrl+Shift+V")}},
        {QStringLiteral("table.counter.rename"), {QStringLiteral("I")}},
        {QStringLiteral("table.counter.set"), {QStringLiteral("S")}},
        {QStringLiteral("table.counter.decrease"), {QStringLiteral("[")}},
        {QStringLiteral("table.counter.increase"), {QStringLiteral("]")}},
        {QStringLiteral("table.library.drawX"), {QStringLiteral("Ctrl+D")}},
        {QStringLiteral("table.library.drawOne"), {QStringLiteral("Ctrl+Alt+D")}},
        {QStringLiteral("table.library.search"), {QStringLiteral("Ctrl+F")}},
        {QStringLiteral("table.library.viewTopX"), {QStringLiteral("Ctrl+L")}},
        {QStringLiteral("table.library.viewTop"), {QStringLiteral("Ctrl+Shift+L")}},
        {QStringLiteral("table.sideboard.view"), {QStringLiteral("Ctrl+B")}},
        {QStringLiteral("table.library.millX"), {QStringLiteral("Ctrl+Shift+G")}},
        {QStringLiteral("table.library.exileX"), {QStringLiteral("Ctrl+Shift+E")}},
        {QStringLiteral("table.library.shuffle"), {QStringLiteral("Ctrl+Shift+S")}},
        {QStringLiteral("table.untapAll"), {QStringLiteral("Ctrl+U")}},
        {QStringLiteral("table.arrangeBattlefield"), {QStringLiteral("Ctrl+Shift+A")}},
        {QStringLiteral("table.createToken"), {QStringLiteral("Ctrl+T")}},
        {QStringLiteral("table.mulligan"), {QStringLiteral("Ctrl+M")}},
        {QStringLiteral("table.toggleHandReveal"), {QStringLiteral("Ctrl+H")}},
        {QStringLiteral("table.discardRandom"), {QStringLiteral("Ctrl+Alt+X")}},
        {QStringLiteral("table.discardAll"), {QStringLiteral("Ctrl+Shift+X")}},
        {QStringLiteral("table.rollDice"), {QStringLiteral("Ctrl+R")}},
        {QStringLiteral("table.flipCoin"), {QStringLiteral("Ctrl+Shift+C")}},
        {QStringLiteral("table.randomPlayer"), {QStringLiteral("Ctrl+Alt+P")}},
        {QStringLiteral("table.randomBattlefield"), {QStringLiteral("Ctrl+Alt+R")}},
        {QStringLiteral("table.declareDraw"), {QStringLiteral("Ctrl+Shift+D")}},
        {QStringLiteral("table.restartGame"), {QStringLiteral("Ctrl+Shift+R")}},
        {QStringLiteral("table.setLife"), {QStringLiteral("Ctrl+Shift+H")}},
        {QStringLiteral("table.life.decrease"), {QStringLiteral("Alt+-")}},
        {QStringLiteral("table.life.increase"), {QStringLiteral("Alt+=")}},
        {QStringLiteral("table.commanderDamage"), {QStringLiteral("Ctrl+K")}},
        {QStringLiteral("table.concede"), {QStringLiteral("Ctrl+Shift+Q")}},
        {QStringLiteral("table.leave"), {QStringLiteral("Ctrl+Shift+W")}},
        {QStringLiteral("table.returnToRoom"), {QStringLiteral("Ctrl+Backspace")}},
        {QStringLiteral("table.selection.playLand"), {QStringLiteral("P")}},
        {QStringLiteral("table.selection.battlefieldFaceUp"), {QStringLiteral("Alt+B")}},
        {QStringLiteral("table.selection.battlefieldFaceDown"), {QStringLiteral("Alt+Shift+B")}},
        {QStringLiteral("table.selection.moveHand"), {QStringLiteral("Alt+H")}},
        {QStringLiteral("table.selection.moveGraveyard"), {QStringLiteral("Alt+G")}},
        {QStringLiteral("table.selection.moveExile"), {QStringLiteral("Alt+E")}},
        {QStringLiteral("table.selection.moveLibraryTop"), {QStringLiteral("Alt+Up")}},
        {QStringLiteral("table.selection.moveLibraryBottom"), {QStringLiteral("Alt+Down")}},
        {QStringLiteral("table.selection.randomLibraryTop"), {QStringLiteral("Alt+Shift+Up")}},
        {QStringLiteral("table.selection.randomLibraryBottom"), {QStringLiteral("Alt+Shift+Down")}},
        {QStringLiteral("table.selection.toggleTap"), {QStringLiteral("T")}},
        {QStringLiteral("table.selection.toggleFaceDown"), {QStringLiteral("F")}},
        {QStringLiteral("table.selection.chooseFace"), {QStringLiteral("V")}},
        {QStringLiteral("table.selection.attach"), {QStringLiteral("A")}},
        {QStringLiteral("table.selection.detach"), {QStringLiteral("Shift+A")}},
        {QStringLiteral("table.selection.target"), {QStringLiteral("R")}},
        {QStringLiteral("table.selection.clearTarget"), {QStringLiteral("Shift+R")}},
        {QStringLiteral("table.selection.attack"), {QStringLiteral("X")}},
        {QStringLiteral("table.selection.block"), {QStringLiteral("Shift+X")}},
        {QStringLiteral("table.selection.clearCombat"), {QStringLiteral("Shift+C")}},
        {QStringLiteral("table.selection.addNumberCounter"), {QStringLiteral("N")}},
        {QStringLiteral("table.selection.numberCounterDecrease"), {QStringLiteral("-")}},
        {QStringLiteral("table.selection.numberCounterIncrease"), {QStringLiteral("=")}},
        {QStringLiteral("table.selection.addAbilityCounter"), {QStringLiteral("Shift+N")}},
        {QStringLiteral("table.selection.setNumberCounter"), {QStringLiteral("Ctrl+N")}},
        {QStringLiteral("table.selection.createTokenCopy"), {QStringLiteral("Alt+C")}},
        {QStringLiteral("replay.playPause"), {QStringLiteral("Space")}},
        {QStringLiteral("replay.previous"), {QStringLiteral("Left")}},
        {QStringLiteral("replay.next"), {QStringLiteral("Right")}},
        {QStringLiteral("replay.reset"), {QStringLiteral("Home")}},
        {QStringLiteral("replay.speedHalf"), {QStringLiteral("1")}},
        {QStringLiteral("replay.speedNormal"), {QStringLiteral("2")}},
        {QStringLiteral("replay.speedDouble"), {QStringLiteral("3")}},
        {QStringLiteral("replay.speedQuadruple"), {QStringLiteral("4")}},
    };
    return definitions;
}

QStringList defaultShortcutSequences(const QString &actionId)
{
    static const QHash<QString, QStringList> defaults = [] {
        QHash<QString, QStringList> result;
        for (const ShortcutDefinition &definition : shortcutDefinitions())
            result.insert(definition.id, definition.defaultSequences);
        return result;
    }();
    return defaults.value(actionId);
}

bool isKnownShortcutAction(const QString &actionId)
{
    return !defaultShortcutSequences(actionId).isEmpty();
}

} // namespace hexproof::client
