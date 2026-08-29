// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "services/BackgroundTaskPools.h"
#include "services/CardArtCache.h"
#include "services/CardCatalogCommon.h"
#include "services/CardResolver.h"
#include "services/CatalogImport.h"
#include "services/CatalogInstaller.h"
#include "services/CatalogStorage.h"
#include "services/NetworkLimits.h"
#include "services/NetworkRequestFactory.h"

#include <QDir>
#include <QElapsedTimer>
#include <QFile>
#include <QNetworkReply>
#include <QReadLocker>
#include <QSqlDatabase>
#include <QSqlQuery>
#include <QTemporaryDir>
#include <QTest>
#include <QThreadPool>
#include <QUrl>

using namespace Qt::StringLiterals;
using namespace hexproof::client;

class TestCardServices final : public QObject
{
    Q_OBJECT

  private slots:
    void resolverOwnsEnglishCompletionState() const;
    void resolverOwnsChinesePrintingFallback() const;
    void installerOwnsAsynchronousImport() const;
    void legacyDatabaseReportsRequiredSchema() const;
    void cancelledBulkImportCleansTemporaryDatabase() const;
    void installerDestructionCancelsImportWithoutBlocking() const;
    void backgroundWorkUsesBoundedDedicatedPools() const;
    void requestFactoryUsesBuildVersion() const;
    void requestFactoryDisablesHttp2() const;
    void requestFactoryKeepsHttp2ForNonScryfallHosts() const;
    void networkReplyLimiterRejectsOversizePayloads() const;
    void imageTimeoutDoesNotOpenHostCooldown() const;
    void artCachePersistsPolicyAndReusesOraclePrinting() const;
    void artCacheRejectsCachedWrongDoubleFace() const;
    void artCachePreservesCorruptMetadataBeforeWriting() const;
};

namespace {

class SizedNetworkReply final : public QNetworkReply
{
  public:
    explicit SizedNetworkReply(qint64 payloadSize)
        : m_payloadSize(payloadSize)
    {
        open(QIODevice::ReadOnly | QIODevice::Unbuffered);
    }

    void abort() override
    {
        m_aborted = true;
        setError(QNetworkReply::OperationCanceledError, QStringLiteral("Response too large"));
        close();
    }

    qint64 bytesAvailable() const override
    {
        return isOpen() ? m_payloadSize + QNetworkReply::bytesAvailable()
                        : QNetworkReply::bytesAvailable();
    }

    bool aborted() const
    {
        return m_aborted;
    }

  protected:
    qint64 readData(char *, qint64) override
    {
        return -1;
    }

  private:
    qint64 m_payloadSize = 0;
    bool m_aborted = false;
};

bool writeBulkCatalog(const QString &path, int cardCount)
{
    QFile file(path);
    if (!file.open(QIODevice::WriteOnly))
        return false;
    if (file.write("[") != 1)
        return false;
    for (int index = 0; index < cardCount; ++index) {
        if (index > 0 && file.write(",") != 1)
            return false;
        const QByteArray card = QByteArrayLiteral("{\"id\":\"") + QByteArray::number(index) +
                                QByteArrayLiteral("\",\"oracle_id\":\"oracle-") +
                                QByteArray::number(index) +
                                QByteArrayLiteral("\",\"name\":\"Card ") +
                                QByteArray::number(index) + QByteArrayLiteral("\"}");
        if (file.write(card) != card.size())
            return false;
    }
    return file.write("]") == 1;
}

} // namespace

void TestCardServices::resolverOwnsEnglishCompletionState() const
{
    QTemporaryDir directory;
    QVERIFY(directory.isValid());
    const QString imagePath = directory.filePath(u"cached.png"_s);
    QFile image(imagePath);
    QVERIFY(image.open(QIODevice::WriteOnly));
    QCOMPARE(image.write("cached"), 6);
    image.close();

    bool completed = false;
    bool queuedMoreWork = false;
    CardResolver::Callbacks callbacks;
    callbacks.lookupCatalog = [](const CardRequest &request) {
        CardRecord record;
        record.name = request.name;
        record.imageLanguage = u"en"_s;
        record.imageUrl = u"https://images.example.test/card.png"_s;
        return record;
    };
    callbacks.imagePathFor = [&imagePath](const CardRequest &, const CardRecord &) {
        return imagePath;
    };
    callbacks.completed = [&completed, &imagePath](const CardRequest &request, CardRecord record,
                                                   bool success, bool cacheFailure,
                                                   const QString &failure) {
        completed = true;
        QCOMPARE(request.name, u"Sol Ring"_s);
        QVERIFY(success);
        QVERIFY(!cacheFailure);
        QVERIFY(failure.isEmpty());
        QCOMPARE(record.imagePath, imagePath);
    };
    callbacks.queueMoreWork = [&queuedMoreWork]() { queuedMoreWork = true; };

    CardResolver resolver(nullptr, std::move(callbacks));
    resolver.resolve(CardRequest{u"Sol Ring"_s, {}, {}, u"en"_s});

    QVERIFY(completed);
    QVERIFY(queuedMoreWork);
    QVERIFY(!resolver.active());
}

