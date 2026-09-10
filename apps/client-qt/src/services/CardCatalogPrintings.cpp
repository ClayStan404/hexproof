// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "CardArtCache.h"
#include "CardCatalog.h"
#include "CardCatalogCommon.h"
#include "CardCatalogQueryInternal.h"
#include "CardImageProvider.h"
#include "CatalogRepository.h"
#include "CatalogStorage.h"
#include "deck/Deck.h"

namespace hexproof::client {
using namespace catalog_internal;

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
    if (m_catalogBusy || !installed())
        return {};
    const QString key = name.simplified().toLower() + QChar(0x1f) + setCode.toUpper() +
                        QChar(0x1f) + collectorNumber;
    if (m_cardFacesCache.contains(key)) {
        clearPrintingsError();
        return m_cardFacesCache.value(key);
    }
    QString error;
    const QVariantList result = guiCatalog().cardFaces(name, setCode, collectorNumber, &error);
    if (!error.isEmpty()) {
        setPrintingsError(error);
        return {};
    }
    clearPrintingsError();
    m_cardFacesCache.insert(key, result);
    return result;
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
