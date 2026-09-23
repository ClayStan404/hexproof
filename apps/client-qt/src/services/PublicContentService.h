// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#pragma once

#include <QDateTime>
#include <QElapsedTimer>
#include <QJsonObject>
#include <QNetworkAccessManager>
#include <QObject>
#include <QPointer>
#include <QSet>
#include <QTimer>
#include <QVariantList>

#include <functional>

namespace hexproof::client {

class PublicContentService final : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QVariantList sponsors READ sponsors NOTIFY contentChanged)
    Q_PROPERTY(QStringList newSponsorIds READ newSponsorIds NOTIFY contentChanged)
    Q_PROPERTY(QVariantList currentAnnouncements READ currentAnnouncements NOTIFY contentChanged)
    Q_PROPERTY(
        QVariantList historicalAnnouncements READ historicalAnnouncements NOTIFY contentChanged)
    Q_PROPERTY(int unreadCount READ unreadCount NOTIFY contentChanged)
    Q_PROPERTY(QString latestUnreadTitle READ latestUnreadTitle NOTIFY contentChanged)
    Q_PROPERTY(bool refreshing READ refreshing NOTIFY statusChanged)
    Q_PROPERTY(bool refreshFailed READ refreshFailed NOTIFY statusChanged)
    Q_PROPERTY(QDateTime lastChecked READ lastChecked NOTIFY statusChanged)
    Q_PROPERTY(bool startupReady READ startupReady NOTIFY startupReadyChanged)

  public:
    explicit PublicContentService(const QString &storageRoot, QObject *parent = nullptr);
    PublicContentService(const QString &storageRoot, const QStringList &sources,
                         QObject *parent = nullptr);

    QVariantList sponsors() const;
    QStringList newSponsorIds() const;
    QVariantList currentAnnouncements() const;
    QVariantList historicalAnnouncements() const;
    int unreadCount() const;
    QString latestUnreadTitle() const;
    bool refreshing() const
    {
        return m_refreshing;
    }
    bool refreshFailed() const
    {
        return m_refreshFailed;
    }
    QDateTime lastChecked() const
    {
        return m_lastChecked;
    }
    bool startupReady() const
    {
        return m_startupReady;
    }
    void setLanguage(const QString &language);
    void start();
    Q_INVOKABLE void refresh(bool force = false);
    Q_INVOKABLE QStringList takeSponsorAnnouncement();
    Q_INVOKABLE void deferSponsorAnnouncement();
    Q_INVOKABLE bool acknowledgeSponsors(const QStringList &ids);
    Q_INVOKABLE bool markRead(const QString &id);
    Q_INVOKABLE bool markAllRead();

  signals:
    void contentChanged();
    void statusChanged();
    void startupReadyChanged();

  private:
    using ReplyHandler = std::function<void(int, const QByteArray &, const QByteArray &)>;
    struct AvatarDownload
    {
        QString hash;
        QUrl url;
    };
    static QStringList defaultSources();
    QString cachePath(const QString &name) const;
    QString avatarPath(const QString &hash) const;
    QNetworkReply *get(const QUrl &url, qint64 limit, const QByteArray &etag, ReplyHandler handler);
    void load(const QString &storageRoot);
    void fetchIndex(int source);
    void fetchDocument(int source, int kind);
    bool installDocument(const QString &kind, const QByteArray &payload,
                         const QJsonObject &descriptor, const QUrl &url);
    void finishRefresh();
    void readyForStartup();
    void refreshAvatars();
    void nextAvatar();
    void pruneAvatars();
    QString avatarSource(const QJsonObject &entry) const;
    QVariantList announcements(bool current) const;
    bool saveState(const QJsonObject &next);

    QNetworkAccessManager m_network;
    QStringList m_sources;
    QStringList m_presentedSponsorIds;
    QString m_root;
    QString m_language = QStringLiteral("en");
    QJsonObject m_index;
    QJsonObject m_etags;
    QJsonObject m_state;
    QHash<QString, QJsonObject> m_documents;
    QHash<QString, QString> m_hashes;
    QHash<QString, QUrl> m_documentUrls;
    QJsonObject m_archive;
    QHash<QString, QString> m_bundledAvatars;
    QSet<QString> m_validAvatars;
    QList<AvatarDownload> m_avatarQueue;
    QPointer<QNetworkReply> m_avatarReply;
    quint64 m_avatarGeneration = 0;
    QElapsedTimer m_lastAttempt;
    QDateTime m_lastChecked;
    QTimer m_refreshTimer;
    QTimer m_displayTimer;
    bool m_refreshing = false;
    bool m_refreshFailed = false;
    bool m_started = false;
    bool m_startupReady = false;
    bool m_sponsorPopupOffered = false;
};

} // namespace hexproof::client
