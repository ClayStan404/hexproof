// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "services/MatchCardCacheBinding.h"
#include "services/MatchLoadCoordinator.h"
#include "services/RoomSessionState.h"
#include "services/RulesSessionState.h"

#include "models/GameTableModel.h"

#include <QJsonArray>
#include <QSignalSpy>
#include <QTest>

using namespace Qt::StringLiterals;
using hexproof::client::MatchLoadCoordinator;

class TestMatchLoadCoordinator : public QObject
{
    Q_OBJECT

  private slots:
    void preloadExpandsBeforeCachingEveryFace() const;
    void backgroundWaitsForTableSnapshotTurn() const;
    void snapshotBeforeBackgroundLoadStartsNextTurn() const;
    void clearedSnapshotBeforeBackgroundLoadWaits() const;
    void cancelledOrReplacedBackgroundLoadCannotStart() const;
    void staleExpansionCannotBeAdopted() const;
    void languageRestartRejectsOldCompletion() const;
    void exactArtModesCannotCrossSettle() const;
    void retriesOnlyFailedCards() const;
    void cancelIgnoresLateResults() const;
    void runtimeBindingWaitsForTheSelectedMode() const;
    void runtimeBindingCancelsQueuedWorkOnLeave() const;
    void spectatorVisibleCardsUseIndependentAuthorizedBatch() const;
    void promptCardsAndPreferenceRefreshAreCoalesced() const;
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

void connectSnapshotReadiness(hexproof::client::GameTableModel *table, MatchLoadCoordinator *loader)
{
    QObject::connect(
        table, &hexproof::client::GameTableModel::snapshotChanged, loader,
        [table, loader]() { loader->handleTableSnapshotStateChanged(table->hasSnapshot()); });
}

void TestMatchLoadCoordinator::preloadExpandsBeforeCachingEveryFace() const
{
    MatchLoadCoordinator loader;
    QSignalSpy expansions(&loader, &MatchLoadCoordinator::cardFaceExpansionRequested);
    QSignalSpy requests(&loader, &MatchLoadCoordinator::cardsRequested);
    QSignalSpy completed(&loader, &MatchLoadCoordinator::loadComplete);

    loader.preparePreload(7, {QVariantMap{{u"name"_s, u"Delver of Secrets"_s},
                                          {u"setCode"_s, u"MID"_s},
                                          {u"collectorNumber"_s, u"47"_s}}});
    QCOMPARE(loader.loadId(), 7);
    QVERIFY(loader.expansionPending());
    QCOMPARE(loader.total(), 0);
    QCOMPARE(requests.count(), 0);
    QCOMPARE(completed.count(), 0);
    QTRY_COMPARE_WITH_TIMEOUT(expansions.count(), 1, 1'000);

    const QList<QVariant> expansion = expansions.takeFirst();
    QCOMPARE(expansion.at(0).toLongLong(), 7);
    const quint64 generation = expansion.at(1).toULongLong();
    QVERIFY(generation > 0);
    loader.adoptExpandedCards(7, generation,
                              {
                                  QVariantMap{{u"name"_s, u"Delver of Secrets"_s},
                                              {u"setCode"_s, u"MID"_s},
                                              {u"collectorNumber"_s, u"47"_s},
                                              {u"priorityName"_s, u"Delver of Secrets"_s}},
                                  QVariantMap{{u"name"_s, u"Insectile Aberration"_s},
                                              {u"setCode"_s, u"MID"_s},
                                              {u"collectorNumber"_s, u"47"_s},
                                              {u"priorityName"_s, u"Delver of Secrets"_s}},
                              });

    QVERIFY(!loader.expansionPending());
    QCOMPARE(loader.total(), 2);
    QCOMPARE(requests.count(), 1);
    const QVariantList requestedCards = requests.first().at(2).toList();
    QCOMPARE(requestedCards.at(0).toMap().value(u"name"_s).toString(), u"Delver of Secrets"_s);
    QCOMPARE(requestedCards.at(1).toMap().value(u"name"_s).toString(), u"Insectile Aberration"_s);
    loader.handleMatchCardCacheFinished(7, generation, u"en|delver of secrets|MID|47"_s,
                                        u"Delver of Secrets"_s, u"MID"_s, u"47"_s, false, true);
    QCOMPARE(loader.completed(), 1);
    QCOMPARE(completed.count(), 0);
    loader.handleMatchCardCacheFinished(7, generation, u"en|insectile aberration|MID|47"_s,
                                        u"Insectile Aberration"_s, u"MID"_s, u"47"_s, false, true);
    QCOMPARE(completed.count(), 1);
    QVERIFY(loader.ready());
    QVERIFY(!loader.active());
    QCOMPARE(loader.progress(), 1.0);
}

void TestMatchLoadCoordinator::backgroundWaitsForTableSnapshotTurn() const
{
    MatchLoadCoordinator loader;
    QSignalSpy expansions(&loader, &MatchLoadCoordinator::cardFaceExpansionRequested);

    loader.prepareBackground(8, cardRequests());
    QTest::qWait(20);
    QCOMPARE(expansions.count(), 0);

    loader.handleTableSnapshotStateChanged(true);
    QCOMPARE(expansions.count(), 0);
    QTRY_COMPARE_WITH_TIMEOUT(expansions.count(), 1, 1'000);
    QCOMPARE(expansions.first().at(0).toLongLong(), 8);
}

void TestMatchLoadCoordinator::snapshotBeforeBackgroundLoadStartsNextTurn() const
{
    hexproof::client::GameTableModel table;
    MatchLoadCoordinator loader;
    connectSnapshotReadiness(&table, &loader);
    QSignalSpy expansions(&loader, &MatchLoadCoordinator::cardFaceExpansionRequested);

    table.applySnapshot({{u"gameId"_s, u"game-1"_s}});
    QVERIFY(table.hasSnapshot());
    QVERIFY(!loader.active());

    loader.prepareBackground(9, cardRequests());
    QCOMPARE(expansions.count(), 0);
    QTRY_COMPARE_WITH_TIMEOUT(expansions.count(), 1, 1'000);
    QCOMPARE(expansions.first().at(0).toLongLong(), 9);
}

void TestMatchLoadCoordinator::clearedSnapshotBeforeBackgroundLoadWaits() const
{
    hexproof::client::GameTableModel table;
    MatchLoadCoordinator loader;
    connectSnapshotReadiness(&table, &loader);
    QSignalSpy expansions(&loader, &MatchLoadCoordinator::cardFaceExpansionRequested);

    table.applySnapshot({{u"gameId"_s, u"game-1"_s}});
    table.clear();
    QVERIFY(!table.hasSnapshot());
    loader.prepareBackground(10, cardRequests());
    QTest::qWait(20);
    QCOMPARE(expansions.count(), 0);

    table.applySnapshot({{u"gameId"_s, u"game-2"_s}});
    QCOMPARE(expansions.count(), 0);
    QTRY_COMPARE_WITH_TIMEOUT(expansions.count(), 1, 1'000);
    QCOMPARE(expansions.first().at(0).toLongLong(), 10);
}

void TestMatchLoadCoordinator::cancelledOrReplacedBackgroundLoadCannotStart() const
{
    MatchLoadCoordinator loader;
    QSignalSpy expansions(&loader, &MatchLoadCoordinator::cardFaceExpansionRequested);

    loader.prepareBackground(9, cardRequests());
    loader.cancel();
    loader.handleTableSnapshotStateChanged(true);
    QTest::qWait(20);
    QCOMPARE(expansions.count(), 0);

    loader.prepareBackground(10, cardRequests());
    loader.handleTableSnapshotStateChanged(true);
    loader.prepareBackground(11, cardRequests());
    loader.handleTableSnapshotStateChanged(false);
    QTest::qWait(20);
    QCOMPARE(expansions.count(), 0);
    loader.handleTableSnapshotStateChanged(true);
    QTRY_COMPARE_WITH_TIMEOUT(expansions.count(), 1, 1'000);
    QCOMPARE(expansions.first().at(0).toLongLong(), 11);
}

void TestMatchLoadCoordinator::staleExpansionCannotBeAdopted() const
{
    MatchLoadCoordinator loader;
    QSignalSpy expansions(&loader, &MatchLoadCoordinator::cardFaceExpansionRequested);
    QSignalSpy requests(&loader, &MatchLoadCoordinator::cardsRequested);

    loader.preparePreload(12, cardRequests());
    QTRY_COMPARE_WITH_TIMEOUT(expansions.count(), 1, 1'000);
    const quint64 staleGeneration = expansions.first().at(1).toULongLong();
    loader.preparePreload(13, cardRequests());
    QTRY_COMPARE_WITH_TIMEOUT(expansions.count(), 2, 1'000);
    const quint64 currentGeneration = expansions.at(1).at(1).toULongLong();
    QVERIFY(currentGeneration != staleGeneration);

    loader.adoptExpandedCards(12, staleGeneration, cardRequests());
    loader.adoptExpandedCards(13, staleGeneration, cardRequests());
    QCOMPARE(requests.count(), 0);
    QVERIFY(loader.expansionPending());

    loader.adoptExpandedCards(13, currentGeneration, cardRequests());
    QCOMPARE(requests.count(), 1);
    QVERIFY(!loader.expansionPending());
}

void TestMatchLoadCoordinator::languageRestartRejectsOldCompletion() const
{
    MatchLoadCoordinator loader;
    QSignalSpy expansions(&loader, &MatchLoadCoordinator::cardFaceExpansionRequested);
    QSignalSpy completed(&loader, &MatchLoadCoordinator::loadComplete);
    QSignalSpy invalidated(&loader, &MatchLoadCoordinator::matchCardSubscriptionsInvalidated);

    loader.preparePreload(14, {cardRequests().first()});
    QTRY_COMPARE_WITH_TIMEOUT(expansions.count(), 1, 1'000);
    const quint64 oldGeneration = expansions.first().at(1).toULongLong();
    loader.adoptExpandedCards(14, oldGeneration, {cardRequests().first()});
    QCOMPARE(loader.total(), 1);

    loader.handleCardLanguageChanged();
    QCOMPARE(invalidated.count(), 1);
    QCOMPARE(invalidated.first().at(0).toLongLong(), 14);
    QCOMPARE(invalidated.first().at(1).toULongLong(), oldGeneration);
    QVERIFY(loader.expansionPending());
    QTRY_COMPARE_WITH_TIMEOUT(expansions.count(), 2, 1'000);
    const quint64 currentGeneration = expansions.at(1).at(1).toULongLong();
    QVERIFY(currentGeneration != oldGeneration);
    loader.adoptExpandedCards(14, currentGeneration, {cardRequests().first()});

    loader.handleMatchCardCacheFinished(14, oldGeneration, u"en|lightning bolt|M11|149"_s,
                                        u"Lightning Bolt"_s, u"M11"_s, u"149"_s, false, false);
    QCOMPARE(loader.completed(), 0);
    QCOMPARE(loader.failed(), 0);
    QCOMPARE(completed.count(), 0);

    loader.handleMatchCardCacheFinished(14, currentGeneration, u"zh|lightning bolt|M11|149"_s,
                                        u"Lightning Bolt"_s, u"M11"_s, u"149"_s, false, true);
    QCOMPARE(completed.count(), 1);
}

void TestMatchLoadCoordinator::exactArtModesCannotCrossSettle() const
{
    MatchLoadCoordinator loader;
    QSignalSpy expansions(&loader, &MatchLoadCoordinator::cardFaceExpansionRequested);
    QSignalSpy completed(&loader, &MatchLoadCoordinator::loadComplete);
    const QVariantMap normal = cardRequests().first().toMap();
    QVariantMap exact = normal;
    exact.insert(u"exactArt"_s, true);

    loader.preparePreload(15, {normal, exact});
    QTRY_COMPARE_WITH_TIMEOUT(expansions.count(), 1, 1'000);
    const quint64 generation = expansions.first().at(1).toULongLong();
    loader.adoptExpandedCards(15, generation, {normal, exact});
    QCOMPARE(loader.total(), 2);

    loader.handleMatchCardCacheFinished(15, generation, u"en|lightning bolt|M11|149"_s,
                                        u"Lightning Bolt"_s, u"M11"_s, u"149"_s, false, true);
    QCOMPARE(loader.completed(), 1);
    QCOMPARE(completed.count(), 0);
    loader.handleMatchCardCacheFinished(15, generation, u"en|lightning bolt|M11|149|exact-art"_s,
                                        u"Lightning Bolt"_s, u"M11"_s, u"149"_s, true, true);
    QCOMPARE(completed.count(), 1);
}

void TestMatchLoadCoordinator::retriesOnlyFailedCards() const
{
    MatchLoadCoordinator loader;
    QSignalSpy expansions(&loader, &MatchLoadCoordinator::cardFaceExpansionRequested);
    QSignalSpy requests(&loader, &MatchLoadCoordinator::cardsRequested);
    QSignalSpy retries(&loader, &MatchLoadCoordinator::cardsRetryRequested);
    QSignalSpy completed(&loader, &MatchLoadCoordinator::loadComplete);

    loader.preparePreload(14, cardRequests());
    QTRY_COMPARE_WITH_TIMEOUT(expansions.count(), 1, 1'000);
    const quint64 generation = expansions.first().at(1).toULongLong();
    loader.adoptExpandedCards(14, generation, cardRequests());
    QCOMPARE(requests.count(), 1);
    loader.handleMatchCardCacheFinished(14, generation, u"en|lightning bolt|M11|149"_s,
                                        u"Lightning Bolt"_s, u"M11"_s, u"149"_s, false, true);
    loader.handleMatchCardCacheFinished(14, generation, u"en|sol ring|CMM|396"_s, u"Sol Ring"_s,
                                        u"CMM"_s, u"396"_s, false, false);
    QCOMPARE(loader.failed(), 1);
    QVERIFY(!loader.lastError().isEmpty());
    QCOMPARE(completed.count(), 0);

    loader.retry();
    QCOMPARE(requests.count(), 1);
    QCOMPARE(retries.count(), 1);
    const QVariantList retried = retries.first().at(2).toList();
    QCOMPARE(retried.size(), 1);
    QCOMPARE(retried.first().toMap().value(u"name"_s).toString(), u"Sol Ring"_s);
    loader.handleMatchCardCacheFinished(14, generation, u"en|sol ring|CMM|396"_s, u"Sol Ring"_s,
                                        u"CMM"_s, u"396"_s, false, true);
    QCOMPARE(completed.count(), 1);
    QVERIFY(loader.ready());
}

void TestMatchLoadCoordinator::cancelIgnoresLateResults() const
{
    MatchLoadCoordinator loader;
    QSignalSpy completed(&loader, &MatchLoadCoordinator::loadComplete);
    loader.preparePreload(15, cardRequests());
    loader.cancel();
    loader.handleMatchCardCacheFinished(15, 1, u"en|lightning bolt|M11|149"_s, u"Lightning Bolt"_s,
                                        u"M11"_s, u"149"_s, false, true);
    QCOMPARE(loader.loadId(), 0);
    QCOMPARE(completed.count(), 0);
    QVERIFY(!loader.active());
}

namespace {

struct CacheRuntime
{
    hexproof::client::GameTableModel table;
    hexproof::client::RulesSessionState rules;
    hexproof::client::RoomSessionState room;
    MatchLoadCoordinator loader;
    hexproof::client::MatchCardCacheBinding binding{&table, &rules, &room, &loader};

    void enter(const QString &mode, const QString &role = u"player"_s)
    {
        room.enter(u"room-1"_s, role, role == u"player"_s ? 0 : -1, false);
        room.applySnapshot({{u"rulesMode"_s, mode}, {u"phase"_s, u"started"_s}});
        binding.setInRoom(true);
    }
};

QJsonObject rulesSnapshot(const QJsonArray &zones = {}, const QJsonArray &stack = {})
{
    return {{u"roomId"_s, u"room-1"_s},
            {u"gameId"_s, u"rules-game-1"_s},
            {u"players"_s, QJsonArray{}},
            {u"zones"_s, zones},
            {u"stack"_s, stack}};
}

QJsonObject projectedCard(const QString &id, const QString &name, bool visible = true)
{
    return {{u"id"_s, id},
            {u"visible"_s, visible},
            {u"identity"_s, QJsonObject{{u"name"_s, name},
                                        {u"setCode"_s, u"m11"_s},
                                        {u"collectorNumber"_s, u"149"_s}}}};
}

QJsonObject cardZone(const QString &zone, const QJsonArray &cards)
{
    return {
        {u"zone"_s, zone}, {u"ownerSeat"_s, 0}, {u"count"_s, cards.size()}, {u"cards"_s, cards}};
}

} // namespace

void TestMatchLoadCoordinator::runtimeBindingWaitsForTheSelectedMode() const
{
    CacheRuntime runtime;
    runtime.enter(u"forge"_s);
    QSignalSpy expansions(&runtime.loader, &MatchLoadCoordinator::cardFaceExpansionRequested);
    // An unrelated manual snapshot must not unlock a Forge background load.
    runtime.table.applySnapshot({{u"gameId"_s, u"manual-old"_s}});
    runtime.loader.prepareBackground(20, cardRequests());
    QTest::qWait(20);
    QCOMPARE(expansions.count(), 0);
    runtime.table.clear();
    QVERIFY(runtime.rules.applySnapshot(rulesSnapshot()));
    QVERIFY(!runtime.table.hasSnapshot());
    QCOMPARE(expansions.count(), 0);
    QTRY_COMPARE_WITH_TIMEOUT(expansions.count(), 1, 1'000);

    // Snapshot-before-load and manual model resets keep Forge readiness intact.
    runtime.loader.cancel();
    runtime.table.clear();
    runtime.loader.prepareBackground(21, cardRequests());
    QTRY_COMPARE_WITH_TIMEOUT(expansions.count(), 2, 1'000);
    runtime.rules.clear();
    runtime.loader.cancel();
    runtime.loader.prepareBackground(22, cardRequests());
    QTest::qWait(20);
    QCOMPARE(expansions.count(), 2);

    // In manual mode, an old Forge snapshot is equally irrelevant.
    runtime.binding.setInRoom(false);
    runtime.enter(u"manual"_s);
    QVERIFY(runtime.rules.applySnapshot(rulesSnapshot()));
    runtime.loader.prepareBackground(23, cardRequests());
    QTest::qWait(20);
    QCOMPARE(expansions.count(), 2);
    runtime.table.applySnapshot({{u"gameId"_s, u"manual-new"_s}});
    QTRY_COMPARE_WITH_TIMEOUT(expansions.count(), 3, 1'000);
}

void TestMatchLoadCoordinator::runtimeBindingCancelsQueuedWorkOnLeave() const
{
    CacheRuntime runtime;
    runtime.enter(u"forge"_s);
    QSignalSpy expansions(&runtime.loader, &MatchLoadCoordinator::cardFaceExpansionRequested);
    QSignalSpy visible(&runtime.binding,
                       &hexproof::client::MatchCardCacheBinding::visibleRulesCardsRequested);
    runtime.loader.prepareBackground(24, cardRequests());
    QVERIFY(runtime.rules.applySnapshot(
        rulesSnapshot({cardZone(u"hand"_s, {projectedCard(u"c1"_s, u"Lightning Bolt"_s)})})));
    runtime.binding.setInRoom(false);
    // A late projection or preference signal cannot restart a departed room.
    QVERIFY(runtime.rules.applySnapshot(
        rulesSnapshot({cardZone(u"battlefield"_s, {projectedCard(u"c2"_s, u"Sol Ring"_s)})})));
    runtime.binding.refreshVisibleCards();
    QTest::qWait(20);
    QCOMPARE(expansions.count(), 0);
    QCOMPARE(visible.count(), 0);
    QVERIFY(!runtime.loader.active());
    QCOMPARE(runtime.loader.loadId(), 0);

    runtime.rules.clear();
    runtime.room.clear();
    runtime.enter(u"forge"_s);
    runtime.loader.prepareBackground(25, cardRequests());
    QJsonObject foreignSnapshot = rulesSnapshot();
    foreignSnapshot.insert(u"roomId"_s, u"other-room"_s);
    QVERIFY(runtime.rules.applySnapshot(foreignSnapshot));
    QTest::qWait(20);
    QCOMPARE(expansions.count(), 0);
    QVERIFY(runtime.rules.applySnapshot(rulesSnapshot()));
    QTRY_COMPARE_WITH_TIMEOUT(expansions.count(), 1, 1'000);
    QCOMPARE(expansions.first().at(0).toLongLong(), 25);
}

void TestMatchLoadCoordinator::spectatorVisibleCardsUseIndependentAuthorizedBatch() const
{
    CacheRuntime runtime;
    runtime.enter(u"forge"_s, u"spectator"_s);
    QSignalSpy visible(&runtime.binding,
                       &hexproof::client::MatchCardCacheBinding::visibleRulesCardsRequested);
    const QJsonObject bolt = projectedCard(u"c1"_s, u"Lightning Bolt"_s);
    const QJsonObject hidden = projectedCard(u"c2"_s, u"Hidden hand identity"_s, false);
    const QJsonObject stack{{u"id"_s, u"stack-1"_s},
                            {u"text"_s, u"Never infer this text"_s},
                            {u"identity"_s, bolt.value(u"identity"_s)}};
    const QJsonObject snapshot = rulesSnapshot(
        {cardZone(u"hand"_s, {hidden}), cardZone(u"battlefield"_s, {bolt, hidden}),
         cardZone(u"library"_s, {projectedCard(u"library-1"_s, u"Not displayed"_s)})},
        {stack, QJsonObject{{u"id"_s, u"unknown-stack"_s}, {u"text"_s, u"Sol Ring"_s}}});
    QVERIFY(runtime.rules.applySnapshot(snapshot));
    QVERIFY(runtime.rules.applySnapshot(snapshot));
    QCOMPARE(visible.count(), 0);
    QTRY_COMPARE_WITH_TIMEOUT(visible.count(), 1, 1'000);
    QCOMPARE(visible.first().first().toList(), QVariantList{cardRequests().first()});
    QVERIFY(!runtime.loader.active());
    QCOMPARE(runtime.loader.loadId(), 0); // Spectators have no deck load subscription.
    QVERIFY(!runtime.table.hasSnapshot());

    QVERIFY(runtime.rules.applySnapshot(snapshot));
    QTest::qWait(20);
    QCOMPARE(visible.count(), 1);
    QJsonObject token = projectedCard(u"token-1"_s, u"Spirit"_s);
    QJsonObject tokenIdentity{{u"name"_s, u"Spirit"_s},
                              {u"setCode"_s, u"tsoi"_s},
                              {u"collectorNumber"_s, u"4"_s},
                              {u"token"_s, true}};
    token.insert(u"identity"_s, tokenIdentity);
    QVERIFY(
        runtime.rules.applySnapshot(rulesSnapshot({cardZone(u"battlefield"_s, {bolt, token})})));
    QTRY_COMPARE_WITH_TIMEOUT(visible.count(), 2, 1'000);
    const QVariantList requests = visible.last().first().toList();
    QCOMPARE(requests.size(), 2);
    QCOMPARE(requests.at(1).toMap(), (QVariantMap{{u"name"_s, u"Spirit"_s},
                                                  {u"setCode"_s, u"TSOI"_s},
                                                  {u"collectorNumber"_s, u"4"_s}}));
}

void TestMatchLoadCoordinator::promptCardsAndPreferenceRefreshAreCoalesced() const
{
    CacheRuntime runtime;
    runtime.enter(u"forge"_s);
    QSignalSpy visible(&runtime.binding,
                       &hexproof::client::MatchCardCacheBinding::visibleRulesCardsRequested);
    QVERIFY(runtime.rules.applySnapshot(rulesSnapshot()));
    QJsonObject prompt{
        {u"totalDamage"_s, 0}, {u"roomId"_s, u"room-1"_s}, {u"gameId"_s, u"rules-game-1"_s},
        {u"pending"_s, true},  {u"promptId"_s, 1},         {u"kind"_s, u"chooseCards"_s}};
    for (const QString &key : {u"options"_s, u"choices"_s, u"cards"_s, u"scryDestinations"_s,
                               u"targets"_s, u"contextCards"_s, u"contextTargets"_s,
                               u"combatSources"_s, u"combatTargets"_s, u"damageTargets"_s})
        prompt.insert(key, QJsonArray{});
    QJsonObject card = QJsonObject::fromVariantMap(cardRequests().first().toMap());
    card.insert(u"id"_s, u"card:1"_s);
    prompt.insert(u"cards"_s, QJsonArray{card, QJsonObject{{u"id"_s, u"hidden-card"_s}}});
    QVERIFY(runtime.rules.applyPrompt(prompt));
    runtime.binding.refreshVisibleCards();
    runtime.binding.refreshVisibleCards();
    QTRY_COMPARE_WITH_TIMEOUT(visible.count(), 1, 1'000);
    QCOMPARE(visible.first().first().toList(), QVariantList{cardRequests().first()});
    runtime.binding.refreshVisibleCards();
    QTRY_COMPARE_WITH_TIMEOUT(visible.count(), 2, 1'000);

    prompt.insert(u"pending"_s, false);
    QVERIFY(runtime.rules.applyPrompt(prompt));
    runtime.binding.refreshVisibleCards();
    QTest::qWait(20);
    QCOMPARE(visible.count(), 2);
    QVERIFY(runtime.rules.applyPrompt(QJsonObject(prompt)));
    runtime.binding.setInRoom(false);
    runtime.binding.refreshVisibleCards();
    QTest::qWait(20);
    QCOMPARE(visible.count(), 2);
}

QTEST_GUILESS_MAIN(TestMatchLoadCoordinator)
#include "matchload_test.moc"
