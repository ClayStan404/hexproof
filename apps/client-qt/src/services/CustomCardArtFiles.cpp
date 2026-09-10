// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "CustomCardArtInternal.h"

#include <QBuffer>
#include <QCryptographicHash>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QImageReader>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QRegularExpression>
#include <QSaveFile>
#include <QSet>

#include <algorithm>
#include <cmath>

namespace hexproof::client::customart {
using namespace Qt::StringLiterals;

namespace {

bool validText(const QString &text, int maximum, bool required = false)
{
    return text.size() <= maximum && (!required || !text.simplified().isEmpty()) &&
           !text.contains(QRegularExpression(u"[\\x00-\\x1f\\x7f]"_s));
}

QString joined(const QStringList &parts)
{
    return parts.join(QChar(0x1f));
}

struct NewFileRollback
{
    QStringList paths;
    bool committed = false;
    ~NewFileRollback()
    {
        if (!committed) {
            for (const QString &path : paths)
                QFile::remove(path);
        }
    }
};

bool writeBytes(const QString &path, const QByteArray &bytes, QString *error)
{
    if (QFileInfo(path).isSymLink()) {
        *error = u"Cannot replace a symbolic link with custom artwork."_s;
        return false;
    }
    QSaveFile output(path);
    if (!output.open(QIODevice::WriteOnly) || output.write(bytes) != bytes.size() ||
        !output.commit()) {
        *error = u"Could not save custom artwork."_s;
        return false;
    }
    return true;
}

} // namespace

QString normalizedName(const QString &name)
{
    return name.simplified().toCaseFolded();
}

QVariantMap normalizeBinding(const QVariantMap &binding, QString *error)
{
    const QString scope = binding.value(u"scope"_s, u"printing"_s).toString();
    const QString name = binding.value(u"name"_s).toString().simplified();
    const QString face = binding.value(u"faceName"_s).toString().simplified();
    const QString setCode = binding.value(u"setCode"_s).toString().trimmed().toUpper();
    const QString collector = binding.value(u"collectorNumber"_s).toString().trimmed();
    const QString oracleId = binding.value(u"oracleId"_s).toString().trimmed().toLower();
    if ((scope != u"printing"_s && scope != u"card"_s) || !validText(name, 512, true) ||
        !validText(face, 512) || !validText(setCode, 16) || !validText(collector, 64) ||
        !validText(oracleId, 128) || setCode.isEmpty() != collector.isEmpty() ||
        (scope == u"printing"_s && setCode.isEmpty()) ||
        (scope == u"card"_s && oracleId.isEmpty()) ||
        (!setCode.isEmpty() && !QRegularExpression(u"^[A-Z0-9_-]+$"_s).match(setCode).hasMatch())) {
        if (error)
            *error = u"Choose an unambiguous card, printing, and face for custom artwork."_s;
        return {};
    }
    return {{u"scope"_s, scope},
            {u"name"_s, name},
            {u"faceName"_s, face},
            {u"setCode"_s, setCode},
            {u"collectorNumber"_s, collector},
            {u"oracleId"_s, oracleId}};
}

QString familyKey(const QVariantMap &binding)
{
    if (binding.value(u"scope"_s).toString() == u"printing"_s)
        return joined({u"printing"_s, binding.value(u"setCode"_s).toString().toUpper(),
                       binding.value(u"collectorNumber"_s).toString()});
    const QString oracle = binding.value(u"oracleId"_s).toString();
    return joined({u"card"_s, oracle.isEmpty()
                                  ? u"name:"_s + normalizedName(binding.value(u"name"_s).toString())
                                  : u"oracle:"_s + oracle.toLower()});
}

QString bindingId(const QVariantMap &binding)
{
    const QString identity =
        familyKey(binding) + QChar(0x1f) + normalizedName(binding.value(u"faceName"_s).toString());
    return QString::fromLatin1(
        QCryptographicHash::hash(identity.toUtf8(), QCryptographicHash::Sha256).toHex());
}

QString exactLookupKey(const QString &name, const QString &setCode, const QString &collector)
{
    return joined({u"printing"_s, setCode.toUpper(), collector, normalizedName(name)});
}

QString cardLookupKey(const QString &name, const QString &oracleId)
{
    return joined({u"card"_s, oracleId.isEmpty() ? u"name"_s : u"oracle:"_s + oracleId.toLower(),
                   normalizedName(name)});
}

QStringList lookupKeys(const QVariantMap &binding)
{
    const QString face = binding.value(u"faceName"_s).toString();
    const QString name = binding.value(u"name"_s).toString();
    QStringList aliases{face.isEmpty() ? name : face};
    if (face.isEmpty() && name.contains(u" // "_s)) {
        const QString first = name.section(u" // "_s, 0, 0);
        const QString second = name.section(u" // "_s, 1, 1);
        // Same-named token faces cannot share the short-name alias. The
        // canonical combined name identifies the front, the explicit face
        // name identifies the reverse, just as in catalog face requests.
        if (normalizedName(first) != normalizedName(second))
            aliases.append(first);
    }
    QStringList keys;
    for (const QString &alias : aliases) {
        if (binding.value(u"scope"_s).toString() == u"printing"_s) {
            keys.append(exactLookupKey(alias, binding.value(u"setCode"_s).toString(),
                                       binding.value(u"collectorNumber"_s).toString()));
        } else {
            keys.append(cardLookupKey(alias, binding.value(u"oracleId"_s).toString()));
        }
    }
    return keys;
}

QString safeManagedFile(const QString &root, const QString &fileName)
{
    static const QRegularExpression filePattern(u"^[0-9a-f]{64}\\.(jpg|png|webp)$"_s);
    if (!filePattern.match(fileName).hasMatch())
        return {};
    const QFileInfo file(QDir(root).filePath(fileName));
    if (!file.isFile() || file.isSymLink())
        return {};
    const QString canonicalRoot = QFileInfo(root).canonicalFilePath();
    if (canonicalRoot.isEmpty() || file.canonicalPath() != canonicalRoot)
        return {};
    return file.canonicalFilePath();
}

bool validateEntry(const QVariantMap &entry, QString *error)
{
    const QVariantMap binding = normalizeBinding(entry, error);
    const QString hash = entry.value(u"sha256"_s).toString();
    const QString format = entry.value(u"format"_s).toString();
    const QString file = entry.value(u"fileName"_s).toString();
    const qint64 size = entry.value(u"bytes"_s).toLongLong();
    bool sizeIsNumeric = false;
    const double numericSize = entry.value(u"bytes"_s).toDouble(&sizeIsNumeric);
    if (binding.isEmpty() || !QRegularExpression(u"^[0-9a-f]{64}$"_s).match(hash).hasMatch() ||
        (format != u"jpg"_s && format != u"png"_s && format != u"webp"_s) ||
        file != hash + u"."_s + format || !sizeIsNumeric || !std::isfinite(numericSize) ||
        numericSize != static_cast<double>(size) || size <= 0 || size > kMaximumImageBytes ||
        entry.value(u"id"_s).toString() != bindingId(binding)) {
        if (error && error->isEmpty())
            *error = u"The custom artwork metadata is damaged or unsupported."_s;
        return false;
    }
    return true;
}

QVariantMap portableEntry(const QVariantMap &entry)
{
    QString error;
    QVariantMap result = normalizeBinding(entry, &error);
    for (const QString &key : {u"id"_s, u"fileName"_s, u"sha256"_s, u"format"_s, u"bytes"_s})
        result.insert(key, entry.value(key));
    return result;
}

ImageInfo validateImage(const QByteArray &bytes)
{
    ImageInfo result;
    if (bytes.isEmpty() || bytes.size() > kMaximumImageBytes) {
        result.error = u"Choose a JPEG, PNG, or WebP image no larger than 32 MiB."_s;
        return result;
    }
    QBuffer buffer;
    buffer.setData(bytes);
    buffer.open(QIODevice::ReadOnly);
    QImageReader reader(&buffer);
    const QByteArray format = reader.format().toLower();
    if (format != "jpeg" && format != "jpg" && format != "png" && format != "webp") {
        result.error = u"Choose a supported JPEG, PNG, or WebP image."_s;
        return result;
    }
    const QSize dimensions = reader.size();
    constexpr qint64 maximumPixels = 40'000'000;
    if (!dimensions.isValid() || dimensions.width() > 12'000 || dimensions.height() > 12'000 ||
        static_cast<qint64>(dimensions.width()) * dimensions.height() > maximumPixels ||
        reader.imageCount() > 1 || reader.supportsAnimation()) {
        result.error =
            u"Custom artwork must be a still image within 12000 pixels and 40 megapixels."_s;
        return result;
    }
    const QImage image = reader.read();
    if (image.isNull()) {
        result.error = u"The selected custom artwork cannot be decoded."_s;
        return result;
    }
    result.ok = true;
    result.format = format == "jpeg" ? u"jpg"_s : QString::fromLatin1(format);
    result.sha256 =
        QString::fromLatin1(QCryptographicHash::hash(bytes, QCryptographicHash::Sha256).toHex());
    result.fileName = result.sha256 + u"."_s + result.format;
    result.bytes = bytes.size();
    result.width = dimensions.width();
    result.height = dimensions.height();
    return result;
}

ImageInfo stageImage(const QString &source, const QString &stagingRoot)
{
    const QFileInfo info(source);
    ImageInfo result;
    if (stagingRoot.isEmpty() || !QFileInfo(stagingRoot).isDir() ||
        QFileInfo(stagingRoot).isSymLink()) {
        result.error = u"Could not create a private custom artwork preview."_s;
        return result;
    }
    if (!info.isFile() || info.isSymLink() || info.size() <= 0 ||
        info.size() > kMaximumImageBytes) {
        result.error = u"Choose a readable local image no larger than 32 MiB."_s;
        return result;
    }
    QFile input(source);
    if (!input.open(QIODevice::ReadOnly)) {
        result.error = u"Could not read the selected custom artwork."_s;
        return result;
    }
    const QByteArray bytes = input.read(kMaximumImageBytes + 1);
    result = validateImage(bytes);
    if (!result.ok)
        return result;
    if (!writeBytes(QDir(stagingRoot).filePath(result.fileName), bytes, &result.error)) {
        result.ok = false;
    }
    return result;
}

bool readIndex(const QString &path, QVariantList *entries, QString *error)
{
    entries->clear();
    const QFileInfo info(path);
    if (!info.exists())
        return true;
    QFile input(path);
    if (!info.isFile() || info.isSymLink() || info.size() > kMaximumManifestBytes ||
        !input.open(QIODevice::ReadOnly)) {
        *error = u"Could not read the local custom artwork index."_s;
        return false;
    }
    QJsonParseError parseError;
    const QJsonDocument document =
        QJsonDocument::fromJson(input.read(kMaximumManifestBytes + 1), &parseError);
    const QJsonObject root = document.object();
    if (parseError.error != QJsonParseError::NoError || !document.isObject() ||
        root.value(u"format"_s) != u"hexproof.custom-art-index"_s ||
        root.value(u"formatVersion"_s).toInt() != 1 || !root.value(u"entries"_s).isArray() ||
        root.value(u"entries"_s).toArray().size() > kMaximumEntries) {
        *error = u"The local custom artwork index is damaged; it was left unchanged."_s;
        return false;
    }
    QSet<QString> ids;
    for (const QJsonValue &value : root.value(u"entries"_s).toArray()) {
        const QVariantMap entry = value.toObject().toVariantMap();
        if (!value.isObject() || !validateEntry(entry, error) ||
            ids.contains(entry.value(u"id"_s).toString())) {
            if (error->isEmpty())
                *error = u"The local custom artwork index contains duplicate mappings."_s;
            entries->clear();
            return false;
        }
        ids.insert(entry.value(u"id"_s).toString());
        entries->append(portableEntry(entry));
    }
    return true;
}

bool writeIndex(const QString &path, const QVariantList &entries, QString *error)
{
    if (entries.size() > kMaximumEntries) {
        *error = u"There are too many custom artwork mappings."_s;
        return false;
    }
    QVariantList portable;
    QSet<QString> ids;
    for (const QVariant &value : entries) {
        const QVariantMap entry = value.toMap();
        if (!validateEntry(entry, error) || ids.contains(entry.value(u"id"_s).toString())) {
            if (error->isEmpty())
                *error = u"The custom artwork index contains conflicting mappings."_s;
            return false;
        }
        ids.insert(entry.value(u"id"_s).toString());
        portable.append(portableEntry(entry));
    }
    const QJsonObject root{{u"format"_s, u"hexproof.custom-art-index"_s},
                           {u"formatVersion"_s, 1},
                           {u"entries"_s, QJsonArray::fromVariantList(portable)}};
    const QByteArray json = QJsonDocument(root).toJson(QJsonDocument::Compact);
    if (json.size() > kMaximumManifestBytes || !QDir().mkpath(QFileInfo(path).absolutePath())) {
        *error = u"Could not save the local custom artwork index."_s;
        return false;
    }
    return writeBytes(path, json, error);
}

WorkResult install(const QString &indexPath, const QString &imageRoot, const QVariantList &existing,
                   const QVariantList &incoming, const QString &stagingRoot, bool replaceExisting)
{
    WorkResult result;
    QHash<QString, QVariantMap> merged;
    for (const QVariant &value : existing) {
        const QVariantMap entry = value.toMap();
        merged.insert(entry.value(u"id"_s).toString(), portableEntry(entry));
    }
    int preserved = 0;
    QVariantList selected;
    QSet<QString> ids;
    for (const QVariant &value : incoming) {
        const QVariantMap entry = value.toMap();
        if (!validateEntry(entry, &result.error) || ids.contains(entry.value(u"id"_s).toString())) {
            if (result.error.isEmpty())
                result.error = u"The custom artwork selection has conflicting mappings."_s;
            return result;
        }
        const QString id = entry.value(u"id"_s).toString();
        ids.insert(id);
        if (merged.contains(id) && !replaceExisting) {
            ++preserved;
            continue;
        }
        selected.append(portableEntry(entry));
    }
    // Verify every selected image before updating either the destination or
    // index. The preview's source paths are never trusted as image identities.
    QSet<QString> verified;
    for (const QVariant &value : selected) {
        const QVariantMap entry = value.toMap();
        const QString fileName = entry.value(u"fileName"_s).toString();
        if (verified.contains(fileName))
            continue;
        const QString source = safeManagedFile(stagingRoot, fileName);
        QFile input(source);
        if (source.isEmpty() || !input.open(QIODevice::ReadOnly)) {
            result.error = u"The inspected custom artwork is no longer available."_s;
            return result;
        }
        const ImageInfo image = validateImage(input.read(kMaximumImageBytes + 1));
        if (!image.ok || image.sha256 != entry.value(u"sha256"_s).toString() ||
            image.bytes != entry.value(u"bytes"_s).toLongLong()) {
            result.error =
                u"The inspected custom artwork changed; inspect it again before importing."_s;
            return result;
        }
        verified.insert(fileName);
    }
    if (!QDir().mkpath(imageRoot)) {
        result.error = u"Could not create the custom artwork directory."_s;
        return result;
    }
    QSet<QString> copied;
    NewFileRollback rollback;
    for (const QVariant &value : selected) {
        const QVariantMap entry = value.toMap();
        const QString fileName = entry.value(u"fileName"_s).toString();
        if (!copied.contains(fileName)) {
            QFile input(safeManagedFile(stagingRoot, fileName));
            if (!input.open(QIODevice::ReadOnly)) {
                result.error = u"Could not read inspected custom artwork."_s;
                return result;
            }
            const QByteArray bytes = input.read(kMaximumImageBytes + 1);
            const QString destination = QDir(imageRoot).filePath(fileName);
            if (!QFileInfo::exists(destination))
                rollback.paths.append(destination);
            const QString existingPath = safeManagedFile(imageRoot, fileName);
            QFile existingImage(existingPath);
            const bool imageUnchanged = !existingPath.isEmpty() &&
                                        existingImage.open(QIODevice::ReadOnly) &&
                                        existingImage.read(kMaximumImageBytes + 1) == bytes;
            existingImage.close();
            if (QString::fromLatin1(
                    QCryptographicHash::hash(bytes, QCryptographicHash::Sha256).toHex()) !=
                    entry.value(u"sha256"_s).toString() ||
                (!imageUnchanged && !writeBytes(destination, bytes, &result.error))) {
                if (result.error.isEmpty())
                    result.error = u"The inspected custom artwork changed."_s;
                return result;
            }
            if (!imageUnchanged)
                result.repairedImageFiles.insert(fileName);
            copied.insert(fileName);
        }
        merged.insert(entry.value(u"id"_s).toString(), entry);
    }
    const QStringList ordered = [&merged]() {
        auto keys = merged.keys();
        keys.sort();
        return keys;
    }();
    for (const QString &id : ordered)
        result.entries.append(merged.value(id));
    if (!selected.isEmpty() && !writeIndex(indexPath, result.entries, &result.error))
        return result;
    rollback.committed = true;
    QSet<QString> referenced;
    for (const QVariant &value : result.entries)
        referenced.insert(value.toMap().value(u"fileName"_s).toString());
    for (const QVariant &value : existing) {
        const QString fileName = value.toMap().value(u"fileName"_s).toString();
        if (!referenced.contains(fileName)) {
            const QString obsolete = safeManagedFile(imageRoot, fileName);
            if (!obsolete.isEmpty())
                QFile::remove(obsolete);
        }
    }
    result.ok = true;
    result.changed = !selected.isEmpty();
    result.result = {{u"importedCount"_s, selected.size()},
                     {u"preservedCount"_s, preserved},
                     {u"imageCount"_s, copied.size()}};
    return result;
}

WorkResult remove(const QString &indexPath, const QString &imageRoot, const QVariantList &existing,
                  const QStringList &ids)
{
    WorkResult result;
    const QSet<QString> selected(ids.begin(), ids.end());
    QSet<QString> retainedFiles;
    QSet<QString> candidates;
    int removed = 0;
    for (const QVariant &value : existing) {
        const QVariantMap entry = value.toMap();
        if (selected.contains(entry.value(u"id"_s).toString())) {
            candidates.insert(entry.value(u"fileName"_s).toString());
            ++removed;
        } else {
            retainedFiles.insert(entry.value(u"fileName"_s).toString());
            result.entries.append(entry);
        }
    }
    if (removed > 0 && !writeIndex(indexPath, result.entries, &result.error))
        return result;
    int retainedOnDisk = 0;
    for (const QString &fileName : candidates) {
        if (retainedFiles.contains(fileName))
            continue;
        const QString path = safeManagedFile(imageRoot, fileName);
        if (!path.isEmpty() && !QFile::remove(path))
            ++retainedOnDisk;
    }
    result.ok = true;
    result.changed = removed > 0;
    result.result = {{u"removedCount"_s, removed}, {u"retainedFileCount"_s, retainedOnDisk}};
    return result;
}

} // namespace hexproof::client::customart
