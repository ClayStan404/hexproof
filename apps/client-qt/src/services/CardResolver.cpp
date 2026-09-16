// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "CardResolver.h"
#include "CardCatalogCommon.h"
#include "NetworkLimits.h"
#include "NetworkRequestFactory.h"

#include <QElapsedTimer>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QPointer>
#include <QQueue>
#include <QTimer>
#include <QUrlQuery>

#include <utility>

namespace hexproof::client {
using namespace catalog_internal;

struct CardResolver::NetworkState final : QObject
{
    using StartJson = std::function<void(std::function<void()>)>;
    struct JsonLane
    {
        QQueue<StartJson> requests;
        QElapsedTimer lastStart;
        int active = 0;
        bool scheduled = false;
    };

    QHash<QString, QDateTime> hostCooldowns;
    QHash<QString, JsonLane> jsonLanes;

    void enqueueJson(const QString &host, StartJson start)
    {
        jsonLanes[host].requests.enqueue(std::move(start));
        startNextJson(host);
    }

    void startNextJson(const QString &host)
    {
        auto &lane = jsonLanes[host];
        if (lane.scheduled || lane.active >= 3 || lane.requests.isEmpty())
            return;
        lane.scheduled = true;
        const int delay = lane.lastStart.isValid()
                              ? static_cast<int>(qMax<qint64>(0, 110 - lane.lastStart.elapsed()))
                              : 0;
        // Pace request starts independently of response latency. A slow
        // lookup may occupy one of the host's three slots, but cannot block
        // every other card. All workers and fallback chains share this gate.
        QTimer::singleShot(delay, Qt::PreciseTimer, this, [this, host]() {
            auto &ready = jsonLanes[host];
            ready.scheduled = false;
            ++ready.active;
            ready.lastStart.start();
            auto start = ready.requests.dequeue();
            start([this, host]() {
                --jsonLanes[host].active;
                startNextJson(host);
            });
            startNextJson(host);
        });
    }
};

CardResolver::CardResolver(QNetworkAccessManager *network, Callbacks callbacks, QObject *parent)
    : QObject(parent),
      m_network(network),
      m_callbacks(std::move(callbacks)),
      m_networkState(std::make_shared<NetworkState>())
{
}

CardResolver::CardResolver(CardResolver &networkOwner, Callbacks callbacks, QObject *parent)
    : QObject(parent),
      m_network(networkOwner.m_network),
      m_callbacks(std::move(callbacks)),
      m_networkState(networkOwner.m_networkState)
{
}

CardResolver::~CardResolver()
{
    const auto replies = m_activeReplies.values();
    for (QNetworkReply *reply : replies) {
        if (!reply)
            continue;
        QObject::disconnect(reply, nullptr, this, nullptr);
        reply->abort();
    }
    m_activeReplies.clear();
}

QUrl CardResolver::chineseExactUrl(const QString &setCode, const QString &collectorNumber) const
{
    const QString set = QString::fromLatin1(QUrl::toPercentEncoding(setCode.toLower()));
    const QString collector = QString::fromLatin1(QUrl::toPercentEncoding(collectorNumber));
    return QUrl(QStringLiteral("https://api.scryfall.com/cards/%1/%2/zhs").arg(set, collector));
}

QUrl CardResolver::chineseSearchUrl(const QString &oracleId, const QString &name) const
{
    QUrl url(QString::fromLatin1(kScryfallSearchUrl));
    QUrlQuery query;
    if (!oracleId.isEmpty()) {
        query.addQueryItem(QStringLiteral("q"),
                           QStringLiteral("oracleid:%1 lang:zhs").arg(oracleId));
    } else {
        query.addQueryItem(QStringLiteral("q"), QStringLiteral("!\"%1\" lang:zhs").arg(name));
    }
    query.addQueryItem(QStringLiteral("unique"), QStringLiteral("prints"));
    query.addQueryItem(QStringLiteral("order"), QStringLiteral("released"));
    query.addQueryItem(QStringLiteral("dir"), QStringLiteral("desc"));
    url.setQuery(query);
    return url;
}

QUrl CardResolver::englishUrl(const QString &name, const QString &setCode,
                              const QString &collectorNumber) const
{
    if (!setCode.isEmpty() && !collectorNumber.isEmpty()) {
        const QString set = QString::fromLatin1(QUrl::toPercentEncoding(setCode.toLower()));
        const QString collector = QString::fromLatin1(QUrl::toPercentEncoding(collectorNumber));
        return QUrl(QStringLiteral("https://api.scryfall.com/cards/%1/%2").arg(set, collector));
    }

    QUrl url(QString::fromLatin1(kScryfallNamedUrl));
    QUrlQuery query;
    query.addQueryItem(QStringLiteral("exact"), name);
    url.setQuery(query);
    return url;
}

QUrl CardResolver::mtgchUrl(const QString &setCode, const QString &collectorNumber) const
{
    if (setCode.isEmpty() || collectorNumber.isEmpty())
        return {};
    return QUrl(QString::fromLatin1(kMtgchCardBaseUrl) +
                QString::fromLatin1(QUrl::toPercentEncoding(setCode.toUpper())) + QLatin1Char('/') +
                QString::fromLatin1(QUrl::toPercentEncoding(collectorNumber)) + QLatin1Char('/'));
}

QNetworkRequest CardResolver::requestFor(const QUrl &url, const QByteArray &accept,
                                         int transferTimeoutMs) const
{
    return makeNetworkRequest(url, accept, transferTimeoutMs);
}

QNetworkReply *CardResolver::startRequest(const QNetworkRequest &request)
{
    if (!m_network)
        return nullptr;
    QNetworkReply *reply = m_network->get(request);
    trackReply(reply);
    return reply;
}

void CardResolver::trackReply(QNetworkReply *reply)
{
    if (!reply)
        return;
    m_activeReplies.insert(reply);
    QObject::connect(reply, &QObject::destroyed, this,
                     [this, reply]() { m_activeReplies.remove(reply); });
    QObject::connect(reply, &QNetworkReply::finished, this,
                     [this, reply]() { m_activeReplies.remove(reply); });
}

QNetworkReply *CardResolver::requestImage(const QUrl &url)
{
    QNetworkReply *reply =
        startRequest(requestFor(url, QByteArrayLiteral("image/*"), kCardImageTransferTimeoutMs));
    network_limits::limitNetworkReply(reply, network_limits::kMaximumCardImageResponseBytes);
    return reply;
}

void CardResolver::requestJson(const QUrl &url, std::function<void(QNetworkReply *)> finished)
{
    QPointer<CardResolver> guard(this);
    NetworkState *state = m_networkState.get();
    state->enqueueJson(url.host().toLower(), [guard, state, url, finished = std::move(finished)](
                                                 std::function<void()> release) {
        if (!guard) {
            release();
            return;
        }
        // Another worker may have opened a cooldown while this request waited.
        if (guard->hostInCooldown(url)) {
            release();
            finished(nullptr);
            return;
        }
        QNetworkReply *reply = guard->startRequest(
            guard->requestFor(url, QByteArrayLiteral("application/json;q=0.9,*/*;q=0.8")));
        if (!reply) {
            release();
            finished(nullptr);
            return;
        }
        network_limits::limitNetworkReply(reply, network_limits::kMaximumJsonResponseBytes);
        QObject::connect(reply, &QNetworkReply::finished, guard,
                         [reply, finished]() { finished(reply); });
        const auto released = std::make_shared<bool>(false);
        const auto releaseOnce = [released, release = std::move(release)]() {
            if (!std::exchange(*released, true))
                release();
        };
        QObject::connect(reply, &QNetworkReply::finished, state, releaseOnce);
        QObject::connect(reply, &QObject::destroyed, state, releaseOnce);
    });
}

int CardResolver::retryDelayMs(int httpStatus, const QByteArray &retryAfter) const
{
    if (httpStatus == 429) {
        const qint64 requestedDelay = retryAfterDelayMs(retryAfter);
        if (requestedDelay < 0 ||
            requestedDelay > static_cast<qint64>(kMaximumRetryAfterSeconds) * 1000) {
            return -1;
        }
        return static_cast<int>(qMax<qint64>(1000, requestedDelay));
    }
    if (httpStatus == 0 || httpStatus == 408 || httpStatus >= 500)
        return 750;
    if (httpStatus >= 200 && httpStatus < 300)
        return 750;
    return -1;
}

bool CardResolver::hostInCooldown(const QUrl &url)
{
    const QString host = url.host().toLower();
    if (host.isEmpty())
        return false;
    const auto cooldown = m_networkState->hostCooldowns.constFind(host);
    if (cooldown == m_networkState->hostCooldowns.cend())
        return false;
    if (*cooldown > QDateTime::currentDateTimeUtc())
        return true;
    m_networkState->hostCooldowns.remove(host);
    return false;
}

void CardResolver::markHostSuccess(const QUrl &url)
{
    // A response already in flight must not cancel another worker's 429.
    hostInCooldown(url);
}

void CardResolver::markHostFailure(const QUrl &url, int httpStatus, const QByteArray &retryAfter,
                                   int networkErrorCode)
{
    const QString host = url.host().toLower();
    if (host.isEmpty())
        return;
    // A single interrupted CDN fetch is not a downed provider. Cooling down
    // cards.scryfall.io after a timeout or connection reset hides every other
    // printing for 60s.
    if (networkErrorCode == QNetworkReply::TimeoutError ||
        networkErrorCode == QNetworkReply::RemoteHostClosedError ||
        networkErrorCode == QNetworkReply::TemporaryNetworkFailureError)
        return;
    if (httpStatus != 0 && httpStatus != 403 && httpStatus != 408 && httpStatus != 429 &&
        httpStatus < 500) {
        return;
    }
    qint64 cooldownMs = retryAfterDelayMs(retryAfter);
    if (cooldownMs < 0)
        cooldownMs = static_cast<qint64>(kHostCooldownSeconds) * 1000;
    cooldownMs = qMax<qint64>(1000, cooldownMs);
    const QDateTime until = QDateTime::currentDateTimeUtc().addMSecs(cooldownMs);
    auto &cooldown = m_networkState->hostCooldowns[host];
    if (!cooldown.isValid() || until > cooldown)
        cooldown = until;
}

void CardResolver::clearCooldowns()
{
    m_networkState->hostCooldowns.clear();
}

QString CardResolver::phaseName(Phase phase) const
{
    switch (phase) {
    case Phase::Mtgch:
        return QStringLiteral("MTGCH metadata");
    case Phase::ScryfallChineseExact:
    case Phase::ScryfallChineseSearch:
        return QStringLiteral("Scryfall Chinese metadata");
    case Phase::ScryfallEnglish:
        return QStringLiteral("Scryfall English metadata");
    case Phase::Image:
        return QStringLiteral("card image");
    case Phase::None:
        return QStringLiteral("card data");
    }
    return QStringLiteral("card data");
}

} // namespace hexproof::client
