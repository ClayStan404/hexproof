// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#pragma once

#include "CatalogTypes.h"

#include <QDateTime>
#include <QFutureWatcher>
#include <QHash>
#include <QList>
#include <QMutex>
#include <QSet>
#include <QString>
#include <QStringList>

#include <functional>
#include <memory>

namespace hexproof::client {

struct CardArtCacheEntry
{
    QString cacheKey;
    CardRecord record;
};

class CardArtCache
{
  public:
    explicit CardArtCache(const QString &storageRoot, const QString &imageRoot = {},
                          const QStringList &previousImageRoots = {}, bool writable = true);
    ~CardArtCache();

    void load();
    bool save();
    void saveAsync();
    void saveAsync(std::function<void(bool)> completion);
    std::function<void(bool)> onSaveFinished;
    bool dirty() const
    {
        return m_dirty;
    }
    bool writable() const
    {
        return m_writable;
    }
    void setWritable(bool writable)
    {
        m_writable = writable;
    }
    int faceAuditVersion() const
    {
        return m_faceAuditVersion;
    }
    bool faceRepairNeeded() const
    {
        return m_faceRepairNeeded;
    }
    void setFaceAuditState(int version, bool repairNeeded);

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
    bool matchesRequestedFace(const CardRequest &request, const CardRecord &record) const;
    CardRecord resolvedPrinting(const CardRequest &request) const;
    CardRecord resolvedPrintingMetadata(const CardRequest &request) const;
    CardRecord localizedMetadataForName(const CardRequest &request) const;
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

    QString imageRoot() const
    {
        return m_imageRoot;
    }
    QList<CardArtCacheEntry> entries() const;
    QSet<QString> referencedImagePaths() const;
    QList<CardArtCacheEntry> removeEntries(bool selectionOnly, const QString &setCode = {},
                                           const QString &imageLanguage = {});
    void replaceEntries(const QList<CardArtCacheEntry> &entries);

  private:
    struct SaveState
    {
        QMutex mutex;
        quint64 committedGeneration = 0;
    };
    struct Snapshot
    {
        QHash<QString, CardRecord> positive;
        QHash<QString, QDateTime> negative;
        int faceAuditVersion;
        bool faceRepairNeeded;
        quint64 generation;
    };
    struct SaveCompletion
    {
        quint64 generation;
        std::function<void(bool)> callback;
    };
    Snapshot snapshot() const;
    static bool writeSnapshot(const QString &path, const Snapshot &snapshot,
                              const std::shared_ptr<SaveState> &state);
    void markDirty();
    bool matchesResolvedPrintingRequest(const CardRequest &request, const CardRecord &record) const;
    void rebuildIndexes();
    void addToIndexes(const QString &cacheKey, const CardRecord &record);
    void removeFromIndexes(const QString &cacheKey, const CardRecord &record);

    QString m_imageRoot;
    QString m_metadataPath;
    QStringList m_previousImageRoots;
    QHash<QString, CardRecord> m_positive;
    QHash<QString, QDateTime> m_negative;
    QHash<QString, QSet<QString>> m_printingIndex;
    QHash<QString, QSet<QString>> m_metadataNameIndex;
    QHash<QString, QSet<QString>> m_oracleIndex;
    QHash<QString, QSet<QString>> m_canonicalNameIndex;
    QHash<QString, QSet<QString>> m_requestedNameIndex;
    bool m_reuseLocalArt = true;
    bool m_writable = true;
    int m_faceAuditVersion = 0;
    bool m_faceRepairNeeded = false;
    bool m_dirty = false;
    quint64 m_generation = 1;
    quint64 m_savingGeneration = 0;
    quint64 m_persistedGeneration = 0;
    bool m_saving = false;
    bool m_saveRequested = false;
    QList<SaveCompletion> m_saveCompletions;
    std::shared_ptr<SaveState> m_saveState = std::make_shared<SaveState>();
    QFutureWatcher<bool> m_saveWatcher;
};

} // namespace hexproof::client
