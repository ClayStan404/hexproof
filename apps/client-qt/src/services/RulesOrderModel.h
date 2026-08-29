// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#pragma once

#include <QAbstractListModel>
#include <QString>
#include <QVariantList>
#include <QVector>

namespace hexproof::client {

struct RulesOrderRow
{
    QString responseId;
    QString name;
    QString setCode;
    QString collectorNumber;
    bool token = false;
    QString oracle;
};

class RulesOrderModel final : public QAbstractListModel
{
    Q_OBJECT

  public:
    enum Role
    {
        ResponseIdRole = Qt::UserRole + 1,
        NameRole,
        SetCodeRole,
        CollectorNumberRole,
        TokenRole,
        OracleRole
    };

    explicit RulesOrderModel(QObject *parent = nullptr);
    int rowCount(const QModelIndex &parent = {}) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;
    void replace(QVector<RulesOrderRow> rows);
    void clear();
    Q_INVOKABLE QVariantList items() const;

  private:
    QVector<RulesOrderRow> m_rows;
};

} // namespace hexproof::client
