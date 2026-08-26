// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "CardCatalogCommon.h"
#include "CardCatalogQueryInternal.h"
#include "CatalogRepository.h"

namespace hexproof::client {

using namespace catalog_internal;

CardRecord CatalogRepository::lookup(const CatalogCardQuery &request) const
{
    CardRecord record;
    if (!ensureOpen())
        return record;
    const QSqlDatabase database = QSqlDatabase::database(m_connectionName);
    const bool hasAliases = m_schema.hasAliases;
    const QString localizedExpression = hasAliases ? localizedNameExpression(QStringLiteral("c"))
                                                   : QStringLiteral("c.printed_name");
    const QString typeExpression = request.language == QStringLiteral("zh") && hasAliases
                                       ? localizedTypeExpression(QStringLiteral("c"))
                                       : QStringLiteral("c.type_line");
    const bool hasImageStatus = m_schema.cardColumns.contains(QStringLiteral("image_status"));
    const QString imageStatusExpression =
        hasImageStatus ? QStringLiteral("c.image_status") : QStringLiteral("''");
    const QString imageUsabilityOrder =
        hasImageStatus
            ? QStringLiteral("CASE WHEN lower(c.image_status) IN ('missing', 'placeholder') "
                             "THEN 1 ELSE 0 END, ")
            : QString{};
    QSqlQuery query(database);
    const QString select =
        QStringLiteral("SELECT c.name, c.oracle_id, %1, %2, c.set_code, c.collector_number, "
                       "c.image_url, c.lang, c.illustration_id, %3 FROM cards c ")
            .arg(localizedExpression, typeExpression, imageStatusExpression);
    const QString preferredLanguage =
        request.language == QStringLiteral("zh") ? QStringLiteral("zhs") : QStringLiteral("en");
    const QString resultOrder =
        QStringLiteral("ORDER BY ") + imageUsabilityOrder +
        QStringLiteral("CASE WHEN c.lang = ? THEN 0 WHEN c.lang = 'en' THEN 1 ELSE 2 END LIMIT 1");
    const bool exactPrinting = !request.setCode.isEmpty() && !request.collectorNumber.isEmpty();
    const auto lookupIndexedName = [&](const QString &column) {
        query = QSqlQuery(database);
        QString statement = select + QStringLiteral("WHERE c.%1 = ? COLLATE NOCASE ").arg(column);
        if (exactPrinting) {
            statement += QStringLiteral("AND c.set_code = ? COLLATE NOCASE "
                                        "AND c.collector_number = ? COLLATE NOCASE ");
        }
        query.prepare(statement + resultOrder);
        query.addBindValue(request.name);
        if (exactPrinting) {
            query.addBindValue(request.setCode);
            query.addBindValue(request.collectorNumber);
        }
        query.addBindValue(preferredLanguage);
        return query.exec() && query.next();
    };

    bool found = !request.name.isEmpty() && lookupIndexedName(QStringLiteral("name"));
    if (!found && !request.name.isEmpty())
        found = lookupIndexedName(QStringLiteral("printed_name"));

    if (!found && exactPrinting) {
        query = QSqlQuery(database);
        query.prepare(select +
                      QStringLiteral("WHERE c.set_code = ? COLLATE NOCASE "
                                     "AND c.collector_number = ? COLLATE NOCASE ") +
                      resultOrder);
        query.addBindValue(request.setCode);
        query.addBindValue(request.collectorNumber);
        query.addBindValue(preferredLanguage);
        found = query.exec() && query.next();
    } else if (!found) {
        query = QSqlQuery(database);
        QString statement =
            select +
            QStringLiteral("WHERE (lower(c.name) = lower(?) OR lower(c.printed_name) = lower(?) ");
        if (hasAliases) {
            statement += QStringLiteral(
                "OR EXISTS (SELECT 1 FROM card_aliases a WHERE a.oracle_id = c.oracle_id "
                "AND (lower(a.localized_name) = lower(?) "
                "OR lower(a.face_name) = lower(?))) ");
        }
        statement +=
            QStringLiteral("OR (instr(c.name, ' // ') > 0 "
                           "AND (lower(substr(c.name, 1, instr(c.name, ' // ') - 1)) = lower(?) "
                           "OR lower(substr(c.name, instr(c.name, ' // ') + 4)) = lower(?))) "
                           ") ORDER BY "
                           "CASE WHEN lower(c.name) = lower(?) "
                           "OR lower(c.printed_name) = lower(?) THEN 0 ELSE 1 END, ");
        statement += imageUsabilityOrder;
        statement += QStringLiteral(
            "CASE WHEN c.lang = ? THEN 0 WHEN c.lang = 'en' THEN 1 ELSE 2 END LIMIT 1");
        query.prepare(statement);
        query.addBindValue(request.name);
        query.addBindValue(request.name);
        if (hasAliases) {
            query.addBindValue(request.name);
            query.addBindValue(request.name);
        }
        query.addBindValue(request.name);
        query.addBindValue(request.name);
        query.addBindValue(request.name);
        query.addBindValue(request.name);
        query.addBindValue(preferredLanguage);
        found = query.exec() && query.next();
    }
    if (found) {
        record.requestedName = request.name;
        record.name = query.value(0).toString();
        record.oracleId = query.value(1).toString();
        record.localizedName =
            request.language == QStringLiteral("zh") ? query.value(2).toString() : record.name;
        if (request.language == QStringLiteral("zh") && !looksLikeChinese(record.localizedName)) {
            record.localizedName.clear();
        }
        if (record.localizedName.isEmpty())
            record.localizedName = record.name;
        const QString requestedDisplayName = request.name.simplified();
        if (exactPrinting && !requestedDisplayName.isEmpty() &&
            !record.name.contains(QStringLiteral(" // ")) &&
            record.name.compare(requestedDisplayName, Qt::CaseInsensitive) != 0) {
            // Universes Beyond reskins and Secret Lair aliases retain the
            // deck-list title while set/collector identify the canonical card.
            record.localizedName = requestedDisplayName;
        }
        record.typeLine = query.value(3).toString();
        record.setCode = query.value(4).toString();
        record.collectorNumber = query.value(5).toString();
        record.imageUrl = upgradeLegacySmallImageUrl(query.value(6).toString());
        const QString rowLanguage = query.value(7).toString().toLower();
        record.illustrationId = query.value(8).toString();
        const QString imageStatus = query.value(9).toString();
        const bool unverifiedLegacyChineseImage =
            !hasImageStatus &&
            (rowLanguage == QStringLiteral("zhs") || rowLanguage == QStringLiteral("zh"));
        if (!imageStatusAllowsArt(imageStatus) || unverifiedLegacyChineseImage)
            record.imageUrl.clear();
        record.imageLanguage =
            rowLanguage == QStringLiteral("zhs") || rowLanguage == QStringLiteral("zh")
                ? QStringLiteral("zh")
                : QStringLiteral("en");
    }
    return record;
}

CardRecord CatalogRepository::lookupLocalizedPrinting(const CatalogCardQuery &request,
                                                      const CardRecord &catalogIdentity,
                                                      int indexVersion) const
{
    CardRecord record;
    if (catalogIdentity.oracleId.isEmpty() || indexVersion < 5 || !ensureOpen())
        return record;
    if (!m_schema.localizedPrintingColumns.contains(QStringLiteral("image_status")))
        return record;

    const QSqlDatabase database = QSqlDatabase::database(m_connectionName);
    QSqlQuery query(database);
    QString statement =
        QStringLiteral("SELECT name, face_name, localized_name, localized_type, set_code, "
                       "collector_number, illustration_id, image_url, image_status "
                       "FROM localized_printings WHERE oracle_id = ? ");
    const QString normalizedRequest = request.name.simplified();
    const QString normalizedCanonical = catalogIdentity.name.simplified();
    const bool requestsFace =
        normalizedCanonical.contains(QStringLiteral(" // ")) &&
        normalizedCanonical.compare(normalizedRequest, Qt::CaseInsensitive) != 0;
    if (requestsFace)
        statement += QStringLiteral("AND lower(face_name) = lower(?) ");
    statement +=
        QStringLiteral("ORDER BY CASE WHEN lower(set_code) = lower(?) AND collector_number = ? "
                       "THEN 0 ELSE 1 END, "
                       "CASE WHEN illustration_id != '' AND lower(illustration_id) = lower(?) "
                       "THEN 0 ELSE 1 END, digital ASC, released_at DESC, face_order ASC LIMIT 1");
    query.prepare(statement);
    query.addBindValue(catalogIdentity.oracleId);
    if (requestsFace)
        query.addBindValue(normalizedRequest);
    query.addBindValue(request.setCode);
    query.addBindValue(request.collectorNumber);
    query.addBindValue(catalogIdentity.illustrationId);
    if (query.exec() && query.next()) {
        record.requestedName = request.name;
        record.name = query.value(0).toString();
        record.faceName = query.value(1).toString();
        record.oracleId = catalogIdentity.oracleId;
        record.localizedName = query.value(2).toString();
        if (record.localizedName.isEmpty())
            record.localizedName = catalogIdentity.localizedName;
        record.typeLine = query.value(3).toString();
        if (record.typeLine.isEmpty())
            record.typeLine = catalogIdentity.typeLine;
        record.setCode = query.value(4).toString();
        record.collectorNumber = query.value(5).toString();
        record.illustrationId = query.value(6).toString();
        record.imageUrl = upgradeLegacySmallImageUrl(query.value(7).toString());
        if (!imageStatusAllowsArt(query.value(8).toString()))
            record.imageUrl.clear();
        if (record.imageUrl.isEmpty())
            return {};
        record.imageLanguage = QStringLiteral("zh");
        record.usesSubstituteArt =
            request.setCode.compare(record.setCode, Qt::CaseInsensitive) != 0 ||
            request.collectorNumber != record.collectorNumber;
        record.resolutionVersion = kCardResolutionVersion;
    }
    return record;
}

bool CatalogRepository::cachedScryfallArtIsUsable(const CardRecord &record) const
{
    if (record.imageUrl.isEmpty() || !ensureOpen())
        return false;

    const QSqlDatabase database = QSqlDatabase::database(m_connectionName);
    const auto matchesTable = [&](const QString &table, const QSet<QString> &columns,
                                  const QString &language) {
        static const QSet<QString> requiredColumns{
            QStringLiteral("oracle_id"),
            QStringLiteral("illustration_id"),
            QStringLiteral("image_url"),
            QStringLiteral("image_status"),
        };
        for (const QString &column : requiredColumns) {
            if (!columns.contains(column))
                return false;
        }
        if (!language.isEmpty() && !columns.contains(QStringLiteral("lang")))
            return false;

        QString statement =
            QStringLiteral("SELECT 1 FROM %1 WHERE image_url != '' "
                           "AND lower(image_status) NOT IN ('missing', 'placeholder') ")
                .arg(table);
        if (!language.isEmpty()) {
            statement += language == QStringLiteral("zh")
                             ? QStringLiteral("AND lower(lang) IN ('zhs', 'zh') ")
                             : QStringLiteral("AND lower(lang) = 'en' ");
        }
        if (!record.oracleId.isEmpty())
            statement += QStringLiteral("AND lower(oracle_id) = lower(?) ");
        statement += QStringLiteral(
            "AND (image_url = ? OR (? != '' AND lower(illustration_id) = lower(?))) LIMIT 1");

        QSqlQuery query(database);
        query.prepare(statement);
        if (!record.oracleId.isEmpty())
            query.addBindValue(record.oracleId);
        query.addBindValue(record.imageUrl);
        query.addBindValue(record.illustrationId);
        query.addBindValue(record.illustrationId);
        return query.exec() && query.next();
    };

    if (record.imageLanguage != QStringLiteral("zh") &&
        record.imageLanguage != QStringLiteral("en")) {
        return false;
    }
    const QString language =
        record.imageLanguage == QStringLiteral("zh") ? QStringLiteral("zh") : QStringLiteral("en");
    if (matchesTable(QStringLiteral("cards"), m_schema.cardColumns, language))
        return true;
    return language == QStringLiteral("zh") && m_schema.hasLocalizedPrintings &&
           matchesTable(QStringLiteral("localized_printings"), m_schema.localizedPrintingColumns,
                        {});
}

} // namespace hexproof::client
