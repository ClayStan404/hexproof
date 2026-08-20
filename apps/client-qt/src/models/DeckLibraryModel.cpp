// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "DeckLibraryModel.h"

#include "ApplicationPaths.h"
#include "deck/DeckEditor.h"
#include "deck/DeckFormat.h"
#include "deck/DeckListFileIO.h"
#include "deck/DeckParser.h"
#include "models/DeckLibraryQueries.h"

#include <QClipboard>
#include <QDateTime>
#include <QDir>
#include <QGuiApplication>
#include <QMetaMethod>
#include <QRegularExpression>
#include <QSaveFile>
#include <QStandardPaths>
#include <QTextStream>
#include <QUuid>
#include <QtConcurrent>

#include <algorithm>
#include <utility>

namespace hexproof::client {

namespace {

constexpr int kValidationDelayMs = 100;

} // namespace

DeckLibraryModel::DeckLibraryModel(QObject *parent)
    : DeckLibraryModel(defaultStorageRoot(), parent)
{
}

DeckLibraryModel::DeckLibraryModel(const QString &storageRoot, QObject *parent)
    : DeckLibraryModel(storageRoot, {}, parent)
{
}

DeckLibraryModel::DeckLibraryModel(const QString &storageRoot, SaveDecksFunction saveDecks,
                                   QObject *parent)
    : QAbstractListModel(parent),
      m_storage(storageRoot),
      m_saveDecks(std::move(saveDecks))
{
    if (!m_saveDecks) {
        m_saveDecks = [this](const QVector<Deck> &decks, quint64 generation, QString *error) {
            return m_storage.saveDecksIfNewer(decks, generation, &m_committedGeneration, error);
        };
    }
    load();
    connect(&m_importWatcher, &QFutureWatcher<DeckParseResult>::finished, this,
            &DeckLibraryModel::finishAsyncDeckImport);
    connect(&m_backgroundSaveWatcher, &QFutureWatcher<BackgroundSaveResult>::finished, this,
            &DeckLibraryModel::finishBackgroundSave);
    m_metadataCommitTimer.setSingleShot(true);
    m_metadataCommitTimer.setInterval(kMetadataCommitDelayMs);
    connect(&m_metadataCommitTimer, &QTimer::timeout, this, &DeckLibraryModel::flushMetadataCommit);
    m_validationTimer.setSingleShot(true);
    m_validationTimer.setInterval(kValidationDelayMs);
    connect(&m_validationTimer, &QTimer::timeout, this, &DeckLibraryModel::validatePendingDecks);
    rebuildVisibleRows();
    rebuildCardDeckIndex();
}

DeckLibraryModel::~DeckLibraryModel()
{
    m_metadataCommitTimer.stop();
    // Process exit may block here so pending edits are not abandoned. Interactive
    // saves only enqueue snapshots and never wait for this worker.
    if (m_backgroundSaveRunning)
        m_backgroundSaveWatcher.waitForFinished();
    if (m_persistedGeneration < m_persistenceGeneration) {
        QString error;
        m_saveDecks(m_decks, m_persistenceGeneration, &error);
    }
}

int DeckLibraryModel::rowCount(const QModelIndex &parent) const
{
    return parent.isValid() ? 0 : static_cast<int>(m_visibleRows.size());
}

QVariant DeckLibraryModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() < 0 || index.row() >= m_visibleRows.size())
        return {};
    const Deck &deck = m_decks.at(m_visibleRows.at(index.row()));
    switch (role) {
    case IdRole:
        return deck.id;
    case NameRole:
        return deck.name;
    case FormatRole:
        return deck.deckFormat;
    case TableModeRole:
        return deck.format;
    case MainCountRole:
        return cardCount(deck.mainboard);
    case SideboardCountRole:
        return cardCount(deck.sideboard);
    case ReadyRole:
        return DeckLibraryQueries::deckReady(deck, validationForDeck(deck.id));
    case StatusRole:
        return DeckLibraryQueries::deckStatus(deck, validationForDeck(deck.id));
    case CommanderRole:
        return DeckLibraryQueries::commanderDisplayName(deck);
    case UpdatedAtRole:
        return deck.updatedAt;
    case ValidationVerifiedRole:
        return validationForDeck(deck.id).value(QStringLiteral("verified"), true);
    case ValidationIssuesRole:
        return validationForDeck(deck.id).value(QStringLiteral("issues")).toStringList();
    default:
        return {};
    }
}

