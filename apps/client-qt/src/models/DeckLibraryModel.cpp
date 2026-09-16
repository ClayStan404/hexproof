// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "DeckLibraryModel.h"

#include "ApplicationPaths.h"
#include "deck/DeckFormat.h"
#include "models/DeckLibraryQueries.h"

#include <QRegularExpression>

#include <algorithm>

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
        return DeckLibraryQueries::deckReady(deck, validationForDeck(deck.id),
                                             imageCounts(deck).missing);
    case StatusRole:
        return DeckLibraryQueries::deckStatus(deck, validationForDeck(deck.id),
                                              imageCounts(deck).missing);
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
    const Deck *deck = currentDeck();
    return deck ? imageCounts(*deck).missing : 0;
}

int DeckLibraryModel::currentConsiderMissingImageCount() const
{
    const Deck *deck = currentDeck();
    return deck ? imageCounts(*deck).considerMissing : 0;
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
    const Deck *deck = currentDeck();
    return deck && DeckLibraryQueries::deckReady(*deck, validationForDeck(deck->id),
                                                 imageCounts(*deck).missing);
}

QString DeckLibraryModel::currentStatus() const
{
    const Deck *deck = currentDeck();
    return deck ? DeckLibraryQueries::deckStatus(*deck, validationForDeck(deck->id),
                                                 imageCounts(*deck).missing)
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
    const Deck *deck = currentDeck();
    return deck ? projectedCards(deck->mainboard, *deck, true, &m_mainProjection) : QVariantList{};
}

QVariantList DeckLibraryModel::sideboardCards() const
{
    const Deck *deck = currentDeck();
    return deck ? projectedCards(deck->sideboard, *deck, false, &m_sideboardProjection)
                : QVariantList{};
}

QVariantList DeckLibraryModel::considerCards() const
{
    const Deck *deck = currentDeck();
    return deck ? projectedCards(deck->consider, *deck, false, &m_considerProjection)
                : QVariantList{};
}

QVariantList DeckLibraryModel::projectedCards(const QVector<DeckCard> &cards, const Deck &deck,
                                              bool grouped, CardProjection *projection) const
{
    const auto sameStorage = [](const QVector<DeckCard> &left, const QVector<DeckCard> &right) {
        return left.constData() == right.constData() && left.size() == right.size();
    };
    // Retaining the source vectors makes every edit detach their shared storage.
    // This also detects metadata applied before its coalesced notification, and
    // avoids sorting/converting the entire deck for every QML property read.
    if (!projection->valid || !sameStorage(projection->cards, cards) ||
        !sameStorage(projection->mainboard, deck.mainboard) ||
        !sameStorage(projection->sideboard, deck.sideboard) ||
        projection->commanders != deck.commanders) {
        projection->values = DeckLibraryQueries::cardVariants(cards, deck, grouped);
        projection->cards = cards;
        projection->mainboard = deck.mainboard;
        projection->sideboard = deck.sideboard;
        projection->commanders = deck.commanders;
        projection->valid = true;
    }
    return projection->values;
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
    return std::any_of(m_decks.cbegin(), m_decks.cend(), [this](const Deck &deck) {
        const ImageCounts &counts = imageCounts(deck);
        return counts.missing > 0 || counts.considerMissing > 0;
    });
}

