// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "RulesCombatModel.h"

#include <QHash>
#include <QSet>
#include <utility>

namespace hexproof::client {

RulesCombatModel::RulesCombatModel(QObject *parent)
    : QAbstractListModel(parent)
{
}

int RulesCombatModel::rowCount(const QModelIndex &parent) const
{
    return parent.isValid() ? 0 : m_sources.size();
}

QVariant RulesCombatModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() < 0 || index.row() >= m_sources.size())
        return {};
    const RulesCombatSourceRow &row = m_sources.at(index.row());
    switch (role) {
    case ResponseIdRole:
        return row.responseId;
    case ObjectIdRole:
        return row.objectId;
    case LabelRole:
        return row.label;
    case NameRole:
        return row.name;
    case SetCodeRole:
        return row.setCode;
    case CollectorNumberRole:
        return row.collectorNumber;
    case TokenRole:
        return row.token;
    case ValidTargetsRole:
        return validTargets(row);
    case MustAssignIfAbleRole:
        return row.mustAssignIfAble;
    case MaximumRole:
        return row.maximum;
    default:
        return {};
    }
}

QHash<int, QByteArray> RulesCombatModel::roleNames() const
{
    return {{ResponseIdRole, "responseId"},
            {ObjectIdRole, "objectId"},
            {LabelRole, "label"},
            {NameRole, "name"},
            {SetCodeRole, "setCode"},
            {CollectorNumberRole, "collectorNumber"},
            {TokenRole, "token"},
            {ValidTargetsRole, "validTargets"},
            {MustAssignIfAbleRole, "mustAssignIfAble"},
            {MaximumRole, "maxAssignments"}};
}

void RulesCombatModel::replace(QVector<RulesCombatSourceRow> sources,
                               QVector<RulesCombatTargetRow> targets)
{
    beginResetModel();
    m_sources = std::move(sources);
    m_targets = std::move(targets);
    endResetModel();
}

void RulesCombatModel::clear()
{
    replace({}, {});
}

bool RulesCombatModel::validAssignments(const QVariantMap &assignments) const
{
    QHash<QString, int> targetCounts;
    for (auto iterator = assignments.cbegin(); iterator != assignments.cend(); ++iterator) {
        const RulesCombatSourceRow *source = sourceById(iterator.key());
        if (!source)
            return false;
        const QVariant &value = iterator.value();
        const QVariantList selected =
            value.metaType().id() == QMetaType::QString ? QVariantList{value} : value.toList();
        if (selected.isEmpty() || selected.size() > source->maximum)
            return false;
        QSet<QString> seen;
        for (const QVariant &target : selected) {
            const QString targetId = target.toString();
            if (!targetById(targetId) || !source->validTargetIds.contains(targetId) ||
                seen.contains(targetId)) {
                return false;
            }
            seen.insert(targetId);
            ++targetCounts[targetId];
        }
    }
    for (const RulesCombatTargetRow &target : m_targets) {
        const int count = targetCounts.value(target.responseId);
        if (count > target.maximum || (count > 0 && count < target.minimum)) {
            return false;
        }
    }
    return true;
}

const RulesCombatSourceRow *RulesCombatModel::sourceById(const QString &responseId) const
{
    for (const RulesCombatSourceRow &source : m_sources) {
        if (source.responseId == responseId)
            return &source;
    }
    return nullptr;
}

const RulesCombatTargetRow *RulesCombatModel::targetById(const QString &responseId) const
{
    for (const RulesCombatTargetRow &target : m_targets) {
        if (target.responseId == responseId)
            return &target;
    }
    return nullptr;
}

QVariantList RulesCombatModel::sourceItems() const
{
    QVariantList result;
    const auto roles = roleNames();
    for (int row = 0; row < rowCount(); ++row) {
        QVariantMap item;
        for (auto role = roles.cbegin(); role != roles.cend(); ++role)
            item.insert(QString::fromUtf8(role.value()), data(index(row), role.key()));
        result.append(item);
    }
    return result;
}

QVariantList RulesCombatModel::validTargets(const RulesCombatSourceRow &source) const
{
    QVariantList result;
    result.reserve(source.validTargetIds.size());
    for (const QString &targetId : source.validTargetIds) {
        const RulesCombatTargetRow *target = targetById(targetId);
        if (!target)
            continue;
        result.append(
            QVariantMap{{QStringLiteral("responseId"), target->responseId},
                        {QStringLiteral("kind"), target->kind},
                        {QStringLiteral("objectId"), target->objectId},
                        {QStringLiteral("seat"), target->seat},
                        {QStringLiteral("label"), target->label},
                        {QStringLiteral("minAssignments"), target->minimum},
                        {QStringLiteral("maxAssignments"), target->maximum},
                        {QStringLiteral("mustReceiveIfAble"), target->mustReceiveIfAble}});
    }
    return result;
}

} // namespace hexproof::client