QHash<int, QByteArray> DeckLibraryModel::roleNames() const
{
    return {
        {IdRole, "deckId"},
        {NameRole, "deckName"},
        {FormatRole, "deckFormat"},
        {TableModeRole, "tableMode"},
        {MainCountRole, "mainCount"},
        {SideboardCountRole, "sideboardCount"},
        {ReadyRole, "ready"},
        {StatusRole, "status"},
        {CommanderRole, "commander"},
        {UpdatedAtRole, "updatedAt"},
        {ValidationVerifiedRole, "legalityVerified"},
        {ValidationIssuesRole, "legalityIssues"},
    };
}

void DeckLibraryModel::setFormatFilter(const QString &filter)
{
    const QString normalized = filter.toLower();
    if (normalized == m_formatFilter ||
        (normalized != QStringLiteral("all") && !supportedDeckFormat(normalized)))
        return;
    beginResetModel();
    m_formatFilter = normalized;
    rebuildVisibleRows();
    endResetModel();
    emit formatFilterChanged();
    emit countChanged();
}

const Deck *DeckLibraryModel::currentDeck() const
{
    for (const Deck &deck : m_decks) {
        if (deck.id == m_currentDeckId)
            return &deck;
    }
    return nullptr;
}

Deck *DeckLibraryModel::currentDeck()
{
    for (Deck &deck : m_decks) {
        if (deck.id == m_currentDeckId)
            return &deck;
    }
    return nullptr;
}

const Deck *DeckLibraryModel::deckById(const QString &id) const
{
    const QString deckId = id.isEmpty() ? m_currentDeckId : id;
    if (deckId.isEmpty())
        return nullptr;
    for (const Deck &deck : m_decks) {
        if (deck.id == deckId)
            return &deck;
    }
    return nullptr;
}

QString DeckLibraryModel::exportFileNameForDeck(const Deck &deck) const
{
    QString name = deck.name.trimmed();
    if (name.isEmpty())
        name = QStringLiteral("deck");
    static const QRegularExpression illegal(QStringLiteral(R"([\\/:*?"<>|])"));
    name.replace(illegal, QStringLiteral("_"));
    if (!name.endsWith(QStringLiteral(".txt"), Qt::CaseInsensitive))
        name += QStringLiteral(".txt");
    return name;
}

const Deck *DeckLibraryModel::activeMatchDeck() const
{
    for (const Deck &deck : m_decks) {
        if (deck.id == m_activeMatchDeckId)
            return &deck;
    }
    return nullptr;
}

QString DeckLibraryModel::currentDeckId() const
{
    return currentDeck() ? currentDeck()->id : QString{};
}

QString DeckLibraryModel::currentDeckName() const
{
    return currentDeck() ? currentDeck()->name : QString{};
}

QString DeckLibraryModel::currentDeckFormat() const
{
    return currentDeck() ? currentDeck()->deckFormat : QString{};
}

QString DeckLibraryModel::currentDeckTableMode() const
{
    return currentDeck() ? currentDeck()->format : QString{};
}

QString DeckLibraryModel::currentCommander() const
{
    return currentDeck() ? DeckLibraryQueries::commanderDisplayName(*currentDeck()) : QString{};
}

int DeckLibraryModel::currentMainCount() const
{
    return currentDeck() ? cardCount(currentDeck()->mainboard) : 0;
}

int DeckLibraryModel::currentMissingImageCount() const
{
    return currentDeck() ? DeckLibraryQueries::missingImageCount(*currentDeck()) : 0;
}

int DeckLibraryModel::currentSideboardCount() const
{
    return currentDeck() ? cardCount(currentDeck()->sideboard) : 0;
}

bool DeckLibraryModel::currentReady() const
{
    return currentDeck() &&
           DeckLibraryQueries::deckReady(*currentDeck(), validationForDeck(currentDeck()->id));
}

QString DeckLibraryModel::currentStatus() const
{
    return currentDeck() ? DeckLibraryQueries::deckStatus(*currentDeck(),
                                                          validationForDeck(currentDeck()->id))
                         : QString{};
}

bool DeckLibraryModel::currentValidationVerified() const
{
    return !currentDeck() ||
           validationForDeck(currentDeck()->id).value(QStringLiteral("verified"), true).toBool();
}

