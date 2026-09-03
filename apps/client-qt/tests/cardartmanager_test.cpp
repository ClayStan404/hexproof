// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

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

  private:
    void setupManager(int auditVersion, bool repairNeeded);

    std::unique_ptr<QTemporaryDir> m_dir;
    std::unique_ptr<CardArtCache> m_cache;
    std::unique_ptr<CardArtManager> m_manager;
};

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

QTEST_MAIN(CardArtManagerAuditTest)
#include "cardartmanager_test.moc"
