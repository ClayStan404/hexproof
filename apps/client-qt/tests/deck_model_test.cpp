// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "deck_test.h"

#include "deck/Deck.h"
#include "deck/DeckParser.h"
#include "models/ClientPreferencesModel.h"
#include "models/DeckLibraryModel.h"
#include "models/DeckLibraryStorage.h"

#include <QDir>
#include <QElapsedTimer>
#include <QFile>
#include <QFileDevice>
#include <QJsonDocument>
#include <QJsonObject>
#include <QScopeGuard>
#include <QSemaphore>
#include <QSet>
#include <QSignalSpy>
#include <QTemporaryDir>
#include <QTest>
#include <QUrl>

#include <atomic>
#include <chrono>
#include <memory>
#include <thread>

using namespace Qt::StringLiterals;
using hexproof::client::ClientPreferencesModel;
using hexproof::client::DeckLibraryModel;
using hexproof::client::DeckLibraryStorage;
using hexproof::client::DeckParser;

namespace {

QString startupDeckText(int count, bool sameName = false)
{
    QString text;
    for (int i = 0; i < count; ++i)
        text +=
            u"1 %1 (TST) %2\n"_s.arg(sameName ? u"Shared"_s : u"Startup %1"_s.arg(i)).arg(i + 1);
    return text;
}

QVariantMap customPrintingBinding(const QString &name, const QString &set, const QString &collector)
{
    return {{u"scope"_s, u"printing"_s},
            {u"name"_s, name},
            {u"setCode"_s, set},
            {u"collectorNumber"_s, collector}};
}

} // namespace

void TestDeckLibrary::defersInitialDisplayPathsInBoundedBatches_data() const
{
    QTest::addColumn<bool>("sameName");
    QTest::newRow("distinct-names") << false;
    QTest::newRow("many-printings-for-one-name") << true;
}

void TestDeckLibrary::defersInitialDisplayPathsInBoundedBatches() const
{
    QFETCH(bool, sameName);
    QTemporaryDir storage;
    QVERIFY(storage.isValid());
    QFile image(storage.filePath(u"existing.png"_s));
    QVERIFY(image.open(QIODevice::WriteOnly));
    QCOMPARE(image.write("image"), qint64(5));
    image.close();
    DeckLibraryModel model(storage.path());
    QVERIFY(model.importDeck(u"Startup"_s, u"custom"_s, startupDeckText(96, sameName)));
    QVERIFY(model.openDeck(model.data(model.index(0), DeckLibraryModel::IdRole).toString()));
    for (int i = 0; i < 96; ++i)
        model.applyCardMetadata(sameName ? u"Shared"_s : u"Startup %1"_s.arg(i), {}, {},
                                image.fileName(), u"TST"_s, QString::number(i + 1));
    QVERIFY(model.currentReady());
    int calls = 0;
    model.setImagePathResolver(
        [&](const hexproof::client::DeckCard &) {
            ++calls;
            return image.fileName();
        },
        true);
    QCOMPARE(calls, 0);
    QCOMPARE(model.currentMissingImageCount(), 96);
    QVERIFY(!model.currentReady());
    for (const QVariant &value : model.mainCards()) {
        QVERIFY(value.toMap().value(u"imageSource"_s).toString().isEmpty());
        QVERIFY(value.toMap().value(u"imageSourceResolved"_s).toBool());
    }
    int firstBatch = 0;
    int callsAtYield = 0;
    connect(&model, &DeckLibraryModel::currentDeckCardsChanged, &model, [&]() {
        if (firstBatch != 0 || calls == 0)
            return;
        firstBatch = calls;
        QTimer::singleShot(0, &model, [&]() { callsAtYield = calls; });
    });
    QTRY_COMPARE(calls, 96);
    QVERIFY(firstBatch > 0);
    QVERIFY(firstBatch <= 32);
    QCOMPARE(callsAtYield, firstBatch);
    QVERIFY(model.currentReady());
    QCOMPARE(model.currentMissingImageCount(), 0);
}

void TestDeckLibrary::deferredDisplayPathsFollowCurrentEditedRows() const
{
    QTemporaryDir storage;
    QVERIFY(storage.isValid());
    DeckLibraryModel model(storage.path());
    QVERIFY(model.importDeck(u"Edited"_s, u"custom"_s, startupDeckText(70)));
    const QString editedId = model.data(model.index(0), DeckLibraryModel::IdRole).toString();
    QVERIFY(model.importDeck(u"Deleted"_s, u"custom"_s, u"1 Deleted (TST) 999\n"_s));
    const QString deletedId = model.data(model.index(0), DeckLibraryModel::IdRole).toString();
    QVERIFY(model.openDeck(editedId));
    QStringList lookedUp;
    model.setImagePathResolver(
        [&](const hexproof::client::DeckCard &card) {
            lookedUp.append(card.name + u"/"_s + card.collectorNumber);
            return storage.filePath(card.name + u"-"_s + card.collectorNumber + u".png"_s);
        },
        true);
    QVERIFY(lookedUp.isEmpty());
    QVERIFY(model.deleteDeck(deletedId));
    QVERIFY(model.changeCardCount(u"Startup 1"_s, u"TST"_s, u"2"_s, false, -1));
    QVERIFY(model.moveCardToConsider(u"Startup 2"_s, u"TST"_s, u"3"_s));
    QVERIFY(
        model.setCardPrinting(u"Startup 0"_s, u"TST"_s, u"1"_s, false, {}, {}, u"TST"_s, u"100"_s));
    QVERIFY(model.addCard(u"Added"_s, {}, {}, u"TST"_s, u"200"_s, false));
    QCOMPARE(lookedUp.size(), 2); // Only the explicitly edited/new rows resolve synchronously.
    bool renamedBetweenBatches = false;
    connect(&model, &DeckLibraryModel::currentDeckCardsChanged, &model, [&]() {
        if (renamedBetweenBatches || lookedUp.size() <= 2)
            return;
        renamedBetweenBatches = true;
        QVERIFY(model.renameCurrentDeck(u"Renamed while loading"_s));
    });
    QTRY_COMPARE(lookedUp.size(), 70);
    QVERIFY(renamedBetweenBatches);
    QVERIFY(!lookedUp.contains(u"Deleted/999"_s));
    QVERIFY(!lookedUp.contains(u"Startup 1/2"_s));
    QVERIFY(!lookedUp.contains(u"Startup 0/1"_s));
    QCOMPARE(lookedUp.count(u"Startup 0/100"_s), 1);
    QCOMPARE(lookedUp.count(u"Added/200"_s), 1);
    QCOMPARE(lookedUp.count(u"Startup 2/3"_s), 1);
    const QVariantMap moved = model.considerCards().first().toMap();
    QVERIFY(QUrl(moved.value(u"imageSource"_s).toString())
                .toLocalFile()
                .endsWith(u"Startup 2-3.png"_s));
}

void TestDeckLibrary::cancelsDeferredDisplayPathsWhenResolverChanges() const
{
    QTemporaryDir storage;
    QVERIFY(storage.isValid());
    DeckLibraryModel model(storage.path());
    QVERIFY(model.importDeck(u"Startup"_s, u"custom"_s, startupDeckText(70)));
    QVERIFY(model.openDeck(model.data(model.index(0), DeckLibraryModel::IdRole).toString()));
    int oldCalls = 0;
    int newCalls = 0;
    const auto oldResolver = [&](const hexproof::client::DeckCard &) {
        ++oldCalls;
        return storage.filePath(u"old.png"_s);
    };
    const auto newResolver = [&](const hexproof::client::DeckCard &) {
        ++newCalls;
        return storage.filePath(u"new.png"_s);
    };
    model.setImagePathResolver(oldResolver, true);
    model.setImagePathResolver(newResolver, true);
    QCOMPARE(oldCalls, 0);
    QCOMPARE(newCalls, 0);
    QTRY_COMPARE(newCalls, 70);
    QCOMPARE(oldCalls, 0);

    model.setImagePathResolver(oldResolver, true);
    model.setImagePathResolver(newResolver);
    QCOMPARE(newCalls, 140);
    QTest::qWait(60);
    QCOMPARE(oldCalls, 0);
    QCOMPARE(newCalls, 140);
    model.setImagePathResolver(oldResolver, true);
    model.setImagePathResolver({});
    QTest::qWait(60);
    QCOMPARE(oldCalls, 0);
    for (const QVariant &value : model.mainCards())
        QVERIFY(!value.toMap().value(u"imageSourceResolved"_s).toBool());

    model.setImagePathResolver(oldResolver, true);
    model.refreshDisplayedCardArt();
    QCOMPARE(oldCalls, 70);
    QTest::qWait(60);
    QCOMPARE(oldCalls, 70);
    {
        auto temporary = std::make_unique<DeckLibraryModel>(storage.filePath(u"temporary"_s));
        QVERIFY(temporary->importDeck(u"Destroyed before callback"_s, u"custom"_s,
                                      startupDeckText(70)));
        temporary->setImagePathResolver(oldResolver, true);
    }
    QTest::qWait(60);
    QCOMPARE(oldCalls, 70);
}

void TestDeckLibrary::refreshesOnlyChangedCustomArtPrintingsWithoutHydrationOrSaving() const
{
    QTemporaryDir storage;
    QVERIFY(storage.isValid());
    DeckLibraryModel model(storage.path());
    QVERIFY(model.importDeck(u"Edited"_s, u"custom"_s,
                             u"1 Alpha (TST) 1\n1 Beta (TST) 2\nSideboard\n1 Alpha (TST) 1\n"
                             u"Consider\n1 中文别名 (TST) 1\n"_s));
    const QString editedId = model.data(model.index(0), DeckLibraryModel::IdRole).toString();
    QVERIFY(
        model.importDeck(u"Unrelated"_s, u"custom"_s, u"1 Alpha (OTHER) 1\n1 Gamma (TST) 3\n"_s));
    QVERIFY(model.openDeck(editedId));
    bool changed = false;
    QStringList lookedUp;
    model.setImagePathResolver([&](const hexproof::client::DeckCard &card) {
        lookedUp.append(card.name + u"/"_s + card.setCode + u"/"_s + card.collectorNumber);
        return storage.filePath(changed && card.setCode == u"TST"_s &&
                                        card.collectorNumber == u"1"_s
                                    ? u"custom.png"_s
                                    : u"official.png"_s);
    });
    QTRY_VERIFY(!model.backgroundSaveRunningForTest());
    const quint64 generation = model.persistenceGenerationForTest();
    QFile library(storage.filePath(u"decks.json"_s));
    QVERIFY(library.open(QIODevice::ReadOnly));
    const QByteArray before = library.readAll();
    library.close();
    QSignalSpy hydration(&model, &DeckLibraryModel::cardsNeedCachedArtLookup);
    QSignalSpy downloads(&model, &DeckLibraryModel::cardsNeedCaching);
    QSignalSpy gridChanged(&model, &DeckLibraryModel::currentDeckCardsChanged);
    lookedUp.clear();
    changed = true;
    const QVariantList bindings{
        customPrintingBinding(u"Different official title"_s, u"tst"_s, u"1"_s)};
    model.refreshCustomCardArt(bindings);
    QVERIFY(lookedUp.isEmpty());
    QTRY_COMPARE(lookedUp.size(), 3);
    QCOMPARE(gridChanged.size(), 1);
    QCOMPARE(lookedUp.count(u"Alpha/TST/1"_s), 2);
    QCOMPARE(lookedUp.count(u"中文别名/TST/1"_s), 1);
    QVERIFY(!lookedUp.contains(u"Alpha/OTHER/1"_s));
    QVERIFY(!lookedUp.contains(u"Beta/TST/2"_s));
    gridChanged.clear();
    lookedUp.clear();
    model.refreshCustomCardArt(bindings);
    QTRY_COMPARE(lookedUp.size(), 3);
    QVERIFY(gridChanged.isEmpty()); // A repeated revision cannot recreate the card grid.
    lookedUp.clear();
    model.refreshCustomCardArt({customPrintingBinding(u"Alpha"_s, u"NOPE"_s, u"9"_s)});
    QTest::qWait(60);
    QVERIFY(lookedUp.isEmpty());
    QVERIFY(gridChanged.isEmpty());
    QVERIFY(hydration.isEmpty());
    QVERIFY(downloads.isEmpty());
    QCOMPARE(model.persistenceGenerationForTest(), generation);
    QVERIFY(!model.metadataCommitPendingForTest());
    QVERIFY(library.open(QIODevice::ReadOnly));
    QCOMPARE(library.readAll(), before);
}