QStringList DeckLibraryModel::currentValidationIssues() const
{
    return currentDeck()
               ? validationForDeck(currentDeck()->id).value(QStringLiteral("issues")).toStringList()
               : QStringList{};
}

QVariantList DeckLibraryModel::mainCards() const
{
    return currentDeck()
               ? DeckLibraryQueries::cardVariants(currentDeck()->mainboard, *currentDeck(), true)
               : QVariantList{};
}

QVariantList DeckLibraryModel::sideboardCards() const
{
    return currentDeck()
               ? DeckLibraryQueries::cardVariants(currentDeck()->sideboard, *currentDeck(), false)
               : QVariantList{};
}

QVariantList DeckLibraryModel::currentTokens() const
{
    return currentDeck() ? DeckLibraryQueries::tokenVariants(currentDeck()->tokens)
                         : QVariantList{};
}

QVariantList DeckLibraryModel::activeMatchTokens() const
{
    return activeMatchDeck() ? DeckLibraryQueries::tokenVariants(activeMatchDeck()->tokens)
                             : QVariantList{};
}

bool DeckLibraryModel::hasMissingArt() const
{
    return DeckLibraryQueries::hasMissingArt(m_decks);
}

bool DeckLibraryModel::importDeck(const QString &name, const QString &format, const QString &text)
{
    clearLastError();
    setLastImportWarnings({});
    QString deckName;
    QString deckFormat;
    if (!validateDeckImport(name, format, &deckName, &deckFormat))
        return false;

    return commitDeckImport(
        deckName, deckFormat,
        DeckParser::parse(text, isCommanderTableMode(tableModeForDeckFormat(deckFormat))));
}

bool DeckLibraryModel::importDeckAsync(const QString &name, const QString &format,
                                       const QString &text)
{
    if (m_importingDeck)
        return false;

    clearLastError();
    setLastImportWarnings({});
    QString deckName;
    QString deckFormat;
    if (!validateDeckImport(name, format, &deckName, &deckFormat))
        return false;

    m_pendingImportName = deckName;
    m_pendingImportFormat = deckFormat;
    m_importingDeck = true;
    setImportStage(QStringLiteral("parsing"));
    emit importingDeckChanged();
    const bool commander = isCommanderTableMode(tableModeForDeckFormat(deckFormat));
    m_importWatcher.setFuture(
        QtConcurrent::run([text, commander]() { return DeckParser::parse(text, commander); }));
    return true;
}

QVariantMap DeckLibraryModel::loadDeckTextFile(const QUrl &fileUrl)
{
    clearLastError();
    const DeckListFileData loaded = loadDeckListFile(fileUrl);
    if (!loaded.error.isEmpty()) {
        setLastError(loaded.error);
        return {};
    }
    return {
        {QStringLiteral("ok"), true},
        {QStringLiteral("text"), loaded.text},
        {QStringLiteral("suggestedName"), loaded.suggestedName},
    };
}

bool DeckLibraryModel::validateDeckImport(const QString &name, const QString &format,
                                          QString *deckName, QString *deckFormat)
{
    *deckName = name.simplified();
    *deckFormat = normalizedDeckFormat(format);
    if (deckName->isEmpty()) {
        setLastError(QStringLiteral("Give the deck a name before importing."));
        return false;
    }
    if (!supportedDeckFormat(*deckFormat)) {
        setLastError(QStringLiteral("Choose a supported deck format."));
        return false;
    }
    return true;
}

bool DeckLibraryModel::commitDeckImport(const QString &deckName, const QString &deckFormat,
                                        const DeckParseResult &parsed)
{
    if (!parsed.ok()) {
        setLastError(parsed.error);
        return false;
    }

    Deck deck = parsed.deck;
    deck.id = QUuid::createUuid().toString(QUuid::WithoutBraces);
    deck.name = deckName;
    deck.deckFormat = deckFormat;
    deck.format = tableModeForDeckFormat(deckFormat);
    deck.createdAt = QDateTime::currentDateTimeUtc().toString(Qt::ISODateWithMs);
    deck.updatedAt = deck.createdAt;

    m_decks.prepend(deck);
    if (!save()) {
        m_decks.removeFirst();
        return false;
    }
    beginResetModel();
    rebuildVisibleRows();
    rebuildCardDeckIndex();
    endResetModel();
    scheduleDeckValidation(deck.id);
    emit countChanged();
    requestCatalogMetadata(m_decks.constFirst(), false);
    emit cardsNeedCachedArtLookup(
        DeckLibraryQueries::cacheRequestsForDeck(m_decks.constFirst(), true));

    setLastImportWarnings(parsed.warnings);
    return true;
}

