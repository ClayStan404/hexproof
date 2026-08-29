// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "CatalogImport.h"
#include "CardCatalogCommon.h"
#include "CardImageProvider.h"
#include "CatalogStorage.h"
#include <QFuture>
#include <QSet>
#include <QtConcurrent>

namespace hexproof::client::catalogimport {
using namespace hexproof::client::catalog_internal;
using ImportResult = CatalogImportResult;

CardRecord parseCardObject(const QJsonObject &object, const QString &language,
                           const QString &requestedName)
{
    CardRecord record;
    record.requestedName = requestedName;
    record.name = object.value(QStringLiteral("name")).toString().simplified();
    record.oracleId = object.value(QStringLiteral("oracle_id")).toString();
    if (record.name.isEmpty())
        record.name = requestedName.simplified();
    const QString normalizedRequest = requestedName.simplified();
    QJsonObject selectedFace;
    QString selectedFaceName;
    bool selectedNestedFace = false;
    const auto selectMatchingFace = [&](const QJsonObject &face) {
        const QStringList candidates{
            face.value(QStringLiteral("face_name")).toString().simplified(),
            face.value(QStringLiteral("name")).toString().simplified(),
        };
        for (const QString &candidate : candidates) {
            if (!candidate.isEmpty() &&
                candidate.compare(normalizedRequest, Qt::CaseInsensitive) == 0) {
                selectedFace = face;
                selectedFaceName = candidate;
                selectedNestedFace = true;
                return true;
            }
        }
        return false;
    };
    const QStringList faceArrayKeys{
        QStringLiteral("card_faces"),
        QStringLiteral("faces"),
        QStringLiteral("other_faces"),
    };
    for (const QString &key : faceArrayKeys) {
        for (const QJsonValue &value : object.value(key).toArray()) {
            if (selectMatchingFace(value.toObject()))
                break;
        }
        if (!selectedFace.isEmpty())
            break;
    }
    if (selectedFace.isEmpty()) {
        const QStringList canonicalFaces = record.name.split(QStringLiteral(" // "));
        if (canonicalFaces.size() == 2 && canonicalFaces.first().simplified().compare(
                                              normalizedRequest, Qt::CaseInsensitive) == 0) {
            selectedFace = object;
            selectedFaceName = canonicalFaces.first().simplified();
        }
    }
    record.faceName = selectedFaceName;
    const QJsonObject metadata = selectedFace.isEmpty() ? object : selectedFace;
    static const QSet<QString> independentFaceLayouts{
        QStringLiteral("transform"),
        QStringLiteral("modal_dfc"),
        QStringLiteral("double_faced_token"),
        QStringLiteral("reversible_card"),
    };
    const bool requiresFaceSpecificImage =
        selectedNestedFace &&
        independentFaceLayouts.contains(object.value(QStringLiteral("layout")).toString());
    record.typeLine = language == QStringLiteral("zh")
                          ? metadata.value(QStringLiteral("zhs_type_line")).toString()
                          : QString{};
    if (record.typeLine.isEmpty() && language == QStringLiteral("zh"))
        record.typeLine = metadata.value(QStringLiteral("printed_type_line")).toString();
    if (record.typeLine.isEmpty())
        record.typeLine = metadata.value(QStringLiteral("type_line")).toString();
    record.setCode = object.value(QStringLiteral("set")).toString().toUpper();
    record.collectorNumber = object.value(QStringLiteral("collector_number")).toString();
    record.illustrationId = metadata.value(QStringLiteral("illustration_id")).toString();
    if (record.illustrationId.isEmpty())
        record.illustrationId = object.value(QStringLiteral("illustration_id")).toString();

    if (language == QStringLiteral("zh")) {
        QStringList localizedCandidates;
        if (!selectedFaceName.isEmpty()) {
            localizedCandidates.append(
                metadata.value(QStringLiteral("zhs_face_name")).toString().simplified());
            localizedCandidates.append(
                metadata.value(QStringLiteral("atomic_official_name")).toString().simplified());
            localizedCandidates.append(
                metadata.value(QStringLiteral("atomic_translated_name")).toString().simplified());
            localizedCandidates.append(
                metadata.value(QStringLiteral("printed_name")).toString().simplified());
        }
        localizedCandidates.append(
            object.value(QStringLiteral("zhs_name")).toString().simplified());
        localizedCandidates.append(
            object.value(QStringLiteral("zhs_face_name")).toString().simplified());
        localizedCandidates.append(
            object.value(QStringLiteral("atomic_official_name")).toString().simplified());
        localizedCandidates.append(
            object.value(QStringLiteral("atomic_translated_name")).toString().simplified());
        localizedCandidates.append(
            object.value(QStringLiteral("printed_name")).toString().simplified());
        for (const QString &candidate : localizedCandidates) {
            if (looksLikeChinese(candidate)) {
                record.localizedName = candidate;
                break;
            }
        }
        record.imageUrl = localizedImageUrl(metadata);
        if (record.imageUrl.isEmpty() && !selectedFace.isEmpty() && !requiresFaceSpecificImage)
            record.imageUrl = localizedImageUrl(object);
        const QString sourceLanguage = object.value(QStringLiteral("lang")).toString().toLower();
        if (record.imageUrl.isEmpty() &&
            (sourceLanguage == QStringLiteral("zhs") || sourceLanguage == QStringLiteral("zh")) &&
            imageStatusAllowsArt(object)) {
            record.imageUrl = normalImageUrl(metadata);
            if (record.imageUrl.isEmpty() && !selectedFace.isEmpty() && !requiresFaceSpecificImage)
                record.imageUrl = normalImageUrl(object);
        }
        if (!record.imageUrl.isEmpty())
            record.imageLanguage = QStringLiteral("zh");
    } else {
        if (imageStatusAllowsArt(object)) {
            record.imageUrl = normalImageUrl(metadata);
            if (record.imageUrl.isEmpty() && !selectedFace.isEmpty() && !requiresFaceSpecificImage)
                record.imageUrl = normalImageUrl(object);
        }
        if (!record.imageUrl.isEmpty())
            record.imageLanguage = QStringLiteral("en");
    }
    const QString flavorName = object.value(QStringLiteral("flavor_name")).toString().simplified();
    if (!normalizedRequest.isEmpty() &&
        flavorName.compare(normalizedRequest, Qt::CaseInsensitive) == 0) {
        record.localizedName = normalizedRequest;
    }
    if (record.localizedName.isEmpty())
        record.localizedName = record.name;
    record.resolutionVersion = kCardResolutionVersion;
    return record;
}

} // namespace hexproof::client::catalogimport
// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "CardImageProvider.h"
#include "CatalogDatabaseImportInternal.h"
#include "CatalogStorage.h"
#include <QFuture>
#include <QtConcurrent>

