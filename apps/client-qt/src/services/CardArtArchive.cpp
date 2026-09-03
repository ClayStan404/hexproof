// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "CardArtArchive.h"

#include "CardCatalogCommon.h"
#include "deck/Deck.h"

#include <QBuffer>
#include <QCryptographicHash>
#include <QDataStream>
#include <QDateTime>
#include <QDir>
#include <QDirIterator>
#include <QFile>
#include <QFileInfo>
#include <QImageReader>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QRegularExpression>
#include <QSaveFile>
#include <QUrl>

#include <algorithm>

namespace hexproof::client::cardart {
using namespace catalog_internal;

namespace {

constexpr auto kPackMagic = "HXPART01";
constexpr auto kPackFormat = "hexproof.card-art-pack";
constexpr int kPackFormatVersion = 1;
constexpr qint64 kMaximumManifestBytes = 64 * 1024 * 1024;
constexpr qint64 kMaximumImageBytes = 32 * 1024 * 1024;
constexpr qint64 kMaximumPayloadBytes = 64LL * 1024 * 1024 * 1024;
constexpr int kMaximumEntries = 500'000;
constexpr int kMaximumImages = 100'000;
constexpr int kMaximumImageDimension = 20'000;
constexpr qint64 kMaximumImagePixels = 100'000'000;

struct BlobSpec
{
    QString sha256;
    QString suffix;
    qint64 size = 0;
};

struct BlobInput : BlobSpec
{
    QString path;
};

struct ParsedPack
{
    bool ok = false;
    QString error;
    QJsonObject manifest;
    QList<BlobSpec> blobs;
    qint64 payloadBytes = 0;
    qint64 payloadOffset = 0;
};

struct InventoryGroup
{
    QString setCode;
    QString language;
    int entryCount = 0;
    int missingEntryCount = 0;
    QSet<QString> paths;
    QSet<QString> sources;
};

// Build the canonical positive-cache key for a pack manifest entry object.
// parsePack's duplicate detection and summaryMap's existing-entry checks share
// this so both agree with CardArtCache::key byte for byte.
QString cacheKeyForObject(const QJsonObject &object);
QString damagedPackError()
{
    return QStringLiteral("The selected card art pack is damaged or unsupported.");
}

QString normalizedRoot(const QString &imageRoot)
{
    const QFileInfo info(imageRoot);
    const QString canonical = info.canonicalFilePath();
    return QDir::cleanPath(canonical.isEmpty() ? info.absoluteFilePath() : canonical);
}

bool pathIsInside(const QString &root, const QString &path)
{
    const QString relative = QDir(root).relativeFilePath(QFileInfo(path).absoluteFilePath());
    return relative != QStringLiteral("..") && !relative.startsWith(QStringLiteral("../")) &&
           !QDir::isAbsolutePath(relative);
}

QString managedFilePath(const QString &imageRoot, const QString &candidate)
{
    const QFileInfo info(candidate);
    if (!info.isFile() || info.isSymLink())
        return {};
    const QString root = normalizedRoot(imageRoot);
    const QString canonical = QDir::cleanPath(info.canonicalFilePath());
    if (root.isEmpty() || canonical.isEmpty())
        return {};
    return pathIsInside(root, canonical) ? canonical : QString{};
}

QString imageSource(const QString &imageUrl)
{
    const QString host = QUrl(imageUrl).host().toLower();
    if (host == QStringLiteral("cards.scryfall.io") || host == QStringLiteral("api.scryfall.com") ||
        host.endsWith(QStringLiteral(".scryfall.com"))) {
        return QStringLiteral("scryfall");
    }
    if (host == QStringLiteral("mtgch.com") || host.endsWith(QStringLiteral(".mtgch.com")))
        return QStringLiteral("mtgch");
    return QStringLiteral("other");
}

QString requestLanguage(const QString &cacheKey)
{
    const qsizetype separator = cacheKey.indexOf(QLatin1Char('|'));
    const QString language = separator < 0 ? QString{} : cacheKey.left(separator).toLower();
    return language == QStringLiteral("zh") ? language : QStringLiteral("en");
}

bool matchesSelection(const CardArtCacheEntry &entry, bool selectionOnly, const QString &setCode,
                      const QString &imageLanguage)
{
    if (!selectionOnly)
        return true;
    return entry.record.setCode.compare(setCode, Qt::CaseInsensitive) == 0 &&
           entry.record.imageLanguage.compare(imageLanguage, Qt::CaseInsensitive) == 0;
}

QByteArray readImage(const QString &path, QString *error)
{
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly) || file.size() <= 0 || file.size() > kMaximumImageBytes) {
        if (error)
            *error = QStringLiteral("The card art pack contains invalid image data.");
        return {};
    }
    const QByteArray bytes = file.read(kMaximumImageBytes + 1);
    if (bytes.size() != file.size()) {
        if (error)
            *error = QStringLiteral("The card art pack contains invalid image data.");
        return {};
    }
    return bytes;
}

