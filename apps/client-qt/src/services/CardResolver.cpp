// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "CardResolver.h"
#include "CardCatalogCommon.h"
#include "NetworkLimits.h"
#include "NetworkRequestFactory.h"

#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QPointer>
#include <QTimer>
#include <QUrlQuery>

namespace hexproof::client {
using namespace catalog_internal;

CardResolver::CardResolver(QNetworkAccessManager *network, Callbacks callbacks, QObject *parent)
    : QObject(parent),
      m_network(network),
      m_callbacks(std::move(callbacks))
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
    QTimer::singleShot(110, this, [guard, url, finished = std::move(finished)]() {
        if (!guard)
            return;
        QNetworkReply *reply = guard->startRequest(
            guard->requestFor(url, QByteArrayLiteral("application/json;q=0.9,*/*;q=0.8")));
        if (!reply) {
            finished(nullptr);
            return;
        }
        network_limits::limitNetworkReply(reply, network_limits::kMaximumJsonResponseBytes);
        QObject::connect(reply, &QNetworkReply::finished, guard,
                         [reply, finished]() { finished(reply); });
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
    const auto cooldown = m_hostCooldowns.constFind(host);
    if (cooldown == m_hostCooldowns.cend())
        return false;
    if (*cooldown > QDateTime::currentDateTimeUtc())
        return true;
    m_hostCooldowns.remove(host);
    return false;
}

void CardResolver::markHostSuccess(const QUrl &url)
{
    m_hostCooldowns.remove(url.host().toLower());
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
    m_hostCooldowns.insert(host, QDateTime::currentDateTimeUtc().addMSecs(cooldownMs));
}

void CardResolver::clearCooldowns()
{
    m_hostCooldowns.clear();
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
