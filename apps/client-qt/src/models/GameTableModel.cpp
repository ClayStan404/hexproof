// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "GameTableModel.h"

#include <utility>

using namespace Qt::StringLiterals;

namespace hexproof::client {

GameTableModel::GameTableModel(QObject *parent)
    : QAbstractListModel(parent),
      m_stackModel(new ZoneCardModel(this)),
      m_revealedModel(new ZoneCardModel(this))
{
}

GameTableModel::~GameTableModel()
{
    for (SeatZoneModels *models : std::as_const(m_zoneModelsBySeat))
        delete models;
}

int GameTableModel::rowCount(const QModelIndex &parent) const
{
    return parent.isValid() ? 0 : m_seats.size();
}

QVariant GameTableModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() < 0 || index.row() >= m_seats.size())
        return {};
    const QVariantMap seat = m_seats.at(index.row()).toMap();
    switch (role) {
    case SeatRole:
        return seat.value(u"seat"_s, -1);
    case DisplayNameRole:
        return seat.value(u"displayName"_s);
    case LifeRole:
        return seat.value(u"life"_s);
    case CountersRole:
        return seat.value(u"counters"_s);
    case CounterCountRole:
        return seat.value(u"counterCount"_s);
    case LibraryCountRole:
        return seat.value(u"libraryCount"_s);
    case HandCountRole:
        return seat.value(u"handCount"_s);
    case MulliganCountRole:
        return seat.value(u"mulliganCount"_s);
    case SideboardCountRole:
        return seat.value(u"sideboardCount"_s);
    case CommanderTaxRole:
        return seat.value(u"commanderTax"_s);
    case CommanderTaxesRole:
        return seat.value(u"commanderTaxes"_s);
    case EliminatedRole:
        return seat.value(u"eliminated"_s);
    case ModelRevisionRole:
        return seat.value(u"modelRevision"_s);
    case HandModelRole:
        return QVariant::fromValue(
            static_cast<QObject *>(seatZoneModel(seat.value(u"seat"_s, -1).toInt(), u"hand"_s)));
    case SideboardModelRole:
        return QVariant::fromValue(static_cast<QObject *>(
            seatZoneModel(seat.value(u"seat"_s, -1).toInt(), u"sideboard"_s)));
    case BattlefieldModelRole:
        return QVariant::fromValue(static_cast<QObject *>(
            seatZoneModel(seat.value(u"seat"_s, -1).toInt(), u"battlefield"_s)));
    case GraveyardModelRole:
        return QVariant::fromValue(static_cast<QObject *>(
            seatZoneModel(seat.value(u"seat"_s, -1).toInt(), u"graveyard"_s)));
    case ExileModelRole:
        return QVariant::fromValue(
            static_cast<QObject *>(seatZoneModel(seat.value(u"seat"_s, -1).toInt(), u"exile"_s)));
    case CommandZoneModelRole:
        return QVariant::fromValue(
            static_cast<QObject *>(seatZoneModel(seat.value(u"seat"_s, -1).toInt(), u"command"_s)));
    default:
        return {};
    }
}

QHash<int, QByteArray> GameTableModel::roleNames() const
{
    return {
        {SeatRole, "seat"},
        {DisplayNameRole, "displayName"},
        {LifeRole, "life"},
        {CountersRole, "counters"},
        {CounterCountRole, "counterCount"},
        {LibraryCountRole, "libraryCount"},
        {HandCountRole, "handCount"},
        {MulliganCountRole, "mulliganCount"},
        {SideboardCountRole, "sideboardCount"},
        {CommanderTaxRole, "commanderTax"},
        {CommanderTaxesRole, "commanderTaxes"},
        {EliminatedRole, "eliminated"},
        {ModelRevisionRole, "modelRevision"},
        {HandModelRole, "handModel"},
        {SideboardModelRole, "sideboardModel"},
        {BattlefieldModelRole, "battlefieldModel"},
        {GraveyardModelRole, "graveyardModel"},
        {ExileModelRole, "exileModel"},
        {CommandZoneModelRole, "commandZoneModel"},
    };
}

QVariantList GameTableModel::seats() const
{
    return m_seats;
}

QVariantList GameTableModel::stackCards() const
{
    return m_stackCards;
}

QVariantList GameTableModel::revealedCards() const
{
    return m_revealedCards;
}

QVariantList GameTableModel::arrows() const
{
    return m_arrows;
}

