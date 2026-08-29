// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "models/GameTableModel.h"
#include "protocol/Message.h"

#include <QDir>
#include <QFile>
#include <QSignalSpy>
#include <QTest>

using namespace Qt::StringLiterals;
using hexproof::client::GameTableModel;

class TestGameTableModel : public QObject
{
    Q_OBJECT

  private slots:
    void indexesSnapshotDomainData() const;
    void replacesIndexesOnSubsequentSnapshots() const;
    void keepsSeatLookupConsistentDuringZoneSignals() const;
    void skipsCardReindexForMetadataOnlySnapshots() const;
    void reconcilesZoneCardsById() const;
    void keepsOpponentHandAndFaceDownIdentitiesRedacted() const;
    void consumesSharedOwnerAndOpponentSnapshots() const;
    void benchmarkFourPlayerBattlefieldSnapshot() const;
};

void TestGameTableModel::benchmarkFourPlayerBattlefieldSnapshot() const
{
    QVariantList seats;
    for (int seat = 0; seat < 4; ++seat) {
        QVariantList battlefield;
        battlefield.reserve(100);
        for (int card = 0; card < 100; ++card) {
            battlefield.append(QVariantMap{
                {u"id"_s, u"s%1-c%2"_s.arg(seat).arg(card)},
                {u"name"_s, u"Benchmark Permanent %1"_s.arg(card)},
                {u"x"_s, card % 20},
                {u"y"_s, card / 20},
            });
        }
        seats.append(QVariantMap{
            {u"seat"_s, seat},
            {u"displayName"_s, u"Player %1"_s.arg(seat + 1)},
            {u"life"_s, 40},
            {u"battlefield"_s, battlefield},
        });
    }

    GameTableModel model;
    int revision = 0;
    QBENCHMARK
    {
        QVariantList changedSeats = seats;
        QVariantMap firstSeat = changedSeats.first().toMap();
        QVariantList battlefield = firstSeat.value(u"battlefield"_s).toList();
        QVariantMap firstCard = battlefield.first().toMap();
        firstCard.insert(u"x"_s, ++revision);
        battlefield.first() = firstCard;
        firstSeat.insert(u"battlefield"_s, battlefield);
        changedSeats.first() = firstSeat;
        model.applySnapshot({{u"seats"_s, changedSeats}});
    }
    QCOMPARE(model.rowCount(), 4);
    QVERIFY(model.cardInZone(u"s3-c99"_s, u"battlefield"_s, 3));
}