void TestDeckLibrary::refreshesCardWideCustomArtInPrioritizedBoundedBatches() const
{
    QTemporaryDir storage;
    QVERIFY(storage.isValid());
    DeckLibraryModel model(storage.path());
    QString currentText = startupDeckText(96);
    currentText.replace(u"Startup"_s, u"Current"_s);
    QVERIFY(model.importDeck(u"Current"_s, u"custom"_s, currentText));
    const QString editedId = model.data(model.index(0), DeckLibraryModel::IdRole).toString();
    QVERIFY(model.importDeck(u"Other"_s, u"custom"_s, startupDeckText(96, true)));
    QVERIFY(model.openDeck(editedId));
    int revision = 0;
    QStringList lookedUp;
    model.setImagePathResolver([&](const hexproof::client::DeckCard &card) {
        lookedUp.append(card.name);
        return storage.filePath(u"revision-%1.png"_s.arg(revision));
    });
    lookedUp.clear();
    ++revision;
    int firstBatch = 0;
    int callsAtYield = 0;
    connect(&model, &DeckLibraryModel::currentDeckCardsChanged, &model, [&]() {
        if (firstBatch == 0 && !lookedUp.isEmpty()) {
            firstBatch = lookedUp.size();
            QTimer::singleShot(0, &model, [&]() { callsAtYield = lookedUp.size(); });
        }
    });
    // The card-wide binding deliberately has a name absent from the deck. A
    // localized row cannot be excluded without a verified per-row Oracle ID.
    model.refreshCustomCardArt({QVariantMap{{u"scope"_s, u"card"_s},
                                            {u"name"_s, u"Unrepresented canonical name"_s},
                                            {u"oracleId"_s, u"oracle-id"_s}}});
    QVERIFY(lookedUp.isEmpty());
    QTRY_COMPARE(lookedUp.size(), 192);
    QVERIFY(firstBatch > 0);
    QVERIFY(firstBatch <= 32);
    QCOMPARE(callsAtYield, firstBatch);
    for (int i = 0; i < 96; ++i)
        QVERIFY(lookedUp.at(i).startsWith(u"Current "_s));
    for (int i = 96; i < 192; ++i)
        QCOMPARE(lookedUp.at(i), u"Shared"_s);
    QSignalSpy gridChanged(&model, &DeckLibraryModel::currentDeckCardsChanged);
    lookedUp.clear();
    model.refreshCustomCardArt({});
    QVERIFY(lookedUp.isEmpty());
    QTRY_COMPARE(lookedUp.size(), 192);
    QVERIFY(gridChanged.isEmpty());
}

void TestDeckLibrary::mergesCustomArtRefreshWithPendingStartupAndEdits() const
{
    QTemporaryDir storage;
    QVERIFY(storage.isValid());
    DeckLibraryModel model(storage.path());
    QVERIFY(model.importDeck(u"Startup"_s, u"custom"_s, startupDeckText(96, true)));
    const QString editedId = model.data(model.index(0), DeckLibraryModel::IdRole).toString();
    QVERIFY(model.importDeck(u"Deleted"_s, u"custom"_s, u"1 Deleted (TST) 1000\n"_s));
    const QString deletedId = model.data(model.index(0), DeckLibraryModel::IdRole).toString();
    QVERIFY(model.openDeck(editedId));
    QStringList lookedUp;
    bool restored = false;
    model.setImagePathResolver(
        [&](const hexproof::client::DeckCard &card) {
            lookedUp.append(card.collectorNumber);
            return storage.filePath(restored && card.collectorNumber == u"1"_s ? u"restored.png"_s
                                                                               : u"initial.png"_s);
        },
        true);
    model.refreshCustomCardArt({customPrintingBinding(u"Shared"_s, u"TST"_s, u"2"_s)});
    QVERIFY(lookedUp.isEmpty());
    connect(&model, &DeckLibraryModel::currentDeckCardsChanged, &model, [&]() {
        if (restored || lookedUp.isEmpty())
            return;
        restored = true;
        QVERIFY(model.deleteDeck(deletedId));
        QVERIFY(model.moveCardToConsider(u"Shared"_s, u"TST"_s, u"80"_s));
        model.refreshCustomCardArt({customPrintingBinding(u"Shared"_s, u"TST"_s, u"1"_s)});
    });
    QTRY_COMPARE(lookedUp.size(), 97);
    QVERIFY(restored);
    QCOMPARE(lookedUp.count(u"1"_s), 2);
    QCOMPARE(lookedUp.count(u"80"_s), 1);
    QVERIFY(!lookedUp.contains(u"1000"_s));
    for (int i = 2; i <= 96; ++i)
        QCOMPARE(lookedUp.count(QString::number(i)), 1);
    for (const QVariant &value : model.mainCards()) {
        const QVariantMap card = value.toMap();
        QVERIFY(card.value(u"imageSourceResolved"_s).toBool());
        QVERIFY(!card.value(u"imageSource"_s).toString().isEmpty());
        if (card.value(u"collectorNumber"_s).toString() == u"1"_s)
            QVERIFY(card.value(u"imageSource"_s).toString().endsWith(u"restored.png"_s));
    }
    QVERIFY(!model.considerCards().first().toMap().value(u"imageSource"_s).toString().isEmpty());
}

void TestDeckLibrary::customArtRestorePreservesOfficialReadinessAndCancelsSafely() const
{
    QTemporaryDir storage;
    QVERIFY(storage.isValid());
    QFile image(storage.filePath(u"custom.png"_s));
    QVERIFY(image.open(QIODevice::WriteOnly));
    QCOMPARE(image.write("image"), qint64(5));
    image.close();
    DeckLibraryModel model(storage.path());
    QVERIFY(model.importDeck(u"Custom ready"_s, u"custom"_s, u"7 Alpha (TST) 1\n"_s));
    QVERIFY(model.openDeck(model.data(model.index(0), DeckLibraryModel::IdRole).toString()));
    int calls = 0;
    bool custom = true;
    model.setImagePathResolver([&](const hexproof::client::DeckCard &) {
        ++calls;
        return custom ? image.fileName() : QString{};
    });
    QVERIFY(model.currentReady());
    const quint64 generation = model.persistenceGenerationForTest();
    custom = false;
    model.refreshCustomCardArt({customPrintingBinding(u"Alpha"_s, u"TST"_s, u"1"_s)});
    QTRY_COMPARE(calls, 2);
    QVERIFY(!model.currentReady());
    QCOMPARE(model.currentMissingImageCount(), 1);
    // The old custom file still exists, but must not count as an official
    // successful download after its mapping has been restored.
    QVERIFY(QFile::exists(image.fileName()));
    QVERIFY(model.mainCards().first().toMap().value(u"imageSource"_s).toString().isEmpty());
    QCOMPARE(model.persistenceGenerationForTest(), generation);
    model.refreshCustomCardArt({});
    model.setImagePathResolver({});
    QTest::qWait(60);
    QCOMPARE(calls, 2);
    QVERIFY(!model.currentReady());
    QVERIFY(!model.mainCards().first().toMap().value(u"imageSourceResolved"_s).toBool());
    {
        auto temporary = std::make_unique<DeckLibraryModel>(storage.filePath(u"temporary"_s));
        QVERIFY(temporary->importDeck(u"Destroyed"_s, u"custom"_s, startupDeckText(96)));
        temporary->setImagePathResolver(
            [&](const hexproof::client::DeckCard &) {
                ++calls;
                return image.fileName();
            },
            true);
        temporary->refreshCustomCardArt({});
    }
    QTest::qWait(60);
    QCOMPARE(calls, 2);
}

void TestDeckLibrary::customArtRefreshResolvesSeparateMeldAliases() const
{
    QTemporaryDir storage;
    QVERIFY(storage.isValid());
    DeckLibraryModel model(storage.path());
    QVERIFY(
        model.importDeck(u"Meld"_s, u"custom"_s,
                         u"1 Bruna, the Fading Light // Brisela, Voice of Nightmares (EMN) 15a\n"
                         u"1 Other (EMN) 15b\n1 Bruna, the Fading Light (OTHER) 20\n"_s));
    QVERIFY(model.openDeck(model.data(model.index(0), DeckLibraryModel::IdRole).toString()));
    QStringList lookedUp;
    model.setImagePathResolver([&](const hexproof::client::DeckCard &card) {
        lookedUp.append(card.collectorNumber);
        return storage.filePath(u"official.png"_s);
    });
    lookedUp.clear();
    model.refreshCustomCardArt(
        {customPrintingBinding(u"Brisela, Voice of Nightmares"_s, u"emn"_s, u"15B"_s)});
    QTRY_COMPARE(lookedUp.size(), 2);
    QVERIFY(lookedUp.contains(u"15a"_s));
    QVERIFY(lookedUp.contains(u"15b"_s));
    QVERIFY(!lookedUp.contains(u"20"_s));
}

