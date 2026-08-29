// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#pragma once

#include <QAbstractListModel>
#include <QVariantList>
#include <QVariantMap>

namespace hexproof::client {

class ZoneCardModel : public QAbstractListModel
{
    Q_OBJECT
    Q_PROPERTY(int count READ rowCount NOTIFY countChanged)
    Q_PROPERTY(quint64 revision READ revision NOTIFY cardsChanged)

  public:
    enum Role
    {
        CardIdRole = Qt::UserRole + 1,
        NameRole,
        SetCodeRole,
        CollectorNumberRole,
        OwnerSeatRole,
        CommanderRole,
        FaceNameRole,
        FaceDownRole,
        HasPositionRole,
        PositionXRole,
        PositionYRole,
        TokenRole,
        TappedRole,
        CountersRole,
        CardDataRole
    };
    Q_ENUM(Role)

    explicit ZoneCardModel(QObject *parent = nullptr);

    int rowCount(const QModelIndex &parent = {}) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;

    quint64 revision() const;
    Q_INVOKABLE QVariantMap get(int row) const;
    void replaceCards(const QVariantList &cards);

  signals:
    void countChanged();
    void cardsChanged();

  private:
    QVariantList m_cards;
    quint64 m_revision = 0;
};

} // namespace hexproof::client
