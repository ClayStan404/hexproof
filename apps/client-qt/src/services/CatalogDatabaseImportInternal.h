// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors
#pragma once
#include "CardCatalogArchiveInternal.h"
#include "CardCatalogQueryInternal.h"
namespace hexproof::client::catalog_internal {

inline QString colorIdentity(const QJsonObject &card)
{
    const QJsonArray identity = card.value(QStringLiteral("color_identity")).toArray();
    QString colors;
    constexpr std::array<QChar, 5> order{
        QLatin1Char('W'), QLatin1Char('U'), QLatin1Char('B'), QLatin1Char('R'), QLatin1Char('G'),
    };
    for (const QChar color : order) {
        for (const QJsonValue &value : identity) {
            if (value.toString().compare(color, Qt::CaseInsensitive) == 0) {
                colors += color;
                break;
            }
        }
    }
    return colors;
}

inline QString legalFormats(const QJsonObject &card)
{
    QStringList formats;
    const QJsonObject legalities = card.value(QStringLiteral("legalities")).toObject();
    for (auto legality = legalities.begin(); legality != legalities.end(); ++legality) {
        const QString status = legality.value().toString();
        if (status == QStringLiteral("legal") || status == QStringLiteral("restricted"))
            formats.append(legality.key().toLower());
    }
    formats.sort();
    return formats.isEmpty() ? QString{}
                             : QLatin1Char('|') + formats.join(QLatin1Char('|')) + QLatin1Char('|');
}

inline QString legalityStatuses(const QJsonObject &card)
{
    QStringList statuses;
    const QJsonObject legalities = card.value(QStringLiteral("legalities")).toObject();
    for (auto legality = legalities.begin(); legality != legalities.end(); ++legality) {
        const QString status = legality.value().toString().toLower();
        if (status == QStringLiteral("legal") || status == QStringLiteral("restricted") ||
            status == QStringLiteral("banned") || status == QStringLiteral("not_legal")) {
            statuses.append(legality.key().toLower() + QLatin1Char(':') + status);
        }
    }
    statuses.sort();
    return statuses.isEmpty()
               ? QString{}
               : QLatin1Char('|') + statuses.join(QLatin1Char('|')) + QLatin1Char('|');
}

inline bool importChineseAliases(QSqlDatabase &database, const QString &jsonLinesPath,
                                 CatalogImportResult *result, CatalogImportStopToken stopToken = {})
{
    if (cancelCatalogImportIfRequested(stopToken, result))
        return false;
    QFile input(jsonLinesPath);
    if (!input.open(QIODevice::ReadOnly)) {
        result->error = QStringLiteral("Could not open the Chinese name index.");
        return false;
    }
    if (!database.transaction()) {
        result->error = database.lastError().text();
        return false;
    }

    QSqlQuery insert(database);
    if (!insert.prepare(QStringLiteral(
            "INSERT OR IGNORE INTO card_aliases "
            "(oracle_id, face_name, localized_name, localized_type, preferred, face_order) "
            "VALUES (?, ?, ?, ?, ?, ?)"))) {
        result->error = insert.lastError().text();
        database.rollback();
        return false;
    }

    QHash<QString, int> nextFaceOrder;
    constexpr qint64 maximumLineBytes = 4LL * 1024 * 1024;
    bool failed = false;
    while (!input.atEnd()) {
        if (cancelCatalogImportIfRequested(stopToken, result)) {
            failed = true;
            break;
        }
        const QByteArray line = input.readLine(maximumLineBytes + 1);
        if (line.size() > maximumLineBytes || (!line.endsWith('\n') && !input.atEnd())) {
            result->error = QStringLiteral("The Chinese name index contains an oversized record.");
            failed = true;
            break;
        }
        if (line.trimmed().isEmpty())
            continue;
        QJsonParseError parseError;
        QJsonDocument document = QJsonDocument::fromJson(line, &parseError);
        if (parseError.error != QJsonParseError::NoError) {
            // magic-cards-zhs currently writes escaped quotes in free-form text
            // with one extra backslash. The fields used below remain valid, so
            // repair only that known encoding defect and keep strict JSON
            // validation for every other malformed record.
            QByteArray repairedLine = line;
            repairedLine.replace(QByteArrayLiteral("\\\\\""), QByteArrayLiteral("\\\""));
            document = QJsonDocument::fromJson(repairedLine, &parseError);
        }
        if (parseError.error != QJsonParseError::NoError || !document.isObject()) {
            result->error = QStringLiteral("The Chinese name index contains invalid card data.");
            failed = true;
            break;
        }
        const QJsonObject object = document.object();
        const QString oracleId = object.value(QStringLiteral("oracle_id")).toString();
        const QString faceName = object.value(QStringLiteral("name")).toString().simplified();
        const QString translatedName =
            object.value(QStringLiteral("translated_name")).toString().simplified();
        const QString translatedType =
            object.value(QStringLiteral("translated_type")).toString().simplified();
        if (oracleId.isEmpty() || faceName.isEmpty() || translatedName.isEmpty())
            continue;
        const int faceOrder = nextFaceOrder.value(oracleId);
        nextFaceOrder.insert(oracleId, faceOrder + 1);

        auto insertAlias = [&](const QString &localizedName, bool preferred) {
            insert.bindValue(0, oracleId);
            insert.bindValue(1, faceName);
            insert.bindValue(2, localizedName);
            insert.bindValue(3, translatedType);
            insert.bindValue(4, preferred ? 1 : 0);
            insert.bindValue(5, faceOrder);
            if (!insert.exec()) {
                result->error = insert.lastError().text();
                return false;
            }
            if (insert.numRowsAffected() > 0)
                ++result->aliasCount;
            return true;
        };

        if (!insertAlias(translatedName, true)) {
            failed = true;
            break;
        }
        for (const QJsonValue &value : object.value(QStringLiteral("former_names")).toArray()) {
            const QString formerName = value.toString().simplified();
            if (!formerName.isEmpty() && formerName != translatedName &&
                !insertAlias(formerName, false)) {
                failed = true;
                break;
            }
        }
        if (failed)
            break;
    }

    if (failed || result->aliasCount == 0) {
        database.rollback();
        if (result->error.isEmpty() && !result->cancelled)
            result->error = QStringLiteral("The Chinese name index did not contain card names.");
        return false;
    }
    if (cancelCatalogImportIfRequested(stopToken, result)) {
        database.rollback();
        return false;
    }
    if (!database.commit()) {
        result->error = database.lastError().text();
        database.rollback();
        return false;
    }
    return true;
}

inline bool insertBulkCard(QSqlQuery &insert, const QJsonObject &card, CatalogImportResult *result)
{
    const QString id = card.value(QStringLiteral("id")).toString();
    const QString name = card.value(QStringLiteral("name")).toString();
    if (id.isEmpty() || name.isEmpty())
        return true;

    insert.bindValue(0, id);
    insert.bindValue(1, card.value(QStringLiteral("oracle_id")).toString());
    insert.bindValue(2, name);
    insert.bindValue(3, card.value(QStringLiteral("printed_name")).toString());
    insert.bindValue(4, card.value(QStringLiteral("type_line")).toString());
    insert.bindValue(5, card.value(QStringLiteral("set")).toString().toUpper());
    insert.bindValue(6, card.value(QStringLiteral("collector_number")).toString());
    const QString imageStatus = card.value(QStringLiteral("image_status")).toString().toLower();
    insert.bindValue(7, imageStatusAllowsArt(imageStatus) ? normalImageUrl(card) : QString{});
    insert.bindValue(8, imageStatus);
    insert.bindValue(9, card.value(QStringLiteral("lang")).toString());
    insert.bindValue(10, colorIdentity(card));
    insert.bindValue(11, card.value(QStringLiteral("cmc")).toDouble());
    insert.bindValue(12, card.value(QStringLiteral("rarity")).toString());
    const QString layout = card.value(QStringLiteral("layout")).toString();
    insert.bindValue(13, layout);
    insert.bindValue(14, legalFormats(card));
    insert.bindValue(15, card.value(QStringLiteral("illustration_id")).toString());
    insert.bindValue(16, card.value(QStringLiteral("released_at")).toString());
    insert.bindValue(17, card.value(QStringLiteral("digital")).toBool() ? 1 : 0);
    insert.bindValue(18, card.value(QStringLiteral("power")).toString());
    insert.bindValue(19, card.value(QStringLiteral("toughness")).toString());
    insert.bindValue(20, card.value(QStringLiteral("oracle_text")).toString());
    insert.bindValue(21, legalityStatuses(card));
    insert.bindValue(22, card.value(QStringLiteral("booster")).toBool() ? 1 : 0);
    if (!insert.exec()) {
        result->error = insert.lastError().text();
        return false;
    }
    ++result->cardCount;
    if (layout == QStringLiteral("token") &&
        card.value(QStringLiteral("lang")).toString() == QStringLiteral("en")) {
        ++result->tokenCount;
    }
    return true;
}

inline bool insertLocalizedPrinting(QSqlQuery &insert, const QJsonObject &card,
                                    CatalogImportResult *result)
{
    const QString language = card.value(QStringLiteral("lang")).toString().toLower();
    if (language != QStringLiteral("zhs") && language != QStringLiteral("zh"))
        return true;
    const QString imageStatus = card.value(QStringLiteral("image_status")).toString().toLower();
    if (!imageStatusAllowsArt(imageStatus))
        return true;

    const QString id = card.value(QStringLiteral("id")).toString();
    const QString oracleId = card.value(QStringLiteral("oracle_id")).toString();
    const QString name = card.value(QStringLiteral("name")).toString().simplified();
    if (id.isEmpty() || oracleId.isEmpty() || name.isEmpty())
        return true;

    const QString setCode = card.value(QStringLiteral("set")).toString().toUpper();
    const QString collectorNumber = card.value(QStringLiteral("collector_number")).toString();
    const QString releasedAt = card.value(QStringLiteral("released_at")).toString();
    const QString layout = card.value(QStringLiteral("layout")).toString();
    const int digital = card.value(QStringLiteral("digital")).toBool() ? 1 : 0;
    const QJsonArray faces = card.value(QStringLiteral("card_faces")).toArray();
    bool insertedFace = false;

    auto insertFace = [&](const QJsonObject &metadata, const QString &faceName, int faceOrder) {
        const QString imageUrl = normalImageUrl(metadata);
        if (imageUrl.isEmpty())
            return true;
        QString localizedName =
            metadata.value(QStringLiteral("printed_name")).toString().simplified();
        if (localizedName.isEmpty())
            localizedName = card.value(QStringLiteral("printed_name")).toString().simplified();
        QString typeLine =
            metadata.value(QStringLiteral("printed_type_line")).toString().simplified();
        if (typeLine.isEmpty())
            typeLine = metadata.value(QStringLiteral("type_line")).toString().simplified();
        QString illustrationId = metadata.value(QStringLiteral("illustration_id")).toString();
        if (illustrationId.isEmpty())
            illustrationId = card.value(QStringLiteral("illustration_id")).toString();

        insert.bindValue(0, id);
        insert.bindValue(1, faceName);
        insert.bindValue(2, oracleId);
        insert.bindValue(3, name);
        insert.bindValue(4, localizedName);
        insert.bindValue(5, typeLine);
        insert.bindValue(6, setCode);
        insert.bindValue(7, collectorNumber);
        insert.bindValue(8, illustrationId);
        insert.bindValue(9, releasedAt);
        insert.bindValue(10, imageUrl);
        insert.bindValue(11, imageStatus);
        insert.bindValue(12, digital);
        insert.bindValue(13, faceOrder);
        insert.bindValue(14, layout);
        if (!insert.exec()) {
            result->error = insert.lastError().text();
            return false;
        }
        insertedFace = true;
        return true;
    };

    if (!faces.isEmpty()) {
        for (qsizetype index = 0; index < faces.size(); ++index) {
            const QJsonObject face = faces.at(index).toObject();
            const QString faceName = face.value(QStringLiteral("name")).toString().simplified();
            if (!faceName.isEmpty() && !insertFace(face, faceName, static_cast<int>(index)))
                return false;
        }
        if (insertedFace)
            return true;
        // Split, adventure, and similar layouts can expose face metadata while
        // using one top-level image. Retain that whole-card printing instead
        // of dropping it from the localized index.
        return insertFace(card, QString{}, 0);
    }
    return insertFace(card, QString{}, 0);
}

inline bool importBulkJsonArray(QFile &input, QSqlQuery &insert, QSqlQuery *localizedInsert,
                                CatalogImportResult *result, bool localizedOnly = false,
                                CatalogImportStopToken stopToken = {})
{
    QByteArray objectBytes;
    int depth = 0;
    bool inString = false;
    bool escaped = false;
    bool startedArray = false;
    bool finishedArray = false;
    bool failed = false;
    while (!input.atEnd() && !failed) {
        if (cancelCatalogImportIfRequested(stopToken, result)) {
            failed = true;
            break;
        }
        const QByteArray chunk = input.read(1024 * 1024);
        for (const char byte : chunk) {
            if (depth == 0) {
                if (!startedArray) {
                    if (QChar::fromLatin1(byte).isSpace())
                        continue;
                    if (byte != '[') {
                        result->error = QStringLiteral("The bulk catalog is not a JSON array.");
                        failed = true;
                        break;
                    }
                    startedArray = true;
                    continue;
                }
                if (finishedArray) {
                    if (!QChar::fromLatin1(byte).isSpace()) {
                        result->error =
                            QStringLiteral("The bulk catalog has data after its array.");
                        failed = true;
                        break;
                    }
                    continue;
                }
                if (byte == '{') {
                    depth = 1;
                    objectBytes.clear();
                    objectBytes.append(byte);
                } else if (byte == ']') {
                    finishedArray = true;
                } else if (byte != ',' && !QChar::fromLatin1(byte).isSpace()) {
                    result->error = QStringLiteral("The bulk catalog contains invalid array data.");
                    failed = true;
                    break;
                }
                continue;
            }

            objectBytes.append(byte);
            if (objectBytes.size() > kMaximumBulkRecordBytes) {
                result->error = QStringLiteral("The bulk catalog contains an oversized card.");
                failed = true;
                break;
            }
            if (inString) {
                if (escaped)
                    escaped = false;
                else if (byte == '\\')
                    escaped = true;
                else if (byte == '"')
                    inString = false;
                continue;
            }
            if (byte == '"') {
                inString = true;
            } else if (byte == '{') {
                ++depth;
            } else if (byte == '}') {
                --depth;
                if (depth == 0) {
                    if (cancelCatalogImportIfRequested(stopToken, result)) {
                        failed = true;
                        break;
                    }
                    QJsonParseError parseError;
                    const QJsonDocument document =
                        QJsonDocument::fromJson(objectBytes, &parseError);
                    if (parseError.error != QJsonParseError::NoError || !document.isObject()) {
                        result->error =
                            QStringLiteral("The bulk catalog contains invalid card JSON.");
                        failed = true;
                        break;
                    }
                    const QJsonObject card = document.object();
                    if ((!localizedOnly && !insertBulkCard(insert, card, result)) ||
                        (localizedInsert &&
                         !insertLocalizedPrinting(*localizedInsert, card, result))) {
                        failed = true;
                        break;
                    }
                }
            }
        }
    }

    if (!failed && (!startedArray || !finishedArray || depth != 0 || inString)) {
        result->error =
            depth != 0 || inString
                ? QStringLiteral("The bulk catalog ended in the middle of a card.")
                : QStringLiteral("The bulk catalog ended before its array was complete.");
        failed = true;
    }
    return !failed;
}

inline bool importBulkJsonLinesGzip(const QString &path, QSqlQuery &insert,
                                    QSqlQuery *localizedInsert, CatalogImportResult *result,
                                    bool localizedOnly = false,
                                    CatalogImportStopToken stopToken = {})
{
    if (cancelCatalogImportIfRequested(stopToken, result))
        return false;
    gzFile archive = openGzipFile(path);
    if (!archive) {
        result->error = QStringLiteral("Could not open the compressed bulk catalog.");
        return false;
    }

    std::array<char, 64 * 1024> buffer{};
    QByteArray pending;
    qint64 expandedBytes = 0;
    bool failed = false;
    auto importLine = [&insert, localizedInsert, result, localizedOnly,
                       &failed](const QByteArray &line) {
        if (line.trimmed().isEmpty())
            return;
        QJsonParseError parseError;
        const QJsonDocument document = QJsonDocument::fromJson(line, &parseError);
        if (parseError.error != QJsonParseError::NoError || !document.isObject()) {
            result->error = QStringLiteral("The compressed bulk catalog contains invalid JSONL.");
            failed = true;
            return;
        }
        const QJsonObject card = document.object();
        if ((!localizedOnly && !insertBulkCard(insert, card, result)) ||
            (localizedInsert && !insertLocalizedPrinting(*localizedInsert, card, result)))
            failed = true;
    };

    while (!failed) {
        if (cancelCatalogImportIfRequested(stopToken, result)) {
            failed = true;
            break;
        }
        const int received =
            gzread(archive, buffer.data(), static_cast<unsigned int>(buffer.size()));
        if (received < 0) {
            result->error = QStringLiteral("The compressed bulk catalog is damaged.");
            failed = true;
            break;
        }
        if (received == 0)
            break;
        expandedBytes += received;
        const qint64 maximumExpandedBytes =
            localizedOnly ? kMaximumLocalizedBulkExpandedBytes : kMaximumBulkExpandedBytes;
        if (expandedBytes > maximumExpandedBytes) {
            result->error = QStringLiteral("The compressed bulk catalog is too large.");
            failed = true;
            break;
        }
        pending.append(buffer.data(), received);
        qsizetype consumed = 0;
        while (!failed) {
            if (cancelCatalogImportIfRequested(stopToken, result)) {
                failed = true;
                break;
            }
            const qsizetype newline = pending.indexOf('\n', consumed);
            if (newline < 0)
                break;
            if (newline - consumed > kMaximumBulkRecordBytes) {
                result->error =
                    QStringLiteral("The compressed bulk catalog contains an oversized card.");
                failed = true;
                break;
            }
            importLine(pending.mid(consumed, newline - consumed));
            consumed = newline + 1;
        }
        if (consumed > 0)
            pending.remove(0, consumed);
        if (pending.size() > kMaximumBulkRecordBytes) {
            result->error =
                QStringLiteral("The compressed bulk catalog contains an oversized card.");
            failed = true;
        }
    }

    if (!failed && !pending.trimmed().isEmpty())
        importLine(pending);
    int zlibError = Z_OK;
    gzerror(archive, &zlibError);
    const int closeResult = gzclose(archive);
    if (!failed && zlibError != Z_OK && zlibError != Z_STREAM_END) {
        result->error = QStringLiteral("The compressed bulk catalog is damaged.");
        failed = true;
    }
    if (!failed && closeResult != Z_OK) {
        result->error = QStringLiteral("The compressed bulk catalog ended unexpectedly.");
        failed = true;
    }
    return !failed;
}

} // namespace hexproof::client::catalog_internal