const DeckLibraryModel::ImageCounts &DeckLibraryModel::imageCounts(const Deck &deck) const
{
    ImageCounts &counts = m_imageCounts[deck.id];
    const auto sameStorage = [](const QVector<DeckCard> &left, const QVector<DeckCard> &right) {
        return left.constData() == right.constData() && left.size() == right.size();
    };
    // UI bindings share one filesystem pass per deck revision. Cache/storage
    // refreshes invalidate this snapshot; match registration still performs its
    // own live check through DeckLibraryQueries::matchPayload().
    if (!counts.valid || !sameStorage(counts.mainboard, deck.mainboard) ||
        !sameStorage(counts.sideboard, deck.sideboard) ||
        !sameStorage(counts.consider, deck.consider)) {
        counts.missing = DeckLibraryQueries::missingImageCount(deck);
        counts.considerMissing = DeckLibraryQueries::missingImageCount(deck.consider);
        counts.mainboard = deck.mainboard;
        counts.sideboard = deck.sideboard;
        counts.consider = deck.consider;
        counts.valid = true;
    }
    return counts;
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

void DeckLibraryModel::rebuildCardDeckIndex(int editedDeckIndex)
{
    ++m_cardLocationRevision;
    const bool rebuildAll = editedDeckIndex < 0;
    if (rebuildAll) {
        m_cardLocationsByName.clear();
        m_indexedCardNamesByDeck.clear();
    } else {
        const QSet<QString> previousNames =
            m_indexedCardNamesByDeck.take(m_decks.at(editedDeckIndex).id);
        for (const QString &name : previousNames) {
            auto locations = m_cardLocationsByName.find(name);
            if (locations == m_cardLocationsByName.end())
                continue;
            locations->removeIf([editedDeckIndex](const CardLocation &location) {
                return location.deckIndex == editedDeckIndex;
            });
            if (locations->isEmpty())
                m_cardLocationsByName.erase(locations);
        }
    }
    const int firstDeckIndex = rebuildAll ? 0 : editedDeckIndex;
    const int endDeckIndex = rebuildAll ? static_cast<int>(m_decks.size()) : editedDeckIndex + 1;
    for (int deckIndex = firstDeckIndex; deckIndex < endDeckIndex; ++deckIndex) {
        const Deck &deck = m_decks.at(deckIndex);
        QSet<QString> &names = m_indexedCardNamesByDeck[deck.id];
        const auto append = [this, deckIndex, &names](const QVector<DeckCard> &cards,
                                                      CardSection section) {
            for (int cardIndex = 0; cardIndex < cards.size(); ++cardIndex) {
                const QString name = normalizedCardName(cards.at(cardIndex).name);
                names.insert(name);
                m_cardLocationsByName[name].append(CardLocation{deckIndex, section, cardIndex});
            }
        };
        append(deck.mainboard, CardSection::Mainboard);
        append(deck.sideboard, CardSection::Sideboard);
        append(deck.consider, CardSection::Consider);
    }
}

const DeckCard *DeckLibraryModel::cardAt(const CardLocation &location) const
{
    if (location.deckIndex < 0 || location.deckIndex >= m_decks.size())
        return nullptr;
    const Deck &deck = m_decks.at(location.deckIndex);
    const QVector<DeckCard> *cards = nullptr;
    switch (location.section) {
    case CardSection::Mainboard:
        cards = &deck.mainboard;
        break;
    case CardSection::Sideboard:
        cards = &deck.sideboard;
        break;
    case CardSection::Consider:
        cards = &deck.consider;
        break;
    default:
        return nullptr;
    }
    if (location.cardIndex < 0 || location.cardIndex >= cards->size())
        return nullptr;
    return &cards->at(location.cardIndex);
}

DeckCard *DeckLibraryModel::cardAt(const CardLocation &location)
{
    if (location.deckIndex < 0 || location.deckIndex >= m_decks.size())
        return nullptr;
    Deck &deck = m_decks[location.deckIndex];
    QVector<DeckCard> *cards = nullptr;
    switch (location.section) {
    case CardSection::Mainboard:
        cards = &deck.mainboard;
        break;
    case CardSection::Sideboard:
        cards = &deck.sideboard;
        break;
    case CardSection::Consider:
        cards = &deck.consider;
        break;
    default:
        return nullptr;
    }
    if (location.cardIndex < 0 || location.cardIndex >= cards->size())
        return nullptr;
    return &(*cards)[location.cardIndex];
}

void DeckLibraryModel::notifyCurrentDeckChanged(bool cardsChanged)
{
    const Deck *deck = currentDeck();
    if (!deck)
        return;
    const bool shouldBeVisible =
        m_formatFilter == QStringLiteral("all") || deck->deckFormat == m_formatFilter;
    const auto visible =
        std::find_if(m_visibleRows.cbegin(), m_visibleRows.cend(),
                     [this, deck](int row) { return m_decks.at(row).id == deck->id; });
    if (shouldBeVisible != (visible != m_visibleRows.cend())) {
        beginResetModel();
        rebuildVisibleRows();
        endResetModel();
    }
    notifyDecksChanged({deck->id}, cardsChanged);
}

void DeckLibraryModel::notifyCardStructureChanged()
{
    for (int deckIndex = 0; deckIndex < m_decks.size(); ++deckIndex) {
        if (m_decks.at(deckIndex).id == m_currentDeckId) {
            rebuildCardDeckIndex(deckIndex);
            break;
        }
    }
    notifyCurrentDeckChanged();
}

void DeckLibraryModel::notifyDecksChanged(const QSet<QString> &deckIds, bool cardsChanged)
{
    // An ordinary structural save has no deferred metadata to publish. Empty
    // IDs must not reach resolveDisplayPaths(), where they mean the whole library.
    if (deckIds.isEmpty())
        return;
    if (cardsChanged)
        resolveDisplayPaths(deckIds);
    static const QList<int> changedRoles{
        NameRole,
        FormatRole,
        TableModeRole,
        MainCountRole,
        SideboardCountRole,
        CommanderRole,
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
