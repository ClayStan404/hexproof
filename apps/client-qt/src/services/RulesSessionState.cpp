// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "RulesSessionState.h"

#include "RulesLaneSlotModel.h"
#include "protocol/WireConstantsGenerated.h"

#include <QHash>
#include <QJsonArray>
#include <QSet>
#include <utility>

namespace hexproof::client {

namespace {
using namespace Qt::StringLiterals;

QVector<RulesNamedValue> parseNamedValues(const QJsonArray &array)
{
    QVector<RulesNamedValue> result;
    result.reserve(array.size());
    for (const QJsonValue &value : array) {
        const QJsonObject item = value.toObject();
        result.append({item.value(u"name"_s).toString(), item.value(u"value"_s).toInt()});
    }
    return result;
}

void applyIdentity(const QJsonObject &identity, QString &name, QString &setCode,
                   QString &collectorNumber, bool &token)
{
    name = identity.value(u"name"_s).toString();
    setCode = identity.value(u"setCode"_s).toString();
    collectorNumber = identity.value(u"collectorNumber"_s).toString();
    token = identity.value(u"token"_s).toBool();
}

bool parseTargetSeat(const QJsonObject &target, RulesPromptTargetRow &row)
{
    const QJsonValue value = target.value(u"seat"_s);
    if (value.isUndefined())
        return true;
    const int seat = value.toInt(-1);
    if (row.kind != u"player"_s || !value.isDouble() || seat < 0 || value.toDouble() != seat)
        return false;
    row.seat = seat;
    return true;
}
} // namespace

void RulesSessionState::setPresentationCatalog(QObject *catalog)
{
    if (m_presentationCatalog == catalog)
        return;
    m_presentationCatalog = catalog;
    for (RulesLaneSlotModel *model : m_laneSlots)
        model->setCatalog(catalog);
}

void RulesSessionState::beginLaneBatch()
{
    for (RulesLaneSlotModel *model : std::as_const(m_laneSlots))
        model->beginBatch();
}

void RulesSessionState::endLaneBatch()
{
    for (RulesLaneSlotModel *model : std::as_const(m_laneSlots))
        model->endBatch();
}

QAbstractItemModel *RulesSessionState::laneSlots(int seat, const QString &zone,
                                                 const QString &category)
{
    if (seat < 0 || zone.isEmpty() || (zone == u"battlefield"_s && category.isEmpty()))
        return nullptr;
    const QString key = QString::number(seat) + u'\u001f' + zone + u'\u001f' + category;
    if (RulesLaneSlotModel *existing = m_laneSlots.value(key))
        return existing;
    QAbstractItemModel *source = zone == u"battlefield"_s
                                     ? static_cast<QAbstractItemModel *>(&m_battlefieldCards)
                                     : static_cast<QAbstractItemModel *>(&m_zoneCards);
    auto *model = new RulesLaneSlotModel(source, seat, zone, category, this);
    model->setCatalog(m_presentationCatalog);
    m_laneSlots.insert(key, model);
    return model;
}

QAbstractItemModel *RulesSessionState::battlefieldCardsForSeat(int seat)
{
    if (seat < 0)
        return nullptr;
    if (auto *model = m_seatBattlefields.value(seat))
        return model;
    // Filter the already-redacted projection before QML creates card delegates.
    // A permanent follows its controller, including cards owned by another seat.
    auto *model = new QSortFilterProxyModel(this);
    model->setSourceModel(&m_battlefieldCards);
    model->setFilterRole(RulesCardModel::ControllerSeatRole);
    model->setFilterRegularExpression(u"^%1$"_s.arg(seat));
    m_seatBattlefields.insert(seat, model);
    return model;
}

namespace {
// One seat's rows of one zone, in source order. A filter proxy reports source
// moves as a layout change, which makes QML views rebuild every delegate; this
// model diffs by card id instead, so a reordered hand keeps its delegates.
class RulesZoneSubsetModel final : public QAbstractListModel
{
  public:
    RulesZoneSubsetModel(const RulesCardModel &source, int seat, QString zone, QObject *parent)
        : QAbstractListModel(parent),
          m_source(source),
          m_seat(seat),
          m_zone(std::move(zone))
    {
        const auto sync = [this] { this->sync(); };
        connect(&source, &QAbstractItemModel::rowsInserted, this, sync);
        connect(&source, &QAbstractItemModel::rowsRemoved, this, sync);
        connect(&source, &QAbstractItemModel::rowsMoved, this, sync);
        connect(&source, &QAbstractItemModel::modelReset, this, sync);
        connect(&source, &QAbstractItemModel::layoutChanged, this, sync);
        connect(&source, &QAbstractItemModel::dataChanged, this,
                [this](const QModelIndex &top, const QModelIndex &bottom, const QList<int> &roles) {
                    forwardChanges(top.row(), bottom.row(), roles);
                });
        sync();
    }

    int rowCount(const QModelIndex &parent = {}) const override
    {
        return parent.isValid() ? 0 : int(m_ids.size());
    }

    QVariant data(const QModelIndex &index, int role) const override
    {
        if (!index.isValid() || index.row() >= m_ids.size())
            return {};
        const int row = sourceRow(index.row());
        return row < 0 ? QVariant{} : m_source.data(m_source.index(row), role);
    }

    QHash<int, QByteArray> roleNames() const override
    {
        return m_source.roleNames();
    }

  private:
    QString sourceId(int row) const
    {
        return m_source.data(m_source.index(row), RulesCardModel::IdRole).toString();
    }

    bool accepts(int row) const
    {
        const QModelIndex index = m_source.index(row);
        return m_source.data(index, RulesCardModel::ZoneOwnerSeatRole).toInt() == m_seat &&
               m_source.data(index, RulesCardModel::ZoneRole).toString() == m_zone;
    }

    // Rows keep their synced position until the next sync. While a sync moves
    // rows, ids are unique and resolve through the id map.
    int sourceRow(int row) const
    {
        const QString &id = m_ids.at(row);
        const auto valid = [this, &id](int candidate) {
            return candidate >= 0 && candidate < m_source.rowCount() && sourceId(candidate) == id;
        };
        if (const int positioned = m_rows.value(row, -1); valid(positioned))
            return positioned;
        if (const int mapped = m_rowsById.value(id, -1); valid(mapped))
            return mapped;
        for (int candidate = 0; candidate < m_source.rowCount(); ++candidate) {
            if (sourceId(candidate) == id)
                return candidate;
        }
        return -1;
    }

    void sync()
    {
        QStringList next;
        QList<int> nextRows;
        m_rowsById.clear();
        for (int row = 0; row < m_source.rowCount(); ++row) {
            if (!accepts(row))
                continue;
            const QString id = sourceId(row);
            next.append(id);
            nextRows.append(row);
            m_rowsById.insert(id, row);
        }
        if (next == m_ids) {
            m_rows = std::move(nextRows);
            return;
        }
        const QSet<QString> nextIds(next.cbegin(), next.cend());
        const QSet<QString> currentIds(m_ids.cbegin(), m_ids.cend());
        // Empty or repeated ids cannot keep delegates safely.
        if (nextIds.size() != next.size() || currentIds.size() != m_ids.size() ||
            nextIds.contains(QString())) {
            beginResetModel();
            m_ids = std::move(next);
            m_rows = std::move(nextRows);
            endResetModel();
            return;
        }
        for (qsizetype row = m_ids.size() - 1; row >= 0; --row) {
            if (nextIds.contains(m_ids.at(row)))
                continue;
            beginRemoveRows({}, int(row), int(row));
            m_ids.removeAt(row);
            endRemoveRows();
        }
        for (qsizetype target = 0; target < next.size(); ++target) {
            const qsizetype from = m_ids.indexOf(next.at(target), target);
            if (from < 0) {
                beginInsertRows({}, int(target), int(target));
                m_ids.insert(target, next.at(target));
                endInsertRows();
            } else if (from != target) {
                beginMoveRows({}, int(from), int(from), {}, int(target));
                m_ids.move(from, target);
                endMoveRows();
            }
        }
        m_rows = std::move(nextRows);
    }

    void forwardChanges(int first, int last, const QList<int> &roles)
    {
        for (int row = first; row <= last; ++row) {
            const qsizetype at = m_rows.indexOf(row);
            if ((at >= 0 && m_ids.at(at) != sourceId(row)) || accepts(row) != (at >= 0)) {
                sync();
                return;
            }
            if (at >= 0)
                emit dataChanged(index(int(at)), index(int(at)), roles);
        }
    }

