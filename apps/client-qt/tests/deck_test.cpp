// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

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

#include "deck_test.h"

void TestDeckLibrary::categorizesLocalizedTypeLines() const
{
    QCOMPARE(hexproof::client::cardCategory(u"基本地 — 山脉"_s), u"Lands"_s);
    QCOMPARE(hexproof::client::cardCategory(u"神器生物 — 魔像"_s), u"Creatures"_s);
    QCOMPARE(hexproof::client::cardCategory(u"生物 ～ 地精"_s), u"Creatures"_s);
    QCOMPARE(hexproof::client::cardCategory(u"鹏洛客 — 杰斯"_s), u"Planeswalkers"_s);
    QCOMPARE(hexproof::client::cardCategory(u"结界"_s), u"Enchantments"_s);
    QCOMPARE(hexproof::client::cardCategory(u"瞬间"_s), u"Spells"_s);
    QCOMPARE(hexproof::client::cardCategory(u"Sorcery"_s), u"Spells"_s);
}

void TestDeckLibrary::benchmarkCommanderDeckParsing() const
{
    QString deckText = u"Commander\n1 Atraxa, Grand Unifier\nDeck\n"_s;
    for (int index = 0; index < 99; ++index)
        deckText += u"1 Benchmark Card %1\n"_s.arg(index);

    hexproof::client::DeckParseResult parsed;
    QBENCHMARK
    {
        parsed = DeckParser::parse(deckText, true);
    }
    QVERIFY2(parsed.ok(), qPrintable(parsed.error));
    QCOMPARE(hexproof::client::cardCount(parsed.deck.mainboard), 100);
    QCOMPARE(parsed.deck.commanders, QStringList{u"Atraxa, Grand Unifier"_s});
}

void TestDeckLibrary::benchmarkEmptyLibraryStartup() const
{
    QTemporaryDir storage;
    QVERIFY(storage.isValid());
    QBENCHMARK
    {
        DeckLibraryModel model(storage.path());
        QCOMPARE(model.rowCount(), 0);
    }
}

void TestDeckLibrary::importsPersistsAndBuildsCubeProduct() const
{
    QTemporaryDir storage;
    QVERIFY(storage.isValid());
    const QString cards = u"Deck\n"
                          "180 Lightning Bolt (2XM) 117\n"
                          "Sideboard\n"
                          "180 Counterspell (MH2) 267\n"_s;

    QString cubeId;
    {
        DeckLibraryModel model(storage.path());
        QVERIFY2(model.importDeck(u"Test Cube"_s, u"cube"_s, cards), qPrintable(model.lastError()));
        QCOMPARE(model.rowCount(), 1);
        cubeId = model.data(model.index(0), DeckLibraryModel::IdRole).toString();
        QCOMPARE(model.data(model.index(0), DeckLibraryModel::FormatRole).toString(), u"cube"_s);
        QCOMPARE(model.data(model.index(0), DeckLibraryModel::MainCountRole).toInt(), 360);
        QCOMPARE(model.data(model.index(0), DeckLibraryModel::SideboardCountRole).toInt(), 0);

        const QVariantList matches = model.matchDecks(u"cube"_s, true);
        QCOMPARE(matches.size(), 1);
        QVERIFY(matches.first().toMap().value(u"ready"_s).toBool());
        QVERIFY(matches.first().toMap().value(u"exactPrintings"_s).toBool());

        const QVariantMap product = model.cubeProduct(cubeId);
        QCOMPARE(product.value(u"productType"_s).toString(), u"cube"_s);
        QCOMPARE(product.value(u"cardsPerPack"_s).toInt(), 0);
        const QVariantList productCards =
            product.value(u"sheets"_s).toList().first().toMap().value(u"cards"_s).toList();
        QCOMPARE(productCards.size(), 2);
        QCOMPARE(productCards.first().toMap().value(u"weight"_s).toInt(), 180);
        QVERIFY(model.exportDeckText(cubeId).contains(u"180 Lightning Bolt (2XM) 117"_s));

        model.flushMetadataCommitForTest();
        QTRY_COMPARE_WITH_TIMEOUT(model.persistedGenerationForTest(),
                                  model.persistenceGenerationForTest(), 1'000);
    }

    DeckLibraryModel restored(storage.path());
    QCOMPARE(restored.rowCount(), 1);
    QCOMPARE(restored.data(restored.index(0), DeckLibraryModel::MainCountRole).toInt(), 360);
    QVERIFY(restored.deleteDeck(cubeId));
    QCOMPARE(restored.rowCount(), 0);
}

void TestDeckLibrary::keepsIncompleteCubeEditableButUnplayable() const
{
    QTemporaryDir storage;
    QVERIFY(storage.isValid());

    DeckLibraryModel model(storage.path());
    QVERIFY(model.importDeck(u"Unresolved Cube"_s, u"cube"_s, u"40 Lightning Bolt\n"_s));
    const QString cubeId = model.data(model.index(0), DeckLibraryModel::IdRole).toString();
    const QVariantList unresolved = model.matchDecks(u"cube"_s, true);
    QCOMPARE(unresolved.size(), 1);
    QVERIFY(!unresolved.first().toMap().value(u"ready"_s).toBool());
    QVERIFY(!unresolved.first().toMap().value(u"exactPrintings"_s).toBool());
    QVERIFY(unresolved.first()
                .toMap()
                .value(u"status"_s)
                .toString()
                .contains(u"exact printing"_s, Qt::CaseInsensitive));
    QVERIFY(model.cubeProduct(cubeId).isEmpty());

    QVERIFY(model.openDeck(cubeId));
    QVERIFY(!model.addCard(u"Counterspell"_s, {}, u"Instant"_s, u"MH2"_s, u"267"_s, true));
    QVERIFY(
        model.setCardPrinting(u"Lightning Bolt"_s, false, {}, u"Instant"_s, u"2XM"_s, u"117"_s));
    QVERIFY(model.changeCardCount(u"Lightning Bolt"_s, false, 140));
    QCOMPARE(model.currentMainCount(), 180);
    QVERIFY(!model.cubeProduct(cubeId).isEmpty());
}

void TestDeckLibrary::migratesLegacyCubesIntoDeckLibrary() const
{
    QTemporaryDir storage;
    QVERIFY(storage.isValid());
    QFile file(QDir(storage.path()).filePath(u"cubes.json"_s));
    QVERIFY(file.open(QIODevice::WriteOnly));
    file.write(R"({
        "schemaVersion": 1,
        "cubes": [{
            "id": "legacy", "name": "Legacy Cube", "cardsPerPack": 15,
            "cardCount": 40,
            "cards": [{"name": "Lightning Bolt", "setCode": "CUBE",
                       "collectorNumber": "1", "weight": 40}]
        }]
    })");
    file.close();

    DeckLibraryModel model(storage.path());
    QCOMPARE(model.rowCount(), 1);
    QCOMPARE(model.data(model.index(0), DeckLibraryModel::FormatRole).toString(), u"cube"_s);
    const QString cubeId = model.data(model.index(0), DeckLibraryModel::IdRole).toString();
    QCOMPARE(cubeId, u"legacy-cube-legacy"_s);
    QVERIFY(model.cubeProduct(cubeId).isEmpty());
    QVERIFY(model.exportDeckText(cubeId).contains(u"(CUBE) 1"_s));
    QVERIFY(!QFile::exists(file.fileName()));
    QCOMPARE(QDir(storage.path()).entryList({u"cubes.json.migrated-*"_s}, QDir::Files).size(), 1);

    DeckLibraryModel restored(storage.path());
    QCOMPARE(restored.rowCount(), 1);
    QCOMPARE(restored.data(restored.index(0), DeckLibraryModel::IdRole).toString(), cubeId);
}

