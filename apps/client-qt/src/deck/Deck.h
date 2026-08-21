// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#pragma once

#include <QJsonObject>
#include <QString>
#include <QStringList>
#include <QVector>

namespace hexproof::client {

struct DeckCard
{
    QString name;
    QString localizedName;
    QString setCode;
    QString collectorNumber;
    QString typeLine;
    QString imagePath;
    int count = 1;
};

struct DeckToken
{
    QString name;
    QString localizedName;
    QString setCode;
    QString collectorNumber;
    QString typeLine;
    QString power;
    QString toughness;
    QString oracleText;
};

struct Deck
{
    QString id;
    QString name;
    // Legacy wire/table behavior value: modern (generic 1v1), duel, or edh.
    QString format;
    // Actual deck-construction policy: custom, standard, pioneer, modern,
    // legacy, vintage, pauper, duel, or commander.
    QString deckFormat;
    QStringList commanders;
    QString createdAt;
    QString updatedAt;
    QVector<DeckCard> mainboard;
    QVector<DeckCard> sideboard;
    QVector<DeckToken> tokens;
};

QString normalizedCardName(const QString &name);
bool cardNamesMatch(const QString &left, const QString &right);
QString cardCategory(const QString &typeLine);
int cardCount(const QVector<DeckCard> &cards);

QJsonObject deckCardToJson(const DeckCard &card);
DeckCard deckCardFromJson(const QJsonObject &object);
QJsonObject deckTokenToJson(const DeckToken &token);
DeckToken deckTokenFromJson(const QJsonObject &object);
QJsonObject deckToJson(const Deck &deck);
Deck deckFromJson(const QJsonObject &object);

} // namespace hexproof::client