QString normalizedImageSuffix(const QByteArray &format)
{
    const QByteArray lowered = format.toLower();
    if (lowered == QByteArrayLiteral("jpeg") || lowered == QByteArrayLiteral("jpg"))
        return QStringLiteral("jpg");
    if (lowered == QByteArrayLiteral("png"))
        return QStringLiteral("png");
    if (lowered == QByteArrayLiteral("webp"))
        return QStringLiteral("webp");
    return {};
}

QString validateImage(const QByteArray &bytes, const QString &declaredSuffix = {})
{
    QBuffer buffer;
    buffer.setData(bytes);
    if (!buffer.open(QIODevice::ReadOnly))
        return {};
    QImageReader reader(&buffer);
    reader.setDecideFormatFromContent(true);
    if (!reader.canRead())
        return {};
    const QString suffix = normalizedImageSuffix(reader.format());
    const QSize size = reader.size();
    if (suffix.isEmpty() || !size.isValid() || size.width() > kMaximumImageDimension ||
        size.height() > kMaximumImageDimension ||
        static_cast<qint64>(size.width()) * size.height() > kMaximumImagePixels) {
        return {};
    }
    if (!declaredSuffix.isEmpty() && suffix != declaredSuffix)
        return {};
    if (reader.read().isNull())
        return {};
    return suffix;
}

bool validText(const QString &value, qsizetype maximum, bool required = false)
{
    return value.size() <= maximum && (!required || !value.simplified().isEmpty());
}

bool validKeyText(const QString &value, qsizetype maximum, bool required = false)
{
    return validText(value, maximum, required) && !value.contains(QLatin1Char('|')) &&
           !value.contains(QChar::Null);
}

bool validEntryObject(const QJsonObject &object)
{
    const QString requestLang = object.value(QStringLiteral("requestLanguage")).toString();
    const QString imageLang = object.value(QStringLiteral("imageLanguage")).toString();
    const bool languagesValid =
        (requestLang == QStringLiteral("en") || requestLang == QStringLiteral("zh")) &&
        (imageLang == QStringLiteral("en") || imageLang == QStringLiteral("zh"));
    const QString setCode = object.value(QStringLiteral("setCode")).toString();
    const QString collector = object.value(QStringLiteral("collectorNumber")).toString();
    return languagesValid &&
           validKeyText(object.value(QStringLiteral("requestedName")).toString(), 512, true) &&
           validText(object.value(QStringLiteral("name")).toString(), 512, true) &&
           validText(object.value(QStringLiteral("oracleId")).toString(), 128) &&
           validText(object.value(QStringLiteral("faceName")).toString(), 512) &&
           validText(object.value(QStringLiteral("localizedName")).toString(), 512) &&
           validText(object.value(QStringLiteral("typeLine")).toString(), 2048) &&
           validKeyText(setCode, 16) && validKeyText(collector, 64) &&
           (setCode.isEmpty() == collector.isEmpty()) &&
           validText(object.value(QStringLiteral("illustrationId")).toString(), 128) &&
           validText(object.value(QStringLiteral("imageUrl")).toString(), 4096) &&
           validText(object.value(QStringLiteral("blobSha256")).toString(), 64, true);
}