void TestDeckLibrary::parsesMoxfieldAndPlainSections() const
{
    const auto parsed = DeckParser::parse(uR"(
Commander
1 Atraxa, Praetors' Voice (2X2) 183 *CMDR*

Deck
4 Sol Ring (CMM) 396
2x Arcane Signet
SB: 2 Negate (M20) 69

Maybeboard
1 Doubling Season
)"_s);

    QVERIFY2(parsed.ok(), qPrintable(parsed.error));
    QCOMPARE(parsed.deck.commanders, QStringList{u"Atraxa, Praetors' Voice"_s});
    QCOMPARE(parsed.deck.mainboard.size(), 3);
    QCOMPARE(parsed.deck.sideboard.size(), 1);
    QCOMPARE(hexproof::client::cardCount(parsed.deck.mainboard), 7);
    QCOMPARE(hexproof::client::cardCount(parsed.deck.sideboard), 2);
    QCOMPARE(parsed.deck.mainboard.at(1).setCode, u"CMM"_s);
    QCOMPARE(parsed.deck.mainboard.at(1).collectorNumber, u"396"_s);
}

void TestDeckLibrary::formatsExplicitDeckSideboardAndCommanderSections() const
{
    hexproof::client::Deck deck;
    deck.commanders = {u"Atraxa, Praetors' Voice"_s};
    deck.mainboard = {
        {u"Sol Ring"_s, {}, u"CMM"_s, u"396"_s, {}, {}, 1},
        {u"Atraxa, Praetors' Voice"_s, {}, u"2X2"_s, u"183"_s, {}, {}, 1},
        {u"Forest"_s, {}, {}, {}, {}, {}, 99},
    };
    deck.sideboard = {{u"Negate"_s, {}, u"M20"_s, u"69"_s, {}, {}, 2}};
    deck.tokens = {{u"Beast"_s, {}, u"TDMU"_s, u"1"_s, {}, {}, {}, {}}};

    const QString text = DeckParser::format(deck);
    QCOMPARE(text, u"Deck\n"
                   "1 Sol Ring (CMM) 396\n"
                   "99 Forest\n"
                   "\n"
                   "Sideboard\n"
                   "2 Negate (M20) 69\n"
                   "\n"
                   "Commander\n"
                   "1 Atraxa, Praetors' Voice (2X2) 183 *CMDR*\n"_s);
    QVERIFY(!text.contains(u"Beast"_s));
}

