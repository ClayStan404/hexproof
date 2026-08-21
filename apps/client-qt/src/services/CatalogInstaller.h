// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#pragma once

#include "CatalogCancellation.h"
#include "CatalogTypes.h"

#include <QByteArray>
#include <QFutureWatcher>
#include <QObject>
#include <QSet>
#include <QString>
#include <QUrl>

#include <functional>
#include <memory>

class QFile;
class QNetworkAccessManager;
class QNetworkReply;
class QNetworkRequest;

namespace hexproof::client {

class CatalogInstaller : public QObject
{
  public:
    enum class ImportKind
    {
        LocalFile,
        OfficialDatabase
    };
    CatalogInstaller(QString storageRoot, QString databasePath, QNetworkAccessManager *network,
                     QObject *parent = nullptr);
    ~CatalogInstaller() override;

    bool busy() const
    {
        return m_busy;
    }
    QString packageType() const
    {
        return m_packageType;
    }

    void downloadCatalog(const QString &packageType);
    void importCatalogFile(const QUrl &fileUrl, const QString &packageType);
    void downloadTokenCatalog();

    void completeOperation();

  public:
    std::function<void(bool)> onBusyChanged;
    std::function<void(qreal)> onProgressChanged;
    std::function<void(const QString &)> onStatusChanged;
    std::function<void(const QString &)> onValidationError;
    std::function<void(const QString &)> onFailed;
    std::function<void(const CatalogImportResult &)> onImportFinished;

  private:
    void cancelImport();
    void startOperation(const QString &packageType);
    void setProgress(qreal progress);
    void setStatus(const QString &status);
    void fail(const QString &error);
    void startImport(ImportKind kind, const QString &source, const QString &package,
                     qint64 expandedSize = 0, const QByteArray &compressedSha256 = {},
                     const QByteArray &databaseSha256 = {});
    void trackReply(QNetworkReply *reply);
    void releaseReply(QNetworkReply *reply);

    void requestOfficialCatalogManifest();
    void startOfficialCatalogDownload(const QUrl &url, qint64 compressedSize,
                                      qint64 uncompressedSize, const QByteArray &compressedSha256,
                                      const QByteArray &databaseSha256, int attempt = 0);
    void startOfficialCatalogImport(qint64 uncompressedSize, const QByteArray &compressedSha256,
                                    const QByteArray &databaseSha256);
    QNetworkRequest requestFor(const QUrl &url, const QByteArray &accept,
                               int transferTimeoutMs = 15'000) const;

    QString m_storageRoot;
    QString m_databasePath;
    QString m_packageType;
    QString m_bulkPartPath;
    QNetworkAccessManager *m_network = nullptr;
    QSet<QNetworkReply *> m_replies;
    std::unique_ptr<QFile> m_bulkFile;
    bool m_busy = false;
    bool m_bulkWriteFailed = false;
    qint64 m_bulkBytesWritten = 0;
    qint64 m_bulkSizeLimit = 0;
    CatalogImportStopSource m_importStopSource;
    QFutureWatcher<CatalogImportResult> m_importWatcher;
};

} // namespace hexproof::client
