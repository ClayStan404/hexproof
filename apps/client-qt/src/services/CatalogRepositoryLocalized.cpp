// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "CardCatalogCommon.h"
#include "CatalogDatabaseImportInternal.h"
#include "CatalogRepository.h"

namespace hexproof::client {

using namespace catalog_internal;

CatalogPersistResult CatalogRepository::persistLocalizedPrintings(const QJsonArray &printings,
                                                                  int indexVersion) const
{
    CatalogPersistResult result;
    if (!installed() || indexVersion < kCatalogIndexVersion || printings.isEmpty())
        return result;
    if (!ensureOpen(&result.error))
        return result;

    QSqlDatabase database = QSqlDatabase::database(m_connectionName);
    if (!database.transaction()) {
        result.error = database.lastError().text();
        database = QSqlDatabase();
        close();
        return result;
    }
    {
        QSqlQuery insert(database);
        if (!insert.prepare(QStringLiteral(
                "INSERT OR REPLACE INTO localized_printings "
                "(id, face_name, oracle_id, name, localized_name, localized_type, "
                "set_code, collector_number, illustration_id, released_at, image_url, "
                "image_status, digital, face_order, layout) "
                "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)"))) {
            result.error = insert.lastError().text();
        } else {
            CatalogImportResult importResult;
            for (const QJsonValue &value : printings) {
                if (!insertLocalizedPrinting(insert, value.toObject(), &importResult)) {
                    result.error = importResult.error;
                    break;
                }
            }
        }

        QSqlQuery query(database);
        if (result.error.isEmpty() &&
            (!query.exec(QStringLiteral("SELECT COUNT(*) FROM localized_printings")) ||
             !query.next())) {
            result.error = query.lastError().text();
        } else if (result.error.isEmpty()) {
            result.localizedPrintingCount = query.value(0).toInt();
            query.prepare(QStringLiteral("INSERT OR REPLACE INTO metadata (key, value) "
                                         "VALUES ('localized_printing_count', ?)"));
            query.bindValue(0, result.localizedPrintingCount);
            if (!query.exec())
                result.error = query.lastError().text();
        }

        if (result.error.isEmpty()) {
            if (!database.commit())
                result.error = database.lastError().text();
        }
        if (!result.error.isEmpty())
            database.rollback();
    }
    if (!result.error.isEmpty()) {
        database = QSqlDatabase();
        close();
    }
    return result;
}

} // namespace hexproof::client
