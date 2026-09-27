// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "services/DraftSimulator.h"

#include <QSet>
#include <QtTest>

using namespace hexproof::client;
using namespace Qt::StringLiterals;

namespace {
QVariantMap product(int cards = 15)
{
    return {{u"name"_s, u"Practice set"_s},
            {u"productType"_s, u"booster"_s},
            {u"cardsPerPack"_s, cards},
            {u"authentic"_s, true}};
}

QVariantList generate(const QVariantMap &definition, int count)
{
    QVariantList packs;
    for (int pack = 0; pack < count; ++pack) {
        QVariantList cards;
        for (int index = 0; index < definition.value(u"cardsPerPack"_s).toInt(); ++index)
            cards.append(QVariantMap{{u"name"_s, u"Pack %1 card %2"_s.arg(pack).arg(index)},
                                     {u"setCode"_s, u"TST"_s},
                                     {u"collectorNumber"_s, QString::number(index)},
                                     {u"rarity"_s, u"common"_s},
                                     {u"cardColors"_s, u"U"_s}});
        packs.append(QVariantMap{{u"cards"_s, cards}});
    }
    return packs;
}

QString firstId(DraftSimulator &simulator)
{
    return simulator.state()->currentPack().first().toMap().value(u"instanceId"_s).toString();
}

void finish(DraftSimulator &simulator)
{
    for (int count = 0; count < 90 && simulator.state()->stage() == u"draft"; ++count)
        QVERIFY(simulator.pick(firstId(simulator)));
    QCOMPARE(simulator.state()->stage(), u"deck_building"_s);
}
} // namespace

class DraftSimulatorTest : public QObject
{
    Q_OBJECT
  private slots:
    void completePod_data()
    {
        QTest::addColumn<int>("seats");
        QTest::addColumn<int>("cards");
        QTest::newRow("two-seat-draft") << 2 << 15;
        QTest::newRow("odd-pod-play") << 3 << 14;
        QTest::newRow("full-pod") << 8 << 15;
        QTest::newRow("maximum-pack") << 8 << 30;
    }

    void completePod()
    {
        QFETCH(int, seats);
        QFETCH(int, cards);
        DraftSimulator simulator;
        simulator.setPackGenerator(generate);
        QVERIFY(simulator.start(product(cards), seats));
        auto *state = simulator.state();
        QSet<QString> picked;
        for (int round = 1; round <= 3; ++round) {
            QCOMPARE(state->packRound(), round);
            QCOMPARE(state->direction(), round == 2 ? -1 : 1);
            for (int pick = 0; pick < cards; ++pick) {
                QCOMPARE(state->stage(), u"draft"_s);
                QCOMPARE(state->currentPack().size(), cards - pick);
                const int sourceSeat = ((round == 2 ? pick : -pick) % seats + seats) % seats;
                const QString prefix = u"Pack %1 card "_s.arg((round - 1) * seats + sourceSeat);
                for (const auto &card : state->currentPack())
                    QVERIFY(card.toMap().value(u"name"_s).toString().startsWith(prefix));
                const QString id = firstId(simulator);
                QVERIFY(!picked.contains(id));
                picked.insert(id);
                QVERIFY(simulator.pick(id));
                QCOMPARE(state->pool().size(), picked.size());
                for (const auto &value : state->participants()) {
                    const QVariantMap participant = value.toMap();
                    QCOMPARE(participant.value(u"poolCount"_s).toInt(), picked.size());
                    QVERIFY(!participant.contains(u"pool"_s));
                    QVERIFY(!participant.contains(u"currentPack"_s));
                }
            }
        }
        QCOMPARE(state->stage(), u"deck_building"_s);
        QVERIFY(state->currentPack().isEmpty());
        QCOMPARE(state->pool().size(), cards * 3);
        QVERIFY(!simulator.pick(*picked.cbegin()));
    }

    void invalidActionsPreserveSession()
    {
        DraftSimulator simulator;
        simulator.setPackGenerator(generate);
        QVERIFY(!simulator.start(product(), 1));
        QVERIFY(!simulator.start(product(), 9));
        QVERIFY(!simulator.state()->active());
        QVERIFY(simulator.start(product(), 2));
        const QString id = firstId(simulator);
        QVERIFY(simulator.pick(id));
        const auto pack = simulator.state()->currentPack();
        QVERIFY(!simulator.pick(id));
        QCOMPARE(simulator.state()->pool().size(), 1);
        QCOMPARE(simulator.state()->currentPack(), pack);
        simulator.setPackGenerator([](const QVariantMap &, int) { return QVariantList{}; });
        QVERIFY(!simulator.start(product(), 2));
        QCOMPARE(simulator.state()->currentPack(), pack);
        simulator.setPackGenerator(generate);
        QVERIFY(simulator.start(product(), 2));
        QVERIFY(firstId(simulator) != id);
        QVERIFY(simulator.lastError().isEmpty());
        simulator.reset();
        QVERIFY(!simulator.state()->active());
        QVERIFY(simulator.state()->pool().isEmpty());
        QVERIFY(!simulator.pick(id));
    }