QVariantList GameTableModel::attachments() const
{
    return m_attachments;
}

QVariantList GameTableModel::commanders() const
{
    return m_commanders;
}

QVariantList GameTableModel::commanderDamage() const
{
    return m_commanderDamage;
}

QVariantList GameTableModel::gameLog() const
{
    return m_gameLog;
}

int GameTableModel::landPlaysThisTurn() const
{
    return m_landPlaysThisTurn;
}

ZoneCardModel *GameTableModel::stackModel() const
{
    return m_stackModel;
}

ZoneCardModel *GameTableModel::revealedModel() const
{
    return m_revealedModel;
}

quint64 GameTableModel::cardIndexRevision() const
{
    return m_cardIndexRevision;
}

QVariantMap GameTableModel::seatData(int seat) const
{
    const auto row = m_rowForSeat.constFind(seat);
    return row == m_rowForSeat.cend() ? QVariantMap{} : m_seats.at(*row).toMap();
}

QObject *GameTableModel::zoneModel(int seat, const QString &zone) const
{
    if (zone == u"stack"_s)
        return m_stackModel;
    if (zone == u"reveal"_s || zone == u"revealed"_s)
        return m_revealedModel;
    return seatZoneModel(seat, zone);
}

QVariantMap GameTableModel::cardData(const QString &cardId) const
{
    return m_cardById.value(cardId);
}

bool GameTableModel::cardInZone(const QString &cardId, const QString &zone, int seat) const
{
    return m_seatForZoneCard.value(zoneCardKey(cardId, zone), -2) == seat;
}

int GameTableModel::visibleZoneSeat(const QString &cardId, const QString &zone) const
{
    return m_seatForZoneCard.value(zoneCardKey(cardId, zone), -1);
}

QVariantMap GameTableModel::attachmentForSource(const QString &cardId) const
{
    return m_attachmentBySource.value(cardId);
}

QVariantMap GameTableModel::arrowForSeat(int seat) const
{
    return m_arrowBySeat.value(seat);
}

QVariantMap GameTableModel::arrowForSource(const QString &cardId) const
{
    return m_arrowBySource.value(cardId);
}

