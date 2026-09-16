// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "RulesStateModels.h"

#include <QCoreApplication>
#include <QHash>
#include <QStringList>
#include <utility>

namespace hexproof::client {

namespace {
using namespace Qt::StringLiterals;

QString counterDisplayName(const QString &name)
{
    const QString key = name.toUpper();
    static const QHash<QString, QString> statNames{
        {u"P1P1"_s, u"+1/+1"_s}, {u"M1M1"_s, u"-1/-1"_s}, {u"M0M1"_s, u"-0/-1"_s},
        {u"M0M2"_s, u"-0/-2"_s}, {u"M1M0"_s, u"-1/-0"_s}, {u"M2M1"_s, u"-2/-1"_s},
        {u"M2M2"_s, u"-2/-2"_s}, {u"P0P1"_s, u"+0/+1"_s}, {u"P0P2"_s, u"+0/+2"_s},
        {u"P1P0"_s, u"+1/+0"_s}, {u"P1P2"_s, u"+1/+2"_s}, {u"P2P0"_s, u"+2/+0"_s},
        {u"P2P2"_s, u"+2/+2"_s}};
    if (const auto found = statNames.constFind(key); found != statNames.cend())
        return *found;
    if (key == u"LORE"_s)
        return QCoreApplication::translate("RulesCounters", "Lore");
    if (key == u"ENERGY"_s)
        return QCoreApplication::translate("RulesCounters", "Energy");
    if (key == u"CHARGE"_s)
        return QCoreApplication::translate("RulesCounters", "Charge");
    if (key == u"POISON"_s)
        return QCoreApplication::translate("RulesCounters", "Poison");
    if (key == u"LOYALTY"_s)
        return QCoreApplication::translate("RulesCounters", "Loyalty");
    return name;
}

QString namedValueSummary(const QVector<RulesNamedValue> &values, bool counterNames = false)
{
    QStringList parts;
    for (const RulesNamedValue &value : values) {
        if (!value.name.isEmpty() && value.value != 0)
            parts.append((counterNames ? counterDisplayName(value.name) : value.name) + u" "_s +
                         QString::number(value.value));
    }
    return parts.join(u" · "_s);
}

template <typename Rows> int modelRowCount(const QModelIndex &parent, const Rows &rows)
{
    return parent.isValid() ? 0 : rows.size();
}
} // namespace

RulesPlayerModel::RulesPlayerModel(QObject *parent)
    : RulesSnapshotModel(parent)
{
}

int RulesPlayerModel::rowCount(const QModelIndex &parent) const
{
    return modelRowCount(parent, m_rows);
}

QVariant RulesPlayerModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() < 0 || index.row() >= m_rows.size())
        return {};
    const RulesPlayerRow &row = m_rows.at(index.row());
    switch (role) {
    case SeatRole:
        return row.seat;
    case NameRole:
        return row.name;
    case StatusRole:
        return row.status;
    case LifeRole:
        return row.life;
    case CountersSummaryRole:
        return namedValueSummary(row.counters, true);
    case ManaSummaryRole:
        return namedValueSummary(row.manaPool);
    case CommandersRole:
        return row.commanders;
    default:
        return {};
    }
}

QHash<int, QByteArray> RulesPlayerModel::roleNames() const
{
    return {{SeatRole, "seat"},
            {NameRole, "name"},
            {StatusRole, "status"},
            {LifeRole, "life"},
            {CountersSummaryRole, "countersSummary"},
            {ManaSummaryRole, "manaSummary"},
            {CommandersRole, "commanders"}};
}

void RulesPlayerModel::replace(QVector<RulesPlayerRow> rows)
{
    replaceRows(m_rows, std::move(rows), [](const RulesPlayerRow &row) { return row.seat; });
}

void RulesPlayerModel::clear()
{
    replace({});
}

RulesZoneModel::RulesZoneModel(QObject *parent)
    : RulesSnapshotModel(parent)
{
}

int RulesZoneModel::rowCount(const QModelIndex &parent) const
{
    return modelRowCount(parent, m_rows);
}