void TestGameTableModel::indexesSnapshotDomainData() const
{
    GameTableModel model;
    model.applySnapshot({
        {u"seats"_s,
         QVariantList{
             QVariantMap{
                 {u"seat"_s, 0},
                 {u"displayName"_s, u"Alice"_s},
                 {u"life"_s, 20},
                 {u"hand"_s, QVariantList{QVariantMap{{u"id"_s, u"s0-h1"_s}}}},
                 {u"battlefield"_s, QVariantList{QVariantMap{{u"id"_s, u"s0-b1"_s}}}},
             },
             QVariantMap{
                 {u"seat"_s, 1},
                 {u"displayName"_s, u"Bob"_s},
                 {u"graveyard"_s, QVariantList{QVariantMap{{u"id"_s, u"s1-g1"_s}}}},
             },
         }},
        {u"stack"_s, QVariantList{QVariantMap{{u"id"_s, u"stack-1"_s}}}},
        {u"revealed"_s, QVariantList{QVariantMap{{u"id"_s, u"reveal-1"_s}}}},
        {u"attachments"_s, QVariantList{QVariantMap{
                               {u"sourceCardId"_s, u"s0-b1"_s},
                               {u"targetCardId"_s, u"s1-g1"_s},
                           }}},
        {u"arrows"_s, QVariantList{QVariantMap{
                          {u"seat"_s, 0},
                          {u"sourceCardId"_s, u"s0-b1"_s},
                          {u"kind"_s, u"target"_s},
                          {u"targetCardId"_s, u"s1-g1"_s},
                      }}},
        {u"landPlaysThisTurn"_s, 2},
    });

    QCOMPARE(model.rowCount(), 2);
    QCOMPARE(model.data(model.index(0), GameTableModel::DisplayNameRole).toString(), u"Alice"_s);
    QCOMPARE(model.seatData(1).value(u"displayName"_s).toString(), u"Bob"_s);
    QVERIFY(!model.seatData(0).contains(u"hand"_s));
    QVERIFY(!model.seatData(0).contains(u"battlefield"_s));
    QCOMPARE(model.cardData(u"s0-h1"_s).value(u"id"_s).toString(), u"s0-h1"_s);
    QVERIFY(model.cardInZone(u"s0-b1"_s, u"battlefield"_s, 0));
    QCOMPARE(model.visibleZoneSeat(u"s1-g1"_s, u"graveyard"_s), 1);
    QCOMPARE(model.visibleZoneSeat(u"stack-1"_s, u"stack"_s), -1);
    auto *handModel =
        qobject_cast<hexproof::client::ZoneCardModel *>(model.zoneModel(0, u"hand"_s));
    QVERIFY(handModel);
    QCOMPARE(handModel->rowCount(), 1);
    QCOMPARE(handModel->revision(), 1);
    QCOMPARE(handModel->data(handModel->index(0), hexproof::client::ZoneCardModel::CardIdRole)
                 .toString(),
             u"s0-h1"_s);
    QCOMPARE(model.stackModel()->rowCount(), 1);
    QCOMPARE(model.attachmentForSource(u"s0-b1"_s).value(u"targetCardId"_s).toString(), u"s1-g1"_s);
    QCOMPARE(model.arrowForSeat(0).value(u"sourceCardId"_s).toString(), u"s0-b1"_s);
    QCOMPARE(model.arrowForSource(u"s0-b1"_s).value(u"kind"_s).toString(), u"target"_s);
    QCOMPARE(model.landPlaysThisTurn(), 2);

    model.clear();
    QCOMPARE(model.rowCount(), 0);
    QVERIFY(model.cardData(u"s0-h1"_s).isEmpty());
    QCOMPARE(model.stackModel()->rowCount(), 0);
    QCOMPARE(model.zoneModel(0, u"hand"_s), handModel);
    QCOMPARE(handModel->rowCount(), 0);
    QCOMPARE(model.landPlaysThisTurn(), 0);
}

void TestGameTableModel::replacesIndexesOnSubsequentSnapshots() const
{
    GameTableModel model;
    QSignalSpy snapshotSpy(&model, &GameTableModel::snapshotChanged);

    model.applySnapshot({
        {u"seats"_s, QVariantList{QVariantMap{
                         {u"seat"_s, 0},
                         {u"libraryCount"_s, 53},
                         {u"hand"_s, QVariantList{QVariantMap{{u"id"_s, u"opening-card"_s}}}},
                     }}},
        {u"attachments"_s, QVariantList{QVariantMap{
                               {u"sourceCardId"_s, u"opening-card"_s},
                               {u"targetCardId"_s, u"target-card"_s},
                           }}},
    });
    QCOMPARE(model.seatData(0).value(u"libraryCount"_s).toInt(), 53);
    QVERIFY(model.cardInZone(u"opening-card"_s, u"hand"_s, 0));
    QVERIFY(!model.attachmentForSource(u"opening-card"_s).isEmpty());

    const QVariantMap replacementSnapshot{
        {u"seats"_s, QVariantList{QVariantMap{
                         {u"seat"_s, 0},
                         {u"libraryCount"_s, 52},
                         {u"hand"_s, QVariantList{QVariantMap{{u"id"_s, u"replacement-card"_s}}}},
                         {u"graveyard"_s, QVariantList{QVariantMap{{u"id"_s, u"opening-card"_s}}}},
                     }}},
    };
    model.applySnapshot(replacementSnapshot);
    QCOMPARE(snapshotSpy.count(), 2);
    QCOMPARE(model.seatData(0).value(u"libraryCount"_s).toInt(), 52);
    QVERIFY(model.cardInZone(u"replacement-card"_s, u"hand"_s, 0));
    QVERIFY(!model.cardInZone(u"opening-card"_s, u"hand"_s, 0));
    QVERIFY(model.cardInZone(u"opening-card"_s, u"graveyard"_s, 0));
    QVERIFY(model.attachmentForSource(u"opening-card"_s).isEmpty());
    auto *handModel =
        qobject_cast<hexproof::client::ZoneCardModel *>(model.zoneModel(0, u"hand"_s));
    QVERIFY(handModel);
    QCOMPARE(handModel->revision(), 2);

    model.applySnapshot(replacementSnapshot);
    QCOMPARE(snapshotSpy.count(), 2);

    model.clear();
    QCOMPARE(snapshotSpy.count(), 3);
    QVERIFY(model.seatData(0).isEmpty());
    QVERIFY(model.cardData(u"opening-card"_s).isEmpty());
}

