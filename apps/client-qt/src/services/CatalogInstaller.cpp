// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "CatalogInstaller.h"

#include "CardCatalogCommon.h"
#include "CatalogImport.h"
#include "NetworkRequestFactory.h"

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QTimer>
#include <QtConcurrent>

namespace hexproof::client {
using namespace catalog_internal;

CatalogInstaller::CatalogInstaller(QString storageRoot, QString databasePath,
                                   QNetworkAccessManager *network, QObject *parent)
    : QObject(parent),
      m_storageRoot(std::move(storageRoot)),
      m_databasePath(std::move(databasePath)),
      m_network(network)
{
    connect(&m_importWatcher, &QFutureWatcher<CatalogImportResult>::finished, this, [this]() {
        const CatalogImportResult result = m_importWatcher.result();
        if (result.cancelled) {
            completeOperation();
            return;
        }
        if (onImportFinished)
            onImportFinished(result);
        else
            completeOperation();
    });
}

CatalogInstaller::~CatalogInstaller()
{
    disconnect(&m_importWatcher, nullptr, this, nullptr);
    // Deliberately not waiting for the import: the worker may be blocked on the
    // catalog write lock that our caller still holds, so waiting here would
    // deadlock. The worker owns its staged file and cleans it up after the stop
    // request. See installerDestructionCancelsImportWithoutBlocking.
    cancelImport();
    const auto replies = m_replies;
    for (QNetworkReply *reply : replies) {
        disconnect(reply, nullptr, this, nullptr);
        reply->abort();
    }
    if (m_bulkFile)
        m_bulkFile->close();
}

void CatalogInstaller::startOperation(const QString &packageType)
{
    m_packageType = packageType;
    if (!m_busy) {
        m_busy = true;
        if (onBusyChanged)
            onBusyChanged(true);
    }
    setProgress(0.0);
}

void CatalogInstaller::setProgress(qreal progress)
{
    if (onProgressChanged)
        onProgressChanged(qBound<qreal>(0.0, progress, 1.0));
}

void CatalogInstaller::setStatus(const QString &status)
{
    if (onStatusChanged)
        onStatusChanged(status);
}

void CatalogInstaller::fail(const QString &error)
{
    if (onFailed)
        onFailed(error.isEmpty() ? QStringLiteral("Catalog update failed.") : error);
}

void CatalogInstaller::startImport(ImportKind kind, const QString &source, const QString &package,
                                   qint64 expandedSize, const QByteArray &compressedSha256,
                                   const QByteArray &databaseSha256)
{
    m_importStopSource = CatalogImportStopSource{};
    const CatalogImportStopToken stopToken = m_importStopSource.token();
    const QString destination = m_databasePath;
    if (kind == ImportKind::OfficialDatabase) {
        m_importWatcher.setFuture(QtConcurrent::run(
            [source, destination, expandedSize, compressedSha256, databaseSha256, stopToken]() {
                return catalogimport::importCompressedDatabaseFile(
                    source, destination, expandedSize, compressedSha256, databaseSha256, stopToken);
            }));
        return;
    }
    m_importWatcher.setFuture(QtConcurrent::run([source, destination, package, stopToken]() {
        if (stopToken.stopRequested())
            return CatalogImportResult{false, {}, 0, 0, 0, {}, 0, true};
        QFile input(source);
        if (!input.open(QIODevice::ReadOnly)) {
            return CatalogImportResult{
                false, QStringLiteral("Could not open the selected catalog file."), 0};
        }
        const QByteArray signature = input.peek(16);
        input.close();
        if (signature == QByteArrayLiteral("SQLite format 3\0"))
            return catalogimport::importDatabaseFile(source, destination, stopToken);
        return catalogimport::importBulkFile(source, destination, package, {}, {}, stopToken);
    }));
}

void CatalogInstaller::cancelImport()
{
    m_importStopSource.requestStop();
}

void CatalogInstaller::trackReply(QNetworkReply *reply)
{
    m_replies.insert(reply);
}

void CatalogInstaller::releaseReply(QNetworkReply *reply)
{
    m_replies.remove(reply);
    reply->deleteLater();
}

QNetworkRequest CatalogInstaller::requestFor(const QUrl &url, const QByteArray &accept,
                                             int transferTimeoutMs) const
{
    return makeNetworkRequest(url, accept, transferTimeoutMs);
}

void CatalogInstaller::downloadCatalog(const QString &packageType)
{
    const QString normalized = packageType.toLower();
    if (m_busy)
        return;
    if (normalized != QStringLiteral("default_cards")) {
        if (onValidationError)
            onValidationError(QStringLiteral("Hexproof uses the Default Cards package."));
        return;
    }
    startOperation(normalized);
    setStatus(QStringLiteral("Checking the official card database…"));
    requestOfficialCatalogManifest();
}

void CatalogInstaller::importCatalogFile(const QUrl &fileUrl, const QString &packageType)
{
    const QString normalized = packageType.toLower();
    if (m_busy)
        return;
    if (normalized != QStringLiteral("default_cards")) {
        if (onValidationError)
            onValidationError(QStringLiteral("Hexproof uses the Default Cards package."));
        return;
    }
    if (!fileUrl.isLocalFile() || !QFileInfo(fileUrl.toLocalFile()).isReadable()) {
        if (onValidationError)
            onValidationError(QStringLiteral("Choose a readable local catalog file."));
        return;
    }

    startOperation(normalized);
    m_bulkPartPath.clear();
    setProgress(0.8);
    setStatus(QStringLiteral("Importing the local card catalog…"));
    startImport(ImportKind::LocalFile, fileUrl.toLocalFile(), normalized);
}

void CatalogInstaller::downloadTokenCatalog()
{
    downloadCatalog(QStringLiteral("default_cards"));
}

void CatalogInstaller::completeOperation()
{
    if (m_bulkFile) {
        m_bulkFile->close();
        m_bulkFile.reset();
    }
    if (!m_bulkPartPath.isEmpty())
        QFile::remove(m_bulkPartPath);
    m_bulkPartPath.clear();
    m_bulkWriteFailed = false;
    m_bulkBytesWritten = 0;
    m_bulkSizeLimit = 0;
    if (m_busy) {
        m_busy = false;
        if (onBusyChanged)
            onBusyChanged(false);
    }
}

} // namespace hexproof::client
