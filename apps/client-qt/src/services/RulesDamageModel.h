// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#pragma once

#include <QAbstractListModel>
#include <QVariantList>
#include <QVector>

namespace hexproof::client {

struct RulesDamageTargetRow
{
    QString responseId;
    QString kind;
    QString label;
    QString objectId;
    QString name;
    QString setCode;
    QString collectorNumber;
    bool token = false;
    int lethalDamage = -1;
};

class RulesDamageModel final : public QAbstractListModel
{
    Q_OBJECT

  public:
    enum Role
    {
        ResponseIdRole = Qt::UserRole + 1,
        KindRole,
        LabelRole,
        ObjectIdRole,
        NameRole,
        SetCodeRole,
        CollectorNumberRole,
        TokenRole,
        LethalDamageRole
    };

    explicit RulesDamageModel(QObject *parent = nullptr);
    int rowCount(const QModelIndex &parent = {}) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;

    void replace(QVector<RulesDamageTargetRow> rows);
    void clear();
    Q_INVOKABLE QVariantList items() const;

  private:
    QVector<RulesDamageTargetRow> m_rows;
};

} // namespace hexproof::client
