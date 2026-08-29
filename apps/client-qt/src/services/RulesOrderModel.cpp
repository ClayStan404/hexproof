// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "RulesOrderModel.h"

#include <QVariantMap>
#include <utility>

namespace hexproof::client {

RulesOrderModel::RulesOrderModel(QObject *parent)
    : QAbstractListModel(parent)
{
}

int RulesOrderModel::rowCount(const QModelIndex &parent) const
{
    return parent.isValid() ? 0 : m_rows.size();
}

QVariant RulesOrderModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() < 0 || index.row() >= m_rows.size())
        return {};
    const RulesOrderRow &row = m_rows.at(index.row());
    switch (role) {
    case ResponseIdRole:
        return row.responseId;
    case NameRole:
        return row.name;
    case SetCodeRole:
        return row.setCode;
    case CollectorNumberRole:
        return row.collectorNumber;
    case TokenRole:
        return row.token;
    case OracleRole:
        return row.oracle;
    default:
        return {};
    }
}

QHash<int, QByteArray> RulesOrderModel::roleNames() const
{
    return {{ResponseIdRole, "responseId"}, {NameRole, "name"},
            {SetCodeRole, "setCode"},       {CollectorNumberRole, "collectorNumber"},
            {TokenRole, "token"},           {OracleRole, "oracle"}};
}

void RulesOrderModel::replace(QVector<RulesOrderRow> rows)
{
    beginResetModel();
    m_rows = std::move(rows);
    endResetModel();
}

void RulesOrderModel::clear()
{
    replace({});
}

QVariantList RulesOrderModel::items() const
{
    QVariantList result;
    result.reserve(m_rows.size());
    for (const RulesOrderRow &row : m_rows) {
        result.append(QVariantMap{{QStringLiteral("responseId"), row.responseId},
                                  {QStringLiteral("name"), row.name},
                                  {QStringLiteral("setCode"), row.setCode},
                                  {QStringLiteral("collectorNumber"), row.collectorNumber},
                                  {QStringLiteral("token"), row.token},
                                  {QStringLiteral("oracle"), row.oracle}});
    }
    return result;
}

} // namespace hexproof::client