void TestDeckLibrary::roundTripsFormattedDeckTextThroughTheParser() const
{
    hexproof::client::Deck deck;
    deck.commanders = {u"Thrasios, Triton Hero"_s, u"Tymna the Weaver"_s};
    deck.mainboard = {
        {u"Thrasios, Triton Hero"_s, {}, u"C16"_s, u"46"_s, {}, {}, 1},
        {u"Sol Ring"_s, {}, u"CMM"_s, u"396"_s, {}, {}, 1},
        {u"Tymna the Weaver"_s, {}, u"C16"_s, u"48"_s, {}, {}, 1},
        {u"Island"_s, {}, {}, {}, {}, {}, 30},
    };
    deck.sideboard = {{u"Wear // Tear"_s, {}, u"DGM"_s, u"135"_s, {}, {}, 1}};

    const auto parsed = DeckParser::parse(DeckParser::format(deck));
    QVERIFY2(parsed.ok(), qPrintable(parsed.error));
    QCOMPARE(parsed.deck.commanders,
             QStringList({u"Thrasios, Triton Hero"_s, u"Tymna the Weaver"_s}));
    QCOMPARE(hexproof::client::cardCount(parsed.deck.mainboard), 33);
    QCOMPARE(parsed.deck.mainboard.size(), 4);
    QCOMPARE(parsed.deck.sideboard.size(), 1);
    QCOMPARE(parsed.deck.sideboard.at(0).name, u"Wear // Tear"_s);
    QCOMPARE(parsed.deck.sideboard.at(0).setCode, u"DGM"_s);
    QCOMPARE(parsed.deck.sideboard.at(0).collectorNumber, u"135"_s);

    QStringList mainNames;
    for (const auto &card : parsed.deck.mainboard)
        mainNames.append(card.name);
    QVERIFY(mainNames.contains(u"Sol Ring"_s));
    QVERIFY(mainNames.contains(u"Island"_s));
    QVERIFY(mainNames.contains(u"Thrasios, Triton Hero"_s));
    QVERIFY(mainNames.contains(u"Tymna the Weaver"_s));
}

void TestDeckLibrary::exportsDeckTextAndSavesUtf8File() const
{
    QTemporaryDir storage;
    QVERIFY(storage.isValid());
    DeckLibraryModel model(storage.path());
    QVERIFY(model.importDeck(u"Burn"_s, u"modern"_s,
                             u"Deck\n4 Lightning Bolt (M11) 149\n"
                             "Sideboard\n2 Wear // Tear\n"
                             "Commander\n"_s));
    QCOMPARE(model.rowCount(), 1);
    const QString deckId = model.data(model.index(0, 0), DeckLibraryModel::IdRole).toString();
    QVERIFY(!deckId.isEmpty());

    const QString text = model.exportDeckText(deckId);
    QVERIFY(text.startsWith(u"Deck\n"_s));
    QVERIFY(text.contains(u"Sideboard\n"_s));
    QVERIFY(text.contains(u"Commander\n"_s));
    QVERIFY(text.contains(u"4 Lightning Bolt (M11) 149"_s));
    QVERIFY(text.contains(u"2 Wear // Tear"_s));

    const QString path = storage.filePath(u"burn.txt"_s);
    QVERIFY(model.saveDeckText(deckId, QUrl::fromLocalFile(path)));
    QFile file(path);
    QVERIFY(file.open(QIODevice::ReadOnly | QIODevice::Text));
    QCOMPARE(QString::fromUtf8(file.readAll()), text);

    QVERIFY(model.openDeck(deckId));
    QCOMPARE(model.exportCurrentDeckText(), text);
    QCOMPARE(model.suggestedExportFileName(deckId), u"Burn.txt"_s);
}

void TestDeckLibrary::loadsDeckTextFromUtf8File() const
{
    QTemporaryDir storage;
    QVERIFY(storage.isValid());
    const QString path = storage.filePath(u"蓝白控制.txt"_s);
    QFile file(path);
    QVERIFY(file.open(QIODevice::WriteOnly | QIODevice::Text));
    const QString text = u"Deck\n4 Counterspell\n4 岛\n"_s;
    QCOMPARE(file.write(text.toUtf8()), text.toUtf8().size());
    file.close();

    DeckLibraryModel model(storage.path());
    const QVariantMap loaded = model.loadDeckTextFile(QUrl::fromLocalFile(path));
    QVERIFY(loaded.value(u"ok"_s).toBool());
    QCOMPARE(loaded.value(u"text"_s).toString(), text);
    QCOMPARE(loaded.value(u"suggestedName"_s).toString(), u"蓝白控制"_s);
    QVERIFY(model.lastError().isEmpty());
    QVERIFY(model.importDeck(loaded.value(u"suggestedName"_s).toString(), u"custom"_s,
                             loaded.value(u"text"_s).toString()));
    QCOMPARE(model.rowCount(), 1);
}

void TestDeckLibrary::rejectsInvalidDeckListFiles() const
{
    QTemporaryDir storage;
    QVERIFY(storage.isValid());
    DeckLibraryModel model(storage.path());

    QVERIFY(model.loadDeckTextFile(QUrl(u"https://example.test/deck.txt"_s)).isEmpty());
    QVERIFY(model.lastError().contains(u"local deck list file"_s));
    QVERIFY(
        model.loadDeckTextFile(QUrl::fromLocalFile(storage.filePath(u"missing.txt"_s))).isEmpty());
    QVERIFY(model.lastError().contains(u"could not be read"_s));

    const QString emptyPath = storage.filePath(u"empty.txt"_s);
    QFile emptyFile(emptyPath);
    QVERIFY(emptyFile.open(QIODevice::WriteOnly | QIODevice::Text));
    emptyFile.write("  \n");
    emptyFile.close();
    QVERIFY(model.loadDeckTextFile(QUrl::fromLocalFile(emptyPath)).isEmpty());
    QVERIFY(model.lastError().contains(u"empty"_s));

    const QString oversizedPath = storage.filePath(u"oversized.txt"_s);
    QFile oversizedFile(oversizedPath);
    QVERIFY(oversizedFile.open(QIODevice::WriteOnly));
    QCOMPARE(oversizedFile.write(QByteArray(1024 * 1024 + 1, 'x')), 1024 * 1024 + 1);
    oversizedFile.close();
    QVERIFY(model.loadDeckTextFile(QUrl::fromLocalFile(oversizedPath)).isEmpty());
    QVERIFY(model.lastError().contains(u"too large"_s));
}

