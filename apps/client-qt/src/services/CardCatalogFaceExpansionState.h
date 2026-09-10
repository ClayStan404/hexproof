// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#pragma once

#include <QSet>
#include <QString>
#include <QVariantList>

namespace hexproof::client {

struct CardFaceExpansionState
{
    qint64 loadId = 0;
    quint64 generation = 0;
    quint64 serial = 0;
    QString language;
    QVariantList cards;
    QVariantList expanded;
    QSet<QString> requestKeys;
    qsizetype nextIndex = 0;
    bool scheduled = false;
};

struct LimitedArtFaceExpansionState
{
    quint64 serial = 0;
    QString productId;
    QString language;
    QVariantList cards;
    QVariantList expanded;
    qsizetype nextIndex = 0;
    bool scheduled = false;
};

} // namespace hexproof::client