void DeckLibraryModel::finishAsyncDeckImport()
{
    m_pendingParsedImport = m_importWatcher.result();
    setImportStage(QStringLiteral("finalizing"));
    QTimer::singleShot(16, this, &DeckLibraryModel::commitPendingAsyncDeckImport);
}

void DeckLibraryModel::commitPendingAsyncDeckImport()
{
    const DeckParseResult parsed = std::exchange(m_pendingParsedImport, {});
    const QString deckName = std::exchange(m_pendingImportName, {});
    const QString deckFormat = std::exchange(m_pendingImportFormat, {});
    const bool success = commitDeckImport(deckName, deckFormat, parsed);
    m_importingDeck = false;
    setImportStage({});
    emit importingDeckChanged();
    emit deckImportFinished(success);
}

QString DeckLibraryModel::exportDeckText(const QString &id) const
{
    const Deck *deck = deckById(id);
    return deck ? DeckParser::format(*deck) : QString{};
}

QString DeckLibraryModel::exportCurrentDeckText() const
{
    return exportDeckText(m_currentDeckId);
}

QString DeckLibraryModel::suggestedExportFileName(const QString &id) const
{
    const Deck *deck = deckById(id);
    return deck ? exportFileNameForDeck(*deck) : QString{};
}

QUrl DeckLibraryModel::suggestedExportUrl(const QString &id) const
{
    const QString fileName = suggestedExportFileName(id);
    if (fileName.isEmpty())
        return {};
    const QString folder = QStandardPaths::writableLocation(QStandardPaths::DocumentsLocation);
    return QUrl::fromLocalFile(QDir(folder).filePath(fileName));
}

bool DeckLibraryModel::copyDeckText(const QString &id)
{
    const QString text = exportDeckText(id);
    if (text.isEmpty()) {
        setLastError(QStringLiteral("Deck not found."));
        return false;
    }
    QGuiApplication *app = qGuiApp;
    if (!app || !app->clipboard()) {
        setLastError(QStringLiteral("The clipboard is not available."));
        return false;
    }
    app->clipboard()->setText(text);
    return true;
}

bool DeckLibraryModel::copyCurrentDeckText()
{
    return copyDeckText(m_currentDeckId);
}

bool DeckLibraryModel::saveDeckText(const QString &id, const QUrl &fileUrl)
{
    const QString text = exportDeckText(id);
    if (text.isEmpty()) {
        setLastError(QStringLiteral("Deck not found."));
        return false;
    }
    if (!fileUrl.isLocalFile()) {
        setLastError(QStringLiteral("Choose a local file to export the deck list."));
        return false;
    }
    const QString path = fileUrl.toLocalFile();
    if (path.isEmpty()) {
        setLastError(QStringLiteral("Choose a file to export the deck list."));
        return false;
    }
    QSaveFile file(path);
    if (!file.open(QIODevice::WriteOnly | QIODevice::Text)) {
        setLastError(QStringLiteral("The deck list could not be saved."));
        return false;
    }
    QTextStream stream(&file);
    stream.setEncoding(QStringConverter::Utf8);
    stream << text;
    if (stream.status() != QTextStream::Ok) {
        file.cancelWriting();
        setLastError(QStringLiteral("The deck list could not be saved."));
        return false;
    }
    if (!file.commit()) {
        setLastError(QStringLiteral("The deck list could not be saved."));
        return false;
    }
    return true;
}

bool DeckLibraryModel::saveCurrentDeckText(const QUrl &fileUrl)
{
    return saveDeckText(m_currentDeckId, fileUrl);
}

