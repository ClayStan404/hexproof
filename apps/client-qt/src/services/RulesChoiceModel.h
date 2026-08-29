// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#pragma once

#include <QAbstractListModel>
#include <QString>
#include <QVector>

namespace hexproof::client {

struct RulesChoiceRow
{
    QString responseId;
    QString label;
    int weight = 1;
    bool canRepeat = false;
};

class RulesChoiceModel final : public QAbstractListModel
{
  public:
    enum Role
    {
        ResponseIdRole = Qt::UserRole + 1,
        LabelRole,
        WeightRole,
        CanRepeatRole
    };

    explicit RulesChoiceModel(QObject *parent = nullptr);
    int rowCount(const QModelIndex &parent = {}) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;
    void replace(QVector<RulesChoiceRow> rows);
    void clear();

  private:
    QVector<RulesChoiceRow> m_rows;
};

} // namespace hexproof::client
