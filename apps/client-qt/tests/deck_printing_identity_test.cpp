// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "deck_test.h"

#include "models/DeckLibraryModel.h"

#include <QSignalSpy>
#include <QTemporaryDir>
#include <QTest>

using namespace Qt::StringLiterals;
using hexproof::client::DeckLibraryModel;

namespace {

bool changePrintingCount(DeckLibraryModel &model, const QString &name, const QString &setCode,
                         const QString &collectorNumber, bool sideboard, int delta)
{
    bool result = false;
    const bool invoked = QMetaObject::invokeMethod(
        &model, "changeCardCount", Qt::DirectConnection, Q_RETURN_ARG(bool, result),
        Q_ARG(QString, name), Q_ARG(QString, setCode), Q_ARG(QString, collectorNumber),
        Q_ARG(bool, sideboard), Q_ARG(int, delta));
    return invoked && result;
}

bool movePrinting(DeckLibraryModel &model, const QString &name, const QString &setCode,
                  const QString &collectorNumber, bool toSideboard)
{
    bool result = false;
    const bool invoked = QMetaObject::invokeMethod(
        &model, "moveCard", Qt::DirectConnection, Q_RETURN_ARG(bool, result), Q_ARG(QString, name),
        Q_ARG(QString, setCode), Q_ARG(QString, collectorNumber), Q_ARG(bool, toSideboard));
    return invoked && result;
}

bool changePrinting(DeckLibraryModel &model, const QString &name, const QString &currentSetCode,
                    const QString &currentCollectorNumber, bool sideboard,
                    const QString &localizedName, const QString &typeLine,
                    const QString &newSetCode, const QString &newCollectorNumber)
{
    bool result = false;
    const bool invoked = QMetaObject::invokeMethod(
        &model, "setCardPrinting", Qt::DirectConnection, Q_RETURN_ARG(bool, result),
        Q_ARG(QString, name), Q_ARG(QString, currentSetCode),
        Q_ARG(QString, currentCollectorNumber), Q_ARG(bool, sideboard),
        Q_ARG(QString, localizedName), Q_ARG(QString, typeLine), Q_ARG(QString, newSetCode),
        Q_ARG(QString, newCollectorNumber));
    return invoked && result;
}

QVariantMap cardWithPrinting(const QVariantList &cards, const QString &setCode,
                             const QString &collectorNumber)
{
    for (const QVariant &value : cards) {
        const QVariantMap card = value.toMap();
        if (card.value(u"setCode"_s).toString() == setCode &&
            card.value(u"collectorNumber"_s).toString() == collectorNumber) {
            return card;
        }
    }
    return {};
}

} // namespace

