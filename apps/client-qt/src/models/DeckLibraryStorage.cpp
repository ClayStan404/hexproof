// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "DeckLibraryStorage.h"

#include "deck/DeckFormat.h"

#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QHash>
#include <QJsonArray>
#include <QJsonDocument>
#include <QMutex>
#include <QMutexLocker>
#include <QSaveFile>
#include <QSet>

#include <algorithm>
#include <cmath>
#include <utility>

namespace hexproof::client {

namespace {

qreal normalizedInterfaceScale(qreal scale)
{
    if (!std::isfinite(scale))
        return 1.0;
    return std::clamp(std::round(scale * 20.0) / 20.0, 0.75, 1.5);
}

qreal normalizedTableCardScale(qreal scale)
{
    if (!std::isfinite(scale) || scale <= 0.0)
        return 0.0;
    return std::clamp(std::round(scale * 20.0) / 20.0, 0.5, 1.25);
}

qreal normalizedTableControlPosition(qreal position)
{
    if (!std::isfinite(position) || position < 0.0)
        return -1.0;
    return std::clamp(position, 0.0, 1.0);
}

bool validCards(const QJsonValue &value)
{
    if (!value.isArray())
        return false;
    for (const QJsonValue &cardValue : value.toArray()) {
        if (!cardValue.isObject())
            return false;
        const QJsonObject card = cardValue.toObject();
        if (card.value(QStringLiteral("name")).toString().simplified().isEmpty() ||
            !card.value(QStringLiteral("count")).isDouble() ||
            card.value(QStringLiteral("count")).toInt() <= 0) {
            return false;
        }
    }
    return true;
}

bool validTokens(const QJsonValue &value)
{
    if (value.isUndefined())
        return true;
    if (!value.isArray())
        return false;
    QSet<QString> identities;
    for (const QJsonValue &tokenValue : value.toArray()) {
        if (!tokenValue.isObject())
            return false;
        const QJsonObject token = tokenValue.toObject();
        const QString name = token.value(QStringLiteral("name")).toString().simplified();
        const QString setCode = token.value(QStringLiteral("setCode")).toString().toUpper();
        const QString collectorNumber = token.value(QStringLiteral("collectorNumber")).toString();
        if (name.isEmpty() || setCode.isEmpty() || collectorNumber.isEmpty())
            return false;
        const QString identity =
            normalizedCardName(name) + QChar(0x1f) + setCode + QChar(0x1f) + collectorNumber;
        if (identities.contains(identity))
            return false;
        identities.insert(identity);
    }
    return true;
}

} // namespace

DeckLibraryStorage::DeckLibraryStorage(const QString &storageRoot)
    : m_libraryPath(QDir(storageRoot).filePath(QStringLiteral("decks.json"))),
      m_legacyCubePath(QDir(storageRoot).filePath(QStringLiteral("cubes.json"))),
      m_settingsPath(QDir(storageRoot).filePath(QStringLiteral("settings.json"))),
      m_writeMutex(std::make_shared<QMutex>())
{
    QDir().mkpath(storageRoot);
}

bool DeckLibraryStorage::loadDecks(QVector<Deck> *decks, QString *error)
{
    QFile file(m_libraryPath);
    if (!file.exists())
        return true;
    if (!file.open(QIODevice::ReadOnly)) {
        m_libraryWritable = false;
        *error = QStringLiteral("Could not open the local deck library.");
        return false;
    }

    QJsonParseError parseError;
    const QJsonDocument document = QJsonDocument::fromJson(file.readAll(), &parseError);
    bool damaged = parseError.error != QJsonParseError::NoError || !document.isObject();
    QVector<Deck> loadedDecks;
    if (!damaged) {
        const QJsonObject root = document.object();
        const QJsonValue decksValue = root.value(QStringLiteral("decks"));
        damaged = root.value(QStringLiteral("version")).toInt() != 1 || !decksValue.isArray();
        QSet<QString> ids;
        for (const QJsonValue &value : decksValue.toArray()) {
            if (!value.isObject()) {
                damaged = true;
                break;
            }
            const QJsonObject object = value.toObject();
            const Deck deck = deckFromJson(object);
            if (deck.id.isEmpty() || ids.contains(deck.id) || deck.name.isEmpty() ||
                !supportedTableMode(deck.format) || !supportedDeckFormat(deck.deckFormat) ||
                tableModeForDeckFormat(deck.deckFormat) != deck.format ||
                !validCards(object.value(QStringLiteral("mainboard"))) ||
                !validCards(object.value(QStringLiteral("sideboard"))) ||
                (!object.value(QStringLiteral("consider")).isUndefined() &&
                 !validCards(object.value(QStringLiteral("consider")))) ||
                !validTokens(object.value(QStringLiteral("tokens")))) {
                damaged = true;
                break;
            }
            ids.insert(deck.id);
            loadedDecks.append(deck);
        }
    }
    if (damaged) {
        file.close();
        const QString backupPath = m_libraryPath + QStringLiteral(".corrupt-") +
                                   QString::number(QDateTime::currentMSecsSinceEpoch());
        if (QFile::rename(m_libraryPath, backupPath)) {
            *error =
                QStringLiteral("The damaged deck library was preserved as %1.").arg(backupPath);
        } else {
            m_libraryWritable = false;
            *error = QStringLiteral("The local deck library is not valid JSON.");
        }
        return false;
    }

    *decks = std::move(loadedDecks);
    return true;
}

bool DeckLibraryStorage::saveDecks(const QVector<Deck> &decks, QString *error) const
{
    const QMutexLocker locker(m_writeMutex.get());
    return writeDecksLocked(decks, error);
}

bool DeckLibraryStorage::migrateLegacyCubes(QVector<Deck> *decks, QString *error)
{
    QFile file(m_legacyCubePath);
    if (!file.exists())
        return true;
    if (!file.open(QIODevice::ReadOnly)) {
        *error = QStringLiteral("Could not open the legacy Cube library for migration.");
        return false;
    }

    QJsonParseError parseError;
    const QJsonDocument document = QJsonDocument::fromJson(file.readAll(), &parseError);
    const QJsonObject root = document.object();
    const int schemaVersion = root.value(QStringLiteral("schemaVersion")).toInt();
    const QJsonValue cubesValue = root.value(QStringLiteral("cubes"));
    if (parseError.error != QJsonParseError::NoError || !document.isObject() ||
        (schemaVersion != 1 && schemaVersion != 2) || !cubesValue.isArray()) {
        *error =
            QStringLiteral("The legacy Cube library could not be migrated and was left unchanged.");
        return false;
    }

    QVector<Deck> migrated = *decks;
    QHash<QString, qsizetype> deckRows;
    for (qsizetype index = 0; index < migrated.size(); ++index)
        deckRows.insert(migrated.at(index).id, index);
    bool changed = false;

    for (const QJsonValue &cubeValue : cubesValue.toArray()) {
        if (!cubeValue.isObject()) {
            *error = QStringLiteral(
                "The legacy Cube library could not be migrated and was left unchanged.");
            return false;
        }
        const QJsonObject cube = cubeValue.toObject();
        const QString legacyId = cube.value(QStringLiteral("id")).toString().trimmed();
        const QString name = cube.value(QStringLiteral("name")).toString().simplified();
        const QJsonValue cardsValue = cube.value(QStringLiteral("cards"));
        if (legacyId.isEmpty() || name.isEmpty() || !cardsValue.isArray()) {
            *error = QStringLiteral(
                "The legacy Cube library could not be migrated and was left unchanged.");
            return false;
        }

        const QString deckId = QStringLiteral("legacy-cube-") + legacyId;
        if (deckRows.contains(deckId)) {
            const Deck &existing = migrated.at(deckRows.value(deckId));
            if (!isCubeDeckFormat(existing.deckFormat)) {
                *error = QStringLiteral(
                    "A legacy Cube conflicts with an existing deck and was left unchanged.");
                return false;
            }
            continue;
        }

        Deck deck;
        deck.id = deckId;
        deck.name = name;
        deck.format = QString::fromLatin1(kTableModeOneVsOne);
        deck.deckFormat = QString::fromLatin1(kDeckFormatCube);
        deck.createdAt = cube.value(QStringLiteral("updatedAt")).toString();
        if (deck.createdAt.isEmpty())
            deck.createdAt = QDateTime::currentDateTimeUtc().toString(Qt::ISODateWithMs);
        deck.updatedAt = deck.createdAt;

        for (const QJsonValue &cardValue : cardsValue.toArray()) {
            if (!cardValue.isObject()) {
                *error = QStringLiteral(
                    "The legacy Cube library could not be migrated and was left unchanged.");
                return false;
            }
            const QJsonObject card = cardValue.toObject();
            DeckCard migratedCard;
            migratedCard.name = card.value(QStringLiteral("name")).toString().simplified();
            migratedCard.setCode =
                card.value(QStringLiteral("setCode")).toString().trimmed().toUpper();
            migratedCard.collectorNumber =
                card.value(QStringLiteral("collectorNumber")).toString().trimmed();
            migratedCard.typeLine = card.value(QStringLiteral("typeLine")).toString();
            migratedCard.count = card.value(QStringLiteral("weight")).toInt();
            if (migratedCard.name.isEmpty() || migratedCard.count <= 0) {
                *error = QStringLiteral(
                    "The legacy Cube library could not be migrated and was left unchanged.");
                return false;
            }
            deck.mainboard.append(migratedCard);
        }
        if (deck.mainboard.isEmpty()) {
            *error = QStringLiteral(
                "The legacy Cube library could not be migrated and was left unchanged.");
            return false;
        }
        deckRows.insert(deck.id, migrated.size());
        migrated.append(std::move(deck));
        changed = true;
    }

    if (changed && !saveDecks(migrated, error))
        return false;
    *decks = std::move(migrated);
    file.close();

    const QString archivePath = m_legacyCubePath + QStringLiteral(".migrated-") +
                                QString::number(QDateTime::currentMSecsSinceEpoch());
    if (!QFile::rename(m_legacyCubePath, archivePath)) {
        *error = QStringLiteral(
            "Legacy Cubes were imported, but their source file could not be archived.");
        return false;
    }
    return true;
}

bool DeckLibraryStorage::saveDecksIfNewer(const QVector<Deck> &decks, quint64 generation,
                                          std::atomic<quint64> *committedGeneration,
                                          QString *error) const
{
    const QMutexLocker locker(m_writeMutex.get());
    if (committedGeneration != nullptr && generation <= committedGeneration->load())
        return true;
    if (!writeDecksLocked(decks, error))
        return false;
    if (committedGeneration != nullptr)
        committedGeneration->store(generation);
    return true;
}

bool DeckLibraryStorage::writeDecksLocked(const QVector<Deck> &decks, QString *error) const
{
    if (!m_libraryWritable) {
        *error = QStringLiteral("The local deck library cannot be updated safely.");
        return false;
    }
    QJsonArray serializedDecks;
    for (const Deck &deck : decks)
        serializedDecks.append(deckToJson(deck));
    const QJsonObject root{
        {QStringLiteral("version"), 1},
        {QStringLiteral("decks"), serializedDecks},
    };
    QSaveFile file(m_libraryPath);
    if (!file.open(QIODevice::WriteOnly) ||
        file.write(QJsonDocument(root).toJson(QJsonDocument::Indented)) < 0 || !file.commit()) {
        *error = QStringLiteral("Could not save the local deck library.");
        return false;
    }
    return true;
}

DeckLibraryPreferences DeckLibraryStorage::loadPreferences()
{
    DeckLibraryPreferences preferences;
    QFile file(m_settingsPath);
    if (!file.exists() || !file.open(QIODevice::ReadOnly))
        return preferences;

    QJsonParseError parseError;
    const QJsonDocument document = QJsonDocument::fromJson(file.readAll(), &parseError);
    if (parseError.error != QJsonParseError::NoError || !document.isObject()) {
        // Returning defaults silently would let the next save overwrite the
        // user's language, scale, and table layout with no diagnostic. Preserve
        // the damaged file the same way a damaged deck library is preserved.
        file.close();
        const QString damagedPath = m_settingsPath + QStringLiteral(".corrupt-") +
                                    QString::number(QDateTime::currentMSecsSinceEpoch());
        if (!QFile::rename(m_settingsPath, damagedPath))
            m_settingsWritable = false;
        return preferences;
    }
    const QJsonObject settings = document.object();
    const QString legacyLanguage = settings.value(QStringLiteral("language")).toString();
    const QString uiLanguage =
        settings.value(QStringLiteral("uiLanguage")).toString(legacyLanguage);
    const QString cardLanguage =
        settings.value(QStringLiteral("cardLanguage")).toString(legacyLanguage);
    if (uiLanguage == QStringLiteral("zh") || uiLanguage == QStringLiteral("en"))
        preferences.uiLanguage = uiLanguage;
    if (cardLanguage == QStringLiteral("zh") || cardLanguage == QStringLiteral("en"))
        preferences.cardLanguage = cardLanguage;
    const QString cardArtProvider =
        settings.value(QStringLiteral("cardArtProvider")).toString().toLower();
    if (cardArtProvider == QStringLiteral("auto") ||
        cardArtProvider == QStringLiteral("scryfall") ||
        cardArtProvider == QStringLiteral("mtgch")) {
        preferences.cardArtProvider = cardArtProvider;
    }
    const QJsonValue reuseLocalCardArt = settings.value(QStringLiteral("reuseLocalCardArt"));
    if (reuseLocalCardArt.isBool())
        preferences.reuseLocalCardArt = reuseLocalCardArt.toBool();
    const QJsonValue animatePackOpenings = settings.value(QStringLiteral("animatePackOpenings"));
    if (animatePackOpenings.isBool())
        preferences.animatePackOpenings = animatePackOpenings.toBool();
    preferences.sponsorAnnouncementId =
        settings.value(QStringLiteral("sponsorAnnouncementId")).toString().trimmed().left(128);
    preferences.cardArtRepairNoticeVersion =
        qMax(0, settings.value(QStringLiteral("cardArtRepairNoticeVersion")).toInt());
    const QJsonValue interfaceScale = settings.value(QStringLiteral("interfaceScale"));
    if (interfaceScale.isDouble())
        preferences.interfaceScale = normalizedInterfaceScale(interfaceScale.toDouble());
    const QJsonValue tableShowPlayers = settings.value(QStringLiteral("tableShowPlayers"));
    if (tableShowPlayers.isBool())
        preferences.tableShowPlayers = tableShowPlayers.toBool();
    const QJsonValue tableShowShared = settings.value(QStringLiteral("tableShowShared"));
    if (tableShowShared.isBool())
        preferences.tableShowShared = tableShowShared.toBool();
    const QJsonValue tableShowInspector = settings.value(QStringLiteral("tableShowInspector"));
    if (tableShowInspector.isBool())
        preferences.tableShowInspector = tableShowInspector.toBool();
    const QJsonValue tableShowGameLog = settings.value(QStringLiteral("tableShowGameLog"));
    if (tableShowGameLog.isBool())
        preferences.tableShowGameLog = tableShowGameLog.toBool();
    const QJsonValue tableCounterCount = settings.value(QStringLiteral("tableCounterCount"));
    if (tableCounterCount.isDouble())
        preferences.tableCounterCount = std::clamp(tableCounterCount.toInt(), 0, 7);
    const QJsonValue tableOverviewCardScale =
        settings.value(QStringLiteral("tableOverviewCardScale"));
    if (tableOverviewCardScale.isDouble()) {
        preferences.tableOverviewCardScale =
            normalizedTableCardScale(tableOverviewCardScale.toDouble());
    }
    const QJsonValue tableFocusCardScale = settings.value(QStringLiteral("tableFocusCardScale"));
    if (tableFocusCardScale.isDouble())
        preferences.tableFocusCardScale = normalizedTableCardScale(tableFocusCardScale.toDouble());
    const QJsonValue tableBattlefieldControlX =
        settings.value(QStringLiteral("tableBattlefieldControlX"));
    if (tableBattlefieldControlX.isDouble()) {
        preferences.tableBattlefieldControlX =
            normalizedTableControlPosition(tableBattlefieldControlX.toDouble());
    }
    const QJsonValue tableBattlefieldControlY =
        settings.value(QStringLiteral("tableBattlefieldControlY"));
    if (tableBattlefieldControlY.isDouble()) {
        preferences.tableBattlefieldControlY =
            normalizedTableControlPosition(tableBattlefieldControlY.toDouble());
    }
    const QJsonValue shortcuts = settings.value(QStringLiteral("shortcuts"));
    if (shortcuts.isObject()) {
        const QJsonObject shortcutObject = shortcuts.toObject();
        for (auto it = shortcutObject.constBegin(); it != shortcutObject.constEnd(); ++it) {
            if (!it.value().isArray())
                continue;
            QStringList sequences;
            bool valid = true;
            for (const QJsonValue &sequence : it.value().toArray()) {
                if (!sequence.isString()) {
                    valid = false;
                    break;
                }
                sequences.append(sequence.toString());
            }
            if (valid)
                preferences.shortcutOverrides.insert(it.key(), sequences);
        }
    }
    return preferences;
}

bool DeckLibraryStorage::savePreferences(const DeckLibraryPreferences &preferences,
                                         QString *error) const
{
    const QMutexLocker locker(m_writeMutex.get());
    if (!m_settingsWritable) {
        *error = QStringLiteral("The local settings cannot be updated safely.");
        return false;
    }
    QSaveFile file(m_settingsPath);
    QJsonObject shortcuts;
    QStringList shortcutActionIds = preferences.shortcutOverrides.keys();
    shortcutActionIds.sort();
    for (const QString &actionId : std::as_const(shortcutActionIds)) {
        QJsonArray sequences;
        for (const QString &sequence : preferences.shortcutOverrides.value(actionId))
            sequences.append(sequence);
        shortcuts.insert(actionId, sequences);
    }
    const QJsonObject settings{
        {QStringLiteral("version"), 12},
        {QStringLiteral("uiLanguage"), preferences.uiLanguage},
        {QStringLiteral("cardLanguage"), preferences.cardLanguage},
        {QStringLiteral("cardArtProvider"), preferences.cardArtProvider},
        {QStringLiteral("reuseLocalCardArt"), preferences.reuseLocalCardArt},
        {QStringLiteral("animatePackOpenings"), preferences.animatePackOpenings},
        {QStringLiteral("sponsorAnnouncementId"), preferences.sponsorAnnouncementId},
        {QStringLiteral("cardArtRepairNoticeVersion"), preferences.cardArtRepairNoticeVersion},
        {QStringLiteral("interfaceScale"), preferences.interfaceScale},
        {QStringLiteral("tableShowPlayers"), preferences.tableShowPlayers},
        {QStringLiteral("tableShowShared"), preferences.tableShowShared},
        {QStringLiteral("tableShowInspector"), preferences.tableShowInspector},
        {QStringLiteral("tableShowGameLog"), preferences.tableShowGameLog},
        {QStringLiteral("tableCounterCount"), preferences.tableCounterCount},
        {QStringLiteral("tableOverviewCardScale"), preferences.tableOverviewCardScale},
        {QStringLiteral("tableFocusCardScale"), preferences.tableFocusCardScale},
        {QStringLiteral("tableBattlefieldControlX"), preferences.tableBattlefieldControlX},
        {QStringLiteral("tableBattlefieldControlY"), preferences.tableBattlefieldControlY},
        {QStringLiteral("shortcuts"), shortcuts},
    };
    if (!file.open(QIODevice::WriteOnly) ||
        file.write(QJsonDocument(settings).toJson(QJsonDocument::Indented)) < 0 || !file.commit()) {
        *error = QStringLiteral("Could not save settings.");
        return false;
    }
    return true;
}

} // namespace hexproof::client
