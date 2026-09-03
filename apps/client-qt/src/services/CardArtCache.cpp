// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "CardArtCache.h"

#include "CardCatalogCommon.h"
#include "CatalogStorage.h"
#include "deck/Deck.h"

namespace hexproof::client {
using namespace catalog_internal;

namespace {

constexpr QChar kIndexSeparator = QChar(0x1f);

QString joinedIndexKey(std::initializer_list<QString> parts)
{
    QString result;
    for (const QString &part : parts) {
        if (!result.isEmpty())
            result += kIndexSeparator;
        result += part;
    }
    return result;
}

QString cacheLanguage(const QString &cacheKey)
{
    return cacheKey.left(cacheKey.indexOf(QLatin1Char('|')));
}

void removeIndexEntry(QHash<QString, QSet<QString>> *index, const QString &indexKey,
                      const QString &cacheKey)
{
    auto it = index->find(indexKey);
    if (it == index->end())
        return;
    it->remove(cacheKey);
    if (it->isEmpty())
        index->erase(it);
}

} // namespace

CardArtCache::CardArtCache(const QString &storageRoot)
    : m_imageRoot(QDir(storageRoot).filePath(QStringLiteral("images"))),
      m_metadataPath(QDir(storageRoot).filePath(QStringLiteral("card-cache.json")))
{
    QDir().mkpath(m_imageRoot);
}

void CardArtCache::load()
{
    m_positive.clear();
    m_negative.clear();
    m_printingIndex.clear();
    m_oracleIndex.clear();
    m_canonicalNameIndex.clear();
    m_requestedNameIndex.clear();
    m_faceAuditVersion = 0;
    m_faceRepairNeeded = false;
    m_dirty = false;

    QFile file(m_metadataPath);
    if (!file.open(QIODevice::ReadOnly))
        return;
    QJsonParseError parseError;
    const QJsonDocument document = QJsonDocument::fromJson(file.readAll(), &parseError);
    if (parseError.error != QJsonParseError::NoError || !document.isObject()) {
        // A truncated cache would otherwise look like an empty one and be
        // overwritten by the next save, discarding every resolved image with no
        // trace of why. Preserve the evidence and rebuild instead.
        file.close();
        const QString damagedPath = m_metadataPath + QStringLiteral(".corrupt-") +
                                    QString::number(QDateTime::currentMSecsSinceEpoch());
        if (!QFile::rename(m_metadataPath, damagedPath))
            QFile::remove(m_metadataPath);
        return;
    }
    const QJsonObject root = document.object();
    m_faceAuditVersion = qMax(0, root.value(QStringLiteral("faceAuditVersion")).toInt());
    m_faceRepairNeeded = root.value(QStringLiteral("faceRepairNeeded")).toBool();
    const QJsonObject positive = root.value(QStringLiteral("positive")).toObject();
    for (auto it = positive.begin(); it != positive.end(); ++it)
        m_positive.insert(it.key(), recordFromJson(it.value().toObject()));
    rebuildIndexes();

    // Resolution-policy changes can make an earlier missing result stale.
    if (root.value(QStringLiteral("version")).toInt() == kCardResolutionVersion &&
        root.value(QStringLiteral("negativeVersion")).toInt() == kNegativeCacheVersion) {
        const QJsonObject negative = root.value(QStringLiteral("negative")).toObject();
        for (auto it = negative.begin(); it != negative.end(); ++it) {
            const QDateTime timestamp =
                QDateTime::fromString(it.value().toString(), Qt::ISODateWithMs);
            if (timestamp.isValid())
                m_negative.insert(it.key(), timestamp);
        }
    }
}

bool CardArtCache::save()
{
    QJsonObject positive;
    for (auto it = m_positive.cbegin(); it != m_positive.cend(); ++it)
        positive.insert(it.key(), recordToJson(it.value()));
    QJsonObject negative;
    for (auto it = m_negative.cbegin(); it != m_negative.cend(); ++it)
        negative.insert(it.key(), it.value().toString(Qt::ISODateWithMs));
    const QJsonObject root{
        {QStringLiteral("version"), kCardResolutionVersion},
        {QStringLiteral("negativeVersion"), kNegativeCacheVersion},
        {QStringLiteral("faceAuditVersion"), m_faceAuditVersion},
        {QStringLiteral("faceRepairNeeded"), m_faceRepairNeeded},
        {QStringLiteral("positive"), positive},
        {QStringLiteral("negative"), negative},
    };
    if (!catalogstorage::writeJson(m_metadataPath, root))
        return false;
    m_dirty = false;
    return true;
}

void CardArtCache::setFaceAuditState(int version, bool repairNeeded)
{
    const int normalizedVersion = qMax(0, version);
    if (m_faceAuditVersion == normalizedVersion && m_faceRepairNeeded == repairNeeded)
        return;
    m_faceAuditVersion = normalizedVersion;
    m_faceRepairNeeded = repairNeeded;
    m_dirty = true;
}

QString CardArtCache::key(const QString &name, const QString &language, const QString &setCode,
                          const QString &collectorNumber) const
{
    return cardArtCacheKey(language, name, setCode, collectorNumber);
}

CardRecord CardArtCache::exactRecord(const QString &cacheKey) const
{
    return m_positive.value(cacheKey);
}

bool CardArtCache::matchesRequestedFace(const CardRequest &request, const CardRecord &record) const
{
    const QStringList faces = record.name.split(QStringLiteral(" // "), Qt::SkipEmptyParts);
    if (faces.size() != 2)
        return true;

    const QString requestedName = normalizedCardName(request.name);
    const QString frontName = normalizedCardName(faces.first());
    const QString backName = normalizedCardName(faces.last());
    const QString recordFace = normalizedCardName(record.faceName);
    if (requestedName == frontName)
        return recordFace.isEmpty() || recordFace == frontName;
    if (requestedName == backName)
        return recordFace == backName;

    // Whole-card requests render the front of a transforming or modal card.
    // Do not let a cached back-face record alias the canonical printing key.
    if (requestedName == normalizedCardName(record.name))
        return recordFace.isEmpty() || recordFace == frontName;
    return true;
}

CardRecord CardArtCache::resolvedPrinting(const CardRequest &request) const
{
    if (request.setCode.isEmpty() || request.collectorNumber.isEmpty())
        return {};
    const QString requestedName = normalizedCardName(request.name);
    const QString indexKey = joinedIndexKey(
        {request.language, request.setCode.toUpper(), request.collectorNumber, requestedName});
    const QSet<QString> candidates = m_printingIndex.value(indexKey);
    for (const QString &candidateKey : candidates) {
        const auto it = m_positive.constFind(candidateKey);
        if (it == m_positive.cend() || it->resolutionVersion < kCardResolutionVersion) {
            continue;
        }
        if (!matchesRequestedFace(request, *it))
            continue;
        if (it->reusesLocalArt && !request.allowsSubstituteArt(m_reuseLocalArt))
            continue;
        if (QFileInfo::exists(it->imagePath))
            return *it;
    }
    return {};
}

CardRecord CardArtCache::reusableArt(const CardRequest &request,
                                     const CardRecord &catalogIdentity) const
{
    if (!request.allowsSubstituteArt(m_reuseLocalArt))
        return {};

    const QString requestedName = normalizedCardName(request.name);
    const QString canonicalName = normalizedCardName(catalogIdentity.name);
    const QString oracleId = catalogIdentity.oracleId;
    const bool requestsFace = !canonicalName.isEmpty() && canonicalName != requestedName &&
                              catalogIdentity.name.split(QStringLiteral(" // "), Qt::SkipEmptyParts)
                                  .contains(request.name, Qt::CaseInsensitive);

    QSet<QString> candidates;
    if (!oracleId.isEmpty()) {
        candidates.unite(
            m_oracleIndex.value(joinedIndexKey({request.language, oracleId.toCaseFolded()})));
    }
    const QString identityName = canonicalName.isEmpty() ? requestedName : canonicalName;
    candidates.unite(m_canonicalNameIndex.value(joinedIndexKey({request.language, identityName})));
    if (canonicalName.isEmpty()) {
        candidates.unite(
            m_requestedNameIndex.value(joinedIndexKey({request.language, requestedName})));
    }

    for (const QString &candidateKey : candidates) {
        const auto it = m_positive.constFind(candidateKey);
        if (it == m_positive.cend() || it->resolutionVersion < kCardResolutionVersion ||
            it->imageLanguage != request.language) {
            continue;
        }

        const QString candidateName = normalizedCardName(it->name);
        const QString candidateFace = normalizedCardName(it->faceName);
        const QString candidateRequest = normalizedCardName(it->requestedName);
        const bool oracleMatches = !oracleId.isEmpty() && !it->oracleId.isEmpty() &&
                                   oracleId.compare(it->oracleId, Qt::CaseInsensitive) == 0;
        const bool oracleIdentityAvailable = !oracleId.isEmpty() && !it->oracleId.isEmpty();
        const bool nameMatches = (!canonicalName.isEmpty() && candidateName == canonicalName) ||
                                 (canonicalName.isEmpty() && (candidateName == requestedName ||
                                                              candidateRequest == requestedName));
        if ((oracleIdentityAvailable && !oracleMatches) ||
            (!oracleIdentityAvailable && !nameMatches)) {
            continue;
        }

        if (requestsFace) {
            const QStringList candidateFaces = candidateName.split(QStringLiteral(" // "));
            const bool inferredFront = candidateFace.isEmpty() && candidateFaces.size() == 2 &&
                                       normalizedCardName(candidateFaces.first()) == requestedName;
            const bool standaloneFace =
                candidateFaces.size() == 1 && candidateName == requestedName;
            if (candidateFace != requestedName && !inferredFront && !standaloneFace) {
                continue;
            }
        } else {
            if (!candidateFace.isEmpty())
                continue;
            if (candidateName.contains(QStringLiteral(" // ")) &&
                candidateRequest != candidateName && candidateRequest != requestedName) {
                continue;
            }
        }
        if (!QFileInfo::exists(it->imagePath))
            continue;
        return *it;
    }
    return {};
}

CardRecord CardArtCache::substituteRecord(const CardRequest &request,
                                          const CardRecord &catalogIdentity,
                                          const CardRecord &cachedArt) const
{
    CardRecord substitute = cachedArt;
    substitute.requestedName = request.name;
    if (!request.setCode.isEmpty() && !request.collectorNumber.isEmpty()) {
        substitute.setCode = request.setCode;
        substitute.collectorNumber = request.collectorNumber;
        if (catalogIdentity.valid()) {
            substitute.name = catalogIdentity.name;
            substitute.oracleId = catalogIdentity.oracleId;
            substitute.localizedName = catalogIdentity.localizedName;
            substitute.typeLine = catalogIdentity.typeLine;
        }
    }
    substitute.resolutionVersion = kCardResolutionVersion;
    substitute.usesSubstituteArt = true;
    substitute.reusesLocalArt = true;
    return substitute;
}

QString CardArtCache::imagePath(const QString &name, const QString &imageUrl,
                                const QString &language) const
{
    const QByteArray digest =
        QCryptographicHash::hash(
            (language + QLatin1Char('|') + normalizedCardName(name) + QLatin1Char('|') + imageUrl)
                .toUtf8(),
            QCryptographicHash::Sha256)
            .toHex();
    QString suffix = QFileInfo(QUrl(imageUrl).path()).suffix().toLower();
    if (suffix != QStringLiteral("png") && suffix != QStringLiteral("webp"))
        suffix = QStringLiteral("jpg");
    return QDir(m_imageRoot).filePath(QString::fromLatin1(digest) + QLatin1Char('.') + suffix);
}

void CardArtCache::rememberSuccess(const QString &cacheKey, const CardRecord &record)
{
    const auto existing = m_positive.constFind(cacheKey);
    if (existing != m_positive.cend())
        removeFromIndexes(cacheKey, *existing);
    m_positive.insert(cacheKey, record);
    addToIndexes(cacheKey, record);
    m_negative.remove(cacheKey);
    m_dirty = true;
}

void CardArtCache::rebuildIndexes()
{
    m_printingIndex.clear();
    m_oracleIndex.clear();
    m_canonicalNameIndex.clear();
    m_requestedNameIndex.clear();
    for (auto it = m_positive.cbegin(); it != m_positive.cend(); ++it)
        addToIndexes(it.key(), it.value());
}

void CardArtCache::addToIndexes(const QString &cacheKey, const CardRecord &record)
{
    const QString language = cacheLanguage(cacheKey);
    const QString requestedName = normalizedCardName(record.requestedName);
    const QString canonicalName = normalizedCardName(record.name);
    QString inferredFaceName = normalizedCardName(record.faceName);
    if (inferredFaceName.isEmpty()) {
        const QStringList faces = record.name.split(QStringLiteral(" // "), Qt::SkipEmptyParts);
        if (faces.size() == 2)
            inferredFaceName = normalizedCardName(faces.first());
    }
    if (!record.setCode.isEmpty() && !record.collectorNumber.isEmpty()) {
        const QString printingPrefix =
            joinedIndexKey({language, record.setCode.toUpper(), record.collectorNumber});
        if (!requestedName.isEmpty())
            m_printingIndex[printingPrefix + kIndexSeparator + requestedName].insert(cacheKey);
        if (!canonicalName.isEmpty())
            m_printingIndex[printingPrefix + kIndexSeparator + canonicalName].insert(cacheKey);
        if (!inferredFaceName.isEmpty())
            m_printingIndex[printingPrefix + kIndexSeparator + inferredFaceName].insert(cacheKey);
    }
    if (!record.imageLanguage.isEmpty()) {
        if (!record.oracleId.isEmpty()) {
            m_oracleIndex[joinedIndexKey({record.imageLanguage, record.oracleId.toCaseFolded()})]
                .insert(cacheKey);
        }
        if (!canonicalName.isEmpty()) {
            m_canonicalNameIndex[joinedIndexKey({record.imageLanguage, canonicalName})].insert(
                cacheKey);
        }
        if (!requestedName.isEmpty()) {
            m_requestedNameIndex[joinedIndexKey({record.imageLanguage, requestedName})].insert(
                cacheKey);
        }
    }
}

void CardArtCache::removeFromIndexes(const QString &cacheKey, const CardRecord &record)
{
    const QString language = cacheLanguage(cacheKey);
    const QString requestedName = normalizedCardName(record.requestedName);
    const QString canonicalName = normalizedCardName(record.name);
    QString inferredFaceName = normalizedCardName(record.faceName);
    if (inferredFaceName.isEmpty()) {
        const QStringList faces = record.name.split(QStringLiteral(" // "), Qt::SkipEmptyParts);
        if (faces.size() == 2)
            inferredFaceName = normalizedCardName(faces.first());
    }
    if (!record.setCode.isEmpty() && !record.collectorNumber.isEmpty()) {
        const QString printingPrefix =
            joinedIndexKey({language, record.setCode.toUpper(), record.collectorNumber});
        if (!requestedName.isEmpty()) {
            removeIndexEntry(&m_printingIndex, printingPrefix + kIndexSeparator + requestedName,
                             cacheKey);
        }
        if (!canonicalName.isEmpty()) {
            removeIndexEntry(&m_printingIndex, printingPrefix + kIndexSeparator + canonicalName,
                             cacheKey);
        }
        if (!inferredFaceName.isEmpty()) {
            removeIndexEntry(&m_printingIndex, printingPrefix + kIndexSeparator + inferredFaceName,
                             cacheKey);
        }
    }
    if (!record.imageLanguage.isEmpty()) {
        if (!record.oracleId.isEmpty()) {
            removeIndexEntry(&m_oracleIndex,
                             joinedIndexKey({record.imageLanguage, record.oracleId.toCaseFolded()}),
                             cacheKey);
        }
        if (!canonicalName.isEmpty()) {
            removeIndexEntry(&m_canonicalNameIndex,
                             joinedIndexKey({record.imageLanguage, canonicalName}), cacheKey);
        }
        if (!requestedName.isEmpty()) {
            removeIndexEntry(&m_requestedNameIndex,
                             joinedIndexKey({record.imageLanguage, requestedName}), cacheKey);
        }
    }
}

void CardArtCache::rememberFailure(const QString &cacheKey, const QDateTime &timestamp)
{
    m_negative.insert(cacheKey, timestamp);
    m_dirty = true;
}

bool CardArtCache::forgetFailure(const QString &cacheKey)
{
    if (m_negative.remove(cacheKey) == 0)
        return false;
    m_dirty = true;
    return true;
}

bool CardArtCache::failedRecently(const QString &cacheKey, const QDateTime &now,
                                  qint64 maximumAgeSeconds) const
{
    const auto failure = m_negative.constFind(cacheKey);
    if (failure == m_negative.cend() || !failure->isValid())
        return false;
    const qint64 age = failure->secsTo(now);
    return age >= 0 && age < maximumAgeSeconds;
}

QList<CardArtCacheEntry> CardArtCache::entries() const
{
    QList<CardArtCacheEntry> result;
    result.reserve(m_positive.size());
    for (auto it = m_positive.cbegin(); it != m_positive.cend(); ++it)
        result.append({it.key(), it.value()});
    return result;
}

QSet<QString> CardArtCache::referencedImagePaths() const
{
    QSet<QString> paths;
    for (const CardRecord &record : m_positive) {
        if (!record.imagePath.isEmpty())
            paths.insert(QFileInfo(record.imagePath).absoluteFilePath());
    }
    return paths;
}

QList<CardArtCacheEntry> CardArtCache::removeEntries(bool selectionOnly, const QString &setCode,
                                                     const QString &imageLanguage)
{
    const QString normalizedSet = setCode.toUpper();
    const QString normalizedLanguage = imageLanguage.toLower();
    QList<CardArtCacheEntry> removed;
    for (auto it = m_positive.begin(); it != m_positive.end();) {
        const CardRecord &record = it.value();
        const bool matches =
            !selectionOnly ||
            (record.setCode.compare(normalizedSet, Qt::CaseInsensitive) == 0 &&
             record.imageLanguage.compare(normalizedLanguage, Qt::CaseInsensitive) == 0);
        if (!matches) {
            ++it;
            continue;
        }
        const QString cacheKey = it.key();
        const CardRecord removedRecord = it.value();
        removeFromIndexes(cacheKey, removedRecord);
        it = m_positive.erase(it);
        removed.append({cacheKey, removedRecord});
    }
    if (!removed.isEmpty()) {
        m_negative.clear();
        m_dirty = true;
    }
    return removed;
}

void CardArtCache::replaceEntries(const QList<CardArtCacheEntry> &entries)
{
    m_positive.clear();
    for (const CardArtCacheEntry &entry : entries) {
        if (!entry.cacheKey.isEmpty())
            m_positive.insert(entry.cacheKey, entry.record);
    }
    rebuildIndexes();
    m_dirty = true;
}

} // namespace hexproof::client