void TestDeckLibrary::targetsExactPrintingForCountsMovesAndPrintingChanges() const
{
    QTemporaryDir storage;
    QVERIFY(storage.isValid());
    DeckLibraryModel model(storage.path());
    QVERIFY(model.importDeck(u"Printing edits"_s, u"modern"_s,
                             u"Deck\n"
                             "1 Lightning Bolt (M11) 149\n"
                             "1 Lightning Bolt (2X2) 117\n"_s));
    const QString id = model.data(model.index(0), DeckLibraryModel::IdRole).toString();
    QVERIFY(model.openDeck(id));

    QVERIFY(changePrintingCount(model, u"Lightning Bolt"_s, u"2x2"_s, u"117"_s, false, 1));
    QCOMPARE(cardWithPrinting(model.mainCards(), u"M11"_s, u"149"_s).value(u"count"_s).toInt(), 1);
    QCOMPARE(cardWithPrinting(model.mainCards(), u"2X2"_s, u"117"_s).value(u"count"_s).toInt(), 2);
    QVERIFY(changePrintingCount(model, u"Lightning Bolt"_s, u"2X2"_s, u"117"_s, false, -1));

    QVERIFY(movePrinting(model, u"Lightning Bolt"_s, u"M11"_s, u"149"_s, true));
    QCOMPARE(model.mainCards().size(), 1);
    QCOMPARE(cardWithPrinting(model.mainCards(), u"2X2"_s, u"117"_s).value(u"count"_s).toInt(), 1);
    QCOMPARE(cardWithPrinting(model.sideboardCards(), u"M11"_s, u"149"_s).value(u"count"_s).toInt(),
             1);
    QVERIFY(movePrinting(model, u"Lightning Bolt"_s, u"M11"_s, u"149"_s, false));
    QCOMPARE(model.mainCards().size(), 2);
    QVERIFY(cardWithPrinting(model.mainCards(), u"M11"_s, u"149"_s).size() > 0);

    QSignalSpy cachingSpy(&model, &DeckLibraryModel::cardsNeedCaching);
    QVERIFY(changePrinting(model, u"Lightning Bolt"_s, u"2X2"_s, u"117"_s, false, u"闪电击"_s,
                           u"Instant"_s, u"CLB"_s, u"401"_s));
    QCOMPARE(cardWithPrinting(model.mainCards(), u"M11"_s, u"149"_s).value(u"count"_s).toInt(), 1);
    const QVariantMap changed = cardWithPrinting(model.mainCards(), u"CLB"_s, u"401"_s);
    QCOMPARE(changed.value(u"displayName"_s).toString(), u"闪电击"_s);
    QCOMPARE(cachingSpy.count(), 1);
    const QVariantMap request = cachingSpy.constFirst().constFirst().toList().constFirst().toMap();
    QCOMPARE(request.value(u"setCode"_s).toString(), u"CLB"_s);
    QCOMPARE(request.value(u"collectorNumber"_s).toString(), u"401"_s);
    QVERIFY(request.value(u"exactArt"_s).toBool());
    QCOMPARE(model.currentCardCopies(u"Lightning Bolt"_s), 2);
}

void TestDeckLibrary::mergesCountsWhenChangingToExistingPrinting() const
{
    QTemporaryDir storage;
    QVERIFY(storage.isValid());
    DeckLibraryModel model(storage.path());
    QVERIFY(model.importDeck(u"Printing merge"_s, u"modern"_s,
                             u"Deck\n"
                             "2 Lightning Bolt (M11) 149\n"
                             "3 Lightning Bolt (2X2) 117\n"_s));
    const QString id = model.data(model.index(0), DeckLibraryModel::IdRole).toString();
    QVERIFY(model.openDeck(id));
    QSignalSpy cachingSpy(&model, &DeckLibraryModel::cardsNeedCaching);

    QVERIFY(changePrinting(model, u"Lightning Bolt"_s, u"2X2"_s, u"117"_s, false, u"闪电击"_s,
                           u"Instant — chosen metadata"_s, u"M11"_s, u"149"_s));

    QCOMPARE(model.mainCards().size(), 1);
    const QVariantMap merged = cardWithPrinting(model.mainCards(), u"M11"_s, u"149"_s);
    QCOMPARE(merged.value(u"count"_s).toInt(), 5);
    QCOMPARE(merged.value(u"displayName"_s).toString(), u"闪电击"_s);
    QCOMPARE(merged.value(u"typeLine"_s).toString(), u"Instant — chosen metadata"_s);
    QCOMPARE(model.currentCardCopies(u"Lightning Bolt"_s), 5);
    QCOMPARE(cachingSpy.count(), 1);
    const QVariantMap request = cachingSpy.constFirst().constFirst().toList().constFirst().toMap();
    QCOMPARE(request.value(u"setCode"_s).toString(), u"M11"_s);
    QCOMPARE(request.value(u"collectorNumber"_s).toString(), u"149"_s);
    QVERIFY(request.value(u"exactArt"_s).toBool());
}

