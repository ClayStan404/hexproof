// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "models/SideboardTableModel.h"

#include <QSignalSpy>
#include <QTest>

using namespace Qt::StringLiterals;
using hexproof::client::SideboardTableModel;

class TestSideboardTableModel : public QObject
{
    Q_OBJECT

  private slots:
    void groupsBilingualTypesAndStacksPrintings() const;
    void separatesVirtualBasicsFromPoolPrintings() const;
    void skipsEquivalentSnapshots() const;
    void benchmarkCommanderDeckGrouping() const;
};

void TestSideboardTableModel::groupsBilingualTypesAndStacksPrintings() const
{
    SideboardTableModel model;
    model.setMainboardCards(QVariantList{
        QVariantMap{
            {u"name"_s, u"Lightning Bolt"_s},
            {u"count"_s, 2},
            {u"setCode"_s, u"M11"_s},
            {u"collectorNumber"_s, u"149"_s},
            {u"typeLine"_s, u"瞬间"_s},
        },
        QVariantMap{
            {u"name"_s, u"Lightning Bolt"_s},
            {u"count"_s, 1},
            {u"setCode"_s, u"2X2"_s},
            {u"collectorNumber"_s, u"117"_s},
            {u"typeLine"_s, u"Instant"_s},
        },
        QVariantMap{
            {u"name"_s, u"Mountain"_s},
            {u"count"_s, 4},
            {u"typeLine"_s, u"基本地 — 山脉"_s},
        },
        QVariantMap{
            {u"name"_s, u"Walking Ballista"_s},
            {u"count"_s, 1},
            {u"typeLine"_s, u"Artifact Creature — Construct"_s},
        },
    });

    QCOMPARE(model.mainboardCount(), 8);
    const QVariantList groups = model.mainboardGroups();
    QCOMPARE(groups.size(), 3);
    QCOMPARE(groups[0].toMap().value(u"category"_s).toString(), u"Creature"_s);
    QCOMPARE(groups[1].toMap().value(u"category"_s).toString(), u"Instant"_s);
    const QVariantList instantCards = groups[1].toMap().value(u"cards"_s).toList();
    QCOMPARE(instantCards.size(), 1);
    QCOMPARE(instantCards[0].toMap().value(u"pileCount"_s).toInt(), 3);
    QCOMPARE(groups[2].toMap().value(u"category"_s).toString(), u"Land"_s);
    QCOMPARE(model.cardCategory(u"生物 ～ 地精"_s), u"Creature"_s);
}

void TestSideboardTableModel::separatesVirtualBasicsFromPoolPrintings() const
{
    SideboardTableModel model;
    model.setMainboardCards(QVariantList{
        QVariantMap{
            {u"name"_s, u"Island"_s},
            {u"count"_s, 17},
            {u"typeLine"_s, u"Basic Land"_s},
        },
        QVariantMap{
            {u"name"_s, u"Island"_s},
            {u"count"_s, 1},
            {u"setCode"_s, u"TST"_s},
            {u"collectorNumber"_s, u"2"_s},
            {u"typeLine"_s, u"Basic Land — Island"_s},
        },
    });

    QCOMPARE(model.mainboardCount(), 18);
    const QVariantList groups = model.mainboardGroups();
    QCOMPARE(groups.size(), 1);
    const QVariantList cards = groups.first().toMap().value(u"cards"_s).toList();
    QCOMPARE(cards.size(), 2);
    QVERIFY(cards[0].toMap().value(u"virtualCard"_s).toBool() !=
            cards[1].toMap().value(u"virtualCard"_s).toBool());
}

void TestSideboardTableModel::skipsEquivalentSnapshots() const
{
    SideboardTableModel model;
    QSignalSpy changed(&model, &SideboardTableModel::mainboardChanged);
    const QVariantList cards{QVariantMap{
        {u"name"_s, u"Sol Ring"_s},
        {u"count"_s, 1},
        {u"typeLine"_s, u"Artifact"_s},
    }};
    model.setMainboardCards(cards);
    model.setMainboardCards(cards);
    QCOMPARE(changed.count(), 1);
}

void TestSideboardTableModel::benchmarkCommanderDeckGrouping() const
{
    QVariantList cards;
    cards.reserve(100);
    const QStringList types{
        u"Artifact"_s, u"Creature — Human"_s, u"Enchantment"_s, u"Instant"_s,
        u"Land"_s,     u"Planeswalker"_s,     u"Sorcery"_s,
    };
    for (int index = 0; index < 100; ++index) {
        cards.append(QVariantMap{
            {u"name"_s, u"Card %1"_s.arg(index)},
            {u"count"_s, 1},
            {u"setCode"_s, u"TST"_s},
            {u"collectorNumber"_s, QString::number(index + 1)},
            {u"typeLine"_s, types[index % types.size()]},
        });
    }

    SideboardTableModel model;
    int revision = 0;
    QBENCHMARK
    {
        QVariantList snapshot = cards;
        QVariantMap last = snapshot.last().toMap();
        last.insert(u"collectorNumber"_s, QString::number(++revision));
        snapshot.last() = last;
        model.setMainboardCards(snapshot);
    }
    QCOMPARE(model.mainboardCount(), 100);
}

QTEST_MAIN(TestSideboardTableModel)

#include "sideboardtablemodel_test.moc"
