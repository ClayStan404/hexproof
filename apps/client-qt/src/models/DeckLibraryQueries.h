// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#pragma once

#include "deck/Deck.h"

#include <QHash>
#include <QVariantList>
#include <QVariantMap>

namespace hexproof::client {

class DeckLibraryQueries
{
  public:
    static QString commanderDisplayName(const Deck &deck);
    static bool deckReady(const Deck &deck, const QVariantMap &validation = {});
    static bool deckSelectable(const Deck &deck, bool allowMissingArt,
                               const QVariantMap &validation = {});
    static QString deckStatus(const Deck &deck, const QVariantMap &validation = {});
    static int missingImageCount(const Deck &deck);
    static bool hasMissingArt(const QVector<Deck> &decks);
    static bool hasExactPrintings(const Deck &deck);
    static QVariantMap cubeProduct(const Deck &deck);

    static QVariantList cardVariants(const QVector<DeckCard> &cards, const Deck &deck,
                                     bool grouped);
    static QVariantList tokenVariants(const QVector<DeckToken> &tokens);
    static QVariantList matchingDecks(const QVector<Deck> &decks, const QString &format,
                                      bool allowMissingArt,
                                      const QHash<QString, QVariantMap> &validations = {});
    static QVariantMap matchPayload(const QVector<Deck> &decks, const QString &id,
                                    bool allowMissingArt,
                                    const QHash<QString, QVariantMap> &validations = {});
    static QVariantList cacheRequestsForDeck(const Deck &deck, bool includeCached = false);
    static QVariantList cacheRequestsForLibrary(const QVector<Deck> &decks,
                                                bool includeCached = false);
};

} // namespace hexproof::client