void TestDeckLibrary::keepsDistinctPrintingsAcrossAddAndConsiderMoves() const
{
    QTemporaryDir storage;
    QVERIFY(storage.isValid());
    DeckLibraryModel model(storage.path());
    QVERIFY(model.importDeck(u"Printing zones"_s, u"modern"_s,
                             u"Deck\n"
                             "1 Lightning Bolt (2X2) 117\n"
                             "Consider\n"
                             "1 Lightning Bolt (M11) 149\n"_s));
    const QString id = model.data(model.index(0), DeckLibraryModel::IdRole).toString();
    QVERIFY(model.openDeck(id));

    QVERIFY(model.moveConsiderCardToMain(u"Lightning Bolt"_s, u"M11"_s, u"149"_s));
    QCOMPARE(model.mainCards().size(), 2);
    QVERIFY(cardWithPrinting(model.mainCards(), u"M11"_s, u"149"_s).size() > 0);
    QVERIFY(cardWithPrinting(model.mainCards(), u"2X2"_s, u"117"_s).size() > 0);
    QVERIFY(model.moveCardToConsider(u"Lightning Bolt"_s, u"M11"_s, u"149"_s));
    QCOMPARE(model.mainCards().size(), 1);
    QCOMPARE(cardWithPrinting(model.mainCards(), u"2X2"_s, u"117"_s).value(u"count"_s).toInt(), 1);
    QCOMPARE(cardWithPrinting(model.considerCards(), u"M11"_s, u"149"_s).value(u"count"_s).toInt(),
             1);

    QVERIFY(model.addCard(u"Lightning Bolt"_s, {}, u"Instant"_s, u"STA"_s, u"42"_s, false));
    QCOMPARE(model.mainCards().size(), 2);
    QVERIFY(model.addCard(u"Lightning Bolt"_s, {}, u"Instant"_s, u"sta"_s, u"42"_s, false));
    QCOMPARE(model.mainCards().size(), 2);
    QCOMPARE(cardWithPrinting(model.mainCards(), u"STA"_s, u"42"_s).value(u"count"_s).toInt(), 2);
}

void TestDeckLibrary::keepsNameOnlyRowsNameKeyedAndDfcAliasesEditable() const
{
    QTemporaryDir storage;
    QVERIFY(storage.isValid());
    DeckLibraryModel model(storage.path());
    QVERIFY(model.importDeck(u"Legacy identities"_s, u"modern"_s,
                             u"Deck\n"
                             "1 Lightning Bolt\n"
                             "1 Delver of Secrets (MID) 47\n"_s));
    const QString id = model.data(model.index(0), DeckLibraryModel::IdRole).toString();
    QVERIFY(model.openDeck(id));

    QVERIFY(model.addCard(u"Lightning Bolt"_s, {}, u"Instant"_s, {}, {}, false));
    QCOMPARE(cardWithPrinting(model.mainCards(), {}, {}).value(u"count"_s).toInt(), 2);
    QVERIFY(model.addCard(u"Lightning Bolt"_s, {}, u"Instant"_s, u"M11"_s, u"149"_s, false));
    QCOMPARE(model.mainCards().size(), 3);
    QCOMPARE(cardWithPrinting(model.mainCards(), {}, {}).value(u"count"_s).toInt(), 2);
    QCOMPARE(cardWithPrinting(model.mainCards(), u"M11"_s, u"149"_s).value(u"count"_s).toInt(), 1);
    QVERIFY(changePrintingCount(model, u"Lightning Bolt"_s, {}, {}, false, 1));
    QCOMPARE(cardWithPrinting(model.mainCards(), {}, {}).value(u"count"_s).toInt(), 3);
    QCOMPARE(model.currentCardCopies(u"Lightning Bolt"_s), 4);

    QVERIFY(changePrinting(model, u"Delver of Secrets // Insectile Aberration"_s, u"MID"_s, u"47"_s,
                           false, u"Delver of Secrets"_s,
                           u"Creature — Human Wizard // Creature — Insect"_s, u"V17"_s, u"11"_s));
    QVERIFY(cardWithPrinting(model.mainCards(), u"V17"_s, u"11"_s).size() > 0);
}
