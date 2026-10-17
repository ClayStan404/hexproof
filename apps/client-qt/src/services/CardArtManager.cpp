// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "CardArtManager.h"

#include "BackgroundTaskPools.h"
#include "CardArtArchive.h"
#include "CardArtCache.h"
#include "CardCatalogCommon.h"

#include <QDate>
#include <QDir>
#include <QElapsedTimer>
#include <QFileInfo>
#include <QFutureWatcher>
#include <QPointer>
#include <QRegularExpression>
#include <QStandardPaths>
#include <QTimer>
#include <QtConcurrent>

namespace hexproof::client {

CardArtManager::CardArtManager(QString storageRoot, CardArtCache *cache, QObject *parent)
    : QObject(parent),
      m_storageRoot(std::move(storageRoot)),
      m_databasePath(QDir(m_storageRoot).filePath(QStringLiteral("cards.sqlite"))),
      m_cache(cache)
{
    m_repairNeeded = m_cache && m_cache->faceRepairNeeded();
}

CardArtManager::~CardArtManager()
{
    // Keep the profile and storage locks alive until workers stop writing.
    for (auto *watcher : findChildren<QFutureWatcherBase *>())
        watcher->waitForFinished();
    // The worker may finish during shutdown without delivering its queued
    // completion. Its new files still belong to this uncommitted import.
    if (m_importWatcher)
        m_uncommittedImportImages.unite(m_importWatcher->result().createdImagePaths);
    // Closing during a frame-paced index update cancels that transaction.
    // The cache's generation guard prevents an older writer restoring it.
    if (m_rollback)
        m_rollback();
    if (!m_uncommittedImportImages.isEmpty()) {
        const QString imageRoot = storagePath();
        const QSet<QString> referenced = m_cache->referencedImagePaths();
        const QSet<QString> paths = std::move(m_uncommittedImportImages);
        auto cleanup = QtConcurrent::run(
            BackgroundTaskPools::catalogMaintenance(), [imageRoot, referenced, paths] {
                return cardart::removeUnreferencedFiles(imageRoot, referenced, paths, false);
            });
        // Do not release profile/storage ownership while rollback still writes.
        cleanup.waitForFinished();
    }
}

QString CardArtManager::storagePath() const
{
    return m_cache ? m_cache->imageRoot() : QDir(m_storageRoot).filePath(QStringLiteral("images"));
}

void CardArtManager::setOperationGuard(std::function<bool()> guard)
{
    m_operationGuard = std::move(guard);
}

void CardArtManager::setInspectionGuard(std::function<bool()> guard)
{
    m_inspectionGuard = std::move(guard);
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

void CardArtManager::saveCache(std::function<void(bool)> completion)
{
    m_cache->saveAsync(
        [guard = QPointer<CardArtManager>(this), completion = std::move(completion)](bool ok) {
            if (guard) {
                if (!ok && guard->m_rollback)
                    guard->m_rollback();
                guard->m_rollback = {};
                if (ok) {
                    guard->m_uncommittedImportImages.clear();
                    completion(true);
                } else {
                    guard->removeUncommittedImportImages(
                        [completion = std::move(completion)] { completion(false); });
                }
            }
        });
}

void CardArtManager::removeUncommittedImportImages(std::function<void()> completion)
{
    if (m_uncommittedImportImages.isEmpty()) {
        completion();
        return;
    }
    const QString imageRoot = storagePath();
    const QSet<QString> referenced = m_cache->referencedImagePaths();
    const QSet<QString> paths = std::move(m_uncommittedImportImages);
    auto *watcher = new QFutureWatcher<cardart::OperationResult>(this);
    connect(watcher, &QFutureWatcher<cardart::OperationResult>::finished, this,
            [watcher, completion = std::move(completion)] {
                watcher->deleteLater();
                completion();
            });
    watcher->setFuture(QtConcurrent::run(
        BackgroundTaskPools::catalogMaintenance(), [imageRoot, referenced, paths] {
            return cardart::removeUnreferencedFiles(imageRoot, referenced, paths, false);
        }));
}

void CardArtManager::applyEntries(const QList<CardArtCacheEntry> &entries,
                                  std::function<void()> completion, qsizetype next)
{
    QElapsedTimer elapsed;
    elapsed.start();
    const qsizetype limit = qMin(next + 64, entries.size());
    while (next < limit && elapsed.elapsed() < 4) {
        const auto &entry = entries.at(next++);
        m_cache->rememberSuccess(entry.cacheKey, entry.record);
    }
    if (next < entries.size()) {
        QTimer::singleShot(16, this, [this, entries, completion = std::move(completion), next] {
            applyEntries(entries, completion, next);
        });
        return;
    }
    completion();
}

bool CardArtManager::beginOperation(const QString &status, bool inspectionOnly)
{
    if (m_busy) {
        setError(QStringLiteral("Another card art operation is already running."));
        return false;
    }
    const auto &guard = inspectionOnly ? m_inspectionGuard : m_operationGuard;
    if (!m_cache || (guard && !guard())) {
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
            setStatus({});
            setBusy(false);
            emit auditFinished();
        } else {
            const bool repairNeeded = m_auditResult.repairNeeded();
            if (m_repairNeeded != repairNeeded) {
                m_repairNeeded = repairNeeded;
                emit repairNeededChanged();
            }
            m_cache->setFaceAuditState(catalog_internal::kCardFaceAuditVersion, repairNeeded);
            saveCache([this, repairNeeded](bool saved) {
                if (!saved)
                    setError(QStringLiteral("Could not update the local card art cache."));
                else if (repairNeeded)
                    setResult(QStringLiteral("Card art issues were found."));
                else
                    setResult(QStringLiteral("No card art repairs are needed."));
                setStatus({});
                setBusy(false);
                emit auditFinished();
            });
        }
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
    m_rollback = [cache = m_cache, previous, previousAuditVersion, previousRepairNeeded] {
        cache->replaceEntries(previous);
        cache->setFaceAuditState(previousAuditVersion, previousRepairNeeded);
    };
    const bool repairedLocally = !m_auditResult.repairedEntries.isEmpty();
    const QVariantList missingRequests = m_auditResult.missingRequests;
    applyEntries(m_auditResult.repairedEntries, [this, repairedLocally, missingRequests] {
        m_cache->setFaceAuditState(catalog_internal::kCardFaceAuditVersion, true);
        saveCache([this, repairedLocally, missingRequests](bool saved) {
            if (!saved) {
                setError(QStringLiteral("Could not update the local card art cache."));
                setStatus({});
                setBusy(false);
                return;
            }
            if (repairedLocally)
                emit contentsChanged();
            setResult(missingRequests.isEmpty()
                          ? QStringLiteral("Local card art mappings repaired.")
                          : QStringLiteral("Local repairs completed; downloading "
                                           "missing card faces…"));
            setStatus({});
            setBusy(false);
            if (!missingRequests.isEmpty())
                emit repairDownloadsRequested(missingRequests);
            else
                QTimer::singleShot(0, this, &CardArtManager::repeatAuditAfterRepair);
        });
    });
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
    // Inspection reads a cache snapshot and validates files on the worker.
    // Pending downloads must not discard a selection made in a native chooser.
    if (!beginOperation(QStringLiteral("Inspecting card art pack…"), true)) {
        m_packPreview = {{QStringLiteral("ok"), false}, {QStringLiteral("error"), m_lastError}};
        emit packInspectionFinished();
        return;
    }

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

QUrl CardArtManager::suggestedDeckExportUrl(const QString &deckName) const
{
    QString directory = QStandardPaths::writableLocation(QStandardPaths::DownloadLocation);
    if (directory.isEmpty())
        directory = QDir::homePath();
    QString scope = deckName.simplified();
    scope.replace(QRegularExpression(QStringLiteral("[<>:\"/\\\\|?*\\x00-\\x1f]")),
                  QStringLiteral("-"));
    // Leave room for the prefix/suffix within a portable 255-byte filename,
    // including UTF-8 Chinese names, without splitting a surrogate pair.
    scope = scope.left(60);
    if (!scope.isEmpty() && scope.back().isHighSurrogate())
        scope.chop(1);
    if (scope.isEmpty())
        scope = QStringLiteral("deck");
    const QString name = QStringLiteral("hexproof-card-art-%1-%2.hexproof-artpack")
                             .arg(scope, QDate::currentDate().toString(QStringLiteral("yyyyMMdd")));
    return QUrl::fromLocalFile(QDir(directory).filePath(name));
}

void CardArtManager::exportDeckPack(const QUrl &fileUrl, const QVariantList &cards)
{
    const auto reject = [this, fileUrl](const QString &error) {
        setError(error);
        emit deckExportFinished({{QStringLiteral("ok"), false},
                                 {QStringLiteral("error"), error},
                                 {QStringLiteral("fileUrl"), fileUrl.toString()}});
    };
    const QString path = localPath(fileUrl, true);
    if (path.isEmpty()) {
        reject(QStringLiteral("Choose a writable local destination for the card art pack."));
        return;
    }
    if (cards.isEmpty()) {
        reject(QStringLiteral("This deck has no cards to export."));
        return;
    }
    if (!beginOperation(QStringLiteral("Exporting deck card art pack…"))) {
        emit deckExportFinished({{QStringLiteral("ok"), false},
                                 {QStringLiteral("error"), m_lastError},
                                 {QStringLiteral("fileUrl"), fileUrl.toString()}});
        return;
    }

    const QString imageRoot = storagePath();
    const QString databasePath = m_databasePath;
    const QList<CardArtCacheEntry> entries = m_cache->entries();
    auto *watcher = new QFutureWatcher<cardart::DeckExportResult>(this);
    connect(watcher, &QFutureWatcher<cardart::DeckExportResult>::finished, this,
            [this, watcher, fileUrl]() {
                const cardart::DeckExportResult result = watcher->result();
                watcher->deleteLater();
                if (result.operation.ok) {
                    setResult(result.missingFaceCount > 0 || result.operation.skippedCount > 0
                                  ? QStringLiteral(
                                        "Card art pack exported with unavailable entries skipped.")
                                  : QStringLiteral("Card art pack exported."));
                } else {
                    setError(result.operation.error);
                }
                setStatus({});
                setBusy(false);
                QVariantMap summary = result.summary();
                summary.insert(QStringLiteral("fileUrl"), fileUrl.toString());
                emit deckExportFinished(summary);
            });
    watcher->setFuture(QtConcurrent::run(BackgroundTaskPools::catalogMaintenance(),
                                         [path, imageRoot, databasePath, cards, entries]() {
                                             return cardart::exportDeckPack(
                                                 path, imageRoot, databasePath, cards, entries);
                                         }));
}

void CardArtManager::importPack(const QUrl &fileUrl)
{
    const QString path = localPath(fileUrl, false);
    if (path.isEmpty()) {
        setError(QStringLiteral("Choose a readable local card art pack."));
        return;
    }
    if (!beginOperation(QStringLiteral("Importing card art pack…")))
        return;

    const QString imageRoot = storagePath();
    const QList<CardArtCacheEntry> existingEntries = m_cache->entries();
    auto *watcher = new QFutureWatcher<cardart::OperationResult>(this);
    m_importWatcher = watcher;
    connect(watcher, &QFutureWatcher<cardart::OperationResult>::finished, this, [this, watcher]() {
        const cardart::OperationResult result = watcher->result();
        m_importWatcher = nullptr;
        watcher->deleteLater();
        if (!result.ok) {
            setError(result.error);
            setStatus(QStringLiteral("Scanning the local card art cache…"));
            startInventoryScan();
            return;
        }

        const QList<CardArtCacheEntry> previous = m_cache->entries();
        m_uncommittedImportImages = result.createdImagePaths;
        m_rollback = [cache = m_cache, previous] { cache->replaceEntries(previous); };
        const bool imported = !result.importedEntries.isEmpty();
        applyEntries(result.importedEntries, [this, imported] {
            saveCache([this, imported](bool saved) {
                if (!saved) {
                    setError(QStringLiteral("Could not update the local card art cache."));
                } else {
                    setResult(imported
                                  ? QStringLiteral("Card art pack imported.")
                                  : QStringLiteral("Every image in this pack is already cached."));
                    if (imported)
                        emit contentsChanged();
                }
                setStatus(QStringLiteral("Scanning the local card art cache…"));
                startInventoryScan();
            });
        });
    });
    watcher->setFuture(QtConcurrent::run(
        BackgroundTaskPools::catalogMaintenance(), [path, imageRoot, existingEntries]() {
            auto result = cardart::importPack(path, imageRoot, existingEntries);
            // The maintenance guard keeps this snapshot authoritative until
            // commit; file validation already happened on this worker.
            result.importedEntries.removeIf([&result](const CardArtCacheEntry &entry) {
                return result.retainedEntryKeys.contains(entry.cacheKey);
            });
            return result;
        }));
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
    m_rollback = [cache = m_cache, previous] { cache->replaceEntries(previous); };
    const QString imageRoot = storagePath();
    const QSet<QString> referenced = m_cache->referencedImagePaths();
    saveCache([this, removed, imageRoot, referenced, selectionOnly](bool saved) {
        if (!saved) {
            setError(QStringLiteral("Could not update the local card art cache."));
            setStatus({});
            setBusy(false);
            return;
        }
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
        watcher->setFuture(
            QtConcurrent::run(BackgroundTaskPools::catalogMaintenance(),
                              [imageRoot, referenced, removed, removeAll = !selectionOnly]() {
                                  QSet<QString> candidates;
                                  for (const auto &entry : removed) {
                                      if (!entry.record.imagePath.isEmpty())
                                          candidates.insert(entry.record.imagePath);
                                  }
                                  return cardart::removeUnreferencedFiles(imageRoot, referenced,
                                                                          candidates, removeAll);
                              }));
    });
}

} // namespace hexproof::client