void TestDeckLibrary::rejectsNonLocalDeckExportUrl() const
{
    QTemporaryDir storage;
    QVERIFY(storage.isValid());
    DeckLibraryModel model(storage.path());
    QVERIFY(model.importDeck(u"Burn"_s, u"modern"_s,
                             u"Deck\n4 Lightning Bolt (M11) 149\n"
                             "Sideboard\n2 Wear // Tear\n"
                             "Commander\n"_s));
    const QString deckId = model.data(model.index(0, 0), DeckLibraryModel::IdRole).toString();
    QVERIFY(!deckId.isEmpty());

    QVERIFY(!model.saveDeckText(deckId, QUrl(u"https://example.test/burn.txt"_s)));
    QVERIFY(model.lastError().contains(u"local file"_s));
    QVERIFY(!model.saveDeckText(deckId, QUrl(u"content://media/burn.txt"_s)));
    QVERIFY(model.lastError().contains(u"local file"_s));
}

void TestDeckLibrary::failedDeckExportLeavesExistingTarget() const
{
#ifdef Q_OS_WIN
    QSKIP("QFile::setPermissions cannot make a directory unwritable on Windows.");
#endif
    QTemporaryDir storage;
    QVERIFY(storage.isValid());
    DeckLibraryModel model(storage.path());
    QVERIFY(model.importDeck(u"Burn"_s, u"modern"_s,
                             u"Deck\n4 Lightning Bolt (M11) 149\n"
                             "Sideboard\n2 Wear // Tear\n"
                             "Commander\n"_s));
    const QString deckId = model.data(model.index(0, 0), DeckLibraryModel::IdRole).toString();
    QVERIFY(!deckId.isEmpty());

    const QString path = storage.filePath(u"burn.txt"_s);
    {
        QFile existing(path);
        QVERIFY(existing.open(QIODevice::WriteOnly | QIODevice::Text));
        existing.write("original");
    }

    const QFileDevice::Permissions writable = QFile::permissions(storage.path());
    const auto restorePermissions =
        qScopeGuard([&]() { QFile::setPermissions(storage.path(), writable); });
    QVERIFY(QFile::setPermissions(storage.path(), QFileDevice::ReadOwner | QFileDevice::ExeOwner |
                                                      QFileDevice::ReadUser |
                                                      QFileDevice::ExeUser));

    QVERIFY(!model.saveDeckText(deckId, QUrl::fromLocalFile(path)));
    QVERIFY(!model.lastError().isEmpty());

    QVERIFY(QFile::setPermissions(storage.path(), writable));
    QFile existing(path);
    QVERIFY(existing.open(QIODevice::ReadOnly | QIODevice::Text));
    QCOMPARE(QString::fromUtf8(existing.readAll()), u"original"_s);
}

void TestDeckLibrary::replacesExistingDeckExportFile() const
{
    QTemporaryDir storage;
    QVERIFY(storage.isValid());
    DeckLibraryModel model(storage.path());
    QVERIFY(model.importDeck(u"Burn"_s, u"modern"_s,
                             u"Deck\n4 Lightning Bolt (M11) 149\n"
                             "Sideboard\n2 Wear // Tear\n"
                             "Commander\n"_s));
    const QString deckId = model.data(model.index(0, 0), DeckLibraryModel::IdRole).toString();
    QVERIFY(!deckId.isEmpty());

    const QString path = storage.filePath(u"burn.txt"_s);
    {
        QFile existing(path);
        QVERIFY(existing.open(QIODevice::WriteOnly | QIODevice::Text));
        existing.write("original");
    }

    const QString text = model.exportDeckText(deckId);
    QVERIFY(text != u"original"_s);
    QVERIFY(model.saveDeckText(deckId, QUrl::fromLocalFile(path)));
    QFile file(path);
    QVERIFY(file.open(QIODevice::ReadOnly | QIODevice::Text));
    QCOMPARE(QString::fromUtf8(file.readAll()), text);
}

void TestDeckLibrary::parsesMoxfieldPrintingDecorations() const
{
    const auto parsed = DeckParser::parse(uR"(
1 Arcane Sanctum (40K) 264★ *F*
1 Azorius Signet (SLD) 286 *E*
1 Emeritus of Ideation / Ancestral Recall (SOS) 315 *F*
1 Reconnaissance (SLD) 1575★ *CMDR* *F*
)"_s);

    QVERIFY2(parsed.ok(), qPrintable(parsed.error));
    QVERIFY(parsed.warnings.isEmpty());
    QCOMPARE(parsed.deck.mainboard.size(), 4);
    QCOMPARE(parsed.deck.mainboard.at(0).name, u"Arcane Sanctum"_s);
    QCOMPARE(parsed.deck.mainboard.at(0).setCode, u"40K"_s);
    QCOMPARE(parsed.deck.mainboard.at(0).collectorNumber, u"264"_s);
    QCOMPARE(parsed.deck.mainboard.at(1).name, u"Azorius Signet"_s);
    QCOMPARE(parsed.deck.mainboard.at(1).collectorNumber, u"286"_s);
    QCOMPARE(parsed.deck.mainboard.at(2).name, u"Emeritus of Ideation // Ancestral Recall"_s);
    QCOMPARE(parsed.deck.mainboard.at(2).setCode, u"SOS"_s);
    QCOMPARE(parsed.deck.mainboard.at(2).collectorNumber, u"315"_s);
    QCOMPARE(parsed.deck.commanders, QStringList{u"Reconnaissance"_s});
}