QVariant RulesZoneModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() < 0 || index.row() >= m_rows.size())
        return {};
    const RulesZoneRow &row = m_rows.at(index.row());
    switch (role) {
    case ZoneRole:
        return row.zone;
    case OwnerSeatRole:
        return row.ownerSeat;
    case CountRole:
        return row.count;
    default:
        return {};
    }
}

QHash<int, QByteArray> RulesZoneModel::roleNames() const
{
    return {{ZoneRole, "zone"}, {OwnerSeatRole, "ownerSeat"}, {CountRole, "count"}};
}

int RulesZoneModel::countFor(int ownerSeat, const QString &zone) const
{
    for (const RulesZoneRow &row : m_rows) {
        if (row.ownerSeat == ownerSeat && row.zone == zone)
            return row.count;
    }
    return 0;
}

void RulesZoneModel::replace(QVector<RulesZoneRow> rows)
{
    replaceRows(m_rows, std::move(rows),
                [](const RulesZoneRow &row) { return qMakePair(row.ownerSeat, row.zone); });
}

void RulesZoneModel::clear()
{
    replace({});
}

RulesCardModel::RulesCardModel(QObject *parent)
    : RulesSnapshotModel(parent)
{
}

int RulesCardModel::rowCount(const QModelIndex &parent) const
{
    return modelRowCount(parent, m_rows);
}

QVariant RulesCardModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() < 0 || index.row() >= m_rows.size())
        return {};
    const RulesCardRow &row = m_rows.at(index.row());
    switch (role) {
    case IdRole:
        return row.id;
    case ZoneRole:
        return row.zone;
    case ZoneOwnerSeatRole:
        return row.zoneOwnerSeat;
    case VisibleRole:
        return row.visible;
    case NameRole:
        return row.name;
    case SetCodeRole:
        return row.setCode;
    case CollectorNumberRole:
        return row.collectorNumber;
    case TokenRole:
        return row.token;
    case OwnerSeatRole:
        return row.ownerSeat;
    case ControllerSeatRole:
        return row.controllerSeat;
    case TappedRole:
        return row.tapped;
    case FaceDownRole:
        return row.faceDown;
    case AttackingRole:
        return row.attacking;
    case PowerRole:
        return row.power;
    case ToughnessRole:
        return row.toughness;
    case DamageRole:
        return row.damage;
    case AttachedToRole:
        return row.attachedTo;
    case CountersSummaryRole:
        return namedValueSummary(row.counters, true);
    default:
        return {};
    }
}

QHash<int, QByteArray> RulesCardModel::roleNames() const
{
    return {{IdRole, "cardId"},
            {ZoneRole, "zone"},
            {ZoneOwnerSeatRole, "zoneOwnerSeat"},
            {VisibleRole, "visibleIdentity"},
            {NameRole, "name"},
            {SetCodeRole, "setCode"},
            {CollectorNumberRole, "collectorNumber"},
            {TokenRole, "token"},
            {OwnerSeatRole, "ownerSeat"},
            {ControllerSeatRole, "controllerSeat"},
            {TappedRole, "tapped"},
            {FaceDownRole, "faceDown"},
            {AttackingRole, "attacking"},
            {PowerRole, "power"},
            {ToughnessRole, "toughness"},
            {DamageRole, "damage"},
            {AttachedToRole, "attachedTo"},
            {CountersSummaryRole, "countersSummary"}};
}

void RulesCardModel::replace(QVector<RulesCardRow> rows)
{
    replaceRows(m_rows, std::move(rows), [](const RulesCardRow &row) { return row.id; });
}

void RulesCardModel::clear()
{
    replace({});
}

RulesStackModel::RulesStackModel(QObject *parent)
    : RulesSnapshotModel(parent)
{
}

int RulesStackModel::rowCount(const QModelIndex &parent) const
{
    return modelRowCount(parent, m_rows);
}

QVariant RulesStackModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() < 0 || index.row() >= m_rows.size())
        return {};
    const RulesStackRow &row = m_rows.at(index.row());
    switch (role) {
    case IdRole:
        return row.id;
    case SourceIdRole:
        return row.sourceId;
    case ControllerSeatRole:
        return row.controllerSeat;
    case OwnerSeatRole:
        return row.ownerSeat;
    case NameRole:
        return row.name;
    case SetCodeRole:
        return row.setCode;
    case CollectorNumberRole:
        return row.collectorNumber;
    case TokenRole:
        return row.token;
    case TextRole:
        return row.text;
    case TargetsRole:
        return row.targets;
    default:
        return {};
    }
}