ParsedPack parsePack(QFile *file)
{
    ParsedPack result;
    if (!file || !file->isOpen() || file->read(8) != QByteArray(kPackMagic, 8)) {
        result.error = damagedPackError();
        return result;
    }

    QDataStream stream(file);
    stream.setByteOrder(QDataStream::BigEndian);
    quint32 manifestSize = 0;
    stream >> manifestSize;
    if (stream.status() != QDataStream::Ok || manifestSize == 0 ||
        manifestSize > kMaximumManifestBytes) {
        result.error = damagedPackError();
        return result;
    }
    const QByteArray manifestBytes = file->read(manifestSize);
    QJsonParseError parseError;
    const QJsonDocument document = QJsonDocument::fromJson(manifestBytes, &parseError);
    if (manifestBytes.size() != manifestSize || parseError.error != QJsonParseError::NoError ||
        !document.isObject()) {
        result.error = damagedPackError();
        return result;
    }
    result.manifest = document.object();
    if (result.manifest.value(QStringLiteral("format")).toString() !=
            QString::fromLatin1(kPackFormat) ||
        result.manifest.value(QStringLiteral("formatVersion")).toInt() != kPackFormatVersion) {
        result.error = damagedPackError();
        return result;
    }

    const QJsonArray entries = result.manifest.value(QStringLiteral("entries")).toArray();
    const QJsonArray blobs = result.manifest.value(QStringLiteral("images")).toArray();
    if (entries.isEmpty() || entries.size() > kMaximumEntries || blobs.isEmpty() ||
        blobs.size() > kMaximumImages) {
        result.error = damagedPackError();
        return result;
    }

    static const QRegularExpression shaPattern(QStringLiteral("^[0-9a-f]{64}$"));
    QSet<QString> hashes;
    for (const QJsonValue &value : blobs) {
        const QJsonObject object = value.toObject();
        BlobSpec blob;
        blob.sha256 = object.value(QStringLiteral("sha256")).toString();
        blob.suffix = object.value(QStringLiteral("format")).toString();
        blob.size = static_cast<qint64>(object.value(QStringLiteral("bytes")).toDouble(-1));
        if (!shaPattern.match(blob.sha256).hasMatch() || hashes.contains(blob.sha256) ||
            (blob.suffix != QStringLiteral("jpg") && blob.suffix != QStringLiteral("png") &&
             blob.suffix != QStringLiteral("webp")) ||
            blob.size <= 0 || blob.size > kMaximumImageBytes ||
            result.payloadBytes > kMaximumPayloadBytes - blob.size) {
            result.error = damagedPackError();
            return result;
        }
        hashes.insert(blob.sha256);
        result.payloadBytes += blob.size;
        result.blobs.append(blob);
    }

    QSet<QString> entryKeys;
    for (const QJsonValue &value : entries) {
        const QJsonObject object = value.toObject();
        const QString blob = object.value(QStringLiteral("blobSha256")).toString();
        if (!validEntryObject(object) || !hashes.contains(blob)) {
            result.error = damagedPackError();
            return result;
        }
        const QString key = cacheKeyForObject(object);
        if (entryKeys.contains(key)) {
            result.error = damagedPackError();
            return result;
        }
        entryKeys.insert(key);
    }

    result.payloadOffset = file->pos();
    if (result.payloadOffset > file->size() ||
        result.payloadBytes != file->size() - result.payloadOffset) {
        result.error = damagedPackError();
        return result;
    }
    result.ok = true;
    return result;
}

