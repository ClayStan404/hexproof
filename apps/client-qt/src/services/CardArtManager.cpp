// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "CardArtManager.h"

#include "BackgroundTaskPools.h"
#include "CardArtArchive.h"
#include "CardArtCache.h"
#include "CardCatalogCommon.h"

#include <QDate>
#include <QDir>
#include <QFileInfo>
#include <QFutureWatcher>
#include <QStandardPaths>
#include <QTimer>
#include <QtConcurrent>

namespace hexproof::client {

namespace {

bool isManagedCacheFile(const QString &imageRoot, const QString &path)
{
    const QFileInfo file(path);
    const QFileInfo root(imageRoot);
    if (!file.isFile() || file.isSymLink())
        return false;
    const QString filePath = QDir::cleanPath(file.canonicalFilePath());
    const QString rootPath = QDir::cleanPath(root.canonicalFilePath());
    if (filePath.isEmpty() || rootPath.isEmpty())
        return false;
    const QString relative = QDir(rootPath).relativeFilePath(filePath);
    return relative != QStringLiteral("..") && !relative.startsWith(QStringLiteral("../")) &&
           !QDir::isAbsolutePath(relative);
}

} // namespace

CardArtManager::CardArtManager(QString storageRoot, CardArtCache *cache, QObject *parent)
    : QObject(parent),
      m_storageRoot(std::move(storageRoot)),
      m_databasePath(QDir(m_storageRoot).filePath(QStringLiteral("cards.sqlite"))),
      m_cache(cache)
{
    m_repairNeeded = m_cache && m_cache->faceRepairNeeded();
}

QString CardArtManager::storagePath() const
{
    return m_cache ? m_cache->imageRoot() : QDir(m_storageRoot).filePath(QStringLiteral("images"));
}

void CardArtManager::setOperationGuard(std::function<bool()> guard)
{
    m_operationGuard = std::move(guard);
}

void CardArtManager::setAuditRequestProvider(std::function<QVariantList()> provider,
                                             std::function<QString()> languageProvider)
{
    m_auditRequestProvider = std::move(provider);
    m_auditLanguageProvider = std::move(languageProvider);
}

void CardArtManager::setBusy(bool busy)
{
    if (m_busy == busy)
        return;
    m_busy = busy;
    emit busyChanged();
}

void CardArtManager::setStatus(const QString &status)
{
    if (m_status == status)
        return;
    m_status = status;
    emit statusChanged();
}

void CardArtManager::setResult(const QString &result)
{
    if (m_lastResult == result)
        return;
    m_lastResult = result;
    emit lastResultChanged();
}

void CardArtManager::setError(const QString &error)
{
    if (m_lastError == error)
        return;
    m_lastError = error;
    emit lastErrorChanged();
}

void CardArtManager::clearMessages()
{
    setResult({});
    setError({});
}

bool CardArtManager::beginOperation(const QString &status)
{
    if (m_busy) {
        setError(QStringLiteral("Another card art operation is already running."));
        return false;
    }
    if (!m_cache || (m_operationGuard && !m_operationGuard())) {
        setError(QStringLiteral("Wait for the current card operation to finish."));
        return false;
    }
    clearMessages();
    setStatus(status);
    setBusy(true);
    return true;
}

QString CardArtManager::localPath(const QUrl &fileUrl, bool forExport) const
{
    if (!fileUrl.isLocalFile())
        return {};
    QString path = fileUrl.toLocalFile();
    if (forExport && QFileInfo(path).suffix().isEmpty())
        path += QStringLiteral(".hexproof-artpack");
    return QFileInfo(path).absoluteFilePath();
}

void CardArtManager::refresh()
{
    if (!beginOperation(QStringLiteral("Scanning the local card art cache…")))
        return;
    startInventoryScan();
}

void CardArtManager::auditCardArt(bool force)
{
    if (!m_cache || !m_auditRequestProvider)
        return;
    // Re-run with a current audit version when a repair is still flagged:
    // repairAuditedCardArt persists the audit version before its downloads
    // finish, so an interrupted repair must be re-audited on startup instead
    // of being skipped at this gate forever.
    if (!force && m_cache->faceAuditVersion() >= catalog_internal::kCardFaceAuditVersion &&
        !m_cache->faceRepairNeeded())
        return;
    if (!force && (m_busy || (m_operationGuard && !m_operationGuard()))) {
        if (!m_autoAuditRetryScheduled) {
            m_autoAuditRetryScheduled = true;
            QTimer::singleShot(1'000, this, [this]() {
                m_autoAuditRetryScheduled = false;
                auditCardArt(false);
            });
        }
        return;
    }
    if (!QFileInfo::exists(m_databasePath)) {
        if (force)
            setError(QStringLiteral("Install the card database before checking card art."));
        return;
    }
    if (!beginOperation(QStringLiteral("Checking cached card faces…")))
        return;
    m_autoAuditRetryScheduled = false;
    startAudit(m_auditRequestProvider());
}

