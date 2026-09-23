// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#pragma once

#include <QElapsedTimer>
#include <QJsonArray>
#include <QJsonObject>
#include <QString>

namespace hexproof::client {

// Local support history contains only typed, allowlisted metadata. It never
// accepts messages, paths, URLs, engine output or gameplay publications.
class ForgeHostDiagnostics
{
  public:
    explicit ForgeHostDiagnostics(const QString &directory);
    QString begin(const QString &operation, const QString &parentOperationId = {});
    void state(const QString &state, const QJsonObject &progress = {});
    void diagnostic(const QJsonObject &details);
    void finish(const QString &outcome, const QJsonObject &details = {});
    void setVersions(const QString &helperVersion, const QString &runtimeId);
    QJsonObject report(const QString &runtimeDirectory) const;
    QString operationId() const
    {
        return m_operationId;
    }
    static QString safeState(const QString &state);
    static QString safeVersion(const QString &version);
    static QString safeRuntimeId(const QString &runtimeId);

  private:
    void append(const QString &kind, const QJsonObject &details = {});
    void persist();
    void trim();
    void load();
    QString m_directory;
    QJsonArray m_events;
    QString m_operationId;
    QString m_parentOperationId;
    QString m_operation;
    QString m_helperVersion;
    QString m_runtimeId;
    QString m_lastState;
    QString m_historyPersistence = QStringLiteral("available");
    QElapsedTimer m_elapsed;
    qint64 m_lastProgress = -1;
};

} // namespace hexproof::client