void TestDeckLibrary::limitsDisplayPathResolutionToChangedCards() const
{
    QTemporaryDir storage;
    QVERIFY(storage.isValid());
    DeckLibraryModel model(storage.path());
    QVERIFY(model.importDeck(u"Edited"_s, u"commander"_s,
                             u"1 Alpha (TST) 1\n1 Beta (TST) 2\nConsider\n1 Delta (TST) 4\n"_s));
    const QString editedId = model.data(model.index(0), DeckLibraryModel::IdRole).toString();
    QVERIFY(model.importDeck(u"Unrelated"_s, u"custom"_s, u"1 Gamma (TST) 3\n"_s));
    QVERIFY(model.openDeck(editedId));
    QStringList lookedUp;
    const auto resolver = [&](const hexproof::client::DeckCard &card) {
        lookedUp.append(card.name);
        return storage.filePath(card.name + u"-"_s + card.collectorNumber + u".png"_s);
    };
    model.setImagePathResolver(resolver);
    QCOMPARE(lookedUp.size(), 4);
    lookedUp.clear();
    QVERIFY(model.renameCurrentDeck(u"Renamed"_s));
    QVERIFY(model.setCommander(u"Alpha"_s));
    QVERIFY(model.changeCardCount(u"Alpha"_s, u"TST"_s, u"1"_s, false, 1));
    QVERIFY(model.moveCardToConsider(u"Beta"_s, u"TST"_s, u"2"_s));
    QVERIFY(model.moveConsiderCardToMain(u"Beta"_s, u"TST"_s, u"2"_s));
    QVERIFY(model.changeCurrentDeckFormat(u"custom"_s));
    QVERIFY(lookedUp.isEmpty());

    QVERIFY(model.addCard(u"Epsilon"_s, {}, u"Creature"_s, u"TST"_s, u"5"_s, false));
    QCOMPARE(lookedUp, QStringList{u"Epsilon"_s});
    lookedUp.clear();
    QVERIFY(model.addConsiderCard(u"Zeta"_s, {}, u"Creature"_s, u"TST"_s, u"6"_s));
    QCOMPARE(lookedUp, QStringList{u"Zeta"_s});
    lookedUp.clear();
    QVERIFY(model.importDeck(u"New import"_s, u"custom"_s, u"1 Eta (TST) 7\n"_s));
    QCOMPARE(lookedUp, QStringList{u"Eta"_s});

    // Only an explicit artwork revision or a new resolver refreshes the library.
    lookedUp.clear();
    model.refreshDisplayedCardArt();
    QCOMPARE(lookedUp.size(), 7);
    lookedUp.clear();
    model.setImagePathResolver(resolver);
    QCOMPARE(lookedUp.size(), 7);
    lookedUp.clear();
    model.setImagePathResolver({});
    QVERIFY(lookedUp.isEmpty());
    for (const QVariant &entry : model.mainCards()) {
        QVERIFY(!entry.toMap().value(u"imageSourceResolved"_s).toBool());
        QVERIFY(entry.toMap().value(u"imageSource"_s).toString().isEmpty());
    }
}

void TestDeckLibrary::invalidatesDisplayPathsOnlyForArtOrPrintingMetadata() const
{
    QTemporaryDir storage;
    QVERIFY(storage.isValid());
    DeckLibraryModel model(storage.path());
    QVERIFY(model.importDeck(u"Edited"_s, u"custom"_s, u"1 Alpha\n1 Beta (TST) 2\n"_s));
    const QString editedId = model.data(model.index(0), DeckLibraryModel::IdRole).toString();
    QVERIFY(model.importDeck(u"Unrelated"_s, u"custom"_s, u"1 Gamma (TST) 3\n"_s));
    QVERIFY(model.openDeck(editedId));
    QStringList lookedUp;
    model.setImagePathResolver([&](const hexproof::client::DeckCard &card) {
        lookedUp.append(card.name + u"/"_s + card.setCode + u"/"_s + card.collectorNumber);
        return card.imagePath;
    });
    QCOMPARE(lookedUp.size(), 3);
    lookedUp.clear();
    model.applyCatalogMetadata({QVariantMap{{u"requestedName"_s, u"Beta"_s},
                                            {u"requestedSetCode"_s, u"TST"_s},
                                            {u"requestedCollectorNumber"_s, u"2"_s},
                                            {u"localizedName"_s, u"贝塔"_s},
                                            {u"manaValue"_s, 2},
                                            {u"cardColors"_s, u"U"_s}}});
    QVERIFY(lookedUp.isEmpty());
    QSignalSpy changed(&model, &DeckLibraryModel::currentDeckChanged);
    model.applyCardMetadata(u"Beta"_s, u"新贝塔"_s, u"Creature"_s, {}, u"TST"_s, u"2"_s);
    QTRY_VERIFY(!changed.isEmpty());
    QVERIFY(lookedUp.isEmpty());

    const QString imagePath = storage.filePath(u"official.png"_s);
    model.applyCardMetadata(u"Beta"_s, {}, {}, imagePath, u"TST"_s, u"2"_s);
    QTRY_COMPARE(lookedUp, QStringList{u"Beta/TST/2"_s});
    lookedUp.clear();
    model.applyCardMetadata(u"Alpha"_s, {}, {}, {}, u"TST"_s, u"1"_s);
    QTRY_COMPARE(lookedUp, QStringList{u"Alpha/TST/1"_s});
    model.setImagePathResolver({});
    for (const QVariant &entry : model.mainCards()) {
        const QVariantMap card = entry.toMap();
        if (card.value(u"name"_s).toString() == u"Beta"_s) {
            QCOMPARE(QUrl(card.value(u"imageSource"_s).toString()).toLocalFile(), imagePath);
            QVERIFY(!card.value(u"imageSourceResolved"_s).toBool());
        }
    }
}

void TestDeckLibrary::refreshesDisplayPathsAndMetadataAfterPrintingMerge() const
{
    QTemporaryDir storage;
    QVERIFY(storage.isValid());
    DeckLibraryModel model(storage.path());
    QVERIFY(model.importDeck(u"Edited"_s, u"custom"_s,
                             u"1 Alpha (TST) 1\n1 Alpha (TST) 2\n1 Beta (TST) 3\n"_s));
    const QString editedId = model.data(model.index(0), DeckLibraryModel::IdRole).toString();
    QVERIFY(model.importDeck(u"Unrelated"_s, u"custom"_s, u"1 Gamma (TST) 4\n"_s));
    QVERIFY(model.openDeck(editedId));
    QStringList lookedUp;
    model.setImagePathResolver([&](const hexproof::client::DeckCard &card) {
        lookedUp.append(card.name + u"/"_s + card.collectorNumber);
        return storage.filePath(card.name + u"-"_s + card.collectorNumber + u".png"_s);
    });
    lookedUp.clear();
    QVERIFY(model.setCardPrinting(u"Alpha"_s, u"TST"_s, u"1"_s, false, {}, {}, u"TST"_s, u"5"_s));
    QCOMPARE(lookedUp, QStringList{u"Alpha/5"_s});
    lookedUp.clear();
    QVERIFY(model.setCardPrinting(u"Alpha"_s, u"TST"_s, u"5"_s, false, {}, {}, u"TST"_s, u"2"_s));
    QCOMPARE(lookedUp, QStringList{u"Alpha/2"_s});
    QCOMPARE(model.mainCards().size(), 2);
    lookedUp.clear();
    // Merging removed the first row; the remaining Beta metadata location must
    // still address Beta, not the old pre-merge vector index.
    model.applyCardMetadata(u"Beta"_s, u"贝塔"_s, u"Creature"_s,
                            storage.filePath(u"beta-official.png"_s), u"TST"_s, u"3"_s);
    QTRY_COMPARE(lookedUp, QStringList{u"Beta/3"_s});
    for (const QVariant &entry : model.mainCards()) {
        const QVariantMap card = entry.toMap();
        if (card.value(u"name"_s).toString() == u"Alpha"_s) {
            QCOMPARE(card.value(u"count"_s).toInt(), 2);
            QVERIFY(QUrl(card.value(u"imageSource"_s).toString())
                        .toLocalFile()
                        .endsWith(u"Alpha-2.png"_s));
        } else {
            QCOMPARE(card.value(u"displayName"_s).toString(), u"贝塔"_s);
        }
    }
}