bool DeckLibraryModel::deleteDeck(const QString &id)
{
    for (int i = 0; i < m_decks.size(); ++i) {
        if (m_decks.at(i).id != id)
            continue;
        const QVector<Deck> previousDecks = m_decks;
        const QString previousCurrentDeckId = m_currentDeckId;
        const QString previousActiveMatchDeckId = m_activeMatchDeckId;
        m_decks.removeAt(i);
        if (m_currentDeckId == id)
            m_currentDeckId.clear();
        const bool activeMatchDeckRemoved = m_activeMatchDeckId == id;
        if (activeMatchDeckRemoved)
            m_activeMatchDeckId.clear();
        if (!save()) {
            m_decks = previousDecks;
            m_currentDeckId = previousCurrentDeckId;
            m_activeMatchDeckId = previousActiveMatchDeckId;
            return false;
        }
        m_deckValidations.remove(id);
        m_validationRevisions.remove(id);
        m_pendingValidationDeckIds.remove(id);
        beginResetModel();
        rebuildVisibleRows();
        rebuildCardDeckIndex();
        endResetModel();
        emit countChanged();
        emit currentDeckChanged();
        if (activeMatchDeckRemoved)
            emit activeMatchTokensChanged();
        return true;
    }
    setLastError(QStringLiteral("Deck not found."));
    return false;
}

bool DeckLibraryModel::openDeck(const QString &id)
{
    for (const Deck &deck : m_decks) {
        if (deck.id == id) {
            m_currentDeckId = id;
            emit currentDeckChanged();
            return true;
        }
    }
    setLastError(QStringLiteral("Deck not found."));
    return false;
}

void DeckLibraryModel::closeDeck()
{
    if (m_currentDeckId.isEmpty())
        return;
    m_currentDeckId.clear();
    emit currentDeckChanged();
}

bool DeckLibraryModel::renameCurrentDeck(const QString &name)
{
    Deck *deck = currentDeck();
    if (!deck)
        return false;
    const Deck previous = *deck;
    if (!DeckEditor::rename(*deck, name))
        return false;
    if (!save()) {
        *deck = previous;
        return false;
    }
    notifyAllChanged();
    return true;
}

bool DeckLibraryModel::changeCurrentDeckFormat(const QString &format)
{
    clearLastError();
    Deck *deck = currentDeck();
    if (!deck)
        return false;
    const QString normalized = normalizedDeckFormat(format);
    if (deck->deckFormat == normalized)
        return true;

    const Deck previous = *deck;
    QString error;
    if (!DeckEditor::changeFormat(*deck, normalized, &error)) {
        if (!error.isEmpty())
            setLastError(error);
        return false;
    }
    if (!save()) {
        *deck = previous;
        return false;
    }

    const QString deckId = deck->id;
    if (isNamedConstructedFormat(deck->deckFormat)) {
        scheduleDeckValidation(deckId);
    } else {
        m_deckValidations.remove(deckId);
        m_validationRevisions.remove(deckId);
        m_pendingValidationDeckIds.remove(deckId);
    }
    notifyAllChanged();
    return true;
}

bool DeckLibraryModel::setCommander(const QString &cardName)
{
    clearLastError();
    Deck *deck = currentDeck();
    if (!deck || !isCommanderTableMode(deck->format))
        return false;
    const Deck previous = *deck;
    QString error;
    if (!DeckEditor::toggleCommander(*deck, cardName, &error)) {
        if (!error.isEmpty())
            setLastError(error);
        return false;
    }
    if (!save()) {
        *deck = previous;
        return false;
    }
    scheduleDeckValidation(deck->id);
    notifyAllChanged();
    return true;
}

bool DeckLibraryModel::moveCard(const QString &cardName, bool toSideboard)
{
    Deck *deck = currentDeck();
    if (!deck)
        return false;
    const Deck previous = *deck;
    if (!DeckEditor::moveCard(*deck, cardName, toSideboard))
        return false;
    if (!save()) {
        *deck = previous;
        return false;
    }
    scheduleDeckValidation(deck->id);
    notifyAllChanged();
    return true;
}

bool DeckLibraryModel::changeCardCount(const QString &cardName, bool sideboard, int delta)
{
    Deck *deck = currentDeck();
    if (!deck)
        return false;
    const Deck previous = *deck;
    QString error;
    if (!DeckEditor::changeCardCount(*deck, cardName, sideboard, delta, &error)) {
        if (!error.isEmpty())
            setLastError(error);
        return false;
    }
    if (!save()) {
        *deck = previous;
        return false;
    }
    scheduleDeckValidation(deck->id);
    rebuildCardDeckIndex();
    notifyAllChanged();
    return true;
}

