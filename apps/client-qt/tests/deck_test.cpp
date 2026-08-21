// SPDX-License-Identifier: GPL-2.0-only
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

class TestDeckLibrary : public QObject
{
    Q_OBJECT

  private slots:
    void parsesMoxfieldAndPlainSections() const;
    void formatsExplicitDeckSideboardAndCommanderSections() const;
    void roundTripsFormattedDeckTextThroughTheParser() const;
    void exportsDeckTextAndSavesUtf8File() const;
    void loadsDeckTextFromUtf8File() const;
    void rejectsInvalidDeckListFiles() const;
    void rejectsNonLocalDeckExportUrl() const;
    void failedDeckExportLeavesExistingTarget() const;
    void replacesExistingDeckExportFile() const;
    void parsesMoxfieldPrintingDecorations() const;
    void parsesMultipleCommanders() const;
    void parsesSplitCardNames() const;
    void parsesBlankLineSideboard() const;
    void parsesBlankLineCommander() const;
    void rejectsOversizedImports() const;
    void rejectsInvalidAndOverflowingCounts() const;
    void rejectsControlCharacters() const;
    void allowsInteractiveBasicLandCopies() const;
    void importsFiltersEditsAndPersists() const;
    void validatesOnlyAffectedDecks() const;
    void edhReadinessRequiresCommanderAndImages() const;
    void duelCommanderImportsFiltersAndBuildsPayload() const;
    void changesDeckFormatWithoutLosingCards() const;
    void coalescesCardMetadataPersistence() const;
    void backgroundMetadataSaveCannotOverwriteSynchronousEdit() const;
    void retriesFailedBackgroundMetadataSave() const;
    void keepsMetadataDirtyAfterBoundedBackgroundRetries() const;
    void designatesUpToTwoCommanders() const;
    void readinessRequiresAnOpeningHand() const;
    void preservesCorruptLibraryBeforeWriting() const;
    void preservesMalformedLibrarySchema() const;
    void migratesLegacyTableFormatsToDeckFormats() const;
    void preservesCorruptPreferencesBeforeWriting() const;
    void keepsDamagedPreferencesWhenRenameFails() const;
    void storesUiAndCardLanguagesSeparately() const;
    void storesLocalArtReusePreference() const;
    void storesAndClampsInterfaceScale() const;
    void storesTableLayoutPreferences() const;
    void reportsEditorFailuresThroughLastError() const;
    void buildsPrivateMatchDeckPayload() const;
    void categorizesLocalizedTypeLines() const;
    void keepsDistinctPrintingCacheRequests() const;
    void doesNotCacheArtOnImportUntilRequested() const;
    void hydratesTypeLineFromCatalogWithoutCachingArt() const;
    void appliesDoubleFacedPrintingUnderFaceName() const;
    void reportsImportWarnings() const;
    void storesDeckTokensAndActivatesThemForMatches() const;
    void backfillsLegacyDeckTokenMetadata() const;
};

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

QTEST_GUILESS_MAIN(TestDeckLibrary)
#include "deck_test.moc"
