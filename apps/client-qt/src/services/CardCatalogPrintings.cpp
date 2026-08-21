// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "CardArtCache.h"
#include "CardCatalog.h"
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
        !exact.usesSubstituteArt && QFileInfo::exists(exact.imagePath)) {
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
    const QString path = resolvedImagePath(request);
    if (path.isEmpty())
        return {};
    if (!m_cardImageProvider)
        return QUrl::fromLocalFile(path).toString();
    return m_cardImageProvider->sourceForPath(path);
}

QString CardCatalog::resolvedImagePath(const CardRequest &request) const
{
    const QString key =
        cacheKey(request.name, request.language, request.setCode, request.collectorNumber);
    const CardRecord exact = m_artCache->exactRecord(key);
    if (exact.valid() && exact.resolutionVersion >= kCardResolutionVersion &&
        (!exact.reusesLocalArt || request.allowsSubstituteArt(m_artCache->reuseLocalArt())) &&
        QFileInfo::exists(exact.imagePath)) {
        return exact.imagePath;
    }

    const QString path = cachedResolvedPrinting(request).imagePath;
    return QFileInfo::exists(path) ? path : QString{};
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

    const QString key =
        cacheKey(request.name, request.language, request.setCode, request.collectorNumber);
    const CardRecord exact = m_artCache->exactRecord(key);
    if (!exact.typeLine.isEmpty())
        return exact.typeLine;

    const CardRecord cached = cachedResolvedPrinting(request);
    if (!cached.typeLine.isEmpty())
        return cached.typeLine;

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
    const QString englishKey =
        cacheKey(english.name, english.language, english.setCode, english.collectorNumber);
    const CardRecord englishExact = m_artCache->exactRecord(englishKey);
    if (!englishExact.typeLine.isEmpty())
        return englishExact.typeLine;
    const CardRecord englishCached = cachedResolvedPrinting(english);
    if (!englishCached.typeLine.isEmpty())
        return englishCached.typeLine;
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

QString CardCatalog::tokenImageSource(const QString &name, const QString &setCode,
                                      const QString &collectorNumber) const
{
    const CardRequest request{
        name.simplified(),
        setCode.toUpper(),
        collectorNumber,
        QStringLiteral("en"),
    };
    const QString key =
        cacheKey(request.name, request.language, request.setCode, request.collectorNumber);
    const CardRecord exact = m_artCache->exactRecord(key);
    QString path;
    if (exact.valid() && QFileInfo::exists(exact.imagePath))
        path = exact.imagePath;
    else
        path = cachedResolvedPrinting(request).imagePath;
    return path.isEmpty() ? QString{} : QUrl::fromLocalFile(path).toString();
}

} // namespace hexproof::client
