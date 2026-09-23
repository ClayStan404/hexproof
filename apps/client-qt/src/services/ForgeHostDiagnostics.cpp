// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "ForgeHostDiagnostics.h"

#include <QCoreApplication>
#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QJsonDocument>
#include <QRegularExpression>
#include <QSaveFile>
#include <QStorageInfo>
#include <QSysInfo>
#include <QUuid>
#include <cmath>

namespace hexproof::client {
using namespace Qt::StringLiterals;
namespace {
constexpr qsizetype maxHistoryBytes = 256 * 1024;
constexpr qsizetype maxEvents = 256;
constexpr qint64 retentionSeconds = 7 * 24 * 60 * 60;

QString allowed(const QString &value, const QStringList &values)
{
    return values.contains(value) ? value : QString{};
}

QString matching(const QString &value, const QString &pattern)
{
    return value.size() <= 160 && QRegularExpression(pattern).match(value).hasMatch() ? value
                                                                                      : QString{};
}

QString uuid(const QString &value)
{
    return matching(value, u"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"_s);
}

QString operationName(const QString &value)
{
    return allowed(
        value, {u"check"_s, u"prepare"_s, u"import"_s, u"import_check"_s, u"cleanup"_s, u"host"_s});
}

void copyNumber(QJsonObject &target, const QJsonObject &source, const QString &key,
                double minimum = 0, double maximum = 9007199254740991.0)
{
    const auto value = source.value(key);
    const double number = value.toDouble(-2);
    if (value.isDouble() && std::isfinite(number) && std::floor(number) == number &&
        number >= minimum && number <= maximum)
        target.insert(key, value);
}

QJsonObject safeDetails(const QJsonObject &input)
{
    QJsonObject output;
    const auto copy = [&](const QString &key, const QString &value) {
        if (!value.isEmpty())
            output.insert(key, value);
    };
    copy(u"stage"_s, allowed(input.value(u"stage"_s).toString(),
                             {u"storage"_s, u"lock"_s, u"download"_s, u"import"_s, u"extract"_s,
                              u"verify"_s, u"publish"_s, u"check"_s, u"use"_s, u"overlay"_s,
                              u"cleanup"_s, u"configuration"_s, u"prepare"_s, u"jvm_probe"_s,
                              u"jvm_start"_s, u"hosting"_s, u"helper"_s}));
    copy(u"component"_s, allowed(input.value(u"component"_s).toString(),
                                 {u"runtime"_s, u"forge"_s, u"java"_s, u"pack"_s, u"cache"_s,
                                  u"adapter"_s, u"helper"_s, u"client"_s}));
    copy(u"source"_s, allowed(input.value(u"source"_s).toString(),
                              {u"official"_s, u"mirror"_s, u"cache"_s, u"offline"_s}));
    copy(u"code"_s, allowed(input.value(u"code"_s).toString(), {u"started"_s,
                                                                u"completed"_s,
                                                                u"waiting"_s,
                                                                u"available"_s,
                                                                u"attempt_started"_s,
                                                                u"cache_hit"_s,
                                                                u"operation_failed"_s,
                                                                u"cancelled"_s,
                                                                u"timeout"_s,
                                                                u"permission_denied"_s,
                                                                u"disk_space"_s,
                                                                u"file_missing"_s,
                                                                u"package_version_mismatch"_s,
                                                                u"platform_mismatch"_s,
                                                                u"dns_failed"_s,
                                                                u"tls_failed"_s,
                                                                u"network_failed"_s,
                                                                u"checksum_mismatch"_s,
                                                                u"archive_invalid"_s,
                                                                u"data_truncated"_s,
                                                                u"metadata_invalid"_s,
                                                                u"member_missing"_s,
                                                                u"size_mismatch"_s,
                                                                u"invalid_configuration"_s,
                                                                u"unsafe_archive"_s,
                                                                u"unsupported_platform"_s,
                                                                u"runtime_not_prepared"_s,
                                                                u"http_status"_s,
                                                                u"range_mismatch"_s,
                                                                u"content_encoding"_s,
                                                                u"download_interrupted"_s,
                                                                u"storage_failed"_s,
                                                                u"lock_failed"_s,
                                                                u"integrity_invalid"_s,
                                                                u"adapter_incompatible"_s,
                                                                u"executable_missing"_s,
                                                                u"executable_permission_denied"_s,
                                                                u"executable_invalid"_s,
                                                                u"executable_start_failed"_s,
                                                                u"profile_create_failed"_s,
                                                                u"pipe_setup_failed"_s,
                                                                u"probe_timeout"_s,
                                                                u"process_exited"_s,
                                                                u"process_signalled"_s,
                                                                u"protocol_invalid"_s,
                                                                u"response_too_large"_s,
                                                                u"protocol_eof"_s,
                                                                u"pipe_write_failed"_s,
                                                                u"probe_rejected"_s,
                                                                u"configuration_invalid"_s,
                                                                u"process_guard_failed"_s,
                                                                u"helper_identity_mismatch"_s,
                                                                u"executable_lookup_failed"_s,
                                                                u"hosting_failed"_s,
                                                                u"helper_missing"_s,
                                                                u"helper_start_failed"_s,
                                                                u"helper_crashed"_s,
                                                                u"helper_read_failed"_s,
                                                                u"helper_write_failed"_s,
                                                                u"helper_error"_s,
                                                                u"helper_output_limit"_s,
                                                                u"import_source_invalid"_s,
                                                                u"interrupted"_s}));
    copy(u"state"_s, ForgeHostDiagnostics::safeState(input.value(u"state"_s).toString()));
    copy(u"outcome"_s, allowed(input.value(u"outcome"_s).toString(),
                               {u"succeeded"_s, u"failed"_s, u"cancelled"_s, u"interrupted"_s}));
    for (const auto &key : {u"expectedPlatform"_s, u"actualPlatform"_s})
        copy(key, matching(input.value(key).toString(),
                           u"^(linux|darwin|windows)-(amd64|arm64|386|arm)$"_s));
    for (const auto &key : {u"expectedPackageId"_s, u"actualPackageId"_s})
        copy(key, matching(input.value(key).toString(), u"^[0-9a-f]{20}$"_s));
    for (const auto &key : {u"received"_s, u"total"_s, u"availableBytes"_s, u"requiredBytes"_s})
        copyNumber(output, input, key);
    copyNumber(output, input, u"attempt"_s, 0, 100);
    copyNumber(output, input, u"httpStatus"_s, 100, 599);
    copyNumber(output, input, u"exitCode"_s, -2147483648.0, 4294967295.0);
    return output;
}

QJsonObject safeEvent(const QJsonObject &input)
{
    const QString id = uuid(input.value(u"operationId"_s).toString());
    const QString operation = operationName(input.value(u"operation"_s).toString());
    const QString kind = allowed(input.value(u"kind"_s).toString(),
                                 {u"started"_s, u"state"_s, u"diagnostic"_s, u"finished"_s});
    const QString timestamp = matching(input.value(u"timestamp"_s).toString(),
                                       u"^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}\\.\\d{3}Z$"_s);
    const QDateTime date = QDateTime::fromString(timestamp, Qt::ISODateWithMs);
    const auto now = QDateTime::currentDateTimeUtc();
    if (id.isEmpty() || operation.isEmpty() || kind.isEmpty() || !date.isValid() ||
        date < now.addSecs(-retentionSeconds) || date > now.addSecs(60))
        return {};
    QJsonObject output = safeDetails(input);
    output.insert(u"operationId"_s, id);
    output.insert(u"operation"_s, operation);
    output.insert(u"kind"_s, kind);
    output.insert(u"timestamp"_s, timestamp);
    copyNumber(output, input, u"elapsedMs"_s);
    const QString parent = uuid(input.value(u"parentOperationId"_s).toString());
    if (!parent.isEmpty())
        output.insert(u"parentOperationId"_s, parent);
    for (const auto &key : {u"applicationVersion"_s, u"helperVersion"_s}) {
        const QString version = ForgeHostDiagnostics::safeVersion(input.value(key).toString());
        if (!version.isEmpty())
            output.insert(key, version);
    }
    const QString runtime =
        ForgeHostDiagnostics::safeRuntimeId(input.value(u"runtimeId"_s).toString());
    if (!runtime.isEmpty())
        output.insert(u"runtimeId"_s, runtime);
    return output;
}
} // namespace

ForgeHostDiagnostics::ForgeHostDiagnostics(const QString &directory)
    : m_directory(directory)
{
    load();
}

QString ForgeHostDiagnostics::safeVersion(const QString &version)
{
    return matching(
        version,
        u"^[0-9]{1,5}\\.[0-9]{1,5}\\.[0-9]{1,5}(?:-(?:alpha|beta|rc)\\.[0-9]{1,5})?(?:\\+[0-9a-f]{7,40})?$"_s);
}

QString ForgeHostDiagnostics::safeRuntimeId(const QString &runtimeId)
{
    return matching(runtimeId, u"^[0-9a-f]{40}-adapter[0-9]{1,5}-[0-9a-f]{64}$"_s);
}

QString ForgeHostDiagnostics::safeState(const QString &state)
{
    return allowed(state, {u"forge"_s,
                           u"java"_s,
                           u"importing"_s,
                           u"pack_version_failed"_s,
                           u"pack_platform_failed"_s,
                           u"import_failed"_s,
                           u"extracting"_s,
                           u"verifying"_s,
                           u"disk_space"_s,
                           u"cleaning"_s,
                           u"cache_cleared"_s,
                           u"cleanup_failed"_s,
                           u"cancelled"_s,
                           u"stopped"_s,
                           u"host_stopped"_s,
                           u"connected"_s,
                           u"reconnecting"_s,
                           u"helper_missing"_s,
                           u"adapter_failed"_s,
                           u"version_mismatch"_s,
                           u"prepare_failed"_s,
                           u"start_failed"_s,
                           u"hosting_failed"_s,
                           u"ready"_s,
                           u"not_ready"_s,
                           u"configuration_error"_s,
                           u"process_guard_failed"_s});
}

QString ForgeHostDiagnostics::begin(const QString &operation, const QString &parentOperationId)
{
    m_operationId = QUuid::createUuid().toString(QUuid::WithoutBraces);
    m_parentOperationId = uuid(parentOperationId);
    m_operation = operationName(operation);
    m_helperVersion.clear();
    m_runtimeId.clear();
    m_lastState.clear();
    m_lastProgress = -1;
    m_elapsed.start();
    append(u"started"_s);
    return m_operationId;
}

void ForgeHostDiagnostics::setVersions(const QString &helperVersion, const QString &runtimeId)
{
    if (!safeVersion(helperVersion).isEmpty())
        m_helperVersion = safeVersion(helperVersion);
    if (!safeRuntimeId(runtimeId).isEmpty())
        m_runtimeId = safeRuntimeId(runtimeId);
}

void ForgeHostDiagnostics::state(const QString &state, const QJsonObject &progress)
{
    const QString cleanState = safeState(state);
    if (cleanState.isEmpty())
        return;
    const qint64 elapsed = m_elapsed.isValid() ? m_elapsed.elapsed() : 0;
    // Progress may arrive for every download chunk. Preserve stage changes and
    // periodically sample progress without causing a write for every chunk.
    if (cleanState == m_lastState && m_lastProgress >= 0 && elapsed - m_lastProgress < 2000)
        return;
    m_lastState = cleanState;
    m_lastProgress = elapsed;
    QJsonObject details{{u"state"_s, cleanState}};
    copyNumber(details, progress, u"received"_s);
    copyNumber(details, progress, u"total"_s);
    append(u"state"_s, details);
}

void ForgeHostDiagnostics::diagnostic(const QJsonObject &details)
{
    const QJsonObject clean = safeDetails(details);
    // Unknown diagnostic strings do not become free-form support messages.
    if (clean.contains(u"code"_s))
        append(u"diagnostic"_s, clean);
}

void ForgeHostDiagnostics::finish(const QString &outcome, const QJsonObject &details)
{
    if (m_operationId.isEmpty())
        return;
    QJsonObject clean = safeDetails(details);
    clean.insert(u"outcome"_s, outcome);
    append(u"finished"_s, clean);
    m_operationId.clear();
}

void ForgeHostDiagnostics::append(const QString &kind, const QJsonObject &details)
{
    if (m_operationId.isEmpty())
        return;
    QJsonObject event = details;
    event.insert(u"operationId"_s, m_operationId);
    event.insert(u"parentOperationId"_s, m_parentOperationId);
    event.insert(u"operation"_s, m_operation);
    event.insert(u"kind"_s, kind);
    event.insert(u"timestamp"_s, QDateTime::currentDateTimeUtc().toString(Qt::ISODateWithMs));
    event.insert(u"elapsedMs"_s, m_elapsed.isValid() ? m_elapsed.elapsed() : 0);
    event.insert(u"applicationVersion"_s, QCoreApplication::applicationVersion());
    event.insert(u"helperVersion"_s, m_helperVersion);
    event.insert(u"runtimeId"_s, m_runtimeId);
    const auto clean = safeEvent(event);
    if (!clean.isEmpty())
        m_events.append(clean);
    persist();
}

void ForgeHostDiagnostics::trim()
{
    const auto cutoff = QDateTime::currentDateTimeUtc().addSecs(-retentionSeconds);
    while (!m_events.isEmpty() &&
           (m_events.size() > maxEvents ||
            QDateTime::fromString(m_events.first().toObject().value(u"timestamp"_s).toString(),
                                  Qt::ISODateWithMs) < cutoff))
        m_events.removeFirst();
}

void ForgeHostDiagnostics::persist()
{
    trim();
    QByteArray bytes;
    do {
        bytes = QJsonDocument(QJsonObject{{u"schemaVersion"_s, 2}, {u"events"_s, m_events}})
                    .toJson(QJsonDocument::Compact);
        if (bytes.size() <= maxHistoryBytes)
            break;
        m_events.removeFirst();
    } while (!m_events.isEmpty());
    QSaveFile file(QDir(m_directory).filePath(u"diagnostics-v2.json"_s));
    const bool saved = QDir().mkpath(m_directory) && file.open(QIODevice::WriteOnly) &&
                       file.setPermissions(QFile::ReadOwner | QFile::WriteOwner) &&
                       file.write(bytes) == bytes.size() && file.commit();
    m_historyPersistence = saved ? u"available"_s : u"write_failed"_s;
}

void ForgeHostDiagnostics::load()
{
    QFile file(QDir(m_directory).filePath(u"diagnostics-v2.json"_s));
    if (!file.exists())
        return;
    if (!file.open(QIODevice::ReadOnly) || file.size() > maxHistoryBytes) {
        m_historyPersistence = u"read_failed"_s;
        return;
    }
    QJsonParseError parseError;
    const auto document = QJsonDocument::fromJson(file.read(maxHistoryBytes + 1), &parseError);
    file.close();
    const auto root = document.object();
    if (parseError.error != QJsonParseError::NoError || root.value(u"schemaVersion"_s) != 2 ||
        !root.value(u"events"_s).isArray()) {
        m_historyPersistence = u"read_failed"_s;
        return;
    }
    for (const auto &value : root.value(u"events"_s).toArray()) {
        const auto clean = safeEvent(value.toObject());
        if (!clean.isEmpty())
            m_events.append(clean);
    }
    trim();
    if (!m_events.isEmpty()) {
        QJsonObject last = m_events.last().toObject();
        if (last.value(u"kind"_s) != u"finished"_s) {
            // Only history is restored; readiness and hosting are always checked
            // anew. A missing terminal event indicates an interrupted client.
            // Keep the last observed elapsed time; time while the application
            // was closed is not measured operation duration.
            last.insert(u"kind"_s, u"finished"_s);
            last.insert(u"timestamp"_s,
                        QDateTime::currentDateTimeUtc().toString(Qt::ISODateWithMs));
            last.insert(u"outcome"_s, u"interrupted"_s);
            last.insert(u"code"_s, u"interrupted"_s);
            m_events.append(last);
        }
    }
    // Rewrite only sanitized history, including any inferred interruption.
    persist();
}

QJsonObject ForgeHostDiagnostics::report(const QString &runtimeDirectory) const
{
    QJsonArray currentEvents;
    for (const auto &value : m_events) {
        const auto event = safeEvent(value.toObject());
        if (!event.isEmpty())
            currentEvents.append(event);
    }
    QJsonObject output{
        {u"events"_s, currentEvents},
        {u"historyPersistence"_s, m_historyPersistence},
        {u"exportedAt"_s, QDateTime::currentDateTimeUtc().toString(Qt::ISODateWithMs)},
        {u"operatingSystem"_s,
         allowed(QSysInfo::productType(),
                 {u"windows"_s,       u"macos"_s,     u"osx"_s,
                  u"ubuntu"_s,        u"debian"_s,    u"fedora"_s,
                  u"arch"_s,          u"opensuse"_s,  u"opensuse-tumbleweed"_s,
                  u"opensuse-leap"_s, u"linuxmint"_s, u"manjaro"_s,
                  u"pop"_s,           u"nixos"_s,     u"alpine"_s,
                  u"rhel"_s,          u"centos"_s,    u"rocky"_s,
                  u"almalinux"_s,     u"gentoo"_s,    u"endeavouros"_s,
                  u"steamos"_s,       u"linux"_s,     u"unknown"_s})},
        {u"kernelType"_s, allowed(QSysInfo::kernelType(), {u"linux"_s, u"darwin"_s, u"winnt"_s})},
        {u"operatingSystemVersion"_s,
         matching(QSysInfo::productVersion(), u"^[0-9]+(?:\\.[0-9]+){0,3}$"_s)},
        {u"kernelVersion"_s, QRegularExpression(u"^[0-9]+(?:\\.[0-9]+){0,3}"_s)
                                 .match(QSysInfo::kernelVersion())
                                 .captured()},
        {u"qtVersion"_s, safeVersion(QString::fromLatin1(qVersion()))},
        {u"architecture"_s, allowed(QSysInfo::currentCpuArchitecture(),
                                    {u"x86_64"_s, u"i386"_s, u"arm64"_s, u"arm"_s})}};
    const QStorageInfo storage(runtimeDirectory);
    if (storage.isValid() && storage.isReady()) {
        if (storage.bytesAvailable() >= 0)
            output.insert(u"availableBytes"_s, storage.bytesAvailable());
        if (storage.bytesTotal() >= 0)
            output.insert(u"storageTotalBytes"_s, storage.bytesTotal());
    }
    return output;
}

} // namespace hexproof::client