QHash<int, QByteArray> RulesStackModel::roleNames() const
{
    return {{IdRole, "objectId"},
            {SourceIdRole, "sourceId"},
            {ControllerSeatRole, "controllerSeat"},
            {OwnerSeatRole, "ownerSeat"},
            {NameRole, "name"},
            {SetCodeRole, "setCode"},
            {CollectorNumberRole, "collectorNumber"},
            {TokenRole, "token"},
            {TextRole, "rulesText"},
            {TargetsRole, "targets"}};
}

void RulesStackModel::replace(QVector<RulesStackRow> rows)
{
    replaceRows(m_rows, std::move(rows), [](const RulesStackRow &row) { return row.id; });
}

void RulesStackModel::clear()
{
    replace({});
}

RulesPromptOptionModel::RulesPromptOptionModel(QObject *parent)
    : QAbstractListModel(parent)
{
}

int RulesPromptOptionModel::rowCount(const QModelIndex &parent) const
{
    return modelRowCount(parent, m_rows);
}

QVariant RulesPromptOptionModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() < 0 || index.row() >= m_rows.size())
        return {};
    const RulesPromptOptionRow &row = m_rows.at(index.row());
    switch (role) {
    case ResponseIdRole:
        return row.responseId;
    case KindRole:
        return row.kind;
    case LabelRole:
        return row.label;
    case CardIdRole:
        return row.cardId;
    default:
        return {};
    }
}

QHash<int, QByteArray> RulesPromptOptionModel::roleNames() const
{
    return {{ResponseIdRole, "responseId"},
            {KindRole, "kind"},
            {LabelRole, "label"},
            {CardIdRole, "cardId"}};
}

QVariantList RulesPromptOptionModel::castActionsForCard(const QString &cardId) const
{
    QVariantList actions;
    if (cardId.isEmpty())
        return actions;
    for (const RulesPromptOptionRow &row : m_rows) {
        if ((row.kind != u"cast"_s && row.kind != u"playLand"_s) || row.cardId != cardId)
            continue;
        actions.append(QVariantMap{
            {u"responseId"_s, row.responseId}, {u"kind"_s, row.kind}, {u"label"_s, row.label}});
    }
    return actions;
}

QVariantList RulesPromptOptionModel::cardActionsForCard(const QString &cardId) const
{
    QVariantList actions;
    if (cardId.isEmpty())
        return actions;
    for (const RulesPromptOptionRow &row : m_rows) {
        if (row.cardId != cardId || (row.kind != u"cast"_s && row.kind != u"playLand"_s &&
                                     row.kind != u"activateAbility"_s))
            continue;
        actions.append(QVariantMap{
            {u"responseId"_s, row.responseId}, {u"kind"_s, row.kind}, {u"label"_s, row.label}});
    }
    return actions;
}

QVariantList RulesPromptOptionModel::items() const
{
    QVariantList result;
    for (const RulesPromptOptionRow &row : m_rows) {
        result.append(QVariantMap{{u"responseId"_s, row.responseId},
                                  {u"kind"_s, row.kind},
                                  {u"label"_s, row.label},
                                  {u"cardId"_s, row.cardId}});
    }
    return result;
}

void RulesPromptOptionModel::replace(QVector<RulesPromptOptionRow> rows)
{
    beginResetModel();
    m_rows = std::move(rows);
    endResetModel();
}

void RulesPromptOptionModel::clear()
{
    replace({});
}

RulesPromptCardModel::RulesPromptCardModel(QObject *parent)
    : QAbstractListModel(parent)
{
}

int RulesPromptCardModel::rowCount(const QModelIndex &parent) const
{
    return modelRowCount(parent, m_rows);
}

QVariant RulesPromptCardModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() < 0 || index.row() >= m_rows.size())
        return {};
    const RulesPromptCardRow &row = m_rows.at(index.row());
    switch (role) {
    case IdRole:
        return row.id;
    case NameRole:
        return row.name;
    case SetCodeRole:
        return row.setCode;
    case CollectorNumberRole:
        return row.collectorNumber;
    case TokenRole:
        return row.token;
    default:
        return {};
    }
}