void TestDeckLibrary::snapshotsArtExportRequestsForOnlyTheSelectedDeck() const
{
    QTemporaryDir storage;
    QVERIFY(storage.isValid());
    DeckLibraryModel model(storage.path());
    QVERIFY(model.importDeck(u"Export scope"_s, u"modern"_s, uR"(
Deck
4 Lightning Bolt (M11) 146
1 Sol Ring (CMM) 396
Sideboard
2 Lightning Bolt (M11) 146
1 Lightning Bolt (2XM) 117
Consider
1 Plains (M21) 260
)"_s));
    const QString selectedId = model.data(model.index(0), DeckLibraryModel::IdRole).toString();
    QVERIFY(model.openDeck(selectedId));
    QVERIFY(model.addToken({{u"name"_s, u"Angel"_s},
                            {u"setCode"_s, u"TM21"_s},
                            {u"collectorNumber"_s, u"1"_s},
                            {u"kind"_s, u"token"_s}}));
    QVERIFY(model.addToken({{u"name"_s, u"Teferi Emblem"_s},
                            {u"setCode"_s, u"TDOM"_s},
                            {u"collectorNumber"_s, u"16"_s},
                            {u"kind"_s, u"emblem"_s}}));
    QVERIFY(model.importDeck(u"Unrelated"_s, u"modern"_s, u"1 Island (M21) 263\n"_s));
    QString unrelatedId;
    for (int row = 0; row < model.rowCount(); ++row) {
        const QString id = model.data(model.index(row), DeckLibraryModel::IdRole).toString();
        if (id != selectedId)
            unrelatedId = id;
    }
    QVERIFY(model.openDeck(unrelatedId));
    model.setFormatFilter(u"cube"_s);
    QCOMPARE(model.rowCount(), 0);
    QSignalSpy caching(&model, &DeckLibraryModel::cardsNeedCaching);
    const QVariantList snapshot = model.cardArtExportRequests(selectedId);
    QCOMPARE(snapshot.size(), 6); // Copies and duplicate zones share one printing request.
    QSet<QString> printings;
    QSet<QString> kinds;
    for (const QVariant &value : snapshot) {
        const QVariantMap request = value.toMap();
        printings.insert(request.value(u"setCode"_s).toString() + QLatin1Char('/') +
                         request.value(u"collectorNumber"_s).toString());
        if (request.contains(u"kind"_s))
            kinds.insert(request.value(u"kind"_s).toString());
    }
    QCOMPARE(printings, (QSet<QString>{u"M11/146"_s, u"CMM/396"_s, u"2XM/117"_s, u"M21/260"_s,
                                       u"TM21/1"_s, u"TDOM/16"_s}));
    QCOMPARE(kinds, (QSet<QString>{u"token"_s, u"emblem"_s}));
    QVERIFY(model.cardArtExportRequests({}).isEmpty());
    QVERIFY(model.cardArtExportRequests(u"missing"_s).isEmpty());
    QCOMPARE(caching.count(), 0);
    QCOMPARE(model.currentDeckId(), unrelatedId);
    QVERIFY(model.deleteDeck(selectedId));
    QVERIFY(model.cardArtExportRequests(selectedId).isEmpty());
    QCOMPARE(snapshot.size(), 6);
}

void TestDeckLibrary::importsFiltersEditsAndPersists() const
{
    QTemporaryDir storage;
    QVERIFY(storage.isValid());

    QString deckId;
    {
        DeckLibraryModel model(storage.path());
        QSignalSpy cachingSpy(&model, &DeckLibraryModel::cardsNeedCaching);
        QVERIFY(model.importDeck(u"Burn"_s, u"modern"_s, uR"(
Deck
4 Lightning Bolt
4 Monastery Swiftspear
Sideboard
2 Smash to Smithereens
)"_s));
        QCOMPARE(model.rowCount(), 1);
        QCOMPARE(model.data(model.index(0), DeckLibraryModel::MainCountRole).toInt(), 8);
        QCOMPARE(model.data(model.index(0), DeckLibraryModel::SideboardCountRole).toInt(), 2);
        QCOMPARE(cachingSpy.count(), 0);

        deckId = model.data(model.index(0), DeckLibraryModel::IdRole).toString();
        QVERIFY(model.openDeck(deckId));
        QVERIFY(model.changeCardCount(u"Lightning Bolt"_s, {}, {}, false, 1));
        QCOMPARE(model.currentCardCopies(u"Lightning Bolt"_s), 5);
        QVERIFY(model.moveCard(u"Lightning Bolt"_s, {}, {}, true));
        QCOMPARE(model.currentMainCount(), 8);
        QCOMPARE(model.currentSideboardCount(), 3);
        QVERIFY(model.changeCardCount(u"Lightning Bolt"_s, {}, {}, true, 1));
        QVERIFY(
            model.addCard(u"Sol Ring"_s, u"Sol Ring"_s, u"Artifact"_s, u"CMM"_s, u"396"_s, false));
        QCOMPARE(model.currentMainCount(), 9);
        QCOMPARE(cachingSpy.count(), 1);
        const QVariantList added = cachingSpy.last().first().toList();
        QCOMPARE(added.size(), 1);
        QCOMPARE(added.first().toMap().value(u"name"_s).toString(), u"Sol Ring"_s);
        QSignalSpy cardsAboutToChangeSpy(&model, &DeckLibraryModel::currentDeckCardsAboutToChange);
        QSignalSpy cardsChangedSpy(&model, &DeckLibraryModel::currentDeckCardsChanged);
        QVERIFY(model.setCardPrinting(u"Sol Ring"_s, u"CMM"_s, u"396"_s, false, u"阳光戒"_s,
                                      u"神器"_s, u"2X2"_s, u"308"_s));
        QCOMPARE(cardsAboutToChangeSpy.count(), 1);
        QCOMPARE(cardsChangedSpy.count(), 1);
        QCOMPARE(cachingSpy.count(), 2);
        const QVariantMap printingRequest = cachingSpy.last().first().toList().constFirst().toMap();
        QVERIFY(printingRequest.value(u"exactArt"_s).toBool());
        QVariantMap solRing;
        for (const QVariant &value : model.mainCards()) {
            if (value.toMap().value(u"name"_s).toString() == u"Sol Ring"_s)
                solRing = value.toMap();
        }
        QVERIFY(!solRing.isEmpty());
        QCOMPARE(solRing.value(u"setCode"_s).toString(), u"2X2"_s);
        QCOMPARE(solRing.value(u"collectorNumber"_s).toString(), u"308"_s);
        QCOMPARE(solRing.value(u"totalCount"_s).toInt(), 1);

        model.setFormatFilter(u"edh"_s);
        QCOMPARE(model.rowCount(), 0);
        model.setFormatFilter(u"all"_s);
        QCOMPARE(model.rowCount(), 1);
    }

    DeckLibraryModel restored(storage.path());
    QCOMPARE(restored.rowCount(), 1);
    QVERIFY(restored.openDeck(deckId));
    QCOMPARE(restored.currentMainCount(), 9);
    QCOMPARE(restored.currentSideboardCount(), 4);
    QVERIFY(restored.deleteDeck(deckId));
    QCOMPARE(restored.rowCount(), 0);
}

void TestDeckLibrary::edhReadinessRequiresCommanderAndImages() const
{
    QTemporaryDir storage;
    QVERIFY(storage.isValid());
    DeckLibraryModel model(storage.path());
    QVERIFY(model.importDeck(u"Commander test"_s, u"edh"_s, u"7 Sol Ring\n"_s));
    const QString id = model.data(model.index(0), DeckLibraryModel::IdRole).toString();
    QVERIFY(model.openDeck(id));
    QCOMPARE(model.currentStatus(), u"Commander required"_s);
    QVERIFY(model.setCommander(u"Sol Ring"_s));
    QCOMPARE(model.currentStatus(), u"1 image missing"_s);

    const QString imagePath = storage.filePath(u"sol-ring.jpg"_s);
    QFile image(imagePath);
    QVERIFY(image.open(QIODevice::WriteOnly));
    QVERIFY(image.write("image") > 0);
    image.close();

    model.applyCardMetadata(u"Sol Ring"_s, u"阳光戒"_s, u"Artifact"_s, imagePath, u"CMM"_s,
                            u"396"_s);
    QVERIFY(model.currentReady());
    QCOMPARE(model.currentStatus(), u"Playable"_s);
    QCOMPARE(model.mainCards().first().toMap().value(u"displayName"_s).toString(), u"阳光戒"_s);
}

void TestDeckLibrary::validatesOnlyAffectedDecks() const
{
    QTemporaryDir storage;
    QVERIFY(storage.isValid());
    DeckLibraryModel model(storage.path());
    QSignalSpy validationSpy(&model, &DeckLibraryModel::decksNeedValidation);

    const auto acknowledge = [&model](const QVariantList &requests) {
        QVariantList results;
        for (const QVariant &requestEntry : requests) {
            const QVariantMap request = requestEntry.toMap();
            results.append(QVariantMap{
                {u"deckId"_s, request.value(u"deckId"_s)},
                {u"validationRevision"_s, request.value(u"validationRevision"_s)},
                {u"valid"_s, true},
                {u"verified"_s, true},
                {u"status"_s, u"Playable"_s},
                {u"issues"_s, QStringList{}},
            });
        }
        model.applyDeckValidation(results);
    };

    QVERIFY(model.importDeck(u"First"_s, u"modern"_s, u"60 Mountain\n"_s));
    const QString firstId = model.data(model.index(0), DeckLibraryModel::IdRole).toString();
    QTRY_COMPARE(validationSpy.count(), 1);
    QVariantList requests = validationSpy.takeFirst().constFirst().toList();
    QCOMPARE(requests.size(), 1);
    QCOMPARE(requests.constFirst().toMap().value(u"deckId"_s).toString(), firstId);
    acknowledge(requests);

    QVERIFY(model.importDeck(u"Second"_s, u"modern"_s, u"60 Forest\n"_s));
    const QString secondId = model.data(model.index(0), DeckLibraryModel::IdRole).toString();
    QTRY_COMPARE(validationSpy.count(), 1);
    requests = validationSpy.takeFirst().constFirst().toList();
    QCOMPARE(requests.size(), 1);
    QCOMPARE(requests.constFirst().toMap().value(u"deckId"_s).toString(), secondId);
    acknowledge(requests);

    QVERIFY(model.deleteDeck(firstId));
    QTest::qWait(150);
    QCOMPARE(validationSpy.count(), 0);

    QVERIFY(model.openDeck(secondId));
    QVERIFY(model.renameCurrentDeck(u"Renamed"_s));
    QTest::qWait(150);
    QCOMPARE(validationSpy.count(), 0);

    QVERIFY(model.changeCardCount(u"Forest"_s, {}, {}, false, -1));
    QTRY_COMPARE(validationSpy.count(), 1);
    requests = validationSpy.takeFirst().constFirst().toList();
    QCOMPARE(requests.size(), 1);
    QCOMPARE(requests.constFirst().toMap().value(u"deckId"_s).toString(), secondId);
}

void TestDeckLibrary::rejectsValidationFromPreviousDeckFormat() const
{
    QTemporaryDir storage;
    QVERIFY(storage.isValid());
    DeckLibraryModel model(storage.path());
    QSignalSpy validationSpy(&model, &DeckLibraryModel::decksNeedValidation);
    QVERIFY(model.importDeck(u"Format changes"_s, u"modern"_s, u"60 Mountain\n"_s));
    const QString deckId = model.data(model.index(0), DeckLibraryModel::IdRole).toString();
    QVERIFY(model.openDeck(deckId));
    QTRY_COMPARE(validationSpy.count(), 1);
    const QVariantMap previous = validationSpy.takeFirst().first().toList().first().toMap();

    QVERIFY(model.changeCurrentDeckFormat(u"custom"_s));
    model.refreshDeckValidation();
    QVERIFY(model.changeCurrentDeckFormat(u"pioneer"_s));
    const QVariantMap staleResult{
        {u"deckId"_s, deckId},
        {u"validationRevision"_s, previous.value(u"validationRevision"_s)},
        {u"valid"_s, false},
        {u"verified"_s, true},
        {u"issues"_s, QStringList{u"Old format error"_s}},
    };
    // The old worker may finish before the new request's debounce timer fires.
    model.applyDeckValidation({staleResult});
    QVERIFY(model.currentValidationIssues().isEmpty());
    QTRY_COMPARE(validationSpy.count(), 1);
    const QVariantMap current = validationSpy.takeFirst().first().toList().first().toMap();
    QCOMPARE(current.value(u"deckFormat"_s).toString(), u"pioneer"_s);
    model.applyDeckValidation({QVariantMap{
        {u"deckId"_s, deckId},
        {u"validationRevision"_s, current.value(u"validationRevision"_s)},
        {u"valid"_s, true},
        {u"verified"_s, true},
        {u"issues"_s, QStringList{}},
    }});
    model.applyDeckValidation({staleResult});
    QVERIFY(model.currentValidationVerified());
    QVERIFY(model.currentValidationIssues().isEmpty());
}

void TestDeckLibrary::legalityWarningsDoNotBlockDeckSelection() const
{
    QTemporaryDir storage;
    QVERIFY(storage.isValid());
    DeckLibraryModel model(storage.path());
    QSignalSpy validationSpy(&model, &DeckLibraryModel::decksNeedValidation);

    QVERIFY(model.importDeck(u"Advisory identity"_s, u"edh"_s,
                             u"1 White Commander *CMDR*\n99 Plains\n"_s));
    const QString id = model.data(model.index(0), DeckLibraryModel::IdRole).toString();
    QVERIFY(model.openDeck(id));
    QTRY_COMPARE(validationSpy.count(), 1);
    const QVariantMap request =
        validationSpy.takeFirst().constFirst().toList().constFirst().toMap();
    QSignalSpy cardsChangedSpy(&model, &DeckLibraryModel::currentDeckCardsChanged);
    const QString summary = u"2 cards may be outside the commanders' color identity."_s;
    model.applyDeckValidation({QVariantMap{
        {u"deckId"_s, id},
        {u"validationRevision"_s, request.value(u"validationRevision"_s)},
        {u"valid"_s, true},
        {u"verified"_s, true},
        {u"status"_s, summary},
        {u"issues"_s,
         QStringList{summary, u"Counterspell is outside the commanders' color identity."_s,
                     u"Lightning Bolt is outside the commanders' color identity."_s}},
        {u"warnings"_s, QStringList{summary}},
    }});

    QCOMPARE(cardsChangedSpy.count(), 0);
    QCOMPARE(model.currentValidationWarnings(), QStringList{summary});
    QCOMPARE(model.data(model.index(0), DeckLibraryModel::ValidationWarningsRole).toStringList(),
             QStringList{summary});
    const QVariantList decks = model.matchDecks(u"commander"_s, true);
    QCOMPARE(decks.size(), 1);
    QVERIFY(decks.constFirst().toMap().value(u"ready"_s).toBool());
    QCOMPARE(decks.constFirst().toMap().value(u"legalityWarnings"_s).toStringList(),
             QStringList{summary});
    QVERIFY(!model.deckForMatch(id, true).isEmpty());
}

void TestDeckLibrary::duelCommanderImportsFiltersAndBuildsPayload() const
{
    QTemporaryDir storage;
    QVERIFY(storage.isValid());
    DeckLibraryModel model(storage.path());
    QVERIFY(model.importDeck(u"Duel test"_s, u"duel"_s, u"7 Sol Ring (CMM) 396 *CMDR*\n"_s));
    const QString id = model.data(model.index(0), DeckLibraryModel::IdRole).toString();
    QVERIFY(model.openDeck(id));
    QCOMPARE(model.currentDeckFormat(), u"duel"_s);
    QCOMPARE(model.currentCommander(), u"Sol Ring"_s);
    QCOMPARE(model.currentStatus(), u"1 image missing"_s);

    const QString imagePath = storage.filePath(u"sol-ring.jpg"_s);
    QFile image(imagePath);
    QVERIFY(image.open(QIODevice::WriteOnly));
    QVERIFY(image.write("image") > 0);
    image.close();
    model.applyCardMetadata(u"Sol Ring"_s, u"Sol Ring"_s, u"Artifact"_s, imagePath, u"CMM"_s,
                            u"396"_s);
    QVERIFY(model.currentReady());

    model.setFormatFilter(u"duel"_s);
    QCOMPARE(model.rowCount(), 1);
    model.setFormatFilter(u"modern"_s);
    QCOMPARE(model.rowCount(), 0);

    const QVariantMap payload = model.deckForMatch(id);
    QCOMPARE(payload.value(u"format"_s).toString(), u"duel"_s);
    QCOMPARE(payload.value(u"commander"_s).toString(), u"Sol Ring"_s);
    QCOMPARE(payload.value(u"commanders"_s).toStringList(), QStringList{u"Sol Ring"_s});
}

void TestDeckLibrary::changesDeckFormatWithoutLosingCards() const
{
    QTemporaryDir storage;
    QVERIFY(storage.isValid());
    QString deckId;
    {
        DeckLibraryModel model(storage.path());
        QVERIFY(model.importDeck(u"Convertible"_s, u"modern"_s,
                                 u"Deck\n59 Mountain\n1 Negate (M20) 69\n"
                                 u"Sideboard\n2 Negate (STA) 18\n"_s));
        deckId = model.data(model.index(0), DeckLibraryModel::IdRole).toString();
        QVERIFY(model.openDeck(deckId));
        QSignalSpy validationSpy(&model, &DeckLibraryModel::decksNeedValidation);

        QVERIFY(model.changeCurrentDeckFormat(u"commander"_s));
        QCOMPARE(model.currentDeckFormat(), u"commander"_s);
        QCOMPARE(model.currentDeckTableMode(), u"edh"_s);
        QCOMPARE(model.currentMainCount(), 62);
        QCOMPARE(model.currentSideboardCount(), 0);
        QVERIFY(model.currentCommander().isEmpty());
        QSet<QString> negatePrintings;
        for (const QVariant &entry : model.mainCards()) {
            const QVariantMap card = entry.toMap();
            if (card.value(u"name"_s).toString() == u"Negate"_s) {
                negatePrintings.insert(card.value(u"setCode"_s).toString() + u"/"_s +
                                       card.value(u"collectorNumber"_s).toString());
            }
        }
        QCOMPARE(negatePrintings, QSet<QString>({u"M20/69"_s, u"STA/18"_s}));
        QTRY_COMPARE(validationSpy.count(), 1);
        const QVariantList requests = validationSpy.takeFirst().constFirst().toList();
        QCOMPARE(requests.size(), 1);
        QCOMPARE(requests.constFirst().toMap().value(u"deckId"_s).toString(), deckId);
        QCOMPARE(requests.constFirst().toMap().value(u"deckFormat"_s).toString(), u"commander"_s);

        QVERIFY(model.setCommander(u"Mountain"_s));
        QCOMPARE(model.currentCommander(), u"Mountain"_s);
        QVERIFY(model.changeCurrentDeckFormat(u"duel"_s));
        QCOMPARE(model.currentDeckTableMode(), u"duel"_s);
        QCOMPARE(model.currentCommander(), u"Mountain"_s);

        QVERIFY(model.changeCurrentDeckFormat(u"standard"_s));
        QCOMPARE(model.currentDeckTableMode(), u"modern"_s);
        QCOMPARE(model.currentMainCount(), 62);
        QCOMPARE(model.currentSideboardCount(), 0);
        QVERIFY(model.currentCommander().isEmpty());
        QVERIFY(!model.changeCurrentDeckFormat(u"alchemy"_s));
        QCOMPARE(model.lastError(), u"Choose a supported deck format."_s);
        QCOMPARE(model.currentDeckFormat(), u"standard"_s);
        QTRY_COMPARE_WITH_TIMEOUT(model.persistedGenerationForTest(),
                                  model.persistenceGenerationForTest(), 1'000);
    }

    DeckLibraryModel restored(storage.path());
    QVERIFY(restored.openDeck(deckId));
    QCOMPARE(restored.currentDeckFormat(), u"standard"_s);
    QCOMPARE(restored.currentDeckTableMode(), u"modern"_s);
    QCOMPARE(restored.currentMainCount(), 62);
    QCOMPARE(restored.currentSideboardCount(), 0);
    QVERIFY(restored.currentCommander().isEmpty());
}

void TestDeckLibrary::changesDeckToCubeWithoutLosingCards() const
{
    QTemporaryDir storage;
    QVERIFY(storage.isValid());
    DeckLibraryModel model(storage.path());
    QVERIFY(model.importDeck(u"Convertible Cube"_s, u"modern"_s,
                             u"Deck\n200 Lightning Bolt (2XM) 117\n"
                             u"Sideboard\n160 Counterspell (MH2) 267\n"_s));
    const QString deckId = model.data(model.index(0), DeckLibraryModel::IdRole).toString();
    QVERIFY(model.openDeck(deckId));

    QVERIFY(model.changeCurrentDeckFormat(u"commander"_s));
    QVERIFY(model.setCommander(u"Lightning Bolt"_s));
    QCOMPARE(model.currentCommander(), u"Lightning Bolt"_s);
    QVERIFY(model.changeCurrentDeckFormat(u"cube"_s));
    QCOMPARE(model.currentDeckFormat(), u"cube"_s);
    QCOMPARE(model.currentDeckTableMode(), u"modern"_s);
    QCOMPARE(model.currentMainCount(), 360);
    QCOMPARE(model.currentSideboardCount(), 0);
    QVERIFY(model.currentCommander().isEmpty());
    QVERIFY(!model.moveCard(u"Lightning Bolt"_s, u"2XM"_s, u"117"_s, true));
    QVERIFY(!model.addCard(u"Island"_s, {}, u"Basic Land — Island"_s, u"M21"_s, u"265"_s, true));
    QVERIFY(!model.changeCardCount(u"Lightning Bolt"_s, u"2XM"_s, u"117"_s, true, 1));
    QCOMPARE(model.matchDecks(u"cube"_s, true).size(), 1);
    QVERIFY(!model.cubeProduct(deckId).isEmpty());

    QVERIFY(model.changeCurrentDeckFormat(u"standard"_s));
    QCOMPARE(model.currentDeckFormat(), u"standard"_s);
    QCOMPARE(model.currentMainCount(), 360);
    QCOMPARE(model.currentSideboardCount(), 0);
}

void TestDeckLibrary::appliesMetadataOnlyToMatchingCardLocations() const
{
    QTemporaryDir storage;
    QVERIFY(storage.isValid());
    DeckLibraryModel model(storage.path());

    QVERIFY(model.importDeck(u"Mixed printings"_s, u"modern"_s,
                             u"Deck\n"
                             "1 Lightning Bolt (M11) 149\n"
                             "1 Lightning Bolt (2XM) 117\n"
                             "1 Island (M21) 265\n"
                             "Sideboard\n"
                             "1 Lightning Bolt (M11) 149\n"_s));
    const QString mixedId = model.data(model.index(0), DeckLibraryModel::IdRole).toString();
    QVERIFY(model.importDeck(u"Matching zones"_s, u"modern"_s,
                             u"Deck\n"
                             "1 Lightning Bolt (M11) 149\n"
                             "1 Mountain (M21) 273\n"
                             "Consider\n"
                             "1 Lightning Bolt (M11) 149\n"_s));
    const QString matchingId = model.data(model.index(0), DeckLibraryModel::IdRole).toString();
    QVERIFY(model.importDeck(u"Different printing"_s, u"modern"_s,
                             u"1 Lightning Bolt (2XM) 117\n6 Forest (M21) 272\n"_s));
    const QString differentId = model.data(model.index(0), DeckLibraryModel::IdRole).toString();
    QTRY_COMPARE_WITH_TIMEOUT(model.persistedGenerationForTest(),
                              model.persistenceGenerationForTest(), 1'000);

    model.applyCardMetadata(u"Lightning Bolt"_s, u"闪电击"_s, u"Instant"_s, {}, u"M11"_s, u"149"_s);

    const auto cardWithPrinting = [](const QVariantList &cards, const QString &setCode,
                                     const QString &collectorNumber) {
        for (const QVariant &value : cards) {
            const QVariantMap card = value.toMap();
            if (card.value(u"setCode"_s).toString() == setCode &&
                card.value(u"collectorNumber"_s).toString() == collectorNumber) {
                return card;
            }
        }
        return QVariantMap{};
    };
    const auto verifyUpdated = [](const QVariantMap &card) {
        QVERIFY(!card.isEmpty());
        QCOMPARE(card.value(u"displayName"_s).toString(), u"闪电击"_s);
        QCOMPARE(card.value(u"typeLine"_s).toString(), u"Instant"_s);
    };
    const auto verifyUnchanged = [](const QVariantMap &card) {
        QVERIFY(!card.isEmpty());
        QCOMPARE(card.value(u"displayName"_s).toString(), u"Lightning Bolt"_s);
        QVERIFY(card.value(u"typeLine"_s).toString().isEmpty());
    };

    QVERIFY(model.openDeck(mixedId));
    verifyUpdated(cardWithPrinting(model.mainCards(), u"M11"_s, u"149"_s));
    verifyUpdated(cardWithPrinting(model.sideboardCards(), u"M11"_s, u"149"_s));
    verifyUnchanged(cardWithPrinting(model.mainCards(), u"2XM"_s, u"117"_s));

    QVERIFY(model.openDeck(matchingId));
    verifyUpdated(cardWithPrinting(model.mainCards(), u"M11"_s, u"149"_s));
    verifyUpdated(cardWithPrinting(model.considerCards(), u"M11"_s, u"149"_s));

    QVERIFY(model.openDeck(differentId));
    verifyUnchanged(cardWithPrinting(model.mainCards(), u"2XM"_s, u"117"_s));

    model.flushMetadataCommitForTest();
    QTRY_COMPARE_WITH_TIMEOUT(model.persistedGenerationForTest(),
                              model.persistenceGenerationForTest(), 1'000);
}

void TestDeckLibrary::coalescesCardMetadataPersistence() const
{
    QTemporaryDir storage;
    QVERIFY(storage.isValid());
    DeckLibraryModel model(storage.path());
    QVERIFY(model.importDeck(u"Metadata batch"_s, u"modern"_s,
                             u"4 Lightning Bolt\n4 Monastery Swiftspear\n"_s));
    const QString id = model.data(model.index(0), DeckLibraryModel::IdRole).toString();
    QVERIFY(model.openDeck(id));
    QSignalSpy changedSpy(&model, &DeckLibraryModel::currentDeckChanged);
    QSignalSpy cardsChangedSpy(&model, &DeckLibraryModel::currentDeckCardsChanged);
    QSignalSpy dataChangedSpy(&model, &QAbstractItemModel::dataChanged);
    QSignalSpy resetSpy(&model, &QAbstractItemModel::modelReset);

    const QString boltImagePath = storage.filePath(u"bolt.jpg"_s);
    QFile boltImage(boltImagePath);
    QVERIFY(boltImage.open(QIODevice::WriteOnly));
    QVERIFY(boltImage.write("bolt") > 0);
    boltImage.close();
    const QString swiftspearImagePath = storage.filePath(u"swiftspear.jpg"_s);
    QFile swiftspearImage(swiftspearImagePath);
    QVERIFY(swiftspearImage.open(QIODevice::WriteOnly));
    QVERIFY(swiftspearImage.write("swiftspear") > 0);
    swiftspearImage.close();

    model.applyCardMetadata(u"Lightning Bolt"_s, u"闪电击"_s, u"Instant"_s, boltImagePath, u"M11"_s,
                            u"149"_s);
    model.applyCardMetadata(u"Monastery Swiftspear"_s, u"寺院迅矛僧"_s, u"Creature"_s,
                            swiftspearImagePath, u"KTK"_s, u"118"_s);

    QCOMPARE(changedSpy.count(), 0);
    QTRY_COMPARE_WITH_TIMEOUT(changedSpy.count(), 1, 1'000);
    QCOMPARE(cardsChangedSpy.count(), 1);
    QCOMPARE(dataChangedSpy.count(), 1);
    QCOMPARE(resetSpy.count(), 0);
    DeckLibraryModel restored(storage.path());
    QVERIFY(restored.openDeck(id));
    QVERIFY(restored.currentReady());
}

void TestDeckLibrary::backgroundMetadataSaveCannotOverwriteSynchronousEdit() const
{
    QTemporaryDir storage;
    QVERIFY(storage.isValid());
    const DeckLibraryStorage backingStorage(storage.path());
    QSemaphore backgroundStarted;
    QSemaphore releaseBackground;
    QSemaphore backgroundFinished;
    std::atomic_int saveCalls = 0;
    std::atomic_bool blockNextBackgroundSave = false;
    auto committedGeneration = std::make_shared<std::atomic<quint64>>(0);
    const auto saveDecks = [backingStorage, &backgroundStarted, &releaseBackground,
                            &backgroundFinished, &saveCalls, &blockNextBackgroundSave,
                            committedGeneration](const QVector<hexproof::client::Deck> &decks,
                                                 quint64 generation, QString *error) {
        ++saveCalls;
        const bool blocked = blockNextBackgroundSave.exchange(false);
        if (blocked) {
            backgroundStarted.release();
            releaseBackground.acquire();
        }
        const bool saved =
            backingStorage.saveDecksIfNewer(decks, generation, committedGeneration.get(), error);
        if (blocked)
            backgroundFinished.release();
        return saved;
    };

    DeckLibraryModel model(storage.path(), saveDecks);
    const auto releaseBlockedSave =
        qScopeGuard([&releaseBackground]() { releaseBackground.release(); });
    QVERIFY(model.importDeck(u"Metadata race"_s, u"modern"_s, u"8 Lightning Bolt\n"_s));
    QTRY_COMPARE_WITH_TIMEOUT(saveCalls.load(), 1, 1'000);
    QTRY_COMPARE_WITH_TIMEOUT(model.persistedGenerationForTest(),
                              model.persistenceGenerationForTest(), 1'000);
    const QString id = model.data(model.index(0), DeckLibraryModel::IdRole).toString();
    QVERIFY(model.openDeck(id));

    blockNextBackgroundSave.store(true);
    model.applyCardMetadata(u"Lightning Bolt"_s, u"闪电击"_s, u"Instant"_s, {}, u"M11"_s, u"149"_s);
    bool metadataApplied = false;
    for (const QVariant &value : model.mainCards()) {
        if (value.toMap().value(u"displayName"_s).toString() == u"闪电击"_s) {
            metadataApplied = true;
            break;
        }
    }
    QVERIFY(metadataApplied);
    QVERIFY(model.metadataCommitPendingForTest());
    QVERIFY(model.persistenceGenerationForTest() > model.persistedGenerationForTest());
    model.flushMetadataCommitForTest();
    QVERIFY(model.backgroundSaveRunningForTest());
    QTRY_COMPARE_WITH_TIMEOUT(saveCalls.load(), 2, 5'000);
    QTRY_VERIFY_WITH_TIMEOUT(backgroundStarted.available() > 0, 5'000);
    QVERIFY(backgroundStarted.tryAcquire());

    QSemaphore renameReturned;
    std::thread watchdog([&releaseBackground, &renameReturned]() {
        if (!renameReturned.tryAcquire(1, 3'000))
            releaseBackground.release();
    });
    QElapsedTimer timer;
    timer.start();
    QVERIFY(model.renameCurrentDeck(u"Newest name"_s));
    renameReturned.release();
    QVERIFY2(timer.elapsed() < 750, "structural save blocked on a background metadata write");
    watchdog.join();
    releaseBackground.release();
    QVERIFY(backgroundFinished.tryAcquire(1, 1'000));
    QTRY_COMPARE_WITH_TIMEOUT(model.persistedGenerationForTest(),
                              model.persistenceGenerationForTest(), 1'000);

    DeckLibraryModel restored(storage.path());
    QVERIFY(restored.openDeck(id));
    QCOMPARE(restored.currentDeckName(), u"Newest name"_s);
}

void TestDeckLibrary::retriesFailedBackgroundMetadataSave() const
{
    QTemporaryDir storage;
    QVERIFY(storage.isValid());
    const DeckLibraryStorage backingStorage(storage.path());
    std::atomic_int backgroundAttempts = 0;
    std::atomic_bool failMetadataSaves = false;
    const auto saveDecks = [backingStorage, &backgroundAttempts,
                            &failMetadataSaves](const QVector<hexproof::client::Deck> &decks,
                                                quint64, QString *error) {
        if (failMetadataSaves.load() && ++backgroundAttempts <= 2) {
            *error = u"Transient metadata save failure."_s;
            return false;
        }
        return backingStorage.saveDecks(decks, error);
    };

    DeckLibraryModel model(storage.path(), saveDecks);
    QVERIFY(model.importDeck(u"Metadata retry"_s, u"modern"_s, u"8 Lightning Bolt\n"_s));
    QTRY_COMPARE_WITH_TIMEOUT(model.persistedGenerationForTest(),
                              model.persistenceGenerationForTest(), 1'000);
    const QString id = model.data(model.index(0), DeckLibraryModel::IdRole).toString();
    QVERIFY(model.openDeck(id));
    QSignalSpy changedSpy(&model, &DeckLibraryModel::currentDeckChanged);

    failMetadataSaves.store(true);
    model.applyCardMetadata(u"Lightning Bolt"_s, u"闪电击"_s, u"Instant"_s, {}, u"M11"_s, u"149"_s);
    model.flushMetadataCommitForTest();
    QTRY_COMPARE_WITH_TIMEOUT(backgroundAttempts.load(), 3, 3'000);
    QTRY_COMPARE_WITH_TIMEOUT(changedSpy.count(), 1, 1'000);

    DeckLibraryModel restored(storage.path());
    QVERIFY(restored.openDeck(id));
    bool foundLocalizedName = false;
    for (const QVariant &value : restored.mainCards()) {
        if (value.toMap().value(u"displayName"_s).toString() == u"闪电击"_s) {
            foundLocalizedName = true;
            break;
        }
    }
    QVERIFY(foundLocalizedName);
}

void TestDeckLibrary::keepsMetadataDirtyAfterBoundedBackgroundRetries() const
{
    QTemporaryDir storage;
    QVERIFY(storage.isValid());
    const DeckLibraryStorage backingStorage(storage.path());
    std::atomic_int backgroundAttempts = 0;
    std::atomic_bool failMetadataSaves = false;
    const auto saveDecks = [backingStorage, &backgroundAttempts,
                            &failMetadataSaves](const QVector<hexproof::client::Deck> &decks,
                                                quint64, QString *error) {
        if (failMetadataSaves.load()) {
            ++backgroundAttempts;
            *error = u"Persistent metadata save failure."_s;
            return false;
        }
        return backingStorage.saveDecks(decks, error);
    };

    DeckLibraryModel model(storage.path(), saveDecks);
    QVERIFY(model.importDeck(u"Metadata dirty"_s, u"modern"_s, u"8 Lightning Bolt\n"_s));
    QTRY_COMPARE_WITH_TIMEOUT(model.persistedGenerationForTest(),
                              model.persistenceGenerationForTest(), 1'000);
    const QString id = model.data(model.index(0), DeckLibraryModel::IdRole).toString();
    QVERIFY(model.openDeck(id));

    failMetadataSaves.store(true);
    model.applyCardMetadata(u"Lightning Bolt"_s, u"闪电击"_s, u"Instant"_s, {}, u"M11"_s, u"149"_s);
    model.flushMetadataCommitForTest();
    QTRY_COMPARE_WITH_TIMEOUT(backgroundAttempts.load(), 3, 3'000);
    QTRY_VERIFY_WITH_TIMEOUT(model.lastError().contains(u"pending"_s), 1'000);
    QVERIFY(model.metadataCommitPendingForTest());
}

void TestDeckLibrary::designatesUpToTwoCommanders() const
{
    QTemporaryDir storage;
    QVERIFY(storage.isValid());
    DeckLibraryModel model(storage.path());
    QVERIFY(model.importDeck(u"Partners"_s, u"edh"_s,
                             u"1 Yoshimaru\n1 Keleth\n1 Rograkh\n7 Plains\n"_s));
    const QString id = model.data(model.index(0), DeckLibraryModel::IdRole).toString();
    QVERIFY(model.openDeck(id));
    QVERIFY(model.setCommander(u"Yoshimaru"_s));
    QVERIFY(model.setCommander(u"Keleth"_s));
    QCOMPARE(model.currentCommander(), u"Yoshimaru / Keleth"_s);
    QVERIFY(!model.setCommander(u"Rograkh"_s));
    QCOMPARE(model.lastError(), u"A Commander deck can designate at most two commanders."_s);

    int commanderCount = 0;
    for (const QVariant &value : model.mainCards()) {
        if (value.toMap().value(u"commander"_s).toBool())
            ++commanderCount;
    }
    QCOMPARE(commanderCount, 2);

    QVERIFY(model.setCommander(u"Yoshimaru"_s));
    QCOMPARE(model.currentCommander(), u"Keleth"_s);
}

void TestDeckLibrary::readinessRequiresAnOpeningHand() const
{
    QTemporaryDir storage;
    QVERIFY(storage.isValid());
    DeckLibraryModel model(storage.path());
    QVERIFY(model.importDeck(u"Short deck"_s, u"modern"_s, u"6 Forest (M21) 272\n"_s));
    const QString id = model.data(model.index(0), DeckLibraryModel::IdRole).toString();
    QVERIFY(model.openDeck(id));

    const QString imagePath = storage.filePath(u"forest.jpg"_s);
    QFile image(imagePath);
    QVERIFY(image.open(QIODevice::WriteOnly));
    QVERIFY(image.write("image") > 0);
    image.close();
    model.applyCardMetadata(u"Forest"_s, {}, u"Basic Land — Forest"_s, imagePath, u"M21"_s,
                            u"272"_s);

    QVERIFY(!model.currentReady());
    QCOMPARE(model.currentStatus(), u"At least 7 main-deck cards required"_s);
}

void TestDeckLibrary::preservesCorruptLibraryBeforeWriting() const
{
    QTemporaryDir storage;
    QVERIFY(storage.isValid());
    QFile library(storage.filePath(u"decks.json"_s));
    QVERIFY(library.open(QIODevice::WriteOnly));
    QCOMPARE(library.write("not json"), 8);
    library.close();

    DeckLibraryModel model(storage.path());
    QVERIFY(model.lastError().contains(u"preserved"_s));
    const QStringList backups =
        QDir(storage.path()).entryList({u"decks.json.corrupt-*"_s}, QDir::Files);
    QCOMPARE(backups.size(), 1);
    QVERIFY(model.importDeck(u"Recovered"_s, u"modern"_s, u"1 Sol Ring\n"_s));
    QTRY_VERIFY_WITH_TIMEOUT(QFile::exists(storage.filePath(u"decks.json"_s)), 1'000);
}

void TestDeckLibrary::preservesMalformedLibrarySchema() const
{
    QTemporaryDir storage;
    QVERIFY(storage.isValid());
    QFile library(storage.filePath(u"decks.json"_s));
    QVERIFY(library.open(QIODevice::WriteOnly));
    const QByteArray malformed = R"({"version":1,"decks":"not-an-array"})";
    QCOMPARE(library.write(malformed), malformed.size());
    library.close();

    DeckLibraryModel model(storage.path());
    QVERIFY(model.lastError().contains(u"preserved"_s));
    QCOMPARE(QDir(storage.path()).entryList({u"decks.json.corrupt-*"_s}, QDir::Files).size(), 1);
    QCOMPARE(model.rowCount(), 0);
}

void TestDeckLibrary::migratesLegacyTableFormatsToDeckFormats() const
{
    QTemporaryDir storage;
    QVERIFY(storage.isValid());
    QFile library(storage.filePath(u"decks.json"_s));
    QVERIFY(library.open(QIODevice::WriteOnly));
    const QByteArray legacy = R"({
        "version": 1,
        "decks": [{
            "id": "legacy-1",
            "name": "Legacy generic table deck",
            "format": "modern",
            "createdAt": "2026-08-17T00:00:00Z",
            "updatedAt": "2026-08-17T00:00:00Z",
            "mainboard": [{"name": "Plains", "count": 7}],
            "sideboard": []
        }]
    })";
    QCOMPARE(library.write(legacy), legacy.size());
    library.close();

    DeckLibraryModel model(storage.path());
    QCOMPARE(model.rowCount(), 1);
    const QString id = model.data(model.index(0), DeckLibraryModel::IdRole).toString();
    QVERIFY(model.openDeck(id));
    QCOMPARE(model.currentDeckTableMode(), u"modern"_s);
    QCOMPARE(model.currentDeckFormat(), u"custom"_s);
}

void TestDeckLibrary::preservesCorruptPreferencesBeforeWriting() const
{
    QTemporaryDir storage;
    QVERIFY(storage.isValid());
    QFile settings(storage.filePath(u"settings.json"_s));
    QVERIFY(settings.open(QIODevice::WriteOnly));
    QCOMPARE(settings.write("not json"), 8);
    settings.close();

    ClientPreferencesModel model(storage.path());
    QCOMPARE(QDir(storage.path()).entryList({u"settings.json.corrupt-*"_s}, QDir::Files).size(), 1);
    QCOMPARE(model.uiLanguage(), u"en"_s);
    QCOMPARE(model.interfaceScale(), 1.0);

    // The damaged file must not block later writes.
    model.setUiLanguage(u"zh"_s);
    QCOMPARE(ClientPreferencesModel(storage.path()).uiLanguage(), u"zh"_s);
}

void TestDeckLibrary::keepsDamagedPreferencesWhenRenameFails() const
{
    QTemporaryDir storage;
    QVERIFY(storage.isValid());
    const QString settingsPath = storage.filePath(u"settings.json"_s);
    QFile settings(settingsPath);
    QVERIFY(settings.open(QIODevice::WriteOnly));
    QCOMPARE(settings.write("not json"), 8);
    settings.close();

    const QFileDevice::Permissions writable = QFile::permissions(storage.path());
    const auto restorePermissions =
        qScopeGuard([&] { QFile::setPermissions(storage.path(), writable); });
    QVERIFY(QFile::setPermissions(storage.path(), QFileDevice::ReadOwner | QFileDevice::ExeOwner));

    ClientPreferencesModel model(storage.path());
    QVERIFY(QFile::setPermissions(storage.path(), writable));

    if (!QFile::exists(settingsPath)) {
        QSKIP("The filesystem still renamed the damaged preferences file.");
    }

    model.setUiLanguage(u"zh"_s);
    QCOMPARE(model.uiLanguage(), u"en"_s);
    QVERIFY(!model.lastError().isEmpty());

    QFile remaining(settingsPath);
    QVERIFY(remaining.open(QIODevice::ReadOnly));
    QCOMPARE(remaining.readAll(), QByteArray("not json"));
}

void TestDeckLibrary::storesUiAndCardLanguagesSeparately() const
{
    QTemporaryDir storage;
    QVERIFY(storage.isValid());
    {
        ClientPreferencesModel model(storage.path());
        model.setUiLanguage(u"zh"_s);
        QCOMPARE(model.uiLanguage(), u"zh"_s);
        QCOMPARE(model.cardLanguage(), u"en"_s);
        QSignalSpy languageSpy(&model, &ClientPreferencesModel::cardLanguageChanged);
        model.setCardLanguage(u"zh"_s);
        QCOMPARE(model.cardLanguage(), u"zh"_s);
        QCOMPARE(languageSpy.count(), 1);
    }

    ClientPreferencesModel restored(storage.path());
    QCOMPARE(restored.uiLanguage(), u"zh"_s);
    QCOMPARE(restored.cardLanguage(), u"zh"_s);
}

void TestDeckLibrary::storesCardArtProviderPreference() const
{
    QTemporaryDir storage;
    QVERIFY(storage.isValid());
    {
        ClientPreferencesModel model(storage.path());
        QCOMPARE(model.cardArtProvider(), u"auto"_s);
        QSignalSpy preferenceSpy(&model, &ClientPreferencesModel::cardArtProviderChanged);
        model.setCardArtProvider(u"mtgch"_s);
        QCOMPARE(model.cardArtProvider(), u"mtgch"_s);
        QCOMPARE(preferenceSpy.count(), 1);
    }

    ClientPreferencesModel restored(storage.path());
    QCOMPARE(restored.cardArtProvider(), u"mtgch"_s);
    restored.setCardArtProvider(u"unsupported"_s);
    QCOMPARE(restored.cardArtProvider(), u"auto"_s);
}

void TestDeckLibrary::storesLocalArtReusePreference() const
{
    QTemporaryDir storage;
    QVERIFY(storage.isValid());
    {
        ClientPreferencesModel model(storage.path());
        QVERIFY(model.reuseLocalCardArt());
        QSignalSpy preferenceSpy(&model, &ClientPreferencesModel::reuseLocalCardArtChanged);
        model.setReuseLocalCardArt(false);
        QVERIFY(!model.reuseLocalCardArt());
        QCOMPARE(preferenceSpy.count(), 1);
    }

    ClientPreferencesModel restored(storage.path());
    QVERIFY(!restored.reuseLocalCardArt());
}

void TestDeckLibrary::storesPackOpeningAnimationPreference() const
{
    QTemporaryDir storage;
    QVERIFY(storage.isValid());
    {
        ClientPreferencesModel model(storage.path());
        QVERIFY(model.animatePackOpenings());
        QSignalSpy preferenceSpy(&model, &ClientPreferencesModel::animatePackOpeningsChanged);
        model.setAnimatePackOpenings(false);
        QVERIFY(!model.animatePackOpenings());
        QCOMPARE(preferenceSpy.count(), 1);
    }

    ClientPreferencesModel restored(storage.path());
    QVERIFY(!restored.animatePackOpenings());
}

void TestDeckLibrary::ignoresRemovedThemePreferences() const
{
    for (const QString &themeId : {u"glass"_s, u"ember"_s}) {
        QTemporaryDir storage;
        QVERIFY(storage.isValid());
        QFile settings(storage.filePath(u"settings.json"_s));
        QVERIFY(settings.open(QIODevice::WriteOnly));
        const QJsonObject legacy{{u"version"_s, 13},
                                 {u"themeId"_s, themeId},
                                 {u"reducedMotion"_s, true},
                                 {u"uiLanguage"_s, u"zh"_s},
                                 {u"cardLanguage"_s, u"en"_s},
                                 {u"interfaceScale"_s, 1.25},
                                 {u"animatePackOpenings"_s, false}};
        QVERIFY(settings.write(QJsonDocument(legacy).toJson()) > 0);
        settings.close();

        ClientPreferencesModel model(storage.path());
        QCOMPARE(model.uiLanguage(), u"zh"_s);
        QCOMPARE(model.cardLanguage(), u"en"_s);
        QCOMPARE(model.interfaceScale(), 1.25);
        QVERIFY(!model.animatePackOpenings());
        QVERIFY(!model.property("themeId").isValid());
        QVERIFY(!model.property("reducedMotion").isValid());
        model.setReuseLocalCardArt(false);
        QVERIFY(model.lastError().isEmpty());
        QVERIFY(settings.open(QIODevice::ReadOnly));
        const auto saved = QJsonDocument::fromJson(settings.readAll()).object();
        QVERIFY(!saved.contains(u"themeId"_s));
        QVERIFY(!saved.contains(u"reducedMotion"_s));
        QCOMPARE(saved.value(u"uiLanguage"_s).toString(), u"zh"_s);
        QCOMPARE(saved.value(u"cardLanguage"_s).toString(), u"en"_s);
        QCOMPARE(saved.value(u"interfaceScale"_s).toDouble(), 1.25);
        QCOMPARE(saved.value(u"animatePackOpenings"_s).toBool(), false);
    }
}

void TestDeckLibrary::storesSponsorAnnouncementAcknowledgement() const
{
    QTemporaryDir storage;
    QVERIFY(storage.isValid());
    {
        ClientPreferencesModel model(storage.path());
        QVERIFY(!model.sponsorAnnouncementSeen(u"founding-sponsors-2026-09"_s));
        QVERIFY(!model.acknowledgeSponsorAnnouncement({}));
        QVERIFY(model.acknowledgeSponsorAnnouncement(u" founding-sponsors-2026-09 "_s));
        QVERIFY(model.sponsorAnnouncementSeen(u"founding-sponsors-2026-09"_s));
    }

    ClientPreferencesModel restored(storage.path());
    QVERIFY(restored.sponsorAnnouncementSeen(u"founding-sponsors-2026-09"_s));
    QVERIFY(!restored.sponsorAnnouncementSeen(u"future-sponsor-announcement"_s));
}

void TestDeckLibrary::storesCardArtRepairNoticeAcknowledgement() const
{
    QTemporaryDir storage;
    QVERIFY(storage.isValid());
    {
        ClientPreferencesModel model(storage.path());
        QVERIFY(!model.cardArtRepairNoticeSeen(1));
        QVERIFY(!model.acknowledgeCardArtRepairNotice(0));
        QVERIFY(model.acknowledgeCardArtRepairNotice(1));
        QVERIFY(model.cardArtRepairNoticeSeen(1));
    }

    ClientPreferencesModel restored(storage.path());
    QVERIFY(restored.cardArtRepairNoticeSeen(1));
    QVERIFY(!restored.cardArtRepairNoticeSeen(2));
}

void TestDeckLibrary::storesAndClampsInterfaceScale() const
{
    QTemporaryDir storage;
    QVERIFY(storage.isValid());
    {
        ClientPreferencesModel model(storage.path());
        QCOMPARE(model.interfaceScale(), 1.0);
        QSignalSpy scaleSpy(&model, &ClientPreferencesModel::interfaceScaleChanged);
        model.setInterfaceScale(1.24);
        QCOMPARE(model.interfaceScale(), 1.25);
        QCOMPARE(scaleSpy.count(), 1);
    }

    ClientPreferencesModel restored(storage.path());
    QCOMPARE(restored.interfaceScale(), 1.25);
    restored.setInterfaceScale(0.1);
    QCOMPARE(restored.interfaceScale(), 0.75);
    restored.setInterfaceScale(9.0);
    QCOMPARE(restored.interfaceScale(), 1.5);
}

void TestDeckLibrary::storesTableLayoutPreferences() const
{
    QTemporaryDir storage;
    QVERIFY(storage.isValid());
    {
        ClientPreferencesModel model(storage.path());
        QVERIFY(model.tableShowPlayers());
        QVERIFY(model.tableShowShared());
        QVERIFY(model.tableShowInspector());
        QVERIFY(model.tableShowGameLog());
        QCOMPARE(model.tableCounterCount(), 0);
        QCOMPARE(model.tableOverviewCardScale(), 0.0);
        QCOMPARE(model.tableFocusCardScale(), 0.0);
        QCOMPARE(model.tableBattlefieldControlX(), -1.0);
        QCOMPARE(model.tableBattlefieldControlY(), -1.0);
        model.setTableShowPlayers(false);
        model.setTableShowShared(false);
        model.setTableShowInspector(false);
        model.setTableShowGameLog(false);
        model.setTableCounterCount(99);
        model.setTableOverviewCardScale(0.72);
        model.setTableFocusCardScale(1.17);
        model.setTableBattlefieldControlPosition(0.25, 0.75);
        QCOMPARE(model.tableCounterCount(), 7);
        QCOMPARE(model.tableOverviewCardScale(), 0.7);
        QCOMPARE(model.tableFocusCardScale(), 1.15);
        QCOMPARE(model.tableBattlefieldControlX(), 0.25);
        QCOMPARE(model.tableBattlefieldControlY(), 0.75);
    }

    ClientPreferencesModel restored(storage.path());
    QVERIFY(!restored.tableShowPlayers());
    QVERIFY(!restored.tableShowShared());
    QVERIFY(!restored.tableShowInspector());
    QVERIFY(!restored.tableShowGameLog());
    QCOMPARE(restored.tableCounterCount(), 7);
    QCOMPARE(restored.tableOverviewCardScale(), 0.7);
    QCOMPARE(restored.tableFocusCardScale(), 1.15);
    QCOMPARE(restored.tableBattlefieldControlX(), 0.25);
    QCOMPARE(restored.tableBattlefieldControlY(), 0.75);
    restored.setTableCounterCount(-3);
    QCOMPARE(restored.tableCounterCount(), 0);
    restored.setTableOverviewCardScale(0.1);
    restored.setTableFocusCardScale(9.0);
    QCOMPARE(restored.tableOverviewCardScale(), 0.5);
    QCOMPARE(restored.tableFocusCardScale(), 1.25);
    restored.setTableOverviewCardScale(0.0);
    QCOMPARE(restored.tableOverviewCardScale(), 0.0);
    restored.setTableBattlefieldControlPosition(-2.0, 8.0);
    QCOMPARE(restored.tableBattlefieldControlX(), -1.0);
    QCOMPARE(restored.tableBattlefieldControlY(), 1.0);
}

void TestDeckLibrary::storesCustomShortcutPreferences() const
{
    QTemporaryDir storage;
    QVERIFY(storage.isValid());
    {
        ClientPreferencesModel model(storage.path());
        QCOMPARE(model.shortcutSequences(u"app.fullscreen"_s), QStringList{u"F11"_s});
        QCOMPARE(model.shortcutDisplay(u"table.help"_s), u"F1 / ?"_s);
        QVERIFY(!model.shortcutCustomized(u"app.fullscreen"_s));

        QSignalSpy shortcutSpy(&model, &ClientPreferencesModel::shortcutsChanged);
        QVERIFY(model.setShortcutSequence(u"app.fullscreen"_s, u"Ctrl+Alt+F"_s));
        QCOMPARE(model.shortcutSequences(u"app.fullscreen"_s), QStringList{u"Ctrl+Alt+F"_s});
        QVERIFY(model.shortcutCustomized(u"app.fullscreen"_s));
        QCOMPARE(model.shortcutRevision(), 1);
        QCOMPARE(shortcutSpy.count(), 1);

        QVERIFY(model.setShortcutSequence(u"table.help"_s, {}));
        QVERIFY(model.shortcutSequences(u"table.help"_s).isEmpty());
        QVERIFY(model.shortcutCustomized(u"table.help"_s));
    }

    ClientPreferencesModel restored(storage.path());
    QCOMPARE(restored.shortcutSequences(u"app.fullscreen"_s), QStringList{u"Ctrl+Alt+F"_s});
    QVERIFY(restored.shortcutSequences(u"table.help"_s).isEmpty());
    QVERIFY(restored.resetShortcut(u"app.fullscreen"_s));
    QCOMPARE(restored.shortcutSequences(u"app.fullscreen"_s), QStringList{u"F11"_s});
    QVERIFY(restored.resetAllShortcuts());
    QCOMPARE(restored.shortcutSequences(u"table.help"_s), (QStringList{u"F1"_s, u"?"_s}));
}

void TestDeckLibrary::rejectsShortcutConflictsAndInvalidSequences() const
{
    QTemporaryDir storage;
    QVERIFY(storage.isValid());
    ClientPreferencesModel model(storage.path());

    QCOMPARE(model.shortcutConflictAction(u"app.fullscreen"_s, u"Ctrl+Right"_s),
             u"table.advancePhase"_s);
    QVERIFY(!model.setShortcutSequence(u"app.fullscreen"_s, u"Ctrl+Right"_s));
    QVERIFY(model.lastError().contains(u"already assigned"_s));
    QCOMPARE(model.shortcutSequences(u"app.fullscreen"_s), QStringList{u"F11"_s});

    QVERIFY(!model.setShortcutSequence(u"app.fullscreen"_s, u"Ctrl+"_s));
    QVERIFY(model.lastError().contains(u"valid single"_s));
    QVERIFY(!model.setShortcutSequence(u"missing.action"_s, u"Ctrl+Alt+F"_s));
    QVERIFY(model.lastError().contains(u"Unknown"_s));

    QVERIFY(model.setShortcutSequence(u"table.advancePhase"_s, u"Ctrl+Alt+Y"_s));
    QVERIFY(model.setShortcutSequence(u"app.fullscreen"_s, u"Ctrl+Right"_s));
    QVERIFY(!model.resetShortcut(u"table.advancePhase"_s));
    QVERIFY(model.lastError().contains(u"default shortcut"_s));
    QVERIFY(model.resetAllShortcuts());
    QCOMPARE(model.keyEventSequence(Qt::Key_J, Qt::ControlModifier | Qt::AltModifier),
             u"Ctrl+Alt+J"_s);
    QVERIFY(model.keyEventSequence(Qt::Key_Control, Qt::ControlModifier).isEmpty());
}

void TestDeckLibrary::reportsEditorFailuresThroughLastError() const
{
    QTemporaryDir storage;
    QVERIFY(storage.isValid());
    DeckLibraryModel model(storage.path());
    QVERIFY(model.importDeck(u"Burn"_s, u"modern"_s, u"4 Lightning Bolt\n"_s));
    const QString id = model.data(model.index(0), DeckLibraryModel::IdRole).toString();
    QVERIFY(model.openDeck(id));

    QVERIFY(!model.addCard({}, {}, {}, {}, {}, false));
    QVERIFY(model.lastError().contains(u"Card name"_s));
    QVERIFY(!model.changeCardCount(u"Missing Card"_s, {}, {}, false, 1));
    QVERIFY(model.lastError().contains(u"not in the deck"_s));
}

void TestDeckLibrary::buildsPrivateMatchDeckPayload() const
{
    QTemporaryDir storage;
    QVERIFY(storage.isValid());
    DeckLibraryModel model(storage.path());
    QVERIFY(model.importDeck(u"Burn"_s, u"modern"_s, u"7 Lightning Bolt (M11) 149\n"_s));
    const QString id = model.data(model.index(0), DeckLibraryModel::IdRole).toString();
    QVERIFY(model.openDeck(id));

    const QVariantList preloadOptions = model.matchDecks(u"modern"_s);
    QCOMPARE(preloadOptions.size(), 1);
    QVERIFY(!preloadOptions.first().toMap().value(u"ready"_s).toBool());
    QVERIFY(!preloadOptions.first().toMap().value(u"artReady"_s).toBool());
    QVERIFY(model.deckForMatch(id).isEmpty());

    const QVariantList backgroundOptions = model.matchDecks(u"modern"_s, true);
    QCOMPARE(backgroundOptions.size(), 1);
    QVERIFY(backgroundOptions.first().toMap().value(u"ready"_s).toBool());
    QVERIFY(!backgroundOptions.first().toMap().value(u"artReady"_s).toBool());
    QVERIFY(!model.deckForMatch(id, true).isEmpty());

    const QString imagePath = storage.filePath(u"bolt.jpg"_s);
    QFile image(imagePath);
    QVERIFY(image.open(QIODevice::WriteOnly));
    QVERIFY(image.write("image") > 0);
    image.close();
    model.applyCardMetadata(u"Lightning Bolt"_s, u"闪电击"_s, u"Instant"_s, imagePath, u"M11"_s,
                            u"149"_s);

    const QVariantList options = model.matchDecks(u"modern"_s);
    QCOMPARE(options.size(), 1);
    QVERIFY(options.first().toMap().value(u"ready"_s).toBool());
    QCOMPARE(model.matchDecks(u"edh"_s).size(), 0);

    const QVariantMap payload = model.deckForMatch(id);
    QCOMPARE(payload.value(u"name"_s).toString(), u"Burn"_s);
    QCOMPARE(payload.value(u"format"_s).toString(), u"modern"_s);
    QVERIFY(!payload.contains(u"deckId"_s));
    const QVariantMap card = payload.value(u"mainboard"_s).toList().first().toMap();
    QCOMPARE(card.value(u"name"_s).toString(), u"Lightning Bolt"_s);
    QCOMPARE(card.value(u"count"_s).toInt(), 7);
    QCOMPARE(card.value(u"setCode"_s).toString(), u"M11"_s);
    QCOMPARE(card.value(u"collectorNumber"_s).toString(), u"149"_s);
    QCOMPARE(card.value(u"typeLine"_s).toString(), u"Instant"_s);
    QVERIFY(!card.contains(u"imageSource"_s));
    QVERIFY(!card.contains(u"localizedName"_s));
}
