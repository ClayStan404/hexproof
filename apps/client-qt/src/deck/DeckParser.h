// SPDX-License-Identifier: GPL-3.0-or-later
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

enum class DeckParseProfile
{
    Constructed,
    Cube,
};

// Parses common plain-text and Moxfield clipboard exports, and writes the
// same explicit Deck / Sideboard / Commander / Consider text for round-trip import while
// retaining set/collector hints for Hexproof's image resolver.
class DeckParser
{
  public:
    static DeckParseResult parse(const QString &text, bool blankSectionIsCommander = false,
                                 DeckParseProfile profile = DeckParseProfile::Constructed);
    static QString format(const Deck &deck);
};

} // namespace hexproof::client