void TestGameTableModel::keepsSeatLookupConsistentDuringZoneSignals() const
{
    GameTableModel model;
    model.applySnapshot({
        {u"seats"_s,
         QVariantList{
             QVariantMap{{u"seat"_s, 0}, {u"displayName"_s, u"Alice"_s}},
             QVariantMap{{u"seat"_s, 1}, {u"displayName"_s, u"Bob"_s}},
         }},
        {u"stack"_s, QVariantList{QVariantMap{{u"id"_s, u"stack-1"_s}}}},
    });

    bool observedStackRemoval = false;
    connect(model.stackModel(), &QAbstractItemModel::rowsRemoved, &model,
            [&model, &observedStackRemoval] {
                observedStackRemoval = true;
                QCOMPARE(model.seatData(0).value(u"displayName"_s).toString(), u"Alice"_s);
                QVERIFY(model.seatData(1).isEmpty());
            });

    model.applySnapshot({
        {u"seats"_s, QVariantList{QVariantMap{{u"seat"_s, 0}, {u"displayName"_s, u"Alice"_s}}}},
        {u"stack"_s, QVariantList{}},
    });

    QVERIFY(observedStackRemoval);
}

void TestGameTableModel::skipsCardReindexForMetadataOnlySnapshots() const
{
    GameTableModel model;
    const QVariantList hand{QVariantMap{{u"id"_s, u"card-1"_s}, {u"name"_s, u"Card"_s}}};
    QVariantMap snapshot{
        {u"activeSeat"_s, 0},
        {u"seats"_s, QVariantList{QVariantMap{
                         {u"seat"_s, 0},
                         {u"displayName"_s, u"Alice"_s},
                         {u"life"_s, 20},
                         {u"hand"_s, hand},
                     }}},
    };
    model.applySnapshot(snapshot);

    auto *handModel =
        qobject_cast<hexproof::client::ZoneCardModel *>(model.zoneModel(0, u"hand"_s));
    QVERIFY(handModel);
    const quint64 initialZoneRevision = handModel->revision();
    const quint64 initialIndexRevision = model.cardIndexRevision();
    const quint64 initialSeatRevision = model.seatData(0).value(u"modelRevision"_s).toULongLong();
    QCOMPARE(initialZoneRevision, quint64(1));
    QCOMPARE(initialIndexRevision, quint64(1));
    QCOMPARE(initialSeatRevision, quint64(1));

    snapshot[u"activeSeat"_s] = 1;
    model.applySnapshot(snapshot);
    QCOMPARE(handModel->revision(), initialZoneRevision);
    QCOMPARE(model.cardIndexRevision(), initialIndexRevision);
    QCOMPARE(model.seatData(0).value(u"modelRevision"_s).toULongLong(), initialSeatRevision);

    QVariantList seats = snapshot.value(u"seats"_s).toList();
    QVariantMap seat = seats.first().toMap();
    seat[u"life"_s] = 19;
    seats[0] = seat;
    snapshot[u"seats"_s] = seats;
    model.applySnapshot(snapshot);
    QCOMPARE(handModel->revision(), initialZoneRevision);
    QCOMPARE(model.cardIndexRevision(), initialIndexRevision);
    QCOMPARE(model.seatData(0).value(u"modelRevision"_s).toULongLong(), initialSeatRevision + 1);

    seat[u"hand"_s] =
        QVariantList{QVariantMap{{u"id"_s, u"card-2"_s}, {u"name"_s, u"Replacement"_s}}};
    seats[0] = seat;
    snapshot[u"seats"_s] = seats;
    model.applySnapshot(snapshot);
    QCOMPARE(handModel->revision(), initialZoneRevision + 1);
    QCOMPARE(model.cardIndexRevision(), initialIndexRevision + 1);
    QVERIFY(model.cardData(u"card-1"_s).isEmpty());
    QCOMPARE(model.cardData(u"card-2"_s).value(u"name"_s).toString(), u"Replacement"_s);
}

