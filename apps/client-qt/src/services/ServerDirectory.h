// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#pragma once

#include <QElapsedTimer>
#include <QHash>
#include <QJsonObject>
#include <QList>
#include <QNetworkAccessManager>
#include <QObject>
#include <QString>
#include <QStringList>
#include <QVariantList>

namespace hexproof::client {

// ServerDirectory owns the online public-hub catalog, last-known-good cache,
// bundled fallback, custom endpoint, and health probes.
// WsClient remains the QML compatibility facade while connection/session state
// stays independent from endpoint discovery.
class ServerDirectory : public QObject
{
    Q_OBJECT

  public:
    explicit ServerDirectory(QObject *parent = nullptr);

    int configuredServerCount() const;
    int customServerIndex() const;
    QVariantList entries() const;
    QString source() const;
    bool refreshing() const;
    bool refreshFailed() const;
    QString serverUrl(int serverIndex) const;
    QString customServerUrl() const;
    bool setCustomServerUrl(const QString &url);
    int indexForUrl(const QString &url) const;
    QString normalizePersistedUrl(const QString &url) const;
    QVariantList latencies() const;

    void refreshLatencies();
    void refreshDirectory(bool force = false);
    void recordForgeCapability(const QString &url, bool supported);

  signals:
    void latenciesChanged();
    void customServerUrlChanged();
    void directoryChanged();
    void statusChanged();

  private:
    void applyDirectory(const QJsonObject &document, const QString &source);
    void fetchNextSource(int index);
    QString cachePath() const;

    QNetworkAccessManager m_networkManager;
    QJsonObject m_document;
    QVariantList m_servers;
    QStringList m_directoryUrls;
    QList<int> m_latencyMs;
    QHash<QString, int> m_observedForge;
    QString m_customServerUrl;
    QString m_source;
    bool m_refreshing = false;
    bool m_refreshFailed = false;
    QElapsedTimer m_lastDirectoryAttempt;
    quint64 m_catalogGeneration = 0;
    quint64 m_probeGeneration = 0;
    quint64 m_customGeneration = 0;
};

} // namespace hexproof::client
