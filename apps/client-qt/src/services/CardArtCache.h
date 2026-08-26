// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#pragma once

#include "CatalogTypes.h"

#include <QDateTime>
#include <QHash>
#include <QSet>
#include <QString>

namespace hexproof::client {

class CardArtCache
{
  public:
    explicit CardArtCache(const QString &storageRoot);

    void load();
    bool save();
    bool dirty() const
    {
        return m_dirty;
    }

    bool reuseLocalArt() const
    {
        return m_reuseLocalArt;
    }
    void setReuseLocalArt(bool reuse)
    {
        m_reuseLocalArt = reuse;
    }

    QString key(const QString &name, const QString &language, const QString &setCode = {},
                const QString &collectorNumber = {}) const;
    CardRecord exactRecord(const QString &key) const;
    CardRecord resolvedPrinting(const CardRequest &request) const;
    CardRecord reusableArt(const CardRequest &request, const CardRecord &catalogIdentity) const;
    CardRecord substituteRecord(const CardRequest &request, const CardRecord &catalogIdentity,
                                const CardRecord &cachedArt) const;
    QString imagePath(const QString &name, const QString &imageUrl, const QString &language) const;

    void rememberSuccess(const QString &key, const CardRecord &record);
    void rememberFailure(const QString &key,
                         const QDateTime &timestamp = QDateTime::currentDateTimeUtc());
    bool forgetFailure(const QString &key);
    bool failedRecently(const QString &key, const QDateTime &now = QDateTime::currentDateTimeUtc(),
                        qint64 maximumAgeSeconds = 24 * 60 * 60) const;

  private:
    void rebuildIndexes();
    void addToIndexes(const QString &cacheKey, const CardRecord &record);
    void removeFromIndexes(const QString &cacheKey, const CardRecord &record);

    QString m_imageRoot;
    QString m_metadataPath;
    QHash<QString, CardRecord> m_positive;
    QHash<QString, QDateTime> m_negative;
    QHash<QString, QSet<QString>> m_printingIndex;
    QHash<QString, QSet<QString>> m_oracleIndex;
    QHash<QString, QSet<QString>> m_canonicalNameIndex;
    QHash<QString, QSet<QString>> m_requestedNameIndex;
    bool m_reuseLocalArt = true;
    bool m_dirty = false;
};

} // namespace hexproof::client
