// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "CardImageProvider.h"
#include "CatalogDatabaseImportInternal.h"
#include "CatalogImport.h"
#include "CatalogStorage.h"
#include <QFuture>
#include <QtConcurrent>

namespace hexproof::client::catalogimport {
using namespace hexproof::client::catalog_internal;
using ImportResult = CatalogImportResult;

CatalogImportResult importBulkFile(const QString &jsonPath, const QString &databasePath,
                                   const QString &packageType, const QString &chineseArchivePath,
                                   const QString &localizedPrintingsPath,
                                   CatalogImportStopToken stopToken)
{
    ImportResult result;
    result.packageType = packageType;
    result.generatedAt = QDateTime::currentDateTimeUtc().toString(Qt::ISODate);
    result.schemaVersion = kCatalogIndexVersion;
    if (cancelCatalogImportIfRequested(stopToken, &result))
        return result;
    if (packageType != QStringLiteral("default_cards")) {
        result.error = QStringLiteral("Hexproof now uses the Default Cards package only.");
        return result;
    }
    QFile input(jsonPath);
    if (!input.open(QIODevice::ReadOnly)) {
        result.error = QStringLiteral("Could not open the downloaded catalog.");
        return result;
    }

    const QString newPath = databasePath + QStringLiteral(".new");
    if (!catalogstorage::recoverDatabase(databasePath, &result.error))
        return result;
    const QString connectionName = sqlConnectionName(QStringLiteral("hexproof-import-"));
    {
        QSqlDatabase database =
            QSqlDatabase::addDatabase(QStringLiteral("QSQLITE"), connectionName);
        database.setDatabaseName(newPath);
        if (!database.open()) {
            result.error = database.lastError().text();
        } else {
            QSqlQuery query(database);
            query.exec(QStringLiteral("PRAGMA journal_mode=OFF"));
            query.exec(QStringLiteral("PRAGMA synchronous=OFF"));
            if (!query.exec(QStringLiteral(
                    "CREATE TABLE cards (id TEXT PRIMARY KEY, oracle_id TEXT, name TEXT NOT NULL, "
                    "printed_name TEXT, type_line TEXT, set_code TEXT, collector_number TEXT, "
                    "image_url TEXT, image_status TEXT NOT NULL DEFAULT '', lang TEXT, colors "
                    "TEXT, mana_value REAL, rarity TEXT, layout TEXT, "
                    "legal_formats TEXT NOT NULL DEFAULT '', illustration_id TEXT, "
                    "released_at TEXT, digital INTEGER NOT NULL DEFAULT 0, power TEXT, "
                    "toughness TEXT, oracle_text TEXT, "
                    "legality_statuses TEXT NOT NULL DEFAULT '')"))) {
                result.error = query.lastError().text();
            } else if (!query.exec(
                           QStringLiteral("CREATE TABLE card_aliases (oracle_id TEXT NOT NULL, "
                                          "face_name TEXT NOT NULL, "
                                          "localized_name TEXT NOT NULL, localized_type TEXT, "
                                          "preferred INTEGER NOT NULL, "
                                          "face_order INTEGER NOT NULL, "
                                          "PRIMARY KEY (oracle_id, face_name, localized_name))"))) {
                result.error = query.lastError().text();
            } else if (!query.exec(QStringLiteral(
                           "CREATE TABLE localized_printings ("
                           "id TEXT NOT NULL, face_name TEXT NOT NULL DEFAULT '', "
                           "oracle_id TEXT NOT NULL, name TEXT NOT NULL, localized_name TEXT, "
                           "localized_type TEXT, set_code TEXT, collector_number TEXT, "
                           "illustration_id TEXT, released_at TEXT, image_url TEXT NOT NULL, "
                           "image_status TEXT NOT NULL DEFAULT '', "
                           "digital INTEGER NOT NULL DEFAULT 0, "
                           "face_order INTEGER NOT NULL DEFAULT 0, "
                           "layout TEXT NOT NULL DEFAULT '', "
                           "PRIMARY KEY (id, face_name))"))) {
                result.error = query.lastError().text();
            } else if (!query.exec(QStringLiteral(
                           "CREATE TABLE metadata (key TEXT PRIMARY KEY, value TEXT)"))) {
                result.error = query.lastError().text();
            } else {
                bool failed = !database.transaction();
                if (failed)
                    result.error = database.lastError().text();
                QSqlQuery insert(database);
                if (!insert.prepare(
                        QStringLiteral("INSERT OR REPLACE INTO cards "
                                       "(id, oracle_id, name, printed_name, type_line, set_code, "
                                       "collector_number, "
                                       "image_url, image_status, lang, colors, mana_value, rarity, "
                                       "layout, "
                                       "legal_formats, illustration_id, released_at, digital, "
                                       "power, toughness, oracle_text, legality_statuses) "
                                       "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, "
                                       "?, ?, ?, ?, ?, ?)"))) {
                    failed = true;
                    result.error = insert.lastError().text();
                }
                QSqlQuery localizedInsert(database);
                if (!failed &&
                    !localizedInsert.prepare(QStringLiteral(
                        "INSERT OR REPLACE INTO localized_printings "
                        "(id, face_name, oracle_id, name, localized_name, localized_type, "
                        "set_code, collector_number, illustration_id, released_at, image_url, "
                        "image_status, digital, face_order, layout) "
                        "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)"))) {
                    failed = true;
                    result.error = localizedInsert.lastError().text();
                }

                if (!failed) {
                    const QByteArray signature = input.peek(2);
                    if (signature.size() == 2 &&
                        static_cast<unsigned char>(signature.at(0)) == 0x1f &&
                        static_cast<unsigned char>(signature.at(1)) == 0x8b) {
                        input.close();
                        failed = !importBulkJsonLinesGzip(jsonPath, insert, &localizedInsert,
                                                          &result, false, stopToken);
                    } else {
                        failed = !importBulkJsonArray(input, insert, &localizedInsert, &result,
                                                      false, stopToken);
                    }
                }

                if (!failed && !localizedPrintingsPath.isEmpty()) {
                    QFile localizedInput(localizedPrintingsPath);
                    if (!localizedInput.open(QIODevice::ReadOnly)) {
                        failed = true;
                        result.error =
                            QStringLiteral("Could not open the localized printing catalog.");
                    } else {
                        const QByteArray signature = localizedInput.peek(2);
                        if (signature.size() == 2 &&
                            static_cast<unsigned char>(signature.at(0)) == 0x1f &&
                            static_cast<unsigned char>(signature.at(1)) == 0x8b) {
                            localizedInput.close();
                            failed = !importBulkJsonLinesGzip(localizedPrintingsPath, insert,
                                                              &localizedInsert, &result, true,
                                                              stopToken);
                        } else {
                            failed = !importBulkJsonArray(localizedInput, insert, &localizedInsert,
                                                          &result, true, stopToken);
                        }
                    }
                }

                if (!failed && result.cardCount > 0) {
                    failed = cancelCatalogImportIfRequested(stopToken, &result);
                    if (!failed && !database.commit()) {
                        failed = true;
                        result.error = database.lastError().text();
                    }
                    const QString aliasesPath = newPath + QStringLiteral(".aliases");
                    if (!failed && !chineseArchivePath.isEmpty()) {
                        QFile::remove(aliasesPath);
                        if (!extractChineseNameFile(chineseArchivePath, aliasesPath, &result.error,
                                                    stopToken, &result) ||
                            !importChineseAliases(database, aliasesPath, &result, stopToken)) {
                            failed = true;
                        }
                        QFile::remove(aliasesPath);
                    }
                    const QStringList indexStatements{
                        QStringLiteral("CREATE INDEX cards_name_idx ON cards(name COLLATE NOCASE)"),
                        QStringLiteral("CREATE INDEX cards_printed_name_idx "
                                       "ON cards(printed_name COLLATE NOCASE)"),
                        QStringLiteral("CREATE INDEX cards_printing_idx ON "
                                       "cards(set_code COLLATE NOCASE, "
                                       "collector_number COLLATE NOCASE)"),
                        QStringLiteral("CREATE INDEX cards_oracle_id_idx ON cards(oracle_id)"),
                        QStringLiteral("CREATE INDEX cards_token_identity_idx ON "
                                       "cards(layout, lang, oracle_id)"),
                        QStringLiteral("CREATE INDEX cards_token_printing_idx ON "
                                       "cards(layout, lang, set_code COLLATE NOCASE, "
                                       "collector_number COLLATE NOCASE)"),
                        QStringLiteral("CREATE INDEX localized_printings_oracle_idx ON "
                                       "localized_printings(oracle_id, illustration_id, digital, "
                                       "released_at DESC)"),
                        QStringLiteral("CREATE INDEX localized_printings_name_idx ON "
                                       "localized_printings(name COLLATE NOCASE, face_name COLLATE "
                                       "NOCASE)"),
                        QStringLiteral("CREATE INDEX card_aliases_name_idx "
                                       "ON card_aliases(localized_name COLLATE NOCASE)"),
                        QStringLiteral("CREATE INDEX card_aliases_oracle_idx "
                                       "ON card_aliases(oracle_id, preferred, face_order)"),
                    };
                    for (const QString &statement : indexStatements) {
                        if (failed || cancelCatalogImportIfRequested(stopToken, &result)) {
                            failed = true;
                            break;
                        }
                        if (!query.exec(statement)) {
                            failed = true;
                            result.error = query.lastError().text();
                            break;
                        }
                    }
                    if (!failed &&
                        query.exec(QStringLiteral("SELECT COUNT(*) FROM localized_printings")) &&
                        query.next()) {
                        result.localizedPrintingCount = query.value(0).toInt();
                    } else if (!failed) {
                        failed = true;
                        result.error = query.lastError().text();
                    }
                    if (!failed) {
                        query.prepare(QStringLiteral(
                            "INSERT INTO metadata (key, value) VALUES ('package', ?)"));
                        query.bindValue(0, packageType);
                        if (!query.exec()) {
                            failed = true;
                            result.error = query.lastError().text();
                        }
                    }
                    if (!failed) {
                        query.prepare(QStringLiteral(
                            "INSERT INTO metadata (key, value) VALUES ('count', ?)"));
                        query.bindValue(0, result.cardCount);
                        if (!query.exec()) {
                            failed = true;
                            result.error = query.lastError().text();
                        }
                    }
                    if (!failed) {
                        query.prepare(QStringLiteral(
                            "INSERT INTO metadata (key, value) VALUES ('alias_count', ?)"));
                        query.bindValue(0, result.aliasCount);
                        if (!query.exec()) {
                            failed = true;
                            result.error = query.lastError().text();
                        }
                    }
                    if (!failed) {
                        query.prepare(QStringLiteral(
                            "INSERT INTO metadata (key, value) VALUES ('token_count', ?)"));
                        query.bindValue(0, result.tokenCount);
                        if (!query.exec()) {
                            failed = true;
                            result.error = query.lastError().text();
                        }
                    }
                    if (!failed) {
                        query.prepare(QStringLiteral("INSERT INTO metadata (key, value) VALUES "
                                                     "('localized_printing_count', ?)"));
                        query.bindValue(0, result.localizedPrintingCount);
                        if (!query.exec()) {
                            failed = true;
                            result.error = query.lastError().text();
                        }
                    }
                    if (!failed &&
                        !query.exec(QStringLiteral(
                            "INSERT INTO metadata (key, value) VALUES ('schema_version', '9')"))) {
                        failed = true;
                        result.error = query.lastError().text();
                    }
                    if (!failed) {
                        query.prepare(QStringLiteral(
                            "INSERT INTO metadata (key, value) VALUES ('generated_at', ?)"));
                        query.bindValue(0, result.generatedAt);
                        if (!query.exec()) {
                            failed = true;
                            result.error = query.lastError().text();
                        }
                    }
                }
                if (failed || result.cardCount == 0) {
                    database.rollback();
                    if (result.error.isEmpty() && !result.cancelled)
                        result.error =
                            QStringLiteral("The downloaded catalog did not contain cards.");
                } else {
                    result.ok = true;
                }
                database.close();
            }
        }
    }
    QSqlDatabase::removeDatabase(connectionName);

    if (!result.ok) {
        QFile::remove(newPath);
        return result;
    }
    if (cancelCatalogImportIfRequested(stopToken, &result)) {
        QFile::remove(newPath);
        return result;
    }
    QString installError;
    if (!catalogstorage::installDatabase(newPath, databasePath, &installError)) {
        result.ok = false;
        result.error = installError;
        QFile::remove(newPath);
    }
    return result;
}

} // namespace hexproof::client::catalogimport
