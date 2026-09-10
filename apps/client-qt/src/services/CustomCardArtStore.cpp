// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "CustomCardArtStore.h"

#include "BackgroundTaskPools.h"
#include "CustomCardArtInternal.h"

#include <QDate>
#include <QDir>
#include <QFileInfo>
#include <QFutureWatcher>
#include <QStandardPaths>
#include <QTemporaryDir>
#include <QtConcurrent>

#include <algorithm>
#include <utility>

namespace hexproof::client {
using namespace Qt::StringLiterals;

namespace {

QVariantList changedBindings(const QVariantList &previous, const QVariantList &current,
                             const QSet<QString> &repairedImages)
{
    QHash<QString, QVariantMap> removed;
    for (const QVariant &value : previous) {
        const QVariantMap entry = value.toMap();
        removed.insert(entry.value(u"id"_s).toString(), entry);
    }
    QVariantList bindings;
    for (const QVariant &value : current) {
        const QVariantMap entry = value.toMap();
        const QVariantMap old = removed.take(entry.value(u"id"_s).toString());
        if (old == entry && !repairedImages.contains(entry.value(u"fileName"_s).toString()))
            continue;
        const QVariantMap binding = customart::normalizeBinding(entry, nullptr);
        const QVariantMap oldBinding = customart::normalizeBinding(old, nullptr);
        if (!oldBinding.isEmpty() && oldBinding != binding)
            bindings.append(oldBinding);
        bindings.append(binding);
    }
    for (const QVariantMap &entry : std::as_const(removed))
        bindings.append(customart::normalizeBinding(entry, nullptr));
    return bindings;
}

} // namespace

CustomCardArtStore::CustomCardArtStore(QString profileRoot, QString imageRoot, QObject *parent)
    : QObject(parent),
      m_profileRoot(std::move(profileRoot)),
      m_indexPath(QDir(m_profileRoot).filePath(u"custom-art.json"_s)),
      m_databasePath(QDir(m_profileRoot).filePath(u"cards.sqlite"_s)),
      m_imageRoot(imageRoot.isEmpty() ? QDir(m_profileRoot).filePath(u"custom-art"_s)
                                      : QFileInfo(imageRoot).absoluteFilePath())
{
    load();
}

CustomCardArtStore::~CustomCardArtStore()
{
    // Workers own only immutable snapshots, but wait before releasing the
    // profile lock and private inspection files during application shutdown.
    if (m_worker)
        m_worker->waitForFinished();
}

void CustomCardArtStore::load()
{
    if (m_busy)
        return;
    QString error;
    m_indexReadable = customart::readIndex(m_indexPath, &m_entries, &error);
    m_lastError = error;
    rebuildLookup();
    ++m_revision;
    emit changed();
    emit bindingsChanged({});
    emit messagesChanged();
}

bool CustomCardArtStore::setImageRoot(const QString &path)
{
    if (m_busy || path.trimmed().isEmpty())
        return false;
    m_imageRoot = QFileInfo(path).absoluteFilePath();
    rebuildLookup();
    ++m_revision;
    emit changed();
    emit bindingsChanged({});
    return true;
}

void CustomCardArtStore::setOperationGuard(std::function<bool()> guard)
{
    m_operationGuard = std::move(guard);
}

QVariantList CustomCardArtStore::entries() const
{
    QVariantList result;
    for (const QVariant &value : m_entries) {
        QVariantMap entry = value.toMap();
        const QString path =
            customart::safeManagedFile(m_imageRoot, entry.value(u"fileName"_s).toString());
        entry.insert(u"imageSource"_s,
                     path.isEmpty() ? QString{} : QUrl::fromLocalFile(path).toString());
        entry.insert(u"missing"_s, path.isEmpty());
        result.append(entry);
    }
    std::sort(result.begin(), result.end(), [](const QVariant &left, const QVariant &right) {
        const auto a = left.toMap();
        const auto b = right.toMap();
        const int compared = a.value(u"name"_s).toString().compare(b.value(u"name"_s).toString(),
                                                                   Qt::CaseInsensitive);
        return compared != 0 ? compared < 0
                             : a.value(u"id"_s).toString() < b.value(u"id"_s).toString();
    });
    return result;
}

QVariantMap CustomCardArtStore::entryFor(const QVariantMap &binding) const
{
    QString error;
    const QVariantMap normalized = customart::normalizeBinding(binding, &error);
    if (normalized.isEmpty())
        return {};
    const QString id = customart::bindingId(normalized);
    QVariantMap entry = m_entriesById.value(id);
    if (entry.isEmpty())
        return {};
    const QString path =
        customart::safeManagedFile(m_imageRoot, entry.value(u"fileName"_s).toString());
    entry.insert(u"imageSource"_s,
                 path.isEmpty() ? QString{} : QUrl::fromLocalFile(path).toString());
    entry.insert(u"missing"_s, path.isEmpty());
    return entry;
}

QString CustomCardArtStore::imagePathForBinding(const QVariantMap &binding) const
{
    const QVariantMap entry = entryFor(binding);
    return entry.isEmpty() ? QString{}
                           : QUrl(entry.value(u"imageSource"_s).toString()).toLocalFile();
}

void CustomCardArtStore::rebuildLookup()
{
    m_lookup.clear();
    m_entriesById.clear();
    for (const QVariant &value : m_entries) {
        const QVariantMap entry = value.toMap();
        m_entriesById.insert(entry.value(u"id"_s).toString(), entry);
        for (const QString &key : customart::lookupKeys(entry))
            m_lookup.insert(key, entry.value(u"fileName"_s).toString());
    }
}

QString CustomCardArtStore::imagePath(const QString &name, const QString &setCode,
                                      const QString &collectorNumber, const QString &oracleId) const
{
    QStringList keys;
    if (!setCode.isEmpty() && !collectorNumber.isEmpty())
        keys.append(customart::exactLookupKey(name, setCode, collectorNumber));
    if (!oracleId.isEmpty())
        keys.append(customart::cardLookupKey(name, oracleId));
    keys.append(customart::cardLookupKey(name, {}));
    for (const QString &key : keys) {
        const QString path = customart::safeManagedFile(m_imageRoot, m_lookup.value(key));
        if (!path.isEmpty())
            return path;
    }
    return {};
}

void CustomCardArtStore::clearMessages()
{
    m_lastError.clear();
    m_lastResult.clear();
    emit messagesChanged();
}

void CustomCardArtStore::reject(const QString &operation, const QString &error,
                                const QString &fileUrl)
{
    m_lastError = error;
    emit messagesChanged();
    if (operation.startsWith(u"inspect"_s)) {
        const QString kind =
            operation == u"inspectImage"_s
                ? u"image"_s
                : (operation == u"inspectDirectory"_s ? u"directory"_s : u"pack"_s);
        m_preview = {
            {u"kind"_s, kind}, {u"fileUrl"_s, fileUrl}, {u"ok"_s, false}, {u"error"_s, error}};
        m_pendingEntries.clear();
        m_staging.reset();
        emit inspectionFinished();
    }
    emit operationFinished({{u"operation"_s, operation},
                            {u"ok"_s, false},
                            {u"error"_s, error},
                            {u"fileUrl"_s, fileUrl}});
}

bool CustomCardArtStore::begin(const QString &operation, const QString &fileUrl)
{
    if (m_busy || (m_operationGuard && !m_operationGuard())) {
        reject(operation, u"Wait for the current card artwork operation to finish."_s, fileUrl);
        return false;
    }
    if (!m_indexReadable) {
        reject(operation, u"The local custom artwork index is damaged; it was left unchanged."_s,
               fileUrl);
        return false;
    }
    clearMessages();
    m_status = u"Processing custom artwork…"_s;
    m_busy = true;
    emit statusChanged();
    emit busyChanged();
    return true;
}

void CustomCardArtStore::run(const QString &operation, const QString &fileUrl,
                             std::function<customart::WorkResult()> work)
{
    auto *watcher = new QFutureWatcher<customart::WorkResult>(this);
    m_worker = watcher;
    connect(watcher, &QFutureWatcher<customart::WorkResult>::finished, this,
            [this, watcher, operation, fileUrl]() {
                const customart::WorkResult result = watcher->result();
                m_worker = nullptr;
                watcher->deleteLater();
                if (result.changed && result.ok) {
                    m_entries = result.entries;
                    rebuildLookup();
                    ++m_revision;
                }
                if (operation.startsWith(u"inspect"_s)) {
                    m_preview = result.preview;
                    m_preview.insert(u"ok"_s, result.ok);
                    m_preview.insert(u"error"_s, result.error);
                    m_preview.insert(u"fileUrl"_s, fileUrl);
                    m_pendingEntries = result.ok ? result.pendingEntries : QVariantList{};
                    m_staging = result.staging;
                }
                m_lastError = result.error;
                m_lastResult = result.ok && !operation.startsWith(u"inspect"_s)
                                   ? u"Custom artwork operation completed."_s
                                   : QString{};
                m_busy = false;
                m_status.clear();
                emit messagesChanged();
                emit statusChanged();
                emit busyChanged();
                if (result.changed && result.ok) {
                    emit changed();
                    if (!result.changedBindings.isEmpty())
                        emit bindingsChanged(result.changedBindings);
                }
                if (operation.startsWith(u"inspect"_s))
                    emit inspectionFinished();
                QVariantMap completion = result.result;
                completion.insert(u"operation"_s, operation);
                completion.insert(u"ok"_s, result.ok);
                completion.insert(u"error"_s, result.error);
                completion.insert(u"fileUrl"_s, fileUrl);
                emit operationFinished(completion);
            });
    watcher->setFuture(QtConcurrent::run(
        BackgroundTaskPools::customCardArt(), [work = std::move(work), previous = m_entries]() {
            auto result = work();
            if (result.changed && result.ok)
                result.changedBindings =
                    changedBindings(previous, result.entries, result.repairedImageFiles);
            return result;
        }));
}

void CustomCardArtStore::inspectImage(const QUrl &fileUrl)
{
    if (!fileUrl.isLocalFile()) {
        reject(u"inspectImage"_s, u"Choose a local custom artwork image."_s, fileUrl.toString());
        return;
    }
    if (!begin(u"inspectImage"_s, fileUrl.toString()))
        return;
    auto staging = std::make_shared<QTemporaryDir>();
    run(u"inspectImage"_s, fileUrl.toString(), [staging, path = fileUrl.toLocalFile()] {
        customart::WorkResult result;
        result.staging = staging;
        result.preview.insert(u"kind"_s, u"image"_s);
        const auto image = customart::stageImage(path, staging->path());
        result.ok = image.ok;
        result.error = image.error;
        if (image.ok) {
            result.preview.insert(
                u"imageSource"_s,
                QUrl::fromLocalFile(QDir(staging->path()).filePath(image.fileName)).toString());
            result.preview.insert(u"width"_s, image.width);
            result.preview.insert(u"height"_s, image.height);
            result.preview.insert(u"bytes"_s, image.bytes);
        }
        return result;
    });
}

void CustomCardArtStore::setImage(const QUrl &fileUrl, const QVariantMap &binding)
{
    QString error;
    const auto normalized = customart::normalizeBinding(binding, &error);
    if (!fileUrl.isLocalFile() || normalized.isEmpty()) {
        reject(u"setImage"_s, error.isEmpty() ? u"Choose a local custom artwork image."_s : error,
               fileUrl.toString());
        return;
    }
    if (!begin(u"setImage"_s, fileUrl.toString()))
        return;
    auto staging = std::make_shared<QTemporaryDir>();
    run(u"setImage"_s, fileUrl.toString(),
        [staging, normalized, source = fileUrl.toLocalFile(), index = m_indexPath,
         root = m_imageRoot, database = m_databasePath, entries = m_entries] {
            QString bindingError;
            if (!customart::validateBindingForCatalog(normalized, database, &bindingError)) {
                customart::WorkResult result;
                result.error = bindingError;
                return result;
            }
            const auto image = customart::stageImage(source, staging->path());
            if (!image.ok) {
                customart::WorkResult result;
                result.error = image.error;
                return result;
            }
            QVariantMap entry = normalized;
            entry.insert(u"id"_s, customart::bindingId(normalized));
            entry.insert(u"fileName"_s, image.fileName);
            entry.insert(u"sha256"_s, image.sha256);
            entry.insert(u"format"_s, image.format);
            entry.insert(u"bytes"_s, image.bytes);
            auto result = customart::install(index, root, entries, {entry}, staging->path(), true);
            result.result.insert(u"id"_s, entry.value(u"id"_s));
            return result;
        });
}

void CustomCardArtStore::removeIds(const QStringList &ids, const QString &operation)
{
    if (!begin(operation))
        return;
    run(operation, {}, [index = m_indexPath, root = m_imageRoot, entries = m_entries, ids] {
        return customart::remove(index, root, entries, ids);
    });
}

void CustomCardArtStore::removeEntry(const QString &id)
{
    removeIds({id}, u"removeEntry"_s);
}

void CustomCardArtStore::removeBindings(const QVariantMap &binding, bool allFaces)
{
    QString error;
    const auto normalized = customart::normalizeBinding(binding, &error);
    if (normalized.isEmpty()) {
        reject(u"removeBindings"_s, error);
        return;
    }
    QStringList ids;
    for (const QVariant &value : m_entries) {
        const auto entry = value.toMap();
        if ((!allFaces && entry.value(u"id"_s).toString() == customart::bindingId(normalized)) ||
            (allFaces && customart::familyKey(entry) == customart::familyKey(normalized))) {
            ids.append(entry.value(u"id"_s).toString());
        }
    }
    removeIds(ids, u"removeBindings"_s);
}

void CustomCardArtStore::clear()
{
    QStringList ids;
    for (const QVariant &value : m_entries)
        ids.append(value.toMap().value(u"id"_s).toString());
    removeIds(ids, u"clear"_s);
}

void CustomCardArtStore::inspectDirectory(const QUrl &directoryUrl)
{
    if (!directoryUrl.isLocalFile() || !QFileInfo(directoryUrl.toLocalFile()).isDir()) {
        reject(u"inspectDirectory"_s, u"Choose a readable local artwork directory."_s,
               directoryUrl.toString());
        return;
    }
    if (!begin(u"inspectDirectory"_s, directoryUrl.toString()))
        return;
    auto staging = std::make_shared<QTemporaryDir>();
    run(u"inspectDirectory"_s, directoryUrl.toString(),
        [staging, path = directoryUrl.toLocalFile(), database = m_databasePath,
         entries = m_entries] {
            return customart::inspectDirectory(path, database, entries, staging);
        });
}

void CustomCardArtStore::inspectPack(const QUrl &fileUrl)
{
    if (!fileUrl.isLocalFile()) {
        reject(u"inspectPack"_s, u"Choose a local custom artwork pack."_s, fileUrl.toString());
        return;
    }
    if (!begin(u"inspectPack"_s, fileUrl.toString()))
        return;
    auto staging = std::make_shared<QTemporaryDir>();
    run(u"inspectPack"_s, fileUrl.toString(),
        [staging, path = fileUrl.toLocalFile(), database = m_databasePath, entries = m_entries] {
            return customart::inspectPack(path, database, entries, staging);
        });
}

void CustomCardArtStore::importPreview(bool replaceExisting)
{
    const QString kind = m_preview.value(u"kind"_s).toString();
    if (!m_preview.value(u"ok"_s).toBool() || (kind != u"directory"_s && kind != u"pack"_s) ||
        m_pendingEntries.isEmpty() || !m_staging) {
        reject(u"importPreview"_s,
               u"Inspect a custom artwork directory or pack before importing."_s);
        return;
    }
    if (!begin(u"importPreview"_s))
        return;
    run(u"importPreview"_s, m_preview.value(u"fileUrl"_s).toString(),
        [index = m_indexPath, root = m_imageRoot, existing = m_entries, incoming = m_pendingEntries,
         staging = m_staging, replaceExisting] {
            return customart::install(index, root, existing, incoming, staging->path(),
                                      replaceExisting);
        });
}

void CustomCardArtStore::exportPack(const QUrl &fileUrl, const QStringList &ids)
{
    if (!fileUrl.isLocalFile()) {
        reject(u"exportPack"_s, u"Choose a local destination for the custom artwork pack."_s,
               fileUrl.toString());
        return;
    }
    QVariantList selected;
    for (const QVariant &value : m_entries) {
        if (ids.isEmpty() || ids.contains(value.toMap().value(u"id"_s).toString()))
            selected.append(value);
    }
    if (selected.isEmpty()) {
        reject(u"exportPack"_s, u"There is no custom artwork in this selection."_s,
               fileUrl.toString());
        return;
    }
    if (!begin(u"exportPack"_s, fileUrl.toString()))
        return;
    QString path = fileUrl.toLocalFile();
    if (QFileInfo(path).suffix().isEmpty())
        path += u".hexproof-custom-artpack"_s;
    run(u"exportPack"_s, fileUrl.toString(), [path, root = m_imageRoot, selected] {
        return customart::exportPack(path, root, selected);
    });
}

QUrl CustomCardArtStore::suggestedExportUrl() const
{
    QString directory = QStandardPaths::writableLocation(QStandardPaths::DownloadLocation);
    if (directory.isEmpty())
        directory = QDir::homePath();
    return QUrl::fromLocalFile(
        QDir(directory).filePath(u"hexproof-custom-art-%1.hexproof-custom-artpack"_s.arg(
            QDate::currentDate().toString(u"yyyyMMdd"_s))));
}

} // namespace hexproof::client