void TestCardServices::resolverOwnsChinesePrintingFallback() const
{
    QTemporaryDir directory;
    QVERIFY(directory.isValid());
    const QString imagePath = directory.filePath(u"cached-zhs.png"_s);
    QFile image(imagePath);
    QVERIFY(image.open(QIODevice::WriteOnly));
    QCOMPARE(image.write("cached"), 6);
    image.close();

    bool localizedLookupUsed = false;
    bool identityMatched = false;
    bool completed = false;
    CardResolver::Callbacks callbacks;
    callbacks.lookupCatalog = [](const CardRequest &request) {
        CardRecord record;
        record.name = request.name;
        record.oracleId = u"oracle-id"_s;
        return record;
    };
    callbacks.lookupLocalizedPrinting =
        [&localizedLookupUsed, &identityMatched](const CardRequest &, const CardRecord &identity) {
            localizedLookupUsed = true;
            identityMatched = identity.oracleId == u"oracle-id"_s;
            CardRecord record;
            record.name = identity.name;
            record.localizedName = u"阳光戒"_s;
            record.imageLanguage = u"zh"_s;
            record.imageUrl = u"https://images.example.test/card-zhs.png"_s;
            return record;
        };
    callbacks.imagePathFor = [&imagePath](const CardRequest &, const CardRecord &) {
        return imagePath;
    };
    callbacks.completed = [&completed](const CardRequest &, CardRecord record, bool success, bool,
                                       const QString &) {
        completed = true;
        QVERIFY(success);
        QCOMPARE(record.localizedName, u"阳光戒"_s);
        QCOMPARE(record.imageLanguage, u"zh"_s);
    };

    CardResolver resolver(nullptr, std::move(callbacks));
    resolver.resolve(CardRequest{u"Sol Ring"_s, {}, {}, u"zh"_s});

    QVERIFY(localizedLookupUsed);
    QVERIFY(identityMatched);
    QVERIFY(completed);
    QVERIFY(!resolver.active());
}

void TestCardServices::installerOwnsAsynchronousImport() const
{
    QTemporaryDir directory;
    QVERIFY(directory.isValid());
    const QString sourcePath = directory.filePath(u"empty.json"_s);
    QFile source(sourcePath);
    QVERIFY(source.open(QIODevice::WriteOnly));
    QCOMPARE(source.write("[]"), 2);
    source.close();

    CatalogInstaller installer(directory.path(), directory.filePath(u"cards.sqlite"_s), nullptr);
    bool finished = false;
    installer.onImportFinished = [&installer, &finished](const CatalogImportResult &result) {
        finished = true;
        QVERIFY(!result.ok);
        QVERIFY(!result.error.isEmpty());
        installer.completeOperation();
    };
    installer.importCatalogFile(QUrl::fromLocalFile(sourcePath), u"default_cards"_s);

    QVERIFY(installer.busy());
    QTRY_VERIFY_WITH_TIMEOUT(finished, 5000);
    QVERIFY(!installer.busy());
}

void TestCardServices::legacyDatabaseReportsRequiredSchema() const
{
    QTemporaryDir directory;
    QVERIFY(directory.isValid());
    const QString sourcePath = directory.filePath(u"legacy.sqlite"_s);
    const QString connectionName = u"legacy-catalog-test"_s;
    {
        QSqlDatabase database = QSqlDatabase::addDatabase(u"QSQLITE"_s, connectionName);
        database.setDatabaseName(sourcePath);
        QVERIFY(database.open());
        QSqlQuery query(database);
        QVERIFY(query.exec(u"CREATE TABLE metadata (key TEXT PRIMARY KEY, value TEXT)"_s));
        QVERIFY(query.exec(u"INSERT INTO metadata VALUES ('package', 'default_cards')"_s));
        QVERIFY(query.exec(u"INSERT INTO metadata VALUES ('count', '1')"_s));
        QVERIFY(query.exec(u"INSERT INTO metadata VALUES ('schema_version', '6')"_s));
        database.close();
    }
    QSqlDatabase::removeDatabase(connectionName);

    const CatalogImportResult result =
        catalogimport::importDatabaseFile(sourcePath, directory.filePath(u"installed.sqlite"_s));
    QVERIFY(!result.ok);
    QCOMPARE(result.error,
             u"The selected card database uses schema version 6, but this Hexproof version "
             "requires schema version 10."_s);
}

