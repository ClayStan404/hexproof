// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "CardArtAudit.h"

#include "CardCatalogCommon.h"
#include "CatalogRepository.h"
#include "deck/Deck.h"

#include <QDir>
#include <QFileInfo>
#include <QHash>
#include <QSet>

#include <utility>

namespace hexproof::client::cardart {
using namespace catalog_internal;

namespace {

QString cacheKey(const QString &name, const QString &language, const QString &setCode,
                 const QString &collectorNumber)
{
    QString result = language + QLatin1Char('|') + normalizedCardName(name);
    if (!setCode.isEmpty() && !collectorNumber.isEmpty())
        result += QLatin1Char('|') + setCode.toUpper() + QLatin1Char('|') + collectorNumber;
    return result;
}

QString requestLanguage(const QString &key)
{
    const qsizetype separator = key.indexOf(QLatin1Char('|'));
    return separator < 0 ? QString{} : key.left(separator);
}

QString printingKey(const QString &language, const QString &setCode, const QString &collectorNumber)
{
    return language + QChar(0x1f) + setCode.toUpper() + QChar(0x1f) + collectorNumber;
}

QString managedFilePath(const QString &imageRoot, const QString &candidate)
{
    const QFileInfo rootInfo(imageRoot);
    const QFileInfo fileInfo(candidate);
    if (!fileInfo.isFile() || fileInfo.isSymLink())
        return {};
    const QString root = QDir::cleanPath(rootInfo.canonicalFilePath());
    const QString file = QDir::cleanPath(fileInfo.canonicalFilePath());
    if (root.isEmpty() || file.isEmpty())
        return {};
    const QString relative = QDir(root).relativeFilePath(file);
    if (relative == QStringLiteral("..") || relative.startsWith(QStringLiteral("../")) ||
        QDir::isAbsolutePath(relative)) {
        return {};
    }
    return file;
}

bool matchesRequestedFace(const CardRequest &request, const CardRecord &record)
{
    const QStringList faces = record.name.split(QStringLiteral(" // "), Qt::SkipEmptyParts);
    if (faces.size() != 2)
        return true;

    const QString requestedName = normalizedCardName(request.name);
    const QString frontName = normalizedCardName(faces.first());
    const QString backName = normalizedCardName(faces.last());
    const QString recordFace = normalizedCardName(record.faceName);
    if (requestedName == frontName)
        return recordFace == frontName;
    if (requestedName == backName)
        return recordFace == backName;
    if (requestedName == normalizedCardName(record.name))
        return recordFace.isEmpty() || recordFace == frontName;
    return true;
}

bool reusableRecord(const CardRequest &request, const CardRecord &record, const QString &imageRoot,
                    bool reuseLocalArt)
{
    return record.valid() && record.resolutionVersion >= kCardResolutionVersion &&
           (!record.reusesLocalArt || request.allowsSubstituteArt(reuseLocalArt)) &&
           !managedFilePath(imageRoot, record.imagePath).isEmpty();
}

bool usableRecord(const CardRequest &request, const CardRecord &record, const QString &imageRoot,
                  bool reuseLocalArt)
{
    return reusableRecord(request, record, imageRoot, reuseLocalArt) &&
           matchesRequestedFace(request, record);
}

QVariantMap requestMap(const CardRequest &request)
{
    return {
        {QStringLiteral("name"), request.name},
        {QStringLiteral("setCode"), request.setCode},
        {QStringLiteral("collectorNumber"), request.collectorNumber},
    };
}

} // namespace

QVariantMap AuditResult::summary() const
{
    return {
        {QStringLiteral("ok"), ok},
        {QStringLiteral("error"), error},
        {QStringLiteral("printingCount"), printingCount},
        {QStringLiteral("faceCount"), faceCount},
        {QStringLiteral("missingFaceCount"), missingFaceCount},
        {QStringLiteral("repairableEntryCount"), repairableEntryCount},
        {QStringLiteral("repairNeeded"), repairNeeded()},
    };
}

AuditResult auditDeckArt(const QString &databasePath, const QString &imageRoot,
                         const QString &language, bool reuseLocalArt, const QVariantList &cards,
                         const QList<CardArtCacheEntry> &entries)
{
    AuditResult result;
    CatalogRepository repository(databasePath);
    if (!repository.installed()) {
        result.error = QStringLiteral("Install the card database before checking card art.");
        return result;
    }

    QHash<QString, CardRecord> recordsByKey;
    QMultiHash<QString, CardArtCacheEntry> recordsByPrinting;
    for (const CardArtCacheEntry &entry : entries) {
        recordsByKey.insert(entry.cacheKey, entry.record);
        if (!entry.record.setCode.isEmpty() && !entry.record.collectorNumber.isEmpty()) {
            recordsByPrinting.insert(printingKey(requestLanguage(entry.cacheKey),
                                                 entry.record.setCode,
                                                 entry.record.collectorNumber),
                                     entry);
        }
    }

    QSet<QString> seenPrintings;
    QSet<QString> seenRequests;
    for (const QVariant &value : cards) {
        const QVariantMap map = value.toMap();
        const QString name = map.value(QStringLiteral("name")).toString().simplified();
        const QString setCode = map.value(QStringLiteral("setCode")).toString().toUpper();
        const QString collectorNumber = map.value(QStringLiteral("collectorNumber")).toString();
        const QString baseKey =
            normalizedCardName(name) + QChar(0x1f) + setCode + QChar(0x1f) + collectorNumber;
        if (name.isEmpty() || seenPrintings.contains(baseKey))
            continue;
        seenPrintings.insert(baseKey);
        if (!setCode.isEmpty() && !collectorNumber.isEmpty() &&
            !recordsByPrinting.contains(printingKey(language, setCode, collectorNumber)) &&
            !recordsByKey.contains(cacheKey(name, language, setCode, collectorNumber))) {
            continue;
        }
        QString error;
        QString canonicalName;
        const QVariantList faces =
            repository.cardFaces(name, setCode, collectorNumber, &error, nullptr, &canonicalName);
        if (!error.isEmpty()) {
            result.error = error;
            return result;
        }
        if (canonicalName.isEmpty())
            continue;

        QVariantList requests;
        if (faces.size() >= 2) {
            for (const QVariant &faceValue : faces) {
                QVariantMap request = map;
                request.insert(QStringLiteral("name"),
                               faceValue.toMap().value(QStringLiteral("name")));
                requests.append(request);
            }
        } else {
            requests.append(map);
        }

        const QString resolvedName = canonicalName.isEmpty() ? name : canonicalName;
        if (faces.size() < 2 && !resolvedName.contains(QStringLiteral(" // ")))
            continue;

        QList<CardArtCacheEntry> printingCandidates;
        if (!setCode.isEmpty() && !collectorNumber.isEmpty()) {
            printingCandidates =
                recordsByPrinting.values(printingKey(language, setCode, collectorNumber));
        }
        const QString wholeCardKey = cacheKey(resolvedName, language, setCode, collectorNumber);
        if (recordsByKey.contains(wholeCardKey))
            printingCandidates.append({wholeCardKey, recordsByKey.value(wholeCardKey)});
        for (const QVariant &requestValue : requests) {
            const QString faceName =
                requestValue.toMap().value(QStringLiteral("name")).toString().simplified();
            const QString faceKey = cacheKey(faceName, language, setCode, collectorNumber);
            if (recordsByKey.contains(faceKey))
                printingCandidates.append({faceKey, recordsByKey.value(faceKey)});
        }
        if (printingCandidates.isEmpty())
            continue;
        ++result.printingCount;

        for (const QVariant &requestValue : requests) {
            const QVariantMap requestData = requestValue.toMap();
            CardRequest request{
                requestData.value(QStringLiteral("name")).toString().simplified(),
                setCode,
                collectorNumber,
                language,
            };
            if (request.name.isEmpty())
                continue;
            const QString desiredKey = cacheKey(request.name, language, setCode, collectorNumber);
            if (seenRequests.contains(desiredKey))
                continue;
            seenRequests.insert(desiredKey);
            ++result.faceCount;

            const CardRecord exact = recordsByKey.value(desiredKey);
            if (usableRecord(request, exact, imageRoot, reuseLocalArt))
                continue;

            CardRecord repaired;
            for (const CardArtCacheEntry &candidate : std::as_const(printingCandidates)) {
                if (!usableRecord(request, candidate.record, imageRoot, reuseLocalArt))
                    continue;
                repaired = candidate.record;
                repaired.requestedName = request.name;
                repaired.setCode = setCode;
                repaired.collectorNumber = collectorNumber;
                break;
            }

            const QString frontName =
                faces.isEmpty()
                    ? QString{}
                    : faces.first().toMap().value(QStringLiteral("name")).toString().simplified();
            const bool frontFaceRequest =
                faces.size() >= 2 && request.name.compare(frontName, Qt::CaseInsensitive) == 0;
            if (!repaired.valid() && frontFaceRequest) {
                for (const CardArtCacheEntry &candidate : std::as_const(printingCandidates)) {
                    if (!reusableRecord(request, candidate.record, imageRoot, reuseLocalArt) ||
                        !candidate.record.faceName.isEmpty() ||
                        normalizedCardName(candidate.record.name) !=
                            normalizedCardName(resolvedName)) {
                        continue;
                    }
                    repaired = candidate.record;
                    repaired.requestedName = request.name;
                    repaired.faceName = frontName;
                    repaired.setCode = setCode.isEmpty() ? repaired.setCode : setCode;
                    repaired.collectorNumber =
                        collectorNumber.isEmpty() ? repaired.collectorNumber : collectorNumber;
                    break;
                }
            }

            const bool wholeCardRequest =
                faces.size() < 2 &&
                normalizedCardName(request.name) == normalizedCardName(resolvedName) &&
                resolvedName.contains(QStringLiteral(" // "));
            if (!repaired.valid() && wholeCardRequest && exact.valid() &&
                exact.resolutionVersion >= kCardResolutionVersion &&
                normalizedCardName(exact.name) == normalizedCardName(resolvedName) &&
                !exact.faceName.isEmpty() &&
                !managedFilePath(imageRoot, exact.imagePath).isEmpty()) {
                repaired = exact;
                repaired.requestedName = request.name;
                repaired.faceName.clear();
            }

            if (repaired.valid() && usableRecord(request, repaired, imageRoot, reuseLocalArt)) {
                result.repairedEntries.append({desiredKey, repaired});
                ++result.repairableEntryCount;
                continue;
            }

            result.missingRequests.append(requestMap(request));
            ++result.missingFaceCount;
        }
    }

    result.ok = true;
    return result;
}

} // namespace hexproof::client::cardart