QVariantMap summaryMap(const ParsedPack &pack, const QList<CardArtCacheEntry> &existingEntries,
                       const QString &imageRoot)
{
    QSet<QString> existingKeys;
    for (const CardArtCacheEntry &entry : existingEntries) {
        const bool fileExists = imageRoot.isEmpty()
                                    ? QFileInfo::exists(entry.record.imagePath)
                                    : !managedFilePath(imageRoot, entry.record.imagePath).isEmpty();
        if (fileExists)
            existingKeys.insert(entry.cacheKey);
    }
    int existingCount = 0;
    const QJsonArray entries = pack.manifest.value(QStringLiteral("entries")).toArray();
    for (const QJsonValue &value : entries) {
        if (existingKeys.contains(cacheKeyForObject(value.toObject())))
            ++existingCount;
    }
    return {
        {QStringLiteral("ok"), pack.ok},
        {QStringLiteral("error"), pack.error},
        {QStringLiteral("formatVersion"), kPackFormatVersion},
        {QStringLiteral("createdAt"), pack.manifest.value(QStringLiteral("createdAt")).toString()},
        {QStringLiteral("createdBy"), pack.manifest.value(QStringLiteral("createdBy")).toString()},
        {QStringLiteral("entryCount"), entries.size()},
        {QStringLiteral("newEntryCount"), entries.size() - existingCount},
        {QStringLiteral("existingEntryCount"), existingCount},
        {QStringLiteral("imageCount"), pack.blobs.size()},
        {QStringLiteral("bytes"), pack.payloadBytes},
    };
}

QString safeImportedImageUrl(const QString &value)
{
    const QUrl url(value);
    if (!url.isValid() || url.scheme() != QStringLiteral("https"))
        return {};
    return imageSource(value) == QStringLiteral("other") ? QString{} : value;
}

QString cacheKeyForObject(const QJsonObject &object)
{
    return cardArtCacheKey(object.value(QStringLiteral("requestLanguage")).toString(),
                           object.value(QStringLiteral("requestedName")).toString(),
                           object.value(QStringLiteral("setCode")).toString(),
                           object.value(QStringLiteral("collectorNumber")).toString());
}

} // namespace

QVariantMap inventory(const QString &imageRoot, const QList<CardArtCacheEntry> &entries)
{
    QHash<QString, InventoryGroup> groups;
    QSet<QString> referencedPaths;
    int cachedEntryCount = 0;
    int missingEntryCount = 0;

    for (const CardArtCacheEntry &entry : entries) {
        const QString setCode = entry.record.setCode.toUpper();
        const QString language = entry.record.imageLanguage.toLower();
        const QString groupKey = setCode + QChar(0x1f) + language;
        InventoryGroup &group = groups[groupKey];
        group.setCode = setCode;
        group.language = language;
        ++group.entryCount;
        group.sources.insert(imageSource(entry.record.imageUrl));

        const QString path = managedFilePath(imageRoot, entry.record.imagePath);
        if (path.isEmpty()) {
            ++missingEntryCount;
            ++group.missingEntryCount;
            continue;
        }
        ++cachedEntryCount;
        referencedPaths.insert(path);
        group.paths.insert(path);
    }

    int imageCount = 0;
    int orphanCount = 0;
    qint64 totalBytes = 0;
    qint64 orphanBytes = 0;
    QHash<QString, qint64> fileSizes;
    QDirIterator iterator(imageRoot, QDir::Files | QDir::NoSymLinks | QDir::Hidden,
                          QDirIterator::Subdirectories);
    while (iterator.hasNext()) {
        const QString path = managedFilePath(imageRoot, iterator.next());
        if (path.isEmpty())
            continue;
        const qint64 size = QFileInfo(path).size();
        fileSizes.insert(path, size);
        ++imageCount;
        totalBytes += size;
        if (!referencedPaths.contains(path)) {
            ++orphanCount;
            orphanBytes += size;
        }
    }

    QVariantList groupList;
    for (const InventoryGroup &group : groups) {
        qint64 bytes = 0;
        for (const QString &path : group.paths)
            bytes += fileSizes.value(path);
        QStringList sources = group.sources.values();
        std::sort(sources.begin(), sources.end());
        groupList.append(QVariantMap{
            {QStringLiteral("setCode"), group.setCode},
            {QStringLiteral("language"), group.language},
            {QStringLiteral("sources"), sources},
            {QStringLiteral("entryCount"), group.entryCount},
            {QStringLiteral("missingEntryCount"), group.missingEntryCount},
            {QStringLiteral("imageCount"), group.paths.size()},
            {QStringLiteral("bytes"), bytes},
        });
    }
    std::sort(groupList.begin(), groupList.end(), [](const QVariant &left, const QVariant &right) {
        const QVariantMap a = left.toMap();
        const QVariantMap b = right.toMap();
        const int setOrder =
            a.value(QStringLiteral("setCode"))
                .toString()
                .compare(b.value(QStringLiteral("setCode")).toString(), Qt::CaseInsensitive);
        if (setOrder != 0)
            return setOrder < 0;
        return a.value(QStringLiteral("language")).toString() <
               b.value(QStringLiteral("language")).toString();
    });

    return {
        {QStringLiteral("imageCount"), imageCount},
        {QStringLiteral("indexedImageCount"), referencedPaths.size()},
        {QStringLiteral("indexedEntryCount"), entries.size()},
        {QStringLiteral("cachedEntryCount"), cachedEntryCount},
        {QStringLiteral("missingEntryCount"), missingEntryCount},
        {QStringLiteral("orphanCount"), orphanCount},
        {QStringLiteral("totalBytes"), totalBytes},
        {QStringLiteral("orphanBytes"), orphanBytes},
        {QStringLiteral("groups"), groupList},
    };
}

