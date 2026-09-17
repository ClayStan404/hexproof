// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "PeerTransportService.h"

#include <QCoreApplication>
#include <QDir>
#include <QFileInfo>
#include <QJsonDocument>
#include <QTimer>

namespace hexproof::client {
using namespace Qt::StringLiterals;

PeerTransportService::PeerTransportService(QObject *parent)
    : QObject(parent)
{
}

PeerTransportService::~PeerTransportService()
{
    for (auto *process : findChildren<QProcess *>()) {
        disconnect(process, nullptr, this, nullptr);
        process->closeWriteChannel();
        if (!process->waitForFinished(1000)) {
            process->kill();
            process->waitForFinished(1000);
        }
    }
}

void PeerTransportService::setState(const QString &state)
{
    if (state == m_state)
        return;
    m_state = state;
    emit changed();
}

void PeerTransportService::start(const QJsonObject &grant)
{
    const QString binding = grant.value(u"bindingId"_s).toString();
    if (binding == m_bindingId && m_process)
        return;
    stop();
    if (binding.size() != 64 || grant.value(u"token"_s).toString().size() != 64)
        return;
    m_bindingId = binding;
    m_gameId = grant.value(u"gameId"_s).toString();
    m_hostSeat = grant.value(u"hostSeat"_s).toInt(-1);
    QString name = u"hexproof-forge-host"_s;
#ifdef Q_OS_WIN
    name += u".exe"_s;
#endif
    const QString path = QDir(QCoreApplication::applicationDirPath()).filePath(name);
    if (!QFileInfo(path).isExecutable())
        return;
    m_process = new QProcess(this);
    QProcess *process = m_process;
    connect(process, &QProcess::readyReadStandardOutput, this, &PeerTransportService::readOutput);
    connect(process, &QProcess::readyReadStandardError, this,
            [process]() { process->readAllStandardError(); });
    connect(process, &QProcess::errorOccurred, this, [this, process](QProcess::ProcessError) {
        if (m_process == process)
            stop();
    });
    connect(process, &QProcess::finished, this, [this, process](int, QProcess::ExitStatus) {
        if (m_process == process) {
            m_process = nullptr;
            m_output.clear();
            setState(u"relay"_s);
        }
        process->deleteLater();
    });
    process->setProgram(path);
    process->setArguments({u"--peer"_s, u"--parent-pipe"_s});
    process->start();
    QJsonObject configuration{{u"bindingId"_s, binding},
                              {u"token"_s, grant.value(u"token"_s)},
                              {u"offerer"_s, grant.value(u"offerer"_s)},
                              {u"stun"_s, grant.value(u"stun"_s)}};
    write(configuration);
    setState(u"connecting"_s);
}

void PeerTransportService::stop()
{
    QProcess *process = m_process;
    m_process = nullptr;
    m_output.clear();
    m_bindingId.clear();
    m_gameId.clear();
    m_hostSeat = -1;
    if (process) {
        disconnect(process, &QProcess::readyReadStandardOutput, this,
                   &PeerTransportService::readOutput);
        process->closeWriteChannel();
        QTimer::singleShot(1000, process, [process]() {
            if (process->state() != QProcess::NotRunning)
                process->kill();
        });
    }
    setState(u"relay"_s);
}

bool PeerTransportService::write(const QJsonObject &value)
{
    if (!m_process || m_process->state() == QProcess::NotRunning)
        return false;
    const QByteArray data = QJsonDocument(value).toJson(QJsonDocument::Compact) + '\n';
    if (data.size() > 4 * 1024 * 1024 + 65536 ||
        m_process->bytesToWrite() + data.size() > 8 * 1024 * 1024) {
        stop();
        return false;
    }
    return m_process->write(data) == data.size();
}

bool PeerTransportService::send(const QJsonObject &message)
{
    return ready() && write({{u"message"_s, message}});
}

void PeerTransportService::signal(const QJsonObject &value)
{
    if (!write({{u"signal"_s, value}}))
        stop();
}

void PeerTransportService::readOutput()
{
    if (!m_process)
        return;
    m_output += m_process->readAllStandardOutput();
    if (m_output.size() > 8 * 1024 * 1024) {
        stop();
        return;
    }
    qsizetype newline;
    while ((newline = m_output.indexOf('\n')) >= 0) {
        const QByteArray line = m_output.left(newline);
        m_output.remove(0, newline + 1);
        const QJsonObject event = QJsonDocument::fromJson(line).object();
        if (event.value(u"bindingId"_s).toString() != m_bindingId)
            continue;
        if (event.contains(u"signal"_s))
            emit localSignal(event.value(u"signal"_s).toObject());
        else if (event.contains(u"message"_s))
            emit messageReceived(event.value(u"message"_s).toObject());
        else if (event.value(u"state"_s).toString() == u"direct"_s)
            setState(u"direct"_s);
        else
            setState(u"relay"_s);
    }
}
} // namespace hexproof::client
