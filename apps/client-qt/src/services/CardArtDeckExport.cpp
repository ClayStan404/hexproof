// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "CardArtArchive.h"

#include "CardCatalogCommon.h"
#include "CatalogRepository.h"

#include <QHash>
#include <QSet>

#include <utility>

namespace hexproof::client::cardart {
using namespace catalog_internal;

namespace {

QString printingKey(const QString &setCode, const QString &collectorNumber)
{
    return setCode.toUpper() + QChar(0x1f) + collectorNumber;
}

struct IndexedEntry
{
    QString requestedName;
    QString setCode;
    QString collectorNumber;
};

struct RequestedPrinting
{
    QList<QSet<QString>> faceEntryKeys;
};

void indexName(QMultiHash<QString, qsizetype> *index, const QString &name, qsizetype entryIndex)
{
    if (!name.isEmpty())
        index->insert(normalizedCardName(name), entryIndex);
}

int matchingFace(const CardArtCacheEntry &entry, const IndexedEntry &identity,
                 const QStringList &faces)
{
    if (faces.size() < 2)
        return 0;
    const QString marker = normalizedCardName(entry.record.faceName);
    if (!marker.isEmpty())
        return faces.indexOf(marker);
    // A legacy unmarked image is only a front. Never export an unmarked
    // front under a reverse-face request key and claim the reverse is cached.
    const int requestedFace = faces.indexOf(identity.requestedName);
    if (requestedFace > 0)
        return -1;
    const QString recordedName = normalizedCardName(entry.record.name);
    return recordedName == faces.first() || recordedName.contains(QStringLiteral(" // ")) ? 0 : -1;
}

} // namespace

QVariantMap DeckExportResult::summary() const
{
    return {
        {QStringLiteral("ok"), operation.ok},
        {QStringLiteral("error"), operation.error},
        {QStringLiteral("entryCount"), operation.entryCount},
        {QStringLiteral("imageCount"), operation.imageCount},
        {QStringLiteral("bytes"), operation.bytes},
        {QStringLiteral("skippedEntryCount"), operation.skippedCount},
        {QStringLiteral("requestedPrintingCount"), requestedPrintingCount},
        {QStringLiteral("requestedFaceCount"), requestedFaceCount},
        {QStringLiteral("missingPrintingCount"), missingPrintingCount},
        {QStringLiteral("missingFaceCount"), missingFaceCount},
        {QStringLiteral("faceCoverageVerified"), faceCoverageVerified},
    };
}

DeckExportResult exportDeckPack(const QString &path, const QString &imageRoot,
                                const QString &databasePath, const QVariantList &cards,
                                const QList<CardArtCacheEntry> &entries)
{
    DeckExportResult result;
    // Index once; a large Cube must not repeatedly scan the entire image cache
    // for each card. Cache keys own requested-printing identity, while records
    // can still describe provider fallback artwork from another printing.
    QMultiHash<QString, qsizetype> entriesByPrinting;
    QMultiHash<QString, qsizetype> entriesByName;
    QList<IndexedEntry> identities;
    identities.reserve(entries.size());
    for (qsizetype i = 0; i < entries.size(); ++i) {
        const CardArtCacheEntry &entry = entries.at(i);
        const QStringList keyParts = entry.cacheKey.split(QLatin1Char('|'));
        IndexedEntry identity;
        identity.requestedName = keyParts.size() >= 2
                                     ? normalizedCardName(keyParts.at(1))
                                     : normalizedCardName(entry.record.requestedName);
        identity.setCode = keyParts.size() == 4 ? keyParts.at(2) : entry.record.setCode;
        identity.collectorNumber =
            keyParts.size() == 4 ? keyParts.at(3) : entry.record.collectorNumber;
        identities.append(identity);
        if (!identity.setCode.isEmpty() && !identity.collectorNumber.isEmpty()) {
            entriesByPrinting.insert(printingKey(identity.setCode, identity.collectorNumber), i);
        }
        indexName(&entriesByName, identity.requestedName, i);
        indexName(&entriesByName, entry.record.requestedName, i);
        indexName(&entriesByName, entry.record.name, i);
        indexName(&entriesByName, entry.record.faceName, i);
        for (const QString &face :
             entry.record.name.split(QStringLiteral(" // "), Qt::SkipEmptyParts))
            indexName(&entriesByName, face, i);
    }

    CatalogRepository repository(databasePath);
    const bool hasCatalog = repository.installed();
    QSet<QString> requestedKeys;
    QSet<QString> selectedKeys;
    QSet<QString> unusableFaceKeys;
    QList<CardArtCacheEntry> selected;
    QList<RequestedPrinting> requestedPrintings;
    for (const QVariant &value : cards) {
        const QVariantMap card = value.toMap();
        const QString name = card.value(QStringLiteral("name")).toString().simplified();
        if (name.isEmpty())
            continue;
        const QString setCode =
            card.value(QStringLiteral("setCode")).toString().trimmed().toUpper();
        const QString collector =
            card.value(QStringLiteral("collectorNumber")).toString().trimmed();
        const bool exactPrinting = !setCode.isEmpty() && !collector.isEmpty();
        const QString requestKey =
            exactPrinting ? QStringLiteral("printing:") + printingKey(setCode, collector)
                          : QStringLiteral("name:") + normalizedCardName(name) + QChar(0x1f) +
                                printingKey(setCode, collector);
        if (requestedKeys.contains(requestKey))
            continue;
        requestedKeys.insert(requestKey);

        QString canonicalName;
        QStringList faces;
        QHash<QString, int> relatedFacesByPrinting;
        if (hasCatalog) {
            QString error;
            const QVariantList cardFaces =
                repository.cardFaces(name, setCode, collector, &error, nullptr, &canonicalName);
            // The installed catalog is optional, but an unreadable installed
            // database must not silently report a front-only pack as complete.
            if (!error.isEmpty()) {
                result.operation.error = QStringLiteral("Could not read card faces.");
                return result;
            }
            for (const QVariant &value : cardFaces) {
                const QVariantMap face = value.toMap();
                const int faceIndex = faces.size();
                faces.append(normalizedCardName(face.value(QStringLiteral("name")).toString()));
                if (!face.value(QStringLiteral("relatedCard")).toBool())
                    continue;
                // Meld results are separate catalog printings, with their own
                // cache keys, rather than marked backs of the front printing.
                const QVariantMap front = cardFaces.first().toMap();
                if ((!setCode.isEmpty() && front.value(QStringLiteral("setCode"))
                                                   .toString()
                                                   .compare(setCode, Qt::CaseInsensitive) != 0) ||
                    (!collector.isEmpty() &&
                     front.value(QStringLiteral("collectorNumber")).toString() != collector))
                    continue;
                const QString relatedSet = face.value(QStringLiteral("setCode")).toString();
                const QString relatedNumber =
                    face.value(QStringLiteral("collectorNumber")).toString();
                if (!relatedSet.isEmpty() && !relatedNumber.isEmpty())
                    relatedFacesByPrinting.insert(printingKey(relatedSet, relatedNumber),
                                                  faceIndex);
            }
        }
        result.faceCoverageVerified = result.faceCoverageVerified && !canonicalName.isEmpty();

        QSet<qsizetype> candidateIndexes;
        const auto addCandidates = [&candidateIndexes](const QList<qsizetype> &indexes) {
            for (const qsizetype index : indexes)
                candidateIndexes.insert(index);
        };
        if (exactPrinting) {
            addCandidates(entriesByPrinting.values(printingKey(setCode, collector)));
        } else {
            addCandidates(entriesByName.values(normalizedCardName(name)));
            if (!canonicalName.isEmpty())
                addCandidates(entriesByName.values(normalizedCardName(canonicalName)));
            for (const QString &face : std::as_const(faces))
                addCandidates(entriesByName.values(face));

            const QString requestedName = normalizedCardName(name);
            const QString family = normalizedCardName(canonicalName);
            QSet<qsizetype> matchingIndexes;
            for (const qsizetype index : std::as_const(candidateIndexes)) {
                const QString candidateName = normalizedCardName(entries.at(index).record.name);
                const bool matchesKnownFamily =
                    !family.isEmpty() && (candidateName == family ||
                                          (faces.size() > 1 && faces.contains(candidateName)));
                // A second characteristic is not itself the playable card:
                // a Swords to Plowshares request must not export an Emeritus
                // prepare image. With no catalog, only the canonical name
                // or an unambiguous first characteristic identifies a family.
                const bool matchesWithoutCatalog =
                    family.isEmpty() &&
                    (candidateName == requestedName ||
                     candidateName.startsWith(requestedName + QStringLiteral(" // ")));
                if (matchesKnownFamily || matchesWithoutCatalog)
                    matchingIndexes.insert(index);
            }
            candidateIndexes = std::move(matchingIndexes);
        }
        for (auto related = relatedFacesByPrinting.cbegin();
             related != relatedFacesByPrinting.cend(); ++related)
            addCandidates(entriesByPrinting.values(related.key()));
        // Without a metadata database, an explicit cached face marker still
        // lets us include both known faces. Do not split prepare/adventure
        // names merely because they contain " // ".
        if (faces.isEmpty() && canonicalName.isEmpty()) {
            for (const qsizetype index : std::as_const(candidateIndexes)) {
                const CardRecord &record = entries.at(index).record;
                const QStringList names =
                    record.name.split(QStringLiteral(" // "), Qt::SkipEmptyParts);
                if (!record.faceName.isEmpty() && names.size() == 2) {
                    for (const QString &face : names)
                        faces.append(normalizedCardName(face));
                    break;
                }
            }
        }
        if (faces.isEmpty())
            faces.append(normalizedCardName(canonicalName.isEmpty() ? name : canonicalName));

        RequestedPrinting printing;
        printing.faceEntryKeys.resize(faces.size());
        for (const qsizetype index : std::as_const(candidateIndexes)) {
            const IndexedEntry &identity = identities.at(index);
            const CardArtCacheEntry &entry = entries.at(index);
            int face = -1;
            const auto related = relatedFacesByPrinting.constFind(
                printingKey(identity.setCode, identity.collectorNumber));
            if (related != relatedFacesByPrinting.cend()) {
                const QString &expectedName = faces.at(related.value());
                const QString marker = normalizedCardName(entry.record.faceName);
                if ((identity.requestedName == expectedName ||
                     normalizedCardName(entry.record.name) == expectedName) &&
                    (marker.isEmpty() || marker == expectedName))
                    face = related.value();
            } else {
                if ((!setCode.isEmpty() &&
                     identity.setCode.compare(setCode, Qt::CaseInsensitive) != 0) ||
                    (!collector.isEmpty() && identity.collectorNumber != collector))
                    continue;
                face = matchingFace(entry, identity, faces);
            }
            if (face < 0) {
                unusableFaceKeys.insert(entry.cacheKey);
                continue;
            }
            printing.faceEntryKeys[face].insert(entry.cacheKey);
            if (!selectedKeys.contains(entry.cacheKey)) {
                selectedKeys.insert(entry.cacheKey);
                CardArtCacheEntry exported = entry;
                // Keep the exported lookup mapping faithful to the request,
                // including caches created before fallback records retained
                // requested printing metadata consistently.
                exported.record.setCode = identity.setCode;
                exported.record.collectorNumber = identity.collectorNumber;
                if (normalizedCardName(exported.record.requestedName) != identity.requestedName)
                    exported.record.requestedName = identity.requestedName;
                if (faces.size() == 1 && canonicalName.contains(QStringLiteral(" // ")) &&
                    normalizedCardName(exported.record.name) == normalizedCardName(canonicalName)) {
                    // Older prepare/adventure mappings marked the second
                    // characteristic as an independent reverse. The catalog
                    // positively identified one image, so clear that stale
                    // marker in the portable snapshot, not the user's cache.
                    exported.record.faceName.clear();
                }
                selected.append(std::move(exported));
            }
        }
        result.requestedFaceCount += faces.size();
        requestedPrintings.append(std::move(printing));
    }
    result.requestedPrintingCount = requestedPrintings.size();
    if (requestedPrintings.isEmpty()) {
        result.operation.error = QStringLiteral("This deck has no cards to export.");
        return result;
    }

    result.operation = exportPack(path, imageRoot, selected, false, {}, {});
    result.operation.skippedCount += unusableFaceKeys.size();
    for (const RequestedPrinting &printing : std::as_const(requestedPrintings)) {
        bool available = false;
        for (const QSet<QString> &keys : printing.faceEntryKeys) {
            bool faceAvailable = false;
            for (const QString &key : keys) {
                if (result.operation.exportedEntryKeys.contains(key)) {
                    faceAvailable = true;
                    break;
                }
            }
            available = available || faceAvailable;
            if (!faceAvailable)
                ++result.missingFaceCount;
        }
        if (!available)
            ++result.missingPrintingCount;
    }
    return result;
}

} // namespace hexproof::client::cardart