QVariantMap inspectPack(const QString &path, const QList<CardArtCacheEntry> &existingEntries,
                        const QString &imageRoot)
{
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly)) {
        return {{QStringLiteral("ok"), false},
                {QStringLiteral("error"),
                 QStringLiteral("Could not open the selected card art pack.")}};
    }
    return summaryMap(parsePack(&file), existingEntries, imageRoot);
}

OperationResult exportPack(const QString &path, const QString &imageRoot,
                           const QList<CardArtCacheEntry> &entries, bool selectionOnly,
                           const QString &setCode, const QString &imageLanguage)
{
    OperationResult result;
    const QString outputPath = QFileInfo(path).absoluteFilePath();
    const QString root = normalizedRoot(imageRoot);
    if (pathIsInside(root, outputPath)) {
        result.error = QStringLiteral("Choose an export location outside the card image cache.");
        return result;
    }

    QList<CardArtCacheEntry> selected;
    for (const CardArtCacheEntry &entry : entries) {
        if (matchesSelection(entry, selectionOnly, setCode, imageLanguage))
            selected.append(entry);
    }
    std::sort(selected.begin(), selected.end(),
              [](const auto &left, const auto &right) { return left.cacheKey < right.cacheKey; });

    QHash<QString, BlobInput> blobsByHash;
    QJsonArray exportedEntries;
    for (const CardArtCacheEntry &entry : selected) {
        const QString imagePath = managedFilePath(imageRoot, entry.record.imagePath);
        if (imagePath.isEmpty()) {
            ++result.skippedCount;
            continue;
        }
        QString readError;
        const QByteArray bytes = readImage(imagePath, &readError);
        const QString suffix = bytes.isEmpty() ? QString{} : validateImage(bytes);
        if (suffix.isEmpty()) {
            ++result.skippedCount;
            continue;
        }
        const QString sha256 = QString::fromLatin1(
            QCryptographicHash::hash(bytes, QCryptographicHash::Sha256).toHex());
        if (!blobsByHash.contains(sha256)) {
            if (blobsByHash.size() >= kMaximumImages) {
                result.error = QStringLiteral("The card art selection is too large to export.");
                return result;
            }
            BlobInput blob;
            blob.sha256 = sha256;
            blob.suffix = suffix;
            blob.size = bytes.size();
            blob.path = imagePath;
            blobsByHash.insert(sha256, blob);
        }
        if (exportedEntries.size() >= kMaximumEntries) {
            result.error = QStringLiteral("The card art selection is too large to export.");
            return result;
        }
        QJsonObject object = recordToJson(entry.record);
        object.remove(QStringLiteral("imagePath"));
        object.insert(QStringLiteral("requestLanguage"), requestLanguage(entry.cacheKey));
        object.insert(QStringLiteral("blobSha256"), sha256);
        object.insert(QStringLiteral("source"), imageSource(entry.record.imageUrl));
        exportedEntries.append(object);
    }
    if (exportedEntries.isEmpty()) {
        result.error = QStringLiteral("No cached card images match this selection.");
        return result;
    }

    QList<BlobInput> blobs = blobsByHash.values();
    std::sort(blobs.begin(), blobs.end(), [](const BlobInput &left, const BlobInput &right) {
        return left.sha256 < right.sha256;
    });
    QJsonArray images;
    qint64 payloadBytes = 0;
    for (const BlobInput &blob : blobs) {
        if (payloadBytes > kMaximumPayloadBytes - blob.size) {
            result.error = QStringLiteral("The card art selection is too large to export.");
            return result;
        }
        images.append(QJsonObject{
            {QStringLiteral("sha256"), blob.sha256},
            {QStringLiteral("format"), blob.suffix},
            {QStringLiteral("bytes"), static_cast<double>(blob.size)},
        });
        payloadBytes += blob.size;
    }
    const QJsonObject manifest{
        {QStringLiteral("format"), QString::fromLatin1(kPackFormat)},
        {QStringLiteral("formatVersion"), kPackFormatVersion},
        {QStringLiteral("createdAt"), QDateTime::currentDateTimeUtc().toString(Qt::ISODateWithMs)},
        {QStringLiteral("createdBy"), QStringLiteral(HEXPROOF_VERSION)},
        {QStringLiteral("entries"), exportedEntries},
        {QStringLiteral("images"), images},
    };
    const QByteArray manifestBytes = QJsonDocument(manifest).toJson(QJsonDocument::Compact);
    if (manifestBytes.isEmpty() || manifestBytes.size() > kMaximumManifestBytes) {
        result.error = QStringLiteral("The card art selection is too large to export.");
        return result;
    }

    QSaveFile output(outputPath);
    if (!output.open(QIODevice::WriteOnly) || output.write(kPackMagic, 8) != 8) {
        result.error = QStringLiteral("Could not write the card art pack.");
        return result;
    }
    QDataStream stream(&output);
    stream.setByteOrder(QDataStream::BigEndian);
    stream << static_cast<quint32>(manifestBytes.size());
    if (stream.status() != QDataStream::Ok || output.write(manifestBytes) != manifestBytes.size()) {
        output.cancelWriting();
        result.error = QStringLiteral("Could not write the card art pack.");
        return result;
    }
    for (const BlobInput &blob : blobs) {
        QString readError;
        const QByteArray bytes = readImage(blob.path, &readError);
        const QString sha256 = QString::fromLatin1(
            QCryptographicHash::hash(bytes, QCryptographicHash::Sha256).toHex());
        if (bytes.size() != blob.size || sha256 != blob.sha256 ||
            output.write(bytes) != bytes.size()) {
            output.cancelWriting();
            result.error = QStringLiteral("Could not write the card art pack.");
            return result;
        }
    }
    if (!output.commit()) {
        result.error = QStringLiteral("Could not write the card art pack.");
        return result;
    }

    result.ok = true;
    result.entryCount = exportedEntries.size();
    result.imageCount = blobs.size();
    result.bytes = payloadBytes;
    return result;
}

