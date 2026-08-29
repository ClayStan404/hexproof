// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#pragma once

#include <QAbstractListModel>
#include <QString>
#include <QVector>

namespace hexproof::client {

struct RulesNamedValue
{
    QString name;
    int value = 0;
};

struct RulesPlayerRow
{
    int seat = -1;
    QString name;
    QString status;
    int life = 0;
    QVector<RulesNamedValue> counters;
    QVector<RulesNamedValue> manaPool;
};

struct RulesZoneRow
{
    QString zone;
    int ownerSeat = -1;
    int count = 0;
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
    bool faceDown = false;
    bool attacking = false;
    QString power;
    QString toughness;
    int damage = 0;
    QString attachedTo;
    QVector<RulesNamedValue> counters;
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
};

class RulesPlayerModel final : public QAbstractListModel
{
  public:
    enum Role
    {
        SeatRole = Qt::UserRole + 1,
        NameRole,
        StatusRole,
        LifeRole,
        CountersSummaryRole,
        ManaSummaryRole
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

class RulesZoneModel final : public QAbstractListModel
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
    void replace(QVector<RulesZoneRow> rows);
    void clear();

  private:
    QVector<RulesZoneRow> m_rows;
};

class RulesCardModel final : public QAbstractListModel
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
        FaceDownRole,
        AttackingRole,
        PowerRole,
        ToughnessRole,
        DamageRole,
        AttachedToRole,
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

class RulesStackModel final : public QAbstractListModel
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
        TextRole
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
    void replace(QVector<RulesPromptOptionRow> rows);
    void clear();

  private:
    QVector<RulesPromptOptionRow> m_rows;
};

class RulesPromptCardModel final : public QAbstractListModel
{
  public:
    enum Role
    {
        IdRole = Qt::UserRole + 1,
        NameRole,
        SetCodeRole,
        CollectorNumberRole,
        TokenRole
    };

    explicit RulesPromptCardModel(QObject *parent = nullptr);
    int rowCount(const QModelIndex &parent = {}) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;
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
        TokenRole
    };

    explicit RulesPromptTargetModel(QObject *parent = nullptr);
    int rowCount(const QModelIndex &parent = {}) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;
    void replace(QVector<RulesPromptTargetRow> rows);
    void clear();

  private:
    QVector<RulesPromptTargetRow> m_rows;
};

} // namespace hexproof::client
