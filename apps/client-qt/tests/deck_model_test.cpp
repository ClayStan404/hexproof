// SPDX-License-Identifier: GPL-2.0-only
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
        QVERIFY(model.changeCardCount(u"Lightning Bolt"_s, false, 1));
        QCOMPARE(model.currentCardCopies(u"Lightning Bolt"_s), 5);
        QVERIFY(model.moveCard(u"Lightning Bolt"_s, true));
        QCOMPARE(model.currentMainCount(), 8);
        QCOMPARE(model.currentSideboardCount(), 3);
        QVERIFY(model.changeCardCount(u"Lightning Bolt"_s, true, 1));
        QVERIFY(
            model.addCard(u"Sol Ring"_s, u"Sol Ring"_s, u"Artifact"_s, u"CMM"_s, u"396"_s, false));
        QCOMPARE(model.currentMainCount(), 9);
        QCOMPARE(cachingSpy.count(), 1);
        const QVariantList added = cachingSpy.last().first().toList();
        QCOMPARE(added.size(), 1);
        QCOMPARE(added.first().toMap().value(u"name"_s).toString(), u"Sol Ring"_s);
        QVERIFY(model.setCardPrinting(u"Sol Ring"_s, false, u"阳光戒"_s, u"神器"_s, u"2X2"_s,
                                      u"308"_s));
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

    QVERIFY(model.changeCardCount(u"Forest"_s, false, -1));
    QTRY_COMPARE(validationSpy.count(), 1);
    requests = validationSpy.takeFirst().constFirst().toList();
    QCOMPARE(requests.size(), 1);
    QCOMPARE(requests.constFirst().toMap().value(u"deckId"_s).toString(), secondId);
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
    QVERIFY(!model.moveCard(u"Lightning Bolt"_s, true));
    QVERIFY(!model.addCard(u"Island"_s, {}, u"Basic Land — Island"_s, u"M21"_s, u"265"_s, true));
    QVERIFY(!model.changeCardCount(u"Lightning Bolt"_s, true, 1));
    QCOMPARE(model.matchDecks(u"cube"_s, true).size(), 1);
    QVERIFY(!model.cubeProduct(deckId).isEmpty());

    QVERIFY(model.changeCurrentDeckFormat(u"standard"_s));
    QCOMPARE(model.currentDeckFormat(), u"standard"_s);
    QCOMPARE(model.currentMainCount(), 360);
    QCOMPARE(model.currentSideboardCount(), 0);
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
        QCOMPARE(model.cardArtProvider(), u"scryfall"_s);
        QSignalSpy preferenceSpy(&model, &ClientPreferencesModel::cardArtProviderChanged);
        model.setCardArtProvider(u"mtgch"_s);
        QCOMPARE(model.cardArtProvider(), u"mtgch"_s);
        QCOMPARE(preferenceSpy.count(), 1);
    }

    ClientPreferencesModel restored(storage.path());
    QCOMPARE(restored.cardArtProvider(), u"mtgch"_s);
    restored.setCardArtProvider(u"unsupported"_s);
    QCOMPARE(restored.cardArtProvider(), u"scryfall"_s);
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

        QVERIFY(model.setShortcutSequence(u"replay.speedHalf"_s, {}));
        QVERIFY(model.shortcutSequences(u"replay.speedHalf"_s).isEmpty());
        QVERIFY(model.shortcutCustomized(u"replay.speedHalf"_s));
    }

    ClientPreferencesModel restored(storage.path());
    QCOMPARE(restored.shortcutSequences(u"app.fullscreen"_s), QStringList{u"Ctrl+Alt+F"_s});
    QVERIFY(restored.shortcutSequences(u"replay.speedHalf"_s).isEmpty());
    QVERIFY(restored.resetShortcut(u"app.fullscreen"_s));
    QCOMPARE(restored.shortcutSequences(u"app.fullscreen"_s), QStringList{u"F11"_s});
    QVERIFY(restored.resetAllShortcuts());
    QCOMPARE(restored.shortcutSequences(u"replay.speedHalf"_s), QStringList{u"1"_s});
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
    QVERIFY(!model.changeCardCount(u"Missing Card"_s, false, 1));
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
