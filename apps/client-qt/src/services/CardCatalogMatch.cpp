// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "CardCatalog.h"

#include <algorithm>

namespace hexproof::client {

void CardCatalog::cacheMatchCardsIncrementally(qint64 loadId, quint64 generation,
                                               const QVariantList &cards)
{
    queueMatchCards(loadId, generation, cards, false);
}

void CardCatalog::queueMatchCards(qint64 loadId, quint64 generation, const QVariantList &cards,
                                  bool retry)
{
    QVariantList missing;
    for (const QVariant &value : cards) {
        const QVariantMap map = value.toMap();
        CardRequest request{map.value(QStringLiteral("name")).toString(),
                            map.value(QStringLiteral("setCode")).toString().toUpper(),
                            map.value(QStringLiteral("collectorNumber")).toString(), m_language};
        request.exactArt = map.value(QStringLiteral("exactArt")).toBool();
        if (customImagePath(request).isEmpty()) {
            missing.append(value);
        } else {
            // Display readiness is local presentation state, not a successful
            // official download. Do not write overrides into the normal cache.
            emit matchCardCacheFinished(loadId, generation, queuedRequestKey(request), request.name,
                                        request.setCode, request.collectorNumber, request.exactArt,
                                        true);
        }
    }
    subscribeMatchCards(loadId, generation, missing);
    if (retry)
        retryCards(missing);
    else
        cacheCardsIncrementally(missing);
}

void CardCatalog::retryMatchCards(qint64 loadId, quint64 generation, const QVariantList &cards)
{
    // Match retries share the local override readiness shortcut. Explicit
    // library cache/repair commands still download official images normally.
    queueMatchCards(loadId, generation, cards, true);
}

void CardCatalog::subscribeMatchCards(qint64 loadId, quint64 generation, const QVariantList &cards)
{
    for (const QVariant &value : cards) {
        const QVariantMap map = value.toMap();
        CardRequest request{
            map.value(QStringLiteral("name")).toString().simplified(),
            map.value(QStringLiteral("setCode")).toString().toUpper(),
            map.value(QStringLiteral("collectorNumber")).toString(),
            m_language,
        };
        request.exactArt = map.value(QStringLiteral("exactArt")).toBool();
        if (request.name.isEmpty())
            continue;
        QList<MatchCacheSubscription> &subscriptions =
            m_matchCacheSubscriptions[queuedRequestKey(request)];
        const bool duplicate = std::any_of(
            subscriptions.cbegin(), subscriptions.cend(),
            [loadId, generation](const MatchCacheSubscription &subscription) {
                return subscription.loadId == loadId && subscription.generation == generation;
            });
        if (!duplicate)
            subscriptions.append({loadId, generation});
    }
}

void CardCatalog::cancelMatchCardSubscriptions(qint64 loadId, quint64 generation)
{
    for (auto it = m_matchCacheSubscriptions.begin(); it != m_matchCacheSubscriptions.end();) {
        QList<MatchCacheSubscription> &subscriptions = it.value();
        subscriptions.removeIf([loadId, generation](const MatchCacheSubscription &subscription) {
            return subscription.loadId == loadId && subscription.generation == generation;
        });
        if (subscriptions.isEmpty())
            it = m_matchCacheSubscriptions.erase(it);
        else
            ++it;
    }
}

} // namespace hexproof::client