void TestCardServices::cancelledBulkImportCleansTemporaryDatabase() const
{
    QTemporaryDir directory;
    QVERIFY(directory.isValid());
    const QString sourcePath = directory.filePath(u"cards.json"_s);
    QVERIFY(writeBulkCatalog(sourcePath, 1));
    const QString databasePath = directory.filePath(u"cards.sqlite"_s);

    CatalogImportStopSource stopSource;
    QVERIFY(stopSource.requestStop());
    const CatalogImportResult result = catalogimport::importBulkFile(
        sourcePath, databasePath, u"default_cards"_s, {}, {}, stopSource.token());

    QVERIFY(result.cancelled);
    QVERIFY(!result.ok);
    QVERIFY(result.error.isEmpty());
    QVERIFY(!QFile::exists(databasePath));
    QVERIFY(!QFile::exists(databasePath + u".new"_s));
}

void TestCardServices::installerDestructionCancelsImportWithoutBlocking() const
{
    QTemporaryDir directory;
    QVERIFY(directory.isValid());
    const QString sourcePath = directory.filePath(u"cards.json"_s);
    QVERIFY(writeBulkCatalog(sourcePath, 1));
    const QString databasePath = directory.filePath(u"cards.sqlite"_s);

    QReadLocker databaseReadLock(&catalogstorage::databaseLock());
    QThreadPool *const maintenancePool = BackgroundTaskPools::catalogMaintenance();
    const int activeThreadsBefore = maintenancePool->activeThreadCount();
    auto *installer = new CatalogInstaller(directory.path(), databasePath, nullptr);
    installer->importCatalogFile(QUrl::fromLocalFile(sourcePath), u"default_cards"_s);
    QTRY_VERIFY_WITH_TIMEOUT(maintenancePool->activeThreadCount() > activeThreadsBefore, 5000);

    QElapsedTimer timer;
    timer.start();
    delete installer;
    QVERIFY2(timer.elapsed() < 500,
             "CatalogInstaller destruction waited for the background import to finish.");

    databaseReadLock.unlock();
    QVERIFY(maintenancePool->waitForDone(5000));
    QVERIFY(!QFile::exists(databasePath));
    QVERIFY(!QFile::exists(databasePath + u".new"_s));
}

void TestCardServices::backgroundWorkUsesBoundedDedicatedPools() const
{
    QThreadPool *const search = BackgroundTaskPools::catalogSearch();
    QThreadPool *const maintenance = BackgroundTaskPools::catalogMaintenance();
    QThreadPool *const parsing = BackgroundTaskPools::deckParsing();
    QThreadPool *const persistence = BackgroundTaskPools::deckPersistence();

    QCOMPARE(search->maxThreadCount(), 1);
    QCOMPARE(maintenance->maxThreadCount(), 2);
    QCOMPARE(parsing->maxThreadCount(), 1);
    QCOMPARE(persistence->maxThreadCount(), 1);
    QVERIFY(search != maintenance);
    QVERIFY(search != parsing);
    QVERIFY(maintenance != persistence);
}

void TestCardServices::requestFactoryUsesBuildVersion() const
{
    const QNetworkRequest request =
        makeNetworkRequest(QUrl(u"https://example.test/data"_s), u"application/json"_s.toLatin1());
    QCOMPARE(request.rawHeader("User-Agent"),
             QByteArrayLiteral("Hexproof/") + QByteArrayLiteral(HEXPROOF_VERSION) +
                 QByteArrayLiteral(" (+https://github.com/ClayStan404/hexproof)"));
    QCOMPARE(request.rawHeader("Accept"), QByteArrayLiteral("application/json"));
}

