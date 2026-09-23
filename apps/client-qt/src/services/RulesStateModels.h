// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#pragma once

#include "RulesSnapshotModel.h"

#include <QAbstractListModel>
#include <QString>
#include <QStringList>
#include <QVariantList>
#include <QVector>

namespace hexproof::client {

struct RulesNamedValue
{
    QString name;
    int value = 0;
    bool operator==(const RulesNamedValue &) const = default;
};

struct RulesPlayerRow
{
    int seat = -1;
    int controllingSeat = -1;
    QString name;
    QString status;
    int life = 0;
    QVector<RulesNamedValue> counters;
    QVector<RulesNamedValue> manaPool;
    QVariantList commanders;
    bool operator==(const RulesPlayerRow &) const = default;
};

struct RulesZoneRow
{
    QString zone;
    int ownerSeat = -1;
    int count = 0;
    bool operator==(const RulesZoneRow &) const = default;
};

struct RulesCardRow
{
    QString id;
    QString zone;
    int zoneOwnerSeat = -1;
    bool visible = false;
    QString name;
    QString setCode;
    QString collectorNumber;
    bool token = false;
    int ownerSeat = -1;
    int controllerSeat = -1;
    bool tapped = false;
    bool enteredThisTurn = false;
    bool summoningSick = false;
    bool faceDown = false;
    bool attacking = false;
    QString power;
    QString toughness;
    int damage = 0;
    QString attachedTo;
    int exiledCardCount = 0;
    QStringList exiledCardIds;
    QStringList chosenCardIds;
    QVariantList annotations;
    QVector<RulesNamedValue> counters;
    bool operator==(const RulesCardRow &) const = default;
};

struct RulesStackRow
{
    QString id;
    QString sourceId;
    int controllerSeat = -1;
    int ownerSeat = -1;
    QString name;
    QString setCode;
    QString collectorNumber;
    bool token = false;
    QString text;
    QVariantList targets;
    bool operator==(const RulesStackRow &) const = default;
};

struct RulesPromptOptionRow
{
    QString responseId;
    QString kind;
    QString label;
    QString cardId;
};

struct RulesPromptCardRow
{
    QString id;
    QString name;
    QString setCode;
    QString collectorNumber;
    bool token = false;
    bool nativeSelected = false;
    bool readOnly = false;
};

struct RulesPromptTargetRow
{
    QString responseId;
    QString kind;
    QString label;
    QString objectId;
    QString name;
    QString setCode;
    QString collectorNumber;
    bool token = false;
    int seat = -1;
    bool nativeSelected = false;
};

class RulesPlayerModel final : public RulesSnapshotModel
{
  public:
    enum Role
    {
        SeatRole = Qt::UserRole + 1,
        ControllingSeatRole,
        NameRole,
        StatusRole,
        LifeRole,
        CountersSummaryRole,
        ManaSummaryRole,
        ManaPoolRole,
        CommandersRole
    };

    explicit RulesPlayerModel(QObject *parent = nullptr);
    int rowCount(const QModelIndex &parent = {}) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;
    void replace(QVector<RulesPlayerRow> rows);
    void clear();

  private:
    QVector<RulesPlayerRow> m_rows;
};

class RulesZoneModel final : public RulesSnapshotModel
{
  public:
    enum Role
    {
        ZoneRole = Qt::UserRole + 1,
        OwnerSeatRole,
        CountRole
    };

    explicit RulesZoneModel(QObject *parent = nullptr);
    int rowCount(const QModelIndex &parent = {}) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;
    int countFor(int ownerSeat, const QString &zone) const;
    void replace(QVector<RulesZoneRow> rows);
    void clear();

  private:
    QVector<RulesZoneRow> m_rows;
};

class RulesCardModel final : public RulesSnapshotModel
{
  public:
    enum Role
    {
        IdRole = Qt::UserRole + 1,
        ZoneRole,
        ZoneOwnerSeatRole,
        VisibleRole,
        NameRole,
        SetCodeRole,
        CollectorNumberRole,
        TokenRole,
        OwnerSeatRole,
        ControllerSeatRole,
        TappedRole,
        EnteredThisTurnRole,
        SummoningSickRole,
        FaceDownRole,
        AttackingRole,
        PowerRole,
        ToughnessRole,
        DamageRole,
        AttachedToRole,
        ExiledCardCountRole,
        ExiledCardIdsRole,
        ChosenCardIdsRole,
        AnnotationsRole,
        CountersSummaryRole
    };

    explicit RulesCardModel(QObject *parent = nullptr);
    int rowCount(const QModelIndex &parent = {}) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;
    void replace(QVector<RulesCardRow> rows);
    void clear();

  private:
    QVector<RulesCardRow> m_rows;
};

class RulesStackModel final : public RulesSnapshotModel
{
  public:
    enum Role
    {
        IdRole = Qt::UserRole + 1,
        SourceIdRole,
        ControllerSeatRole,
        OwnerSeatRole,
        NameRole,
        SetCodeRole,
        CollectorNumberRole,
        TokenRole,
        TextRole,
        TargetsRole
    };

    explicit RulesStackModel(QObject *parent = nullptr);
    int rowCount(const QModelIndex &parent = {}) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;
    void replace(QVector<RulesStackRow> rows);
    void clear();

  private:
    QVector<RulesStackRow> m_rows;
};

class RulesPromptOptionModel final : public QAbstractListModel
{
  public:
    enum Role
    {
        ResponseIdRole = Qt::UserRole + 1,
        KindRole,
        LabelRole,
        CardIdRole
    };

    explicit RulesPromptOptionModel(QObject *parent = nullptr);
    int rowCount(const QModelIndex &parent = {}) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;
    QVariantList castActionsForCard(const QString &cardId) const;
    QVariantList cardActionsForCard(const QString &cardId) const;
    QVariantList items() const;
    void replace(QVector<RulesPromptOptionRow> rows);
    void clear();

  private:
    QVector<RulesPromptOptionRow> m_rows;
};

class RulesPromptCardModel final : public QAbstractListModel
{
    Q_OBJECT

  public:
    enum Role
    {
        IdRole = Qt::UserRole + 1,
        NameRole,
        SetCodeRole,
        CollectorNumberRole,
        TokenRole,
        NativeSelectedRole,
        ReadOnlyRole
    };

    explicit RulesPromptCardModel(QObject *parent = nullptr);
    int rowCount(const QModelIndex &parent = {}) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;
    Q_INVOKABLE QVariantList items() const;
    void replace(QVector<RulesPromptCardRow> rows);
    void clear();

  private:
    QVector<RulesPromptCardRow> m_rows;
};

class RulesPromptTargetModel final : public QAbstractListModel
{
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
        SeatRole,
        NativeSelectedRole
    };

    explicit RulesPromptTargetModel(QObject *parent = nullptr);
    int rowCount(const QModelIndex &parent = {}) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;
    QVariantList items() const;
    QStringList responseIdsForObject(const QString &kind, const QString &objectId) const;
    QStringList responseIdsForSeat(int seat) const;
    void replace(QVector<RulesPromptTargetRow> rows);
    void clear();

  private:
    QVector<RulesPromptTargetRow> m_rows;
};

} // namespace hexproof::client