OperationResult importPack(const QString &path, const QString &imageRoot)
{
    OperationResult result;
    QFile input(path);
    if (!input.open(QIODevice::ReadOnly)) {
        result.error = QStringLiteral("Could not open the selected card art pack.");
        return result;
    }
    const ParsedPack pack = parsePack(&input);
    if (!pack.ok) {
        result.error = pack.error;
        return result;
    }
    if (!QDir().mkpath(imageRoot)) {
        result.error = QStringLiteral("Could not write imported card images.");
        return result;
    }

    QHash<QString, QString> importedPaths;
    for (const BlobSpec &blob : pack.blobs) {
        const QByteArray bytes = input.read(blob.size);
        const QString sha256 = QString::fromLatin1(
            QCryptographicHash::hash(bytes, QCryptographicHash::Sha256).toHex());
        if (bytes.size() != blob.size || sha256 != blob.sha256 ||
            validateImage(bytes, blob.suffix).isEmpty()) {
            result.error = QStringLiteral("The card art pack contains invalid image data.");
            return result;
        }
        const QString destination =
            QDir(imageRoot).filePath(blob.sha256 + QLatin1Char('.') + blob.suffix);
        bool needsWrite = true;
        const QFileInfo destinationInfo(destination);
        if (destinationInfo.isSymLink()) {
            result.error = QStringLiteral("Could not write imported card images.");
            return result;
        }
        if (destinationInfo.exists()) {
            QString existingError;
            const QByteArray existing = readImage(destination, &existingError);
            needsWrite = QCryptographicHash::hash(existing, QCryptographicHash::Sha256).toHex() !=
                         blob.sha256.toLatin1();
        }
        if (needsWrite) {
            QSaveFile output(destination);
            if (!output.open(QIODevice::WriteOnly) || output.write(bytes) != bytes.size() ||
                !output.commit()) {
                result.error = QStringLiteral("Could not write imported card images.");
                return result;
            }
        }
        importedPaths.insert(blob.sha256, QFileInfo(destination).absoluteFilePath());
    }

    const QJsonArray entries = pack.manifest.value(QStringLiteral("entries")).toArray();
    QSet<QString> importedKeys;
    for (const QJsonValue &value : entries) {
        const QJsonObject object = value.toObject();
        const QString cacheKey = cacheKeyForObject(object);
        if (cacheKey.isEmpty() || importedKeys.contains(cacheKey)) {
            result.error = damagedPackError();
            result.importedEntries.clear();
            return result;
        }
        importedKeys.insert(cacheKey);
        CardRecord record = recordFromJson(object);
        record.imageUrl = safeImportedImageUrl(record.imageUrl);
        record.imagePath =
            importedPaths.value(object.value(QStringLiteral("blobSha256")).toString());
        record.resolutionVersion = qBound(0, record.resolutionVersion, kCardResolutionVersion);
        if (!record.valid() || record.imagePath.isEmpty()) {
            result.error = damagedPackError();
            result.importedEntries.clear();
            return result;
        }
        result.importedEntries.append({cacheKey, record});
    }

    result.ok = true;
    result.entryCount = result.importedEntries.size();
    result.imageCount = pack.blobs.size();
    result.bytes = pack.payloadBytes;
    return result;
}