#include <vector>

namespace hexproof::client::catalogimport {
using namespace hexproof::client::catalog_internal;
using ImportResult = CatalogImportResult;

namespace {

bool fileSha256Cancellable(const QString &path, CatalogImportStopToken stopToken,
                           QByteArray *digest, ImportResult *result)
{
    if (cancelCatalogImportIfRequested(stopToken, result))
        return false;
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly))
        return false;
    QCryptographicHash hash(QCryptographicHash::Sha256);
    std::vector<char> buffer(1024 * 1024);
    while (!file.atEnd()) {
        if (cancelCatalogImportIfRequested(stopToken, result))
            return false;
        const qint64 received = file.read(buffer.data(), buffer.size());
        if (received < 0)
            return false;
        if (received == 0)
            break;
        hash.addData(QByteArrayView(buffer.data(), received));
    }
    if (cancelCatalogImportIfRequested(stopToken, result))
        return false;
    *digest = hash.result().toHex();
    return true;
}

bool copyFileCancellable(const QString &sourcePath, const QString &destinationPath,
                         CatalogImportStopToken stopToken, ImportResult *result)
{
    QFile source(sourcePath);
    if (!source.open(QIODevice::ReadOnly)) {
        result->error = QStringLiteral("Could not open the selected card database for copying.");
        return false;
    }
    QSaveFile destination(destinationPath);
    if (!destination.open(QIODevice::WriteOnly)) {
        result->error = QStringLiteral("Could not create the card database installation file.");
        return false;
    }

    std::vector<char> buffer(1024 * 1024);
    while (!source.atEnd()) {
        if (cancelCatalogImportIfRequested(stopToken, result)) {
            destination.cancelWriting();
            return false;
        }
        const qint64 received = source.read(buffer.data(), buffer.size());
        if (received < 0) {
            result->error = QStringLiteral("Could not read the selected card database.");
            destination.cancelWriting();
            return false;
        }
        if (received == 0)
            break;
        if (destination.write(buffer.data(), received) != received) {
            result->error = QStringLiteral("Could not copy the selected card database.");
            destination.cancelWriting();
            return false;
        }
    }
    if (cancelCatalogImportIfRequested(stopToken, result)) {
        destination.cancelWriting();
        return false;
    }
    if (!destination.commit()) {
        result->error = QStringLiteral("Could not finish copying the selected card database.");
        return false;
    }
    return true;
}

} // namespace

