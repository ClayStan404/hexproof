// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "services/CardArtArchive.h"
#include "services/CardArtCache.h"
#include "services/CardArtManager.h"
#include "services/CardCatalogCommon.h"

#include <QDir>
#include <QFile>
#include <QSignalSpy>
#include <QTemporaryDir>
#include <QTest>

#include <memory>

using hexproof::client::CardArtCache;
using hexproof::client::CardArtManager;

class CardArtManagerAuditTest final : public QObject
{
    Q_OBJECT

  private slots:
    void auditResumesWhenRepairStillNeeded();
    void auditSkipsWhenCurrentAndHealthy();
    void reimportingExportDoesNotCreateUnusedImages();
    void importingPackRepairsCorruptCachedFile();
    void deckExportUsesSnapshotAndReportsCompletion();
    void rejectedDeckExportsAlwaysReportCompletion();
    void suggestedDeckExportNamesStayInDownloadDirectory();

  private:
    void setupManager(int auditVersion, bool repairNeeded);

    std::unique_ptr<QTemporaryDir> m_dir;
    std::unique_ptr<CardArtCache> m_cache;
    std::unique_ptr<CardArtManager> m_manager;
};

void CardArtManagerAuditTest::deckExportUsesSnapshotAndReportsCompletion()
{
    setupManager(hexproof::client::catalog_internal::kCardFaceAuditVersion, false);
    hexproof::client::CardRecord record;
    record.name = record.requestedName = QStringLiteral("Island");
    record.setCode = QStringLiteral("EOE");
    record.collectorNumber = QStringLiteral("269");
    record.imageLanguage = QStringLiteral("en");
    record.imageUrl = QStringLiteral("https://cards.scryfall.io/normal/front/island.png");
    record.imagePath = m_cache->imagePath(record.name, record.imageUrl, record.imageLanguage);
    record.resolutionVersion = hexproof::client::catalog_internal::kCardResolutionVersion;
    const QByteArray png = QByteArray::fromBase64("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAA"
                                                  "C0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=");
    QFile image(record.imagePath);
    QVERIFY(image.open(QIODevice::WriteOnly));
    QCOMPARE(image.write(png), png.size());
    image.close();
    const QString key =
        m_cache->key(record.name, record.imageLanguage, record.setCode, record.collectorNumber);
    m_cache->rememberSuccess(key, record);
    QVERIFY(m_cache->save());
    const QUrl archive = QUrl::fromLocalFile(m_dir->filePath(QStringLiteral("deck-export")));
    QVariantList cards{QVariantMap{{QStringLiteral("name"), record.name},
                                   {QStringLiteral("setCode"), record.setCode},
                                   {QStringLiteral("collectorNumber"), record.collectorNumber}}};
    QSignalSpy completed(m_manager.get(), &CardArtManager::deckExportFinished);
    QSignalSpy contentsChanged(m_manager.get(), &CardArtManager::contentsChanged);
    m_manager->exportDeckPack(archive, cards);
    QVERIFY(m_manager->busy());
    cards.clear();
    QTRY_COMPARE(completed.count(), 1);
    QVERIFY(!m_manager->busy());
    QVERIFY(m_manager->lastError().isEmpty());
    const QVariantMap summary = completed.first().first().toMap();
    QVERIFY(summary.value(QStringLiteral("ok")).toBool());
    QCOMPARE(summary.value(QStringLiteral("entryCount")).toInt(), 1);
    QCOMPARE(summary.value(QStringLiteral("requestedPrintingCount")).toInt(), 1);
    QCOMPARE(summary.value(QStringLiteral("fileUrl")).toString(), archive.toString());
    QVERIFY(!summary.value(QStringLiteral("faceCoverageVerified")).toBool());
    QVERIFY(QFileInfo::exists(archive.toLocalFile() + QStringLiteral(".hexproof-artpack")));
    QCOMPARE(contentsChanged.count(), 0);
    QCOMPARE(m_cache->entries().size(), 1);
    QVERIFY(!m_cache->dirty());
}

