// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "ForgeHostService.h"

#include "ApplicationPaths.h"
#include <QCoreApplication>
#include <QDir>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QSaveFile>
#include <QSettings>
#include <QStandardPaths>
#include <QSysInfo>
#include <QTimer>

namespace hexproof::client {
using namespace Qt::StringLiterals;

ForgeHostService::ForgeHostService(QObject *parent)
    : QObject(parent)
{
    connect(&m_process, &QProcess::readyReadStandardOutput, this, &ForgeHostService::readOutput);
    connect(&m_process, &QProcess::readyReadStandardError, this, [this]() {
        // Helper/engine diagnostics never enter player-visible logs.
        m_process.readAllStandardError();
    });
    connect(&m_process, &QProcess::errorOccurred, this, [this](QProcess::ProcessError) {
        if (!m_stopping) {
            m_state = u"start_failed"_s;
            emit changed();
        }
    });
    connect(&m_process, &QProcess::finished, this,
            [this](int exitCode, QProcess::ExitStatus exitStatus) {
                readOutput();
                if (m_stopping)
                    m_state = m_hosting ? u"host_stopped"_s : u"stopped"_s;
                else if (exitCode != 0 || exitStatus != QProcess::NormalExit) {
                    if (!m_state.endsWith(u"failed") && m_state != u"not_ready"_s &&
                        m_state != u"version_mismatch"_s && m_state != u"disk_space"_s &&
                        m_state != u"cancelled"_s)
                        m_state = u"hosting_failed"_s;
                }
                m_hosting = false;
                m_stopping = false;
                emit changed();
            });
}

ForgeHostService::~ForgeHostService()
{
    disconnect(&m_process, nullptr, this, nullptr);
    m_process.closeWriteChannel();
    if (m_process.state() != QProcess::NotRunning && !m_process.waitForFinished(5000)) {
        m_process.kill();
        m_process.waitForFinished(1000);
    }
}

QString ForgeHostService::helperPath() const
{
    QString name = u"hexproof-forge-host"_s;
#ifdef Q_OS_WIN
    name += u".exe"_s;
#endif
    return QDir(QCoreApplication::applicationDirPath()).filePath(name);
}

QString ForgeHostService::runtimeDirectory() const
{
    const QString overridePath = qEnvironmentVariable("HEXPROOF_FORGE_HOST_RUNTIME_DIR");
    return overridePath.isEmpty() ? QDir(defaultStorageRoot()).absoluteFilePath(u"forge-runtime"_s)
                                  : QDir(overridePath).absolutePath();
}

void ForgeHostService::launch(const QStringList &arguments, const QJsonObject &configuration)
{
    if (busy())
        return;
    if (!QFileInfo(helperPath()).isExecutable()) {
        m_state = u"helper_missing"_s;
        emit changed();
        return;
    }
    m_output.clear();
    m_stopping = false;
    m_progress = 0;
    m_state = u"verifying"_s;
    QStringList options{u"--runtime-dir"_s, runtimeDirectory(), u"--parent-pipe"_s};
    options.append(arguments);
    m_process.setProgram(helperPath());
    m_process.setArguments(options);
    m_process.start();
    if (!configuration.isEmpty()) {
        m_process.write(QJsonDocument(configuration).toJson(QJsonDocument::Compact) + '\n');
    }
    emit changed();
}

void ForgeHostService::check()
{
    if (!ready() && !busy())
        launch({u"--check"_s});
}

void ForgeHostService::prepare()
{
    if (busy())
        return;
    m_ready = false;
    QStringList options{u"--prepare"_s};
    if (!downloadMirror().isEmpty())
        options.append({u"--download-mirror"_s, downloadMirror()});
    launch(options);
}

void ForgeHostService::importPack(const QUrl &source)
{
    if (busy())
        return;
    if (!source.isLocalFile() || !QFileInfo(source.toLocalFile()).isFile()) {
        m_state = u"import_failed"_s;
        emit changed();
        return;
    }
    m_ready = false;
    launch({u"--import-pack"_s, source.toLocalFile()});
}

QString ForgeHostService::downloadMirror() const
{
    return QSettings().value(u"network/forgeDownloadMirror"_s).toString();
}

bool ForgeHostService::saveDownloadMirror(const QString &value)
{
    if (busy())
        return false;
    const QString trimmed = value.trimmed();
    const QUrl url(trimmed, QUrl::StrictMode);
    if (!trimmed.isEmpty() &&
        (!url.isValid() || url.scheme() != u"https"_s || url.host().isEmpty() ||
         !url.userInfo().isEmpty() || url.hasQuery() || url.hasFragment()))
        return false;
    QSettings settings;
    settings.setValue(u"network/forgeDownloadMirror"_s, trimmed);
    settings.sync();
    emit changed();
    return settings.status() == QSettings::NoError;
}

void ForgeHostService::clearCache()
{
    if (!busy())
        launch({u"--clear-cache"_s});
}

bool ForgeHostService::exportDiagnostics(const QUrl &destination) const
{
    if (!destination.isLocalFile() || destination.toLocalFile().isEmpty())
        return false;
    // Deliberate allowlist: never serialize grants, URLs, paths, user names,
    // engine publications, decks, or the helper's raw stdout/stderr.
    const QJsonObject report{{u"schemaVersion"_s, 1},
                             {u"applicationVersion"_s, QCoreApplication::applicationVersion()},
                             {u"helperVersion"_s, m_helperVersion},
                             {u"runtimeId"_s, m_runtimeId},
                             {u"operatingSystem"_s, QSysInfo::productType()},
                             {u"architecture"_s, QSysInfo::currentCpuArchitecture()},
                             {u"ready"_s, ready()},
                             {u"hosting"_s, hosting()},
                             {u"state"_s, m_state},
                             {u"recentStates"_s, QJsonArray::fromStringList(m_recentStates)},
                             {u"transport"_s, m_transportState},
                             {u"directDecisions"_s, m_directDecisions},
                             {u"relayFallbacks"_s, m_transportFallbacks}};
    QSaveFile file(destination.toLocalFile());
    const QByteArray data = QJsonDocument(report).toJson();
    return file.open(QIODevice::WriteOnly) && file.write(data) == data.size() && file.commit();
}

QUrl ForgeHostService::suggestedDiagnosticsUrl() const
{
    return QUrl::fromLocalFile(
        QDir(QStandardPaths::writableLocation(QStandardPaths::DocumentsLocation))
            .filePath(u"hexproof-forge-diagnostics.json"_s));
}

void ForgeHostService::startHosting(const QString &serverUrl, const QJsonObject &grant)
{
    if (busy())
        return;
    QJsonObject configuration = grant;
    configuration.insert(u"serverUrl"_s, serverUrl);
    m_hosting = true;
    launch({}, configuration);
}

void ForgeHostService::setTransportDiagnostics(const QString &state, int decisions, int fallbacks)
{
    static const QStringList allowed{u"off"_s,   u"waiting"_s,   u"connecting"_s,  u"direct"_s,
                                     u"relay"_s, u"migrating"_s, u"reconnecting"_s};
    m_transportState = allowed.contains(state) ? state : u"relay"_s;
    m_directDecisions = qMax(0, decisions);
    m_transportFallbacks = qMax(0, fallbacks);
}

bool ForgeHostService::submitPeerAction(const QJsonObject &action)
{
    if (!hosting() || m_stopping)
        return false;
    const QByteArray data =
        QJsonDocument(QJsonObject{{u"peerAction"_s, action}}).toJson(QJsonDocument::Compact) + '\n';
    if (data.size() > 256 * 1024 || m_process.bytesToWrite() + data.size() > 512 * 1024)
        return false;
    return m_process.write(data) == data.size();
}

void ForgeHostService::cancel()
{
    stop();
}

void ForgeHostService::stop()
{
    if (!busy())
        return;
    m_stopping = true;
    m_process.closeWriteChannel();
    const qint64 processId = m_process.processId();
    QTimer::singleShot(5000, this, [this, processId]() {
        if (m_stopping && m_process.state() != QProcess::NotRunning &&
            m_process.processId() == processId)
            m_process.kill();
    });
    emit changed();
}

void ForgeHostService::readOutput()
{
    m_output += m_process.readAllStandardOutput();
    if (m_output.size() > 8 * 1024 * 1024) {
        stop();
        return;
    }
    qsizetype newline;
    while ((newline = m_output.indexOf('\n')) >= 0) {
        const QByteArray line = m_output.left(newline);
        m_output.remove(0, newline + 1);
        const QJsonObject event = QJsonDocument::fromJson(line).object();
        if (event.isEmpty())
            continue;
        if (event.contains(u"peerReply"_s)) {
            emit peerReply(event.value(u"peerReply"_s).toObject());
            continue;
        }
        m_state = event.value(u"state"_s).toString();
        m_runtimeId = event.value(u"runtimeId"_s).toString();
        m_helperVersion = event.value(u"version"_s).toString();
        if (m_recentStates.isEmpty() || m_recentStates.last() != m_state) {
            m_recentStates.append(m_state);
            if (m_recentStates.size() > 32)
                m_recentStates.removeFirst();
        }
        if (m_state == u"cache_cleared"_s)
            m_freedBytes = event.value(u"received"_s).toInteger();
        if (m_state == u"ready"_s)
            m_ready = true;
        if (m_state == u"not_ready"_s || m_state == u"prepare_failed"_s ||
            m_state == u"version_mismatch"_s || m_state == u"start_failed"_s ||
            m_state == u"disk_space"_s || m_state == u"adapter_failed"_s)
            m_ready = false;
        const double total = event.value(u"total"_s).toDouble();
        m_progress = total > 0 ? event.value(u"received"_s).toDouble() / total : 0;
        emit changed();
    }
}

QString ForgeHostService::status() const
{
    if (m_state == u"forge"_s)
        return tr("Downloading Forge…");
    if (m_state == u"java"_s)
        return tr("Downloading Java…");
    if (m_state == u"importing"_s)
        return tr("Importing the offline Forge pack…");
    if (m_state == u"pack_version_failed"_s)
        return tr("This offline pack does not match this version of Hexproof. Use a matching pack "
                  "or update Hexproof.");
    if (m_state == u"pack_platform_failed"_s)
        return tr("This offline pack is for another operating system or processor. Choose the pack "
                  "for this computer.");
    if (m_state == u"import_failed"_s)
        return tr("Could not import the offline pack. Check that the file is complete and readable "
                  "and that there is enough free disk space, then retry.");
    if (m_state == u"extracting"_s)
        return tr("Installing the local rules engine…");
    if (m_state == u"verifying"_s)
        return tr("Checking the local rules engine…");
    if (m_state == u"disk_space"_s)
        return tr("At least 1 GiB of free space is needed. Clear cached downloads or free disk "
                  "space, then retry.");
    if (m_state == u"cleaning"_s)
        return tr("Clearing unused Forge downloads and runtimes…");
    if (m_state == u"cache_cleared"_s)
        return tr("Freed %1 MiB. Current and running Forge installations were kept.")
            .arg(QString::number(static_cast<double>(m_freedBytes) / (1024 * 1024), 'f', 1));
    if (m_state == u"cleanup_failed"_s)
        return tr("The cache could not be cleared. Close other preparation windows and retry.");
    if (m_state == u"cancelled"_s || m_state == u"stopped"_s)
        return tr("Stopped. You can retry the import or resume the download.");
    if (m_state == u"host_stopped"_s)
        return tr("Local hosting stopped. The installed runtime is ready for reuse.");
    if (m_state == u"connected"_s)
        return tr("Local Forge is connected.");
    if (m_state == u"reconnecting"_s)
        return tr("Reconnecting the hosted engine… Keep Hexproof open.");
    if (m_state == u"helper_missing"_s)
        return tr("The hosting helper is missing. Reinstall the complete client package.");
    if (m_state == u"adapter_failed"_s)
        return tr("The bundled Forge adapter is missing or does not match this client. Reinstall "
                  "the complete client package.");
    if (m_state == u"version_mismatch"_s)
        return tr("The server requires a different Forge runtime. Update Hexproof.");
    if (m_state == u"prepare_failed"_s)
        return tr("The rules engine could not be prepared. Check the connection and free disk "
                  "space, then retry.");
    if (m_state.endsWith(u"failed"))
        return tr("Local Forge stopped or could not start. Return to the room and prepare hosting "
                  "again.");
    if (m_ready)
        return tr("The local rules engine is ready.");
    return tr("Download Java and Forge or import an offline pack to host games on this computer. "
              "Joining players do not need this installation.");
}

} // namespace hexproof::client