void CardArtManager::startAudit(const QVariantList &cards)
{
    const QString databasePath = m_databasePath;
    const QString imageRoot = storagePath();
    QString auditLanguage =
        m_auditLanguageProvider ? m_auditLanguageProvider().toLower() : QStringLiteral("en");
    if (auditLanguage != QStringLiteral("zh"))
        auditLanguage = QStringLiteral("en");
    const bool reuseLocalArt = m_cache && m_cache->reuseLocalArt();
    const QList<CardArtCacheEntry> entries = m_cache->entries();
    auto *watcher = new QFutureWatcher<cardart::AuditResult>(this);
    connect(watcher, &QFutureWatcher<cardart::AuditResult>::finished, this, [this, watcher]() {
        m_auditResult = watcher->result();
        watcher->deleteLater();
        emit auditResultChanged();
        if (!m_auditResult.ok) {
            setError(m_auditResult.error);
        } else {
            const bool repairNeeded = m_auditResult.repairNeeded();
            if (m_repairNeeded != repairNeeded) {
                m_repairNeeded = repairNeeded;
                emit repairNeededChanged();
            }
            m_cache->setFaceAuditState(catalog_internal::kCardFaceAuditVersion, repairNeeded);
            if (!m_cache->save()) {
                setError(QStringLiteral("Could not update the local card art cache."));
            } else if (repairNeeded) {
                setResult(QStringLiteral("Card art issues were found."));
            } else {
                setResult(QStringLiteral("No card art repairs are needed."));
            }
        }
        setStatus({});
        setBusy(false);
        emit auditFinished();
    });
    watcher->setFuture(QtConcurrent::run(
        BackgroundTaskPools::catalogMaintenance(),
        [databasePath, imageRoot, auditLanguage, reuseLocalArt, cards, entries]() {
            return cardart::auditDeckArt(databasePath, imageRoot, auditLanguage, reuseLocalArt,
                                         cards, entries);
        }));
}

void CardArtManager::repairAuditedCardArt()
{
    if (!m_auditResult.ok || !m_auditResult.repairNeeded()) {
        setError(QStringLiteral("Check the local card art before repairing it."));
        return;
    }
    if (!beginOperation(QStringLiteral("Repairing cached card faces…")))
        return;

    const QList<CardArtCacheEntry> previous = m_cache->entries();
    const int previousAuditVersion = m_cache->faceAuditVersion();
    const bool previousRepairNeeded = m_cache->faceRepairNeeded();
    for (const CardArtCacheEntry &entry : m_auditResult.repairedEntries)
        m_cache->rememberSuccess(entry.cacheKey, entry.record);
    m_cache->setFaceAuditState(catalog_internal::kCardFaceAuditVersion, true);
    if (m_cache->dirty() && !m_cache->save()) {
        m_cache->replaceEntries(previous);
        m_cache->setFaceAuditState(previousAuditVersion, previousRepairNeeded);
        setError(QStringLiteral("Could not update the local card art cache."));
        setStatus({});
        setBusy(false);
        return;
    }

    const bool repairedLocally = !m_auditResult.repairedEntries.isEmpty();
    const QVariantList missingRequests = m_auditResult.missingRequests;
    if (repairedLocally)
        emit contentsChanged();
    setResult(missingRequests.isEmpty()
                  ? QStringLiteral("Local card art mappings repaired.")
                  : QStringLiteral("Local repairs completed; downloading missing card faces…"));
    setStatus({});
    setBusy(false);
    if (!missingRequests.isEmpty()) {
        emit repairDownloadsRequested(missingRequests);
    } else {
        QTimer::singleShot(0, this, &CardArtManager::repeatAuditAfterRepair);
    }
}

void CardArtManager::repeatAuditAfterRepair()
{
    if (!m_auditRequestProvider || m_busy)
        return;
    if (!beginOperation(QStringLiteral("Checking repaired card faces…")))
        return;
    startAudit(m_auditRequestProvider());
}