void CardArtManagerAuditTest::rejectedDeckExportsAlwaysReportCompletion()
{
    setupManager(hexproof::client::catalog_internal::kCardFaceAuditVersion, false);
    const QUrl destination =
        QUrl::fromLocalFile(m_dir->filePath(QStringLiteral("out.hexproof-artpack")));
    const QVariantList cards{QVariantMap{{QStringLiteral("name"), QStringLiteral("Island")}}};
    QSignalSpy completed(m_manager.get(), &CardArtManager::deckExportFinished);
    const QUrl remote(QStringLiteral("https://example.test/artpack"));
    m_manager->exportDeckPack(remote, cards);
    QCOMPARE(completed.count(), 1);
    QCOMPARE(completed.last().first().toMap().value(QStringLiteral("fileUrl")).toString(),
             remote.toString());
    QVERIFY(!completed.last().first().toMap().value(QStringLiteral("ok")).toBool());
    m_manager->exportDeckPack(destination, {});
    QCOMPARE(completed.count(), 2);
    QVERIFY(!m_manager->busy());
    m_manager->setOperationGuard([] { return false; });
    m_manager->exportDeckPack(destination, cards);
    QCOMPARE(completed.count(), 3);
    QVERIFY(!m_manager->busy());
    m_manager->setOperationGuard([] { return true; });
    m_manager->refresh();
    QVERIFY(m_manager->busy());
    m_manager->exportDeckPack(destination, cards);
    QCOMPARE(completed.count(), 4);
    QVERIFY(m_manager->busy());
    QTRY_VERIFY(!m_manager->busy());
    QVERIFY(!QFileInfo::exists(destination.toLocalFile()));
    for (const auto &signal : completed) {
        const QVariantMap result = signal.first().toMap();
        QVERIFY(!result.value(QStringLiteral("ok")).toBool());
        QVERIFY(!result.value(QStringLiteral("error")).toString().isEmpty());
    }
}

void CardArtManagerAuditTest::suggestedDeckExportNamesStayInDownloadDirectory()
{
    setupManager(hexproof::client::catalog_internal::kCardFaceAuditVersion, false);
    const QUrl safe = m_manager->suggestedDeckExportUrl(QStringLiteral("safe cube"));
    const QUrl unsafe =
        m_manager->suggestedDeckExportUrl(QStringLiteral("../../cube\\bad:*?<>|\""));
    QVERIFY(safe.isLocalFile());
    QCOMPARE(QFileInfo(safe.toLocalFile()).absolutePath(),
             QFileInfo(unsafe.toLocalFile()).absolutePath());
    QVERIFY(QFileInfo(safe.toLocalFile()).fileName().contains(QStringLiteral("safe cube")));
    QVERIFY(
        QFileInfo(unsafe.toLocalFile()).fileName().endsWith(QStringLiteral(".hexproof-artpack")));
    QVERIFY(!QFileInfo(unsafe.toLocalFile()).fileName().contains(QLatin1Char('\\')));
    QVERIFY(!QFileInfo(unsafe.toLocalFile()).fileName().contains(QLatin1Char(':')));
    QVERIFY(!m_manager->suggestedDeckExportUrl(QString{}).isEmpty());
    for (const QString &name :
         {QString(100, QChar(0x4e2d)), QString(59, QChar(0x4e2d)) + QString::fromUtf8("🎲Cube")}) {
        const QString fileName =
            QFileInfo(m_manager->suggestedDeckExportUrl(name).toLocalFile()).fileName();
        QVERIFY(fileName.toUtf8().size() <= 255);
        QCOMPARE(QString::fromUtf8(fileName.toUtf8()), fileName);
    }
}

void CardArtManagerAuditTest::setupManager(int auditVersion, bool repairNeeded)
{
    m_dir = std::make_unique<QTemporaryDir>();
    const QString root = m_dir->path();
    m_cache = std::make_unique<CardArtCache>(root);
    m_cache->setFaceAuditState(auditVersion, repairNeeded);
    m_cache->save();
    // auditCardArt refuses to run without a card database file; its content is
    // irrelevant to the gate, an empty placeholder is enough.
    QFile database(QDir(root).filePath(QStringLiteral("cards.sqlite")));
    QVERIFY(database.open(QIODevice::WriteOnly));
    database.close();

    m_manager = std::make_unique<CardArtManager>(root, m_cache.get());
    m_manager->setAuditRequestProvider([] { return QVariantList{}; },
                                       [] { return QStringLiteral("en"); });
}

void CardArtManagerAuditTest::auditResumesWhenRepairStillNeeded()
{
    // Simulate a repair interrupted mid-download: the audit version is already
    // persisted as current but repairNeeded is still flagged. The startup
    // audit must re-run instead of returning at the version gate, or the
    // stale flag can never clear without another manual repair.
    setupManager(hexproof::client::catalog_internal::kCardFaceAuditVersion, true);

    QSignalSpy finished(m_manager.get(), &CardArtManager::auditFinished);
    m_manager->auditCardArt(false);

    QTRY_COMPARE(finished.count(), 1);
    QVERIFY(!m_manager->busy());
}

void CardArtManagerAuditTest::auditSkipsWhenCurrentAndHealthy()
{
    setupManager(hexproof::client::catalog_internal::kCardFaceAuditVersion, false);

    QSignalSpy finished(m_manager.get(), &CardArtManager::auditFinished);
    m_manager->auditCardArt(false);

    QTest::qWait(200);
    QCOMPARE(finished.count(), 0);
    QVERIFY(!m_manager->busy());
}

