// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "ReconnectController.h"

#include "ServerDirectory.h"

#include <QDateTime>
#include <QSettings>
#include <QtGlobal>

#include <algorithm>

namespace hexproof::client {

namespace {
using namespace Qt::StringLiterals;

constexpr qint64 ReconnectWindowMs = 3 * 60 * 1000;
constexpr int ResumePersistDelayMs = 2000;
} // namespace

ReconnectController::ReconnectController(ServerDirectory *serverDirectory, QObject *parent)
    : QObject(parent),
      m_serverDirectory(serverDirectory)
{
    Q_ASSERT(m_serverDirectory);

    m_retryTimer.setSingleShot(true);
    connect(&m_retryTimer, &QTimer::timeout, this, [this]() {
        if (QDateTime::currentMSecsSinceEpoch() >= m_deadlineMs) {
            emit reconnectExpired();
            return;
        }
        ++m_attempt;
        emit retryDue();
    });

    m_persistTimer.setSingleShot(true);
    m_persistTimer.setInterval(ResumePersistDelayMs);
    connect(&m_persistTimer, &QTimer::timeout, this, &ReconnectController::persist);

    m_countdownTimer.setInterval(1000);
    connect(&m_countdownTimer, &QTimer::timeout, this,
            &ReconnectController::updateRemainingSeconds);

    load();
}

ReconnectController::~ReconnectController()
{
    flush();
}

bool ReconnectController::matches(const QString &serverUrl, const QString &displayName) const
{
    return serverUrl == m_serverUrl && displayName == m_displayName;
}

void ReconnectController::updateSession(const QString &token, const QString &serverUrl,
                                        const QString &displayName)
{
    if (!token.isEmpty())
        m_token = token;
    m_serverUrl = serverUrl;
    m_displayName = displayName;
}

void ReconnectController::observeSequence(qint64 seq)
{
    if (seq <= m_lastSeq)
        return;
    m_lastSeq = seq;
    if (hasCredentials())
        m_persistTimer.start();
}

void ReconnectController::resetSequence()
{
    m_lastSeq = 0;
}

void ReconnectController::beginReconnectWindow()
{
    m_attempt = 0;
    m_deadlineMs = QDateTime::currentMSecsSinceEpoch() + ReconnectWindowMs;
    updateRemainingSeconds();
    m_countdownTimer.start();
}

void ReconnectController::scheduleRetry()
{
    if (!m_retryTimer.isActive())
        m_retryTimer.start(retryDelayMs(m_attempt));
}

void ReconnectController::stopRetry()
{
    m_retryTimer.stop();
    m_countdownTimer.stop();
    if (m_remainingSeconds != 0) {
        m_remainingSeconds = 0;
        emit remainingSecondsChanged();
    }
}

void ReconnectController::flush()
{
    m_persistTimer.stop();
    persist();
}

void ReconnectController::clear()
{
    m_retryTimer.stop();
    m_persistTimer.stop();
    m_countdownTimer.stop();
    m_token.clear();
    m_serverUrl.clear();
    m_displayName.clear();
    m_lastSeq = 0;
    m_deadlineMs = 0;
    m_attempt = 0;
    if (m_remainingSeconds != 0) {
        m_remainingSeconds = 0;
        emit remainingSecondsChanged();
    }

    QSettings settings;
    settings.remove(u"network/resumeToken"_s);
    settings.remove(u"network/resumeServerUrl"_s);
    settings.remove(u"network/resumeDisplayName"_s);
    settings.remove(u"network/resumeLastSeq"_s);
    settings.sync();
}

int ReconnectController::retryDelayMs(int attempt)
{
    const int exponent = qBound(0, attempt, 3);
    return qMin(10000, 1000 * (1 << exponent));
}

void ReconnectController::updateRemainingSeconds()
{
    const qint64 remainingMs =
        std::max<qint64>(0, m_deadlineMs - QDateTime::currentMSecsSinceEpoch());
    const int remainingSeconds = static_cast<int>((remainingMs + 999) / 1000);
    if (m_remainingSeconds == remainingSeconds)
        return;
    m_remainingSeconds = remainingSeconds;
    emit remainingSecondsChanged();
    if (m_remainingSeconds == 0)
        m_countdownTimer.stop();
}

void ReconnectController::load()
{
    QSettings settings;
    m_token = settings.value(u"network/resumeToken"_s).toString();
    m_serverUrl = m_serverDirectory->normalizePersistedUrl(
        settings.value(u"network/resumeServerUrl"_s).toString());
    m_displayName = settings.value(u"network/resumeDisplayName"_s).toString();
    m_lastSeq = settings.value(u"network/resumeLastSeq"_s).toLongLong();
}

void ReconnectController::persist()
{
    if (!hasCredentials())
        return;
    QSettings settings;
    settings.setValue(u"network/resumeToken"_s, m_token);
    settings.setValue(u"network/resumeServerUrl"_s, m_serverUrl);
    settings.setValue(u"network/resumeDisplayName"_s, m_displayName);
    settings.setValue(u"network/resumeLastSeq"_s, m_lastSeq);
    settings.sync();
}

} // namespace hexproof::client
