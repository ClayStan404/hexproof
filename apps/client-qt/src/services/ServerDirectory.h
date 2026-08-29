// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#pragma once

#include <array>

#include <QNetworkAccessManager>
#include <QObject>
#include <QString>
#include <QStringList>
#include <QVariantList>

namespace hexproof::client {

// ServerDirectory owns the public-hub configuration, custom endpoint, and
// health probes.
// WsClient remains the QML compatibility facade while connection/session state
// stays independent from endpoint discovery.
class ServerDirectory : public QObject
{
    Q_OBJECT

  public:
    static constexpr int ConfiguredServerCount = 3;
    static constexpr int CustomServerIndex = ConfiguredServerCount;
    static constexpr int ServerCount = ConfiguredServerCount + 1;

    explicit ServerDirectory(QObject *parent = nullptr);

    QString serverUrl(int serverIndex) const;
    QString customServerUrl() const;
    bool setCustomServerUrl(const QString &url);
    int indexForUrl(const QString &url) const;
    QString normalizePersistedUrl(const QString &url) const;
    QVariantList latencies() const;

    void refreshLatencies();

  signals:
    void latenciesChanged();
    void customServerUrlChanged();

  private:
    QNetworkAccessManager m_networkManager;
    std::array<QString, ConfiguredServerCount> m_configuredServerUrls;
    std::array<QStringList, ConfiguredServerCount> m_legacyServerUrls;
    std::array<int, ServerCount> m_latencyMs{{-2, -2, -2, -2}};
    QString m_customServerUrl;
    quint64 m_probeGeneration = 0;
};

} // namespace hexproof::client
