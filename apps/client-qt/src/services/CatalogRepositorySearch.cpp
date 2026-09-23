// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "CardCatalogCommon.h"
#include "CardCatalogQueryInternal.h"
#include "CatalogRepository.h"

#include <QRegularExpression>
#include <QSet>

namespace hexproof::client {

using namespace catalog_internal;

namespace {
// Filter values are bound parameters, never SQL fragments supplied by the UI.
void appendFilter(QString &statement, QVariantList &bindings, const QString &raw,
                  const QString &kind, bool hasMana = true)
{
    if (raw.isEmpty())
        return;
    QStringList alternatives;
    const QStringList values = raw.split(QLatin1Char(','), Qt::SkipEmptyParts);
    for (const QString &part : values.mid(0, 16)) {
        const QString value = part.trimmed();
        if (kind == QStringLiteral("type")) {
            alternatives.append(QStringLiteral("c.type_line LIKE ? ESCAPE '\\'"));
            bindings.append(QLatin1Char('%') + escapedLike(value) + QLatin1Char('%'));
        } else if (kind == QStringLiteral("rarity")) {
            alternatives.append(QStringLiteral("c.rarity = ? COLLATE NOCASE"));
            bindings.append(value);
        } else if (kind == QStringLiteral("color")) {
            if (value == QStringLiteral("C"))
                alternatives.append(QStringLiteral("c.colors = ''"));
            else if (value == QStringLiteral("M"))
                alternatives.append(QStringLiteral("length(c.colors) > 1"));
            else {
                alternatives.append(QStringLiteral("instr(c.colors, ?) > 0"));
                bindings.append(value);
            }
        } else {
            bool valid = false;
            const int mana = value.toInt(&valid);
            if (!hasMana)
                alternatives.append(QStringLiteral("0"));
            else if (value == QStringLiteral("7+"))
                alternatives.append(QStringLiteral("c.mana_value >= 7"));
            else if (valid && mana >= 0 && mana <= 6) {
                alternatives.append(QStringLiteral("c.mana_value = ?"));
                bindings.append(mana);
            } else
                alternatives.append(QStringLiteral("0"));
        }
    }
    // Every selected color must be present; the other categories allow alternatives.
    const QString separator =
        kind == QStringLiteral("color") ? QStringLiteral(" AND ") : QStringLiteral(" OR ");
    statement += QStringLiteral(" AND (") +
                 (alternatives.isEmpty() ? QStringLiteral("0") : alternatives.join(separator)) +
                 QLatin1Char(')');
}
} // namespace

CatalogSearchResult
CatalogRepository::search(const QString &text, const QString &language, const QString &typeFilter,
                          const QString &setFilter, const QString &languageFilter,
                          const QString &colorFilter, const QString &rarityFilter,
                          const QString &legalityFilter, const QString &manaFilter) const
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
            const QString colorsExpression = m_schema.cardColumns.contains(QStringLiteral("colors"))
                                                 ? QStringLiteral("c.colors")
                                                 : QStringLiteral("''");
            const QString manaValueExpression =
                m_schema.cardColumns.contains(QStringLiteral("mana_value"))
                    ? QStringLiteral("c.mana_value")
                    : QStringLiteral("-1");
            const QString rarityExpression = m_schema.cardColumns.contains(QStringLiteral("rarity"))
                                                 ? QStringLiteral("c.rarity")
                                                 : QStringLiteral("'unknown'");
            QSqlQuery query(database);
            QString statement =
                QStringLiteral(
                    "WITH matching_cards AS ("
                    "SELECT c.rowid, c.oracle_id, c.name, %1 AS localized_name, %2 AS type_line, "
                    "c.set_code, c.collector_number, c.image_url, c.lang, row_number() OVER ("
                    "PARTITION BY name COLLATE NOCASE ORDER BY "
                    "CASE WHEN c.lang = ? THEN 0 WHEN c.lang = 'en' THEN 1 ELSE 2 END, c.rowid) "
                    "choice, %3 AS colors, %4 AS mana_value, %5 AS rarity "
                    "FROM cards c WHERE ")
                    .arg(localizedExpression, typeExpression, colorsExpression, manaValueExpression,
                         rarityExpression);
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
            if (m_schema.cardColumns.contains(QStringLiteral("layout")))
                statement += QStringLiteral(" AND ") + catalogPlayablePrintingSql();
            QVariantList filterBindings;
            appendFilter(statement, filterBindings, typeFilter, QStringLiteral("type"));
            if (!setFilter.isEmpty())
                statement += QStringLiteral(" AND c.set_code = ? COLLATE NOCASE ");
            if (!setFilter.isEmpty())
                filterBindings.append(setFilter);
            if (!languageFilter.isEmpty())
                statement += QStringLiteral(" AND c.lang = ? COLLATE NOCASE ");
            if (!languageFilter.isEmpty())
                filterBindings.append(languageFilter);
            appendFilter(statement, filterBindings, colorFilter, QStringLiteral("color"));
            appendFilter(statement, filterBindings, rarityFilter, QStringLiteral("rarity"));
            appendFilter(statement, filterBindings, manaFilter, QStringLiteral("mana"),
                         m_schema.cardColumns.contains(QStringLiteral("mana_value")));
            if (!legalityFilter.isEmpty())
                statement += QStringLiteral(" AND instr(c.legal_formats, ?) > 0 ");
            if (!legalityFilter.isEmpty())
                filterBindings.append(QLatin1Char('|') + legalityFilter + QLatin1Char('|'));
            statement += QStringLiteral(
                ") SELECT c.name, c.localized_name, c.type_line, c.set_code, "
                "c.collector_number, c.image_url, "
                "(SELECT count(DISTINCT v.set_code || char(31) || v.collector_number) "
                " FROM cards v WHERE v.name = c.name COLLATE NOCASE");
            if (m_schema.cardColumns.contains(QStringLiteral("layout")))
                statement +=
                    QStringLiteral(" AND ") + catalogPlayablePrintingSql(QStringLiteral("v."));
            statement += QStringLiteral(
                "), c.colors, c.mana_value, c.rarity FROM matching_cards c WHERE c.choice = 1 ");
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
            for (const QVariant &value : filterBindings)
                query.addBindValue(value);
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
                        {QStringLiteral("colors"), query.value(7).toString().toUpper()},
                        {QStringLiteral("manaValue"), query.value(8).toDouble()},
                        {QStringLiteral("rarity"), query.value(9).toString()},
                    });
                }
            } else {
                result.error = QStringLiteral("Could not search the local card catalog.");
            }
    }
    result.cards = enrichLimitedCards(result.cards, nullptr, language);
    return result;
}