void CardArtManager::startInventoryScan()
{
    const QString imageRoot = storagePath();
    const QList<CardArtCacheEntry> entries =
        m_cache ? m_cache->entries() : QList<CardArtCacheEntry>{};
    auto *watcher = new QFutureWatcher<QVariantMap>(this);
    connect(watcher, &QFutureWatcher<QVariantMap>::finished, this, [this, watcher]() {
        m_inventory = watcher->result();
        watcher->deleteLater();
        emit inventoryChanged();
        setStatus({});
        setBusy(false);
    });
    watcher->setFuture(
        QtConcurrent::run(BackgroundTaskPools::catalogMaintenance(), [imageRoot, entries]() {
            return cardart::inventory(imageRoot, entries);
        }));
}

void CardArtManager::inspectPack(const QUrl &fileUrl)
{
    const QString path = localPath(fileUrl, false);
    if (path.isEmpty()) {
        clearMessages();
        const QString error = QStringLiteral("Choose a readable local card art pack.");
        m_packPreview = {{QStringLiteral("ok"), false}, {QStringLiteral("error"), error}};
        setError(error);
        emit packInspectionFinished();
        return;
    }
    if (!beginOperation(QStringLiteral("Inspecting card art pack…")))
        return;

    const QList<CardArtCacheEntry> entries = m_cache->entries();
    const QString imageRoot = storagePath();
    auto *watcher = new QFutureWatcher<QVariantMap>(this);
    connect(watcher, &QFutureWatcher<QVariantMap>::finished, this, [this, watcher]() {
        m_packPreview = watcher->result();
        watcher->deleteLater();
        if (!m_packPreview.value(QStringLiteral("ok")).toBool())
            setError(m_packPreview.value(QStringLiteral("error")).toString());
        setStatus({});
        setBusy(false);
        emit packInspectionFinished();
    });
    watcher->setFuture(
        QtConcurrent::run(BackgroundTaskPools::catalogMaintenance(), [path, entries, imageRoot]() {
            return cardart::inspectPack(path, entries, imageRoot);
        }));
}

QUrl CardArtManager::suggestedExportUrl(bool selectionOnly, const QString &setCode,
                                        const QString &imageLanguage) const
{
    QString directory = QStandardPaths::writableLocation(QStandardPaths::DownloadLocation);
    if (directory.isEmpty())
        directory = QDir::homePath();
    QString scope = QStringLiteral("all");
    if (selectionOnly) {
        scope = setCode.isEmpty() ? QStringLiteral("unassigned") : setCode.toLower();
        if (!imageLanguage.isEmpty())
            scope += QLatin1Char('-') + imageLanguage.toLower();
    }
    const QString name = QStringLiteral("hexproof-card-art-%1-%2.hexproof-artpack")
                             .arg(scope, QDate::currentDate().toString(QStringLiteral("yyyyMMdd")));
    return QUrl::fromLocalFile(QDir(directory).filePath(name));
}

void CardArtManager::exportPack(const QUrl &fileUrl, bool selectionOnly, const QString &setCode,
                                const QString &imageLanguage)
{
    const QString path = localPath(fileUrl, true);
    if (path.isEmpty()) {
        setError(QStringLiteral("Choose a writable local destination for the card art pack."));
        return;
    }
    if (!beginOperation(QStringLiteral("Exporting card art pack…")))
        return;

    const QString imageRoot = storagePath();
    const QList<CardArtCacheEntry> entries = m_cache->entries();
    auto *watcher = new QFutureWatcher<cardart::OperationResult>(this);
    connect(watcher, &QFutureWatcher<cardart::OperationResult>::finished, this, [this, watcher]() {
        const cardart::OperationResult result = watcher->result();
        watcher->deleteLater();
        if (result.ok) {
            setResult(
                result.skippedCount > 0
                    ? QStringLiteral("Card art pack exported with unavailable entries skipped.")
                    : QStringLiteral("Card art pack exported."));
        } else {
            setError(result.error);
        }
        setStatus({});
        setBusy(false);
    });
    watcher->setFuture(
        QtConcurrent::run(BackgroundTaskPools::catalogMaintenance(),
                          [path, imageRoot, entries, selectionOnly, setCode, imageLanguage]() {
                              return cardart::exportPack(path, imageRoot, entries, selectionOnly,
                                                         setCode, imageLanguage);
                          }));
}

