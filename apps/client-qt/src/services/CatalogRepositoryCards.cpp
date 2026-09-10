// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "CardCatalogCommon.h"
#include "CardCatalogQueryInternal.h"
#include "CatalogRepository.h"

#include <QSqlDatabase>
#include <QSqlError>
#include <QSqlQuery>

namespace hexproof::client {

using namespace catalog_internal;

QVariantList CatalogRepository::printings(const QString &name, const QString &language,
                                          QString *error) const
{
    QVariantList result;
    if (!installed() || name.simplified().isEmpty())
        return result;

    struct PrintingChoice
    {
        QVariantMap data;
        int languageScore = -1;
    };
    QHash<QString, PrintingChoice> choices;
    QStringList order;
    if (!ensureOpen(error))
        return result;
    const QSqlDatabase database = QSqlDatabase::database(m_connectionName);
    const bool hasAliases = m_schema.hasAliases;
    const QString localizedExpression = hasAliases ? localizedNameExpression(QStringLiteral("c"))
                                                   : QStringLiteral("c.printed_name");
    const QString typeExpression = language == QStringLiteral("zh") && hasAliases
                                       ? localizedTypeExpression(QStringLiteral("c"))
                                       : QStringLiteral("c.type_line");
    QSqlQuery query(database);
    query.prepare(
        QStringLiteral("SELECT c.name, %1, %2, c.set_code, c.collector_number, "
                       "c.image_url, c.lang FROM cards c WHERE %3 AND %4 "
                       "ORDER BY c.set_code COLLATE NOCASE, c.collector_number COLLATE NOCASE")
            .arg(localizedExpression, typeExpression, catalogNameMatchesSql(),
                 catalogPlayablePrintingSql()));
    const QString cardName = name.simplified();
    query.addBindValue(cardName);
    query.addBindValue(cardName);
    query.addBindValue(cardName);
    if (!query.exec()) {
        if (error) {
            *error = query.lastError().text().isEmpty()
                         ? QStringLiteral("Could not read card printings.")
                         : query.lastError().text();
        }
        return result;
    }
    while (query.next()) {
        const QString setCode = query.value(3).toString().toUpper();
        const QString collectorNumber = query.value(4).toString();
        const QString key = setCode + QChar(0x1f) + collectorNumber;
        const QString rowLanguage = query.value(6).toString().toLower();
        const int languageScore = language == QStringLiteral("zh")
                                      ? (rowLanguage == QStringLiteral("zhs")
                                             ? 2
                                             : (rowLanguage == QStringLiteral("en") ? 1 : 0))
                                      : (rowLanguage == QStringLiteral("en") ? 2 : 0);
        if (choices.contains(key) && choices.value(key).languageScore >= languageScore)
            continue;
        QString displayName = language == QStringLiteral("zh") ? query.value(1).toString()
                                                               : query.value(0).toString();
        if (displayName.isEmpty())
            displayName = query.value(0).toString();
        choices.insert(key, PrintingChoice{
                                QVariantMap{
                                    {QStringLiteral("name"), query.value(0).toString()},
                                    {QStringLiteral("displayName"), displayName},
                                    {QStringLiteral("typeLine"), query.value(2).toString()},
                                    {QStringLiteral("setCode"), setCode},
                                    {QStringLiteral("collectorNumber"), collectorNumber},
                                    {QStringLiteral("imageUrl"), query.value(5).toString()},
                                },
                                languageScore,
                            });
        if (!order.contains(key))
            order.append(key);
    }
    for (const QString &key : std::as_const(order))
        result.append(choices.value(key).data);
    return result;
}

QVariantList CatalogRepository::cardFaces(const QString &name, const QString &setCode,
                                          const QString &collectorNumber, QString *error,
                                          QString *resolvedLayout,
                                          QString *resolvedCanonicalName) const
{
    QVariantList result;
    if (resolvedLayout)
        resolvedLayout->clear();
    if (resolvedCanonicalName)
        resolvedCanonicalName->clear();
    if (!installed() || name.simplified().isEmpty())
        return result;

    QString cardName;
    QString layout;
    QString typeLine;
    if (!ensureOpen(error))
        return result;
    const QSqlDatabase database = QSqlDatabase::database(m_connectionName);
    QSqlQuery query(database);
    const QString relatedColumn = m_schema.cardColumns.contains(QStringLiteral("related_cards"))
                                      ? QStringLiteral("related_cards")
                                      : QStringLiteral("''");
    const QString select = QStringLiteral("SELECT name, layout, type_line, set_code, "
                                          "collector_number, %1 FROM cards ")
                               .arg(relatedColumn);
    if (!setCode.isEmpty() && !collectorNumber.isEmpty()) {
        query.prepare(select +
                      QStringLiteral("WHERE %1 "
                                     "ORDER BY CASE WHEN lang = 'en' THEN 0 ELSE 1 END LIMIT 1")
                          .arg(catalogExactPrintingSql(QString{})));
        query.addBindValue(setCode);
        query.addBindValue(collectorNumber);
    } else {
        query.prepare(
            select + QStringLiteral(
                         "WHERE %1 "
                         "ORDER BY CASE WHEN name = ? COLLATE NOCASE THEN 0 ELSE 1 END, "
                         "CASE WHEN layout IN ('art_series','token','double_faced_token','emblem') "
                         "THEN 1 ELSE 0 END, CASE WHEN lang = 'en' THEN 0 ELSE 1 END LIMIT 1")
                         .arg(catalogNameMatchesSql(QString{})));
        const QString cardName = name.simplified();
        query.addBindValue(cardName);
        query.addBindValue(cardName);
        query.addBindValue(cardName);
        query.addBindValue(cardName);
    }
    if (!query.exec()) {
        if (error) {
            *error = query.lastError().text().isEmpty()
                         ? QStringLiteral("Could not read card faces.")
                         : query.lastError().text();
        }
        return result;
    }
    if (query.next()) {
        cardName = query.value(0).toString();
        layout = query.value(1).toString();
        typeLine = query.value(2).toString();
    }
    if (resolvedLayout)
        *resolvedLayout = layout;
    if (resolvedCanonicalName)
        *resolvedCanonicalName = cardName;

    if (layout == QStringLiteral("meld")) {
        const QString resolvedSet = query.value(3).toString();
        const QString resolvedCollector = query.value(4).toString();
        const QJsonArray related =
            QJsonDocument::fromJson(query.value(5).toString().toUtf8()).array();
        for (const QJsonValue &value : related) {
            const QJsonObject part = value.toObject();
            const QString resultName = part.value(QStringLiteral("name")).toString();
            if (part.value(QStringLiteral("component")).toString() !=
                    QStringLiteral("meld_result") ||
                resultName.isEmpty() || resultName == cardName)
                continue;
            QSqlQuery target(database);
            const QString targetSelect =
                QStringLiteral("SELECT name, type_line, set_code, collector_number FROM cards ");
            const QString id = part.value(QStringLiteral("id")).toString();
            bool foundTarget = false;
            if (!id.isEmpty()) {
                // Prefer the related printing's primary key without also
                // collecting every localized/name fallback candidate.
                target.prepare(targetSelect + QStringLiteral("WHERE id = ? LIMIT 1"));
                target.addBindValue(id);
                foundTarget = target.exec() && target.next();
            }
            if (!foundTarget) {
                target.prepare(targetSelect +
                               QStringLiteral("WHERE name = ? COLLATE NOCASE "
                                              "AND set_code = ? COLLATE NOCASE "
                                              "ORDER BY CASE WHEN lang = 'en' THEN 0 ELSE 1 END "
                                              "LIMIT 1"));
                target.addBindValue(resultName);
                target.addBindValue(resolvedSet);
                if (!target.exec() || !target.next())
                    continue;
            }
            result.append(QVariantMap{{QStringLiteral("name"), cardName},
                                      {QStringLiteral("faceName"), QString{}},
                                      {QStringLiteral("displayName"), cardName},
                                      {QStringLiteral("typeLine"), typeLine},
                                      {QStringLiteral("setCode"), resolvedSet},
                                      {QStringLiteral("collectorNumber"), resolvedCollector}});
            result.append(QVariantMap{{QStringLiteral("name"), target.value(0)},
                                      {QStringLiteral("faceName"), target.value(0)},
                                      {QStringLiteral("displayName"), target.value(0)},
                                      {QStringLiteral("typeLine"), target.value(1)},
                                      {QStringLiteral("setCode"), target.value(2)},
                                      {QStringLiteral("collectorNumber"), target.value(3)},
                                      {QStringLiteral("relatedCard"), true}});
            return result;
        }
        return {};
    }

    static const QSet<QString> doubleFacedLayouts{
        QStringLiteral("transform"),
        QStringLiteral("modal_dfc"),
        QStringLiteral("double_faced_token"),
        QStringLiteral("reversible_card"),
    };
    if (!doubleFacedLayouts.contains(layout))
        return result;
    const QStringList names = cardName.split(QStringLiteral(" // "), Qt::SkipEmptyParts);
    if (names.size() != 2)
        return result;
    const QStringList typeLines = typeLine.split(QStringLiteral(" // "), Qt::KeepEmptyParts);
    const QString frontTypeLine =
        typeLines.size() == names.size() ? typeLines.at(0).simplified() : QString{};
    const QString backTypeLine =
        typeLines.size() == names.size() ? typeLines.at(1).simplified() : QString{};
    // Same-named double-faced tokens still have two independently selectable
    // images. Keep their whole identity for the front and explicit face for back.
    const QString frontRequestName = names.at(0).compare(names.at(1), Qt::CaseInsensitive) == 0
                                         ? cardName
                                         : names.at(0).simplified();
    result.append(QVariantMap{
        {QStringLiteral("name"), frontRequestName},
        {QStringLiteral("faceName"), QString{}},
        {QStringLiteral("displayName"), names.at(0).simplified()},
        {QStringLiteral("typeLine"), frontTypeLine},
        {QStringLiteral("setCode"), setCode.toUpper()},
        {QStringLiteral("collectorNumber"), collectorNumber},
    });
    result.append(QVariantMap{
        {QStringLiteral("name"), names.at(1).simplified()},
        {QStringLiteral("faceName"), names.at(1).simplified()},
        {QStringLiteral("displayName"), names.at(1).simplified()},
        {QStringLiteral("typeLine"), backTypeLine},
        {QStringLiteral("setCode"), setCode.toUpper()},
        {QStringLiteral("collectorNumber"), collectorNumber},
    });
    return result;
}

} // namespace hexproof::client