void TestDeckLibrary::keepsDistinctPrintingCacheRequests() const
{
    QTemporaryDir storage;
    QVERIFY(storage.isValid());
    DeckLibraryModel model(storage.path());
    QSignalSpy cachingSpy(&model, &DeckLibraryModel::cardsNeedCaching);

    QVERIFY(model.importDeck(u"Mixed printings"_s, u"modern"_s,
                             u"1 Lightning Bolt (M11) 149\n"
                             "1 Lightning Bolt (2X2) 117\n"
                             "5 Mountain\n"_s));
    QCOMPARE(cachingSpy.count(), 0);

    const QString deckId = model.data(model.index(0, 0), DeckLibraryModel::IdRole).toString();
    QVERIFY(model.openDeck(deckId));
    model.cacheCurrentDeckArt();
    QCOMPARE(cachingSpy.count(), 1);
    const QVariantList requests = cachingSpy.first().first().toList();
    QCOMPARE(requests.size(), 3);
    QSet<QString> printingKeys;
    for (const QVariant &request : requests) {
        const QVariantMap map = request.toMap();
        printingKeys.insert(map.value(u"name"_s).toString() + u"|"_s +
                            map.value(u"setCode"_s).toString() + u"|"_s +
                            map.value(u"collectorNumber"_s).toString());
    }
    QVERIFY(printingKeys.contains(u"Lightning Bolt|M11|149"_s));
    QVERIFY(printingKeys.contains(u"Lightning Bolt|2X2|117"_s));
}

void TestDeckLibrary::doesNotCacheArtOnImportUntilRequested() const
{
    QTemporaryDir storage;
    QVERIFY(storage.isValid());
    DeckLibraryModel model(storage.path());
    QSignalSpy cachingSpy(&model, &DeckLibraryModel::cardsNeedCaching);
    QSignalSpy cachedLookupSpy(&model, &DeckLibraryModel::cardsNeedCachedArtLookup);

    QVERIFY(model.importDeck(u"Burn"_s, u"modern"_s,
                             u"Deck\n4 Lightning Bolt (M11) 149\n"
                             "Sideboard\n2 Wear // Tear\n"
                             "Commander\n"_s));
    QCOMPARE(cachingSpy.count(), 0);
    QCOMPARE(cachedLookupSpy.count(), 1);
    QCOMPARE(cachedLookupSpy.first().first().toList().size(), 2);
    QCOMPARE(model.currentMissingImageCount(), 0);

    cachedLookupSpy.clear();
    model.hydrateCatalogMetadata();
    QCOMPARE(cachedLookupSpy.count(), 1);
    QCOMPARE(cachedLookupSpy.first().first().toList().size(), 2);

    const QString deckId = model.data(model.index(0, 0), DeckLibraryModel::IdRole).toString();
    QVERIFY(model.openDeck(deckId));
    QCOMPARE(model.currentMissingImageCount(), 2);

    QVERIFY(model.addCard(u"Mountain"_s, u"Mountain"_s, u"Basic Land — Mountain"_s, u"M21"_s,
                          u"273"_s, false));
    QCOMPARE(cachingSpy.count(), 1);
    const QVariantList added = cachingSpy.last().first().toList();
    QCOMPARE(added.size(), 1);
    QCOMPARE(added.first().toMap().value(u"name"_s).toString(), u"Mountain"_s);
    QCOMPARE(added.first().toMap().value(u"setCode"_s).toString(), u"M21"_s);
    QVERIFY(added.first().toMap().value(u"exactArt"_s).toBool());

    model.cacheCurrentDeckArt();
    QCOMPARE(cachingSpy.count(), 2);
    const QVariantList missing = cachingSpy.last().first().toList();
    QCOMPARE(missing.size(), 3);
    QSet<QString> names;
    for (const QVariant &request : missing)
        names.insert(request.toMap().value(u"name"_s).toString());
    QVERIFY(names.contains(u"Lightning Bolt"_s));
    QVERIFY(names.contains(u"Wear // Tear"_s));
    QVERIFY(names.contains(u"Mountain"_s));
}