bool DeckLibraryModel::addCard(const QString &name, const QString &localizedName,
                               const QString &typeLine, const QString &setCode,
                               const QString &collectorNumber, bool sideboard)
{
    Deck *deck = currentDeck();
    if (!deck)
        return false;
    const Deck previous = *deck;
    QString error;
    if (!DeckEditor::addCard(*deck, name, localizedName, typeLine, setCode, collectorNumber,
                             sideboard, &error)) {
        if (!error.isEmpty())
            setLastError(error);
        return false;
    }
    if (!save()) {
        *deck = previous;
        return false;
    }
    scheduleDeckValidation(deck->id);
    rebuildCardDeckIndex();
    notifyAllChanged();
    emit cardsNeedCaching(QVariantList{QVariantMap{
        {QStringLiteral("name"), name},
        {QStringLiteral("setCode"), setCode},
        {QStringLiteral("collectorNumber"), collectorNumber},
        {QStringLiteral("exactArt"), true},
    }});
    return true;
}

bool DeckLibraryModel::setCardPrinting(const QString &cardName, bool sideboard,
                                       const QString &localizedName, const QString &typeLine,
                                       const QString &setCode, const QString &collectorNumber)
{
    Deck *deck = currentDeck();
    if (!deck)
        return false;
    const Deck previous = *deck;
    DeckCard updatedCard;
    if (!DeckEditor::setCardPrinting(*deck, cardName, sideboard, localizedName, typeLine, setCode,
                                     collectorNumber, &updatedCard)) {
        return false;
    }
    if (!save()) {
        *deck = previous;
        return false;
    }
    scheduleDeckValidation(deck->id);
    notifyAllChanged();
    emit cardsNeedCaching(QVariantList{QVariantMap{
        {QStringLiteral("name"), updatedCard.name},
        {QStringLiteral("setCode"), updatedCard.setCode},
        {QStringLiteral("collectorNumber"), updatedCard.collectorNumber},
        {QStringLiteral("exactArt"), true},
    }});
    return true;
}

bool DeckLibraryModel::addToken(const QVariantMap &token)
{
    Deck *deck = currentDeck();
    if (!deck)
        return false;
    const Deck previous = *deck;
    const DeckToken deckToken{
        token.value(QStringLiteral("name")).toString(),
        token.value(QStringLiteral("displayName")).toString(),
        token.value(QStringLiteral("setCode")).toString(),
        token.value(QStringLiteral("collectorNumber")).toString(),
        token.value(QStringLiteral("typeLine")).toString(),
        token.value(QStringLiteral("power")).toString(),
        token.value(QStringLiteral("toughness")).toString(),
        token.value(QStringLiteral("oracleText")).toString(),
    };
    if (!DeckEditor::addToken(*deck, deckToken))
        return false;
    if (!save()) {
        *deck = previous;
        return false;
    }
    notifyAllChanged();
    if (deck->id == m_activeMatchDeckId)
        emit activeMatchTokensChanged();
    return true;
}

bool DeckLibraryModel::removeToken(const QString &name, const QString &setCode,
                                   const QString &collectorNumber)
{
    Deck *deck = currentDeck();
    if (!deck)
        return false;
    const Deck previous = *deck;
    if (!DeckEditor::removeToken(*deck, name, setCode, collectorNumber))
        return false;
    if (!save()) {
        *deck = previous;
        return false;
    }
    notifyAllChanged();
    if (deck->id == m_activeMatchDeckId)
        emit activeMatchTokensChanged();
    return true;
}

bool DeckLibraryModel::setActiveMatchDeck(const QString &id)
{
    if (m_activeMatchDeckId == id)
        return activeMatchDeck() != nullptr;
    const auto deck = std::find_if(m_decks.cbegin(), m_decks.cend(),
                                   [&id](const Deck &candidate) { return candidate.id == id; });
    if (deck == m_decks.cend())
        return false;
    m_activeMatchDeckId = id;
    emit activeMatchTokensChanged();
    return true;
}

int DeckLibraryModel::currentCardCopies(const QString &cardName) const
{
    const Deck *deck = currentDeck();
    return deck ? DeckEditor::cardCopies(*deck, cardName) : 0;
}

bool DeckLibraryModel::canAddCard(const QString &cardName, const QString &typeLine) const
{
    const Deck *deck = currentDeck();
    return deck && DeckEditor::canAddCard(*deck, cardName, typeLine);
}

