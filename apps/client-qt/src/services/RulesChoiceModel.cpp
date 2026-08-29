// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "RulesChoiceModel.h"

#include <utility>

namespace hexproof::client {

RulesChoiceModel::RulesChoiceModel(QObject *parent)
    : QAbstractListModel(parent)
{
}

int RulesChoiceModel::rowCount(const QModelIndex &parent) const
{
    return parent.isValid() ? 0 : m_rows.size();
}

QVariant RulesChoiceModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() < 0 || index.row() >= m_rows.size())
        return {};
    const RulesChoiceRow &row = m_rows.at(index.row());
    switch (role) {
    case ResponseIdRole:
        return row.responseId;
    case LabelRole:
        return row.label;
    case WeightRole:
        return row.weight;
    case CanRepeatRole:
        return row.canRepeat;
    default:
        return {};
    }
}

QHash<int, QByteArray> RulesChoiceModel::roleNames() const
{
    return {{ResponseIdRole, "responseId"},
            {LabelRole, "label"},
            {WeightRole, "weight"},
            {CanRepeatRole, "canRepeat"}};
}

void RulesChoiceModel::replace(QVector<RulesChoiceRow> rows)
{
    beginResetModel();
    m_rows = std::move(rows);
    endResetModel();
}

void RulesChoiceModel::clear()
{
    replace({});
}

} // namespace hexproof::client
