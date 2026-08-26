// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#pragma once

#include <QByteArray>
#include <QObject>
#include <QString>
#include <QUrl>

#include <memory>

class QCryptographicHash;
class QNetworkAccessManager;
class QNetworkReply;
class QSaveFile;

namespace hexproof::client {

class AppUpdateService final : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString currentVersion READ currentVersion CONSTANT)
    Q_PROPERTY(QString targetVersion READ targetVersion NOTIFY stateChanged)
    Q_PROPERTY(QString releaseName READ releaseName NOTIFY stateChanged)
    Q_PROPERTY(QString releaseNotes READ releaseNotes NOTIFY stateChanged)
    Q_PROPERTY(QString publishedAt READ publishedAt NOTIFY stateChanged)
    Q_PROPERTY(QString releaseUrl READ releaseUrl NOTIFY stateChanged)
    Q_PROPERTY(bool exactVersion READ exactVersion NOTIFY stateChanged)
    Q_PROPERTY(bool releaseAvailable READ releaseAvailable NOTIFY stateChanged)
    Q_PROPERTY(bool updateAvailable READ updateAvailable NOTIFY stateChanged)
    Q_PROPERTY(bool checking READ checking NOTIFY stateChanged)
    Q_PROPERTY(bool downloading READ downloading NOTIFY stateChanged)
    Q_PROPERTY(qreal progress READ progress NOTIFY progressChanged)
    Q_PROPERTY(bool downloadReady READ downloadReady NOTIFY stateChanged)
    Q_PROPERTY(QString downloadPath READ downloadPath NOTIFY stateChanged)
    Q_PROPERTY(QString lastError READ lastError NOTIFY stateChanged)

  public:
    explicit AppUpdateService(QObject *parent = nullptr);
    AppUpdateService(const QString &downloadRoot, QNetworkAccessManager *network,
                     QObject *parent = nullptr);
    ~AppUpdateService() override;

    QString currentVersion() const;
    QString targetVersion() const;
    QString releaseName() const;
    QString releaseNotes() const;
    QString publishedAt() const;
    QString releaseUrl() const;
    bool exactVersion() const;
    bool releaseAvailable() const;
    bool updateAvailable() const;
    bool checking() const;
    bool downloading() const;
    qreal progress() const;
    bool downloadReady() const;
    QString downloadPath() const;
    QString lastError() const;

    Q_INVOKABLE void checkForUpdates();
    Q_INVOKABLE void checkForVersion(const QString &version);
    Q_INVOKABLE void checkAutomatically();
    Q_INVOKABLE void downloadUpdate();
    Q_INVOKABLE void cancelDownload();
    Q_INVOKABLE bool openDownloadLocation();
    Q_INVOKABLE bool openReleasePage();
    Q_INVOKABLE void clearLastError();

  signals:
    void stateChanged();
    void progressChanged();

  private:
    struct ReleaseInfo
    {
        QString version;
        QString name;
        QString notes;
        QString publishedAt;
        QUrl releaseUrl;
        QString assetName;
        QUrl assetUrl;
        qint64 assetSize = 0;
        QUrl checksumsUrl;
        QByteArray checksum;
        bool exact = false;
    };

    void requestRelease(const QUrl &apiUrl, const QString &exactVersion = {});
    void handleReleaseReply(QNetworkReply *reply);
    void requestChecksums(ReleaseInfo release);
    void handleChecksumsReply(QNetworkReply *reply);
    void applyRelease(ReleaseInfo release);
    void finishCheckWithError(const QString &error);
    void loadCachedLatestRelease();
    void cacheLatestRelease() const;
    void recordLatestCheckAttempt() const;
    bool automaticCheckIsDue() const;

    bool readDownloadData();
    void finishDownload(QNetworkReply *reply);
    void failDownload(const QString &error);
    void resetDownloadedUpdate();
    void setLastError(const QString &error);

    static QString defaultDownloadRoot();
    static QString platformAssetName(const QString &version);
    static bool validVersion(const QString &version);
    static int compareVersions(const QString &left, const QString &right);
    static bool officialReleaseUrl(const QUrl &url, const QString &tag, const QString &assetName);
    static bool officialReleasePageUrl(const QUrl &url, const QString &tag);
    static ReleaseInfo parseRelease(const QByteArray &payload, const QString &exactVersion);
    static QByteArray checksumForAsset(const QByteArray &payload, const QString &assetName);

    QString m_currentVersion;
    QString m_downloadRoot;
    std::unique_ptr<QNetworkAccessManager> m_ownedNetwork;
    QNetworkAccessManager *m_network = nullptr;
    QNetworkReply *m_checkReply = nullptr;
    QNetworkReply *m_downloadReply = nullptr;
    ReleaseInfo m_release;
    ReleaseInfo m_pendingRelease;
    QString m_requestedExactVersion;
    bool m_checking = false;
    bool m_automaticCheckStarted = false;
    bool m_downloading = false;
    bool m_downloadCancelled = false;
    bool m_downloadWriteFailed = false;
    qreal m_progress = 0.0;
    qint64 m_downloadedBytes = 0;
    std::unique_ptr<QSaveFile> m_downloadFile;
    std::unique_ptr<QCryptographicHash> m_downloadHash;
    bool m_downloadReady = false;
    QString m_downloadPath;
    QString m_lastError;
};

} // namespace hexproof::client