QVariantList DeckLibraryModel::matchDecks(const QString &format, bool allowMissingArt) const
{
    return DeckLibraryQueries::matchingDecks(m_decks, format, allowMissingArt, m_deckValidations);
}

QVariantMap DeckLibraryModel::deckForMatch(const QString &id, bool allowMissingArt) const
{
    return DeckLibraryQueries::matchPayload(m_decks, id, allowMissingArt, m_deckValidations);
}

void DeckLibraryModel::clearLastError()
{
    if (m_lastError.isEmpty())
        return;
    m_lastError.clear();
    emit lastErrorChanged();
}

bool DeckLibraryModel::load()
{
    QString error;
    const bool loaded = m_storage.loadDecks(&m_decks, &error);
    if (!loaded)
        setLastError(error);
    return loaded;
}

bool DeckLibraryModel::save()
{
    if (!m_storage.libraryWritable()) {
        setLastError(QStringLiteral("The local deck library cannot be updated safely."));
        return false;
    }
    ++m_persistenceGeneration;
    m_backgroundSaveAttempts = 0;
    m_metadataCommitTimer.stop();
    m_metadataCommitPending = true;
    startBackgroundSave();
    return true;
}

void DeckLibraryModel::scheduleDeckValidation(const QString &deckId)
{
    if (!isSignalConnected(QMetaMethod::fromSignal(&DeckLibraryModel::decksNeedValidation)))
        return;
    const Deck *deck = deckById(deckId);
    if (!deck || !isNamedConstructedFormat(deck->deckFormat))
        return;

    ++m_validationRevisions[deckId];
    m_pendingValidationDeckIds.insert(deckId);
    QVariantMap validation = m_deckValidations.value(deckId);
    validation.insert(QStringLiteral("pending"), true);
    m_deckValidations.insert(deckId, validation);
    m_validationTimer.start();
}

QVariantMap DeckLibraryModel::validationForDeck(const QString &deckId) const
{
    return m_deckValidations.value(deckId);
}

void DeckLibraryModel::refreshDeckValidation()
{
    if (!isSignalConnected(QMetaMethod::fromSignal(&DeckLibraryModel::decksNeedValidation)))
        return;
    m_validationTimer.stop();
    QSet<QString> validDeckIds;
    QSet<QString> changedDeckIds;
    for (const Deck &deck : m_decks) {
        if (!isNamedConstructedFormat(deck.deckFormat)) {
            if (m_deckValidations.remove(deck.id) > 0) {
                changedDeckIds.insert(deck.id);
            }
            m_validationRevisions.remove(deck.id);
            m_pendingValidationDeckIds.remove(deck.id);
            continue;
        }
        validDeckIds.insert(deck.id);
        ++m_validationRevisions[deck.id];
        m_pendingValidationDeckIds.insert(deck.id);
        QVariantMap pending = m_deckValidations.value(deck.id);
        pending.insert(QStringLiteral("pending"), true);
        m_deckValidations.insert(deck.id, pending);
        changedDeckIds.insert(deck.id);
    }
    for (auto it = m_deckValidations.begin(); it != m_deckValidations.end();) {
        if (validDeckIds.contains(it.key())) {
            ++it;
            continue;
        }
        m_validationRevisions.remove(it.key());
        m_pendingValidationDeckIds.remove(it.key());
        it = m_deckValidations.erase(it);
    }
    if (!changedDeckIds.isEmpty())
        notifyDecksChanged(changedDeckIds);
    validatePendingDecks();
}

