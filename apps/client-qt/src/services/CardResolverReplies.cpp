// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "CardCatalogCommon.h"
#include "CardResolver.h"
#include "CatalogImport.h"

namespace hexproof::client {
using namespace catalog_internal;

namespace {

struct JsonTransport
{
    QByteArray payload;
    int httpStatus = 0;
    QNetworkReply::NetworkError networkError = QNetworkReply::NoError;
    QString networkErrorString;
    QByteArray retryAfter;
    QUrl requestUrl;
    bool networkOk = false;
};

struct ImageTransport
{
    QByteArray bytes;
    int httpStatus = 0;
    QNetworkReply::NetworkError networkError = QNetworkReply::NoError;
    QString networkErrorString;
    QByteArray retryAfter;
    QString contentType;
    QString declaredLength;
    QString responseHeaders;
    QUrl requestUrl;
    QUrl originalUrl;
    ImagePayloadInspection image;
    QString payloadKind;
    bool networkOk = false;
    bool ok = false;
};

JsonTransport takeJsonTransport(QNetworkReply *reply)
{
    JsonTransport transport;
    transport.payload = takeAvailableData(reply);
    transport.httpStatus = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
    transport.networkError = reply->error();
    transport.networkErrorString = reply->errorString();
    transport.retryAfter = reply->rawHeader(QByteArrayLiteral("Retry-After"));
    transport.networkOk =
        transport.networkError == QNetworkReply::NoError &&
        (transport.httpStatus == 0 || (transport.httpStatus >= 200 && transport.httpStatus < 300));
    transport.requestUrl = reply->url();
    reply->deleteLater();
    return transport;
}

ImageTransport takeImageTransport(QNetworkReply *reply)
{
    ImageTransport transport;
    transport.bytes = takeAvailableData(reply);
    transport.httpStatus = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
    transport.networkError = reply->error();
    transport.networkErrorString = reply->errorString();
    transport.retryAfter = reply->rawHeader(QByteArrayLiteral("Retry-After"));
    transport.contentType =
        reply->header(QNetworkRequest::ContentTypeHeader).toString().simplified();
    const QVariant contentLengthHeader = reply->header(QNetworkRequest::ContentLengthHeader);
    transport.declaredLength =
        contentLengthHeader.isValid() ? contentLengthHeader.toString() : QStringLiteral("<none>");
    transport.responseHeaders = diagnosticResponseHeaders(reply);
    transport.requestUrl = reply->url();
    transport.originalUrl = reply->request().url();
    transport.image = inspectImagePayload(transport.bytes);
    transport.payloadKind = imagePayloadKind(transport.bytes);
    transport.networkOk =
        transport.networkError == QNetworkReply::NoError &&
        (transport.httpStatus == 0 || (transport.httpStatus >= 200 && transport.httpStatus < 300));
    transport.ok = transport.networkOk && !transport.bytes.isEmpty() && transport.image.canRead;
    reply->deleteLater();
    return transport;
}

QString noneIfEmpty(const QString &value)
{
    return value.isEmpty() ? QStringLiteral("<none>") : value;
}

void logImageDebug(const QString &cardName, const ImageTransport &transport)
{
    qCDebug(cardCatalogLog).noquote()
        << "Card image response"
        << "card=" + cardName << QStringLiteral("http=%1").arg(transport.httpStatus)
        << QStringLiteral("networkError=%1").arg(static_cast<int>(transport.networkError))
        << "contentType=" + noneIfEmpty(transport.contentType)
        << QStringLiteral("bytes=%1").arg(transport.bytes.size())
        << "declaredLength=" + transport.declaredLength << "payloadKind=" + transport.payloadKind
        << "decoderFormat=" + (transport.image.format.isEmpty()
                                   ? QStringLiteral("<none>")
                                   : QString::fromLatin1(transport.image.format))
        << "decoderCanRead=" +
               QString(transport.image.canRead ? QStringLiteral("true") : QStringLiteral("false"))
        << "decoderError=" + transport.image.error
        << "url=" + transport.requestUrl.toString(QUrl::FullyEncoded);
}

void logImageFailure(const QString &cardName, const QString &printing,
                     const ImageTransport &transport)
{
    const bool transportFailure =
        transport.networkError != QNetworkReply::NoError || transport.bytes.isEmpty();
    const bool likelyTextResponse = transport.payloadKind == QStringLiteral("html") ||
                                    transport.payloadKind == QStringLiteral("json") ||
                                    (!transport.contentType.isEmpty() &&
                                     !transport.contentType.startsWith(QStringLiteral("image/")));
    qCWarning(cardCatalogLog).noquote()
        << "Card image download failed"
        << "card=" + cardName << "printing=" + noneIfEmpty(printing)
        << QStringLiteral("http=%1").arg(transport.httpStatus)
        << QStringLiteral("networkError=%1").arg(static_cast<int>(transport.networkError))
        << "networkErrorText=" + transport.networkErrorString
        << "contentType=" + noneIfEmpty(transport.contentType)
        << QStringLiteral("bytes=%1").arg(transport.bytes.size())
        << "declaredLength=" + transport.declaredLength << "payloadKind=" + transport.payloadKind
        << "magic=" + (transport.bytes.isEmpty()
                           ? QStringLiteral("<none>")
                           : QString::fromLatin1(transport.bytes.left(24).toHex(' ')))
        << "decoderFormat=" + (transportFailure
                                   ? QStringLiteral("<none>")
                                   : (transport.image.format.isEmpty()
                                          ? QStringLiteral("<none>")
                                          : QString::fromLatin1(transport.image.format)))
        << "decoderCanRead=" + QString((!transportFailure && transport.image.canRead)
                                           ? QStringLiteral("true")
                                           : QStringLiteral("false"))
        << "decoderError=" + (transportFailure ? QStringLiteral("<none>") : transport.image.error)
        << "supportedFormats=" +
               (transportFailure ? QStringLiteral("<none>") : supportedImageFormatsForLog())
        << "pluginPaths=" + (transportFailure
                                 ? QStringLiteral("<none>")
                                 : QCoreApplication::libraryPaths().join(QLatin1Char(';')))
        << "headers=" + noneIfEmpty(transport.responseHeaders)
        << "payloadPreview=" + (transport.bytes.isEmpty()
                                    ? QStringLiteral("<none>")
                                    : (likelyTextResponse ? printablePayloadPreview(transport.bytes)
                                                          : QStringLiteral("<binary>")))
        << "originalUrl=" + transport.originalUrl.toString(QUrl::FullyEncoded)
        << "finalUrl=" + transport.requestUrl.toString(QUrl::FullyEncoded);
}

} // namespace

void CardResolver::handleJsonReply(QNetworkReply *reply, Phase phase)
{
    const JsonTransport transport = takeJsonTransport(reply);
    QJsonParseError error;
    const QJsonDocument document = QJsonDocument::fromJson(transport.payload, &error);
    if (!transport.networkOk || error.error != QJsonParseError::NoError || !document.isObject()) {
        rejectJsonReply(transport.requestUrl, phase, transport.httpStatus,
                        static_cast<int>(transport.networkError), transport.networkErrorString,
                        transport.retryAfter, transport.networkOk);
        return;
    }
    markHostSuccess(transport.requestUrl);
    applyJsonObject(phase, document.object());
}

void CardResolver::rejectJsonReply(const QUrl &requestUrl, Phase phase, int httpStatus,
                                   int networkError, const QString &networkErrorString,
                                   const QByteArray &retryAfter, bool networkOk)
{
    const bool confirmedMissing = httpStatus == 404;
    const QString validationError = networkOk ? QStringLiteral("invalid JSON response") : QString{};
    setCurrentFailure(requestUrl, phase, httpStatus, networkError, networkErrorString,
                      validationError);
    if (!confirmedMissing && retryCurrentPhase(requestUrl, phase, httpStatus, retryAfter))
        return;
    markHostFailure(requestUrl, httpStatus, retryAfter, networkError);
    continueAfterJsonFailure(phase, confirmedMissing);
}

void CardResolver::applyJsonObject(Phase phase, const QJsonObject &object)
{
    switch (phase) {
    case Phase::ScryfallEnglish:
        applyScryfallEnglishJson(object);
        return;
    case Phase::ScryfallChineseExact:
        applyScryfallChineseExactJson(object);
        return;
    case Phase::ScryfallChineseSearch:
        applyScryfallChineseSearchJson(object);
        return;
    case Phase::Mtgch:
        applyMtgchJson(object);
        return;
    case Phase::Image:
    case Phase::None:
        finishCurrentCard(false, true);
        return;
    }
}

void CardResolver::applyScryfallEnglishJson(const QJsonObject &object)
{
    CardRecord scryfall =
        catalogimport::parseCardObject(object, QStringLiteral("en"), m_currentRequest.name);
    if (m_currentRequest.language == QStringLiteral("zh") &&
        looksLikeChinese(m_catalogRecord.localizedName)) {
        scryfall.localizedName = m_catalogRecord.localizedName;
        if (!m_catalogRecord.typeLine.isEmpty())
            scryfall.typeLine = m_catalogRecord.typeLine;
    }
    if (!scryfall.imageUrl.isEmpty()) {
        m_currentRecord = std::move(scryfall);
        beginImageRequest(ArtStage::ScryfallEnglish);
    } else {
        m_currentConfirmedMissing = true;
        beginNextEnglishCandidate();
    }
}

void CardResolver::applyScryfallChineseExactJson(const QJsonObject &object)
{
    QJsonArray printings;
    printings.append(object);
    if (m_callbacks.persistLocalizedPrintings)
        m_callbacks.persistLocalizedPrintings(printings);
    CardRecord scryfall =
        catalogimport::parseCardObject(object, QStringLiteral("zh"), m_currentRequest.name);
    if (looksLikeChinese(m_catalogRecord.localizedName))
        scryfall.localizedName = m_catalogRecord.localizedName;
    if (!m_catalogRecord.typeLine.isEmpty())
        scryfall.typeLine = m_catalogRecord.typeLine;
    if (!scryfall.imageUrl.isEmpty()) {
        m_currentRecord = std::move(scryfall);
        beginImageRequest(ArtStage::ScryfallChineseExact);
    } else {
        beginChineseAlternate();
    }
}

void CardResolver::applyScryfallChineseSearchJson(const QJsonObject &object)
{
    const QJsonArray printings = object.value(QStringLiteral("data")).toArray();
    if (m_callbacks.persistLocalizedPrintings)
        m_callbacks.persistLocalizedPrintings(printings);
    CardRecord best;
    int bestScore = std::numeric_limits<int>::max();
    for (const QJsonValue &value : printings) {
        const QJsonObject candidateObject = value.toObject();
        CardRecord candidate = catalogimport::parseCardObject(candidateObject, QStringLiteral("zh"),
                                                              m_currentRequest.name);
        if (candidate.imageUrl.isEmpty())
            continue;
        int score = candidateObject.value(QStringLiteral("digital")).toBool() ? 2 : 1;
        if (!m_catalogRecord.illustrationId.isEmpty() &&
            candidate.illustrationId.compare(m_catalogRecord.illustrationId, Qt::CaseInsensitive) ==
                0) {
            score = 0;
        }
        if (score < bestScore) {
            best = std::move(candidate);
            bestScore = score;
        }
    }
    if (best.valid() && !best.imageUrl.isEmpty()) {
        if (looksLikeChinese(m_catalogRecord.localizedName))
            best.localizedName = m_catalogRecord.localizedName;
        if (!m_catalogRecord.typeLine.isEmpty())
            best.typeLine = m_catalogRecord.typeLine;
        if (!m_currentRequest.setCode.isEmpty() && !m_currentRequest.collectorNumber.isEmpty()) {
            best.setCode = m_currentRequest.setCode;
            best.collectorNumber = m_currentRequest.collectorNumber;
            best.usesSubstituteArt = true;
        }
        m_currentRecord = std::move(best);
        beginImageRequest(ArtStage::ScryfallChineseAlternate);
    } else {
        continueAfterScryfallChinese();
    }
}

void CardResolver::applyMtgchJson(const QJsonObject &object)
{
    CardRecord mtgchChinese =
        catalogimport::parseCardObject(object, QStringLiteral("zh"), m_currentRequest.name);
    m_mtgchEnglishRecord =
        catalogimport::parseCardObject(object, QStringLiteral("en"), m_currentRequest.name);
    if (looksLikeChinese(m_catalogRecord.localizedName)) {
        mtgchChinese.localizedName = m_catalogRecord.localizedName;
        m_mtgchEnglishRecord.localizedName = m_catalogRecord.localizedName;
    }
    if (!m_catalogRecord.typeLine.isEmpty()) {
        if (mtgchChinese.typeLine.isEmpty())
            mtgchChinese.typeLine = m_catalogRecord.typeLine;
        if (m_mtgchEnglishRecord.typeLine.isEmpty())
            m_mtgchEnglishRecord.typeLine = m_catalogRecord.typeLine;
    }
    if (m_currentRequest.language == QStringLiteral("zh") && !mtgchChinese.imageUrl.isEmpty()) {
        m_currentConfirmedMissing = false;
        m_currentRecord = std::move(mtgchChinese);
        beginImageRequest(ArtStage::MtgchChinese);
    } else if (m_currentRequest.language == QStringLiteral("zh")) {
        continueAfterMtgchChinese();
    } else if (!m_mtgchEnglishRecord.imageUrl.isEmpty()) {
        m_currentMtgchEnglishImageTried = true;
        m_currentConfirmedMissing = false;
        m_currentRecord = m_mtgchEnglishRecord;
        beginImageRequest(ArtStage::MtgchEnglish);
    } else {
        m_currentConfirmedMissing = true;
        beginNextEnglishCandidate();
    }
}

void CardResolver::handleImageReply(QNetworkReply *reply)
{
    const ImageTransport transport = takeImageTransport(reply);
    logImageDebug(m_currentRequest.name, transport);
    if (!transport.ok) {
        QString validationError;
        if (transport.networkError == QNetworkReply::NoError && transport.httpStatus >= 200 &&
            transport.httpStatus < 300)
            validationError = QStringLiteral("invalid image data");
        setCurrentFailure(transport.requestUrl, Phase::Image, transport.httpStatus,
                          static_cast<int>(transport.networkError), transport.networkErrorString,
                          validationError);
        if (transport.httpStatus != 404 &&
            retryCurrentPhase(transport.requestUrl, Phase::Image, transport.httpStatus,
                              transport.retryAfter)) {
            qCDebug(cardCatalogLog).noquote()
                << "Card image download interrupted; retrying"
                << "card=" + m_currentRequest.name
                << QStringLiteral("networkError=%1").arg(static_cast<int>(transport.networkError))
                << "url=" + transport.requestUrl.toString(QUrl::FullyEncoded);
            return;
        }
        logImageFailure(m_currentRequest.name,
                        m_currentRecord.setCode.isEmpty()
                            ? QString{}
                            : m_currentRecord.setCode + QLatin1Char('/') +
                                  m_currentRecord.collectorNumber,
                        transport);
        markHostFailure(transport.requestUrl, transport.httpStatus, transport.retryAfter,
                        static_cast<int>(transport.networkError));
        continueAfterImageFailure(transport.httpStatus == 404);
        return;
    }
    markHostSuccess(transport.requestUrl);
    acceptImageBytes(transport.requestUrl, transport.bytes);
}

void CardResolver::acceptImageBytes(const QUrl &requestUrl, const QByteArray &bytes)
{
    const QString path = m_callbacks.imagePathFor
                             ? m_callbacks.imagePathFor(m_currentRequest, m_currentRecord)
                             : QString{};
    if (!writeBytesAtomically(path, bytes)) {
        setCurrentFailure(requestUrl, Phase::Image, 0, QNetworkReply::NoError, {},
                          QStringLiteral("could not write the image cache"));
        finishCurrentCard(false);
        return;
    }
    m_currentRecord.imagePath = path;
    finishCurrentCard(true);
}

} // namespace hexproof::client