void CardArtManager::importPack(const QUrl &fileUrl)
{
    const QString path = localPath(fileUrl, false);
    if (path.isEmpty() || !QFileInfo(path).isReadable()) {
        setError(QStringLiteral("Choose a readable local card art pack."));
        return;
    }
    if (!beginOperation(QStringLiteral("Importing card art pack…")))
        return;

    const QString imageRoot = storagePath();
    auto *watcher = new QFutureWatcher<cardart::OperationResult>(this);
    connect(watcher, &QFutureWatcher<cardart::OperationResult>::finished, this, [this, watcher]() {
        const cardart::OperationResult result = watcher->result();
        watcher->deleteLater();
        if (!result.ok) {
            setError(result.error);
            setStatus(QStringLiteral("Scanning the local card art cache…"));
            startInventoryScan();
            return;
        }

        const QList<CardArtCacheEntry> previous = m_cache->entries();
        int imported = 0;
        for (const CardArtCacheEntry &entry : result.importedEntries) {
            const CardRecord existing = m_cache->exactRecord(entry.cacheKey);
            if (existing.valid() && isManagedCacheFile(storagePath(), existing.imagePath) &&
                existing.resolutionVersion >= entry.record.resolutionVersion) {
                continue;
            }
            m_cache->rememberSuccess(entry.cacheKey, entry.record);
            ++imported;
        }
        if (m_cache->dirty() && !m_cache->save()) {
            m_cache->replaceEntries(previous);
            setError(QStringLiteral("Could not update the local card art cache."));
            setStatus(QStringLiteral("Scanning the local card art cache…"));
            startInventoryScan();
            return;
        }
        setResult(imported > 0 ? QStringLiteral("Card art pack imported.")
                               : QStringLiteral("Every image in this pack is already cached."));
        if (imported > 0)
            emit contentsChanged();
        setStatus(QStringLiteral("Scanning the local card art cache…"));
        startInventoryScan();
    });
    watcher->setFuture(
        QtConcurrent::run(BackgroundTaskPools::catalogMaintenance(),
                          [path, imageRoot]() { return cardart::importPack(path, imageRoot); }));
}

void CardArtManager::removeOrphans()
{
    if (!beginOperation(QStringLiteral("Removing unused card image files…")))
        return;
    const QString imageRoot = storagePath();
    const QSet<QString> referenced = m_cache->referencedImagePaths();
    auto *watcher = new QFutureWatcher<cardart::OperationResult>(this);
    connect(watcher, &QFutureWatcher<cardart::OperationResult>::finished, this, [this, watcher]() {
        const cardart::OperationResult result = watcher->result();
        watcher->deleteLater();
        if (result.ok)
            setResult(QStringLiteral("Unused card image files removed."));
        else
            setError(result.error);
        setStatus(QStringLiteral("Scanning the local card art cache…"));
        startInventoryScan();
    });
    watcher->setFuture(
        QtConcurrent::run(BackgroundTaskPools::catalogMaintenance(), [imageRoot, referenced]() {
            return cardart::removeUnreferencedFiles(imageRoot, referenced, {}, true);
        }));
}

void CardArtManager::removeSelection(bool selectionOnly, const QString &setCode,
                                     const QString &imageLanguage)
{
    if (!beginOperation(QStringLiteral("Removing selected card art…")))
        return;

    const QList<CardArtCacheEntry> previous = m_cache->entries();
    const QList<CardArtCacheEntry> removed =
        m_cache->removeEntries(selectionOnly, setCode, imageLanguage);
    if (selectionOnly && removed.isEmpty()) {
        setError(QStringLiteral("No cached card images match this selection."));
        setStatus({});
        setBusy(false);
        return;
    }
    if (!removed.isEmpty() && !m_cache->save()) {
        m_cache->replaceEntries(previous);
        setError(QStringLiteral("Could not update the local card art cache."));
        setStatus({});
        setBusy(false);
        return;
    }

    QSet<QString> candidates;
    for (const CardArtCacheEntry &entry : removed) {
        if (!entry.record.imagePath.isEmpty())
            candidates.insert(entry.record.imagePath);
    }
    const QString imageRoot = storagePath();
    const QSet<QString> referenced = m_cache->referencedImagePaths();
    auto *watcher = new QFutureWatcher<cardart::OperationResult>(this);
    connect(watcher, &QFutureWatcher<cardart::OperationResult>::finished, this,
            [this, watcher, hadRemoved = !removed.isEmpty()]() {
                const cardart::OperationResult result = watcher->result();
                watcher->deleteLater();
                if (result.ok)
                    setResult(QStringLiteral("Selected card art removed."));
                else
                    setError(result.error);
                if (hadRemoved)
                    emit contentsChanged();
                setStatus(QStringLiteral("Scanning the local card art cache…"));
                startInventoryScan();
            });
    watcher->setFuture(QtConcurrent::run(
        BackgroundTaskPools::catalogMaintenance(),
        [imageRoot, referenced, candidates, removeAll = !selectionOnly]() {
            return cardart::removeUnreferencedFiles(imageRoot, referenced, candidates, removeAll);
        }));
}

} // namespace hexproof::client