void TestCardServices::requestFactoryDisablesHttp2() const
{
    const QNetworkRequest cdn = makeNetworkRequest(
        QUrl(u"https://cards.scryfall.io/normal/front/example.jpg"_s), u"image/*"_s.toLatin1());
    const QVariant cdnHttp2 = cdn.attribute(QNetworkRequest::Http2AllowedAttribute);
    QVERIFY(cdnHttp2.isValid());
    QCOMPARE(cdnHttp2.toBool(), false);

    const QNetworkRequest api = makeNetworkRequest(QUrl(u"https://api.scryfall.com/cards/named"_s),
                                                   u"application/json"_s.toLatin1());
    const QVariant apiHttp2 = api.attribute(QNetworkRequest::Http2AllowedAttribute);
    QVERIFY(apiHttp2.isValid());
    QCOMPARE(apiHttp2.toBool(), false);
}

void TestCardServices::requestFactoryKeepsHttp2ForNonScryfallHosts() const
{
    const QNetworkRequest request =
        makeNetworkRequest(QUrl(u"https://example.test/data"_s), u"application/json"_s.toLatin1());
    const QVariant http2Allowed = request.attribute(QNetworkRequest::Http2AllowedAttribute);
    QVERIFY(!http2Allowed.isValid() || http2Allowed.toBool());

    const QNetworkRequest github = makeNetworkRequest(
        QUrl(u"https://github.com/ClayStan404/hexproof/releases/download/card-data/x"_s),
        u"application/gzip"_s.toLatin1());
    const QVariant githubHttp2 = github.attribute(QNetworkRequest::Http2AllowedAttribute);
    QVERIFY(!githubHttp2.isValid() || githubHttp2.toBool());
}

void TestCardServices::networkReplyLimiterRejectsOversizePayloads() const
{
    SizedNetworkReply allowed(network_limits::kMaximumJsonResponseBytes);
    network_limits::limitNetworkReply(&allowed, network_limits::kMaximumJsonResponseBytes);
    QVERIFY(!allowed.aborted());
    QVERIFY(!network_limits::responseSizeLimitExceeded(&allowed));

    SizedNetworkReply rejected(network_limits::kMaximumJsonResponseBytes + 1);
    network_limits::limitNetworkReply(&rejected, network_limits::kMaximumJsonResponseBytes);
    QVERIFY(rejected.aborted());
    QVERIFY(network_limits::responseSizeLimitExceeded(&rejected));
}

void TestCardServices::imageTimeoutDoesNotOpenHostCooldown() const
{
    CardResolver resolver(nullptr, {});
    const QUrl cdn(u"https://cards.scryfall.io/normal/front/x.jpg"_s);
    resolver.markHostFailure(cdn, 0, {}, QNetworkReply::TimeoutError);
    QVERIFY(!resolver.hostInCooldown(cdn));

    resolver.markHostFailure(cdn, 503, {});
    QVERIFY(resolver.hostInCooldown(cdn));
}

void TestCardServices::artCachePersistsPolicyAndReusesOraclePrinting() const
{
    QTemporaryDir directory;
    QVERIFY(directory.isValid());

    CardArtCache cache(directory.path());
    const QString imagePath =
        cache.imagePath(u"Sol Ring"_s, u"https://example.test/sol-ring.jpg"_s, u"zh"_s);
    QFile image(imagePath);
    QVERIFY(image.open(QIODevice::WriteOnly));
    QCOMPARE(image.write("cached"), 6);
    image.close();

    CardRecord cached;
    cached.requestedName = u"Sol Ring"_s;
    cached.name = u"Sol Ring"_s;
    cached.oracleId = u"oracle-sol-ring"_s;
    cached.setCode = u"CMM"_s;
    cached.collectorNumber = u"396"_s;
    cached.imageLanguage = u"zh"_s;
    cached.imagePath = imagePath;
    cached.resolutionVersion = catalog_internal::kCardResolutionVersion;
    const QString exactKey =
        cache.key(cached.name, u"zh"_s, cached.setCode, cached.collectorNumber);
    cache.rememberSuccess(exactKey, cached);
    const QString failedKey = cache.key(u"Missing Card"_s, u"zh"_s);
    cache.rememberFailure(failedKey);
    QVERIFY(cache.save());

    CardArtCache restored(directory.path());
    restored.load();
    QCOMPARE(restored.exactRecord(exactKey).imagePath, imagePath);
    QVERIFY(restored.failedRecently(failedKey));

    CardRecord replacement = cached;
    replacement.setCode = u"2XM"_s;
    replacement.collectorNumber = u"270"_s;
    restored.rememberSuccess(exactKey, replacement);
    QVERIFY(!restored.resolvedPrinting(CardRequest{u"Sol Ring"_s, u"CMM"_s, u"396"_s, u"zh"_s})
                 .valid());
    QVERIFY(
        restored.resolvedPrinting(CardRequest{u"Sol Ring"_s, u"2XM"_s, u"270"_s, u"zh"_s}).valid());

    const CardRequest request{u"Sol Ring"_s, u"2XM"_s, u"270"_s, u"zh"_s};
    CardRecord identity;
    identity.name = u"Sol Ring"_s;
    identity.oracleId = u"oracle-sol-ring"_s;
    const CardRecord reusable = restored.reusableArt(request, identity);
    QVERIFY(reusable.valid());
    QCOMPARE(reusable.imagePath, imagePath);

    restored.setReuseLocalArt(false);
    QVERIFY(!restored.reusableArt(request, identity).valid());
    const CardRequest unspecifiedPrinting{u"Sol Ring"_s, {}, {}, u"zh"_s};
    QVERIFY(restored.reusableArt(unspecifiedPrinting, identity).valid());
}