CatalogImportResult importDatabaseFile(const QString &sourcePath, const QString &databasePath,
                                       CatalogImportStopToken stopToken)
{
    ImportResult result;
    if (cancelCatalogImportIfRequested(stopToken, &result))
        return result;
    const QString connectionName = sqlConnectionName(QStringLiteral("hexproof-db-import-"));
    {
        QSqlDatabase database =
            QSqlDatabase::addDatabase(QStringLiteral("QSQLITE"), connectionName);
        database.setConnectOptions(QStringLiteral("QSQLITE_OPEN_READONLY"));
        database.setDatabaseName(sourcePath);
        if (!database.open()) {
            result.error = QStringLiteral("Could not open the selected card database.");
        } else {
            QSqlQuery query(database);
            query.prepare(QStringLiteral("SELECT value FROM metadata WHERE key = ?"));
            auto metadataValue = [&query](const QString &key) {
                query.bindValue(0, key);
                if (!query.exec() || !query.next())
                    return QString{};
                return query.value(0).toString();
            };
            result.packageType = metadataValue(QStringLiteral("package"));
            result.cardCount = metadataValue(QStringLiteral("count")).toInt();
            result.aliasCount = metadataValue(QStringLiteral("alias_count")).toInt();
            result.tokenCount = metadataValue(QStringLiteral("token_count")).toInt();
            result.localizedPrintingCount =
                metadataValue(QStringLiteral("localized_printing_count")).toInt();
            result.generatedAt = metadataValue(QStringLiteral("generated_at"));
            const int schemaVersion = metadataValue(QStringLiteral("schema_version")).toInt();
            result.schemaVersion = schemaVersion;
            if (result.packageType != QStringLiteral("default_cards") || result.cardCount <= 0 ||
                schemaVersion <= 0) {
                result.error = QStringLiteral("The selected card database has invalid metadata.");
            } else if (schemaVersion != kCatalogIndexVersion) {
                result.error =
                    QStringLiteral("The selected card database uses schema version %1, but this "
                                   "Hexproof version requires schema version %2.")
                        .arg(schemaVersion)
                        .arg(kCatalogIndexVersion);
            }
            if (result.error.isEmpty()) {
                if (!query.exec(QStringLiteral(
                        "SELECT name FROM pragma_table_info('cards') "
                        "WHERE name IN ('name', 'layout', 'image_url', 'legal_formats', "
                        "'illustration_id', 'power', 'toughness', 'oracle_text', "
                        "'legality_statuses', 'image_status', 'booster')"))) {
                    result.error =
                        QStringLiteral("The selected file is not a Hexproof card database.");
                } else {
                    QSet<QString> columns;
                    while (query.next())
                        columns.insert(query.value(0).toString());
                    if (columns.size() != 11) {
                        result.error =
                            QStringLiteral("The selected card database is incomplete or damaged.");
                    }
                }
            }
            if (result.error.isEmpty()) {
                if (!query.exec(
                        QStringLiteral("SELECT name FROM pragma_table_info('limited_products') "
                                       "WHERE name IN ('id', 'name', 'set_code', 'product_type', "
                                       "'authentic', 'definition_json')"))) {
                    result.error =
                        QStringLiteral("The selected file is not a Hexproof card database.");
                } else {
                    QSet<QString> columns;
                    while (query.next())
                        columns.insert(query.value(0).toString());
                    if (columns.size() != 6) {
                        result.error =
                            QStringLiteral("The selected card database is incomplete or damaged.");
                    }
                }
            }
            if (result.error.isEmpty()) {
                if (!query.exec(QStringLiteral(
                        "SELECT name FROM pragma_table_info('localized_printings') "
                        "WHERE name IN ('oracle_id', 'face_name', 'illustration_id', "
                        "'released_at', 'image_url', 'image_status', 'face_order', 'layout')"))) {
                    result.error =
                        QStringLiteral("The selected file is not a Hexproof card database.");
                } else {
                    QSet<QString> columns;
                    while (query.next())
                        columns.insert(query.value(0).toString());
                    if (columns.size() != 8) {
                        result.error =
                            QStringLiteral("The selected card database is incomplete or damaged.");
                    }
                }
            }
            database.close();
        }
    }
    QSqlDatabase::removeDatabase(connectionName);
    if (cancelCatalogImportIfRequested(stopToken, &result))
        return result;
    if (!result.error.isEmpty())
        return result;

    if (result.generatedAt.isEmpty()) {
        result.generatedAt = QFileInfo(sourcePath).lastModified().toUTC().toString(Qt::ISODate);
    }

    const QString newPath = databasePath + QStringLiteral(".new");
    if (!catalogstorage::recoverDatabase(databasePath, &result.error))
        return result;
    if (!copyFileCancellable(sourcePath, newPath, stopToken, &result)) {
        QFile::remove(newPath);
        return result;
    }
    if (cancelCatalogImportIfRequested(stopToken, &result)) {
        QFile::remove(newPath);
        return result;
    }
    if (!catalogstorage::installDatabase(newPath, databasePath, &result.error))
        return result;
    result.ok = true;
    return result;
}

