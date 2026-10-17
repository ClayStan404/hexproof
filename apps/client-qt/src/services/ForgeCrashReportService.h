// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors
#pragma once

#include <QDateTime>
#include <QJsonObject>
#include <QObject>
#include <QTimer>
#include <QUrl>
#include <QVariantList>
#include <functional>

namespace hexproof::client {

// Durable, offline diagnostics independent of live room/game state.
class ForgeCrashReportService final : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QVariantList entries READ entries NOTIFY entriesChanged)
    Q_PROPERTY(QString noticeId READ noticeId NOTIFY noticeChanged)
    Q_PROPERTY(QString storageError READ storageError NOTIFY statusChanged)
    Q_PROPERTY(QString operationStatus READ operationStatus NOTIFY statusChanged)
    Q_PROPERTY(QString operationReportId READ operationReportId NOTIFY statusChanged)

  public:
    using Clock = std::function<QDateTime()>;
    explicit ForgeCrashReportService(QObject *parent = nullptr, const QString &directory = {},
                                     Clock clock = QDateTime::currentDateTimeUtc);
    QVariantList entries() const;
    QString noticeId() const;
    QString storageError() const
    {
        return m_storageError;
    }
    QString operationStatus() const
    {
        return m_operationStatus;
    }
    QString operationReportId() const
    {
        return m_operationReportId;
    }
    // Returns true for valid duplicates too, so redelivery bypasses generic errors.
    bool accept(const QJsonObject &report);
    Q_INVOKABLE QVariantMap report(const QString &id);
    Q_INVOKABLE QString reportText(const QString &id);
    Q_INVOKABLE QUrl suggestedFile(const QString &id);
    Q_INVOKABLE bool copyReport(const QString &id);
    Q_INVOKABLE bool saveReport(const QString &id, const QUrl &url);
    Q_INVOKABLE void dismiss(const QString &id);
    Q_INVOKABLE void refresh();

  signals:
    void entriesChanged();
    void noticeChanged();
    void statusChanged();

  private:
    struct Entry
    {
        QJsonObject report;
        QDateTime received;
        bool dismissed = false;
    };
    bool expired(const Entry &entry) const;
    bool prune();
    void persist();
    void load();
    void setOperationStatus(const QString &value, const QString &id);
    int find(const QString &id) const;
    QString m_directory;
    QList<Entry> m_entries;
    QStringList m_notices;
    QString m_storageError;
    QString m_operationStatus;
    QString m_operationReportId;
    Clock m_clock;
    QTimer m_maintenance;
};

// A strict, bounded projection shared by network acceptance and disk restore.
QJsonObject normalizedForgeCrashReport(const QJsonObject &report);

} // namespace hexproof::client