void TestCardServices::artCacheRejectsCachedWrongDoubleFace() const
{
    QTemporaryDir directory;
    QVERIFY(directory.isValid());

    CardArtCache cache(directory.path());
    const QString imagePath =
        cache.imagePath(u"Ajani, Nacatl Avenger"_s, u"https://images.test/front.webp"_s, u"zh"_s);
    QFile image(imagePath);
    QVERIFY(image.open(QIODevice::WriteOnly));
    QCOMPARE(image.write("cached"), 6);
    image.close();

    CardRecord stale;
    stale.requestedName = u"Ajani, Nacatl Avenger"_s;
    stale.name = u"Ajani, Nacatl Pariah // Ajani, Nacatl Avenger"_s;
    stale.oracleId = u"ajani-oracle"_s;
    stale.setCode = u"MH3"_s;
    stale.collectorNumber = u"237"_s;
    stale.imageLanguage = u"zh"_s;
    stale.imagePath = imagePath;
    stale.resolutionVersion = catalog_internal::kCardResolutionVersion;
    cache.rememberSuccess(
        cache.key(stale.requestedName, u"zh"_s, stale.setCode, stale.collectorNumber), stale);

    const CardRequest backRequest{u"Ajani, Nacatl Avenger"_s, u"MH3"_s, u"237"_s, u"zh"_s};
    QVERIFY(!cache.matchesRequestedFace(backRequest, stale));
    QVERIFY(!cache.resolvedPrinting(backRequest).valid());

    stale.faceName = u"Ajani, Nacatl Avenger"_s;
    QVERIFY(cache.matchesRequestedFace(backRequest, stale));
}

void TestCardServices::artCachePreservesCorruptMetadataBeforeWriting() const
{
    QTemporaryDir directory;
    QVERIFY(directory.isValid());
    const QString metadataPath = directory.filePath(u"card-cache.json"_s);

    CardRecord cached;
    cached.requestedName = u"Sol Ring"_s;
    cached.name = u"Sol Ring"_s;
    cached.setCode = u"CMM"_s;
    cached.collectorNumber = u"396"_s;
    cached.imageLanguage = u"zh"_s;
    cached.resolutionVersion = catalog_internal::kCardResolutionVersion;
    CardArtCache cache(directory.path());
    const QString key = cache.key(cached.name, u"zh"_s, cached.setCode, cached.collectorNumber);
    cache.rememberSuccess(key, cached);
    QVERIFY(cache.save());
    QVERIFY(QFile::exists(metadataPath));

    QFile metadata(metadataPath);
    QVERIFY(metadata.open(QIODevice::WriteOnly | QIODevice::Truncate));
    QCOMPARE(metadata.write("{\"positive\":"), 12);
    metadata.close();

    // A truncated cache must be preserved rather than silently overwritten by
    // the next save, and the cache must still be usable afterwards.
    CardArtCache reloaded(directory.path());
    reloaded.load();
    QCOMPARE(QDir(directory.path()).entryList({u"card-cache.json.corrupt-*"_s}, QDir::Files).size(),
             1);
    QVERIFY(!reloaded.exactRecord(key).valid());
    reloaded.rememberSuccess(key, cached);
    QVERIFY(reloaded.save());

    CardArtCache verified(directory.path());
    verified.load();
    QCOMPARE(verified.exactRecord(key).setCode, cached.setCode);
}

QTEST_GUILESS_MAIN(TestCardServices)
#include "cardservices_test.moc"