void TestDeckLibrary::hydratesTypeLineFromCatalogWithoutCachingArt() const
{
    QTemporaryDir storage;
    QVERIFY(storage.isValid());
    DeckLibraryModel model(storage.path());
    QSignalSpy cachingSpy(&model, &DeckLibraryModel::cardsNeedCaching);
    QSignalSpy metadataRequestSpy(&model, &DeckLibraryModel::cardsNeedMetadata);

    QVERIFY(model.importDeck(u"Burn"_s, u"modern"_s, u"4 Lightning Bolt\n3 Mountain\n"_s));
    QCOMPARE(cachingSpy.count(), 0);
    QCOMPARE(metadataRequestSpy.count(), 1);
    QCOMPARE(metadataRequestSpy.first().first().toList().size(), 2);
    model.applyCatalogMetadata(QVariantList{
        QVariantMap{
            {u"requestedName"_s, u"Lightning Bolt"_s},
            {u"requestedSetCode"_s, QString{}},
            {u"requestedCollectorNumber"_s, QString{}},
            {u"typeLine"_s, u"Instant"_s},
            {u"localizedName"_s, u"闪电击"_s},
        },
        QVariantMap{
            {u"requestedName"_s, u"Mountain"_s},
            {u"requestedSetCode"_s, QString{}},
            {u"requestedCollectorNumber"_s, QString{}},
            {u"typeLine"_s, u"Basic Land — Mountain"_s},
        },
    });

    const QString id = model.data(model.index(0), DeckLibraryModel::IdRole).toString();
    QVERIFY(model.openDeck(id));
    const QVariantList cards = model.mainCards();
    QCOMPARE(cards.size(), 2);

    QVariantMap bolt;
    QVariantMap mountain;
    for (const QVariant &value : cards) {
        const QVariantMap card = value.toMap();
        if (card.value(u"name"_s).toString() == u"Lightning Bolt")
            bolt = card;
        else if (card.value(u"name"_s).toString() == u"Mountain")
            mountain = card;
    }
    QCOMPARE(bolt.value(u"typeLine"_s).toString(), u"Instant"_s);
    QCOMPARE(bolt.value(u"category"_s).toString(), u"Spells"_s);
    QCOMPARE(bolt.value(u"displayName"_s).toString(), u"闪电击"_s);
    QCOMPARE(mountain.value(u"typeLine"_s).toString(), u"Basic Land — Mountain"_s);
    QCOMPARE(mountain.value(u"category"_s).toString(), u"Lands"_s);
    QVERIFY(bolt.value(u"imageSource"_s).toString().isEmpty());
    QCOMPARE(cachingSpy.count(), 0);

    model.flushMetadataCommitForTest();
    QTRY_COMPARE_WITH_TIMEOUT(model.persistedGenerationForTest(),
                              model.persistenceGenerationForTest(), 1'000);
    DeckLibraryModel restored(storage.path());
    QVERIFY(restored.openDeck(id));
    QCOMPARE(restored.mainCards().first().toMap().value(u"category"_s).toString().isEmpty(), false);
    bool sawSpell = false;
    bool sawLand = false;
    for (const QVariant &value : restored.mainCards()) {
        const QString category = value.toMap().value(u"category"_s).toString();
        sawSpell = sawSpell || category == u"Spells";
        sawLand = sawLand || category == u"Lands";
    }
    QVERIFY(sawSpell);
    QVERIFY(sawLand);

    DeckLibraryModel pending(storage.path());
    QSignalSpy pendingCacheSpy(&pending, &DeckLibraryModel::cardsNeedCaching);
    QVERIFY(pending.importDeck(u"Pending"_s, u"modern"_s, u"4 Lightning Bolt\n"_s));
    QVERIFY(pending.openDeck(pending.data(pending.index(0), DeckLibraryModel::IdRole).toString()));
    QCOMPARE(pending.mainCards().first().toMap().value(u"category"_s).toString(), u"Other"_s);
    pending.applyCatalogMetadata(QVariantList{QVariantMap{
        {u"requestedName"_s, u"Lightning Bolt"_s},
        {u"requestedSetCode"_s, QString{}},
        {u"requestedCollectorNumber"_s, QString{}},
        {u"typeLine"_s, u"Instant"_s},
    }});
    QCOMPARE(pending.mainCards().first().toMap().value(u"category"_s).toString(), u"Spells"_s);
    QCOMPARE(pendingCacheSpy.count(), 0);
}

void TestDeckLibrary::appliesDoubleFacedPrintingUnderFaceName() const
{
    QTemporaryDir storage;
    QVERIFY(storage.isValid());
    DeckLibraryModel model(storage.path());
    QVERIFY(model.importDeck(u"Delver"_s, u"modern"_s, u"1 Delver of Secrets\n"_s));
    const QString id = model.data(model.index(0), DeckLibraryModel::IdRole).toString();
    QVERIFY(model.openDeck(id));
    QVERIFY(model.setCardPrinting(u"Delver of Secrets // Insectile Aberration"_s, false,
                                  u"Delver of Secrets // Insectile Aberration"_s,
                                  u"Creature — Human Wizard // Creature — Insect"_s, u"MID"_s,
                                  u"47"_s));
    QCOMPARE(model.mainCards().size(), 1);
    const QVariantMap card = model.mainCards().first().toMap();
    QCOMPARE(card.value(u"name"_s).toString(), u"Delver of Secrets"_s);
    QCOMPARE(card.value(u"setCode"_s).toString(), u"MID"_s);
    QCOMPARE(card.value(u"collectorNumber"_s).toString(), u"47"_s);
}

void TestDeckLibrary::reportsImportWarnings() const
{
    QTemporaryDir storage;
    QVERIFY(storage.isValid());
    DeckLibraryModel model(storage.path());
    QSignalSpy warningSpy(&model, &DeckLibraryModel::lastImportWarningsChanged);

    QVERIFY(model.importDeck(u"Warnings"_s, u"modern"_s, u"7 Mountain\nnot a card\n"_s));
    QCOMPARE(model.lastImportWarnings(), QStringList{u"Line 2 was ignored: not a card"_s});
    QCOMPARE(warningSpy.count(), 1);

    QVERIFY(model.importDeck(u"Clean"_s, u"modern"_s, u"7 Island\n"_s));
    QVERIFY(model.lastImportWarnings().isEmpty());
    QCOMPARE(warningSpy.count(), 2);
}

void TestDeckLibrary::storesDeckTokensAndActivatesThemForMatches() const
{
    QTemporaryDir storage;
    QVERIFY(storage.isValid());
    QString deckId;
    {
        DeckLibraryModel model(storage.path());
        QVERIFY(model.importDeck(u"Tokens"_s, u"modern"_s, u"7 Mountain\n"_s));
        deckId = model.data(model.index(0), DeckLibraryModel::IdRole).toString();
        QVERIFY(model.openDeck(deckId));
        const QVariantMap goblin{
            {u"name"_s, u"Goblin"_s},
            {u"displayName"_s, u"地精"_s},
            {u"typeLine"_s, u"衍生生物 — 地精"_s},
            {u"setCode"_s, u"TNEO"_s},
            {u"collectorNumber"_s, u"12"_s},
            {u"power"_s, u"1"_s},
            {u"toughness"_s, u"1"_s},
            {u"oracleText"_s, u"Haste"_s},
        };
        QVERIFY(model.addToken(goblin));
        QVERIFY(!model.addToken(goblin));
        QCOMPARE(model.currentTokens().size(), 1);
        QCOMPARE(model.currentTokens().first().toMap().value(u"displayName"_s).toString(),
                 u"地精"_s);
        QCOMPARE(model.currentTokens().first().toMap().value(u"oracleText"_s).toString(),
                 u"Haste"_s);
        QVERIFY(model.setActiveMatchDeck(deckId));
        QCOMPARE(model.activeMatchTokens().size(), 1);

        const QVariantMap payload = model.deckForMatch(deckId, true);
        QVERIFY(!payload.contains(u"tokens"_s));
    }

    DeckLibraryModel restored(storage.path());
    QVERIFY(restored.openDeck(deckId));
    QCOMPARE(restored.currentTokens().size(), 1);
    const QVariantMap restoredToken = restored.currentTokens().first().toMap();
    QCOMPARE(restoredToken.value(u"name"_s).toString(), u"Goblin"_s);
    QCOMPARE(restoredToken.value(u"displayName"_s).toString(), u"地精"_s);
    QCOMPARE(restoredToken.value(u"power"_s).toString(), u"1"_s);
    QCOMPARE(restoredToken.value(u"toughness"_s).toString(), u"1"_s);
    QCOMPARE(restoredToken.value(u"oracleText"_s).toString(), u"Haste"_s);
    QVERIFY(restored.removeToken(u"Goblin"_s, u"tneo"_s, u"12"_s));
    QVERIFY(restored.currentTokens().isEmpty());
}

void TestDeckLibrary::backfillsLegacyDeckTokenMetadata() const
{
    QTemporaryDir storage;
    QVERIFY(storage.isValid());
    QString deckId;
    {
        DeckLibraryModel model(storage.path());
        QVERIFY(model.importDeck(u"Legacy token"_s, u"modern"_s, u"7 Mountain\n"_s));
        deckId = model.data(model.index(0), DeckLibraryModel::IdRole).toString();
        QVERIFY(model.openDeck(deckId));
        QVERIFY(model.addToken(QVariantMap{
            {u"name"_s, u"Cat"_s},
            {u"displayName"_s, u"Cat"_s},
            {u"typeLine"_s, u"Token Creature — Cat"_s},
            {u"setCode"_s, u"TUNF"_s},
            {u"collectorNumber"_s, u"1"_s},
        }));

        QSignalSpy requestSpy(&model, &DeckLibraryModel::tokensNeedMetadata);
        model.refreshTokenMetadata();
        QCOMPARE(requestSpy.count(), 1);
        const QVariantList requests = requestSpy.first().first().toList();
        QCOMPARE(requests.size(), 1);
        QCOMPARE(requests.first().toMap().value(u"setCode"_s).toString(), u"TUNF"_s);

        model.applyTokenMetadata(QVariantList{QVariantMap{
            {u"requestedName"_s, u"Cat"_s},
            {u"requestedSetCode"_s, u"TUNF"_s},
            {u"requestedCollectorNumber"_s, u"1"_s},
            {u"power"_s, u"2"_s},
            {u"toughness"_s, u"2"_s},
            {u"oracleText"_s, u"Flying"_s},
        }});
        const QVariantMap enriched = model.currentTokens().first().toMap();
        QCOMPARE(enriched.value(u"power"_s).toString(), u"2"_s);
        QCOMPARE(enriched.value(u"toughness"_s).toString(), u"2"_s);
        QCOMPARE(enriched.value(u"oracleText"_s).toString(), u"Flying"_s);
    }

    DeckLibraryModel restored(storage.path());
    QVERIFY(restored.openDeck(deckId));
    const QVariantMap token = restored.currentTokens().first().toMap();
    QCOMPARE(token.value(u"power"_s).toString(), u"2"_s);
    QCOMPARE(token.value(u"toughness"_s).toString(), u"2"_s);
    QCOMPARE(token.value(u"oracleText"_s).toString(), u"Flying"_s);
}

void TestDeckLibrary::parsesMultipleCommanders() const
{
    const auto parsed = DeckParser::parse(uR"(
Commanders
1 Yoshimaru, Ever Faithful
1 Keleth, Sunmane Familiar

Deck
7 Plains
)"_s);

    QVERIFY2(parsed.ok(), qPrintable(parsed.error));
    QCOMPARE(parsed.deck.commanders,
             QStringList({u"Yoshimaru, Ever Faithful"_s, u"Keleth, Sunmane Familiar"_s}));
    QCOMPARE(hexproof::client::cardCount(parsed.deck.mainboard), 9);
}

void TestDeckLibrary::parsesSplitCardNames() const
{
    const auto parsed = DeckParser::parse(u"2 Wear // Tear\n"_s);

    QVERIFY2(parsed.ok(), qPrintable(parsed.error));
    QCOMPARE(parsed.deck.mainboard.size(), 1);
    QCOMPARE(parsed.deck.mainboard.first().name, u"Wear // Tear"_s);
    QCOMPARE(parsed.deck.mainboard.first().count, 2);
}

void TestDeckLibrary::parsesBlankLineSideboard() const
{
    const QString deckText = uR"(3 Arid Mesa
4 Blazing Rootwalla
3 Bloodstained Mire
4 Burning Inquiry
4 Detective's Phoenix
1 Elegant Parlor
4 Faithless Looting
4 Hardened Academic
4 Hollow One
3 Lightning Bolt
4 Marauding Mako
4 Mountain
1 Ox of Agonas
2 Practiced Offense
3 Sacred Foundry
4 Scalding Tarn
4 Street Wraith
4 Vengevine
)"_s + QStringLiteral(" \n") +
                             uR"(2 Damping Sphere
2 Fire Magic
1 Lightning Bolt
3 Meltdown
2 Obsidian Charmaw
3 Surgical Extraction
2 Wear // Tear)"_s;
    const auto parsed = DeckParser::parse(deckText);

    QVERIFY2(parsed.ok(), qPrintable(parsed.error));
    QCOMPARE(hexproof::client::cardCount(parsed.deck.mainboard), 60);
    QCOMPARE(hexproof::client::cardCount(parsed.deck.sideboard), 15);
    QCOMPARE(parsed.deck.mainboard.size(), 18);
    QCOMPARE(parsed.deck.sideboard.size(), 7);
    QCOMPARE(parsed.deck.sideboard.last().name, u"Wear // Tear"_s);
}

