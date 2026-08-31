// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2009-2026 Cockatrice contributors
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "DeckParser.h"

#include <QRegularExpression>
#include <QSet>

namespace hexproof::client {

namespace {

constexpr qsizetype kMaximumDeckImportBytes = 1024 * 1024;

struct DeckParseLimits
{
    int cards;
    qsizetype entries;
};

constexpr DeckParseLimits kConstructedLimits{1000, 500};
constexpr DeckParseLimits kCubeLimits{10'000, 5'000};

enum class Section
{
    Mainboard,
    Sideboard,
    Commander,
    Consider
};

DeckParseLimits limitsForProfile(DeckParseProfile profile)
{
    return profile == DeckParseProfile::Cube ? kCubeLimits : kConstructedLimits;
}

bool mergeCard(QVector<DeckCard> &cards, const DeckCard &incoming, const DeckParseLimits &limits)
{
    const QString key = normalizedCardName(incoming.name);
    for (DeckCard &card : cards) {
        if (normalizedCardName(card.name) == key &&
            card.setCode.compare(incoming.setCode, Qt::CaseInsensitive) == 0 &&
            card.collectorNumber == incoming.collectorNumber) {
            if (incoming.count > limits.cards - card.count)
                return false;
            card.count += incoming.count;
            return true;
        }
    }
    if (cards.size() >= limits.entries)
        return false;
    cards.append(incoming);
    return true;
}

bool containsDisallowedControl(const QString &text)
{
    for (const QChar character : text) {
        if (character.category() == QChar::Other_Control && character != QLatin1Char('\n') &&
            character != QLatin1Char('\r') && character != QLatin1Char('\t')) {
            return true;
        }
    }
    return false;
}

bool isHeading(const QString &line, const QStringList &names)
{
    QString heading = line.trimmed().toCaseFolded();
    while (heading.endsWith(QLatin1Char(':')))
        heading.chop(1);
    return names.contains(heading.trimmed());
}

QString formatCardLine(const DeckCard &card, bool commander)
{
    QString line = QStringLiteral("%1 %2").arg(card.count).arg(card.name);
    if (!card.setCode.isEmpty() && !card.collectorNumber.isEmpty())
        line += QStringLiteral(" (%1) %2").arg(card.setCode, card.collectorNumber);
    if (commander)
        line += QStringLiteral(" *CMDR*");
    return line;
}

bool isDesignatedCommander(const Deck &deck, const DeckCard &card)
{
    const QString key = normalizedCardName(card.name);
    for (const QString &name : deck.commanders) {
        if (normalizedCardName(name) == key)
            return true;
    }
    return false;
}

} // namespace

DeckParseResult DeckParser::parse(const QString &text, bool blankSectionIsCommander,
                                  DeckParseProfile profile)
{
    DeckParseResult result;
    const DeckParseLimits limits = limitsForProfile(profile);
    if (text.size() > kMaximumDeckImportBytes || text.toUtf8().size() > kMaximumDeckImportBytes) {
        result.error = QStringLiteral("Deck imports cannot exceed 1 MB.");
        return result;
    }
    if (text.trimmed().isEmpty()) {
        result.error = QStringLiteral("Paste a deck list before importing.");
        return result;
    }
    if (containsDisallowedControl(text)) {
        result.error = QStringLiteral("Deck imports cannot contain control characters.");
        return result;
    }

    static const QRegularExpression cardLine(
        QStringLiteral(R"(^\s*[\[(]?[xX]?(\d+)[xX*\])]*\s+(.+?)\s*$)"));
    static const QRegularExpression setSuffix(
        QStringLiteral(R"(^(.+?)\s+\(([A-Za-z0-9]{2,8})\)\s+([A-Za-z0-9-]+)[★☆]?\s*$)"));
    static const QRegularExpression exportMarker(
        QStringLiteral(R"((?:^|\s)\*(CMDR|F|E)\*(?=\s|$))"),
        QRegularExpression::CaseInsensitiveOption);
    static const QRegularExpression splitCardSeparator(QStringLiteral(R"(\s+/\s+)"));
    static const QRegularExpression sideboardPrefix(QStringLiteral(R"(^\s*SB:\s*(.+)$)"),
                                                    QRegularExpression::CaseInsensitiveOption);

    Section section = Section::Mainboard;
    bool sawCard = false;
    bool sawSectionHeading = false;
    bool pendingPlainSideboard = false;
    const QStringList lines = text.split(QLatin1Char('\n'));
    for (int lineNumber = 0; lineNumber < lines.size(); ++lineNumber) {
        QString line = lines.at(lineNumber).trimmed();
        if (line.isEmpty()) {
            if (!sawSectionHeading && section == Section::Mainboard &&
                !result.deck.mainboard.isEmpty()) {
                pendingPlainSideboard = true;
            }
            continue;
        }
        if (line.startsWith(QStringLiteral("//")) || line.startsWith(QLatin1Char('#')))
            continue;

        if (isHeading(line, {QStringLiteral("deck"), QStringLiteral("decklist"),
                             QStringLiteral("mainboard"), QStringLiteral("main deck")})) {
            sawSectionHeading = true;
            pendingPlainSideboard = false;
            section = Section::Mainboard;
            continue;
        }
        if (isHeading(line, {QStringLiteral("sideboard"), QStringLiteral("side board")})) {
            sawSectionHeading = true;
            pendingPlainSideboard = false;
            section = Section::Sideboard;
            continue;
        }
        if (isHeading(line, {QStringLiteral("commander"), QStringLiteral("commanders")})) {
            sawSectionHeading = true;
            pendingPlainSideboard = false;
            section = Section::Commander;
            continue;
        }
        if (isHeading(line, {QStringLiteral("consider"), QStringLiteral("maybeboard"),
                             QStringLiteral("maybe board"), QStringLiteral("considering")})) {
            sawSectionHeading = true;
            pendingPlainSideboard = false;
            section = Section::Consider;
            continue;
        }

        bool prefixedSideboard = false;
        const QRegularExpressionMatch sideboardMatch = sideboardPrefix.match(line);
        if (sideboardMatch.hasMatch()) {
            prefixedSideboard = true;
            line = sideboardMatch.captured(1).trimmed();
        }

        bool markedCommander = false;
        QRegularExpressionMatchIterator markerMatches = exportMarker.globalMatch(line);
        while (markerMatches.hasNext()) {
            if (markerMatches.next().captured(1).compare(QStringLiteral("CMDR"),
                                                         Qt::CaseInsensitive) == 0) {
                markedCommander = true;
            }
        }
        line.remove(exportMarker);

        const QRegularExpressionMatch cardMatch = cardLine.match(line);
        if (!cardMatch.hasMatch()) {
            result.warnings.append(QStringLiteral("Line %1 was ignored: %2")
                                       .arg(lineNumber + 1)
                                       .arg(lines.at(lineNumber).trimmed()));
            continue;
        }

        DeckCard card;
        bool countOk = false;
        const qlonglong parsedCount = cardMatch.captured(1).toLongLong(&countOk);
        if (!countOk || parsedCount <= 0 || parsedCount > limits.cards) {
            result.error = QStringLiteral("Line %1 has an invalid card count.").arg(lineNumber + 1);
            return result;
        }
        card.count = static_cast<int>(parsedCount);
        QString cardName = cardMatch.captured(2).trimmed();
        const QRegularExpressionMatch setMatch = setSuffix.match(cardName);
        if (setMatch.hasMatch()) {
            cardName = setMatch.captured(1).trimmed();
            card.setCode = setMatch.captured(2).toUpper();
            card.collectorNumber = setMatch.captured(3);
        }
        cardName.replace(splitCardSeparator, QStringLiteral(" // "));
        card.name = cardName.simplified();

        if (card.count <= 0 || card.name.isEmpty()) {
            result.warnings.append(
                QStringLiteral("Line %1 did not contain a usable card.").arg(lineNumber + 1));
            continue;
        }
        if (pendingPlainSideboard) {
            section = blankSectionIsCommander ? Section::Commander : Section::Sideboard;
            pendingPlainSideboard = false;
        }
        const bool commander = markedCommander || section == Section::Commander;
        if (commander && !result.deck.commanders.contains(card.name, Qt::CaseInsensitive)) {
            result.deck.commanders.append(card.name);
        }

        bool merged = false;
        if (section == Section::Consider) {
            merged = mergeCard(result.deck.consider, card, limits);
        } else if (prefixedSideboard || section == Section::Sideboard) {
            merged = mergeCard(result.deck.sideboard, card, limits);
        } else {
            merged = mergeCard(result.deck.mainboard, card, limits);
        }
        if (!merged) {
            result.error =
                QStringLiteral("Deck imports can contain at most %1 cards and %2 entries.")
                    .arg(limits.cards)
                    .arg(limits.entries);
            return result;
        }
        sawCard = true;
    }

    if (result.deck.mainboard.size() + result.deck.sideboard.size() + result.deck.consider.size() >
        limits.entries) {
        result.error = QStringLiteral("Deck imports can contain at most %1 cards and %2 entries.")
                           .arg(limits.cards)
                           .arg(limits.entries);
        return result;
    }

    qint64 totalCards = 0;
    for (const auto &cards : {result.deck.mainboard, result.deck.sideboard, result.deck.consider}) {
        for (const DeckCard &card : cards) {
            if (card.count > limits.cards - totalCards) {
                result.error =
                    QStringLiteral("Deck imports can contain at most %1 cards.").arg(limits.cards);
                return result;
            }
            totalCards += card.count;
        }
    }

    if (!sawCard) {
        result.error =
            QStringLiteral("No card lines were recognized. Use lines such as '4 Lightning Bolt'.");
        return result;
    }
    if (result.deck.commanders.size() > 2) {
        result.error = QStringLiteral("A Commander deck can designate at most two commanders.");
    }
    return result;
}

QString DeckParser::format(const Deck &deck)
{
    QStringList lines{QStringLiteral("Deck")};
    for (const DeckCard &card : deck.mainboard) {
        if (!isDesignatedCommander(deck, card))
            lines.append(formatCardLine(card, false));
    }
    lines.append(QString());
    lines.append(QStringLiteral("Sideboard"));
    for (const DeckCard &card : deck.sideboard)
        lines.append(formatCardLine(card, false));
    lines.append(QString());
    lines.append(QStringLiteral("Commander"));
    QSet<QString> exportedCommanders;
    for (const QString &commanderName : deck.commanders) {
        const QString key = normalizedCardName(commanderName);
        if (exportedCommanders.contains(key))
            continue;
        exportedCommanders.insert(key);
        bool found = false;
        for (const DeckCard &card : deck.mainboard) {
            if (normalizedCardName(card.name) != key)
                continue;
            lines.append(formatCardLine(card, true));
            found = true;
        }
        if (!found && !commanderName.trimmed().isEmpty()) {
            DeckCard fallback;
            fallback.name = commanderName;
            fallback.count = 1;
            lines.append(formatCardLine(fallback, true));
        }
    }
    if (!deck.consider.isEmpty()) {
        lines.append(QString());
        lines.append(QStringLiteral("Consider"));
        for (const DeckCard &card : deck.consider)
            lines.append(formatCardLine(card, false));
    }
    return lines.join(QLatin1Char('\n')) + QLatin1Char('\n');
}

} // namespace hexproof::client
