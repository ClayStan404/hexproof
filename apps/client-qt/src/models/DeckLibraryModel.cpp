// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "DeckLibraryModel.h"

#include "ApplicationPaths.h"
#include "deck/DeckFormat.h"
#include "models/DeckLibraryQueries.h"

#include <QRegularExpression>

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
    case ValidationWarningsRole:
        return validationForDeck(deck.id).value(QStringLiteral("warnings")).toStringList();
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
        {ValidationWarningsRole, "legalityWarnings"},
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

int DeckLibraryModel::currentConsiderMissingImageCount() const
{
    return currentDeck() ? DeckLibraryQueries::missingImageCount(currentDeck()->consider) : 0;
}

int DeckLibraryModel::currentSideboardCount() const
{
    return currentDeck() ? cardCount(currentDeck()->sideboard) : 0;
}

int DeckLibraryModel::currentConsiderCount() const
{
    return currentDeck() ? cardCount(currentDeck()->consider) : 0;
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

QStringList DeckLibraryModel::currentValidationWarnings() const
{
    return currentDeck() ? validationForDeck(currentDeck()->id)
                               .value(QStringLiteral("warnings"))
                               .toStringList()
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

QVariantList DeckLibraryModel::considerCards() const
{
    return currentDeck()
               ? DeckLibraryQueries::cardVariants(currentDeck()->consider, *currentDeck(), false)
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
    if (!loaded) {
        setLastError(error);
        return false;
    }
    if (!m_storage.migrateLegacyCubes(&m_decks, &error))
        setLastError(error);
    return true;
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
        append(deck.consider);
    }
}

void DeckLibraryModel::notifyAllChanged()
{
    emit currentDeckCardsAboutToChange();
    beginResetModel();
    rebuildVisibleRows();
    endResetModel();
    emit countChanged();
    emit currentDeckCardsChanged();
    emit currentDeckChanged();
}

void DeckLibraryModel::notifyDecksChanged(const QSet<QString> &deckIds, bool cardsChanged)
{
    static const QList<int> changedRoles{
        ReadyRole,
        StatusRole,
        UpdatedAtRole,
        ValidationVerifiedRole,
        ValidationIssuesRole,
        ValidationWarningsRole,
    };
    for (int visibleRow = 0; visibleRow < m_visibleRows.size(); ++visibleRow) {
        const Deck &deck = m_decks.at(m_visibleRows.at(visibleRow));
        if (deckIds.contains(deck.id))
            emit dataChanged(index(visibleRow), index(visibleRow), changedRoles);
    }
    emit countChanged();
    if (deckIds.contains(m_currentDeckId)) {
        if (cardsChanged) {
            emit currentDeckCardsAboutToChange();
            emit currentDeckCardsChanged();
        }
        emit currentDeckChanged();
    }
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