void TestDeckLibrary::parsesBlankLineCommander() const
{
    const auto parsed =
        DeckParser::parse(u"1 Sol Ring\n1 Arcane Signet\n\n1 Atraxa, Praetors' Voice\n"_s, true);

    QVERIFY2(parsed.ok(), qPrintable(parsed.error));
    QCOMPARE(parsed.deck.commanders, QStringList{u"Atraxa, Praetors' Voice"_s});
    QCOMPARE(hexproof::client::cardCount(parsed.deck.mainboard), 3);
    QCOMPARE(parsed.deck.sideboard.size(), 0);
}

void TestDeckLibrary::rejectsOversizedImports() const
{
    const auto parsed = DeckParser::parse(QString(1024 * 1024 + 1, QLatin1Char('x')));
    QVERIFY(!parsed.ok());
    QCOMPARE(parsed.error, u"Deck imports cannot exceed 1 MB."_s);
}

void TestDeckLibrary::rejectsInvalidAndOverflowingCounts() const
{
    const auto huge = DeckParser::parse(u"999999999999999999999 Mountain\n"_s);
    QVERIFY(!huge.ok());
    QCOMPARE(huge.error, u"Line 1 has an invalid card count."_s);

    const auto duplicate = DeckParser::parse(u"600 Mountain\n500 Mountain\n"_s);
    QVERIFY(!duplicate.ok());
    QCOMPARE(duplicate.error, u"Deck imports can contain at most 1000 cards and 500 entries."_s);

    const auto aggregate = DeckParser::parse(u"600 Mountain\n500 Island\n"_s);
    QVERIFY(!aggregate.ok());
    QCOMPARE(aggregate.error, u"Deck imports can contain at most 1000 cards."_s);

    QString tooManyEntries;
    for (int index = 0; index < 500; ++index)
        tooManyEntries += QStringLiteral("1 Main Card %1\n").arg(index);
    tooManyEntries += QStringLiteral("Sideboard\n1 Side Card\n");
    const auto entries = DeckParser::parse(tooManyEntries);
    QVERIFY(!entries.ok());
    QCOMPARE(entries.error, u"Deck imports can contain at most 1000 cards and 500 entries."_s);
}

