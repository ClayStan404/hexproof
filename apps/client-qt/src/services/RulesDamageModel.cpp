// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "RulesDamageModel.h"

#include <utility>

namespace hexproof::client {

RulesDamageModel::RulesDamageModel(QObject *parent)
    : QAbstractListModel(parent)
{
}

int RulesDamageModel::rowCount(const QModelIndex &parent) const
{
    return parent.isValid() ? 0 : m_rows.size();
}

QVariant RulesDamageModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() < 0 || index.row() >= m_rows.size())
        return {};
    const RulesDamageTargetRow &row = m_rows.at(index.row());
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
    case LethalDamageRole:
        return row.lethalDamage;
    default:
        return {};
    }
}

QHash<int, QByteArray> RulesDamageModel::roleNames() const
{
    return {{ResponseIdRole, "responseId"},
            {KindRole, "kind"},
            {LabelRole, "label"},
            {ObjectIdRole, "objectId"},
            {NameRole, "name"},
            {SetCodeRole, "setCode"},
            {CollectorNumberRole, "collectorNumber"},
            {TokenRole, "token"},
            {LethalDamageRole, "lethalDamage"}};
}

void RulesDamageModel::replace(QVector<RulesDamageTargetRow> rows)
{
    beginResetModel();
    m_rows = std::move(rows);
    endResetModel();
}

void RulesDamageModel::clear()
{
    replace({});
}

QVariantList RulesDamageModel::items() const
{
    QVariantList result;
    result.reserve(m_rows.size());
    for (const RulesDamageTargetRow &row : m_rows) {
        result.append(QVariantMap{{QStringLiteral("responseId"), row.responseId},
                                  {QStringLiteral("kind"), row.kind},
                                  {QStringLiteral("label"), row.label},
                                  {QStringLiteral("objectId"), row.objectId},
                                  {QStringLiteral("name"), row.name},
                                  {QStringLiteral("setCode"), row.setCode},
                                  {QStringLiteral("collectorNumber"), row.collectorNumber},
                                  {QStringLiteral("token"), row.token},
                                  {QStringLiteral("oracle"), QString{}},
                                  {QStringLiteral("lethalDamage"), row.lethalDamage}});
    }
    return result;
}

} // namespace hexproof::client
