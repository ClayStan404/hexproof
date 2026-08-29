// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "services/MatchLoadCoordinator.h"

#include <QSignalSpy>
#include <QTest>

using namespace Qt::StringLiterals;
using hexproof::client::MatchLoadCoordinator;

class TestMatchLoadCoordinator : public QObject
{
    Q_OBJECT

  private slots:
    void completesOnlyAfterEveryCardSucceeds() const;
    void retriesOnlyFailedCards() const;
    void cancelIgnoresLateResults() const;
};

QVariantList cardRequests()
{
    return {
        QVariantMap{{u"name"_s, u"Lightning Bolt"_s},
                    {u"setCode"_s, u"M11"_s},
                    {u"collectorNumber"_s, u"149"_s}},
        QVariantMap{
            {u"name"_s, u"Sol Ring"_s}, {u"setCode"_s, u"CMM"_s}, {u"collectorNumber"_s, u"396"_s}},
    };
}

void TestMatchLoadCoordinator::completesOnlyAfterEveryCardSucceeds() const
{
    MatchLoadCoordinator loader;
    QSignalSpy requests(&loader, &MatchLoadCoordinator::cardsRequested);
    QSignalSpy completed(&loader, &MatchLoadCoordinator::loadComplete);

    loader.beginLoad(7, cardRequests());
    QCOMPARE(loader.loadId(), 7);
    QCOMPARE(loader.total(), 2);
    QTRY_COMPARE_WITH_TIMEOUT(requests.count(), 1, 1'000);
    loader.handleCardCacheFinished(u"Lightning Bolt"_s, u"M11"_s, u"149"_s, true);
    QCOMPARE(loader.completed(), 1);
    QCOMPARE(completed.count(), 0);
    loader.handleCardCacheFinished(u"Sol Ring"_s, u"CMM"_s, u"396"_s, true);
    QCOMPARE(completed.count(), 1);
    QVERIFY(loader.ready());
    QVERIFY(!loader.active());
    QCOMPARE(loader.progress(), 1.0);
}

void TestMatchLoadCoordinator::retriesOnlyFailedCards() const
{
    MatchLoadCoordinator loader;
    QSignalSpy requests(&loader, &MatchLoadCoordinator::cardsRequested);
    QSignalSpy completed(&loader, &MatchLoadCoordinator::loadComplete);

    loader.beginLoad(8, cardRequests());
    QTRY_COMPARE_WITH_TIMEOUT(requests.count(), 1, 1'000);
    loader.handleCardCacheFinished(u"Lightning Bolt"_s, u"M11"_s, u"149"_s, true);
    loader.handleCardCacheFinished(u"Sol Ring"_s, u"CMM"_s, u"396"_s, false);
    QCOMPARE(loader.failed(), 1);
    QVERIFY(!loader.lastError().isEmpty());
    QCOMPARE(completed.count(), 0);

    loader.retry();
    QCOMPARE(requests.count(), 2);
    const QVariantList retried = requests.at(1).at(0).toList();
    QCOMPARE(retried.size(), 1);
    QCOMPARE(retried.first().toMap().value(u"name"_s).toString(), u"Sol Ring"_s);
    loader.handleCardCacheFinished(u"Sol Ring"_s, u"CMM"_s, u"396"_s, true);
    QCOMPARE(completed.count(), 1);
    QVERIFY(loader.ready());
}

void TestMatchLoadCoordinator::cancelIgnoresLateResults() const
{
    MatchLoadCoordinator loader;
    QSignalSpy completed(&loader, &MatchLoadCoordinator::loadComplete);
    loader.beginLoad(9, cardRequests());
    loader.cancel();
    loader.handleCardCacheFinished(u"Lightning Bolt"_s, u"M11"_s, u"149"_s, true);
    QCOMPARE(loader.loadId(), 0);
    QCOMPARE(completed.count(), 0);
    QVERIFY(!loader.active());
}

QTEST_GUILESS_MAIN(TestMatchLoadCoordinator)
#include "matchload_test.moc"
