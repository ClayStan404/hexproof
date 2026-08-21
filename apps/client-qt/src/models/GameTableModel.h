// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#pragma once

#include <QAbstractListModel>
#include <QHash>
#include <QSet>
#include <QVariantList>
#include <QVariantMap>
#include <QVector>

#include "ZoneCardModel.h"

namespace hexproof::client {

class GameTableModel : public QAbstractListModel
{
    Q_OBJECT
    Q_PROPERTY(int count READ rowCount NOTIFY snapshotChanged)
    Q_PROPERTY(QVariantList seats READ seats NOTIFY snapshotChanged)
    Q_PROPERTY(QVariantList arrows READ arrows NOTIFY snapshotChanged)
    Q_PROPERTY(QVariantList attachments READ attachments NOTIFY snapshotChanged)
    Q_PROPERTY(QVariantList commanders READ commanders NOTIFY snapshotChanged)
    Q_PROPERTY(QVariantList commanderDamage READ commanderDamage NOTIFY snapshotChanged)
    Q_PROPERTY(QVariantList gameLog READ gameLog NOTIFY snapshotChanged)
    Q_PROPERTY(int landPlaysThisTurn READ landPlaysThisTurn NOTIFY snapshotChanged)
    Q_PROPERTY(ZoneCardModel *stackModel READ stackModel CONSTANT)
    Q_PROPERTY(ZoneCardModel *revealedModel READ revealedModel CONSTANT)

  public:
    enum Role
    {
        SeatRole = Qt::UserRole + 1,
        DisplayNameRole,
        LifeRole,
        CountersRole,
        CounterCountRole,
        LibraryCountRole,
        HandCountRole,
        MulliganCountRole,
        SideboardCountRole,
        CommanderTaxRole,
        CommanderTaxesRole,
        EliminatedRole,
        ModelRevisionRole,
        HandModelRole,
        SideboardModelRole,
        BattlefieldModelRole,
        GraveyardModelRole,
        ExileModelRole,
        CommandZoneModelRole
    };
    Q_ENUM(Role)

    explicit GameTableModel(QObject *parent = nullptr);
    ~GameTableModel() override;

    int rowCount(const QModelIndex &parent = {}) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;

    QVariantList seats() const;
    QVariantList stackCards() const;
    QVariantList revealedCards() const;
    QVariantList arrows() const;
    QVariantList attachments() const;
    QVariantList commanders() const;
    QVariantList commanderDamage() const;
    QVariantList gameLog() const;
    int landPlaysThisTurn() const;
    ZoneCardModel *stackModel() const;
    ZoneCardModel *revealedModel() const;
    quint64 cardIndexRevision() const;

    Q_INVOKABLE QVariantMap seatData(int seat) const;
    Q_INVOKABLE QObject *zoneModel(int seat, const QString &zone) const;
    Q_INVOKABLE QVariantMap cardData(const QString &cardId) const;
    Q_INVOKABLE bool cardInZone(const QString &cardId, const QString &zone, int seat) const;
    Q_INVOKABLE int visibleZoneSeat(const QString &cardId, const QString &zone) const;
    Q_INVOKABLE QVariantMap attachmentForSource(const QString &cardId) const;
    Q_INVOKABLE QVariantMap arrowForSeat(int seat) const;
    Q_INVOKABLE QVariantMap arrowForSource(const QString &cardId) const;

  public slots:
    void applySnapshot(const QVariantMap &snapshot);
    void clear();

  signals:
    void snapshotChanged();

  private:
    struct SeatZoneModels
    {
        ZoneCardModel *hand = nullptr;
        ZoneCardModel *sideboard = nullptr;
        ZoneCardModel *battlefield = nullptr;
        ZoneCardModel *graveyard = nullptr;
        ZoneCardModel *exile = nullptr;
        ZoneCardModel *commandZone = nullptr;
    };

    struct ZoneUpdate
    {
        int seat = -1;
        QString zone;
        QVariantList cards;
        ZoneCardModel *model = nullptr;
    };

    static QVariantList listValue(const QVariantMap &map, const QString &key);
    static QVariantMap seatMetadata(const QVariantMap &seat);
    static QString zoneCardKey(const QString &cardId, const QString &zone);
    static QString zoneStorageKey(int seat, const QString &zone);
    SeatZoneModels *ensureSeatZoneModels(int seat);
    ZoneCardModel *seatZoneModel(int seat, const QString &zone) const;
    void appendZoneUpdate(QVector<ZoneUpdate> &updates, int seat, const QString &zone,
                          const QVariantList &cards, ZoneCardModel *model);
    void appendSeatZoneUpdates(QVector<ZoneUpdate> &updates, int seat, const QVariantMap &seatData);
    void applyZoneUpdates(const QVector<ZoneUpdate> &updates);
    void indexCards(const QVariantList &cards, const QString &zone, int seat);
    void rebuildAttachmentIndex();
    void rebuildArrowIndex();

    QVariantList m_seats;
    QVariantList m_stackCards;
    QVariantList m_revealedCards;
    QVariantList m_arrows;
    QVariantList m_attachments;
    QVariantList m_commanders;
    QVariantList m_commanderDamage;
    QVariantList m_gameLog;
    int m_landPlaysThisTurn = 0;
    QHash<int, int> m_rowForSeat;
    QHash<int, quint64> m_seatRevisions;
    QHash<QString, QVariantList> m_cardsByZone;
    QHash<QString, QVariantMap> m_cardById;
    QHash<QString, int> m_seatForZoneCard;
    QHash<QString, QVariantMap> m_attachmentBySource;
    QHash<int, QVariantMap> m_arrowBySeat;
    QHash<QString, QVariantMap> m_arrowBySource;
    QHash<int, SeatZoneModels *> m_zoneModelsBySeat;
    ZoneCardModel *m_stackModel = nullptr;
    ZoneCardModel *m_revealedModel = nullptr;
    QVariantMap m_snapshot;
    quint64 m_cardIndexRevision = 0;
};

} // namespace hexproof::client