void TestGameTableModel::reconcilesZoneCardsById() const
{
    hexproof::client::ZoneCardModel model;
    QSignalSpy resetSpy(&model, &QAbstractItemModel::modelReset);
    QSignalSpy changedSpy(&model, &QAbstractItemModel::dataChanged);
    QSignalSpy movedSpy(&model, &QAbstractItemModel::rowsMoved);

    model.replaceCards({QVariantMap{{u"id"_s, u"a"_s}, {u"tapped"_s, false}},
                        QVariantMap{{u"id"_s, u"b"_s}, {u"tapped"_s, false}}});
    QCOMPARE(model.rowCount(), 2);
    QCOMPARE(resetSpy.count(), 0);

    model.replaceCards({QVariantMap{{u"id"_s, u"b"_s}, {u"tapped"_s, true}},
                        QVariantMap{{u"id"_s, u"a"_s}, {u"tapped"_s, false}}});
    QCOMPARE(resetSpy.count(), 0);
    QCOMPARE(movedSpy.count(), 1);
    QCOMPARE(changedSpy.count(), 1);
    QCOMPARE(model.data(model.index(0), hexproof::client::ZoneCardModel::CardIdRole).toString(),
             u"b"_s);
    QCOMPARE(model.data(model.index(0), hexproof::client::ZoneCardModel::TappedRole).toBool(),
             true);

    model.replaceCards({QVariantMap{{u"id"_s, u"b"_s}}, QVariantMap{{u"id"_s, u"c"_s}}});
    QCOMPARE(resetSpy.count(), 0);
    QCOMPARE(model.rowCount(), 2);
    QCOMPARE(model.data(model.index(1), hexproof::client::ZoneCardModel::CardIdRole).toString(),
             u"c"_s);
}

