// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#pragma once

#include <QObject>
#include <QVariantList>

namespace hexproof::client {

class SideboardTableModel : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QVariantList mainboardCards READ mainboardCards WRITE setMainboardCards NOTIFY
                   mainboardChanged)
    Q_PROPERTY(QVariantList sideboardCards READ sideboardCards WRITE setSideboardCards NOTIFY
                   sideboardChanged)
    Q_PROPERTY(QVariantList mainboardGroups READ mainboardGroups NOTIFY mainboardChanged)
    Q_PROPERTY(QVariantList sideboardGroups READ sideboardGroups NOTIFY sideboardChanged)
    Q_PROPERTY(int mainboardCount READ mainboardCount NOTIFY mainboardChanged)
    Q_PROPERTY(int sideboardCount READ sideboardCount NOTIFY sideboardChanged)

  public:
    explicit SideboardTableModel(QObject *parent = nullptr);

    QVariantList mainboardCards() const
    {
        return m_mainboardCards;
    }
    void setMainboardCards(const QVariantList &cards);
    QVariantList sideboardCards() const
    {
        return m_sideboardCards;
    }
    void setSideboardCards(const QVariantList &cards);
    QVariantList mainboardGroups() const
    {
        return m_mainboardGroups;
    }
    QVariantList sideboardGroups() const
    {
        return m_sideboardGroups;
    }
    int mainboardCount() const
    {
        return m_mainboardCount;
    }
    int sideboardCount() const
    {
        return m_sideboardCount;
    }

    Q_INVOKABLE QString cardCategory(const QString &typeLine) const;
    Q_INVOKABLE QVariantList groupCards(const QVariantList &cards) const;

  signals:
    void mainboardChanged();
    void sideboardChanged();

  private:
    struct GroupedCards
    {
        QVariantList groups;
        int count = 0;
    };

    static GroupedCards buildGroups(const QVariantList &cards);

    QVariantList m_mainboardCards;
    QVariantList m_sideboardCards;
    QVariantList m_mainboardGroups;
    QVariantList m_sideboardGroups;
    int m_mainboardCount = 0;
    int m_sideboardCount = 0;
};

} // namespace hexproof::client