void GameTableModel::applySnapshot(const QVariantMap &snapshot)
{
    if (snapshot == m_snapshot)
        return;

    const QVariantList rawSeats = listValue(snapshot, u"seats"_s);
    QVariantList nextSeats;
    nextSeats.reserve(rawSeats.size());
    QSet<int> presentSeats;
    QVector<ZoneUpdate> zoneUpdates;
    for (const QVariant &value : rawSeats) {
        const QVariantMap rawSeat = value.toMap();
        const int seatNumber = rawSeat.value(u"seat"_s, -1).toInt();
        presentSeats.insert(seatNumber);

        QVariantMap metadata = seatMetadata(rawSeat);
        QVariantMap previousMetadata;
        const auto previousRow = m_rowForSeat.constFind(seatNumber);
        if (previousRow != m_rowForSeat.cend()) {
            previousMetadata = m_seats.at(*previousRow).toMap();
            previousMetadata.remove(u"modelRevision"_s);
        }
        quint64 revision = m_seatRevisions.value(seatNumber, 0);
        if (revision == 0 || previousMetadata != metadata)
            ++revision;
        m_seatRevisions.insert(seatNumber, revision);
        metadata.insert(u"modelRevision"_s, revision);
        nextSeats.append(metadata);

        appendSeatZoneUpdates(zoneUpdates, seatNumber, rawSeat);
    }

    for (auto iterator = m_zoneModelsBySeat.cbegin(); iterator != m_zoneModelsBySeat.cend();
         ++iterator) {
        if (presentSeats.contains(iterator.key()))
            continue;
        const SeatZoneModels *models = iterator.value();
        appendZoneUpdate(zoneUpdates, iterator.key(), u"hand"_s, {}, models->hand);
        appendZoneUpdate(zoneUpdates, iterator.key(), u"sideboard"_s, {}, models->sideboard);
        appendZoneUpdate(zoneUpdates, iterator.key(), u"battlefield"_s, {}, models->battlefield);
        appendZoneUpdate(zoneUpdates, iterator.key(), u"graveyard"_s, {}, models->graveyard);
        appendZoneUpdate(zoneUpdates, iterator.key(), u"exile"_s, {}, models->exile);
        appendZoneUpdate(zoneUpdates, iterator.key(), u"command"_s, {}, models->commandZone);
    }
    for (auto iterator = m_seatRevisions.begin(); iterator != m_seatRevisions.end();) {
        if (presentSeats.contains(iterator.key()))
            ++iterator;
        else
            iterator = m_seatRevisions.erase(iterator);
    }

    const QVariantList nextStack = listValue(snapshot, u"stack"_s);
    const QVariantList nextRevealed = listValue(snapshot, u"revealed"_s);
    appendZoneUpdate(zoneUpdates, -1, u"stack"_s, nextStack, m_stackModel);
    appendZoneUpdate(zoneUpdates, -1, u"reveal"_s, nextRevealed, m_revealedModel);

    bool seatStructureChanged = nextSeats.size() != m_seats.size();
    if (!seatStructureChanged) {
        for (int row = 0; row < nextSeats.size(); ++row) {
            if (nextSeats.at(row).toMap().value(u"seat"_s, -1) !=
                m_seats.at(row).toMap().value(u"seat"_s, -1)) {
                seatStructureChanged = true;
                break;
            }
        }
    }
    if (seatStructureChanged)
        beginResetModel();

    const QVariantList previousSeats = m_seats;
    m_snapshot = snapshot;
    m_seats = nextSeats;
    m_stackCards = nextStack;
    m_revealedCards = nextRevealed;
    // Child zone models emit granular signals while they reconcile below.
    // Rebuild the indexed seat lookup first so QML reacting to those signals
    // never observes rows from the new snapshot through an index from the old
    // snapshot.
    m_rowForSeat.clear();
    for (int row = 0; row < m_seats.size(); ++row)
        m_rowForSeat.insert(m_seats.at(row).toMap().value(u"seat"_s, -1).toInt(), row);
    // Zone contents and the card indexes are refreshed before any seat-row
    // signal below, so a delegate reacting to dataChanged or to a child zone
    // model always reads current cards. The child ZoneCardModel instances are
    // separate models, so their granular signals are valid inside this type's
    // own reset bracket; do not reorder these three steps independently.
    applyZoneUpdates(zoneUpdates);

    const QVariantList nextAttachments = listValue(snapshot, u"attachments"_s);
    if (m_attachments != nextAttachments) {
        m_attachments = nextAttachments;
        rebuildAttachmentIndex();
    }
    const QVariantList nextArrows = listValue(snapshot, u"arrows"_s);
    if (m_arrows != nextArrows) {
        m_arrows = nextArrows;
        rebuildArrowIndex();
    }
    const QVariantList nextLog = listValue(snapshot, u"log"_s);
    if (m_gameLog != nextLog)
        m_gameLog = nextLog;
    m_landPlaysThisTurn = snapshot.value(u"landPlaysThisTurn"_s).toInt();
    m_commanders = listValue(snapshot, u"commanders"_s);
    m_commanderDamage = listValue(snapshot, u"commanderDamage"_s);

    if (seatStructureChanged) {
        endResetModel();
    } else {
        for (int row = 0; row < m_seats.size(); ++row) {
            if (previousSeats.at(row) != m_seats.at(row))
                emit dataChanged(index(row), index(row));
        }
    }
    emit snapshotChanged();
}

void GameTableModel::clear()
{
    applySnapshot({});
}

QVariantList GameTableModel::listValue(const QVariantMap &map, const QString &key)
{
    return map.value(key).toList();
}

QVariantMap GameTableModel::seatMetadata(const QVariantMap &seat)
{
    QVariantMap result = seat;
    result.remove(u"hand"_s);
    result.remove(u"sideboard"_s);
    result.remove(u"battlefield"_s);
    result.remove(u"graveyard"_s);
    result.remove(u"exile"_s);
    result.remove(u"commandZone"_s);
    result.remove(u"modelRevision"_s);
    return result;
}

QString GameTableModel::zoneCardKey(const QString &cardId, const QString &zone)
{
    return zone + u'\x1f' + cardId;
}

QString GameTableModel::zoneStorageKey(int seat, const QString &zone)
{
    return QString::number(seat) + u'\x1f' + zone;
}

GameTableModel::SeatZoneModels *GameTableModel::ensureSeatZoneModels(int seat)
{
    const auto existing = m_zoneModelsBySeat.constFind(seat);
    if (existing != m_zoneModelsBySeat.cend())
        return *existing;

    auto *models = new SeatZoneModels{
        new ZoneCardModel(this), new ZoneCardModel(this), new ZoneCardModel(this),
        new ZoneCardModel(this), new ZoneCardModel(this), new ZoneCardModel(this),
    };
    m_zoneModelsBySeat.insert(seat, models);
    return models;
}

