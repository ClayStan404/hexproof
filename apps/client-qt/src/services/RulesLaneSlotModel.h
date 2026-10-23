// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#pragma once

#include <QAbstractListModel>
#include <QHash>
#include <QMetaMethod>
#include <QObject>
#include <QPointer>
#include <QSet>
#include <QString>
#include <QVariantList>
#include <QVariantMap>
#include <QVector>

namespace hexproof::client {

// One lane's permanents, already filtered and piled. QML reads slot index,
// member rank and slot size instead of sorting every card on a timer.
// Battlefield categories are creature, land, planeswalker and other. Public
// power/toughness takes precedence over the visible identity's printed type.
class RulesLaneSlotModel final : public QAbstractListModel
{
    Q_OBJECT
    Q_PROPERTY(QVariantList stacks READ stacks NOTIFY stacksChanged)
    Q_PROPERTY(int layoutStackCount READ layoutStackCount NOTIFY layoutStackCountChanged)
    Q_PROPERTY(QVariantMap combatGroupingKeys READ combatGroupingKeys WRITE setCombatGroupingKeys
                   NOTIFY combatGroupingKeysChanged)

  public:
    enum ExtraRole
    {
        SlotIndexRole = Qt::UserRole + 100,
        MemberRankRole,
        SlotSizeRole
    };

    RulesLaneSlotModel(QAbstractItemModel *source, int seat, const QString &zone,
                       const QString &category, QObject *parent = nullptr);

    int rowCount(const QModelIndex &parent = {}) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;

    QVariantList stacks() const
    {
        return m_stacks;
    }
    int layoutStackCount() const
    {
        return m_layoutStackCount;
    }
    void setCatalog(QObject *catalog);
    QVariantMap combatGroupingKeys() const
    {
        return m_combatGroupingKeys;
    }
    void setCombatGroupingKeys(const QVariantMap &keys);

    // A snapshot replaces its source rows one signal at a time. Between
    // beginBatch() and endBatch() the lane only records what changed and
    // republishes once at the end.
    void beginBatch();
    void endBatch();

  signals:
    void stacksAboutToChange();
    void stacksChanged();
    void layoutStackCountChanged();
    void combatGroupingKeysChanged();

  private slots:
    void noteStructure();
    void noteCardAvailable(const QString &requestedName);
    void noteLanguage();

  private:
    struct Entry
    {
        int sourceRow = -1;
        QString id;
        int slot = -1;
        int rank = -1;
        int size = 0;
    };
    struct PrintedCategory
    {
        QString name;
        QString setCode;
        QString collectorNumber;
        QString category;
    };

    void rebuild(const QSet<QString> &changedIds = {});
    void publish(QVector<Entry> next, QVariantList stacks, int layoutStackCount,
                 const QSet<QString> &changedIds);

    QString categoryFor(int sourceRow);
    QString typeLineFor(const QString &name, const QString &setCode,
                        const QString &collectorNumber) const;
    QString stackKeyFor(int sourceRow, const QSet<QString> &hosts, bool ignoreTapped = false) const;
    QString combatKeyFor(int sourceRow) const;
    QVariant sourceValue(int sourceRow, int role) const;
    QSet<QString> idsInRange(int first, int last) const;
    void noteSourceData(const QModelIndex &topLeft, const QModelIndex &bottomRight,
                        const QList<int> &roles);

    QAbstractItemModel *m_source = nullptr;
    int m_seat = -1;
    QString m_zone;
    QString m_category;
    QPointer<QObject> m_catalog;
    QMetaMethod m_typeLineMethod;
    QHash<QString, PrintedCategory> m_categoryCache;
    QVector<Entry> m_rows;
    QHash<QString, int> m_rowOfId;
    QVariantList m_stacks;
    QVariantMap m_combatGroupingKeys;
    int m_layoutStackCount = 0;
    int m_batchDepth = 0;
    bool m_batchStructure = false;
    QSet<QString> m_batchChangedIds;
};

} // namespace hexproof::client
