// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#pragma once

#include "CatalogTypes.h"

#include <QJsonArray>
#include <QReadWriteLock>
#include <QSet>
#include <QString>
#include <QVariantList>

#include <memory>

namespace hexproof::client {

// CatalogRepository owns synchronous SQLite reads and localized-printing writes.
// CardCatalog remains responsible for QML state, async orchestration, network
// resolution, and image caches.
//
// One named connection is kept for the object's lifetime so GUI-thread lookups
// do not open and close SQLite on every QML binding. The file lock is taken
// only while that connection is open, so a repository that never touches the
// database cannot block install/recovery, and CardCatalog can drop the GUI
// connection when replacement starts.
class CatalogRepository
{
  public:
    explicit CatalogRepository(QString databasePath);
    CatalogRepository(const CatalogRepository &) = delete;
    CatalogRepository &operator=(const CatalogRepository &) = delete;
    ~CatalogRepository();

    bool installed() const;
    CatalogSearchResult search(const QString &text, const QString &language,
                               const QString &typeFilter, const QString &setFilter,
                               const QString &languageFilter, const QString &colorFilter,
                               const QString &rarityFilter, const QString &legalityFilter) const;
    CatalogSearchResult searchTokens(const QString &text, const QString &language) const;

    QVariantList printings(const QString &name, const QString &language,
                           QString *error = nullptr) const;
    QVariantList cardFaces(const QString &name, const QString &setCode,
                           const QString &collectorNumber, QString *error = nullptr) const;
    QVariantList limitedProducts(QString *error = nullptr) const;
    QVariantMap limitedProduct(const QString &productId, QString *error = nullptr) const;
    CardRecord lookup(const CatalogCardQuery &request) const;
    CardRecord lookupLocalizedPrinting(const CatalogCardQuery &request,
                                       const CardRecord &catalogIdentity, int indexVersion) const;
    bool cachedScryfallArtIsUsable(const CardRecord &record) const;
    // Inserts rows while the file lock is held for the open connection, which
    // is intentional: the lock arbitrates use of the database file against
    // replacement of it, not reader-versus-writer access to rows. SQLite
    // serializes concurrent writers itself, and opening the connection sets a
    // busy timeout for that. Promoting this to the write lock would block
    // unrelated searches without adding safety.
    CatalogPersistResult persistLocalizedPrintings(const QJsonArray &printings,
                                                   int indexVersion) const;

  private:
    struct SchemaInfo
    {
        bool probed = false;
        bool hasAliases = false;
        bool hasLocalizedPrintings = false;
        QSet<QString> cardColumns;
        QSet<QString> localizedPrintingColumns;
    };

    bool ensureOpen(QString *error = nullptr) const;
    void probeSchema() const;
    void close() const;

    QString m_databasePath;
    QString m_connectionName;
    mutable std::unique_ptr<QReadLocker> m_databaseReadLock;
    mutable bool m_open = false;
    mutable SchemaInfo m_schema;
};

} // namespace hexproof::client
