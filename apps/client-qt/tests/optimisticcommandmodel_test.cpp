// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "models/OptimisticCommandModel.h"

#include <QSignalSpy>
#include <QTest>

using namespace Qt::StringLiterals;
using hexproof::client::OptimisticCommandModel;

class TestOptimisticCommandModel : public QObject
{
    Q_OBJECT

  private slots:
    void expiresValuesIndependently() const;
    void rollsBackOnlyTheCorrelatedRequest() const;
    void ownsCardMoveAndBattlefieldPreview() const;
    void ownsPhasePreviewAndRequest() const;
    void ownsLandPlayPreviewAndRequest() const;
};

void TestOptimisticCommandModel::expiresValuesIndependently() const
{
    OptimisticCommandModel model;
    model.setTimeoutMs(80);
    QSignalSpy expired(&model, &OptimisticCommandModel::valuesExpired);
    model.setValue(u"life"_s, u"0"_s, 19);
    model.trackValues(u"life"_s, {u"0"_s});

    // Give the later preview a longer timeout so coarse QTimer ticks cannot
    // expire both keys in the same expireValues() pass.
    model.setTimeoutMs(2000);
    model.setValue(u"counter"_s, u"0:counter-1"_s, 1);
    model.trackValues(u"counter"_s, {u"0:counter-1"_s});

    QTRY_VERIFY_WITH_TIMEOUT(!model.contains(u"life"_s, u"0"_s), 500);
    QVERIFY(model.contains(u"counter"_s, u"0:counter-1"_s));
    QTRY_VERIFY_WITH_TIMEOUT(!model.contains(u"counter"_s, u"0:counter-1"_s), 3000);
    QCOMPARE(expired.count(), 2);
    QCOMPARE(expired.at(0).at(0).toInt(), 1);
}

void TestOptimisticCommandModel::rollsBackOnlyTheCorrelatedRequest() const
{
    OptimisticCommandModel model;
    model.setValue(u"tapped"_s, u"card-a"_s, true);
    model.setValue(u"tapped"_s, u"card-b"_s, false);
    model.trackValues(u"tapped"_s, {u"card-a"_s, u"card-b"_s});
    model.bindRequest(u"tapped"_s, u"card-a"_s, u"request-a"_s);
    model.bindRequest(u"tapped"_s, u"card-b"_s, u"request-b"_s);

    model.rollback(u"tapped"_s, u"card-a"_s, u"request-b"_s);
    QVERIFY(model.contains(u"tapped"_s, u"card-a"_s));
    QVERIFY(model.contains(u"tapped"_s, u"card-b"_s));

    model.rollback(u"tapped"_s, u"card-a"_s, u"request-a"_s);
    QVERIFY(!model.contains(u"tapped"_s, u"card-a"_s));
    QVERIFY(model.contains(u"tapped"_s, u"card-b"_s));
}

void TestOptimisticCommandModel::ownsCardMoveAndBattlefieldPreview() const
{
    OptimisticCommandModel model;
    model.setBattlefieldMove({
        {u"cardId"_s, u"card-a"_s},
        {u"toSeat"_s, 0},
        {u"x"_s, 0.4},
        {u"y"_s, 0.6},
    });
    model.beginCardMoves({QVariantMap{
        {u"cardId"_s, u"card-a"_s},
        {u"card"_s, QVariantMap{}},
        {u"fromZone"_s, u"library"_s},
        {u"fromSeat"_s, 0},
        {u"toZone"_s, u"battlefield"_s},
        {u"toSeat"_s, 0},
        {u"x"_s, 0.4},
        {u"y"_s, 0.6},
    }});

    QVERIFY(model.contains(u"move"_s, u"card-a"_s));
    const QVariantMap move = model.cardMoves().value(u"card-a"_s).toMap();
    QVERIFY(move.value(u"card"_s).toMap().value(u"pending"_s).toBool());
    QVERIFY(move.value(u"card"_s).toMap().value(u"faceDown"_s).toBool());

    model.beginCardMoves({QVariantMap{
        {u"cardId"_s, u"card-b"_s},
        {u"card"_s,
         QVariantMap{
             {u"id"_s, u"card-b"_s},
             {u"name"_s, u"Visible card"_s},
             {u"faceDown"_s, true},
         }},
        {u"fromZone"_s, u"hand"_s},
        {u"fromSeat"_s, 0},
        {u"toZone"_s, u"graveyard"_s},
        {u"toSeat"_s, 0},
    }});
    const QVariantMap visibleMove = model.cardMoves().value(u"card-b"_s).toMap();
    QVERIFY(!visibleMove.value(u"card"_s).toMap().value(u"faceDown"_s).toBool());

    model.bindRequest(u"move"_s, u"card-a"_s, u"move-request"_s);
    model.rollback(u"move"_s, u"card-a"_s, u"other-request"_s);
    QVERIFY(model.contains(u"move"_s, u"card-a"_s));
    model.rollback(u"move"_s, u"card-a"_s, u"move-request"_s);
    QVERIFY(!model.contains(u"move"_s, u"card-a"_s));
    QVERIFY(model.battlefieldMove().isEmpty());
}

void TestOptimisticCommandModel::ownsPhasePreviewAndRequest() const
{
    OptimisticCommandModel model;
    model.beginPhase(u"draw"_s);
    QCOMPARE(model.phase(), u"draw"_s);
    model.bindPhaseRequest(u"phase-request"_s);

    model.rollbackPhase(u"other-request"_s);
    QCOMPARE(model.phase(), u"draw"_s);
    model.rollbackPhase(u"phase-request"_s);
    QVERIFY(model.phase().isEmpty());
}

void TestOptimisticCommandModel::ownsLandPlayPreviewAndRequest() const
{
    OptimisticCommandModel model;
    model.beginLandPlayCount(2);
    QCOMPARE(model.landPlayCount(), 2);
    model.bindLandPlayCountRequest(u"land-request"_s);

    model.rollbackLandPlayCount(u"other-request"_s);
    QCOMPARE(model.landPlayCount(), 2);
    model.rollbackLandPlayCount(u"land-request"_s);
    QCOMPARE(model.landPlayCount(), -1);
}

QTEST_MAIN(TestOptimisticCommandModel)
#include "optimisticcommandmodel_test.moc"
