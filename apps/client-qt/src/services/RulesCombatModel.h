// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#pragma once

#include <QAbstractListModel>
#include <QStringList>
#include <QVariantMap>
#include <QVector>

namespace hexproof::client {

struct RulesCombatSourceRow
{
    QString responseId;
    QString objectId;
    QString label;
    QString name;
    QString setCode;
    QString collectorNumber;
    bool token = false;
    QStringList validTargetIds;
    bool mustAssignIfAble = false;
};

struct RulesCombatTargetRow
{
    QString responseId;
    QString kind;
    QString label;
    QString objectId;
    QString name;
    QString setCode;
    QString collectorNumber;
    bool token = false;
    int minimum = 0;
    int maximum = 0;
    bool mustReceiveIfAble = false;
};

class RulesCombatModel final : public QAbstractListModel
{
    Q_OBJECT

  public:
    enum Role
    {
        ResponseIdRole = Qt::UserRole + 1,
        ObjectIdRole,
        LabelRole,
        NameRole,
        SetCodeRole,
        CollectorNumberRole,
        TokenRole,
        ValidTargetsRole,
        MustAssignIfAbleRole
    };

    explicit RulesCombatModel(QObject *parent = nullptr);
    int rowCount(const QModelIndex &parent = {}) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;

    void replace(QVector<RulesCombatSourceRow> sources, QVector<RulesCombatTargetRow> targets);
    void clear();
    Q_INVOKABLE bool validAssignments(const QVariantMap &assignments) const;

  private:
    const RulesCombatSourceRow *sourceById(const QString &responseId) const;
    const RulesCombatTargetRow *targetById(const QString &responseId) const;
    QVariantList validTargets(const RulesCombatSourceRow &source) const;

    QVector<RulesCombatSourceRow> m_sources;
    QVector<RulesCombatTargetRow> m_targets;
};

} // namespace hexproof::client
