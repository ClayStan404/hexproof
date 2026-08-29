// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "DeckLegalityService.h"

#include "ApplicationPaths.h"
#include "deck/DeckFormat.h"
#include "services/BackgroundTaskPools.h"
#include "services/CardCatalogCommon.h"
#include "services/CatalogStorage.h"

#include <QDir>
#include <QFileInfo>
#include <QReadLocker>
#include <QSet>
#include <QSqlDatabase>
#include <QSqlQuery>
#include <QUuid>
#include <QtConcurrent>

#include <algorithm>
#include <utility>

namespace hexproof::client {

namespace {

struct CatalogCard
{
    bool found = false;
    QString oracleId;
    QString name;
    QString typeLine;
    QString colors;
    QString oracleText;
    QString legalityStatuses;
};

QString normalizedName(const QString &name)
{
    return name.simplified().toCaseFolded();
}

QString formatName(const QString &format)
{
    const QString normalized = normalizedDeckFormat(format);
    if (normalized == QString::fromLatin1(kDeckFormatDuel))
        return QStringLiteral("Duel Commander");
    if (normalized == QString::fromLatin1(kDeckFormatCommander))
        return QStringLiteral("Commander");
    if (normalized == QString::fromLatin1(kDeckFormatPauper))
        return QStringLiteral("Pauper");
    if (normalized == QString::fromLatin1(kDeckFormatVintage))
        return QStringLiteral("Vintage");
    if (normalized == QString::fromLatin1(kDeckFormatLegacy))
        return QStringLiteral("Legacy");
    if (normalized == QString::fromLatin1(kDeckFormatModern))
        return QStringLiteral("Modern");
    if (normalized == QString::fromLatin1(kDeckFormatPioneer))
        return QStringLiteral("Pioneer");
    if (normalized == QString::fromLatin1(kDeckFormatStandard))
        return QStringLiteral("Standard");
    return QStringLiteral("Custom");
}

QString legalityStatus(const QString &statuses, const QString &format)
{
    const QString marker = QLatin1Char('|') + normalizedDeckFormat(format) + QLatin1Char(':');
    const qsizetype begin = statuses.indexOf(marker, 0, Qt::CaseInsensitive);
    if (begin < 0)
        return {};
    const qsizetype valueBegin = begin + marker.size();
    const qsizetype end = statuses.indexOf(QLatin1Char('|'), valueBegin);
    return statuses.mid(valueBegin, end < 0 ? -1 : end - valueBegin).toLower();
}

bool hasDeckLimitException(const CatalogCard &card)
{
    return (card.typeLine.contains(QStringLiteral("Basic"), Qt::CaseInsensitive) &&
            card.typeLine.contains(QStringLiteral("Land"), Qt::CaseInsensitive)) ||
           card.oracleText.contains(QStringLiteral("A deck can have"), Qt::CaseInsensitive);
}

bool colorIdentityContains(const QString &commanderColors, const QString &cardColors)
{
    return std::all_of(cardColors.cbegin(), cardColors.cend(), [&commanderColors](QChar color) {
        return commanderColors.contains(color, Qt::CaseInsensitive);
    });
}

CatalogCard readCard(QSqlDatabase &database, const QVariantMap &card)
{
    QSqlQuery query(database);
    const auto readResult = [&query]() {
        if (!query.exec() || !query.next())
            return CatalogCard{};
        return CatalogCard{true,
                           query.value(0).toString(),
                           query.value(1).toString(),
                           query.value(2).toString(),
                           query.value(3).toString(),
                           query.value(4).toString(),
                           query.value(5).toString()};
    };
    const QString select = QStringLiteral(
        "SELECT oracle_id, name, type_line, colors, oracle_text, legality_statuses FROM cards ");
    const QString resultOrder = QStringLiteral(
        "ORDER BY CASE WHEN layout IN ('art_series','token','double_faced_token','emblem') "
        "THEN 1 ELSE 0 END, digital ASC, lang = 'en' DESC LIMIT 1");
    const QString name = card.value(QStringLiteral("name")).toString();
    query.prepare(select + QStringLiteral("WHERE name = ? COLLATE NOCASE ") + resultOrder);
    query.addBindValue(name);
    if (const CatalogCard result = readResult(); result.found)
        return result;

    const QString setCode = card.value(QStringLiteral("setCode")).toString();
    const QString collectorNumber = card.value(QStringLiteral("collectorNumber")).toString();
    if (!setCode.isEmpty() && !collectorNumber.isEmpty()) {
        query.prepare(select +
                      QStringLiteral("WHERE set_code = ? COLLATE NOCASE AND "
                                     "(collector_number = ? COLLATE NOCASE OR "
                                     "ltrim(collector_number, '0') = ltrim(?, '0')) ") +
                      resultOrder);
        query.addBindValue(setCode);
        query.addBindValue(collectorNumber);
        query.addBindValue(collectorNumber);
        if (const CatalogCard result = readResult(); result.found)
            return result;
    }

    query.prepare(select +
                  QStringLiteral("WHERE instr(name, ' // ') > 0 AND ("
                                 "substr(name, 1, instr(name, ' // ') - 1) = ? COLLATE NOCASE "
                                 "OR substr(name, instr(name, ' // ') + 4) = ? COLLATE NOCASE) ") +
                  resultOrder);
    query.addBindValue(name);
    query.addBindValue(name);
    return readResult();
}

QVariantMap validateOne(QSqlDatabase *database, bool catalogCurrent, const QVariantMap &deck)
{
    const QString deckId = deck.value(QStringLiteral("deckId")).toString();
    const quint64 validationRevision =
        deck.value(QStringLiteral("validationRevision")).toULongLong();
    const QString format =
        normalizedDeckFormat(deck.value(QStringLiteral("deckFormat")).toString());
    const QVariantList mainboard = deck.value(QStringLiteral("mainboard")).toList();
    const QVariantList sideboard = deck.value(QStringLiteral("sideboard")).toList();
    const QStringList commanders = deck.value(QStringLiteral("commanders")).toStringList();
    QStringList errors;

    const auto countCards = [](const QVariantList &cards) {
        int count = 0;
        for (const QVariant &entry : cards)
            count += std::max(0, entry.toMap().value(QStringLiteral("count")).toInt());
        return count;
    };
    const int mainCount = countCards(mainboard);
    const int sideboardCount = countCards(sideboard);
    const bool commanderFormat = format == QString::fromLatin1(kDeckFormatDuel) ||
                                 format == QString::fromLatin1(kDeckFormatCommander);

    if (format == QString::fromLatin1(kDeckFormatCustom)) {
        return {{QStringLiteral("deckId"), deckId},
                {QStringLiteral("validationRevision"), validationRevision},
                {QStringLiteral("valid"), true},
                {QStringLiteral("verified"), true},
                {QStringLiteral("status"), QStringLiteral("Playable")},
                {QStringLiteral("issues"), QStringList{}},
                {QStringLiteral("warnings"), QStringList{}}};
    }

    if (commanderFormat) {
        if (mainCount != 100)
            errors.append(QStringLiteral("Commander decks require exactly 100 main-deck cards."));
        if (sideboardCount != 0)
            errors.append(QStringLiteral("Commander decks cannot use a sideboard."));
        if (commanders.isEmpty() || commanders.size() > 2)
            errors.append(QStringLiteral("Commander decks require one or two commanders."));
    } else {
        if (mainCount < 60)
            errors.append(QStringLiteral("Main deck requires at least 60 cards."));
        if (sideboardCount > 15)
            errors.append(QStringLiteral("Sideboard can contain at most 15 cards."));
    }

    const bool structureValid = errors.isEmpty();
    if (!catalogCurrent || !database) {
        if (errors.isEmpty())
            errors.append(QStringLiteral("Card database required to verify deck legality."));
        return {{QStringLiteral("deckId"), deckId},
                {QStringLiteral("validationRevision"), validationRevision},
                {QStringLiteral("valid"), structureValid},
                {QStringLiteral("verified"), false},
                {QStringLiteral("status"), errors.first()},
                {QStringLiteral("issues"), errors},
                {QStringLiteral("warnings"), QStringList{}}};
    }

    QHash<QString, int> copies;
    QHash<QString, CatalogCard> catalogCards;
    QHash<QString, CatalogCard> namedCatalogCards;
    QHash<QString, QString> displayNames;
    const auto inspectCards = [&](const QVariantList &cards) {
        for (const QVariant &entry : cards) {
            const QVariantMap card = entry.toMap();
            const QString name = card.value(QStringLiteral("name")).toString();
            const QString nameKey = normalizedName(name);
            const CatalogCard catalogCard = readCard(*database, card);
            const QString identityKey = catalogCard.found && !catalogCard.oracleId.isEmpty()
                                            ? catalogCard.oracleId
                                            : nameKey;
            copies[identityKey] += std::max(0, card.value(QStringLiteral("count")).toInt());
            if (!displayNames.contains(identityKey))
                displayNames.insert(identityKey, name);
            catalogCards.insert(identityKey, catalogCard);
            namedCatalogCards.insert(nameKey, catalogCard);
        }
    };
    inspectCards(mainboard);
    inspectCards(sideboard);

    QString commanderColors;
    bool commanderIdentityVerified = true;
    for (const QString &commander : commanders) {
        const CatalogCard card = namedCatalogCards.value(normalizedName(commander));
        if (!card.found) {
            commanderIdentityVerified = false;
            continue;
        }
        for (const QChar color : card.colors) {
            if (!commanderColors.contains(color, Qt::CaseInsensitive))
                commanderColors.append(color);
        }
    }

    QStringList identities = copies.keys();
    identities.sort(Qt::CaseInsensitive);
    QStringList colorIdentityCardNames;
    for (const QString &identity : std::as_const(identities)) {
        const CatalogCard card = catalogCards.value(identity);
        const QString displayName = card.name.isEmpty() ? displayNames.value(identity) : card.name;
        const int copyCount = copies.value(identity);
        if (!card.found) {
            errors.append(
                QStringLiteral("%1 is missing from the local card database.").arg(displayName));
            continue;
        }
        const QString status = legalityStatus(card.legalityStatuses, format);
        if (status != QStringLiteral("legal") && status != QStringLiteral("restricted")) {
            errors.append(
                QStringLiteral("%1 is not legal in %2.").arg(displayName, formatName(format)));
        }
        if (status == QStringLiteral("restricted") && copyCount > 1) {
            errors.append(
                QStringLiteral("%1 is restricted to one copy in Vintage.").arg(displayName));
        } else if (commanderFormat && copyCount > 1 && !hasDeckLimitException(card)) {
            errors.append(QStringLiteral("%1 has %2 copies; commander formats are singleton.")
                              .arg(displayName)
                              .arg(copyCount));
        } else if (!commanderFormat && copyCount > 4 && !hasDeckLimitException(card)) {
            errors.append(QStringLiteral("%1 has %2 copies; this format allows at most four.")
                              .arg(displayName)
                              .arg(copyCount));
        }
        if (commanderFormat && !commanders.isEmpty() && commanderIdentityVerified &&
            !colorIdentityContains(commanderColors, card.colors)) {
            colorIdentityCardNames.append(displayName);
        }
    }

    colorIdentityCardNames.sort(Qt::CaseInsensitive);
    QStringList warnings;
    QStringList warningDetails;
    if (!colorIdentityCardNames.isEmpty()) {
        const int count = colorIdentityCardNames.size();
        warnings.append(
            count == 1 ? QStringLiteral("1 card may be outside the commanders' color identity.")
                       : QStringLiteral("%1 cards may be outside the commanders' color identity.")
                             .arg(count));
        for (const QString &name : std::as_const(colorIdentityCardNames)) {
            warningDetails.append(
                QStringLiteral("%1 is outside the commanders' color identity.").arg(name));
        }
    }
    QStringList issues = errors;
    issues.append(warnings);
    issues.append(warningDetails);
    const QString status = !errors.isEmpty()     ? errors.first()
                           : !warnings.isEmpty() ? warnings.first()
                                                 : QStringLiteral("Playable");
    return {{QStringLiteral("deckId"), deckId},
            {QStringLiteral("validationRevision"), validationRevision},
            {QStringLiteral("valid"), errors.isEmpty()},
            {QStringLiteral("verified"), true},
            {QStringLiteral("status"), status},
            {QStringLiteral("issues"), issues},
            {QStringLiteral("warnings"), warnings}};
}

} // namespace

DeckLegalityService::DeckLegalityService(QObject *parent)
    : DeckLegalityService(defaultStorageRoot(), parent)
{
}

DeckLegalityService::DeckLegalityService(const QString &storageRoot, QObject *parent)
    : QObject(parent),
      m_databasePath(QDir(storageRoot).filePath(QStringLiteral("cards.sqlite")))
{
    connect(&m_watcher, &QFutureWatcher<QVariantList>::finished, this,
            &DeckLegalityService::finishValidation);
}

DeckLegalityService::~DeckLegalityService()
{
    if (m_watcher.isRunning())
        m_watcher.waitForFinished();
}

QVariantList DeckLegalityService::validate(const QString &databasePath, const QVariantList &decks)
{
    QReadLocker databaseLocker(&catalogstorage::databaseLock());
    const QString connectionName = QStringLiteral("hexproof-deck-legality-") +
                                   QUuid::createUuid().toString(QUuid::WithoutBraces);
    bool catalogCurrent = false;
    QVariantList results;
    {
        QSqlDatabase database;
        if (QFileInfo(databasePath).isFile()) {
            database = QSqlDatabase::addDatabase(QStringLiteral("QSQLITE"), connectionName);
            database.setDatabaseName(databasePath);
            if (database.open()) {
                QSqlQuery query(database);
                query.prepare(QStringLiteral(
                    "SELECT value FROM metadata WHERE key = 'schema_version' LIMIT 1"));
                catalogCurrent = query.exec() && query.next() &&
                                 query.value(0).toInt() == catalog_internal::kCatalogIndexVersion;
            }
        }
        results.reserve(decks.size());
        for (const QVariant &entry : decks)
            results.append(validateOne(database.isOpen() ? &database : nullptr, catalogCurrent,
                                       entry.toMap()));
        if (database.isOpen())
            database.close();
    }
    if (QSqlDatabase::contains(connectionName))
        QSqlDatabase::removeDatabase(connectionName);
    return results;
}

void DeckLegalityService::validateDecks(const QVariantList &decks)
{
    m_latestDecks = decks;
    ++m_generation;
    if (!m_watcher.isRunning())
        startLatestValidation();
}

void DeckLegalityService::startLatestValidation()
{
    m_runningGeneration = m_generation;
    const QString databasePath = m_databasePath;
    const QVariantList decks = m_latestDecks;
    m_watcher.setFuture(
        QtConcurrent::run(BackgroundTaskPools::catalogMaintenance(), [databasePath, decks]() {
            return DeckLegalityService::validate(databasePath, decks);
        }));
}

void DeckLegalityService::finishValidation()
{
    if (m_runningGeneration == m_generation)
        emit validationReady(m_watcher.result());
    if (m_runningGeneration != m_generation)
        startLatestValidation();
}

} // namespace hexproof::client
