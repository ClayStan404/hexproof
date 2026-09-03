// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#pragma once

#include "CardArtCache.h"

#include <QList>
#include <QString>
#include <QVariantList>
#include <QVariantMap>

namespace hexproof::client::cardart {

struct AuditResult
{
    bool ok = false;
    QString error;
    int printingCount = 0;
    int faceCount = 0;
    int missingFaceCount = 0;
    int repairableEntryCount = 0;
    QVariantList missingRequests;
    QList<CardArtCacheEntry> repairedEntries;

    bool repairNeeded() const
    {
        return missingFaceCount > 0 || repairableEntryCount > 0;
    }
    QVariantMap summary() const;
};

AuditResult auditDeckArt(const QString &databasePath, const QString &imageRoot,
                         const QString &language, bool reuseLocalArt, const QVariantList &cards,
                         const QList<CardArtCacheEntry> &entries);

} // namespace hexproof::client::cardart
