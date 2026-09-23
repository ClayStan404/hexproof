// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#pragma once

#include "ForgeHostDiagnostics.h"

#include <QJsonObject>
#include <QObject>
#include <QProcess>
#include <QString>
#include <QUrl>

namespace hexproof::client {

// The helper owns engine traffic. QML receives readiness/progress only, never
// the hosting capability, deck requests, or complete engine publications.
class ForgeHostService : public QObject
{
    friend class NativeAudit;
    Q_OBJECT
    Q_PROPERTY(bool ready READ ready NOTIFY changed)
    Q_PROPERTY(bool busy READ busy NOTIFY changed)
    Q_PROPERTY(bool hosting READ hosting NOTIFY changed)
    Q_PROPERTY(QString status READ status NOTIFY changed)
    Q_PROPERTY(double progress READ progress NOTIFY changed)
    Q_PROPERTY(QString downloadMirror READ downloadMirror NOTIFY changed)

  public:
    explicit ForgeHostService(QObject *parent = nullptr);
    ~ForgeHostService() override;
    bool ready() const
    {
        return m_ready;
    }
    bool busy() const
    {
        return m_operation != Operation::None || m_process.state() != QProcess::NotRunning;
    }
    bool hosting() const
    {
        return m_hosting && busy();
    }
    QString status() const;
    double progress() const
    {
        return m_progress;
    }
    Q_INVOKABLE void check();
    Q_INVOKABLE void prepare();
    Q_INVOKABLE void importPack(const QUrl &source);
    Q_INVOKABLE void cancel();
    Q_INVOKABLE void clearCache();
    QString downloadMirror() const;
    Q_INVOKABLE bool saveDownloadMirror(const QString &value);
    Q_INVOKABLE bool exportDiagnostics(const QUrl &destination) const;
    Q_INVOKABLE QUrl suggestedDiagnosticsUrl() const;
    void startHosting(const QString &serverUrl, const QJsonObject &grant);
    void stop();
    bool submitPeerAction(const QJsonObject &action);
    void setTransportDiagnostics(const QString &state, int decisions, int fallbacks);

  private:
    enum class Operation
    {
        None,
        Standard,
        Import,
        ImportCheck
    };
    void launch(const QStringList &arguments, const QJsonObject &configuration = {},
                Operation operation = Operation::Standard);
    void finishOperation(bool succeeded);
    void readOutput();
    QString helperPath() const;
    QString runtimeDirectory() const;
    QString diagnosticsDirectory() const;
    ForgeHostDiagnostics m_diagnostics;
    QProcess m_process;
    QByteArray m_output;
    QString m_state;
    QString m_importResult;
    QString m_importOperationId;
    Operation m_operation = Operation::None;
    bool m_ready = false;
    bool m_hosting = false;
    bool m_stopping = false;
    double m_progress = 0;
    qint64 m_freedBytes = 0;
    QString m_runtimeId;
    QString m_helperVersion;
    QStringList m_recentStates;
    QString m_transportState = QStringLiteral("off");
    int m_directDecisions = 0;
    int m_transportFallbacks = 0;

  signals:
    void changed();
    void peerReply(const QJsonObject &reply);
};

} // namespace hexproof::client
