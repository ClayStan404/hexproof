// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors
#include "ForgeCrashReportService.h"

#include <QClipboard>
#include <QDir>
#include <QFile>
#include <QGuiApplication>
#include <QJsonArray>
#include <QJsonDocument>
#include <QSaveFile>
#include <QStandardPaths>
#include <algorithm>

namespace hexproof::client {
namespace {
using namespace Qt::StringLiterals;
constexpr qint64 maximumBytes = 4 * 1024 * 1024;
constexpr int maximumReports = 64;
constexpr int retentionDays = 7;

bool save(const QString &path, const QByteArray &bytes)
{
    QSaveFile file(path);
    if (!file.open(QIODevice::WriteOnly))
        return false;
    file.setPermissions(QFileDevice::ReadOwner | QFileDevice::WriteOwner);
    return file.write(bytes) == bytes.size() && file.commit();
}
} // namespace

ForgeCrashReportService::ForgeCrashReportService(QObject *parent, const QString &directory,
                                                 Clock clock)
    : QObject(parent),
      m_directory(directory.isEmpty()
                      ? QStandardPaths::writableLocation(QStandardPaths::AppLocalDataLocation) +
                            u"/forge-crash-reports"_s
                      : directory),
      m_clock(std::move(clock))
{
    load();
    m_maintenance.setInterval(60000);
    connect(&m_maintenance, &QTimer::timeout, this, &ForgeCrashReportService::refresh);
    m_maintenance.start();
}

bool ForgeCrashReportService::expired(const Entry &entry) const
{
    return !entry.received.isValid() || entry.received > m_clock() ||
           entry.received.addDays(retentionDays) <= m_clock();
}

QVariantList ForgeCrashReportService::entries() const
{
    QVariantList values;
    for (const auto &entry : m_entries) {
        if (expired(entry))
            continue;
        auto value = entry.report.toVariantMap();
        value.insert(u"firstReceived"_s, entry.received.toString(Qt::ISODateWithMs));
        values.append(value);
    }
    return values;
}

QString ForgeCrashReportService::noticeId() const
{
    for (const auto &id : m_notices) {
        const int index = find(id);
        if (index >= 0 && !expired(m_entries.at(index)))
            return id;
    }
    return {};
}

int ForgeCrashReportService::find(const QString &id) const
{
    for (int i = 0; i < m_entries.size(); ++i)
        if (m_entries.at(i).report.value(u"reportId"_s).toString() == id)
            return i;
    return -1;
}

bool ForgeCrashReportService::prune()
{
    const auto oldCount = m_entries.size();
    m_entries.removeIf([this](const Entry &entry) { return expired(entry); });
    qint64 bytes = 2;
    int keep = 0;
    for (const auto &entry : m_entries) {
        // Include lifecycle/envelope overhead in the total storage budget.
        bytes += QJsonDocument(entry.report).toJson(QJsonDocument::Compact).size() + 256;
        if (keep >= maximumReports || bytes > maximumBytes)
            break;
        ++keep;
    }
    m_entries.erase(m_entries.begin() + keep, m_entries.end());
    m_notices.removeIf([this](const QString &id) { return find(id) < 0; });
    return oldCount != m_entries.size();
}

void ForgeCrashReportService::load()
{
    QFile file(m_directory + u"/history.json"_s);
    if (!file.exists())
        return;
    if (!file.open(QIODevice::ReadOnly) || file.size() > maximumBytes) {
        m_storageError = u"history_unavailable"_s;
        return;
    }
    const auto document = QJsonDocument::fromJson(file.readAll());
    if (!document.isArray() || document.array().size() > maximumReports) {
        m_storageError = u"history_unavailable"_s;
        return;
    }
    for (const auto &item : document.array()) {
        const auto wrapper = item.toObject();
        auto report = normalizedForgeCrashReport(wrapper.value(u"report"_s).toObject());
        const auto received =
            QDateTime::fromString(wrapper.value(u"firstReceived"_s).toString(), Qt::ISODateWithMs)
                .toUTC();
        if (report.isEmpty() || find(report.value(u"reportId"_s).toString()) >= 0)
            continue;
        Entry entry{report, received, wrapper.value(u"dismissed"_s).toBool()};
        if (!expired(entry))
            m_entries.append(std::move(entry));
    }
    // Restored entries never reopen a notice, including a previous abrupt exit.
    std::stable_sort(m_entries.begin(), m_entries.end(),
                     [](const Entry &a, const Entry &b) { return a.received > b.received; });
    prune();
    persist();
}

void ForgeCrashReportService::persist()
{
    QJsonArray values;
    for (const auto &entry : m_entries)
        values.append(QJsonObject{{u"report"_s, entry.report},
                                  {u"firstReceived"_s, entry.received.toString(Qt::ISODateWithMs)},
                                  {u"dismissed"_s, entry.dismissed}});
    bool ok = QDir().mkpath(m_directory);
    if (ok) {
        QFile::setPermissions(m_directory, QFileDevice::ReadOwner | QFileDevice::WriteOwner |
                                               QFileDevice::ExeOwner);
        ok = save(m_directory + u"/history.json"_s,
                  QJsonDocument(values).toJson(QJsonDocument::Compact));
    }
    const QString error = ok ? QString{} : u"history_unavailable"_s;
    if (error != m_storageError) {
        m_storageError = error;
        emit statusChanged();
    }
}

bool ForgeCrashReportService::accept(const QJsonObject &value)
{
    const auto normalized = normalizedForgeCrashReport(value);
    if (normalized.isEmpty())
        return false;
    const QString id = normalized.value(u"reportId"_s).toString();
    // Reject expired historical redelivery after local pruning. Server retention
    // starts at occurrence and cannot outlive a client's first-receipt deadline.
    const auto occurred =
        QDateTime::fromString(normalized.value(u"occurredAt"_s).toString(), Qt::ISODateWithMs)
            .toUTC();
    if (occurred.addDays(retentionDays) <= m_clock())
        return true;
    refresh();
    const int index = find(id);
    if (index >= 0) {
        auto &entry = m_entries[index];
        if (normalized.value(u"revision"_s).toInt() <= entry.report.value(u"revision"_s).toInt())
            return true;
        // An incident's occurrence is immutable; reject misbound revisions.
        if (normalized.value(u"occurredAt"_s) != entry.report.value(u"occurredAt"_s))
            return false;
        entry.report = normalized;
    } else {
        m_entries.prepend({normalized, m_clock(), false});
        m_notices.append(id);
    }
    prune();
    persist();
    emit entriesChanged();
    emit noticeChanged();
    return true;
}

void ForgeCrashReportService::refresh()
{
    if (!prune())
        return;
    persist();
    emit entriesChanged();
    emit noticeChanged();
}

QVariantMap ForgeCrashReportService::report(const QString &id)
{
    refresh();
    const int index = find(id);
    return index < 0 ? QVariantMap{} : m_entries.at(index).report.toVariantMap();
}

QString ForgeCrashReportService::reportText(const QString &id)
{
    const auto value = report(id);
    return value.isEmpty() ? QString{}
                           : QString::fromUtf8(QJsonDocument(QJsonObject::fromVariantMap(value))
                                                   .toJson(QJsonDocument::Indented));
}

QUrl ForgeCrashReportService::suggestedFile(const QString &id)
{
    const auto value = report(id);
    if (value.isEmpty())
        return {};
    const auto time =
        QDateTime::fromString(value.value(u"occurredAt"_s).toString(), Qt::ISODateWithMs);
    const auto filename =
        u"forge-crash-%1-%2.json"_s.arg(time.toUTC().toString(u"yyyyMMdd-HHmmss"_s), id);
    return QUrl::fromLocalFile(QStandardPaths::writableLocation(QStandardPaths::DocumentsLocation) +
                               u"/"_s + filename);
}

void ForgeCrashReportService::setOperationStatus(const QString &value, const QString &id)
{
    m_operationStatus = value;
    m_operationReportId = id;
    emit statusChanged();
}

bool ForgeCrashReportService::copyReport(const QString &id)
{
    const QString text = reportText(id);
    if (text.isEmpty()) {
        setOperationStatus(u"report_expired"_s, id);
        return false;
    }
    if (!qobject_cast<QGuiApplication *>(QCoreApplication::instance()) ||
        !QGuiApplication::clipboard()) {
        setOperationStatus(u"copy_failed"_s, id);
        return false;
    }
    QGuiApplication::clipboard()->setText(text);
    setOperationStatus(u"copied"_s, id);
    return true;
}

bool ForgeCrashReportService::saveReport(const QString &id, const QUrl &url)
{
    const QString text = reportText(id);
    if (text.isEmpty()) {
        setOperationStatus(u"report_expired"_s, id);
        return false;
    }
    if (!url.isLocalFile() || !save(url.toLocalFile(), text.toUtf8())) {
        setOperationStatus(u"export_failed"_s, id);
        return false;
    }
    setOperationStatus(u"saved"_s, id);
    return true;
}

void ForgeCrashReportService::dismiss(const QString &id)
{
    refresh();
    const int index = find(id);
    if (index >= 0) {
        m_entries[index].dismissed = true;
        persist();
    }
    m_notices.removeAll(id);
    emit noticeChanged();
}
} // namespace hexproof::client