OperationResult removeUnreferencedFiles(const QString &imageRoot,
                                        const QSet<QString> &referencedPaths,
                                        const QSet<QString> &candidatePaths, bool removeAllOrphans)
{
    OperationResult result;
    QSet<QString> managedReferences;
    for (const QString &path : referencedPaths) {
        const QString managed = managedFilePath(imageRoot, path);
        if (!managed.isEmpty())
            managedReferences.insert(managed);
    }
    QSet<QString> managedCandidates;
    for (const QString &path : candidatePaths) {
        const QString managed = managedFilePath(imageRoot, path);
        if (!managed.isEmpty())
            managedCandidates.insert(managed);
    }

    int failed = 0;
    QDirIterator iterator(imageRoot, QDir::Files | QDir::NoSymLinks | QDir::Hidden,
                          QDirIterator::Subdirectories);
    while (iterator.hasNext()) {
        const QString path = managedFilePath(imageRoot, iterator.next());
        if (path.isEmpty() || managedReferences.contains(path) ||
            (!removeAllOrphans && !managedCandidates.contains(path))) {
            continue;
        }
        const qint64 size = QFileInfo(path).size();
        if (QFile::remove(path)) {
            ++result.imageCount;
            result.bytes += size;
        } else {
            ++failed;
        }
    }
    result.ok = failed == 0;
    if (failed > 0)
        result.error = QStringLiteral("Could not remove one or more card image files.");
    return result;
}

} // namespace hexproof::client::cardart
