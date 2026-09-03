// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "CardArtCache.h"
#include "CardCatalog.h"
#include "CardCatalogCommon.h"
#include "CardResolver.h"

#include <QJsonDocument>
#include <QNetworkReply>
#include <QUrlQuery>

#include <algorithm>

namespace hexproof::client {
using namespace catalog_internal;

namespace {
QString printingKey(const QString &setCode, const QString &collectorNumber)
{
    return setCode.toUpper() + QChar(0x1f) + collectorNumber;
}

QString requestKey(const QString &name, const QString &setCode, const QString &collectorNumber)
{
    return name.simplified().toCaseFolded() + QChar(0x1f) + printingKey(setCode, collectorNumber);
}

QJsonObject matchingMtgchFace(const QJsonObject &card, const QString &requestedName)
{
    if (card.value(QStringLiteral("display_name"))
            .toString()
            .compare(requestedName, Qt::CaseInsensitive) == 0) {
        return card;
    }
    for (const QJsonValue &value : card.value(QStringLiteral("other_faces")).toArray()) {
        const QJsonObject face = value.toObject();
        if (face.value(QStringLiteral("display_name"))
                .toString()
                .compare(requestedName, Qt::CaseInsensitive) == 0) {
            return face;
        }
    }
    // Non-independent layouts such as prepare use one whole-card image and
    // retain the canonical `front // spell` request. An unmatched individual
    // face, however, must fall through to the ordinary resolver rather than
    // accepting the front image as the back face.
    return requestedName.contains(QStringLiteral(" // ")) ? card : QJsonObject{};
}
} // namespace

void CardCatalog::cacheLimitedProductArt(const QString &productId)
{
    clearOperationError();
    if (m_limitedArtCaching) {
        setLastError(QStringLiteral("Another Limited product art download is already running."));
        return;
    }
    if (!installed()) {
        setLastError(QStringLiteral("Install the card database before downloading product art."));
        return;
    }

    const QVariantMap product = limitedProduct(productId);
    if (product.isEmpty()) {
        setLastError(QStringLiteral("The Limited product is not installed locally."));
        return;
    }
    if (product.value(QStringLiteral("productType")).toString() == QStringLiteral("cube")) {
        setLastError(QStringLiteral("Product art download is available for set products only."));
        return;
    }

    QVariantList cards;
    QSet<QString> seenPrintings;
    for (const QVariant &sheetValue : product.value(QStringLiteral("sheets")).toList()) {
        for (const QVariant &cardValue :
             sheetValue.toMap().value(QStringLiteral("cards")).toList()) {
            QVariantMap card = cardValue.toMap();
            const QString name = card.value(QStringLiteral("name")).toString().simplified();
            const QString setCode = card.value(QStringLiteral("setCode")).toString().toUpper();
            const QString collectorNumber =
                card.value(QStringLiteral("collectorNumber")).toString();
            const QString key = requestKey(name, setCode, collectorNumber);
            if (name.isEmpty() || setCode.isEmpty() || collectorNumber.isEmpty() ||
                seenPrintings.contains(key)) {
                continue;
            }
            seenPrintings.insert(key);
            card.insert(QStringLiteral("name"), name);
            card.insert(QStringLiteral("setCode"), setCode);
            card.insert(QStringLiteral("collectorNumber"), collectorNumber);
            card.insert(QStringLiteral("exactArt"), true);
            cards.append(card);
        }
    }

    const QVariantList expandedCards = expandCardFaceRequests(cards);
    m_limitedArtRequests.clear();
    m_limitedArtMtgchCards.clear();
    m_limitedArtSetQueue.clear();
    m_limitedArtPendingKeys.clear();
    QSet<QString> setCodes;
    for (const QVariant &value : expandedCards) {
        const QVariantMap card = value.toMap();
        CardRequest request{
            card.value(QStringLiteral("name")).toString().simplified(),
            card.value(QStringLiteral("setCode")).toString().toUpper(),
            card.value(QStringLiteral("collectorNumber")).toString(),
            m_language,
        };
        request.exactArt = true;
        if (request.name.isEmpty())
            continue;
        const QString key = requestKey(request.name, request.setCode, request.collectorNumber);
        if (m_limitedArtPendingKeys.contains(key))
            continue;
        m_limitedArtPendingKeys.insert(key);
        m_limitedArtRequests.append(request);
        setCodes.insert(request.setCode);
        m_artCache->forgetFailure(
            cacheKey(request.name, request.language, request.setCode, request.collectorNumber));
    }
    if (m_limitedArtRequests.isEmpty()) {
        setLastError(QStringLiteral("The Limited product does not contain cacheable cards."));
        return;
    }

    m_limitedArtProductId = productId;
    m_limitedArtTotal = m_limitedArtRequests.size();
    m_limitedArtCompleted = 0;
    m_limitedArtFailed = 0;
    m_limitedArtCaching = true;
    if (m_cardResolver)
        m_cardResolver->clearCooldowns();
    emit limitedArtCacheChanged();
    emit busyChanged();

    const bool prefersMtgch =
        m_language == QStringLiteral("zh") && (m_cardArtProvider == QStringLiteral("auto") ||
                                               m_cardArtProvider == QStringLiteral("mtgch"));
    if (!prefersMtgch) {
        finishLimitedArtIndexing();
        return;
    }
    QList<QString> orderedSets = setCodes.values();
    std::sort(orderedSets.begin(), orderedSets.end());
    for (const QString &setCode : orderedSets)
        m_limitedArtSetQueue.enqueue(setCode);
    setStatus(QStringLiteral("Loading MTGCH set indexes for Limited product art…"));
    requestNextLimitedArtSetIndex();
}

void CardCatalog::requestNextLimitedArtSetIndex()
{
    if (!m_limitedArtCaching || m_shuttingDown)
        return;
    if (m_limitedArtSetQueue.isEmpty() || !m_cardResolver) {
        finishLimitedArtIndexing();
        return;
    }

    const QString setCode = m_limitedArtSetQueue.dequeue();
    QUrl url(QString::fromLatin1(kMtgchSetBaseUrl) +
             QString::fromLatin1(QUrl::toPercentEncoding(setCode)) + QStringLiteral("/cards/"));
    QUrlQuery query;
    query.addQueryItem(QStringLiteral("page_size"), QStringLiteral("9999"));
    url.setQuery(query);
    m_cardResolver->requestJson(url, [this, setCode](QNetworkReply *reply) {
        if (!reply) {
            requestNextLimitedArtSetIndex();
            return;
        }
        const QByteArray bytes = takeAvailableData(reply);
        const int status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
        const bool networkOk = reply->error() == QNetworkReply::NoError &&
                               (status == 0 || (status >= 200 && status < 300));
        reply->deleteLater();

        QJsonParseError parseError;
        const QJsonDocument document = QJsonDocument::fromJson(bytes, &parseError);
        if (networkOk && parseError.error == QJsonParseError::NoError && document.isObject()) {
            const QJsonObject object = document.object();
            QJsonArray items = object.value(QStringLiteral("items")).toArray();
            if (items.isEmpty())
                items = object.value(QStringLiteral("data")).toArray();
            for (const QJsonValue &value : items) {
                const QJsonObject card = value.toObject();
                const QString cardSet =
                    card.value(QStringLiteral("set")).toString(setCode).toUpper();
                const QString collector = card.value(QStringLiteral("collector_number")).toString();
                if (!collector.isEmpty())
                    m_limitedArtMtgchCards.insert(printingKey(cardSet, collector), card);
            }
        }
        requestNextLimitedArtSetIndex();
    });
}

void CardCatalog::finishLimitedArtIndexing()
{
    if (!m_limitedArtCaching)
        return;
    for (CardRequest &request : m_limitedArtRequests) {
        const QJsonObject card =
            m_limitedArtMtgchCards.value(printingKey(request.setCode, request.collectorNumber));
        if (card.isEmpty())
            continue;
        const QJsonObject face = matchingMtgchFace(card, request.name);
        if (face.isEmpty())
            continue;
        const QUrl imageUrl(face.value(QStringLiteral("image_url")).toString());
        const QString host = imageUrl.host().toLower();
        if (!imageUrl.isValid() || imageUrl.scheme() != QStringLiteral("https") ||
            (host != QStringLiteral("images.mtgch.com") &&
             !host.endsWith(QStringLiteral(".mtgch.com")))) {
            continue;
        }

        CardRecord record = lookupCatalog(request);
        if (!record.valid())
            record.name = request.name;
        record.requestedName = request.name;
        if (record.name.contains(QStringLiteral(" // ")) &&
            record.name.compare(request.name, Qt::CaseInsensitive) != 0) {
            record.faceName = request.name;
        }
        const QString localizedName =
            face.value(QStringLiteral("display_name_zh")).toString().simplified();
        if (!localizedName.isEmpty())
            record.localizedName = localizedName;
        if (record.localizedName.isEmpty())
            record.localizedName = request.name;
        if (record.typeLine.isEmpty())
            record.typeLine = face.value(QStringLiteral("display_type_line")).toString();
        record.setCode = request.setCode;
        record.collectorNumber = request.collectorNumber;
        record.imageUrl = imageUrl.toString();
        record.imageLanguage = QStringLiteral("zh");
        request.catalogHint = std::move(record);
    }
    m_limitedArtMtgchCards.clear();
    m_limitedArtSetQueue.clear();
    setStatus(QStringLiteral("Caching Limited product card images…"));
    enqueueRequests(m_limitedArtRequests);
    m_limitedArtRequests.clear();
}

void CardCatalog::handleLimitedArtCacheResult(const QString &requestedName, const QString &setCode,
                                              const QString &collectorNumber, bool success)
{
    if (!m_limitedArtCaching)
        return;
    const QString key = requestKey(requestedName, setCode, collectorNumber);
    if (!m_limitedArtPendingKeys.remove(key))
        return;
    ++m_limitedArtCompleted;
    if (!success)
        ++m_limitedArtFailed;
    if (m_limitedArtPendingKeys.isEmpty()) {
        m_limitedArtCaching = false;
        setStatus(m_limitedArtFailed == 0
                      ? QStringLiteral("Limited product card images are cached.")
                      : QStringLiteral("Limited product art finished with %1 unavailable image(s).")
                            .arg(m_limitedArtFailed));
        emit busyChanged();
    }
    emit limitedArtCacheChanged();
}

} // namespace hexproof::client
