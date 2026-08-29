// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "MatchLoadCoordinator.h"

#include <QTimer>

namespace hexproof::client {

MatchLoadCoordinator::MatchLoadCoordinator(QObject *parent)
    : QObject(parent)
{
}

qreal MatchLoadCoordinator::progress() const
{
    return m_requests.isEmpty() ? (m_ready ? 1.0 : 0.0)
                                : static_cast<qreal>(completed()) / m_requests.size();
}

void MatchLoadCoordinator::beginLoad(qint64 loadId, const QVariantList &cardKeys)
{
    if (loadId <= 0 || (loadId == m_loadId && (m_active || m_ready)))
        return;

    m_loadId = loadId;
    m_active = true;
    m_ready = false;
    m_requests.clear();
    m_pending.clear();
    m_failed.clear();
    m_lastError.clear();

    for (const QVariant &value : cardKeys) {
        const QVariantMap request = value.toMap();
        const QString name = request.value(QStringLiteral("name")).toString().simplified();
        const QString setCode = request.value(QStringLiteral("setCode")).toString().toUpper();
        const QString collector = request.value(QStringLiteral("collectorNumber")).toString();
        if (name.isEmpty())
            continue;
        const QString key = requestKey(name, setCode, collector);
        if (m_requests.contains(key))
            continue;
        m_requests.insert(key, QVariantMap{
                                   {QStringLiteral("name"), name},
                                   {QStringLiteral("setCode"), setCode},
                                   {QStringLiteral("collectorNumber"), collector},
                               });
        m_pending.insert(key);
    }

    emit stateChanged();
    if (m_pending.isEmpty()) {
        QTimer::singleShot(0, this, [this]() { finishIfSettled(); });
        return;
    }
    QTimer::singleShot(0, this, [this, loadId]() {
        if (m_active && m_loadId == loadId && !m_pending.isEmpty())
            emit cardsRequested(requestsFor(m_pending));
    });
}

void MatchLoadCoordinator::handleCardCacheFinished(const QString &name, const QString &setCode,
                                                   const QString &collectorNumber, bool success)
{
    const QString key = requestKey(name, setCode, collectorNumber);
    if (!m_active || !m_pending.remove(key))
        return;
    if (success)
        m_failed.remove(key);
    else
        m_failed.insert(key);
    emit stateChanged();
    finishIfSettled();
}

void MatchLoadCoordinator::retry()
{
    if (!m_active || m_failed.isEmpty() || !m_pending.isEmpty())
        return;
    m_pending = m_failed;
    m_failed.clear();
    m_lastError.clear();
    emit stateChanged();
    emit cardsRequested(requestsFor(m_pending));
}

void MatchLoadCoordinator::cancel()
{
    if (m_loadId == 0 && !m_active && !m_ready)
        return;
    m_loadId = 0;
    m_active = false;
    m_ready = false;
    m_requests.clear();
    m_pending.clear();
    m_failed.clear();
    m_lastError.clear();
    emit stateChanged();
}

QString MatchLoadCoordinator::requestKey(const QString &name, const QString &setCode,
                                         const QString &collectorNumber)
{
    return name.simplified().toCaseFolded() + QLatin1Char('|') + setCode.simplified().toUpper() +
           QLatin1Char('|') + collectorNumber.simplified();
}

void MatchLoadCoordinator::finishIfSettled()
{
    if (!m_active || !m_pending.isEmpty())
        return;
    if (!m_failed.isEmpty()) {
        m_lastError = QStringLiteral("Some card images could not be loaded.");
        emit stateChanged();
        return;
    }
    m_active = false;
    m_ready = true;
    emit stateChanged();
    emit loadComplete(m_loadId);
}

QVariantList MatchLoadCoordinator::requestsFor(const QSet<QString> &keys) const
{
    QVariantList result;
    for (const QString &key : keys)
        result.append(m_requests.value(key));
    return result;
}

} // namespace hexproof::client