ZoneCardModel *GameTableModel::seatZoneModel(int seat, const QString &zone) const
{
    const SeatZoneModels *models = m_zoneModelsBySeat.value(seat);
    if (!models)
        return nullptr;
    if (zone == u"hand"_s)
        return models->hand;
    if (zone == u"sideboard"_s)
        return models->sideboard;
    if (zone == u"battlefield"_s)
        return models->battlefield;
    if (zone == u"graveyard"_s)
        return models->graveyard;
    if (zone == u"exile"_s)
        return models->exile;
    if (zone == u"command"_s || zone == u"commandZone"_s)
        return models->commandZone;
    return nullptr;
}

void GameTableModel::appendZoneUpdate(QVector<ZoneUpdate> &updates, int seat, const QString &zone,
                                      const QVariantList &cards, ZoneCardModel *model)
{
    if (m_cardsByZone.value(zoneStorageKey(seat, zone)) == cards)
        return;
    updates.append(ZoneUpdate{seat, zone, cards, model});
}

void GameTableModel::appendSeatZoneUpdates(QVector<ZoneUpdate> &updates, int seat,
                                           const QVariantMap &seatData)
{
    SeatZoneModels *models = ensureSeatZoneModels(seat);
    appendZoneUpdate(updates, seat, u"hand"_s, listValue(seatData, u"hand"_s), models->hand);
    appendZoneUpdate(updates, seat, u"sideboard"_s, listValue(seatData, u"sideboard"_s),
                     models->sideboard);
    appendZoneUpdate(updates, seat, u"battlefield"_s, listValue(seatData, u"battlefield"_s),
                     models->battlefield);
    appendZoneUpdate(updates, seat, u"graveyard"_s, listValue(seatData, u"graveyard"_s),
                     models->graveyard);
    appendZoneUpdate(updates, seat, u"exile"_s, listValue(seatData, u"exile"_s), models->exile);
    appendZoneUpdate(updates, seat, u"command"_s, listValue(seatData, u"commandZone"_s),
                     models->commandZone);
}

void GameTableModel::applyZoneUpdates(const QVector<ZoneUpdate> &updates)
{
    if (updates.isEmpty())
        return;

    for (const ZoneUpdate &update : updates) {
        const QVariantList previous = m_cardsByZone.value(zoneStorageKey(update.seat, update.zone));
        for (const QVariant &value : previous) {
            const QString cardId = value.toMap().value(u"id"_s).toString();
            if (cardId.isEmpty())
                continue;
            m_cardById.remove(cardId);
            m_seatForZoneCard.remove(zoneCardKey(cardId, update.zone));
        }
    }

    for (const ZoneUpdate &update : updates) {
        const QString storageKey = zoneStorageKey(update.seat, update.zone);
        if (update.cards.isEmpty())
            m_cardsByZone.remove(storageKey);
        else
            m_cardsByZone.insert(storageKey, update.cards);
        if (update.model)
            update.model->replaceCards(update.cards);
        indexCards(update.cards, update.zone, update.seat);
    }
    ++m_cardIndexRevision;
}

void GameTableModel::indexCards(const QVariantList &cards, const QString &zone, int seat)
{
    for (const QVariant &value : cards) {
        const QVariantMap card = value.toMap();
        const QString cardId = card.value(u"id"_s).toString();
        if (cardId.isEmpty())
            continue;
        m_cardById.insert(cardId, card);
        m_seatForZoneCard.insert(zoneCardKey(cardId, zone), seat);
    }
}

void GameTableModel::rebuildAttachmentIndex()
{
    m_attachmentBySource.clear();
    for (const QVariant &value : m_attachments) {
        const QVariantMap attachment = value.toMap();
        m_attachmentBySource.insert(attachment.value(u"sourceCardId"_s).toString(), attachment);
    }
}

void GameTableModel::rebuildArrowIndex()
{
    m_arrowBySeat.clear();
    m_arrowBySource.clear();
    for (const QVariant &value : m_arrows) {
        const QVariantMap arrow = value.toMap();
        m_arrowBySeat.insert(arrow.value(u"seat"_s, -1).toInt(), arrow);
        m_arrowBySource.insert(arrow.value(u"sourceCardId"_s).toString(), arrow);
    }
}

} // namespace hexproof::client
