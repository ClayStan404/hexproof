// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "CardCatalogCommon.h"
#include "CardCatalogQueryInternal.h"
#include "CatalogRepository.h"

#include <QRegularExpression>
#include <QSet>

namespace hexproof::client {

using namespace catalog_internal;

CatalogSearchResult CatalogRepository::search(const QString &text, const QString &language,
                                              const QString &typeFilter, const QString &setFilter,
                                              const QString &languageFilter,
                                              const QString &colorFilter,
                                              const QString &rarityFilter,
                                              const QString &legalityFilter) const
{
    CatalogSearchResult result;
    if (!ensureOpen(&result.error)) {
        if (result.error.isEmpty())
            result.error = QStringLiteral("Could not open the local card catalog.");
        return result;
    }
    const QSqlDatabase database = QSqlDatabase::database(m_connectionName);
    {
            const bool hasAliases = m_schema.hasAliases;
            const QString localizedExpression = hasAliases
                                                    ? localizedNameExpression(QStringLiteral("c"))
                                                    : QStringLiteral("c.printed_name");
            const QString typeExpression = language == QStringLiteral("zh") && hasAliases
                                               ? localizedTypeExpression(QStringLiteral("c"))
                                               : QStringLiteral("c.type_line");
            QSqlQuery query(database);
            QString statement =
                QStringLiteral(
                    "WITH matching_cards AS ("
                    "SELECT c.rowid, c.oracle_id, c.name, %1 AS localized_name, %2 AS type_line, "
                    "c.set_code, c.collector_number, c.image_url, c.lang, row_number() OVER ("
                    "PARTITION BY name COLLATE NOCASE ORDER BY "
                    "CASE WHEN c.lang = ? THEN 0 WHEN c.lang = 'en' THEN 1 ELSE 2 END, c.rowid) "
                    "choice "
                    "FROM cards c WHERE ")
                    .arg(localizedExpression, typeExpression);
            if (text.isEmpty()) {
                statement += QStringLiteral("1 = 1 ");
            } else {
                statement += QStringLiteral(
                    "(c.name LIKE ? ESCAPE '\\' OR c.printed_name LIKE ? ESCAPE '\\' ");
                if (hasAliases) {
                    statement += QStringLiteral(
                        "OR EXISTS (SELECT 1 FROM card_aliases sa WHERE sa.oracle_id = c.oracle_id "
                        "AND sa.localized_name LIKE ? ESCAPE '\\') ");
                }
                statement += QStringLiteral(
                    "OR c.name LIKE ? ESCAPE '\\' OR c.printed_name LIKE ? ESCAPE '\\' ");
                if (hasAliases) {
                    statement += QStringLiteral(
                        "OR EXISTS (SELECT 1 FROM card_aliases fa WHERE fa.oracle_id = c.oracle_id "
                        "AND fa.localized_name LIKE ? ESCAPE '\\') ");
                }
                statement += QLatin1Char(')');
            }
            if (!typeFilter.isEmpty())
                statement += QStringLiteral(" AND c.type_line LIKE ? ESCAPE '\\' ");
            if (!setFilter.isEmpty())
                statement += QStringLiteral(" AND c.set_code = ? COLLATE NOCASE ");
            if (!languageFilter.isEmpty())
                statement += QStringLiteral(" AND c.lang = ? COLLATE NOCASE ");
            if (colorFilter == QStringLiteral("C"))
                statement += QStringLiteral(" AND c.colors = '' ");
            else if (colorFilter == QStringLiteral("M"))
                statement += QStringLiteral(" AND length(c.colors) > 1 ");
            else if (!colorFilter.isEmpty())
                statement += QStringLiteral(" AND instr(c.colors, ?) > 0 ");
            if (!rarityFilter.isEmpty())
                statement += QStringLiteral(" AND c.rarity = ? COLLATE NOCASE ");
            if (!legalityFilter.isEmpty())
                statement += QStringLiteral(" AND instr(c.legal_formats, ?) > 0 ");
            statement += QStringLiteral(
                ") SELECT c.name, c.localized_name, c.type_line, c.set_code, "
                "c.collector_number, c.image_url, "
                "(SELECT count(DISTINCT v.set_code || char(31) || v.collector_number) "
                " FROM cards v WHERE v.name = c.name COLLATE NOCASE) "
                "FROM matching_cards c WHERE c.choice = 1 ");
            if (text.isEmpty()) {
                statement += QStringLiteral("ORDER BY c.name LIMIT 40");
            } else {
                statement += QStringLiteral(
                    "ORDER BY CASE WHEN lower(c.name) = lower(?) "
                    "OR lower(c.localized_name) = lower(?) THEN 0 "
                    "WHEN c.name LIKE ? ESCAPE '\\' OR c.localized_name LIKE ? ESCAPE '\\' THEN 1 "
                    "WHEN c.name LIKE ? ESCAPE '\\' OR c.localized_name LIKE ? ESCAPE '\\' THEN 2 "
                    "ELSE 3 END, c.name LIMIT 40");
            }
            query.prepare(statement);
            query.addBindValue(language == QStringLiteral("zh") ? QStringLiteral("zhs")
                                                                : QStringLiteral("en"));
            if (!text.isEmpty()) {
                const QString contains = QLatin1Char('%') + escapedLike(text) + QLatin1Char('%');
                const QString fuzzy = fuzzyLike(text);
                query.addBindValue(contains);
                query.addBindValue(contains);
                if (hasAliases)
                    query.addBindValue(contains);
                query.addBindValue(fuzzy);
                query.addBindValue(fuzzy);
                if (hasAliases)
                    query.addBindValue(fuzzy);
            }
            if (!typeFilter.isEmpty())
                query.addBindValue(QLatin1Char('%') + escapedLike(typeFilter) + QLatin1Char('%'));
            if (!setFilter.isEmpty())
                query.addBindValue(setFilter);
            if (!languageFilter.isEmpty())
                query.addBindValue(languageFilter);
            if (!colorFilter.isEmpty() && colorFilter != QStringLiteral("C") &&
                colorFilter != QStringLiteral("M"))
                query.addBindValue(colorFilter);
            if (!rarityFilter.isEmpty())
                query.addBindValue(rarityFilter);
            if (!legalityFilter.isEmpty())
                query.addBindValue(QLatin1Char('|') + legalityFilter + QLatin1Char('|'));
            if (!text.isEmpty()) {
                const QString escaped = escapedLike(text);
                const QString prefix = escaped + QLatin1Char('%');
                const QString contains = QLatin1Char('%') + escaped + QLatin1Char('%');
                query.addBindValue(text);
                query.addBindValue(text);
                query.addBindValue(prefix);
                query.addBindValue(prefix);
                query.addBindValue(contains);
                query.addBindValue(contains);
            }
            if (query.exec()) {
                while (query.next()) {
                    const QString name = query.value(0).toString();
                    const QString printedName = query.value(1).toString();
                    result.cards.append(QVariantMap{
                        {QStringLiteral("name"), name},
                        {QStringLiteral("displayName"),
                         language == QStringLiteral("zh") && !printedName.isEmpty() ? printedName
                                                                                    : name},
                        {QStringLiteral("typeLine"), query.value(2).toString()},
                        {QStringLiteral("setCode"), query.value(3).toString()},
                        {QStringLiteral("collectorNumber"), query.value(4).toString()},
                        {QStringLiteral("imageUrl"), query.value(5).toString()},
                        {QStringLiteral("versionCount"), query.value(6).toInt()},
                    });
                }
            } else {
                result.error = QStringLiteral("Could not search the local card catalog.");
            }
    }
    return result;
}

CatalogSearchResult CatalogRepository::searchTokens(const QString &text,
                                                    const QString &language) const
{
    CatalogSearchResult result;
    if (!ensureOpen(&result.error)) {
        if (result.error.isEmpty())
            result.error = QStringLiteral("Could not open the local token catalog.");
        return result;
    }
    const QSqlDatabase database = QSqlDatabase::database(m_connectionName);
    {
            const bool hasAliases = m_schema.hasAliases;
            const bool hasLocalizedPrintings = m_schema.hasLocalizedPrintings;
            const QSet<QString> &cardColumns = m_schema.cardColumns;
            QStringList localizedNames;
            QStringList localizedTypes;
            if (language == QStringLiteral("zh")) {
                if (hasAliases) {
                    localizedNames.append(
                        QStringLiteral("(SELECT group_concat(localized_name, ' // ') FROM ("
                                       "SELECT localized_name FROM card_aliases ax "
                                       "WHERE ax.oracle_id = c.oracle_id AND ax.preferred = 1 "
                                       "ORDER BY ax.face_order))"));
                    localizedTypes.append(
                        QStringLiteral("(SELECT group_concat(localized_type, ' // ') FROM ("
                                       "SELECT localized_type FROM card_aliases tx "
                                       "WHERE tx.oracle_id = c.oracle_id AND tx.preferred = 1 "
                                       "AND tx.localized_type != '' ORDER BY tx.face_order))"));
                }
                if (hasLocalizedPrintings) {
                    localizedNames.append(QStringLiteral(
                        "(SELECT group_concat(localized_name, ' // ') FROM ("
                        "SELECT localized_name FROM localized_printings lp "
                        "WHERE lp.oracle_id = c.oracle_id AND lp.localized_name != '' AND lp.id = "
                        "(SELECT chosen.id FROM localized_printings chosen "
                        "WHERE chosen.oracle_id = c.oracle_id AND chosen.localized_name != '' "
                        "ORDER BY chosen.released_at DESC, chosen.id LIMIT 1) "
                        "ORDER BY lp.face_order))"));
                    localizedTypes.append(QStringLiteral(
                        "(SELECT group_concat(localized_type, ' // ') FROM ("
                        "SELECT localized_type FROM localized_printings lt "
                        "WHERE lt.oracle_id = c.oracle_id AND lt.localized_type != '' AND lt.id = "
                        "(SELECT chosen.id FROM localized_printings chosen "
                        "WHERE chosen.oracle_id = c.oracle_id AND chosen.localized_type != '' "
                        "ORDER BY chosen.released_at DESC, chosen.id LIMIT 1) "
                        "ORDER BY lt.face_order))"));
                }
            }
            localizedNames.append(QStringLiteral("c.name"));
            localizedTypes.append(QStringLiteral("c.type_line"));
            const QString localizedName =
                localizedNames.size() == 1
                    ? localizedNames.constFirst()
                    : QStringLiteral("COALESCE(%1)").arg(localizedNames.join(QStringLiteral(", ")));
            const QString localizedType =
                localizedTypes.size() == 1
                    ? localizedTypes.constFirst()
                    : QStringLiteral("COALESCE(%1)").arg(localizedTypes.join(QStringLiteral(", ")));
            const QString powerExpression = cardColumns.contains(QStringLiteral("power"))
                                                ? QStringLiteral("c.power")
                                                : QStringLiteral("''");
            const QString toughnessExpression = cardColumns.contains(QStringLiteral("toughness"))
                                                    ? QStringLiteral("c.toughness")
                                                    : QStringLiteral("''");
            const QString oracleTextExpression = cardColumns.contains(QStringLiteral("oracle_text"))
                                                     ? QStringLiteral("c.oracle_text")
                                                     : QStringLiteral("''");
            const auto appendRows = [&result](QSqlQuery &query) {
                while (query.next()) {
                    result.cards.append(QVariantMap{
                        {QStringLiteral("name"), query.value(0).toString()},
                        {QStringLiteral("displayName"), query.value(1).toString()},
                        {QStringLiteral("typeLine"), query.value(2).toString()},
                        {QStringLiteral("setCode"), query.value(3).toString()},
                        {QStringLiteral("collectorNumber"), query.value(4).toString()},
                        {QStringLiteral("imageUrl"), query.value(5).toString()},
                        {QStringLiteral("power"), query.value(6).toString()},
                        {QStringLiteral("toughness"), query.value(7).toString()},
                        {QStringLiteral("oracleText"), query.value(8).toString()},
                        {QStringLiteral("oracleId"), query.value(9).toString()},
                    });
                }
            };

            bool exactResolved = false;
            static const QRegularExpression exactIdentity(QStringLiteral(
                R"(^\s*([A-Za-z0-9]{2,8})\s*(?:#\s*)?([A-Za-z0-9][A-Za-z0-9._+*-]*)\s*$)"));
            const QRegularExpressionMatch exactMatch = exactIdentity.match(text);
            if (exactMatch.hasMatch()) {
                const QString requestedSet = exactMatch.captured(1).toUpper();
                const QString tokenSet = requestedSet.startsWith(QLatin1Char('T'))
                                             ? requestedSet
                                             : QLatin1Char('T') + requestedSet;
                const QString collectorNumber = exactMatch.captured(2);
                QSqlQuery exactQuery(database);
                exactQuery.prepare(
                    QStringLiteral("SELECT c.name, %1 AS localized_name, %2 AS type_line, "
                                   "c.set_code, c.collector_number, c.image_url, %3 AS power, "
                                   "%4 AS toughness, %5 AS oracle_text, c.oracle_id "
                                   "FROM cards c WHERE c.layout = 'token' AND c.lang = 'en' "
                                   "AND (upper(c.set_code) = ? OR upper(c.set_code) = ?) "
                                   "AND (c.collector_number = ? COLLATE NOCASE OR "
                                   "ltrim(c.collector_number, '0') = "
                                   "ltrim(?, '0') COLLATE NOCASE) "
                                   "ORDER BY CASE WHEN upper(c.set_code) = ? THEN 0 ELSE 1 END, "
                                   "c.rowid DESC LIMIT 60")
                        .arg(localizedName, localizedType, powerExpression, toughnessExpression,
                             oracleTextExpression));
                exactQuery.addBindValue(requestedSet);
                exactQuery.addBindValue(tokenSet);
                exactQuery.addBindValue(collectorNumber);
                exactQuery.addBindValue(collectorNumber);
                exactQuery.addBindValue(requestedSet);
                if (exactQuery.exec()) {
                    appendRows(exactQuery);
                    exactResolved = !result.cards.isEmpty();
                } else {
                    result.error = QStringLiteral("Could not search the local token catalog.");
                }
            }

            if (result.error.isEmpty() && !exactResolved) {
                QSqlQuery query(database);
                QString statement =
                    QStringLiteral(
                        "WITH token_printings AS ("
                        "SELECT c.name, %1 AS localized_name, %2 AS type_line, c.set_code, "
                        "c.collector_number, c.image_url, %3 AS power, %4 AS toughness, "
                        "%5 AS oracle_text, c.oracle_id, "
                        "row_number() OVER (PARTITION BY "
                        "COALESCE(NULLIF(c.oracle_id, ''), c.name || char(31) || c.set_code || "
                        "char(31) || c.collector_number) ORDER BY c.rowid DESC) choice "
                        "FROM cards c WHERE c.layout = 'token' AND c.lang = 'en' ")
                        .arg(localizedName, localizedType, powerExpression, toughnessExpression,
                             oracleTextExpression);
                if (!text.isEmpty()) {
                    statement += QStringLiteral(
                        "AND (c.name LIKE ? ESCAPE '\\' OR c.type_line LIKE ? ESCAPE '\\' "
                        "OR c.set_code LIKE ? ESCAPE '\\' "
                        "OR c.collector_number LIKE ? ESCAPE '\\' ");
                    if (hasAliases) {
                        statement += QStringLiteral("OR EXISTS (SELECT 1 FROM card_aliases a "
                                                    "WHERE a.oracle_id = c.oracle_id "
                                                    "AND (a.localized_name LIKE ? ESCAPE '\\' "
                                                    "OR a.localized_type LIKE ? ESCAPE '\\')) ");
                    }
                    if (hasLocalizedPrintings) {
                        statement +=
                            QStringLiteral("OR EXISTS (SELECT 1 FROM localized_printings lp "
                                           "WHERE lp.oracle_id = c.oracle_id "
                                           "AND (lp.localized_name LIKE ? ESCAPE '\\' "
                                           "OR lp.localized_type LIKE ? ESCAPE '\\')) ");
                    }
                    statement += QLatin1Char(')');
                }
                statement += QStringLiteral(
                    ") SELECT name, localized_name, type_line, set_code, collector_number, "
                    "image_url, power, toughness, oracle_text, oracle_id "
                    "FROM token_printings WHERE choice = 1 ");
                if (text.isEmpty()) {
                    statement += QStringLiteral("ORDER BY name COLLATE NOCASE LIMIT 60");
                } else {
                    statement += QStringLiteral(
                        "ORDER BY CASE WHEN lower(name) = lower(?) "
                        "OR lower(localized_name) = lower(?) THEN 0 "
                        "WHEN name LIKE ? ESCAPE '\\' OR localized_name LIKE ? ESCAPE '\\' "
                        "THEN 1 ELSE 2 END, name COLLATE NOCASE, power, toughness LIMIT 60");
                }
                query.prepare(statement);
                if (!text.isEmpty()) {
                    const QString escaped = escapedLike(text);
                    const QString contains = QLatin1Char('%') + escaped + QLatin1Char('%');
                    query.addBindValue(contains);
                    query.addBindValue(contains);
                    query.addBindValue(contains);
                    query.addBindValue(contains);
                    if (hasAliases) {
                        query.addBindValue(contains);
                        query.addBindValue(contains);
                    }
                    if (hasLocalizedPrintings) {
                        query.addBindValue(contains);
                        query.addBindValue(contains);
                    }
                    query.addBindValue(text);
                    query.addBindValue(text);
                    query.addBindValue(escaped + QLatin1Char('%'));
                    query.addBindValue(escaped + QLatin1Char('%'));
                }
                if (query.exec()) {
                    appendRows(query);
                } else {
                    result.error = QStringLiteral("Could not search the local token catalog.");
                }
            }
    }
    return result;
}

} // namespace hexproof::client
