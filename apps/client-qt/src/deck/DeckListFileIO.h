// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#pragma once

#include <QString>
#include <QUrl>

namespace hexproof::client {

struct DeckListFileData
{
    QString text;
    QString suggestedName;
    QString error;
};

DeckListFileData loadDeckListFile(const QUrl &fileUrl);

} // namespace hexproof::client