    void cubeGeneratesWholeStockAtOnce()
    {
        DraftSimulator simulator;
        int calls = 0;
        simulator.setPackGenerator([&](const QVariantMap &definition, int count) {
            ++calls;
            if (definition.value(u"cardsPerPack"_s).toInt() != 15 || count != 24)
                return QVariantList{};
            return generate(definition, count);
        });
        QVariantMap cube = product(0);
        cube.insert(u"productType"_s, u"cube"_s);
        QVERIFY(simulator.start(cube, 8));
        finish(simulator);
        QCOMPARE(calls, 1);
        QCOMPARE(simulator.state()->eventType(), u"cube_draft"_s);
    }

    void rejectsShortPacks()
    {
        DraftSimulator simulator;
        simulator.setPackGenerator(
            [](const QVariantMap &, int count) { return generate(product(14), count); });
        QVERIFY(!simulator.start(product(15), 8));
        QVERIFY(!simulator.state()->active());
    }

    void botsPreferPlayableCardsToBasicLands()
    {
        DraftSimulator simulator;
        simulator.setPackGenerator([](const QVariantMap &, int count) {
            QVariantList packs;
            for (int i = 0; i < count; ++i)
                packs.append(QVariantMap{
                    {u"cards"_s, QVariantList{QVariantMap{{u"name"_s, u"Basic land"_s},
                                                          {u"typeLine"_s, u"Basic Land"_s}},
                                              QVariantMap{{u"name"_s, u"Rare creature"_s},
                                                          {u"rarity"_s, u"rare"_s}}}}});
            return packs;
        });
        QVERIFY(simulator.start(product(2), 2));
        QVERIFY(simulator.pick(firstId(simulator)));
        QCOMPARE(simulator.state()->currentPack().size(), 1);
        QCOMPARE(simulator.state()->currentPack().first().toMap().value(u"name"_s).toString(),
                 u"Basic land"_s);
    }

    void savesOnlyOwnedCardsAndOrdinaryBasics()
    {
        DraftSimulator simulator;
        simulator.setPackGenerator(generate);
        QVariantMap saved;
        int saves = 0;
        simulator.setDeckSaver([&](const QString &, const QVariantMap &deck) {
            ++saves;
            saved = deck;
            return QString{};
        });
        QVERIFY(simulator.start(product(), 8));
        QVERIFY(!simulator.saveDeck(u"Test"_s, {}, {}));
        finish(simulator);
        const auto pool = simulator.state()->pool();
        QVariantList ids;
        for (int index = 0; index < 23; ++index)
            ids.append(pool.at(index).toMap().value(u"instanceId"_s));
        const QVariantList basics{QVariantMap{{u"name"_s, u"Island"_s},
                                              {u"count"_s, 17},
                                              {u"setCode"_s, u"M21"_s},
                                              {u"collectorNumber"_s, u"263"_s}}};
        QVERIFY(!simulator.saveDeck(u"Test"_s, ids, {}));
        QVERIFY(!simulator.saveDeck(u"Test"_s, {u"other-seat-card"_s}, basics));
        QVERIFY(!simulator.saveDeck(u"Test"_s, {ids.first(), ids.first()}, basics));
        QVERIFY(!simulator.saveDeck(u"Test"_s, ids,
                                    {QVariantMap{{u"name"_s, u"Wastes"_s}, {u"count"_s, 17}}}));
        QCOMPARE(saves, 0);
        QVERIFY(simulator.saveDeck(u"Test"_s, ids, basics));
        QCOMPARE(saves, 1);
        QCOMPARE(saved.value(u"mainboard"_s).toList().size(), 24);
        QCOMPARE(saved.value(u"sideboard"_s).toList().size(), 22);
        QCOMPARE(saved.value(u"mainboard"_s).toList().last(), basics.first());
        QCOMPARE(simulator.state()->mainboardInstanceIds(), ids);
        QCOMPARE(simulator.state()->basicLands(), basics);
        QVERIFY(simulator.state()->deckSubmitted());
        QCOMPARE(simulator.state()->stage(), u"deck_building"_s);
        simulator.setDeckSaver([](const QString &, const QVariantMap &) { return u"disk full"_s; });
        QVERIFY(!simulator.saveDeck(u"Test"_s, {},
                                    {QVariantMap{{u"name"_s, u"Island"_s}, {u"count"_s, 40}}}));
        QCOMPARE(simulator.state()->mainboardInstanceIds(), ids);
        QCOMPARE(simulator.lastError(), u"disk full"_s);
    }
};

QTEST_GUILESS_MAIN(DraftSimulatorTest)
#include "draftsimulator_test.moc"
