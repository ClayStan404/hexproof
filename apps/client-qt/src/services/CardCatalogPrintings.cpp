// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "CardArtCache.h"
#include "CardArtCrop.h"
#include "CardArtStorage.h"
#include "CardCatalog.h"
#include "CardCatalogCommon.h"
#include "CardCatalogQueryInternal.h"
#include "CardImageProvider.h"
#include "CardResolver.h"
#include "CatalogRepository.h"
#include "CatalogStorage.h"
#include "deck/Deck.h"

#include <QRegularExpression>
#include <QUuid>

namespace hexproof::client {
using namespace catalog_internal;

namespace {
constexpr int kMaximumQueuedFaceMetadataProbes = 256;
}

QVariantList CardCatalog::printings(const QString &name)
{
    if (m_catalogBusy || !installed())
        return {};
    const QString key = m_language + QChar(0x1f) + QString::number(m_indexVersion) + QChar(0x1f) +
                        name.simplified().toLower();
    if (m_printingsCache.contains(key)) {
        clearPrintingsError();
        return m_printingsCache.value(key);
    }
    QString error;
    const QVariantList result = guiCatalog().printings(name, m_language, &error);
    if (!error.isEmpty()) {
        setPrintingsError(error);
        return {};
    }
    clearPrintingsError();
    m_printingsCache.insert(key, result);
    return result;
}

QVariantList CardCatalog::cardFaces(const QString &name, const QString &setCode,
                                    const QString &collectorNumber)
{
    const QString key = name.simplified().toLower() + QChar(0x1f) + setCode.toUpper() +
                        QChar(0x1f) + collectorNumber;
    if (!m_catalogBusy && installed() && m_cardFacesCache.contains(key)) {
        clearPrintingsError();
        return m_cardFacesCache.value(key);
    }
    if (!m_catalogBusy && installed()) {
        QString error, layout, canonical;
        const QVariantList result =
            guiCatalog().cardFaces(name, setCode, collectorNumber, &error, &layout, &canonical);
        if (!error.isEmpty()) {
            setPrintingsError(error);
            return {};
        }
        clearPrintingsError();
        if (!canonical.isEmpty()) {
            m_cardFacesCache.insert(key, result);
            return result;
        }
    }
    const CardRequest request{name.simplified(), setCode.toUpper(), collectorNumber, m_language};
    const CardRecord record = m_artCache->faceMetadata(request);
    if (!record.faceMetadataChecked ||
        record.faceMetadataSetCode.compare(setCode, Qt::CaseInsensitive) != 0 ||
        record.faceMetadataCollectorNumber != collectorNumber)
        return {};
    static const QSet<QString> independentLayouts{
        QStringLiteral("transform"), QStringLiteral("modal_dfc"),
        QStringLiteral("double_faced_token"), QStringLiteral("reversible_card")};
    if (independentLayouts.contains(record.layout) && record.independentFaces.size() == 2) {
        for (const QVariant &value : record.independentFaces) {
            const QVariantMap face = value.toMap();
            if (face.value(QStringLiteral("name")).toString().isEmpty() ||
                face.value(QStringLiteral("setCode"))
                        .toString()
                        .compare(setCode, Qt::CaseInsensitive) != 0 ||
                face.value(QStringLiteral("collectorNumber")).toString() != collectorNumber)
                return {};
        }
        return record.independentFaces;
    }
    if (record.layout != QStringLiteral("meld") || record.meldResultId.isEmpty() ||
        record.meldResultName.isEmpty() || record.meldResultName == record.name)
        return {};
    const CardRecord target = m_artCache->faceMetadataById(record.meldResultId);
    if (!target.valid() || target.name != record.meldResultName)
        return {};
    return {QVariantMap{{QStringLiteral("name"), record.name},
                        {QStringLiteral("faceName"), QString{}},
                        {QStringLiteral("displayName"), record.name},
                        {QStringLiteral("typeLine"), record.typeLine},
                        {QStringLiteral("setCode"), record.faceMetadataSetCode},
                        {QStringLiteral("collectorNumber"), record.faceMetadataCollectorNumber}},
            QVariantMap{{QStringLiteral("name"), target.name},
                        {QStringLiteral("faceName"), target.name},
                        {QStringLiteral("displayName"), target.name},
                        {QStringLiteral("typeLine"), target.typeLine},
                        {QStringLiteral("setCode"), target.faceMetadataSetCode},
                        {QStringLiteral("collectorNumber"), target.faceMetadataCollectorNumber},
                        {QStringLiteral("relatedCard"), true}}};
}

void CardCatalog::storeFaceMetadata(const CardRequest &request, const CardRecord &record)
{
    if (m_shuttingDown || m_artCacheBusy || !m_artStorage->writesAllowed())
        return;
    const QString key =
        cacheKey(request.name, request.language, request.setCode, request.collectorNumber);
    const CardRecord previous = m_artCache->exactRecord(key);
    if (previous.valid() &&
        (previous.setCode.compare(record.faceMetadataSetCode, Qt::CaseInsensitive) != 0 ||
         previous.collectorNumber != record.faceMetadataCollectorNumber))
        return;
    const bool discardAmbiguousBack = ambiguousLegacySameNamedFace(previous) &&
                                      record.faceMetadataChecked &&
                                      record.independentFaces.size() == 2;
    CardRecord updated = previous.valid() && !discardAmbiguousBack ? previous : record;
    if (discardAmbiguousBack) {
        updated.imagePath.clear();
        updated.artCropPath.clear();
        updated.artCropUrl.clear();
        updated.requestedName = request.name;
    }
    updated.layout = record.layout;
    updated.printingId = record.printingId;
    updated.faceMetadataSetCode = record.faceMetadataSetCode;
    updated.faceMetadataCollectorNumber = record.faceMetadataCollectorNumber;
    updated.independentFaces = record.independentFaces;
    updated.meldResultId = record.meldResultId;
    updated.meldResultName = record.meldResultName;
    updated.faceMetadataChecked = record.faceMetadataChecked;
    m_artCache->rememberSuccess(key, updated);
    m_artCache->saveAsync();
    scheduleImageRevisionChanged();
}

void CardCatalog::prepareCardFacePreview(const QString &name, const QString &setCode,
                                         const QString &collectorNumber)
{
    const CardRequest request{name.simplified(), setCode.toUpper(), collectorNumber, m_language};
    if (m_shuttingDown || !m_network || request.name.isEmpty() || !request.specifiesPrinting())
        return;
    if (!m_catalogBusy && installed()) {
        QString error, layout, canonical;
        guiCatalog().cardFaces(name, setCode, collectorNumber, &error, &layout, &canonical);
        if (!canonical.isEmpty())
            return;
    }
    const CardRecord cached = m_artCache->faceMetadata(request);
    if (!cached.valid())
        return; // Normal art resolution will publish metadata for uncached cards.
    if (cached.faceMetadataChecked && cached.faceMetadataSetCode == request.setCode &&
        cached.faceMetadataCollectorNumber == request.collectorNumber) {
        if (cached.layout == QStringLiteral("meld"))
            refreshMeldResultMetadata(cached);
        return;
    }
    const QString probeKey = request.setCode + QChar(0x1f) + request.collectorNumber;
    if (m_faceMetadataRequests.contains(probeKey) ||
        m_faceMetadataProbes.size() >= kMaximumQueuedFaceMetadataProbes)
        return;
    m_faceMetadataRequests.insert(probeKey);
    m_faceMetadataProbes.enqueue({request, {}});
    processFaceMetadataProbes();
}

void CardCatalog::refreshMeldResultMetadata(const CardRecord &record)
{
    if (record.layout != QStringLiteral("meld") || record.meldResultName == record.name ||
        QUuid(record.meldResultId).isNull() ||
        m_artCache->faceMetadataById(record.meldResultId).valid())
        return;
    const QString probeKey = QStringLiteral("meld:") + record.meldResultId;
    if (m_faceMetadataRequests.contains(probeKey) ||
        m_faceMetadataProbes.size() >= kMaximumQueuedFaceMetadataProbes)
        return;
    m_faceMetadataRequests.insert(probeKey);
    m_faceMetadataProbes.enqueue(
        {{record.meldResultName, {}, {}, QStringLiteral("en")}, record.meldResultId});
    processFaceMetadataProbes();
}

void CardCatalog::processFaceMetadataProbes()
{
    if (m_shuttingDown || m_catalogBusy || m_artCacheBusy || !artWritesAllowed() ||
        m_faceMetadataProbeActive || m_faceMetadataProbes.isEmpty())
        return;
    m_faceMetadataProbeActive = true;
    const FaceMetadataProbe probe = m_faceMetadataProbes.dequeue();
    const QUrl url =
        probe.printingId.isEmpty()
            ? m_cardResolver->englishUrl(probe.request.name, probe.request.setCode,
                                         probe.request.collectorNumber)
            : QUrl(QStringLiteral("https://api.scryfall.com/cards/") + probe.printingId);
    QNetworkReply *reply = m_network->get(
        m_cardResolver->requestFor(url, QByteArrayLiteral("application/json"), 15000));
    connect(reply, &QNetworkReply::finished, this, [this, reply, probe]() {
        reply->deleteLater();
        // Legacy cache batches share a single paced metadata lane. Previewing
        // many cards must not burst one provider request per existing image.
        QTimer::singleShot(150, this, [this]() {
            m_faceMetadataProbeActive = false;
            processFaceMetadataProbes();
        });
        if (m_shuttingDown || reply->error() != QNetworkReply::NoError ||
            reply->bytesAvailable() > 1024 * 1024)
            return;
        const CardRecord record =
            parseCardObject(QJsonDocument::fromJson(reply->readAll()).object(),
                            QStringLiteral("en"), probe.request.name);
        if (!record.faceMetadataChecked)
            return;
        CardRequest request = probe.request;
        if (!probe.printingId.isEmpty()) {
            if (record.printingId != probe.printingId || record.name != request.name ||
                record.faceMetadataSetCode.isEmpty() ||
                record.faceMetadataCollectorNumber.isEmpty())
                return;
            request.setCode = record.faceMetadataSetCode;
            request.collectorNumber = record.faceMetadataCollectorNumber;
        } else {
            if (record.faceMetadataSetCode != request.setCode ||
                record.faceMetadataCollectorNumber != request.collectorNumber)
                return;
            const QStringList names = record.name.split(QStringLiteral(" // "), Qt::SkipEmptyParts);
            if (record.name.compare(request.name, Qt::CaseInsensitive) != 0 &&
                !names.contains(request.name, Qt::CaseInsensitive))
                return;
        }
        storeFaceMetadata(request, record);
        if (record.layout == QStringLiteral("meld"))
            refreshMeldResultMetadata(record);
    });
}

QVariantList CardCatalog::expandCardFaceRequests(const QVariantList &cards)
{
    QVariantList result;
    QSet<QString> requestKeys;
    const auto appendRequest = [&result, &requestKeys](QVariantMap request) {
        const QString name = request.value(QStringLiteral("name")).toString().simplified();
        if (name.isEmpty())
            return;
        request.insert(QStringLiteral("name"), name);
        request.insert(kCardFacesExpandedKey, true);
        const QString key =
            name.toCaseFolded() + QChar(0x1f) +
            request.value(QStringLiteral("setCode")).toString().toUpper() + QChar(0x1f) +
            request.value(QStringLiteral("collectorNumber")).toString() + QChar(0x1f) +
            request.value(QStringLiteral("kind")).toString() + QChar(0x1f) +
            (request.value(QStringLiteral("exactArt")).toBool() ? QLatin1Char('1')
                                                                : QLatin1Char('0'));
        if (requestKeys.contains(key))
            return;
        requestKeys.insert(key);
        result.append(request);
    };

    for (const QVariant &value : cards) {
        QVariantMap request = value.toMap();
        const QString name = request.value(QStringLiteral("name")).toString().simplified();
        if (!request.contains(QStringLiteral("priorityName")))
            request.insert(QStringLiteral("priorityName"), name);
        const QString setCode = request.value(QStringLiteral("setCode")).toString().toUpper();
        const QString collectorNumber = request.value(QStringLiteral("collectorNumber")).toString();
        const QVariantList faces = cardFaces(name, setCode, collectorNumber);
        if (faces.size() < 2) {
            appendRequest(request);
            continue;
        }
        for (const QVariant &faceValue : faces) {
            QVariantMap faceRequest = request;
            const QVariantMap face = faceValue.toMap();
            faceRequest.insert(QStringLiteral("name"), face.value(QStringLiteral("name")));
            faceRequest.insert(QStringLiteral("faceName"), face.value(QStringLiteral("faceName")));
            if (face.value(QStringLiteral("relatedCard")).toBool()) {
                faceRequest.insert(QStringLiteral("setCode"),
                                   face.value(QStringLiteral("setCode")));
                faceRequest.insert(QStringLiteral("collectorNumber"),
                                   face.value(QStringLiteral("collectorNumber")));
            }
            appendRequest(faceRequest);
        }
    }
    return result;
}

QString CardCatalog::imageSource(const QString &name, const QString &setCode,
                                 const QString &collectorNumber) const
{
    const CardRequest request{
        name.simplified(),
        setCode.toUpper(),
        collectorNumber,
        m_language,
    };
    const QString path = resolvedImagePath(request);
    return path.isEmpty() ? QString{} : QUrl::fromLocalFile(path).toString();
}

QString CardCatalog::printingImageSource(const QString &name, const QString &setCode,
                                         const QString &collectorNumber) const
{
    CardRequest request{
        name.simplified(),
        setCode.toUpper(),
        collectorNumber,
        m_language,
    };
    request.exactArt = true;
    const QString key =
        cacheKey(request.name, request.language, request.setCode, request.collectorNumber);
    const CardRecord exact = m_artCache->exactRecord(key);
    QString path;
    if (exact.valid() && exact.resolutionVersion >= kCardResolutionVersion &&
        m_artCache->matchesRequestedFace(request, exact) && !exact.usesSubstituteArt &&
        QFileInfo::exists(exact.imagePath)) {
        path = exact.imagePath;
    } else {
        path = cachedResolvedPrinting(request).imagePath;
    }
    return QFileInfo::exists(path) ? QUrl::fromLocalFile(path).toString() : QString{};
}

QString CardCatalog::previewImageSource(const QString &name, const QString &setCode,
                                        const QString &collectorNumber, bool token) const
{
    const QString source = token ? tokenImageSource(name, setCode, collectorNumber)
                                 : imageSource(name, setCode, collectorNumber);
    return m_cardImageProvider && !source.isEmpty()
               ? m_cardImageProvider->previewSourceForPath(QUrl(source).toLocalFile())
               : source;
}

QString CardCatalog::tableImageSource(const QString &name, const QString &setCode,
                                      const QString &collectorNumber) const
{
    const CardRequest request{
        name.simplified(),
        setCode.toUpper(),
        collectorNumber,
        m_language,
    };
    const QString path = resolvedTableImagePath(request);
    if (path.isEmpty())
        return {};
    if (!m_cardImageProvider)
        return QUrl::fromLocalFile(path).toString();
    return m_cardImageProvider->sourceForPath(path);
}

QString CardCatalog::tableArtCropSource(const QString &name, const QString &setCode,
                                        const QString &collectorNumber) const
{
    const CardRequest request{name.simplified(), setCode.toUpper(), collectorNumber, m_language};
    const QString path = resolvedArtCropPath(request);
    if (path.isEmpty())
        return {};
    return m_cardImageProvider ? m_cardImageProvider->sourceForPath(path)
                               : QUrl::fromLocalFile(path).toString();
}

QString CardCatalog::resolvedArtCropPath(const CardRequest &request) const
{
    if (request.name.isEmpty() || !customImagePath(request).isEmpty())
        return {};
    const CardRequest related = relatedArtRequest(request);
    if (related.setCode != request.setCode || related.collectorNumber != request.collectorNumber)
        return resolvedArtCropPath(related);
    const QString key =
        cacheKey(request.name, request.language, request.setCode, request.collectorNumber);
    CardRecord selected = m_artCache->exactRecord(key);
    // Select the same record as tableImageSource, including its substitute and
    // face rules. An optional asset may never change which printing is shown.
    if (!(selected.valid() && selected.resolutionVersion >= kCardResolutionVersion &&
          m_artCache->matchesRequestedFace(request, selected) &&
          (!selected.reusesLocalArt || request.allowsSubstituteArt(m_artCache->reuseLocalArt())) &&
          !selected.imagePath.isEmpty()))
        selected = m_artCache->resolvedPrintingMetadata(request);
    if (selected.imagePath.isEmpty() || selected.artCropUrl.isEmpty() ||
        selected.artCropUrl != artCropUrlForImage(selected.imageUrl) ||
        !QFileInfo::exists(selected.artCropPath))
        return {};
    return verifiedArtCrop(selected.artCropPath, request.name) ? selected.artCropPath : QString{};
}

QString CardCatalog::resolvedImagePath(const CardRequest &request) const
{
    const QString custom = customImagePath(request);
    if (!custom.isEmpty())
        return custom;
    const CardRequest related = relatedArtRequest(request);
    if (related.setCode != request.setCode || related.collectorNumber != request.collectorNumber)
        return resolvedImagePath(related);
    const QString key =
        cacheKey(request.name, request.language, request.setCode, request.collectorNumber);
    const CardRecord exact = m_artCache->exactRecord(key);
    if (exact.valid() && exact.resolutionVersion >= kCardResolutionVersion &&
        m_artCache->matchesRequestedFace(request, exact) &&
        (!exact.reusesLocalArt || request.allowsSubstituteArt(m_artCache->reuseLocalArt())) &&
        QFileInfo::exists(exact.imagePath)) {
        return exact.imagePath;
    }

    const QString path = cachedResolvedPrinting(request).imagePath;
    if (QFileInfo::exists(path))
        return path;
    return {};
}

QString CardCatalog::resolvedTableImagePath(const CardRequest &request) const
{
    const QString custom = customImagePath(request);
    if (!custom.isEmpty())
        return custom;
    const CardRequest related = relatedArtRequest(request);
    if (related.setCode != request.setCode || related.collectorNumber != request.collectorNumber)
        return resolvedTableImagePath(related);
    const QString key =
        cacheKey(request.name, request.language, request.setCode, request.collectorNumber);
    const CardRecord exact = m_artCache->exactRecord(key);
    if (exact.valid() && exact.resolutionVersion >= kCardResolutionVersion &&
        m_artCache->matchesRequestedFace(request, exact) &&
        (!exact.reusesLocalArt || request.allowsSubstituteArt(m_artCache->reuseLocalArt())) &&
        !exact.imagePath.isEmpty()) {
        return exact.imagePath;
    }
    const QString path = m_artCache->resolvedPrintingMetadata(request).imagePath;
    if (!path.isEmpty())
        return path;
    return {};
}

QString CardCatalog::cachedTypeLine(const CardRequest &request) const
{
    if (request.name.isEmpty())
        return {};

    const QString key =
        cacheKey(request.name, request.language, request.setCode, request.collectorNumber);
    const CardRecord exact = m_artCache->exactRecord(key);
    if (m_artCache->matchesRequestedFace(request, exact) && !exact.typeLine.isEmpty())
        return exact.typeLine;

    const CardRecord cached = m_artCache->resolvedPrintingMetadata(request);
    if (!cached.typeLine.isEmpty())
        return cached.typeLine;
    return {};
}

QString CardCatalog::cachedCardTypeLine(const QString &name, const QString &setCode,
                                        const QString &collectorNumber) const
{
    const CardRequest request{
        name.simplified(),
        setCode.toUpper(),
        collectorNumber,
        m_language,
    };
    const QString cached = cachedTypeLine(request);
    if (!cached.isEmpty() || request.language == QStringLiteral("en"))
        return cached;

    return cachedTypeLine(CardRequest{
        request.name,
        request.setCode,
        request.collectorNumber,
        QStringLiteral("en"),
    });
}

QString CardCatalog::cardArtFrame(const QString &name, const QString &setCode,
                                  const QString &collectorNumber) const
{
    const CardRequest visible{name.simplified(), setCode.toUpper(), collectorNumber, m_language};
    if (visible.name.isEmpty() || !customImagePath(visible).isEmpty())
        return QStringLiteral("full");
    const auto tableMetadata = [&](const CardRequest &request) {
        const CardRecord exact = m_artCache->exactRecord(
            cacheKey(request.name, request.language, request.setCode, request.collectorNumber));
        if (exact.valid() && exact.resolutionVersion >= kCardResolutionVersion &&
            m_artCache->matchesRequestedFace(request, exact) &&
            (!exact.reusesLocalArt || request.allowsSubstituteArt(m_artCache->reuseLocalArt())) &&
            !exact.imagePath.isEmpty())
            return exact;
        return m_artCache->resolvedPrintingMetadata(request);
    };
    const CardRecord visibleArt = tableMetadata(visible);
    CardRecord imageMetadata;
    if (visibleArt.usesSubstituteArt) {
        // Substitution records can retain the requested set/number and rules
        // while reusing another printing's pixels. Resolve by the actual image
        // URL, and cache both verified frames and conservative misses.
        const QString key = QStringLiteral("art-frame\x1f") + visibleArt.name.toLower() +
                            QChar(0x1f) + visibleArt.imageUrl + QChar(0x1f) +
                            QString::number(m_indexVersion);
        if (const CardRecord *cached = m_lookupCache.object(key)) {
            imageMetadata = *cached;
        } else if (!m_catalogBusy && installed()) {
            imageMetadata = guiCatalog().imageFrameMetadata(visibleArt);
            m_lookupCache.insert(key, new CardRecord(imageMetadata));
        }
        if (!imageMetadata.valid() || imageMetadata.typeLine.isEmpty() ||
            looksLikeChinese(imageMetadata.typeLine))
            return QStringLiteral("full");
    }

    // Classify the current face with canonical English metadata, independently
    // of printed language. lookupCatalog caches both hits and misses; this is
    // evaluated when the face/printing or its art stamp changes, never per paint.
    const CardRequest english{
        visible.name, imageMetadata.valid() ? imageMetadata.setCode : visible.setCode,
        imageMetadata.valid() ? imageMetadata.collectorNumber : visible.collectorNumber,
        QStringLiteral("en")};
    const CardRecord cached = imageMetadata.valid() ? imageMetadata : tableMetadata(english);
    // The English cache can contain substitute pixels even when the visible
    // language uses the original printing. Its metadata cannot classify that
    // original image; use the indexed canonical printing instead.
    const CardRecord indexed = cached.usesSubstituteArt || cached.layout.isEmpty() ||
                                       cached.typeLine.isEmpty() ||
                                       looksLikeChinese(cached.typeLine)
                                   ? lookupCatalog(english)
                                   : CardRecord{};
    CardRecord metadata = cached.valid() && !cached.usesSubstituteArt &&
                                  !cached.typeLine.isEmpty() && !looksLikeChinese(cached.typeLine)
                              ? cached
                              : indexed;
    if (!metadata.valid() || metadata.usesSubstituteArt ||
        (!imageMetadata.valid() && english.specifiesPrinting() &&
         (metadata.setCode.compare(english.setCode, Qt::CaseInsensitive) != 0 ||
          metadata.collectorNumber != english.collectorNumber)))
        return QStringLiteral("full");
    if (metadata.layout.isEmpty())
        metadata.layout = indexed.layout;

    const QStringList names = metadata.name.split(QStringLiteral(" // "), Qt::SkipEmptyParts);
    const QStringList types = metadata.typeLine.split(QStringLiteral(" // "), Qt::KeepEmptyParts);
    int face = 0;
    if (names.size() > 1 && english.name.compare(metadata.name, Qt::CaseInsensitive) != 0) {
        face = -1;
        for (qsizetype index = 0; index < names.size(); ++index) {
            if (names.at(index).compare(english.name, Qt::CaseInsensitive) == 0) {
                face = static_cast<int>(index);
                break;
            }
        }
        if (face < 0)
            return QStringLiteral("full");
    }
    if (types.size() > 1) {
        if (types.size() != names.size())
            return QStringLiteral("full");
        metadata.typeLine = types.at(face);
    }
    const QStringList words = metadata.typeLine.split(
        QRegularExpression(QStringLiteral("[^A-Za-z]+")), Qt::SkipEmptyParts);
    if (words.contains(QStringLiteral("Saga")))
        return QStringLiteral("saga");
    if (words.contains(QStringLiteral("Class")))
        return QStringLiteral("class");
    if (words.contains(QStringLiteral("Battle")))
        return QStringLiteral("battle");
    if (metadata.layout == QStringLiteral("flip"))
        return face == 1 ? QStringLiteral("flip-back") : QStringLiteral("flip");
    static const QSet<QString> ordinaryLayouts{QStringLiteral("normal"),
                                               QStringLiteral("token"),
                                               QStringLiteral("transform"),
                                               QStringLiteral("modal_dfc"),
                                               QStringLiteral("double_faced_token"),
                                               QStringLiteral("adventure"),
                                               QStringLiteral("meld"),
                                               QStringLiteral("leveler")};
    if (!metadata.typeLine.isEmpty() && (ordinaryLayouts.contains(metadata.layout) ||
                                         (metadata.layout.isEmpty() && names.size() <= 1)))
        return words.contains(QStringLiteral("Planeswalker")) ? QStringLiteral("planeswalker")
                                                              : QStringLiteral("standard");
    return QStringLiteral("full");
}

QString CardCatalog::cardRulesText(const QString &name, const QString &setCode,
                                   const QString &collectorNumber, const QString &language) const
{
    const QString selected = language == QStringLiteral("en") || language == QStringLiteral("zh")
                                 ? language
                                 : m_language;
    const CardRequest request{name.simplified(), setCode.toUpper(), collectorNumber, selected};
    if (request.name.isEmpty())
        return {};
    const auto acceptable = [&](const CardRecord &record) {
        if (record.oracleText.isEmpty() || !m_artCache->matchesRequestedFace(request, record))
            return false;
        if (selected == QStringLiteral("zh")) {
            return record.oracleTextLanguage == QStringLiteral("zh") ||
                   (record.oracleTextLanguage.isEmpty() && looksLikeChinese(record.oracleText));
        }
        return record.oracleTextLanguage != QStringLiteral("zh") &&
               !looksLikeChinese(record.oracleText);
    };
    const auto textOf = [&](const CardRecord &record) {
        return acceptable(record) ? record.oracleText : QString{};
    };
    const QString key =
        cacheKey(request.name, request.language, request.setCode, request.collectorNumber);
    const QString exact = textOf(m_artCache->exactRecord(key));
    if (!exact.isEmpty())
        return exact;
    const QString printing = textOf(m_artCache->resolvedPrintingMetadata(request));
    if (!printing.isEmpty())
        return printing;
    return textOf(m_artCache->localizedMetadataForName(request));
}

QString CardCatalog::cardTypeLine(const QString &name, const QString &setCode,
                                  const QString &collectorNumber) const
{
    const CardRequest request{
        name.simplified(),
        setCode.toUpper(),
        collectorNumber,
        m_language,
    };
    if (request.name.isEmpty())
        return {};

    const QString cached = cachedTypeLine(request);
    if (!cached.isEmpty())
        return cached;

    const CardRecord catalog = lookupCatalog(request);
    if (!catalog.typeLine.isEmpty())
        return catalog.typeLine;

    if (request.language == QStringLiteral("en"))
        return {};
    const CardRequest english{
        request.name,
        request.setCode,
        request.collectorNumber,
        QStringLiteral("en"),
    };
    const QString englishCached = cachedTypeLine(english);
    if (!englishCached.isEmpty())
        return englishCached;
    return lookupCatalog(english).typeLine;
}

bool CardCatalog::matchesCardQuery(const QString &name, const QString &setCode,
                                   const QString &collectorNumber, const QString &query) const
{
    const QString needle = query.simplified().toLower();
    if (needle.isEmpty())
        return true;

    const QString identity = normalizedCardName(name) + QLatin1Char('|') + setCode.toUpper() +
                             QLatin1Char('|') + collectorNumber;
    QString haystack;
    if (const QString *cachedText = m_cardQueryTextCache.object(identity)) {
        haystack = *cachedText;
    } else {
        const CardRequest chineseRequest{
            name.simplified(),
            setCode.toUpper(),
            collectorNumber,
            QStringLiteral("zh"),
        };
        if (m_catalogBusy || !installed()) {
            haystack = name.toLower();
        } else {
            const CardRecord chinese = lookupCatalog(chineseRequest);
            haystack =
                QStringList{
                    name,
                    chinese.name,
                    chinese.localizedName,
                    chinese.typeLine,
                }
                    .join(QLatin1Char('\n'))
                    .toLower();
            m_cardQueryTextCache.insert(identity, new QString(haystack));
        }
    }
    if (haystack.contains(needle))
        return true;

    struct TypeAlias
    {
        const char *english;
        const char *chinese;
    };
    static constexpr TypeAlias aliases[] = {
        {"land", "地"},
        {"creature", "生物"},
        {"artifact", "神器"},
        {"enchantment", "结界"},
        {"instant", "瞬间"},
        {"sorcery", "法术"},
        {"planeswalker", "鹏洛客"},
        {"battle", "战役"},
    };
    for (const TypeAlias &alias : aliases) {
        const QString englishAlias = QString::fromLatin1(alias.english);
        const QString chineseAlias = QString::fromUtf8(alias.chinese);
        if ((needle == englishAlias || needle == chineseAlias) &&
            (haystack.contains(englishAlias) || haystack.contains(chineseAlias))) {
            return true;
        }
    }
    return false;
}

QString CardCatalog::tokenDisplayName(const QString &name, const QString &setCode,
                                      const QString &collectorNumber) const
{
    return tokenDetails(name, setCode, collectorNumber)
        .value(QStringLiteral("displayName"))
        .toString();
}

QVariantMap CardCatalog::tokenDetails(const QString &name, const QString &setCode,
                                      const QString &collectorNumber) const
{
    const QString canonicalName = name.simplified();
    if (canonicalName.isEmpty())
        return {};
    const CardRequest request{canonicalName, setCode.toUpper(), collectorNumber, m_language};
    const auto cachedMetadata = [this](const CardRequest &query) {
        const CardRecord exact = m_artCache->exactRecord(
            cacheKey(query.name, query.language, query.setCode, query.collectorNumber));
        if (exact.valid() && m_artCache->matchesRequestedFace(query, exact))
            return exact;
        return m_artCache->resolvedPrintingMetadata(query);
    };
    const CardRecord cached = cachedMetadata(request);
    const CardRecord indexed = lookupCatalog(request);
    CardRequest englishRequest = request;
    englishRequest.language = QStringLiteral("en");
    const CardRecord englishCached =
        m_language == QStringLiteral("en") ? cached : cachedMetadata(englishRequest);
    const CardRecord englishIndexed =
        m_language == QStringLiteral("en") ? indexed : lookupCatalog(englishRequest);
    QString displayName = canonicalName;
    QString typeLine;
    QString oracleText;
    if (m_language == QStringLiteral("zh")) {
        for (const CardRecord &candidate : {cached, indexed}) {
            if (displayName == canonicalName && looksLikeChinese(candidate.localizedName))
                displayName = candidate.localizedName;
            if (typeLine.isEmpty() && looksLikeChinese(candidate.typeLine))
                typeLine = candidate.typeLine;
            if (oracleText.isEmpty() && candidate.oracleTextLanguage == QStringLiteral("zh"))
                oracleText = candidate.oracleText;
        }
    }
    for (const CardRecord &candidate : {englishIndexed, englishCached, indexed, cached}) {
        if (typeLine.isEmpty() && !looksLikeChinese(candidate.typeLine))
            typeLine = candidate.typeLine;
        if (oracleText.isEmpty() && candidate.oracleTextLanguage != QStringLiteral("zh"))
            oracleText = candidate.oracleText;
    }
    return {{QStringLiteral("displayName"), displayName},
            {QStringLiteral("typeLine"), typeLine},
            {QStringLiteral("oracleText"), oracleText}};
}

QString CardCatalog::tokenImageSource(const QString &name, const QString &setCode,
                                      const QString &collectorNumber) const
{
    const CardRequest request{
        name.simplified(),
        setCode.toUpper(),
        collectorNumber,
        m_language,
    };
    QString path = resolvedImagePath(request);
    if (path.isEmpty() && request.language != QStringLiteral("en")) {
        CardRequest english = request;
        english.language = QStringLiteral("en");
        // Display already-downloaded English art while Chinese art is fetched,
        // without creating a completed Chinese cache mapping from it.
        path = resolvedImagePath(english);
    }
    return path.isEmpty() ? QString{} : QUrl::fromLocalFile(path).toString();
}

} // namespace hexproof::client
