// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "HubTransport.h"

#include <QCoreApplication>
#include <QDir>
#include <QFileInfo>
#include <QHostAddress>
#include <QJsonDocument>
#include <QJsonObject>
#include <QRegularExpression>

namespace hexproof::client {
using namespace Qt::StringLiterals;

namespace {
QString bundledHelper()
{
    QString name = u"hexproof-forge-host"_s;
#ifdef Q_OS_WIN
    name += u".exe"_s;
#endif
    return QDir(QCoreApplication::applicationDirPath()).filePath(name);
}
constexpr qint64 maximumQueuedBytes = 8 * 1024 * 1024 + 65536;
} // namespace

HubTransport::HubTransport(QObject *parent)
    : HubTransport(bundledHelper(), parent)
{
}

HubTransport::HubTransport(const QString &helperPath, QObject *parent)
    : QObject(parent),
      m_helperPath(helperPath)
{
    m_helperTimer.setSingleShot(true);
    m_helperTimer.setInterval(35000);
    connect(&m_helperTimer, &QTimer::timeout, this, &HubTransport::helperFailed);
}

HubTransport::~HubTransport()
{
    ++m_generation;
    stopBackend();
    for (auto *process : findChildren<QProcess *>()) {
        disconnect(process, nullptr, this, nullptr);
        process->closeWriteChannel();
        if (!process->waitForFinished(1000)) {
            process->kill();
            process->waitForFinished(1000);
        }
    }
}

bool HubTransport::isHomeUrl(const QUrl &url)
{
    static const QRegularExpression path(u"^/home/[a-z0-9][a-z0-9-]{0,62}/ws$"_s);
    const bool secure = url.scheme() == u"wss"_s;
    const bool local = url.scheme() == u"ws"_s &&
                       (QHostAddress(url.host()).isLoopback() || url.host() == u"localhost"_s);
    return url.isValid() && !url.host().isEmpty() && url.userInfo().isEmpty() &&
           !url.hasFragment() && (secure || local) && path.match(url.path()).hasMatch();
}

void HubTransport::setTransportState(const QString &state)
{
    if (m_transportState == state)
        return;
    m_transportState = state;
    emit transportStateChanged();
}

void HubTransport::open(const QUrl &url)
{
    abort();
    ++m_generation;
    m_url = url;
    m_error.clear();
    m_home = isHomeUrl(url);
    m_forceTurn = m_home && qEnvironmentVariableIntValue("HEXPROOF_HOME_FORCE_TURN") == 1;
    m_sentApplication = false;
    m_reportedConnected = false;
    m_state = QAbstractSocket::ConnectingState;
    if (m_home && (m_forceTurn || QFileInfo(m_helperPath).isExecutable())) {
        setTransportState(u"connecting"_s);
        openHelper();
    } else {
        openSocket();
    }
}

void HubTransport::openSocket()
{
    setTransportState(m_home ? u"relay"_s : QString{});
    auto *socket = new QWebSocket(QString{}, QWebSocketProtocol::VersionLatest, this);
    m_socket = socket;
    const quint64 generation = m_generation;
    socket->setMaxAllowedIncomingFrameSize(m_maximumFrameBytes);
    socket->setMaxAllowedIncomingMessageSize(m_maximumMessageBytes);
    connect(socket, &QWebSocket::connected, this, [this, socket, generation]() {
        if (generation != m_generation || socket != m_socket)
            return;
        m_state = QAbstractSocket::ConnectedState;
        m_reportedConnected = true;
        emit connected();
    });
    connect(socket, &QWebSocket::textMessageReceived, this,
            [this, socket, generation](const QString &message) {
                if (generation == m_generation && socket == m_socket)
                    emit textMessageReceived(message);
            });
    connect(socket, &QWebSocket::disconnected, this, [this, socket, generation]() {
        if (generation == m_generation && socket == m_socket)
            finish();
    });
#if QT_VERSION >= QT_VERSION_CHECK(6, 5, 0)
    connect(socket, &QWebSocket::errorOccurred, this,
#else
    connect(socket, qOverload<QAbstractSocket::SocketError>(&QWebSocket::error), this,
#endif
            [this, socket, generation](QAbstractSocket::SocketError error) {
                if (generation != m_generation || socket != m_socket)
                    return;
                m_error = socket->errorString();
                emit errorOccurred(error);
            });
    socket->open(m_url);
}

void HubTransport::openHelper()
{
    auto *process = new QProcess(this);
    m_process = process;
    const quint64 generation = m_generation;
    process->setProgram(m_helperPath);
    process->setArguments({u"--home-connect"_s, u"--parent-pipe"_s});
    process->setStandardErrorFile(QProcess::nullDevice());
    connect(process, &QProcess::started, this, [this, process, generation]() {
        if (generation != m_generation || process != m_process)
            return;
        QJsonObject configuration{{u"url"_s, m_url.toString(QUrl::FullyEncoded)}};
        if (qEnvironmentVariableIntValue("HEXPROOF_HOME_FORCE_RELAY") == 1)
            configuration.insert(u"forceRelay"_s, true);
        if (m_forceTurn)
            configuration.insert(u"forceTURN"_s, true);
        if (!writeHelper(configuration))
            helperFailed();
    });
    connect(process, &QProcess::readyReadStandardOutput, this,
            [this, process, generation]() { readHelperOutput(process, generation); });
    connect(process, &QProcess::errorOccurred, this,
            [this, process, generation](QProcess::ProcessError) {
                if (generation == m_generation && process == m_process)
                    helperFailed();
            });
    connect(process, &QProcess::finished, this,
            [this, process, generation](int, QProcess::ExitStatus) {
                // Deliver complete final messages before publishing disconnect.
                readHelperOutput(process, generation);
                if (generation == m_generation && process == m_process)
                    helperFailed();
                process->deleteLater();
            });
    m_helperTimer.start();
    process->start();
}

bool HubTransport::writeHelper(const QJsonObject &value)
{
    if (!m_process || m_process->state() != QProcess::Running)
        return false;
    const QByteArray wire = QJsonDocument(value).toJson(QJsonDocument::Compact) + '\n';
    if (wire.size() > maximumQueuedBytes ||
        m_process->bytesToWrite() + wire.size() > maximumQueuedBytes)
        return false;
    return m_process->write(wire) == wire.size();
}

qint64 HubTransport::sendTextMessage(const QString &message)
{
    if (m_state != QAbstractSocket::ConnectedState)
        return -1;
    if (m_socket)
        return m_socket->sendTextMessage(message);
    const QByteArray wire = message.toUtf8();
    const QJsonDocument document = QJsonDocument::fromJson(wire);
    if (!document.isObject())
        return -1;
    // A failed write can be ambiguous. Never switch paths and resend it.
    m_sentApplication = true;
    if (!writeHelper({{u"message"_s, document.object()}})) {
        const quint64 generation = m_generation;
        QTimer::singleShot(0, this, [this, generation]() {
            if (generation == m_generation)
                helperFailed();
        });
        return -1;
    }
    return wire.size();
}

void HubTransport::readHelperOutput(QProcess *process, quint64 generation)
{
    if (generation != m_generation || process != m_process)
        return;
    process->setReadChannel(QProcess::StandardOutput);
    while (process->bytesAvailable() > 0) {
        m_output += process->read(65536);
        qsizetype newline;
        while ((newline = m_output.indexOf('\n')) >= 0) {
            if (quint64(newline) > m_maximumMessageBytes + 65536) {
                helperFailed();
                return;
            }
            const QJsonDocument document = QJsonDocument::fromJson(m_output.left(newline));
            m_output.remove(0, newline + 1);
            if (!document.isObject()) {
                helperFailed();
                return;
            }
            const QJsonObject event = document.object();
            const QString state = event.value(u"state"_s).toString();
            if (state == u"connected"_s && !m_reportedConnected &&
                (event.value(u"transport"_s) == u"direct"_s ||
                 event.value(u"transport"_s) == u"relay"_s)) {
                m_helperTimer.stop();
                m_state = QAbstractSocket::ConnectedState;
                m_reportedConnected = true;
                setTransportState(event.value(u"transport"_s).toString());
                emit connected();
            } else if (event.value(u"message"_s).isObject() && m_reportedConnected) {
                const QByteArray message = QJsonDocument(event.value(u"message"_s).toObject())
                                               .toJson(QJsonDocument::Compact);
                if (quint64(message.size()) > m_maximumMessageBytes) {
                    helperFailed();
                    return;
                }
                emit textMessageReceived(QString::fromUtf8(message));
            } else {
                helperFailed();
                return;
            }
            if (generation != m_generation || process != m_process)
                return;
        }
        if (quint64(m_output.size()) > m_maximumMessageBytes + 65536) {
            helperFailed();
            return;
        }
    }
}

void HubTransport::helperFailed()
{
    if (!m_process)
        return;
    // Missing/old helpers may fail before opening a connection. The same public
    // home URL supports WSS; no application command has entered either path.
    if (!m_forceTurn && !m_sentApplication && !m_reportedConnected) {
        stopBackend();
        openSocket();
        return;
    }
    m_error = u"home server connection closed"_s;
    emit errorOccurred(QAbstractSocket::RemoteHostClosedError);
    finish();
}

void HubTransport::stopBackend()
{
    m_helperTimer.stop();
    m_output.clear();
    if (auto *socket = m_socket) {
        m_socket = nullptr;
        disconnect(socket, nullptr, this, nullptr);
        socket->abort();
        socket->deleteLater();
    }
    if (auto *process = m_process) {
        m_process = nullptr;
        process->closeWriteChannel();
        QTimer::singleShot(1000, process, [process]() {
            if (process->state() != QProcess::NotRunning)
                process->kill();
            else
                process->deleteLater();
        });
    }
}

void HubTransport::finish()
{
    const bool wasOpen = m_state != QAbstractSocket::UnconnectedState;
    ++m_generation;
    stopBackend();
    m_state = QAbstractSocket::UnconnectedState;
    setTransportState({});
    if (wasOpen)
        emit disconnected();
}

void HubTransport::abort()
{
    finish();
}

void HubTransport::close()
{
    if (m_socket)
        m_socket->close();
    else
        finish();
}

void HubTransport::ping(const QByteArray &payload)
{
    if (m_socket)
        m_socket->ping(payload);
    // The home helper owns its network heartbeat and liveness deadlines.
}

void HubTransport::setMaxAllowedIncomingFrameSize(quint64 size)
{
    m_maximumFrameBytes = size;
    if (m_socket)
        m_socket->setMaxAllowedIncomingFrameSize(size);
}

void HubTransport::setMaxAllowedIncomingMessageSize(quint64 size)
{
    m_maximumMessageBytes = size;
    if (m_socket)
        m_socket->setMaxAllowedIncomingMessageSize(size);
}

} // namespace hexproof::client