    const RulesCardModel &m_source;
    int m_seat;
    QString m_zone;
    QStringList m_ids;
    QList<int> m_rows;
    QHash<QString, int> m_rowsById;
};
} // namespace

QAbstractItemModel *RulesSessionState::zoneCardsFor(int seat, const QString &zone)
{
    if (seat < 0 || zone.isEmpty())
        return nullptr;
    const QString key = u"%1/%2"_s.arg(seat).arg(zone);
    if (auto *model = m_seatZones.value(key))
        return model;
    // Like battlefieldCardsForSeat(): only the rows a view shows get delegates.
    auto *model = new RulesZoneSubsetModel(m_zoneCards, seat, zone, this);
    m_seatZones.insert(key, model);
    return model;
}

QVariantList RulesSessionState::cardActionsForCard(const QString &cardId) const
{
    if (!m_promptPending || !m_promptSupported ||
        (m_promptKind != u"chooseAction"_s && m_promptKind != u"payManaCost"_s &&
         m_promptKind != u"mulligan"_s))
        return {};
    const QVariantList actions = m_promptOptions.cardActionsForCard(cardId);
    if (m_promptKind != u"mulligan"_s)
        return actions;
    QVariantList abilities;
    for (const QVariant &action : actions) {
        if (action.toMap().value(u"kind"_s).toString() == u"activateAbility"_s)
            abilities.append(action);
    }
    return abilities;
}

QVariantList RulesSessionState::boardTargetCandidates() const
{
    if (!m_promptPending || !m_promptSupported || m_promptKind != u"chooseBoardTargets"_s)
        return {};
    return m_promptTargets.items();
}

QVariantList RulesSessionState::promptOptionItems() const
{
    if (!m_promptPending || !m_promptSupported)
        return {};
    return m_promptOptions.items();
}

QStringList RulesSessionState::stackObjectIds() const
{
    QStringList result;
    for (int row = 0; row < m_stack.rowCount(); ++row)
        result.append(m_stack.data(m_stack.index(row), RulesStackModel::IdRole).toString());
    return result;
}

QStringList RulesSessionState::targetResponseIdsForObject(const QString &kind,
                                                          const QString &objectId) const
{
    if (!m_promptPending || !m_promptSupported || m_promptKind != u"chooseBoardTargets"_s)
        return {};
    return m_promptTargets.responseIdsForObject(kind, objectId);
}

QStringList RulesSessionState::targetResponseIdsForSeat(int seat) const
{
    if (!m_promptPending || !m_promptSupported || m_promptKind != u"chooseBoardTargets"_s)
        return {};
    return m_promptTargets.responseIdsForSeat(seat);
}

// The row index is published after the model announces its new rows. A binding
// that runs during that announcement must still see the row that is already in
// place, so a mismatched index falls back to a scan.
static int indexedCardRow(const QAbstractListModel &model, const QHash<QString, int> &rows,
                          int idRole, const QString &cardId)
{
    const auto found = rows.constFind(cardId);
    if (found != rows.cend()) {
        const QModelIndex indexed = model.index(*found);
        if (indexed.isValid() && model.data(indexed, idRole).toString() == cardId)
            return *found;
    }
    for (int row = 0; row < model.rowCount(); ++row) {
        if (model.data(model.index(row), idRole).toString() == cardId)
            return row;
    }
    return -1;
}

QVariantMap RulesSessionState::cardForInspection(const QString &cardId) const
{
    if (cardId.isEmpty())
        return {};
    const auto readRow = [](const QAbstractListModel &model, int row) {
        QVariantMap result;
        if (row < 0)
            return result;
        const QModelIndex index = model.index(row);
        const auto roles = model.roleNames();
        for (auto it = roles.cbegin(); it != roles.cend(); ++it)
            result.insert(QString::fromUtf8(it.value()), model.data(index, it.key()));
        return result;
    };
    // Reuse the current viewer projection. Never resolve identities from another
    // zone, the catalog, or an earlier snapshot after visibility changes.
    QVariantMap card =
        readRow(m_battlefieldCards, indexedCardRow(m_battlefieldCards, m_battlefieldIndex,
                                                   RulesCardModel::IdRole, cardId));
    if (!card.isEmpty())
        return card;
    card = readRow(m_zoneCards,
                   indexedCardRow(m_zoneCards, m_zoneIndex, RulesCardModel::IdRole, cardId));
    if (!card.isEmpty())
        return card.value(u"visibleIdentity"_s).toBool() ? card : QVariantMap{};
    card = readRow(m_stack, indexedCardRow(m_stack, m_stackIndex, RulesStackModel::IdRole, cardId));
    if (!card.isEmpty()) {
        card.insert(u"cardId"_s, card.take(u"objectId"_s));
        card.insert(u"zone"_s, u"stack"_s);
        card.insert(u"visibleIdentity"_s, !card.value(u"name"_s).toString().isEmpty());
        card.insert(u"faceDown"_s, card.value(u"rulesText"_s) == u"Face-down spell"_s);
    }
    return card;
}

QVariantMap RulesSessionState::cardPlacement(const QString &cardId) const
{
    if (cardId.isEmpty())
        return {};
    const auto placement = [](const RulesCardModel &model, int row) {
        const QModelIndex index = model.index(row);
        return QVariantMap{
            {u"zone"_s, model.data(index, RulesCardModel::ZoneRole)},
            {u"zoneOwnerSeat"_s, model.data(index, RulesCardModel::ZoneOwnerSeatRole)},
            {u"visibleIdentity"_s, model.data(index, RulesCardModel::VisibleRole)}};
    };
    int row =
        indexedCardRow(m_battlefieldCards, m_battlefieldIndex, RulesCardModel::IdRole, cardId);
    if (row >= 0)
        return placement(m_battlefieldCards, row);
    row = indexedCardRow(m_zoneCards, m_zoneIndex, RulesCardModel::IdRole, cardId);
    if (row >= 0) {
        return m_zoneCards.data(m_zoneCards.index(row), RulesCardModel::VisibleRole).toBool()
                   ? placement(m_zoneCards, row)
                   : QVariantMap{};
    }
    row = indexedCardRow(m_stack, m_stackIndex, RulesStackModel::IdRole, cardId);
    if (row >= 0) {
        const QString name = m_stack.data(m_stack.index(row), RulesStackModel::NameRole).toString();
        return {{u"zone"_s, u"stack"_s}, {u"visibleIdentity"_s, !name.isEmpty()}};
    }
    return {};
}

int RulesSessionState::controllingSeat(int seat) const
{
    for (int row = 0; row < m_players.rowCount(); ++row) {
        const QModelIndex index = m_players.index(row);
        if (m_players.data(index, RulesPlayerModel::SeatRole).toInt() == seat)
            return m_players.data(index, RulesPlayerModel::ControllingSeatRole).toInt();
    }
    return seat;
}

QVariantMap RulesSessionState::topPublicZoneCard(int ownerSeat, const QString &zone) const
{
    QVariantMap face;
    if (zone.isEmpty())
        return face;
    const auto roles = m_zoneCards.roleNames();
    for (int row = 0; row < m_zoneCards.rowCount(); ++row) {
        const QModelIndex index = m_zoneCards.index(row);
        if (m_zoneCards.data(index, RulesCardModel::ZoneOwnerSeatRole).toInt() != ownerSeat)
            continue;
        if (m_zoneCards.data(index, RulesCardModel::ZoneRole).toString() != zone)
            continue;
        face.clear();
        for (auto it = roles.cbegin(); it != roles.cend(); ++it)
            face.insert(QString::fromUtf8(it.value()), m_zoneCards.data(index, it.key()));
    }
    return face;
}

RulesSessionState::RulesSessionState(QObject *parent)
    : QObject(parent),
      m_players(this),
      m_zones(this),
      m_battlefieldCards(this),
      m_zoneCards(this),
      m_stack(this),
      m_promptOptions(this),
      m_promptChoices(this),
      m_promptCards(this),
      m_promptContextCards(this),
      m_promptContextTargets(this),
      m_promptTargets(this),
      m_promptCombat(this),
      m_promptDamageTargets(this)
{
}

bool validPaymentId(const QString &id)
{
    if (id.size() < 1 || id.size() > 64)
        return false;
    const auto letter = [](QChar character) {
        return (character >= u'A' && character <= u'Z') || (character >= u'a' && character <= u'z');
    };
    if (!letter(id.at(0)))
        return false;
    for (const QChar character : id) {
        if (letter(character) || (character >= u'0' && character <= u'9') || character == u':' ||
            character == u'_' || character == u'-')
            continue;
        return false;
    }
    return true;
}

bool RulesSessionState::applyPrompt(const QJsonObject &prompt)
{
    const QString roomId = prompt.value(u"roomId"_s).toString();
    const QString gameId = prompt.value(u"gameId"_s).toString();
    if (roomId.isEmpty() || gameId.isEmpty() || !prompt.value(u"options"_s).isArray() ||
        !prompt.value(u"choices"_s).isArray() || !prompt.value(u"cards"_s).isArray() ||
        !prompt.value(u"scryDestinations"_s).isArray() || !prompt.value(u"targets"_s).isArray() ||
        !prompt.value(u"contextCards"_s).isArray() ||
        !prompt.value(u"contextTargets"_s).isArray() ||
        !prompt.value(u"combatSources"_s).isArray() ||
        !prompt.value(u"combatTargets"_s).isArray() || !prompt.value(u"damageTargets"_s).isArray())
        return false;
    if (!m_roomId.isEmpty() && (roomId != m_roomId || gameId != m_gameId))
        return false;
    const QJsonValue autoPassEligible = prompt.value(u"autoPassEligible"_s);
    if (!autoPassEligible.isUndefined() && !autoPassEligible.isBool())
        return false;

    QVector<RulesPromptOptionRow> options;
    const QJsonArray optionArray = prompt.value(u"options"_s).toArray();
    options.reserve(optionArray.size());
    for (const QJsonValue &value : optionArray) {
        const QJsonObject option = value.toObject();
        RulesPromptOptionRow row{
            option.value(u"responseId"_s).toString(), option.value(u"kind"_s).toString(),
            option.value(u"label"_s).toString(), option.value(u"cardId"_s).toString()};
        if (row.responseId.isEmpty() || row.label.isEmpty())
            return false;
        options.append(std::move(row));
    }
    QVector<RulesChoiceRow> choices;
    QSet<QString> choiceIds;
    const QJsonArray choiceArray = prompt.value(u"choices"_s).toArray();
    choices.reserve(choiceArray.size());
    for (const QJsonValue &value : choiceArray) {
        const QJsonObject choice = value.toObject();
        RulesChoiceRow row{choice.value(u"responseId"_s).toString(),
                           choice.value(u"label"_s).toString(), choice.value(u"weight"_s).toInt(),
                           choice.value(u"canRepeat"_s).toBool()};
        if (!row.responseId.startsWith(u"choice:"_s) || row.label.isEmpty() || row.weight <= 0 ||
            choiceIds.contains(row.responseId)) {
            return false;
        }
        choiceIds.insert(row.responseId);
        choices.append(std::move(row));
    }
    QVector<RulesPromptCardRow> cards;
    QSet<QString> cardIds;
    const QJsonArray cardArray = prompt.value(u"cards"_s).toArray();
    cards.reserve(cardArray.size());
    for (const QJsonValue &value : cardArray) {
        const QJsonObject card = value.toObject();
        RulesPromptCardRow row{
            card.value(u"id"_s).toString(),      card.value(u"name"_s).toString(),
            card.value(u"setCode"_s).toString(), card.value(u"collectorNumber"_s).toString(),
            card.value(u"token"_s).toBool(),     card.value(u"selected"_s).toBool(),
            card.value(u"readOnly"_s).toBool()};
        if (row.id.isEmpty() || cardIds.contains(row.id))
            return false;
        cardIds.insert(row.id);
        cards.append(std::move(row));
    }
    QVector<RulesPromptCardRow> contextCards;
    QSet<QString> contextCardIds;
    const QJsonArray contextCardArray = prompt.value(u"contextCards"_s).toArray();
    if (contextCardArray.size() > 1)
        return false;
    contextCards.reserve(contextCardArray.size());
    for (const QJsonValue &value : contextCardArray) {
        const QJsonObject card = value.toObject();
        RulesPromptCardRow row{card.value(u"id"_s).toString(), card.value(u"name"_s).toString(),
                               card.value(u"setCode"_s).toString(),
                               card.value(u"collectorNumber"_s).toString(),
                               card.value(u"token"_s).toBool()};
        if (!row.id.startsWith(u"context-card:"_s) || row.name.isEmpty() ||
            contextCardIds.contains(row.id)) {
            return false;
        }
        contextCardIds.insert(row.id);
        contextCards.append(std::move(row));
    }
    QStringList scryDestinations;
    QSet<QString> seenScryDestinations;
    const QSet<QString> supportedScryDestinations{u"libraryTop"_s, u"libraryBottom"_s,
                                                  u"graveyard"_s, u"exile"_s, u"hand"_s};
    for (const QJsonValue &value : prompt.value(u"scryDestinations"_s).toArray()) {
        const QString destination = value.toString();
        if (!supportedScryDestinations.contains(destination) ||
            seenScryDestinations.contains(destination) || scryDestinations.size() >= 5) {
            return false;
        }
        seenScryDestinations.insert(destination);
        scryDestinations.append(destination);
    }
    QString paymentId;
    const QJsonValue rawPaymentId = prompt.value(u"paymentId"_s);
    if (!rawPaymentId.isUndefined() && !rawPaymentId.isNull()) {
        if (!rawPaymentId.isString())
            return false;
        paymentId = rawPaymentId.toString();
        // The id only enables click-ahead. A malformed one turns it off
        // instead of blocking the payment.
        if (!validPaymentId(paymentId))
            paymentId.clear();
    }
    const QString promptKind = prompt.value(u"kind"_s).toString();
    if (promptKind != u"payManaCost"_s)
        paymentId.clear();
    if ((promptKind == u"scry"_s) != !scryDestinations.isEmpty())
        return false;
    if (promptKind == u"scry"_s) {
        for (const RulesPromptCardRow &card : cards) {
            if (!card.id.startsWith(u"scry:"_s))
                return false;
        }
    }
    const int requiredSelections = prompt.value(u"requiredSelections"_s).toInt();
    if (requiredSelections < 0 || requiredSelections > cards.size())
        return false;
    const int minCardSelections = prompt.value(u"minCardSelections"_s).toInt();
    const int maxCardSelections = prompt.value(u"maxCardSelections"_s).toInt();
    if (minCardSelections < 0 || maxCardSelections < minCardSelections ||
        maxCardSelections > cards.size()) {
        return false;
    }
    QVector<RulesOrderRow> orderItems;
    QSet<QString> orderIds;
    const QJsonArray orderArray = prompt.value(u"orderItems"_s).toArray();
    orderItems.reserve(orderArray.size());
    for (const QJsonValue &value : orderArray) {
        const QJsonObject item = value.toObject();
        RulesOrderRow row{
            item.value(u"responseId"_s).toString(), item.value(u"name"_s).toString(),
            item.value(u"setCode"_s).toString(),    item.value(u"collectorNumber"_s).toString(),
            item.value(u"token"_s).toBool(),        item.value(u"oracle"_s).toString()};
        if (!row.responseId.startsWith(u"order:"_s) || orderIds.contains(row.responseId))
            return false;
        orderIds.insert(row.responseId);
        orderItems.append(std::move(row));
    }
    QVector<RulesPromptTargetRow> targets;
    QSet<QString> targetIds;
    const QJsonArray targetArray = prompt.value(u"targets"_s).toArray();
    targets.reserve(targetArray.size());
    for (const QJsonValue &value : targetArray) {
        const QJsonObject target = value.toObject();
        RulesPromptTargetRow row{
            target.value(u"responseId"_s).toString(),
            target.value(u"kind"_s).toString(),
            target.value(u"label"_s).toString(),
            target.value(u"objectId"_s).toString(),
            target.value(u"name"_s).toString(),
            target.value(u"setCode"_s).toString(),
            target.value(u"collectorNumber"_s).toString(),
            target.value(u"token"_s).toBool(),
        };
        if (row.responseId.isEmpty() || row.kind.isEmpty() || row.label.isEmpty() ||
            targetIds.contains(row.responseId) || !parseTargetSeat(target, row))
            return false;
        if (target.contains(u"selected"_s) && !target.value(u"selected"_s).isBool())
            return false;
        row.nativeSelected = target.value(u"selected"_s).toBool();
        targetIds.insert(row.responseId);
        targets.append(std::move(row));
    }
    QVector<RulesPromptTargetRow> contextTargets;
    QSet<QString> contextTargetIds;
    const QJsonArray contextTargetArray = prompt.value(u"contextTargets"_s).toArray();
    contextTargets.reserve(contextTargetArray.size());
    for (const QJsonValue &value : contextTargetArray) {
        const QJsonObject target = value.toObject();
        RulesPromptTargetRow row{
            target.value(u"responseId"_s).toString(),
            target.value(u"kind"_s).toString(),
            target.value(u"label"_s).toString(),
            target.value(u"objectId"_s).toString(),
            target.value(u"name"_s).toString(),
            target.value(u"setCode"_s).toString(),
            target.value(u"collectorNumber"_s).toString(),
            target.value(u"token"_s).toBool(),
        };
        if (!row.responseId.startsWith(u"context-target:"_s) || row.kind.isEmpty() ||
            row.label.isEmpty() || contextTargetIds.contains(row.responseId) ||
            !parseTargetSeat(target, row)) {
            return false;
        }
        contextTargetIds.insert(row.responseId);
        contextTargets.append(std::move(row));
    }
    const int minSelections = prompt.value(u"minSelections"_s).toInt();
    const int maxSelections = prompt.value(u"maxSelections"_s).toInt();
    if (minSelections < 0 || maxSelections < minSelections || maxSelections > targets.size())
        return false;
    const int minChoiceTotal = prompt.value(u"minChoiceTotal"_s).toInt();
    const int maxChoiceTotal = prompt.value(u"maxChoiceTotal"_s).toInt();
    const int minNumber = prompt.value(u"minNumber"_s).toInt();
    const int maxNumber = prompt.value(u"maxNumber"_s).toInt();
    if (minChoiceTotal < 0 || maxChoiceTotal < minChoiceTotal || maxChoiceTotal > 512 ||
        minNumber > maxNumber) {
        return false;
    }
    QVector<RulesCombatTargetRow> combatTargets;
    QSet<QString> combatTargetIds;
    const QJsonArray combatTargetArray = prompt.value(u"combatTargets"_s).toArray();
    combatTargets.reserve(combatTargetArray.size());
    for (const QJsonValue &value : combatTargetArray) {
        const QJsonObject target = value.toObject();
        RulesCombatTargetRow row{
            target.value(u"responseId"_s).toString(),
            target.value(u"kind"_s).toString(),
            target.value(u"label"_s).toString(),
            target.value(u"objectId"_s).toString(),
            target.value(u"name"_s).toString(),
            target.value(u"setCode"_s).toString(),
            target.value(u"collectorNumber"_s).toString(),
            target.value(u"token"_s).toBool(),
            target.value(u"minAssignments"_s).toInt(),
            target.value(u"maxAssignments"_s).toInt(),
            target.value(u"mustReceiveIfAble"_s).toBool(),
            target.value(u"seat"_s).toInt(-1),
        };
        if (row.responseId.isEmpty() || row.kind.isEmpty() || row.label.isEmpty() ||
            row.minimum < 0 || row.maximum < 0 || combatTargetIds.contains(row.responseId)) {
            return false;
        }
        combatTargetIds.insert(row.responseId);
        combatTargets.append(std::move(row));
    }
    QVector<RulesCombatSourceRow> combatSources;
    QSet<QString> combatSourceIds;
    const QJsonArray combatSourceArray = prompt.value(u"combatSources"_s).toArray();
    combatSources.reserve(combatSourceArray.size());
    for (const QJsonValue &value : combatSourceArray) {
        const QJsonObject source = value.toObject();
        RulesCombatSourceRow row{
            source.value(u"responseId"_s).toString(),
            source.value(u"objectId"_s).toString(),
            source.value(u"label"_s).toString(),
            source.value(u"name"_s).toString(),
            source.value(u"setCode"_s).toString(),
            source.value(u"collectorNumber"_s).toString(),
            source.value(u"token"_s).toBool(),
            {},
            source.value(u"mustAssignIfAble"_s).toBool(),
            source.value(u"maxAssignments"_s).toInt(1),
        };
        const QJsonValue maximum = source.value(u"maxAssignments"_s);
        if (row.responseId.isEmpty() || row.objectId.isEmpty() || row.label.isEmpty() ||
            row.maximum < 0 || row.maximum > 512 ||
            (!maximum.isUndefined() &&
             (!maximum.isDouble() || maximum.toDouble() != row.maximum)) ||
            (prompt.value(u"kind"_s).toString() == u"chooseAttackers"_s && row.maximum > 1) ||
            !source.value(u"validTargetIds"_s).isArray() ||
            combatSourceIds.contains(row.responseId)) {
            return false;
        }
        QSet<QString> validTargetIds;
        for (const QJsonValue &targetIdValue : source.value(u"validTargetIds"_s).toArray()) {
            const QString targetId = targetIdValue.toString();
            if (targetId.isEmpty() || !combatTargetIds.contains(targetId) ||
                validTargetIds.contains(targetId)) {
                return false;
            }
            validTargetIds.insert(targetId);
            row.validTargetIds.append(targetId);
        }
        combatSourceIds.insert(row.responseId);
        combatSources.append(std::move(row));
    }
    const bool damagePrompt = promptKind == u"chooseDamageAssignmentOrder"_s ||
                              promptKind == u"chooseCombatDamageAssignment"_s;
    QString damageAssignmentMode = protocol::kRulesDamageOrdered;
    if (prompt.contains(u"damageAssignmentMode"_s)) {
        damageAssignmentMode = prompt.value(u"damageAssignmentMode"_s).toString();
        if (damageAssignmentMode != protocol::kRulesDamageOrdered &&
            damageAssignmentMode != protocol::kRulesDamageUnordered &&
            damageAssignmentMode != protocol::kRulesDamageDivideFreely) {
            return false;
        }
    }
    QVariantMap damageSource;
    if (prompt.value(u"damageSource"_s).isObject()) {
        const QJsonObject source = prompt.value(u"damageSource"_s).toObject();
        damageSource = {{u"objectId"_s, source.value(u"objectId"_s).toString()},
                        {u"label"_s, source.value(u"label"_s).toString()},
                        {u"name"_s, source.value(u"name"_s).toString()},
                        {u"setCode"_s, source.value(u"setCode"_s).toString()},
                        {u"collectorNumber"_s, source.value(u"collectorNumber"_s).toString()},
                        {u"token"_s, source.value(u"token"_s).toBool()}};
    }
    QVector<RulesDamageTargetRow> damageTargets;
    QSet<QString> damageTargetIds;
    const QJsonArray damageTargetArray = prompt.value(u"damageTargets"_s).toArray();
    damageTargets.reserve(damageTargetArray.size());
    for (const QJsonValue &value : damageTargetArray) {
        const QJsonObject target = value.toObject();
        RulesDamageTargetRow row{
            target.value(u"responseId"_s).toString(),
            target.value(u"kind"_s).toString(),
            target.value(u"label"_s).toString(),
            target.value(u"objectId"_s).toString(),
            target.value(u"name"_s).toString(),
            target.value(u"setCode"_s).toString(),
            target.value(u"collectorNumber"_s).toString(),
            target.value(u"token"_s).toBool(),
            target.value(u"lethalDamage"_s).toInt(-2),
        };
        if (!row.responseId.startsWith(u"damage-target:"_s) || row.kind.isEmpty() ||
            row.label.isEmpty() || row.lethalDamage < -1 ||
            damageTargetIds.contains(row.responseId)) {
            return false;
        }
        damageTargetIds.insert(row.responseId);
        damageTargets.append(std::move(row));
    }
    const int totalDamage = prompt.value(u"totalDamage"_s).toInt(-1);
    if (totalDamage < 0 ||
        (damagePrompt &&
         (damageSource.value(u"objectId"_s).toString().isEmpty() ||
          damageSource.value(u"label"_s).toString().isEmpty() || damageTargets.isEmpty())) ||
        (!damagePrompt && (!damageSource.isEmpty() || !damageTargets.isEmpty()))) {
        return false;
    }
    m_promptPending = prompt.value(u"pending"_s).toBool();
    m_promptId = prompt.value(u"promptId"_s).toInteger();
    m_promptKind = promptKind;
    m_promptPaymentId = paymentId;
    m_promptSupported = prompt.value(u"supported"_s).toBool();
    m_promptAutoPassEligible = m_promptPending && m_promptSupported &&
                               promptKind == u"chooseAction"_s && autoPassEligible.toBool();
    m_promptTitle = prompt.value(u"title"_s).toString();
    m_promptDetail = prompt.value(u"detail"_s).toString();
    m_promptContextText = prompt.value(u"contextText"_s).toString();
    m_promptRequiredSelections = requiredSelections;
    m_promptMinCardSelections = minCardSelections;
    m_promptMaxCardSelections = maxCardSelections;
    m_promptMinSelections = minSelections;
    m_promptMaxSelections = maxSelections;
    m_promptCancellable = prompt.value(u"cancellable"_s).toBool();
    m_promptMinChoiceTotal = minChoiceTotal;
    m_promptMaxChoiceTotal = maxChoiceTotal;
    m_promptMinNumber = minNumber;
    m_promptMaxNumber = maxNumber;
    m_promptDamageSource = std::move(damageSource);
    m_promptTotalDamage = totalDamage;
    m_promptDamageDeathtouch = prompt.value(u"damageDeathtouch"_s).toBool();
    m_promptDamageAssignmentMode = damageAssignmentMode;
    if (!m_promptPending) {
        m_promptId = 0;
        m_promptKind.clear();
        m_promptPaymentId.clear();
        m_promptSupported = false;
        m_promptAutoPassEligible = false;
        m_promptTitle.clear();
        m_promptDetail.clear();
        m_promptRequiredSelections = 0;
        m_promptMinCardSelections = 0;
        m_promptMaxCardSelections = 0;
        m_promptMinSelections = 0;
        m_promptMaxSelections = 0;
        m_promptCancellable = false;
        m_promptMinChoiceTotal = 0;
        m_promptMaxChoiceTotal = 0;
        m_promptMinNumber = 0;
        m_promptMaxNumber = 0;
        options.clear();
        choices.clear();
        cards.clear();
        contextCards.clear();
        contextTargets.clear();
        m_promptContextText.clear();
        scryDestinations.clear();
        orderItems.clear();
        targets.clear();
        combatSources.clear();
        combatTargets.clear();
        m_promptDamageSource.clear();
        damageTargets.clear();
        m_promptTotalDamage = 0;
        m_promptDamageDeathtouch = false;
        m_promptDamageAssignmentMode = protocol::kRulesDamageOrdered;
    }
    m_promptOptions.replace(std::move(options));
    m_promptChoices.replace(std::move(choices));
    m_promptCards.replace(std::move(cards));
    m_promptContextCards.replace(std::move(contextCards));
    m_promptContextTargets.replace(std::move(contextTargets));
    m_promptScryDestinations = std::move(scryDestinations);
    m_promptOrderItems.replace(std::move(orderItems));
    m_promptTargets.replace(std::move(targets));
    m_promptCombat.replace(std::move(combatSources), std::move(combatTargets));
    m_promptDamageTargets.replace(std::move(damageTargets));
    refreshCardPresentations();
    emit promptChanged();
    return true;
}

QVariantMap trackedObject(const QString &id, const QString &zone, int owner, int controller,
                          const QString &name, bool tapped, int damage, bool attacking)
{
    return {{u"id"_s, id},         {u"zone"_s, zone},
            {u"owner"_s, owner},   {u"controller"_s, controller},
            {u"name"_s, name},     {u"tapped"_s, tapped},
            {u"damage"_s, damage}, {u"attacking"_s, attacking}};
}

QVariantList trackedCards(const QVector<RulesCardRow> &cards, const QVector<RulesStackRow> &stack)
{
    QVariantList result;
    QSet<QString> seen;
    const auto append = [&](const QVariantMap &object) {
        const QString id = object.value(u"id"_s).toString();
        if (id.isEmpty() || seen.contains(id))
            return;
        seen.insert(id);
        result.append(object);
    };
    for (const RulesCardRow &card : cards) {
        append(trackedObject(card.id, card.zone, card.zoneOwnerSeat, card.controllerSeat,
                             card.visible && !card.faceDown ? card.name : QString(), card.tapped,
                             card.damage, card.attacking));
    }
    for (const RulesStackRow &row : stack) {
        append(trackedObject(row.id, u"stack"_s, row.ownerSeat, row.controllerSeat, row.name, false,
                             0, false));
    }
    return result;
}

QVariantList trackedZones(const QVector<RulesZoneRow> &zones)
{
    QVariantList result;
    for (const RulesZoneRow &zone : zones)
        result.append(QVariantMap{
            {u"zone"_s, zone.zone}, {u"seat"_s, zone.ownerSeat}, {u"count"_s, zone.count}});
    return result;
}

QVariantMap trackedLife(const QVector<RulesPlayerRow> &players)
{
    QVariantMap result;
    for (const RulesPlayerRow &player : players)
        result.insert(QString::number(player.seat), player.life);
    return result;
}

QHash<QString, QVariantMap> objectsById(const QVariantList &objects)
{
    QHash<QString, QVariantMap> result;
    for (const QVariant &value : objects) {
        const QVariantMap object = value.toMap();
        const QString id = object.value(u"id"_s).toString();
        if (!id.isEmpty())
            result.insert(id, object);
    }
    return result;
}

int zoneCount(const QVariantList &zones, const QString &zone, int seat)
{
    for (const QVariant &value : zones) {
        const QVariantMap row = value.toMap();
        if (row.value(u"zone"_s).toString() == zone && row.value(u"seat"_s).toInt() == seat)
            return row.value(u"count"_s).toInt();
    }
    return 0;
}

bool flightCovered(const QString &from, const QString &to)
{
    return (from == u"hand"_s && (to == u"stack"_s || to == u"battlefield"_s)) ||
           (from == u"stack"_s &&
            (to == u"battlefield"_s || to == u"graveyard"_s || to == u"exile"_s)) ||
           (from == u"battlefield"_s &&
            (to == u"graveyard"_s || to == u"exile"_s || to == u"hand"_s || to == u"command"_s)) ||
           (from == u"library"_s && to == u"hand"_s) ||
           (from == u"command"_s && to == u"battlefield"_s);
}

QString transitionCategory(const QString &kind, const QString &from, const QString &to)
{
    if (from == u"stack"_s || to == u"stack"_s || kind == u"stackPush"_s ||
        kind == u"stackResolve"_s)
        return u"stack"_s;
    if (kind == u"death"_s || (from == u"battlefield"_s && to == u"graveyard"_s))
        return u"death"_s;
    if (kind == u"attack"_s || kind == u"block"_s)
        return u"combat"_s;
    if (kind == u"life"_s || kind == u"damage"_s)
        return u"damage"_s;
    if (kind == u"move"_s || kind == u"enter"_s || kind == u"leave"_s)
        return u"move"_s;
    return {};
}

QVariantMap transitionEvent(const QString &kind, const QString &id, const QString &from,
                            const QString &to, int owner, int controller, const QString &name,
                            int amount)
{
    const QString category = transitionCategory(kind, from, to);
    return {
        {u"kind"_s, kind},        {u"id"_s, id},           {u"fromZone"_s, from},
        {u"toZone"_s, to},        {u"ownerSeat"_s, owner}, {u"controllerSeat"_s, controller},
        {u"name"_s, name},        {u"amount"_s, amount},   {u"flight"_s, flightCovered(from, to)},
        {u"category"_s, category}};
}

QString linkKey(const QVariant &value)
{
    const QVariantMap link = value.toMap();
    return link.value(u"kind"_s).toString() + u"|"_s + link.value(u"sourceId"_s).toString() +
           u"|"_s + link.value(u"targetId"_s).toString() + u"|"_s +
           QString::number(link.value(u"targetSeat"_s, -1).toInt());
}

QVariantList diffTransitions(const QVariantList &previousObjects, const QVariantList &nextObjects,
                             const QVariantList &previousZones, const QVariantList &nextZones,
                             const QVariantMap &previousLife, const QVariantMap &nextLife,
                             const QVariantList &previousLinks, const QVariantList &nextLinks)
{
    const QHash<QString, QVariantMap> before = objectsById(previousObjects);
    const QHash<QString, QVariantMap> after = objectsById(nextObjects);
    QVariantList events;
    QSet<QString> consumed;
    for (auto iterator = after.cbegin(); iterator != after.cend(); ++iterator) {
        if (!before.contains(iterator.key()))
            continue;
        const QVariantMap &left = before.value(iterator.key());
        const QVariantMap &right = iterator.value();
        consumed.insert(iterator.key());
        const QString from = left.value(u"zone"_s).toString();
        const QString to = right.value(u"zone"_s).toString();
        const QString name = right.value(u"name"_s).toString().isEmpty()
                                 ? left.value(u"name"_s).toString()
                                 : right.value(u"name"_s).toString();
        if (from != to) {
            const QString kind =
                from == u"battlefield"_s && to == u"graveyard"_s ? u"death"_s : u"move"_s;
            events.append(transitionEvent(kind, iterator.key(), from, to,
                                          right.value(u"owner"_s).toInt(),
                                          right.value(u"controller"_s).toInt(), name, 0));
        } else {
            if (left.value(u"tapped"_s).toBool() != right.value(u"tapped"_s).toBool()) {
                events.append(
                    transitionEvent(right.value(u"tapped"_s).toBool() ? u"tap"_s : u"untap"_s,
                                    iterator.key(), from, to, right.value(u"owner"_s).toInt(),
                                    right.value(u"controller"_s).toInt(), name, 0));
            }
            const int damage = right.value(u"damage"_s).toInt() - left.value(u"damage"_s).toInt();
            if (damage != 0) {
                events.append(transitionEvent(u"damage"_s, iterator.key(), from, to,
                                              right.value(u"owner"_s).toInt(),
                                              right.value(u"controller"_s).toInt(), name, damage));
            }
            if (!left.value(u"attacking"_s).toBool() && right.value(u"attacking"_s).toBool()) {
                events.append(transitionEvent(u"attack"_s, iterator.key(), from, to,
                                              right.value(u"owner"_s).toInt(),
                                              right.value(u"controller"_s).toInt(), name, 0));
            }
        }
    }
    struct Side
    {
        QString id;
        QString zone;
        int owner = -1;
        int controller = -1;
        QString name;
    };
    QHash<QString, QVector<Side>> departed;
    QHash<QString, QVector<Side>> arrived;
    const auto remember = [](QHash<QString, QVector<Side>> &bucket, const QVariantMap &object) {
        const QString name = object.value(u"name"_s).toString();
        if (name.isEmpty())
            return;
        const QString key = name + u"\n"_s + QString::number(object.value(u"owner"_s).toInt());
        bucket[key].append(
            Side{object.value(u"id"_s).toString(), object.value(u"zone"_s).toString(),
                 object.value(u"owner"_s).toInt(), object.value(u"controller"_s).toInt(), name});
    };
    for (auto iterator = before.cbegin(); iterator != before.cend(); ++iterator) {
        if (!consumed.contains(iterator.key()))
            remember(departed, iterator.value());
    }
    for (auto iterator = after.cbegin(); iterator != after.cend(); ++iterator) {
        if (!consumed.contains(iterator.key()))
            remember(arrived, iterator.value());
    }
    QSet<QString> inferred;
    for (auto iterator = departed.cbegin(); iterator != departed.cend(); ++iterator) {
        const QVector<Side> &left = iterator.value();
        const QVector<Side> right = arrived.value(iterator.key());
        if (left.size() != 1 || right.size() != 1)
            continue;
        inferred.insert(left.first().id);
        inferred.insert(right.first().id);
        const QString kind =
            left.first().zone == u"battlefield"_s && right.first().zone == u"graveyard"_s
                ? u"death"_s
                : u"move"_s;
        events.append(transitionEvent(kind, right.first().id, left.first().zone, right.first().zone,
                                      right.first().owner, right.first().controller,
                                      right.first().name, 0));
    }
    for (auto iterator = before.cbegin(); iterator != before.cend(); ++iterator) {
        if (consumed.contains(iterator.key()) || inferred.contains(iterator.key()))
            continue;
        const QVariantMap &object = iterator.value();
        const QString zone = object.value(u"zone"_s).toString();
        events.append(transitionEvent(zone == u"stack"_s ? u"stackResolve"_s : u"leave"_s,
                                      iterator.key(), zone, {}, object.value(u"owner"_s).toInt(),
                                      object.value(u"controller"_s).toInt(),
                                      object.value(u"name"_s).toString(), 0));
    }
    QHash<int, int> hiddenHandArrivals;
    for (auto iterator = after.cbegin(); iterator != after.cend(); ++iterator) {
        if (consumed.contains(iterator.key()) || inferred.contains(iterator.key()))
            continue;
        const QVariantMap &object = iterator.value();
        const QString zone = object.value(u"zone"_s).toString();
        if (zone == u"hand"_s && object.value(u"name"_s).toString().isEmpty())
            ++hiddenHandArrivals[object.value(u"owner"_s).toInt()];
        events.append(transitionEvent(zone == u"stack"_s ? u"stackPush"_s : u"enter"_s,
                                      iterator.key(), {}, zone, object.value(u"owner"_s).toInt(),
                                      object.value(u"controller"_s).toInt(),
                                      object.value(u"name"_s).toString(), 0));
    }
    QSet<int> seats;
    for (const QVariant &value : previousZones)
        seats.insert(value.toMap().value(u"seat"_s).toInt());
    for (const QVariant &value : nextZones)
        seats.insert(value.toMap().value(u"seat"_s).toInt());
    for (const int seat : seats) {
        const int drawn =
            zoneCount(nextZones, u"hand"_s, seat) - zoneCount(previousZones, u"hand"_s, seat);
        const int fromLibrary =
            zoneCount(previousZones, u"library"_s, seat) - zoneCount(nextZones, u"library"_s, seat);
        int unexplained = qMin(drawn, fromLibrary);
        if (unexplained <= 0)
            continue;
        unexplained = qMax(0, unexplained - hiddenHandArrivals.value(seat));
        for (int index = 0; index < unexplained; ++index) {
            events.append(transitionEvent(u"move"_s, u"hidden-draw:%1:%2"_s.arg(seat).arg(index),
                                          u"library"_s, u"hand"_s, seat, seat, {}, 0));
        }
    }
    QSet<QString> seatsLife;
    for (const QString &seat : previousLife.keys())
        seatsLife.insert(seat);
    for (const QString &seat : nextLife.keys())
        seatsLife.insert(seat);
    for (const QString &seat : seatsLife) {
        if (!previousLife.contains(seat) || !nextLife.contains(seat))
            continue;
        const int amount = nextLife.value(seat).toInt() - previousLife.value(seat).toInt();
        if (amount != 0) {
            events.append(transitionEvent(u"life"_s, u"player:"_s + seat, {}, {}, seat.toInt(),
                                          seat.toInt(), {}, amount));
        }
    }
    QSet<QString> oldLinks;
    for (const QVariant &link : previousLinks)
        oldLinks.insert(linkKey(link));
    for (const QVariant &link : nextLinks) {
        if (oldLinks.contains(linkKey(link)))
            continue;
        const QVariantMap map = link.toMap();
        if (map.value(u"kind"_s).toString() != u"block"_s)
            continue;
        events.append(transitionEvent(u"block"_s, map.value(u"sourceId"_s).toString(),
                                      u"battlefield"_s, u"battlefield"_s, -1, -1, {}, 0));
    }
    return events;
}

bool RulesSessionState::applySnapshot(const QJsonObject &snapshot)
{
    const QString roomId = snapshot.value(u"roomId"_s).toString();
    const QString gameId = snapshot.value(u"gameId"_s).toString();
    if (roomId.isEmpty() || gameId.isEmpty() || !snapshot.value(u"players"_s).isArray() ||
        !snapshot.value(u"zones"_s).isArray() || !snapshot.value(u"stack"_s).isArray()) {
        return false;
    }

    QVector<RulesPlayerRow> players;
    const QJsonArray playerArray = snapshot.value(u"players"_s).toArray();
    players.reserve(playerArray.size());
    for (const QJsonValue &value : playerArray) {
        const QJsonObject player = value.toObject();
        RulesPlayerRow row;
        row.seat = player.value(u"seat"_s).toInt(-1);
        row.controllingSeat = player.value(u"controllingSeat"_s).toInt(row.seat);
        row.name = player.value(u"name"_s).toString();
        row.status = player.value(u"status"_s).toString();
        row.life = player.value(u"life"_s).toInt();
        row.counters = parseNamedValues(player.value(u"counters"_s).toArray());
        row.manaPool = parseNamedValues(player.value(u"manaPool"_s).toArray());
        for (const QJsonValue &commanderValue : player.value(u"commanders"_s).toArray()) {
            const QJsonObject commander = commanderValue.toObject();
            const QString name = commander.value(u"name"_s).toString();
            const int casts = commander.value(u"casts"_s).toInt(-1);
            const int tax = commander.value(u"tax"_s).toInt(-1);
            if (name.isEmpty() || casts < 0 || tax < 0)
                continue;
            row.commanders.append(
                QVariantMap{{u"name"_s, name},
                            {u"casts"_s, casts},
                            {u"tax"_s, tax},
                            {u"zone"_s, commander.value(u"zone"_s).toString(u"hidden"_s)},
                            {u"objectId"_s, commander.value(u"objectId"_s).toString()}});
        }
        players.append(std::move(row));
    }

    QVector<RulesZoneRow> zones;
    QVector<RulesCardRow> battlefieldCards;
    QVector<RulesCardRow> zoneCards;
    QVariantList relationships;
    const QJsonArray zoneArray = snapshot.value(u"zones"_s).toArray();
    zones.reserve(zoneArray.size());
    for (const QJsonValue &value : zoneArray) {
        const QJsonObject zone = value.toObject();
        RulesZoneRow zoneRow{zone.value(u"zone"_s).toString(), zone.value(u"ownerSeat"_s).toInt(-1),
                             zone.value(u"count"_s).toInt()};
        zones.append(zoneRow);
        for (const QJsonValue &cardValue : zone.value(u"cards"_s).toArray()) {
            const QJsonObject card = cardValue.toObject();
            RulesCardRow cardRow;
            cardRow.id = card.value(u"id"_s).toString();
            cardRow.zone = zoneRow.zone;
            cardRow.zoneOwnerSeat = zoneRow.ownerSeat;
            const bool declaredVisible = card.value(u"visible"_s).toBool();
            if (declaredVisible && card.value(u"identity"_s).isObject()) {
                applyIdentity(card.value(u"identity"_s).toObject(), cardRow.name, cardRow.setCode,
                              cardRow.collectorNumber, cardRow.token);
            }
            cardRow.visible = declaredVisible && !cardRow.name.isEmpty();
            cardRow.ownerSeat = card.value(u"ownerSeat"_s).toInt(-1);
            cardRow.controllerSeat = card.value(u"controllerSeat"_s).toInt(-1);
            cardRow.tapped = card.value(u"tapped"_s).toBool();
            cardRow.enteredThisTurn =
                zoneRow.zone == u"battlefield"_s && card.value(u"enteredThisTurn"_s).toBool();
            cardRow.summoningSick =
                zoneRow.zone == u"battlefield"_s && card.value(u"summoningSick"_s).toBool();
            cardRow.faceDown = card.value(u"faceDown"_s).toBool();
            cardRow.attacking = card.value(u"attacking"_s).toBool();
            cardRow.attackingTarget = card.value(u"attackingTarget"_s).toString();
            cardRow.attackingSeat = card.contains(u"attackingPlayer"_s)
                                        ? card.value(u"attackingPlayer"_s).toInt(-1)
                                        : -1;
            cardRow.power = card.value(u"power"_s).toString();
            cardRow.toughness = card.value(u"toughness"_s).toString();
            cardRow.damage = card.value(u"damage"_s).toInt();
            cardRow.attachedTo = card.value(u"attachedTo"_s).toString();
            cardRow.exiledCardCount = card.value(u"exiledCardCount"_s).toInt();
            for (const QJsonValue &linked : card.value(u"exiledCardIds"_s).toArray())
                cardRow.exiledCardIds.append(linked.toString());
            if (cardRow.visible && !cardRow.faceDown) {
                if (cardRow.zone == u"battlefield"_s) {
                    for (const QJsonValue &linked : card.value(u"chosenCardIds"_s).toArray())
                        cardRow.chosenCardIds.append(linked.toString());
                }
                for (const QJsonValue &value : card.value(u"annotations"_s).toArray()) {
                    const QJsonObject annotation = value.toObject();
                    const QString kind = annotation.value(u"kind"_s).toString();
                    const QString text = annotation.value(u"value"_s).toString();
                    const bool allowed = kind == u"dungeonRoom"_s
                                             ? cardRow.zone == u"command"_s
                                             : cardRow.zone == u"battlefield"_s;
                    if (allowed && !kind.isEmpty() && !text.isEmpty())
                        cardRow.annotations.append(
                            QVariantMap{{u"kind"_s, kind}, {u"value"_s, text}});
                }
            }
            cardRow.counters = parseNamedValues(card.value(u"counters"_s).toArray());
            if (cardRow.zone == u"battlefield"_s) {
                const auto appendRelationship = [&](const QString &kind, const QString &target) {
                    if (!target.isEmpty() && target != cardRow.id)
                        relationships.append(QVariantMap{{u"kind"_s, kind},
                                                         {u"sourceId"_s, cardRow.id},
                                                         {u"targetId"_s, target}});
                };
                appendRelationship(u"attachment"_s, cardRow.attachedTo);
                appendRelationship(u"attack"_s, cardRow.attackingTarget);
                for (const QJsonValue &target : card.value(u"blocking"_s).toArray())
                    appendRelationship(u"block"_s, target.toString());
                battlefieldCards.append(std::move(cardRow));
            } else if (cardRow.zone == u"hand"_s || cardRow.zone == u"graveyard"_s ||
                       cardRow.zone == u"exile"_s || cardRow.zone == u"command"_s ||
                       (cardRow.zone == u"library"_s && cardRow.visible && !cardRow.faceDown)) {
                zoneCards.append(std::move(cardRow));
            }
        }
    }

    QVector<RulesStackRow> stack;
    const QJsonArray stackArray = snapshot.value(u"stack"_s).toArray();
    stack.reserve(stackArray.size());
    for (const QJsonValue &value : stackArray) {
        const QJsonObject object = value.toObject();
        RulesStackRow row;
        row.id = object.value(u"id"_s).toString();
        row.sourceId = object.value(u"sourceId"_s).toString();
        row.controllerSeat = object.value(u"controllerSeat"_s).toInt(-1);
        row.ownerSeat = object.value(u"ownerSeat"_s).toInt(-1);
        applyIdentity(object.value(u"identity"_s).toObject(), row.name, row.setCode,
                      row.collectorNumber, row.token);
        row.text = object.value(u"text"_s).toString();
        for (const QJsonValue &targetValue : object.value(u"targets"_s).toArray()) {
            const QJsonObject target = targetValue.toObject();
            const QString kind = target.value(u"kind"_s).toString();
            const QString objectId = target.value(u"objectId"_s).toString();
            const int seat = target.value(u"seat"_s).toInt(-1);
            if ((kind == u"player" && seat >= 0) ||
                ((kind == u"card" || kind == u"spell") && !objectId.isEmpty())) {
                row.targets.append(QVariantMap{{u"kind"_s, kind},
                                               {u"objectId"_s, objectId},
                                               {u"seat"_s, seat},
                                               {u"label"_s, target.value(u"label"_s).toString()}});
            }
        }
        stack.append(std::move(row));
    }

    // A new game, the first snapshot, a reconnect and a replay seek jump. The
    // following single step diffs against whatever this update stored.
    const bool snap = std::exchange(m_jumpNextSnapshot, false) || m_gameId.isEmpty() ||
                      roomId != m_roomId || gameId != m_gameId || !m_recordTransitions;
    const QVariantList previousObjects = m_trackedObjects;
    const QVariantList previousZones = m_trackedZones;
    const QVariantMap previousLife = m_trackedLife;
    const QVariantList previousLinks = m_battlefieldRelationships;
    emit aboutToApplySnapshot(snap);
    // Prompt ids are scoped to a game. Never expose a previous game's decision
    // alongside the first snapshot of its replacement.
    if (!m_gameId.isEmpty() && (roomId != m_roomId || gameId != m_gameId))
        clear();
    m_publicReviewCards.clear();
    m_battlefieldRelationships.clear();
    QSet<QString> permanentIds;
    for (const RulesCardRow &card : battlefieldCards)
        permanentIds.insert(card.id);
    for (RulesCardRow &card : battlefieldCards) {
        if (!permanentIds.contains(card.attachedTo) || card.attachedTo == card.id)
            card.attachedTo.clear();
        if (!permanentIds.contains(card.attackingTarget) || card.attackingTarget == card.id)
            card.attackingTarget.clear();
        if (!card.attacking)
            card.attackingSeat = -1;
        else if (card.attackingTarget.isEmpty() && card.attackingSeat >= 0) {
            relationships.append(QVariantMap{{u"kind"_s, u"attack"_s},
                                             {u"sourceId"_s, card.id},
                                             {u"targetId"_s, QString()},
                                             {u"targetSeat"_s, card.attackingSeat}});
        }
    }
    for (const QVariant &relation : relationships) {
        const QVariantMap map = relation.toMap();
        const QString target = map.value(u"targetId"_s).toString();
        const int targetSeat = map.value(u"targetSeat"_s).toInt();
        const bool playerAttack = map.value(u"kind"_s).toString() == u"attack"_s &&
                                  target.isEmpty() && map.contains(u"targetSeat"_s) &&
                                  targetSeat >= 0;
        if ((playerAttack || permanentIds.contains(target)) &&
            !m_battlefieldRelationships.contains(relation))
            m_battlefieldRelationships.append(relation);
    }
    const auto appendPublicCards = [this](const QVector<RulesCardRow> &rows) {
        for (const RulesCardRow &card : rows) {
            if (card.zone == u"hand"_s || !card.visible || card.faceDown || card.name.isEmpty())
                continue;
            m_publicReviewCards.append(QVariantMap{{u"name"_s, card.name},
                                                   {u"setCode"_s, card.setCode},
                                                   {u"collectorNumber"_s, card.collectorNumber},
                                                   {u"token"_s, card.token},
                                                   {u"seat"_s, card.zoneOwnerSeat},
                                                   {u"zone"_s, card.zone}});
        }
    };
    appendPublicCards(battlefieldCards);
    appendPublicCards(zoneCards);
    QVector<RulesCardRow> presented = battlefieldCards;
    presented += zoneCards;
    const QVariantList nextObjects = trackedCards(presented, stack);
    const QVariantList nextZones = trackedZones(zones);
    const QVariantMap nextLife = trackedLife(players);
    m_transitions =
        snap ? QVariantList{}
             : diffTransitions(previousObjects, nextObjects, previousZones, nextZones, previousLife,
                               nextLife, previousLinks, m_battlefieldRelationships);
    m_transitionSnap = snap;
    m_trackedObjects = nextObjects;
    m_trackedZones = nextZones;
    m_trackedLife = nextLife;
    m_roomId = roomId;
    m_gameId = gameId;
    m_turn = snapshot.value(u"turn"_s).toInt();
    m_step = snapshot.value(u"step"_s).toString();
    m_activeSeat = snapshot.value(u"activeSeat"_s).toInt(-1);
    m_prioritySeat = snapshot.value(u"prioritySeat"_s).toInt(-1);
    m_gameOver = snapshot.value(u"gameOver"_s).toBool();
    m_hasWinner = snapshot.contains(u"winnerSeat"_s) && !snapshot.value(u"winnerSeat"_s).isNull();
    m_winnerSeat = m_hasWinner ? snapshot.value(u"winnerSeat"_s).toInt(-1) : -1;
    m_battlefieldCardCount = battlefieldCards.size();
    m_visibleZoneCardCount = zoneCards.size();
    m_players.replace(std::move(players));
    m_zones.replace(std::move(zones));
    beginLaneBatch();
    m_battlefieldCards.replace(std::move(battlefieldCards));
    m_zoneCards.replace(std::move(zoneCards));
    endLaneBatch();
    m_stack.replace(std::move(stack));
    const auto indexRows = [](const QAbstractListModel &model, int role,
                              QHash<QString, int> &index) {
        index.clear();
        for (int row = 0; row < model.rowCount(); ++row) {
            const QString id = model.data(model.index(row), role).toString();
            if (!id.isEmpty())
                index.insert(id, row);
        }
    };
    indexRows(m_battlefieldCards, RulesCardModel::IdRole, m_battlefieldIndex);
    indexRows(m_zoneCards, RulesCardModel::IdRole, m_zoneIndex);
    indexRows(m_stack, RulesStackModel::IdRole, m_stackIndex);
    refreshCardPresentations();
    ++m_snapshotRevision;
    emit snapshotChanged();
    emit transitionsChanged();
    return true;
}

void RulesSessionState::refreshCardPresentations()
{
    struct Offer
    {
        int count = 0;
        QString responseId;
        QString kind;
        QString hint;
    };
    QHash<QString, Offer> offers;
    const bool actionPrompt = m_promptPending && m_promptSupported &&
                              (m_promptKind == u"chooseAction"_s ||
                               m_promptKind == u"payManaCost"_s || m_promptKind == u"mulligan"_s);
    if (actionPrompt) {
        for (const QVariant &value : m_promptOptions.items()) {
            const QVariantMap option = value.toMap();
            const QString kind = option.value(u"kind"_s).toString();
            if (m_promptKind == u"mulligan"_s && kind != u"activateAbility"_s)
                continue;
            if (kind != u"cast"_s && kind != u"playLand"_s && kind != u"activateAbility"_s &&
                kind != u"undoMana"_s)
                continue;
            const QString cardId = option.value(u"cardId"_s).toString();
            if (cardId.isEmpty())
                continue;
            Offer &offer = offers[cardId];
            ++offer.count;
            const QString hint = kind == u"undoMana"_s              ? u"undo"_s
                                 : kind != u"activateAbility"_s     ? u"play"_s
                                 : m_promptKind == u"payManaCost"_s ? u"pay"_s
                                                                    : u"activate"_s;
            static const QStringList hintOrder{u"play"_s, u"activate"_s, u"pay"_s, u"undo"_s};
            if (hintOrder.indexOf(hint) > hintOrder.indexOf(offer.hint)) {
                offer.hint = hint;
                offer.responseId = option.value(u"responseId"_s).toString();
                offer.kind = kind;
            }
        }
    }

    QHash<QString, int> targetCounts;
    QSet<QString> nativeTargets;
    if (m_promptPending && m_promptSupported && m_promptKind == u"chooseBoardTargets"_s) {
        for (const QVariant &value : m_promptTargets.items()) {
            const QVariantMap target = value.toMap();
            if (target.value(u"kind"_s).toString() != u"card"_s)
                continue;
            const QString objectId = target.value(u"objectId"_s).toString();
            if (objectId.isEmpty())
                continue;
            ++targetCounts[objectId];
            if (target.value(u"nativeSelected"_s).toBool())
                nativeTargets.insert(objectId);
        }
    }

    struct Links
    {
        int attachmentCount = 0;
        bool structuralLink = false;
        bool linked = false;
        QStringList blockingIds;
        QStringList blockedByIds;
        QStringList attackedByIds;
        QStringList attachmentSources;
        QVariantList links;
    };
    QHash<QString, Links> linksById;
    for (const QVariant &value : m_battlefieldRelationships) {
        const QVariantMap link = value.toMap();
        const QString kind = link.value(u"kind"_s).toString();
        const QString sourceId = link.value(u"sourceId"_s).toString();
        const QString targetId = link.value(u"targetId"_s).toString();
        if (!sourceId.isEmpty()) {
            Links &source = linksById[sourceId];
            source.linked = true;
            source.links.append(link);
            if (kind != u"attack"_s && kind != u"block"_s)
                source.structuralLink = true;
            if (kind == u"block"_s)
                source.blockingIds.append(targetId);
        }
        if (targetId.isEmpty())
            continue;
        Links &target = linksById[targetId];
        target.linked = true;
        target.links.append(link);
        if (kind != u"attack"_s && kind != u"block"_s)
            target.structuralLink = true;
        if (kind == u"attachment"_s) {
            ++target.attachmentCount;
            target.attachmentSources.append(sourceId);
        } else if (kind == u"block"_s) {
            target.blockedByIds.append(sourceId);
        } else if (kind == u"attack"_s) {
            target.attackedByIds.append(sourceId);
        }
    }

    // Only attachments need a copy of their card; hosts draw them from it.
    const auto basicCard = [](const RulesCardModel &model, int row) {
        QVariantMap card;
        const QModelIndex index = model.index(row);
        const auto roles = model.roleNames();
        for (auto role = roles.cbegin(); role != roles.cend(); ++role) {
            if (role.key() < RulesCardModel::ActionCountRole)
                card.insert(QString::fromUtf8(role.value()), model.data(index, role.key()));
        }
        return card;
    };
    const auto attachedCard = [&](const QString &id) {
        if (const auto row = m_battlefieldIndex.constFind(id); row != m_battlefieldIndex.cend())
            return basicCard(m_battlefieldCards, *row);
        if (const auto row = m_zoneIndex.constFind(id); row != m_zoneIndex.cend())
            return basicCard(m_zoneCards, *row);
        return QVariantMap{};
    };

    const auto apply = [&](RulesCardModel &model) {
        QHash<QString, RulesCardModel::Presentation> presentations;
        presentations.reserve(model.rowCount());
        for (int row = 0; row < model.rowCount(); ++row) {
            const QString id = model.data(model.index(row), RulesCardModel::IdRole).toString();
            if (id.isEmpty())
                continue;
            const Offer offer = offers.value(id);
            const Links relations = linksById.value(id);
            RulesCardModel::Presentation presentation;
            presentation.actionCount = offer.count;
            presentation.primaryResponseId = offer.responseId;
            presentation.primaryKind = offer.kind;
            presentation.hintKey = offer.hint;
            presentation.targetCount = targetCounts.value(id);
            presentation.nativeTargetSelected = nativeTargets.contains(id);
            presentation.attachmentCount = relations.attachmentCount;
            presentation.structuralLink = relations.structuralLink;
            presentation.linked = relations.linked;
            presentation.blockingIds = relations.blockingIds;
            presentation.blockedByIds = relations.blockedByIds;
            presentation.attackedByIds = relations.attackedByIds;
            presentation.links = relations.links;
            for (const QString &sourceId : relations.attachmentSources) {
                QVariantMap attached = attachedCard(sourceId);
                if (attached.isEmpty())
                    continue;
                const Offer sourceOffer = offers.value(sourceId);
                const Links sourceRelations = linksById.value(sourceId);
                attached.insert(u"hintKey"_s, sourceOffer.hint);
                attached.insert(u"actionCount"_s, sourceOffer.count);
                attached.insert(u"primaryResponseId"_s, sourceOffer.responseId);
                attached.insert(u"primaryKind"_s, sourceOffer.kind);
                attached.insert(u"targetCount"_s, targetCounts.value(sourceId));
                attached.insert(u"nativeTargetSelected"_s, nativeTargets.contains(sourceId));
                attached.insert(u"attackedByIds"_s, sourceRelations.attackedByIds);
                attached.insert(u"links"_s, sourceRelations.links);
                attached.insert(u"blockingIds"_s, sourceRelations.blockingIds);
                attached.insert(u"blockedByIds"_s, sourceRelations.blockedByIds);
                presentation.attachmentCards.append(attached);
            }
            presentations.insert(id, presentation);
        }
        model.setPresentations(presentations);
    };
    apply(m_battlefieldCards);
    apply(m_zoneCards);
}

void RulesSessionState::clear()
{
    m_roomId.clear();
    m_gameId.clear();
    m_publicReviewCards.clear();
    m_battlefieldRelationships.clear();
    m_trackedObjects.clear();
    m_trackedZones.clear();
    m_trackedLife.clear();
    m_transitions.clear();
    m_transitionSnap = true;
    m_turn = 0;
    m_step.clear();
    m_activeSeat = -1;
    m_prioritySeat = -1;
    m_gameOver = false;
    m_hasWinner = false;
    m_winnerSeat = -1;
    m_battlefieldCardCount = 0;
    m_visibleZoneCardCount = 0;
    m_players.clear();
    m_zones.clear();
    beginLaneBatch();
    m_battlefieldCards.clear();
    m_zoneCards.clear();
    endLaneBatch();
    m_stack.clear();
    m_battlefieldIndex.clear();
    m_zoneIndex.clear();
    m_stackIndex.clear();
    m_battlefieldCards.setPresentations({});
    m_zoneCards.setPresentations({});
    m_promptPending = false;
    m_promptId = 0;
    m_promptKind.clear();
    m_promptPaymentId.clear();
    m_promptSupported = false;
    m_promptAutoPassEligible = false;
    m_promptTitle.clear();
    m_promptDetail.clear();
    m_promptRequiredSelections = 0;
    m_promptMinCardSelections = 0;
    m_promptMaxCardSelections = 0;
    m_promptMinSelections = 0;
    m_promptMaxSelections = 0;
    m_promptCancellable = false;
    m_promptMinChoiceTotal = 0;
    m_promptMaxChoiceTotal = 0;
    m_promptMinNumber = 0;
    m_promptMaxNumber = 0;
    m_promptOptions.clear();
    m_promptChoices.clear();
    m_promptCards.clear();
    m_promptContextCards.clear();
    m_promptContextTargets.clear();
    m_promptContextText.clear();
    m_promptScryDestinations.clear();
    m_promptOrderItems.clear();
    m_promptTargets.clear();
    m_promptCombat.clear();
    m_promptDamageSource.clear();
    m_promptDamageTargets.clear();
    m_promptTotalDamage = 0;
    m_promptDamageDeathtouch = false;
    m_promptDamageAssignmentMode = protocol::kRulesDamageOrdered;
    ++m_snapshotRevision;
    emit snapshotChanged();
    emit promptChanged();
}

} // namespace hexproof::client
