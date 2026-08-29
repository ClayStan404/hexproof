// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#pragma once

#include "Deck.h"

#include <QString>

namespace hexproof::client {

class DeckEditor
{
  public:
    static bool rename(Deck &deck, const QString &name);
    static bool changeFormat(Deck &deck, const QString &format, QString *error);
    static bool toggleCommander(Deck &deck, const QString &cardName, QString *error);
    static bool moveCard(Deck &deck, const QString &cardName, bool toSideboard);
    static bool changeCardCount(Deck &deck, const QString &cardName, bool sideboard, int delta,
                                QString *error);
    static bool addCard(Deck &deck, const QString &name, const QString &localizedName,
                        const QString &typeLine, const QString &setCode,
                        const QString &collectorNumber, bool sideboard, QString *error);
    static bool setCardPrinting(Deck &deck, const QString &cardName, bool sideboard,
                                const QString &localizedName, const QString &typeLine,
                                const QString &setCode, const QString &collectorNumber,
                                DeckCard *updatedCard);
    static bool applyCardMetadata(Deck &deck, const QString &requestedName,
                                  const QString &localizedName, const QString &typeLine,
                                  const QString &imagePath, const QString &setCode,
                                  const QString &collectorNumber);
    static bool addToken(Deck &deck, const DeckToken &token);
    static bool removeToken(Deck &deck, const QString &name, const QString &setCode,
                            const QString &collectorNumber);

    static int cardCopies(const Deck &deck, const QString &cardName);
    static bool canAddCard(const Deck &deck, const QString &cardName, const QString &typeLine);
    static bool isCommander(const Deck &deck, const QString &cardName);

  private:
    static void removeCommander(Deck &deck, const QString &cardName);
    static void touch(Deck &deck);
};

} // namespace hexproof::client
