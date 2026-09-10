// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "CustomCardArtInternal.h"

#include "CatalogRepository.h"

#include <QCryptographicHash>
#include <QDataStream>
#include <QDir>
#include <QDirIterator>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QRegularExpression>
#include <QSaveFile>
#include <QSet>
#include <QTemporaryDir>
#include <QUrl>

#include <algorithm>

namespace hexproof::client::customart {
using namespace Qt::StringLiterals;

namespace {

constexpr auto kPackMagic = "HXPCST01";

QString safeSource(const QString &directory, const QString &relative)
{
    if (relative.isEmpty() || QDir::isAbsolutePath(relative) ||
        relative.contains(QLatin1Char('\\')))
        return {};
    const QString clean = QDir::cleanPath(relative);
    if (clean == u".."_s || clean.startsWith(u"../"_s))
        return {};
    const QFileInfo source(QDir(directory).filePath(clean));
    const QString root = QFileInfo(directory).canonicalFilePath();
    if (!source.isFile() || source.isSymLink() || root.isEmpty() ||
        !source.canonicalFilePath().startsWith(root + QLatin1Char('/')))
        return {};
    return source.canonicalFilePath();
}

QVariantMap imageEntry(QVariantMap binding, const ImageInfo &image)
{
    binding.insert(u"id"_s, bindingId(binding));
    binding.insert(u"fileName"_s, image.fileName);
    binding.insert(u"sha256"_s, image.sha256);
    binding.insert(u"format"_s, image.format);
    binding.insert(u"bytes"_s, image.bytes);
    return binding;
}

QSet<QString> existingIds(const QVariantList &entries)
{
    QSet<QString> result;
    for (const QVariant &value : entries)
        result.insert(value.toMap().value(u"id"_s).toString());
    return result;
}

QVariantMap filenameBinding(const QString &relative, CatalogRepository *repository, QString *error)
{
    static const QRegularExpression pattern(
        u"^([A-Za-z0-9_-]{1,16})/([^/]+)\\.(front|back|face-[1-9][0-9]*)\\.(jpg|jpeg|png|webp)$"_s,
        QRegularExpression::CaseInsensitiveOption);
    const auto match = pattern.match(relative);
    if (!match.hasMatch()) {
        *error = u"Use SET/collector.front|back|face-N.jpg, or an explicit custom-art-map.json."_s;
        return {};
    }
    if (!repository->installed()) {
        *error = u"Install the card database or provide an explicit custom-art-map.json."_s;
        return {};
    }
    const QString setCode = match.captured(1).toUpper();
    const QString collector = QUrl::fromPercentEncoding(match.captured(2).toUtf8());
    const QString slot = match.captured(3).toLower();
    const int faceIndex =
        slot == u"front"_s ? 0 : (slot == u"back"_s ? 1 : slot.mid(5).toInt() - 1);
    const CardRecord record = repository->lookup({{}, setCode, collector, u"en"_s});
    if (!record.valid()) {
        *error = u"The filename does not identify an installed card printing."_s;
        return {};
    }
    QString layout;
    QString canonicalName;
    const QVariantList faces =
        repository->cardFaces(record.name, setCode, collector, error, &layout, &canonicalName);
    if (!error->isEmpty())
        return {};
    if (faceIndex < 0 || (faces.isEmpty() ? faceIndex != 0 : faceIndex >= faces.size())) {
        *error = u"The selected printing does not have this independent image face."_s;
        return {};
    }
    QVariantMap binding{{u"scope"_s, u"printing"_s},       {u"name"_s, record.name},
                        {u"faceName"_s, QString{}},        {u"setCode"_s, setCode},
                        {u"collectorNumber"_s, collector}, {u"oracleId"_s, record.oracleId}};
    if (faceIndex > 0) {
        const QVariantMap face = faces.at(faceIndex).toMap();
        const QString faceSet = face.value(u"setCode"_s, setCode).toString();
        const QString faceCollector = face.value(u"collectorNumber"_s, collector).toString();
        if (faceSet.compare(setCode, Qt::CaseInsensitive) != 0 || faceCollector != collector) {
            // Meld results have an independent printing identity. Their image
            // is not a made-up reverse alias of either component.
            const CardRecord result = repository->lookup(
                {face.value(u"name"_s).toString(), faceSet, faceCollector, u"en"_s});
            if (!result.valid()) {
                *error = u"The related image face is not present in the installed catalog."_s;
                return {};
            }
            binding.insert(u"name"_s, result.name);
            binding.insert(u"oracleId"_s, result.oracleId);
            binding.insert(u"setCode"_s, faceSet);
            binding.insert(u"collectorNumber"_s, faceCollector);
        } else {
            binding.insert(u"faceName"_s, face.value(u"name"_s));
        }
    }
    return normalizeBinding(binding, error);
}

bool validateCatalogBinding(const QVariantMap &binding, CatalogRepository *repository,
                            QString *error)
{
    const bool cardWide = binding.value(u"scope"_s).toString() == u"card"_s;
    if (!repository->installed()) {
        if (cardWide)
            *error = u"Install the card database before applying card-wide custom artwork."_s;
        return !cardWide;
    }
    const QString name = binding.value(u"name"_s).toString();
    const QString setCode = binding.value(u"setCode"_s).toString();
    const QString collector = binding.value(u"collectorNumber"_s).toString();
    const CardRecord record = repository->lookup({name, setCode, collector, u"en"_s});
    // Explicit manifests remain usable with custom/older catalog entries not
    // installed locally, but cannot contradict an identity that is installed.
    if (!record.valid()) {
        if (cardWide)
            *error = u"Card-wide custom artwork requires a verified Oracle card identity."_s;
        return !cardWide;
    }
    const QString oracle = binding.value(u"oracleId"_s).toString();
    if ((cardWide && record.oracleId.isEmpty()) ||
        normalizedName(record.name) != normalizedName(name) ||
        (!oracle.isEmpty() && !record.oracleId.isEmpty() &&
         oracle.compare(record.oracleId, Qt::CaseInsensitive) != 0)) {
        *error = u"The manifest card identity conflicts with the installed catalog."_s;
        return false;
    }
    const QString requestedFace = binding.value(u"faceName"_s).toString();
    if (requestedFace.isEmpty())
        return true;
    QString faceError;
    const QVariantList faces = repository->cardFaces(record.name, setCode, collector, &faceError);
    for (qsizetype i = 1; i < faces.size(); ++i) {
        const auto face = faces.at(i).toMap();
        if (normalizedName(face.value(u"name"_s).toString()) == normalizedName(requestedFace) &&
            face.value(u"setCode"_s, setCode).toString().compare(setCode, Qt::CaseInsensitive) ==
                0 &&
            face.value(u"collectorNumber"_s, collector).toString() == collector)
            return true;
    }
    *error = u"The manifest does not identify an independent back face of this printing."_s;
    return false;
}

void finishPreview(WorkResult *result, const QString &kind, QVariantList rows,
                   const QVariantList &existing)
{
    const QSet<QString> conflicts = existingIds(existing);
    int valid = 0;
    int conflictCount = 0;
    int errors = 0;
    QHash<QString, int> counts;
    for (const QVariant &value : rows) {
        const auto row = value.toMap();
        if (row.value(u"valid"_s).toBool())
            ++counts[row.value(u"id"_s).toString()];
    }
    for (QVariant &value : rows) {
        auto row = value.toMap();
        const QString id = row.value(u"id"_s).toString();
        if (row.value(u"valid"_s).toBool() && counts.value(id) > 1) {
            row.insert(u"valid"_s, false);
            row.insert(
                u"error"_s,
                u"More than one source image maps to this card face; choose an explicit mapping."_s);
        }
        if (row.value(u"valid"_s).toBool()) {
            ++valid;
            const bool conflict = conflicts.contains(id);
            row.insert(u"conflict"_s, conflict);
            if (conflict)
                ++conflictCount;
            result->pendingEntries.append(portableEntry(row));
        } else {
            ++errors;
            row.insert(u"conflict"_s, false);
        }
        value = row;
    }
    result->ok = true;
    result->preview = {{u"kind"_s, kind},
                       {u"rows"_s, rows},
                       {u"validCount"_s, valid},
                       {u"errorCount"_s, errors},
                       {u"conflictCount"_s, conflictCount}};
}

bool inside(const QString &root, const QString &path)
{
    const QString canonical = QFileInfo(root).canonicalFilePath();
    const QString parent = QFileInfo(path).canonicalPath();
    return !canonical.isEmpty() &&
           (parent == canonical || parent.startsWith(canonical + QLatin1Char('/')));
}

} // namespace

bool validateBindingForCatalog(const QVariantMap &binding, const QString &databasePath,
                               QString *error)
{
    CatalogRepository repository(databasePath);
    return validateCatalogBinding(binding, &repository, error);
}

WorkResult inspectDirectory(const QString &directory, const QString &databasePath,
                            const QVariantList &existing, std::shared_ptr<QTemporaryDir> staging)
{
    WorkResult result;
    result.staging = staging;
    result.preview.insert(u"kind"_s, u"directory"_s);
    if (!staging || !staging->isValid()) {
        result.error = u"Could not create a private custom artwork preview."_s;
        return result;
    }
    CatalogRepository repository(databasePath);
    QVariantList specifications;
    const QString manifestPath = QDir(directory).filePath(u"custom-art-map.json"_s);
    const bool hasManifest = QFileInfo::exists(manifestPath);
    if (hasManifest) {
        QFile manifest(manifestPath);
        if (!QFileInfo(manifestPath).isFile() || QFileInfo(manifestPath).isSymLink() ||
            manifest.size() > kMaximumManifestBytes || !manifest.open(QIODevice::ReadOnly)) {
            result.error = u"Could not read custom-art-map.json."_s;
            return result;
        }
        QJsonParseError error;
        const QJsonDocument document =
            QJsonDocument::fromJson(manifest.read(kMaximumManifestBytes + 1), &error);
        const QJsonObject object = document.object();
        if (error.error != QJsonParseError::NoError || !document.isObject() ||
            object.value(u"format"_s) != u"hexproof.custom-art-directory"_s ||
            object.value(u"formatVersion"_s).toInt() != 1 ||
            !object.value(u"entries"_s).isArray() ||
            object.value(u"entries"_s).toArray().size() > kMaximumEntries) {
            result.error = u"The custom artwork directory manifest is damaged or unsupported."_s;
            return result;
        }
        specifications = object.value(u"entries"_s).toArray().toVariantList();
    } else {
        QDirIterator files(directory, QDir::Files | QDir::NoDotAndDotDot | QDir::Hidden,
                           QDirIterator::Subdirectories);
        while (files.hasNext()) {
            const QString path = files.next();
            const QString suffix = QFileInfo(path).suffix().toLower();
            if (suffix != u"jpg"_s && suffix != u"jpeg"_s && suffix != u"png"_s &&
                suffix != u"webp"_s)
                continue;
            if (specifications.size() >= kMaximumEntries) {
                result.error = u"The custom artwork directory contains too many images."_s;
                return result;
            }
            specifications.append(QVariantMap{{u"file"_s, QDir(directory).relativeFilePath(path)}});
        }
    }
    std::sort(
        specifications.begin(), specifications.end(), [](const QVariant &a, const QVariant &b) {
            return a.toMap().value(u"file"_s).toString() < b.toMap().value(u"file"_s).toString();
        });
    QVariantList rows;
    qint64 totalBytes = 0;
    QSet<QString> stagedFiles;
    QHash<QString, ImageInfo> stagedSources;
    for (const QVariant &value : specifications) {
        const QVariantMap specification = value.toMap();
        const QString relative = specification.value(u"file"_s).toString();
        QString error;
        QVariantMap binding = hasManifest ? normalizeBinding(specification, &error)
                                          : filenameBinding(relative, &repository, &error);
        if (!binding.isEmpty() && hasManifest &&
            !validateCatalogBinding(binding, &repository, &error))
            binding.clear();
        const QString source = safeSource(directory, relative);
        if (error.isEmpty() && source.isEmpty())
            error = u"The source image must be an ordinary file inside the selected directory."_s;
        QVariantMap row = binding;
        row.insert(u"sourceFile"_s, relative);
        row.insert(u"valid"_s, false);
        if (error.isEmpty()) {
            if (!stagedSources.contains(source))
                stagedSources.insert(source, stageImage(source, staging->path()));
            const ImageInfo image = stagedSources.value(source);
            error = image.error;
            if (image.ok) {
                if (!stagedFiles.contains(image.fileName)) {
                    totalBytes += image.bytes;
                    stagedFiles.insert(image.fileName);
                }
                if (totalBytes > kMaximumPayloadBytes) {
                    result.error = u"The custom artwork selection is larger than 4 GiB."_s;
                    return result;
                }
                row = imageEntry(binding, image);
                row.insert(u"sourceFile"_s, relative);
                row.insert(u"valid"_s, true);
                row.insert(
                    u"imageSource"_s,
                    QUrl::fromLocalFile(QDir(staging->path()).filePath(image.fileName)).toString());
            }
        }
        row.insert(u"error"_s, error);
        rows.append(row);
    }
    finishPreview(&result, u"directory"_s, rows, existing);
    return result;
}

WorkResult inspectPack(const QString &path, const QString &databasePath,
                       const QVariantList &existing, std::shared_ptr<QTemporaryDir> staging)
{
    WorkResult result;
    result.staging = staging;
    result.preview.insert(u"kind"_s, u"pack"_s);
    QFile input(path);
    const QFileInfo info(path);
    if (!staging || !staging->isValid() || !info.isFile() || info.isSymLink() ||
        info.size() > kMaximumPayloadBytes + kMaximumManifestBytes + 12 ||
        !input.open(QIODevice::ReadOnly) || input.read(8) != QByteArray(kPackMagic, 8)) {
        result.error =
            u"Choose a valid Hexproof custom artwork pack, not a downloaded card-art pack."_s;
        return result;
    }
    QDataStream stream(&input);
    stream.setByteOrder(QDataStream::BigEndian);
    quint32 manifestLength = 0;
    stream >> manifestLength;
    if (stream.status() != QDataStream::Ok || manifestLength == 0 ||
        manifestLength > kMaximumManifestBytes) {
        result.error = u"The custom artwork pack manifest is damaged or too large."_s;
        return result;
    }
    QJsonParseError parseError;
    const QByteArray manifestBytes = input.read(manifestLength);
    const QJsonDocument document = QJsonDocument::fromJson(manifestBytes, &parseError);
    const QJsonObject manifest = document.object();
    if (manifestBytes.size() != manifestLength || parseError.error != QJsonParseError::NoError ||
        !document.isObject() || manifest.value(u"format"_s) != u"hexproof.custom-art-pack"_s ||
        manifest.value(u"formatVersion"_s).toInt() != 1 ||
        !manifest.value(u"entries"_s).isArray() || !manifest.value(u"images"_s).isArray() ||
        manifest.value(u"entries"_s).toArray().size() > kMaximumEntries ||
        manifest.value(u"images"_s).toArray().size() > kMaximumEntries) {
        result.error = u"The custom artwork pack is damaged or unsupported."_s;
        return result;
    }
    const QVariantList entries = manifest.value(u"entries"_s).toArray().toVariantList();
    QSet<QString> ids;
    QHash<QString, QVariantMap> needed;
    CatalogRepository repository(databasePath);
    for (const QVariant &value : entries) {
        const QVariantMap entry = value.toMap();
        if (!validateEntry(entry, &result.error) ||
            !validateCatalogBinding(entry, &repository, &result.error) ||
            ids.contains(entry.value(u"id"_s).toString())) {
            if (result.error.isEmpty())
                result.error = u"The custom artwork pack contains duplicate mappings."_s;
            return result;
        }
        const QString file = entry.value(u"fileName"_s).toString();
        if (needed.contains(file) &&
            needed.value(file).value(u"bytes"_s) != entry.value(u"bytes"_s)) {
            result.error = u"The custom artwork pack contains inconsistent image metadata."_s;
            return result;
        }
        ids.insert(entry.value(u"id"_s).toString());
        needed.insert(file, entry);
    }
    qint64 totalBytes = 0;
    QSet<QString> seenFiles;
    for (const QJsonValue &value : manifest.value(u"images"_s).toArray()) {
        const QJsonObject blob = value.toObject();
        const double count = blob.value(u"bytes"_s).toDouble(-1);
        if (count <= 0 || count > kMaximumImageBytes || count != static_cast<qint64>(count) ||
            totalBytes > kMaximumPayloadBytes - static_cast<qint64>(count)) {
            result.error = u"The custom artwork pack image sizes are invalid."_s;
            return result;
        }
        const QString format = blob.value(u"format"_s).toString();
        const QString hash = blob.value(u"sha256"_s).toString();
        const QString fileName = hash + u"."_s + format;
        if (!needed.contains(fileName) || seenFiles.contains(fileName) ||
            needed.value(fileName).value(u"bytes"_s).toLongLong() != static_cast<qint64>(count)) {
            result.error = u"The custom artwork pack contains unreferenced or duplicate images."_s;
            return result;
        }
        const QByteArray bytes = input.read(static_cast<qint64>(count));
        const ImageInfo image = validateImage(bytes);
        if (!image.ok || image.sha256 != hash || image.format != format ||
            image.bytes != static_cast<qint64>(count)) {
            result.error = u"The custom artwork pack contains invalid image data."_s;
            return result;
        }
        QSaveFile staged(QDir(staging->path()).filePath(fileName));
        if (!staged.open(QIODevice::WriteOnly) || staged.write(bytes) != bytes.size() ||
            !staged.commit()) {
            result.error = u"Could not prepare a private custom artwork preview."_s;
            return result;
        }
        totalBytes += image.bytes;
        seenFiles.insert(fileName);
    }
    if (!input.atEnd() || seenFiles.size() != needed.size()) {
        result.error = u"The custom artwork pack has missing images or unexpected trailing data."_s;
        return result;
    }
    QVariantList rows;
    for (const QVariant &value : entries) {
        QVariantMap row = value.toMap();
        row.insert(u"valid"_s, true);
        row.insert(
            u"imageSource"_s,
            QUrl::fromLocalFile(QDir(staging->path()).filePath(row.value(u"fileName"_s).toString()))
                .toString());
        rows.append(row);
    }
    finishPreview(&result, u"pack"_s, rows, existing);
    return result;
}

WorkResult exportPack(const QString &path, const QString &imageRoot, const QVariantList &entries)
{
    WorkResult result;
    if (inside(imageRoot, path) || QFileInfo(path).isSymLink()) {
        result.error = u"Choose an export location outside the custom artwork directory."_s;
        return result;
    }
    QJsonArray exported;
    QHash<QString, QVariantMap> blobs;
    int skipped = 0;
    QSet<QString> seenIds;
    for (const QVariant &value : entries) {
        const QVariantMap entry = value.toMap();
        QString error;
        if (!validateEntry(entry, &error) || seenIds.contains(entry.value(u"id"_s).toString())) {
            ++skipped;
            continue;
        }
        const QString fileName = entry.value(u"fileName"_s).toString();
        if (!blobs.contains(fileName)) {
            const QString source = safeManagedFile(imageRoot, fileName);
            QFile input(source);
            if (source.isEmpty() || !input.open(QIODevice::ReadOnly)) {
                ++skipped;
                continue;
            }
            const ImageInfo image = validateImage(input.read(kMaximumImageBytes + 1));
            if (!image.ok || image.fileName != fileName ||
                image.bytes != entry.value(u"bytes"_s).toLongLong()) {
                ++skipped;
                continue;
            }
            blobs.insert(fileName, {{u"sha256"_s, image.sha256},
                                    {u"format"_s, image.format},
                                    {u"bytes"_s, image.bytes}});
        } else if (blobs.value(fileName).value(u"bytes"_s).toLongLong() !=
                   entry.value(u"bytes"_s).toLongLong()) {
            ++skipped;
            continue;
        }
        exported.append(QJsonObject::fromVariantMap(portableEntry(entry)));
        seenIds.insert(entry.value(u"id"_s).toString());
    }
    if (exported.isEmpty()) {
        result.error = u"No valid custom artwork is available to export."_s;
        return result;
    }
    QStringList files = blobs.keys();
    files.sort();
    QJsonArray images;
    qint64 totalBytes = 0;
    for (const QString &fileName : files) {
        totalBytes += blobs.value(fileName).value(u"bytes"_s).toLongLong();
        images.append(QJsonObject::fromVariantMap(blobs.value(fileName)));
    }
    const QJsonObject manifest{{u"format"_s, u"hexproof.custom-art-pack"_s},
                               {u"formatVersion"_s, 1},
                               {u"entries"_s, exported},
                               {u"images"_s, images}};
    const QByteArray json = QJsonDocument(manifest).toJson(QJsonDocument::Compact);
    if (json.size() > kMaximumManifestBytes || totalBytes > kMaximumPayloadBytes) {
        result.error = u"The custom artwork selection is too large to export."_s;
        return result;
    }
    QSaveFile output(path);
    if (!output.open(QIODevice::WriteOnly) || output.write(kPackMagic, 8) != 8) {
        result.error = u"Could not write the custom artwork pack."_s;
        return result;
    }
    QDataStream stream(&output);
    stream.setByteOrder(QDataStream::BigEndian);
    stream << static_cast<quint32>(json.size());
    if (stream.status() != QDataStream::Ok || output.write(json) != json.size()) {
        result.error = u"Could not write the custom artwork pack."_s;
        return result;
    }
    for (const QString &fileName : files) {
        QFile input(safeManagedFile(imageRoot, fileName));
        if (!input.open(QIODevice::ReadOnly)) {
            result.error = u"Custom artwork changed while exporting; try again."_s;
            return result;
        }
        const QByteArray bytes = input.read(kMaximumImageBytes + 1);
        const QVariantMap blob = blobs.value(fileName);
        if (bytes.size() != blob.value(u"bytes"_s).toLongLong() ||
            QString::fromLatin1(
                QCryptographicHash::hash(bytes, QCryptographicHash::Sha256).toHex()) !=
                blob.value(u"sha256"_s).toString() ||
            output.write(bytes) != bytes.size()) {
            result.error = u"Custom artwork changed while exporting; try again."_s;
            return result;
        }
    }
    if (!output.commit()) {
        result.error = u"Could not write the custom artwork pack."_s;
        return result;
    }
    result.ok = true;
    result.result = {{u"entryCount"_s, exported.size()},
                     {u"imageCount"_s, images.size()},
                     {u"skippedCount"_s, skipped},
                     {u"bytes"_s, totalBytes}};
    return result;
}

} // namespace hexproof::client::customart
