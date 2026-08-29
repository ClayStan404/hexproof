// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "RulesStateModels.h"

#include <QStringList>
#include <utility>

namespace hexproof::client {

namespace {
using namespace Qt::StringLiterals;

QString namedValueSummary(const QVector<RulesNamedValue> &values)
{
    QStringList parts;
    for (const RulesNamedValue &value : values) {
        if (!value.name.isEmpty() && value.value != 0)
            parts.append(value.name + u" "_s + QString::number(value.value));
    }
    return parts.join(u" · "_s);
}

template <typename Rows> int modelRowCount(const QModelIndex &parent, const Rows &rows)
{
    return parent.isValid() ? 0 : rows.size();
}
} // namespace

RulesPlayerModel::RulesPlayerModel(QObject *parent)
    : QAbstractListModel(parent)
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
        return namedValueSummary(row.counters);
    case ManaSummaryRole:
        return namedValueSummary(row.manaPool);
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
            {ManaSummaryRole, "manaSummary"}};
}

void RulesPlayerModel::replace(QVector<RulesPlayerRow> rows)
{
    beginResetModel();
    m_rows = std::move(rows);
    endResetModel();
}

void RulesPlayerModel::clear()
{
    replace({});
}

RulesZoneModel::RulesZoneModel(QObject *parent)
    : QAbstractListModel(parent)
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

void RulesZoneModel::replace(QVector<RulesZoneRow> rows)
{
    beginResetModel();
    m_rows = std::move(rows);
    endResetModel();
}

void RulesZoneModel::clear()
{
    replace({});
}

RulesCardModel::RulesCardModel(QObject *parent)
    : QAbstractListModel(parent)
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
        return namedValueSummary(row.counters);
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
    beginResetModel();
    m_rows = std::move(rows);
    endResetModel();
}

void RulesCardModel::clear()
{
    replace({});
}

RulesStackModel::RulesStackModel(QObject *parent)
    : QAbstractListModel(parent)
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
            {TextRole, "rulesText"}};
}

void RulesStackModel::replace(QVector<RulesStackRow> rows)
{
    beginResetModel();
    m_rows = std::move(rows);
    endResetModel();
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
            {TokenRole, "token"}};
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