void DeckLibraryModel::validatePendingDecks()
{
    if (!isSignalConnected(QMetaMethod::fromSignal(&DeckLibraryModel::decksNeedValidation)) ||
        m_pendingValidationDeckIds.isEmpty()) {
        return;
    }

    QVariantList requests;
    for (const Deck &deck : m_decks) {
        if (!m_pendingValidationDeckIds.contains(deck.id) ||
            !isNamedConstructedFormat(deck.deckFormat)) {
            continue;
        }
        const auto cardList = [](const QVector<DeckCard> &cards) {
            QVariantList result;
            result.reserve(cards.size());
            for (const DeckCard &card : cards) {
                result.append(QVariantMap{
                    {QStringLiteral("name"), card.name},
                    {QStringLiteral("setCode"), card.setCode},
                    {QStringLiteral("collectorNumber"), card.collectorNumber},
                    {QStringLiteral("count"), card.count},
                });
            }
            return result;
        };
        requests.append(QVariantMap{
            {QStringLiteral("deckId"), deck.id},
            {QStringLiteral("validationRevision"), m_validationRevisions.value(deck.id)},
            {QStringLiteral("tableMode"), deck.format},
            {QStringLiteral("deckFormat"), deck.deckFormat},
            {QStringLiteral("commanders"), deck.commanders},
            {QStringLiteral("mainboard"), cardList(deck.mainboard)},
            {QStringLiteral("sideboard"), cardList(deck.sideboard)},
        });
    }
    if (!requests.isEmpty())
        emit decksNeedValidation(requests);
}

void DeckLibraryModel::applyDeckValidation(const QVariantList &results)
{
    QSet<QString> currentIds;
    for (const Deck &deck : m_decks)
        currentIds.insert(deck.id);
    QSet<QString> changedDeckIds;
    for (const QVariant &entry : results) {
        QVariantMap result = entry.toMap();
        const QString deckId = result.value(QStringLiteral("deckId")).toString();
        if (deckId.isEmpty() || !currentIds.contains(deckId))
            continue;
        const quint64 revision = result.value(QStringLiteral("validationRevision")).toULongLong();
        if (revision != m_validationRevisions.value(deckId))
            continue;
        result.remove(QStringLiteral("deckId"));
        result.remove(QStringLiteral("validationRevision"));
        result.insert(QStringLiteral("pending"), false);
        m_deckValidations.insert(deckId, result);
        m_pendingValidationDeckIds.remove(deckId);
        changedDeckIds.insert(deckId);
    }
    if (!changedDeckIds.isEmpty())
        notifyDecksChanged(changedDeckIds);
}

void DeckLibraryModel::rebuildVisibleRows()
{
    m_visibleRows.clear();
    for (int i = 0; i < m_decks.size(); ++i) {
        if (m_formatFilter == QStringLiteral("all") || m_decks.at(i).deckFormat == m_formatFilter)
            m_visibleRows.append(i);
    }
}

void DeckLibraryModel::rebuildCardDeckIndex()
{
    m_cardDeckIndex.clear();
    for (int deckIndex = 0; deckIndex < m_decks.size(); ++deckIndex) {
        const Deck &deck = m_decks.at(deckIndex);
        const auto append = [this, deckIndex](const QVector<DeckCard> &cards) {
            for (const DeckCard &card : cards)
                m_cardDeckIndex[normalizedCardName(card.name)].insert(deckIndex);
        };
        append(deck.mainboard);
        append(deck.sideboard);
    }
}

void DeckLibraryModel::notifyAllChanged()
{
    beginResetModel();
    rebuildVisibleRows();
    endResetModel();
    emit countChanged();
    emit currentDeckChanged();
}

void DeckLibraryModel::notifyDecksChanged(const QSet<QString> &deckIds)
{
    static const QList<int> changedRoles{
        ReadyRole, StatusRole, UpdatedAtRole, ValidationVerifiedRole, ValidationIssuesRole,
    };
    for (int visibleRow = 0; visibleRow < m_visibleRows.size(); ++visibleRow) {
        const Deck &deck = m_decks.at(m_visibleRows.at(visibleRow));
        if (deckIds.contains(deck.id))
            emit dataChanged(index(visibleRow), index(visibleRow), changedRoles);
    }
    emit countChanged();
    if (deckIds.contains(m_currentDeckId))
        emit currentDeckChanged();
    if (deckIds.contains(m_activeMatchDeckId))
        emit activeMatchTokensChanged();
}

void DeckLibraryModel::setLastError(const QString &error)
{
    if (m_lastError == error)
        return;
    m_lastError = error;
    emit lastErrorChanged();
}

void DeckLibraryModel::setLastImportWarnings(const QStringList &warnings)
{
    if (m_lastImportWarnings == warnings)
        return;
    m_lastImportWarnings = warnings;
    emit lastImportWarningsChanged();
}

void DeckLibraryModel::setImportStage(const QString &stage)
{
    if (m_importStage == stage)
        return;
    m_importStage = stage;
    emit importStageChanged();
}

} // namespace hexproof::client
