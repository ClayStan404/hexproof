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
                                : static_cast<qreal>(completed() - failed()) / m_requests.size();
}

void MatchLoadCoordinator::preparePreload(qint64 loadId, const QVariantList &cardKeys)
{
    prepareLoad(loadId, cardKeys, false);
}

void MatchLoadCoordinator::prepareBackground(qint64 loadId, const QVariantList &cardKeys)
{
    prepareLoad(loadId, cardKeys, true);
}

void MatchLoadCoordinator::prepareLoad(qint64 loadId, const QVariantList &cardKeys,
                                       bool waitForTableSnapshot)
{
    if (loadId <= 0 || (loadId == m_loadId && (m_active || m_ready)))
        return;

    invalidateCurrentSubscriptions();
    ++m_generation;
    m_loadId = loadId;
    m_active = true;
    m_ready = false;
    m_expansionPending = true;
    m_backgroundLoad = waitForTableSnapshot;
    m_waitingForTableSnapshot = waitForTableSnapshot && !m_tableSnapshotReady;
    m_expansionScheduled = false;
    m_cardKeys = cardKeys;
    m_requests.clear();
    m_requestOrder.clear();
    m_pending.clear();
    m_failed.clear();
    m_localAvailable = 0;
    m_lastError.clear();

    emit stateChanged();
    if (!m_waitingForTableSnapshot)
        scheduleExpansion();
}

void MatchLoadCoordinator::handleTableSnapshotStateChanged(bool ready)
{
    m_tableSnapshotReady = ready;
    if (!m_active || !m_backgroundLoad)
        return;
    m_waitingForTableSnapshot = !ready;
    if (ready && m_expansionPending)
        scheduleExpansion();
}

void MatchLoadCoordinator::handleCardLanguageChanged()
{
    if (!m_active)
        return;

    invalidateCurrentSubscriptions();
    ++m_generation;
    m_ready = false;
    m_expansionPending = true;
    m_expansionScheduled = false;
    m_requests.clear();
    m_requestOrder.clear();
    m_pending.clear();
    m_failed.clear();
    m_localAvailable = 0;
    m_lastError.clear();
    emit stateChanged();
    if (!m_waitingForTableSnapshot)
        scheduleExpansion();
}

void MatchLoadCoordinator::scheduleExpansion()
{
    if (!m_active || !m_expansionPending || m_waitingForTableSnapshot || m_expansionScheduled)
        return;
    m_expansionScheduled = true;
    const qint64 loadId = m_loadId;
    const quint64 generation = m_generation;
    QTimer::singleShot(0, this, [this, loadId, generation]() {
        if (m_loadId != loadId || m_generation != generation)
            return;
        m_expansionScheduled = false;
        if (!m_active || !m_expansionPending || m_waitingForTableSnapshot)
            return;
        emit cardFaceExpansionRequested(loadId, generation, m_cardKeys);
    });
}

void MatchLoadCoordinator::adoptExpandedCards(qint64 loadId, quint64 generation,
                                              const QVariantList &cards)
{
    if (!m_active || !m_expansionPending || loadId != m_loadId || generation != m_generation)
        return;

    m_expansionPending = false;
    for (const QVariant &value : cards) {
        const QVariantMap request = value.toMap();
        const QString name = request.value(QStringLiteral("name")).toString().simplified();
        const QString setCode = request.value(QStringLiteral("setCode")).toString().toUpper();
        const QString collector = request.value(QStringLiteral("collectorNumber")).toString();
        if (name.isEmpty())
            continue;
        const bool exactArt = request.value(QStringLiteral("exactArt")).toBool();
        const QString key = requestKey(name, setCode, collector, exactArt);
        if (m_requests.contains(key))
            continue;
        QVariantMap normalizedRequest = request;
        normalizedRequest.insert(QStringLiteral("name"), name);
        normalizedRequest.insert(QStringLiteral("setCode"), setCode);
        normalizedRequest.insert(QStringLiteral("collectorNumber"), collector);
        m_requests.insert(key, normalizedRequest);
        m_requestOrder.append(key);
        if (request.value(QStringLiteral("_hexproofLocalArtAvailable")).toBool())
            ++m_localAvailable;
        else
            m_pending.insert(key);
    }

    emit stateChanged();
    if (m_pending.isEmpty()) {
        QTimer::singleShot(0, this, [this]() { finishIfSettled(); });
        return;
    }
    emit cardsRequested(m_loadId, m_generation, requestsFor(m_pending));
}

void MatchLoadCoordinator::handleMatchCardCacheFinished(qint64 loadId, quint64 generation,
                                                        const QString &requestIdentity,
                                                        const QString &name, const QString &setCode,
                                                        const QString &collectorNumber,
                                                        bool exactArt, bool success)
{
    if (!m_active || loadId != m_loadId || generation != m_generation ||
        requestIdentity.isEmpty()) {
        return;
    }
    const QString key = requestKey(name, setCode, collectorNumber, exactArt);
    if (!m_pending.remove(key))
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
    emit cardsRetryRequested(m_loadId, m_generation, requestsFor(m_pending));
}

void MatchLoadCoordinator::cancel()
{
    if (m_loadId == 0 && !m_active && !m_ready)
        return;
    invalidateCurrentSubscriptions();
    ++m_generation;
    m_loadId = 0;
    m_active = false;
    m_ready = false;
    m_expansionPending = false;
    m_backgroundLoad = false;
    m_waitingForTableSnapshot = false;
    m_expansionScheduled = false;
    m_cardKeys.clear();
    m_requests.clear();
    m_requestOrder.clear();
    m_pending.clear();
    m_failed.clear();
    m_localAvailable = 0;
    m_lastError.clear();
    emit stateChanged();
}

QString MatchLoadCoordinator::requestKey(const QString &name, const QString &setCode,
                                         const QString &collectorNumber, bool exactArt)
{
    QString key = name.simplified().toCaseFolded() + QLatin1Char('|') +
                  setCode.simplified().toUpper() + QLatin1Char('|') + collectorNumber.simplified();
    if (exactArt)
        key += QStringLiteral("|exact-art");
    return key;
}

void MatchLoadCoordinator::invalidateCurrentSubscriptions()
{
    if (m_loadId > 0 && m_generation > 0)
        emit matchCardSubscriptionsInvalidated(m_loadId, m_generation);
}

void MatchLoadCoordinator::finishIfSettled()
{
    if (!m_active || m_expansionPending || !m_pending.isEmpty())
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
    for (const QString &key : m_requestOrder) {
        if (keys.contains(key))
            result.append(m_requests.value(key));
    }
    return result;
}

} // namespace hexproof::client