CatalogSearchResult CatalogRepository::searchTokens(const QString &text, const QString &language,
                                                    const QString &kind,
                                                    const QStringList &setCodes) const
{
    CatalogSearchResult result;
    if (!ensureOpen(&result.error)) {
        if (result.error.isEmpty())
            result.error = QStringLiteral("Could not open the local token catalog.");
        return result;
    }
    const QSqlDatabase database = QSqlDatabase::database(m_connectionName);
    QString layoutFilter =
        kind == QStringLiteral("emblem") ? QStringLiteral("c.layout = 'emblem'")
        : kind == QStringLiteral("token")
            ? QStringLiteral("c.layout IN ('token', 'double_faced_token')")
            : QStringLiteral("c.layout IN ('token', 'double_faced_token', 'emblem')");
    QStringList tokenSets;
    for (const QString &set : setCodes) {
        const QString code = set.trimmed().toUpper();
        if (!code.isEmpty()) {
            tokenSets.append(code);
            tokenSets.append(QLatin1Char('T') + code);
        }
    }
    tokenSets.removeDuplicates();
    if (!tokenSets.isEmpty()) {
        QStringList placeholders;
        for (qsizetype index = 0; index < tokenSets.size(); ++index)
            placeholders.append(QStringLiteral("?"));
        layoutFilter += QStringLiteral(" AND upper(c.set_code) IN (%1)")
                            .arg(placeholders.join(QLatin1Char(',')));
    }
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
                        {QStringLiteral("kind"), query.value(10).toString()},
                    });
                }
            };

            bool exactResolved = false;
            static const QRegularExpression exactIdentity(QStringLiteral(
                R"(^\s*([A-Za-z0-9]{2,8})\s*(?:#\s*)?([A-Za-z0-9][A-Za-z0-9._+*-]*)\s*$)"));
            const QRegularExpressionMatch exactMatch = exactIdentity.match(text);
            if (exactMatch.hasMatch()) {
                const QString requestedSet = exactMatch.captured(1).toUpper();
                // Try both the exact code and its token-set code, including
                // ordinary expansions whose code itself starts with T.
                const QString tokenSet = QLatin1Char('T') + requestedSet;
                const QString collectorNumber = exactMatch.captured(2);
                QSqlQuery exactQuery(database);
                exactQuery.prepare(
                    QStringLiteral(
                        "SELECT c.name, %1 AS localized_name, %2 AS type_line, "
                        "c.set_code, c.collector_number, c.image_url, %3 AS power, "
                        "%4 AS toughness, %5 AS oracle_text, c.oracle_id, "
                        "CASE WHEN c.layout = 'emblem' THEN 'emblem' ELSE 'token' END AS kind "
                        "FROM cards c WHERE %6 AND c.lang = 'en' "
                        "AND (upper(c.set_code) = ? OR upper(c.set_code) = ?) "
                        "AND (c.collector_number = ? COLLATE NOCASE OR "
                        "ltrim(c.collector_number, '0') = "
                        "ltrim(?, '0') COLLATE NOCASE) "
                        "ORDER BY CASE WHEN upper(c.set_code) = ? THEN 0 ELSE 1 END, "
                        "c.rowid DESC LIMIT 60")
                        .arg(localizedName, localizedType, powerExpression, toughnessExpression,
                             oracleTextExpression, layoutFilter));
                for (const QString &set : tokenSets)
                    exactQuery.addBindValue(set);
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
                        "CASE WHEN c.layout = 'emblem' THEN 'emblem' ELSE 'token' END AS kind, "
                        "row_number() OVER (PARTITION BY "
                        "COALESCE(NULLIF(c.oracle_id, ''), c.name || char(31) || c.set_code || "
                        "char(31) || c.collector_number) ORDER BY c.rowid DESC) choice "
                        "FROM cards c WHERE %6 AND c.lang = 'en' ")
                        .arg(localizedName, localizedType, powerExpression, toughnessExpression,
                             oracleTextExpression, layoutFilter);
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
                    "image_url, power, toughness, oracle_text, oracle_id, kind "
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
                for (const QString &set : tokenSets)
                    query.addBindValue(set);
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
