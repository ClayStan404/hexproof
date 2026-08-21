// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2009-2026 Cockatrice contributors
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#pragma once

#include "Deck.h"

#include <QStringList>

namespace hexproof::client {

struct DeckParseResult
{
    Deck deck;
    QString error;
    QStringList warnings;

    bool ok() const
    {
        return error.isEmpty();
    }
};

// Parses common plain-text and Moxfield clipboard exports, and writes the
// same explicit Deck / Sideboard / Commander text for round-trip import while
// retaining set/collector hints for Hexproof's image resolver.
class DeckParser
{
  public:
    static DeckParseResult parse(const QString &text, bool blankSectionIsCommander = false);
    static QString format(const Deck &deck);
};

} // namespace hexproof::client
