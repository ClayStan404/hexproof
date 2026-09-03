// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#pragma once

#include "CardArtCache.h"

#include <QList>
#include <QSet>
#include <QString>
#include <QVariantMap>

namespace hexproof::client::cardart {

struct OperationResult
{
    bool ok = false;
    QString error;
    int entryCount = 0;
    int imageCount = 0;
    int skippedCount = 0;
    qint64 bytes = 0;
    QList<CardArtCacheEntry> importedEntries;
};

QVariantMap inventory(const QString &imageRoot, const QList<CardArtCacheEntry> &entries);
QVariantMap inspectPack(const QString &path, const QList<CardArtCacheEntry> &existingEntries = {},
                        const QString &imageRoot = {});
OperationResult exportPack(const QString &path, const QString &imageRoot,
                           const QList<CardArtCacheEntry> &entries, bool selectionOnly,
                           const QString &setCode, const QString &imageLanguage);
OperationResult importPack(const QString &path, const QString &imageRoot);
OperationResult removeUnreferencedFiles(const QString &imageRoot,
                                        const QSet<QString> &referencedPaths,
                                        const QSet<QString> &candidatePaths, bool removeAllOrphans);

} // namespace hexproof::client::cardart