CatalogImportResult importCompressedDatabaseFile(const QString &sourcePath,
                                                 const QString &databasePath,
                                                 qint64 expectedExpandedSize,
                                                 const QByteArray &expectedCompressedSha256,
                                                 const QByteArray &expectedDatabaseSha256,
                                                 CatalogImportStopToken stopToken)
{
    ImportResult result;
    QByteArray compressedSha256;
    if (!fileSha256Cancellable(sourcePath, stopToken, &compressedSha256, &result)) {
        if (!result.cancelled)
            result.error = QStringLiteral("Could not read the official card database download.");
        return result;
    }
    if (compressedSha256 != expectedCompressedSha256) {
        result.error =
            QStringLiteral("The official card database download failed its SHA-256 check.");
        return result;
    }

    gzFile archive = openGzipFile(sourcePath);
    if (!archive) {
        result.error = QStringLiteral("Could not open the official card database package.");
        return result;
    }

    const QString expandedPath = databasePath + QStringLiteral(".download");
    QFile::remove(expandedPath);
    QSaveFile output(expandedPath);
    if (!output.open(QIODevice::WriteOnly)) {
        gzclose(archive);
        result.error = QStringLiteral("Could not create the card database installation file.");
        return result;
    }

    QCryptographicHash hash(QCryptographicHash::Sha256);
    std::vector<char> buffer(256 * 1024);
    qint64 expandedSize = 0;
    bool failed = false;
    while (!failed) {
        if (cancelCatalogImportIfRequested(stopToken, &result)) {
            failed = true;
            break;
        }
        const int received =
            gzread(archive, buffer.data(), static_cast<unsigned int>(buffer.size()));
        if (received < 0) {
            result.error = QStringLiteral("The official card database package is damaged.");
            failed = true;
            break;
        }
        if (received == 0)
            break;
        expandedSize += received;
        if (expandedSize > expectedExpandedSize ||
            expandedSize > kMaximumOfficialCatalogExpandedBytes) {
            result.error = QStringLiteral("The official card database package is too large.");
            failed = true;
            break;
        }
        hash.addData(QByteArrayView(buffer.data(), received));
        if (output.write(buffer.data(), received) != received) {
            result.error = QStringLiteral("Could not write the card database installation file.");
            failed = true;
        }
    }
    const int closeResult = gzclose(archive);
    if (!failed && closeResult != Z_OK) {
        result.error = QStringLiteral("The official card database package ended unexpectedly.");
        failed = true;
    }
    if (!failed && cancelCatalogImportIfRequested(stopToken, &result))
        failed = true;
    if (!failed &&
        (expandedSize != expectedExpandedSize || hash.result().toHex() != expectedDatabaseSha256)) {
        result.error =
            QStringLiteral("The installed card database failed its size or SHA-256 check.");
        failed = true;
    }
    if (failed) {
        output.cancelWriting();
        QFile::remove(expandedPath);
        return result;
    }
    if (cancelCatalogImportIfRequested(stopToken, &result)) {
        output.cancelWriting();
        QFile::remove(expandedPath);
        return result;
    }
    if (!output.commit()) {
        result.error = QStringLiteral("Could not finish writing the card database.");
        QFile::remove(expandedPath);
        return result;
    }

    result = importDatabaseFile(expandedPath, databasePath, stopToken);
    QFile::remove(expandedPath);
    return result;
}

} // namespace hexproof::client::catalogimport