void CardArtManagerAuditTest::reimportingExportDoesNotCreateUnusedImages()
{
    setupManager(hexproof::client::catalog_internal::kCardFaceAuditVersion, false);
    hexproof::client::CardRecord record;
    record.name = record.requestedName = QStringLiteral("Island");
    record.setCode = QStringLiteral("EOE");
    record.collectorNumber = QStringLiteral("269");
    record.imageLanguage = QStringLiteral("en");
    record.imageUrl = QStringLiteral("https://example.test/island.png");
    record.imagePath = m_cache->imagePath(record.name, record.imageUrl, record.imageLanguage);
    record.resolutionVersion = hexproof::client::catalog_internal::kCardResolutionVersion;
    const QByteArray png = QByteArray::fromBase64("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAA"
                                                  "C0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=");
    QFile image(record.imagePath);
    QVERIFY(image.open(QIODevice::WriteOnly));
    QCOMPARE(image.write(png), png.size());
    image.close();
    const QString key =
        m_cache->key(record.name, record.imageLanguage, record.setCode, record.collectorNumber);
    m_cache->rememberSuccess(key, record);
    QVERIFY(m_cache->save());
    const QUrl archive =
        QUrl::fromLocalFile(m_dir->filePath(QStringLiteral("share.hexproof-artpack")));
    m_manager->exportPack(archive, false);
    QTRY_VERIFY(!m_manager->busy());
    QVERIFY(m_manager->lastError().isEmpty());
    for (int attempt = 0; attempt < 2; ++attempt) {
        m_manager->importPack(archive);
        QTRY_VERIFY(!m_manager->busy());
        QVERIFY(m_manager->lastError().isEmpty());
        QCOMPARE(m_cache->exactRecord(key).imagePath, record.imagePath);
        QCOMPARE(m_manager->inventory().value(QStringLiteral("imageCount")).toInt(), 1);
        QCOMPARE(m_manager->inventory().value(QStringLiteral("orphanCount")).toInt(), 0);
    }
}

void CardArtManagerAuditTest::importingPackRepairsCorruptCachedFile()
{
    setupManager(hexproof::client::catalog_internal::kCardFaceAuditVersion, false);
    hexproof::client::CardRecord record;
    record.name = record.requestedName = QStringLiteral("Island");
    record.setCode = QStringLiteral("EOE");
    record.collectorNumber = QStringLiteral("269");
    record.imageLanguage = QStringLiteral("en");
    record.imageUrl = QStringLiteral("https://cards.scryfall.io/normal/front/island.png");
    record.imagePath = m_cache->imagePath(record.name, record.imageUrl, record.imageLanguage);
    record.resolutionVersion = hexproof::client::catalog_internal::kCardResolutionVersion;
    const QByteArray png = QByteArray::fromBase64("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAA"
                                                  "C0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=");
    QFile image(record.imagePath);
    QVERIFY(image.open(QIODevice::WriteOnly));
    QCOMPARE(image.write(png), png.size());
    image.close();
    const QString key =
        m_cache->key(record.name, record.imageLanguage, record.setCode, record.collectorNumber);
    m_cache->rememberSuccess(key, record);
    QVERIFY(m_cache->save());
    const QUrl archive =
        QUrl::fromLocalFile(m_dir->filePath(QStringLiteral("repair.hexproof-artpack")));
    m_manager->exportPack(archive, false);
    QTRY_VERIFY(!m_manager->busy());
    QVERIFY(m_manager->lastError().isEmpty());
    QVERIFY(image.open(QIODevice::WriteOnly | QIODevice::Truncate));
    image.close();
    QSignalSpy changed(m_manager.get(), &CardArtManager::contentsChanged);
    m_manager->importPack(archive);
    QTRY_VERIFY(!m_manager->busy());
    QVERIFY(m_manager->lastError().isEmpty());
    QCOMPARE(changed.count(), 1);
    QFile repaired(m_cache->exactRecord(key).imagePath);
    QVERIFY(repaired.open(QIODevice::ReadOnly));
    QCOMPARE(repaired.readAll(), png);
    QCOMPARE(m_manager->lastResult(), QStringLiteral("Card art pack imported."));
    // A second repair replaces the same content-hash path, so metadata equality
    // must not suppress the notification that invalidates rendered images.
    repaired.close();
    QVERIFY(repaired.open(QIODevice::WriteOnly | QIODevice::Truncate));
    repaired.close();
    m_manager->importPack(archive);
    QTRY_VERIFY(!m_manager->busy());
    QVERIFY(m_manager->lastError().isEmpty());
    QCOMPARE(changed.count(), 2);
    QVERIFY(repaired.open(QIODevice::ReadOnly));
    QCOMPARE(repaired.readAll(), png);
}

QTEST_MAIN(CardArtManagerAuditTest)
#include "cardartmanager_test.moc"