QHash<int, QByteArray> RulesPromptCardModel::roleNames() const
{
    return {{IdRole, "cardId"},
            {NameRole, "name"},
            {SetCodeRole, "setCode"},
            {CollectorNumberRole, "collectorNumber"},
            {TokenRole, "token"}};
}

QVariantList RulesPromptCardModel::items() const
{
    QVariantList result;
    result.reserve(m_rows.size());
    for (const RulesPromptCardRow &row : m_rows) {
        result.append(QVariantMap{{u"cardId"_s, row.id},
                                  {u"name"_s, row.name},
                                  {u"setCode"_s, row.setCode},
                                  {u"collectorNumber"_s, row.collectorNumber},
                                  {u"token"_s, row.token}});
    }
    return result;
}

void RulesPromptCardModel::replace(QVector<RulesPromptCardRow> rows)
{
    beginResetModel();
    m_rows = std::move(rows);
    endResetModel();
}

void RulesPromptCardModel::clear()
{
    replace({});
}

RulesPromptTargetModel::RulesPromptTargetModel(QObject *parent)
    : QAbstractListModel(parent)
{
}

int RulesPromptTargetModel::rowCount(const QModelIndex &parent) const
{
    return modelRowCount(parent, m_rows);
}

QVariant RulesPromptTargetModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() < 0 || index.row() >= m_rows.size())
        return {};
    const RulesPromptTargetRow &row = m_rows.at(index.row());
    switch (role) {
    case ResponseIdRole:
        return row.responseId;
    case KindRole:
        return row.kind;
    case LabelRole:
        return row.label;
    case ObjectIdRole:
        return row.objectId;
    case NameRole:
        return row.name;
    case SetCodeRole:
        return row.setCode;
    case CollectorNumberRole:
        return row.collectorNumber;
    case TokenRole:
        return row.token;
    case SeatRole:
        return row.seat;
    default:
        return {};
    }
}

QHash<int, QByteArray> RulesPromptTargetModel::roleNames() const
{
    return {{ResponseIdRole, "responseId"},
            {KindRole, "kind"},
            {LabelRole, "label"},
            {ObjectIdRole, "objectId"},
            {NameRole, "name"},
            {SetCodeRole, "setCode"},
            {CollectorNumberRole, "collectorNumber"},
            {TokenRole, "token"},
            {SeatRole, "seat"}};
}

QVariantList RulesPromptTargetModel::items() const
{
    QVariantList targets;
    targets.reserve(m_rows.size());
    for (const RulesPromptTargetRow &row : m_rows) {
        targets.append(QVariantMap{{u"responseId"_s, row.responseId},
                                   {u"kind"_s, row.kind},
                                   {u"label"_s, row.label},
                                   {u"objectId"_s, row.objectId},
                                   {u"seat"_s, row.seat},
                                   {u"name"_s, row.name},
                                   {u"setCode"_s, row.setCode},
                                   {u"collectorNumber"_s, row.collectorNumber},
                                   {u"token"_s, row.token}});
    }
    return targets;
}

QStringList RulesPromptTargetModel::responseIdsForObject(const QString &kind,
                                                         const QString &objectId) const
{
    QStringList ids;
    if (objectId.isEmpty() || (kind != u"card"_s && kind != u"spell"_s))
        return ids;
    for (const RulesPromptTargetRow &row : m_rows) {
        if (row.kind == kind && row.objectId == objectId)
            ids.append(row.responseId);
    }
    return ids;
}

QStringList RulesPromptTargetModel::responseIdsForSeat(int seat) const
{
    QStringList ids;
    if (seat < 0)
        return ids;
    for (const RulesPromptTargetRow &row : m_rows) {
        if (row.kind == u"player"_s && row.seat == seat)
            ids.append(row.responseId);
    }
    return ids;
}

void RulesPromptTargetModel::replace(QVector<RulesPromptTargetRow> rows)
{
    beginResetModel();
    m_rows = std::move(rows);
    endResetModel();
}

void RulesPromptTargetModel::clear()
{
    replace({});
}

} // namespace hexproof::client