void TestDeckLibrary::appliesLargerCubeImportLimits() const
{
    QString cube;
    for (int index = 0; index < 540; ++index) {
        cube += QStringLiteral("1 Cube Card %1 (TST) %1\n").arg(index + 1);
    }

    QTemporaryDir storage;
    QVERIFY(storage.isValid());
    DeckLibraryModel model(storage.path());
    QVERIFY2(model.importDeck(u"Large Cube"_s, u"cube"_s, cube), qPrintable(model.lastError()));
    QCOMPARE(model.data(model.index(0), DeckLibraryModel::MainCountRole).toInt(), 540);

    QString tooManyEntries;
    for (int index = 0; index < 5001; ++index)
        tooManyEntries += QStringLiteral("1 Cube Card %1\n").arg(index + 1);
    const auto parsed =
        DeckParser::parse(tooManyEntries, false, hexproof::client::DeckParseProfile::Cube);
    QVERIFY(!parsed.ok());
    QCOMPARE(parsed.error, u"Deck imports can contain at most 10000 cards and 5000 entries."_s);
}

void TestDeckLibrary::rejectsControlCharacters() const
{
    const auto parsed = DeckParser::parse(u"1 Mountain\u0007\n"_s);
    QVERIFY(!parsed.ok());
    QCOMPARE(parsed.error, u"Deck imports cannot contain control characters."_s);
}

void TestDeckLibrary::allowsInteractiveBasicLandCopies() const
{
    QTemporaryDir storage;
    QVERIFY(storage.isValid());
    DeckLibraryModel model(storage.path());
    QVERIFY(model.importDeck(u"Basics"_s, u"modern"_s, u"4 Mountain (M21) 273\n"_s));
    const QString id = model.data(model.index(0), DeckLibraryModel::IdRole).toString();
    QVERIFY(model.openDeck(id));
    QVERIFY(model.canAddCard(u"Mountain"_s, u"Basic Land — Mountain"_s));
    QVERIFY(model.changeCardCount(u"Mountain"_s, false, 1));
    QCOMPARE(model.currentCardCopies(u"Mountain"_s), 5);
}

QTEST_GUILESS_MAIN(TestDeckLibrary)