void TestGameTableModel::keepsOpponentHandAndFaceDownIdentitiesRedacted() const
{
    GameTableModel model;
    model.applySnapshot({
        {u"seats"_s,
         QVariantList{
             QVariantMap{
                 {u"seat"_s, 0},
                 {u"displayName"_s, u"You"_s},
                 {u"hand"_s,
                  QVariantList{QVariantMap{{u"id"_s, u"own-hand"_s}, {u"name"_s, u"Island"_s}}}},
                 {u"battlefield"_s, QVariantList{QVariantMap{{u"id"_s, u"own-morph"_s},
                                                             {u"name"_s, u"Willbender"_s},
                                                             {u"faceDown"_s, true}}}},
             },
             QVariantMap{
                 {u"seat"_s, 1},
                 {u"displayName"_s, u"Opponent"_s},
                 {u"handCount"_s, 1},
                 {u"hand"_s, QVariantList{QVariantMap{{u"id"_s, u"opp-hand"_s}}}},
                 {u"battlefield"_s,
                  QVariantList{QVariantMap{{u"id"_s, u"opp-morph"_s}, {u"faceDown"_s, true}}}},
             },
         }},
    });

    auto *ownHand = qobject_cast<hexproof::client::ZoneCardModel *>(model.zoneModel(0, u"hand"_s));
    auto *oppHand = qobject_cast<hexproof::client::ZoneCardModel *>(model.zoneModel(1, u"hand"_s));
    auto *ownBattle =
        qobject_cast<hexproof::client::ZoneCardModel *>(model.zoneModel(0, u"battlefield"_s));
    auto *oppBattle =
        qobject_cast<hexproof::client::ZoneCardModel *>(model.zoneModel(1, u"battlefield"_s));
    QVERIFY(ownHand);
    QVERIFY(oppHand);
    QVERIFY(ownBattle);
    QVERIFY(oppBattle);

    QCOMPARE(ownHand->data(ownHand->index(0), hexproof::client::ZoneCardModel::NameRole).toString(),
             u"Island"_s);
    QVERIFY(oppHand->data(oppHand->index(0), hexproof::client::ZoneCardModel::NameRole)
                .toString()
                .isEmpty());
    QVERIFY(!oppHand->data(oppHand->index(0), hexproof::client::ZoneCardModel::CardDataRole)
                 .toMap()
                 .contains(u"name"_s));
    QCOMPARE(ownBattle->data(ownBattle->index(0), hexproof::client::ZoneCardModel::FaceDownRole)
                 .toBool(),
             true);
    QCOMPARE(
        ownBattle->data(ownBattle->index(0), hexproof::client::ZoneCardModel::NameRole).toString(),
        u"Willbender"_s);
    QCOMPARE(oppBattle->data(oppBattle->index(0), hexproof::client::ZoneCardModel::FaceDownRole)
                 .toBool(),
             true);
    QVERIFY(oppBattle->data(oppBattle->index(0), hexproof::client::ZoneCardModel::NameRole)
                .toString()
                .isEmpty());
    QVERIFY(oppBattle->data(oppBattle->index(0), hexproof::client::ZoneCardModel::SetCodeRole)
                .toString()
                .isEmpty());
}

void TestGameTableModel::consumesSharedOwnerAndOpponentSnapshots() const
{
    const auto verifyFixture = [](const QString &name, int visibleSeat, int hiddenSeat,
                                  const QString &firstCardName) {
        QFile file(QDir(QStringLiteral(HEXPROOF_PROTOCOL_FIXTURE_DIR)).filePath(name));
        QVERIFY2(file.open(QIODevice::ReadOnly), qPrintable(file.fileName()));
        bool ok = false;
        const hexproof::protocol::Envelope envelope =
            hexproof::protocol::parse(file.readAll(), &ok);
        QVERIFY(ok);
        QCOMPARE(envelope.type, hexproof::protocol::kTypeGameSnapshot);

        GameTableModel model;
        model.applySnapshot(envelope.payload.toVariantMap());
        auto *visible = qobject_cast<hexproof::client::ZoneCardModel *>(
            model.zoneModel(visibleSeat, u"hand"_s));
        auto *hidden =
            qobject_cast<hexproof::client::ZoneCardModel *>(model.zoneModel(hiddenSeat, u"hand"_s));
        QVERIFY(visible);
        QVERIFY(hidden);
        QCOMPARE(visible->rowCount(), 7);
        QCOMPARE(hidden->rowCount(), 0);
        QCOMPARE(
            visible->data(visible->index(0), hexproof::client::ZoneCardModel::NameRole).toString(),
            firstCardName);
        QCOMPARE(model.seatData(hiddenSeat).value(u"handCount"_s).toInt(), 7);
        QVERIFY(!model.seatData(hiddenSeat).contains(u"hand"_s));
    };

    verifyFixture(u"game-snapshot-owner.json"_s, 0, 1, u"Lightning Bolt"_s);
    verifyFixture(u"game-snapshot-opponent.json"_s, 1, 0, u"Island"_s);
}

QTEST_MAIN(TestGameTableModel)
#include "gametablemodel_test.moc"
