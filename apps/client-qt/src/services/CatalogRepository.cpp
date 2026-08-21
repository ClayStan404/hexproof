// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "CatalogRepository.h"

#include "CardCatalogCommon.h"
#include "CatalogStorage.h"

#include <QFileInfo>
#include <QReadLocker>
#include <QSqlDatabase>
#include <QSqlError>
#include <QSqlQuery>

#include <atomic>
#include <memory>
#include <utility>

namespace hexproof::client {

using namespace catalog_internal;

namespace {

QString makeConnectionName(const void *repository)
{
    static std::atomic<quint64> serial{1};
    return QStringLiteral("hexproof-repo-") + QString::number(serial.fetch_add(1)) +
           QLatin1Char('-') + QString::number(reinterpret_cast<quintptr>(repository));
}

} // namespace

CatalogRepository::CatalogRepository(QString databasePath)
    : m_databasePath(std::move(databasePath)),
      m_connectionName(makeConnectionName(this))
{
}

CatalogRepository::~CatalogRepository()
{
    close();
}

bool CatalogRepository::installed() const
{
    return QFileInfo(m_databasePath).isFile() && QFileInfo(m_databasePath).size() > 0;
}

bool CatalogRepository::ensureOpen(QString *error) const
{
    if (m_open)
        return true;
    if (!installed()) {
        if (error)
            *error = QStringLiteral("Could not open the local card catalog.");
        return false;
    }
    if (!m_databaseReadLock)
        m_databaseReadLock = std::make_unique<QReadLocker>(&catalogstorage::databaseLock());

    QSqlDatabase database = QSqlDatabase::addDatabase(QStringLiteral("QSQLITE"), m_connectionName);
    database.setDatabaseName(m_databasePath);
    if (!database.open()) {
        if (error)
            *error = database.lastError().text().isEmpty()
                         ? QStringLiteral("Could not open the local card catalog.")
                         : database.lastError().text();
        database = QSqlDatabase();
        QSqlDatabase::removeDatabase(m_connectionName);
        m_databaseReadLock.reset();
        return false;
    }
    QSqlQuery busyTimeout(database);
    busyTimeout.exec(QStringLiteral("PRAGMA busy_timeout=1000"));
    m_open = true;
    probeSchema();
    return true;
}

void CatalogRepository::probeSchema() const
{
    if (m_schema.probed || !m_open)
        return;
    const QSqlDatabase database = QSqlDatabase::database(m_connectionName);
    QSqlQuery schemaQuery(database);
    schemaQuery.prepare(QStringLiteral(
        "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'card_aliases'"));
    m_schema.hasAliases = schemaQuery.exec() && schemaQuery.next();
    schemaQuery.prepare(QStringLiteral(
        "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'localized_printings'"));
    m_schema.hasLocalizedPrintings = schemaQuery.exec() && schemaQuery.next();
    if (schemaQuery.exec(QStringLiteral("PRAGMA table_info(cards)"))) {
        while (schemaQuery.next())
            m_schema.cardColumns.insert(schemaQuery.value(1).toString());
    }
    if (m_schema.hasLocalizedPrintings &&
        schemaQuery.exec(QStringLiteral("PRAGMA table_info(localized_printings)"))) {
        while (schemaQuery.next())
            m_schema.localizedPrintingColumns.insert(schemaQuery.value(1).toString());
    }
    m_schema.probed = true;
}

void CatalogRepository::close() const
{
    if (!QSqlDatabase::contains(m_connectionName)) {
        m_open = false;
        return;
    }
    {
        QSqlDatabase database = QSqlDatabase::database(m_connectionName);
        if (database.isOpen())
            database.close();
    }
    QSqlDatabase::removeDatabase(m_connectionName);
    m_open = false;
    m_databaseReadLock.reset();
}

} // namespace hexproof::client
