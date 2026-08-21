// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "CardCatalogCommon.h"
#include "CatalogInstaller.h"
#include "CatalogReleaseManifest.h"
#include "NetworkLimits.h"

namespace hexproof::client {
using namespace catalog_internal;

void CatalogInstaller::requestOfficialCatalogManifest()
{
    QNetworkReply *reply =
        m_network->get(requestFor(QUrl(QString::fromLatin1(kOfficialCatalogManifestUrl)),
                                  QByteArrayLiteral("application/json;q=0.9,*/*;q=0.8")));
    network_limits::limitNetworkReply(reply, network_limits::kMaximumJsonResponseBytes);
    trackReply(reply);
    connect(reply, &QNetworkReply::finished, this, [this, reply]() {
        const QByteArray payload = takeAvailableData(reply);
        const bool networkOk = reply->error() == QNetworkReply::NoError;
        const QString networkError = reply->errorString();
        releaseReply(reply);

        if (!networkOk) {
            qCWarning(cardCatalogLog).noquote()
                << "Official card database manifest request failed:" << networkError;
            fail(QStringLiteral("The official card database is unavailable. Import an offline "
                                "database or try again later."));
            return;
        }

        const CatalogReleaseManifest manifest = parseCatalogReleaseManifest(payload);
        if (!manifest.valid) {
            fail(QStringLiteral("The official card database manifest is invalid."));
            return;
        }
        if (!manifest.compatible()) {
            fail(QStringLiteral("The latest card database requires a newer Hexproof version."));
            return;
        }
        startOfficialCatalogDownload(QUrl(QString::fromLatin1(kOfficialCatalogAssetUrl)),
                                     manifest.compressedSize, manifest.uncompressedSize,
                                     manifest.compressedSha256, manifest.databaseSha256);
    });
}

void CatalogInstaller::startOfficialCatalogDownload(const QUrl &url, qint64 compressedSize,
                                                    qint64 uncompressedSize,
                                                    const QByteArray &compressedSha256,
                                                    const QByteArray &databaseSha256, int attempt)
{
    m_bulkPartPath = QDir(m_storageRoot).filePath(QStringLiteral("cards-official.sqlite.gz.part"));
    m_bulkFile = std::make_unique<QFile>(m_bulkPartPath);
    if (!m_bulkFile->open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        fail(QStringLiteral("Could not create the official database download file."));
        return;
    }
    m_bulkWriteFailed = false;
    m_bulkBytesWritten = 0;
    m_bulkSizeLimit = compressedSize;
    setStatus(QStringLiteral("Downloading the official card database…"));
    QNetworkReply *reply = m_network->get(
        requestFor(url, QByteArrayLiteral("application/gzip,application/octet-stream,*/*"),
                   kLargeDownloadTransferTimeoutMs));
    trackReply(reply);
    connect(reply, &QNetworkReply::readyRead, this, [this, reply]() {
        if (!m_bulkFile)
            return;
        const QByteArray bytes = takeAvailableData(reply);
        if (m_bulkBytesWritten + bytes.size() > m_bulkSizeLimit ||
            m_bulkFile->write(bytes) != bytes.size()) {
            m_bulkWriteFailed = true;
            reply->abort();
        } else {
            m_bulkBytesWritten += bytes.size();
        }
    });
    connect(reply, &QNetworkReply::downloadProgress, this,
            [this, compressedSize](qint64 received, qint64) {
                setProgress(static_cast<qreal>(received) / static_cast<qreal>(compressedSize) *
                            0.8);
            });
    connect(reply, &QNetworkReply::finished, this,
            [this, reply, url, compressedSize, uncompressedSize, compressedSha256, databaseSha256,
             attempt]() {
                if (m_bulkFile) {
                    const QByteArray tail = takeAvailableData(reply);
                    if (!tail.isEmpty()) {
                        if (m_bulkBytesWritten + tail.size() > m_bulkSizeLimit ||
                            m_bulkFile->write(tail) != tail.size()) {
                            m_bulkWriteFailed = true;
                        } else {
                            m_bulkBytesWritten += tail.size();
                        }
                    }
                    m_bulkFile->close();
                }
                const bool networkOk = reply->error() == QNetworkReply::NoError;
                const QString networkError = reply->errorString();
                releaseReply(reply);
                m_bulkFile.reset();

                if (!networkOk || m_bulkWriteFailed || m_bulkBytesWritten != compressedSize) {
                    if (!m_bulkWriteFailed && attempt < 2) {
                        QFile::remove(m_bulkPartPath);
                        setStatus(QStringLiteral(
                            "Connection interrupted; retrying the official card database…"));
                        QTimer::singleShot(750 * (attempt + 1), this,
                                           [this, url, compressedSize, uncompressedSize,
                                            compressedSha256, databaseSha256, attempt]() {
                                               startOfficialCatalogDownload(
                                                   url, compressedSize, uncompressedSize,
                                                   compressedSha256, databaseSha256, attempt + 1);
                                           });
                        return;
                    }
                    if (!m_bulkWriteFailed) {
                        qCWarning(cardCatalogLog).noquote()
                            << "Official card database download failed:" << networkError;
                    }
                    fail(m_bulkWriteFailed
                             ? QStringLiteral(
                                   "The official card database could not be written to disk.")
                             : QStringLiteral("The official card database download failed."));
                    return;
                }
                startOfficialCatalogImport(uncompressedSize, compressedSha256, databaseSha256);
            });
}

void CatalogInstaller::startOfficialCatalogImport(qint64 uncompressedSize,
                                                  const QByteArray &compressedSha256,
                                                  const QByteArray &databaseSha256)
{
    setProgress(0.85);
    setStatus(QStringLiteral("Verifying and installing the official card database…"));
    startImport(ImportKind::OfficialDatabase, m_bulkPartPath, m_packageType, uncompressedSize,
                compressedSha256, databaseSha256);
}

} // namespace hexproof::client
