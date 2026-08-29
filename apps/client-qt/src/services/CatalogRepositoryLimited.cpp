// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "CatalogRepository.h"

#include <QHash>
#include <QJsonDocument>
#include <QJsonObject>
#include <QSet>
#include <QSqlDatabase>
#include <QSqlError>
#include <QSqlQuery>

namespace hexproof::client {

namespace {
bool hasTable(const QSqlDatabase &database, const QString &name)
{
    QSqlQuery query(database);
    query.prepare(QStringLiteral("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?"));
    query.addBindValue(name);
    return query.exec() && query.next();
}

QVariantMap cardFromQuery(const QSqlQuery &query, int weight)
{
    return QVariantMap{{QStringLiteral("name"), query.value(0).toString()},
                       {QStringLiteral("setCode"), query.value(1).toString().toUpper()},
                       {QStringLiteral("collectorNumber"), query.value(2).toString()},
                       {QStringLiteral("typeLine"), query.value(3).toString()},
                       {QStringLiteral("rarity"), query.value(4).toString().toLower()},
                       {QStringLiteral("finish"), QStringLiteral("nonfoil")},
                       {QStringLiteral("weight"), weight}};
}
} // namespace

QVariantList CatalogRepository::limitedProducts(QString *error) const
{
    if (!ensureOpen(error))
        return {};
    const QSqlDatabase database = QSqlDatabase::database(m_connectionName);
    QVariantList result;
    QSet<QString> exactSetCodes;
    if (hasTable(database, QStringLiteral("limited_products"))) {
        QSqlQuery query(database);
        if (!query.exec(QStringLiteral("SELECT id, name, set_code, product_type, authentic "
                                       "FROM limited_products ORDER BY set_code, name"))) {
            if (error)
                *error = query.lastError().text();
            return {};
        }
        while (query.next()) {
            result.append(QVariantMap{{QStringLiteral("id"), query.value(0).toString()},
                                      {QStringLiteral("name"), query.value(1).toString()},
                                      {QStringLiteral("setCode"), query.value(2).toString()},
                                      {QStringLiteral("productType"), query.value(3).toString()},
                                      {QStringLiteral("authentic"), query.value(4).toBool()}});
            exactSetCodes.insert(query.value(2).toString().toUpper());
        }
    }

    const bool hasBoosterColumn = m_schema.cardColumns.contains(QStringLiteral("booster"));
    QSqlQuery query(database);
    QString statement = QStringLiteral(
        "SELECT upper(set_code), count(*) FROM cards WHERE digital = 0 AND lang = 'en' "
        "AND rarity IN ('common','uncommon','rare','mythic') ");
    if (hasBoosterColumn)
        statement += QStringLiteral("AND booster = 1 ");
    statement += QStringLiteral("GROUP BY upper(set_code) HAVING count(*) >= 30 ORDER BY 1 DESC");
    if (!query.exec(statement)) {
        if (!result.isEmpty())
            return result;
        if (error)
            *error = query.lastError().text();
        return {};
    }
    while (query.next()) {
        const QString setCode = query.value(0).toString();
        if (exactSetCodes.contains(setCode))
            continue;
        result.append(QVariantMap{
            {QStringLiteral("id"), QStringLiteral("approx-") + setCode.toLower()},
            {QStringLiteral("name"), setCode + QStringLiteral(" approximate booster")},
            {QStringLiteral("setCode"), setCode},
            {QStringLiteral("productType"), QStringLiteral("approximate")},
            {QStringLiteral("authentic"), false},
        });
    }
    return result;
}

QVariantMap CatalogRepository::limitedProduct(const QString &productId, QString *error) const
{
    if (!ensureOpen(error))
        return {};
    const QSqlDatabase database = QSqlDatabase::database(m_connectionName);
    if (hasTable(database, QStringLiteral("limited_products"))) {
        QSqlQuery query(database);
        query.prepare(QStringLiteral("SELECT definition_json FROM limited_products WHERE id = ?"));
        query.addBindValue(productId);
        if (query.exec() && query.next()) {
            QJsonParseError parseError;
            const QJsonDocument document =
                QJsonDocument::fromJson(query.value(0).toByteArray(), &parseError);
            if (parseError.error == QJsonParseError::NoError && document.isObject())
                return document.object().toVariantMap();
            if (error)
                *error = QStringLiteral("The limited product definition is invalid.");
            return {};
        }
    }

    const QString prefix = QStringLiteral("approx-");
    if (!productId.startsWith(prefix)) {
        if (error)
            *error = QStringLiteral("The limited product is not installed.");
        return {};
    }
    const QString setCode = productId.mid(prefix.size()).toUpper();
    QVariantList commonCards;
    QVariantList uncommonCards;
    QVariantList rareCards;
    QSqlQuery query(database);
    QString statement =
        QStringLiteral("SELECT name, set_code, collector_number, type_line, rarity FROM cards "
                       "WHERE upper(set_code) = ? AND digital = 0 AND lang = 'en' "
                       "AND rarity IN ('common','uncommon','rare','mythic') ");
    if (m_schema.cardColumns.contains(QStringLiteral("booster")))
        statement += QStringLiteral("AND booster = 1 ");
    statement += QStringLiteral("ORDER BY collector_number");
    query.prepare(statement);
    query.addBindValue(setCode);
    if (!query.exec()) {
        if (error)
            *error = query.lastError().text();
        return {};
    }
    while (query.next()) {
        const QString rarity = query.value(4).toString().toLower();
        if (rarity == QStringLiteral("common"))
            commonCards.append(cardFromQuery(query, 1));
        else if (rarity == QStringLiteral("uncommon"))
            uncommonCards.append(cardFromQuery(query, 1));
        else
            rareCards.append(cardFromQuery(query, rarity == QStringLiteral("mythic") ? 1 : 7));
    }
    if (commonCards.size() < 10 || uncommonCards.size() < 3 || rareCards.isEmpty()) {
        if (error)
            *error = QStringLiteral("The set does not contain enough booster-eligible cards.");
        return {};
    }
    const QVariantList sheets{
        QVariantMap{{QStringLiteral("name"), QStringLiteral("common")},
                    {QStringLiteral("withReplacement"), false},
                    {QStringLiteral("cards"), commonCards}},
        QVariantMap{{QStringLiteral("name"), QStringLiteral("uncommon")},
                    {QStringLiteral("withReplacement"), false},
                    {QStringLiteral("cards"), uncommonCards}},
        QVariantMap{{QStringLiteral("name"), QStringLiteral("rare")},
                    {QStringLiteral("withReplacement"), false},
                    {QStringLiteral("cards"), rareCards}},
    };
    const QVariantList packSlots{
        QVariantMap{{QStringLiteral("sheet"), QStringLiteral("common")},
                    {QStringLiteral("count"), 10}},
        QVariantMap{{QStringLiteral("sheet"), QStringLiteral("uncommon")},
                    {QStringLiteral("count"), 3}},
        QVariantMap{{QStringLiteral("sheet"), QStringLiteral("rare")},
                    {QStringLiteral("count"), 1}},
    };
    return QVariantMap{
        {QStringLiteral("id"), productId},
        {QStringLiteral("name"), setCode + QStringLiteral(" approximate booster")},
        {QStringLiteral("setCode"), setCode},
        {QStringLiteral("productType"), QStringLiteral("approximate")},
        {QStringLiteral("authentic"), false},
        {QStringLiteral("cardsPerPack"), 14},
        {QStringLiteral("sheets"), sheets},
        {QStringLiteral("variants"),
         QVariantList{
             QVariantMap{{QStringLiteral("weight"), 1}, {QStringLiteral("slots"), packSlots}}}},
    };
}

QVariantList CatalogRepository::enrichLimitedCards(const QVariantList &cards, QString *error) const
{
    if (cards.isEmpty() || !ensureOpen(error))
        return cards;
    if (!m_schema.cardColumns.contains(QStringLiteral("type_line")) ||
        !m_schema.cardColumns.contains(QStringLiteral("set_code")) ||
        !m_schema.cardColumns.contains(QStringLiteral("collector_number"))) {
        return cards;
    }

    const bool hasColors = m_schema.cardColumns.contains(QStringLiteral("colors"));
    const bool hasManaValue = m_schema.cardColumns.contains(QStringLiteral("mana_value"));
    const bool hasLanguage = m_schema.cardColumns.contains(QStringLiteral("lang"));
    QStringList columns{QStringLiteral("type_line")};
    if (hasColors)
        columns.append(QStringLiteral("colors"));
    if (hasManaValue)
        columns.append(QStringLiteral("mana_value"));

    QString statement = QStringLiteral("SELECT %1 FROM cards WHERE set_code = ? COLLATE NOCASE "
                                       "AND collector_number = ? COLLATE NOCASE")
                            .arg(columns.join(QStringLiteral(", ")));
    if (hasLanguage)
        statement += QStringLiteral(" ORDER BY CASE WHEN lang = 'en' THEN 0 ELSE 1 END");
    statement += QStringLiteral(" LIMIT 1");

    const QSqlDatabase database = QSqlDatabase::database(m_connectionName);
    QSqlQuery query(database);
    if (!query.prepare(statement)) {
        if (error)
            *error = query.lastError().text();
        return cards;
    }

    QVariantList result;
    result.reserve(cards.size());
    QHash<QString, QVariantMap> metadataByPrinting;
    for (const QVariant &value : cards) {
        QVariantMap card = value.toMap();
        const QString setCode = card.value(QStringLiteral("setCode")).toString().trimmed();
        const QString collectorNumber =
            card.value(QStringLiteral("collectorNumber")).toString().trimmed();
        const QString key = setCode.toUpper() + QLatin1Char('/') + collectorNumber.toLower();

        QVariantMap metadata;
        if (!setCode.isEmpty() && !collectorNumber.isEmpty()) {
            const auto cached = metadataByPrinting.constFind(key);
            if (cached != metadataByPrinting.cend()) {
                metadata = cached.value();
            } else {
                query.bindValue(0, setCode);
                query.bindValue(1, collectorNumber);
                if (query.exec() && query.next()) {
                    int column = 0;
                    metadata.insert(QStringLiteral("typeLine"), query.value(column++).toString());
                    if (hasColors)
                        metadata.insert(QStringLiteral("colors"),
                                        query.value(column++).toString().toUpper());
                    if (hasManaValue && !query.value(column).isNull())
                        metadata.insert(QStringLiteral("manaValue"),
                                        query.value(column).toDouble());
                    metadata.insert(QStringLiteral("limitedMetadataResolved"), true);
                }
                metadataByPrinting.insert(key, metadata);
            }
        }

        if (!metadata.isEmpty()) {
            if (card.value(QStringLiteral("typeLine")).toString().isEmpty())
                card.insert(QStringLiteral("typeLine"), metadata.value(QStringLiteral("typeLine")));
            if (metadata.contains(QStringLiteral("colors")))
                card.insert(QStringLiteral("colors"), metadata.value(QStringLiteral("colors")));
            if (metadata.contains(QStringLiteral("manaValue")))
                card.insert(QStringLiteral("manaValue"),
                            metadata.value(QStringLiteral("manaValue")));
            card.insert(QStringLiteral("limitedMetadataResolved"), true);
        }
        result.append(card);
    }
    return result;
}

} // namespace hexproof::client
