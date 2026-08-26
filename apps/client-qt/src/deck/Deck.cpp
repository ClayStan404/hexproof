// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "Deck.h"

#include "DeckFormat.h"

#include <QJsonArray>

#include <algorithm>
#include <initializer_list>
#include <utility>

namespace hexproof::client {

QString normalizedCardName(const QString &name)
{
    return name.simplified().toCaseFolded();
}

bool cardNamesMatch(const QString &left, const QString &right)
{
    const QString a = normalizedCardName(left);
    const QString b = normalizedCardName(right);
    if (a.isEmpty() || b.isEmpty())
        return false;
    if (a == b)
        return true;
    const QString separator = QStringLiteral(" // ");
    const QStringList leftFaces = a.split(separator, Qt::SkipEmptyParts);
    const QStringList rightFaces = b.split(separator, Qt::SkipEmptyParts);
    for (const QString &leftFace : leftFaces) {
        for (const QString &rightFace : rightFaces) {
            if (leftFace == rightFace)
                return true;
        }
    }
    return false;
}

QString cardCategory(const QString &typeLine)
{
    QString type = typeLine.toCaseFolded();
    const qsizetype faceSeparator = type.indexOf(QStringLiteral(" // "));
    if (faceSeparator >= 0)
        type.truncate(faceSeparator);
    qsizetype subtypeSeparator = type.indexOf(QChar(0x2014));
    if (subtypeSeparator < 0)
        subtypeSeparator = type.indexOf(QChar(0x2013));
    if (subtypeSeparator < 0)
        subtypeSeparator = type.indexOf(QChar(0xFF5E));
    if (subtypeSeparator < 0)
        subtypeSeparator = type.indexOf(QChar(0x301C));
    if (subtypeSeparator >= 0)
        type.truncate(subtypeSeparator);
    const auto containsAny = [&type](std::initializer_list<QStringView> terms) {
        for (const QStringView term : terms) {
            if (type.contains(term))
                return true;
        }
        return false;
    };
    if (containsAny({u"land", u"地"}))
        return QStringLiteral("Lands");
    if (containsAny({u"creature", u"生物"}))
        return QStringLiteral("Creatures");
    if (containsAny({u"planeswalker", u"鹏洛客", u"旅法师"}))
        return QStringLiteral("Planeswalkers");
    if (containsAny({u"artifact", u"神器"}))
        return QStringLiteral("Artifacts");
    if (containsAny({u"enchantment", u"结界"}))
        return QStringLiteral("Enchantments");
    if (containsAny({u"instant", u"sorcery", u"瞬间", u"法术"}))
        return QStringLiteral("Spells");
    return QStringLiteral("Other");
}

int cardCount(const QVector<DeckCard> &cards)
{
    int total = 0;
    for (const DeckCard &card : cards)
        total += card.count;
    return total;
}

void mergeSideboardIntoMain(Deck &deck)
{
    for (const DeckCard &sideboardCard : std::as_const(deck.sideboard)) {
        const QString key = normalizedCardName(sideboardCard.name);
        const auto mainboardCard = std::find_if(
            deck.mainboard.begin(), deck.mainboard.end(),
            [&key, &sideboardCard](const DeckCard &card) {
                return normalizedCardName(card.name) == key &&
                       card.setCode.compare(sideboardCard.setCode, Qt::CaseInsensitive) == 0 &&
                       card.collectorNumber == sideboardCard.collectorNumber;
            });
        if (mainboardCard == deck.mainboard.end())
            deck.mainboard.append(sideboardCard);
        else
            mainboardCard->count += sideboardCard.count;
    }
    deck.sideboard.clear();
}

QJsonObject deckCardToJson(const DeckCard &card)
{
    QJsonObject object{
        {QStringLiteral("name"), card.name},
        {QStringLiteral("count"), card.count},
    };
    if (!card.localizedName.isEmpty())
        object.insert(QStringLiteral("localizedName"), card.localizedName);
    if (!card.setCode.isEmpty())
        object.insert(QStringLiteral("setCode"), card.setCode);
    if (!card.collectorNumber.isEmpty())
        object.insert(QStringLiteral("collectorNumber"), card.collectorNumber);
    if (!card.typeLine.isEmpty())
        object.insert(QStringLiteral("typeLine"), card.typeLine);
    if (!card.imagePath.isEmpty())
        object.insert(QStringLiteral("imagePath"), card.imagePath);
    return object;
}

DeckCard deckCardFromJson(const QJsonObject &object)
{
    DeckCard card;
    card.name = object.value(QStringLiteral("name")).toString().simplified();
    card.localizedName = object.value(QStringLiteral("localizedName")).toString().simplified();
    card.setCode = object.value(QStringLiteral("setCode")).toString().toUpper();
    card.collectorNumber = object.value(QStringLiteral("collectorNumber")).toString();
    card.typeLine = object.value(QStringLiteral("typeLine")).toString();
    card.imagePath = object.value(QStringLiteral("imagePath")).toString();
    card.count = qMax(1, object.value(QStringLiteral("count")).toInt(1));
    return card;
}

QJsonObject deckTokenToJson(const DeckToken &token)
{
    QJsonObject object{
        {QStringLiteral("name"), token.name},
        {QStringLiteral("setCode"), token.setCode},
        {QStringLiteral("collectorNumber"), token.collectorNumber},
    };
    if (!token.localizedName.isEmpty())
        object.insert(QStringLiteral("localizedName"), token.localizedName);
    if (!token.typeLine.isEmpty())
        object.insert(QStringLiteral("typeLine"), token.typeLine);
    if (!token.power.isEmpty())
        object.insert(QStringLiteral("power"), token.power);
    if (!token.toughness.isEmpty())
        object.insert(QStringLiteral("toughness"), token.toughness);
    if (!token.oracleText.isEmpty())
        object.insert(QStringLiteral("oracleText"), token.oracleText);
    return object;
}

DeckToken deckTokenFromJson(const QJsonObject &object)
{
    DeckToken token;
    token.name = object.value(QStringLiteral("name")).toString().simplified();
    token.localizedName = object.value(QStringLiteral("localizedName")).toString().simplified();
    token.setCode = object.value(QStringLiteral("setCode")).toString().toUpper();
    token.collectorNumber = object.value(QStringLiteral("collectorNumber")).toString();
    token.typeLine = object.value(QStringLiteral("typeLine")).toString();
    token.power = object.value(QStringLiteral("power")).toString();
    token.toughness = object.value(QStringLiteral("toughness")).toString();
    token.oracleText = object.value(QStringLiteral("oracleText")).toString();
    return token;
}

QJsonObject deckToJson(const Deck &deck)
{
    QJsonArray mainboard;
    for (const DeckCard &card : deck.mainboard)
        mainboard.append(deckCardToJson(card));

    QJsonArray sideboard;
    for (const DeckCard &card : deck.sideboard)
        sideboard.append(deckCardToJson(card));

    QJsonObject object{
        {QStringLiteral("id"), deck.id},
        {QStringLiteral("name"), deck.name},
        {QStringLiteral("format"), deck.format},
        {QStringLiteral("deckFormat"), deck.deckFormat},
        {QStringLiteral("createdAt"), deck.createdAt},
        {QStringLiteral("updatedAt"), deck.updatedAt},
        {QStringLiteral("mainboard"), mainboard},
        {QStringLiteral("sideboard"), sideboard},
    };
    if (!deck.commanders.isEmpty()) {
        QJsonArray commanders;
        for (const QString &commander : deck.commanders)
            commanders.append(commander);
        object.insert(QStringLiteral("commanders"), commanders);
    }
    if (!deck.tokens.isEmpty()) {
        QJsonArray tokens;
        for (const DeckToken &token : deck.tokens)
            tokens.append(deckTokenToJson(token));
        object.insert(QStringLiteral("tokens"), tokens);
    }
    return object;
}

Deck deckFromJson(const QJsonObject &object)
{
    Deck deck;
    deck.id = object.value(QStringLiteral("id")).toString();
    deck.name = object.value(QStringLiteral("name")).toString().simplified();
    deck.format = object.value(QStringLiteral("format")).toString().toLower();
    deck.deckFormat = normalizedDeckFormat(object.value(QStringLiteral("deckFormat")).toString());
    if (deck.deckFormat.isEmpty())
        deck.deckFormat = defaultDeckFormatForTableMode(deck.format);
    const QJsonArray commanders = object.value(QStringLiteral("commanders")).toArray();
    for (const QJsonValue &value : commanders) {
        const QString commander = value.toString().simplified();
        if (!commander.isEmpty() && !deck.commanders.contains(commander, Qt::CaseInsensitive))
            deck.commanders.append(commander);
    }
    if (deck.commanders.isEmpty()) {
        const QString legacyCommander =
            object.value(QStringLiteral("commander")).toString().simplified();
        if (!legacyCommander.isEmpty())
            deck.commanders.append(legacyCommander);
    }
    deck.createdAt = object.value(QStringLiteral("createdAt")).toString();
    deck.updatedAt = object.value(QStringLiteral("updatedAt")).toString();

    const QJsonArray mainboard = object.value(QStringLiteral("mainboard")).toArray();
    for (const QJsonValue &value : mainboard) {
        const DeckCard card = deckCardFromJson(value.toObject());
        if (!card.name.isEmpty())
            deck.mainboard.append(card);
    }

    const QJsonArray sideboard = object.value(QStringLiteral("sideboard")).toArray();
    for (const QJsonValue &value : sideboard) {
        const DeckCard card = deckCardFromJson(value.toObject());
        if (!card.name.isEmpty())
            deck.sideboard.append(card);
    }

    const QJsonArray tokens = object.value(QStringLiteral("tokens")).toArray();
    for (const QJsonValue &value : tokens) {
        const DeckToken token = deckTokenFromJson(value.toObject());
        if (!token.name.isEmpty() && !token.setCode.isEmpty() && !token.collectorNumber.isEmpty()) {
            deck.tokens.append(token);
        }
    }
    return deck;
}

} // namespace hexproof::client
