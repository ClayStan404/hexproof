// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "CardArtStorage.h"

#include "BackgroundTaskPools.h"
#include "CatalogStorage.h"

#include <QCryptographicHash>
#include <QDateTime>
#include <QDir>
#include <QDirIterator>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QLockFile>
#include <QSaveFile>
#include <QStorageInfo>
#include <QTemporaryFile>
#include <QtConcurrentRun>

#include <utility>

namespace hexproof::client {
namespace {

constexpr auto kFormat = "hexproof.card-art-storage";
constexpr auto kOwnerFile = ".hexproof-art-owner.json";
constexpr auto kLockFile = ".hexproof-art.lock";

QString absolutePath(const QString &path)
{
    QFileInfo info(path);
    QStringList missing;
    while (!info.exists() && info.absoluteFilePath() != info.absolutePath()) {
        missing.prepend(info.fileName());
        info = QFileInfo(info.absolutePath());
    }
    QString resolved = info.exists() ? info.canonicalFilePath() : info.absoluteFilePath();
    for (const QString &component : missing)
        resolved = QDir(resolved).filePath(component);
    return QDir::cleanPath(resolved);
}

bool containedBy(const QString &path, const QString &directory)
{
    const QString relative = QDir(directory).relativeFilePath(path);
    return relative == QStringLiteral(".") ||
           (relative != QStringLiteral("..") && !relative.startsWith(QStringLiteral("../")) &&
            !QDir::isAbsolutePath(relative));
}

bool ordinaryDirectory(const QString &path)
{
    const QFileInfo info(path);
    return info.isDir() && !info.isSymLink() &&
           QDir::cleanPath(info.canonicalFilePath()) == QDir::cleanPath(info.absoluteFilePath());
}

bool writableDirectory(const QString &path)
{
    if (!ordinaryDirectory(path) || !QFileInfo(path).isWritable())
        return false;
    QTemporaryFile probe(QDir(path).filePath(QStringLiteral(".hexproof-write-test-XXXXXX")));
    return probe.open();
}

bool safeParents(const QString &directory, const QString &root)
{
    QString path = QDir::cleanPath(directory);
    while (containedBy(path, root)) {
        const QFileInfo info(path);
        if (info.isSymLink() || (info.exists() && !info.isDir()))
            return false;
        if (path == root)
            return true;
        path = info.absolutePath();
    }
    return false;
}

QJsonObject readObject(const QString &path)
{
    const QFileInfo info(path);
    if (!info.isFile() || info.isSymLink() || info.size() > 1024 * 1024)
        return {};
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly) || file.size() > 1024 * 1024)
        return {};
    const QByteArray bytes = file.read(1024 * 1024 + 1);
    return bytes.size() > 1024 * 1024 ? QJsonObject{} : QJsonDocument::fromJson(bytes).object();
}

bool ownedDirectory(const QString &path, const QString &profileKey)
{
    if (!ordinaryDirectory(path))
        return false;
    const QString ownerPath = QDir(path).filePath(QString::fromLatin1(kOwnerFile));
    if (QFileInfo(ownerPath).isSymLink())
        return false;
    const QJsonObject owner = readObject(ownerPath);
    return owner.value(QStringLiteral("format")).toString() == QString::fromLatin1(kFormat) &&
           owner.value(QStringLiteral("profileKey")).toString() == profileKey;
}

struct CopyFile
{
    QString source;
    QString destination;
    qint64 size = 0;
    QDateTime modified;
};

bool scanTree(const QString &sourceRoot, const QString &destinationRoot, QList<CopyFile> *files,
              qint64 *bytes, QString *error)
{
    if (!ordinaryDirectory(sourceRoot)) {
        *error = QStringLiteral(
            "The current card-art directory is unavailable. Reconnect its disk before migrating.");
        return false;
    }
    QDirIterator iterator(sourceRoot,
                          QDir::AllEntries | QDir::NoDotAndDotDot | QDir::Hidden | QDir::System,
                          QDirIterator::Subdirectories);
    while (iterator.hasNext()) {
        iterator.next();
        const QFileInfo info = iterator.fileInfo();
        if (info.isSymLink() || (!info.isFile() && !info.isDir())) {
            *error = QStringLiteral(
                "Card-art migration does not follow symbolic links or special files.");
            return false;
        }
        if (info.isDir())
            continue;
        const QString relative = QDir(sourceRoot).relativeFilePath(info.absoluteFilePath());
        files->append({info.absoluteFilePath(), QDir(destinationRoot).filePath(relative),
                       info.size(), info.lastModified()});
        *bytes += info.size();
    }
    return true;
}

bool verifiedCopy(const CopyFile &copy, const QString &destinationRoot,
                  const std::function<void(qint64)> &progress, QString *error)
{
    const QFileInfo before(copy.source);
    if (!before.isFile() || before.isSymLink() ||
        QDir::cleanPath(before.canonicalFilePath()) != QDir::cleanPath(copy.source) ||
        before.size() != copy.size || before.lastModified() != copy.modified) {
        *error = QStringLiteral(
            "A source image changed after scanning. The original location remains active.");
        return false;
    }
    if (!safeParents(QFileInfo(copy.destination).absolutePath(), destinationRoot) ||
        QFileInfo(copy.destination).isSymLink() ||
        (QFileInfo::exists(copy.destination) && !QFileInfo(copy.destination).isFile()) ||
        !QDir().mkpath(QFileInfo(copy.destination).absolutePath())) {
        *error = QStringLiteral("The destination contains an unsafe or unavailable image path.");
        return false;
    }
    QFile source(copy.source);
    QSaveFile destination(copy.destination);
    if (!source.open(QIODevice::ReadOnly) || !destination.open(QIODevice::WriteOnly)) {
        *error = QStringLiteral(
            "Could not copy card images. Check disk space and directory permissions.");
        return false;
    }
    QCryptographicHash sourceHash(QCryptographicHash::Sha256);
    qint64 copied = 0;
    while (!source.atEnd()) {
        const QByteArray chunk = source.read(1024 * 1024);
        if (chunk.isEmpty() || destination.write(chunk) != chunk.size()) {
            *error = QStringLiteral(
                "Could not copy card images. Check disk space and directory permissions.");
            return false;
        }
        sourceHash.addData(chunk);
        copied += chunk.size();
        progress(chunk.size());
    }
    const QFileInfo after(copy.source);
    if (source.error() != QFileDevice::NoError || copied != copy.size || after.isSymLink() ||
        QDir::cleanPath(after.canonicalFilePath()) != QDir::cleanPath(copy.source) ||
        after.size() != copy.size || after.lastModified() != copy.modified ||
        !destination.commit()) {
        *error = QStringLiteral("A card image changed or could not be saved during migration. The "
                                "original location remains active.");
        return false;
    }
    QFile verification(copy.destination);
    QCryptographicHash destinationHash(QCryptographicHash::Sha256);
    if (!verification.open(QIODevice::ReadOnly) || !destinationHash.addData(&verification) ||
        verification.size() != copied || destinationHash.result() != sourceHash.result()) {
        *error = QStringLiteral(
            "A copied card image failed verification. The original location remains active.");
        return false;
    }
    return true;
}

} // namespace

CardArtStorage::CardArtStorage(const QString &profileRoot, QObject *parent)
    : QObject(parent),
      m_profileRoot(absolutePath(profileRoot)),
      m_profileKey(QString::fromLatin1(
          QCryptographicHash::hash(m_profileRoot.toUtf8(), QCryptographicHash::Sha256)
              .toHex()
              .left(20))),
      m_configPath(QDir(m_profileRoot).filePath(QStringLiteral("card-art-storage.json"))),
      m_imageRoot(QDir(m_profileRoot).filePath(QStringLiteral("images"))),
      m_customImageRoot(QDir(m_profileRoot).filePath(QStringLiteral("custom-art"))),
      m_currentDirectory(m_profileRoot)
{
    initialize();
}

CardArtStorage::~CardArtStorage()
{
    QObject::disconnect(&m_watcher, nullptr, this, nullptr);
    // A committed location must always have a fully copied image tree, even
    // when the application is closed while migration is running.
    m_watcher.waitForFinished();
}

void CardArtStorage::initialize()
{
    if (QFileInfo::exists(m_configPath) || QFileInfo(m_configPath).isSymLink()) {
        const QJsonObject config = readObject(m_configPath);
        if (QFileInfo(m_configPath).isSymLink() ||
            config.value(QStringLiteral("format")).toString() != QString::fromLatin1(kFormat) ||
            config.value(QStringLiteral("version")).toInt() != 1 ||
            config.value(QStringLiteral("profileKey")).toString() != m_profileKey ||
            !config.value(QStringLiteral("baseDirectory")).isString()) {
            setError(QStringLiteral("The card-art location configuration is invalid. No fallback "
                                    "directory was selected."));
            return;
        }
        m_baseDirectory = config.value(QStringLiteral("baseDirectory")).toString();
        for (const QJsonValue &value :
             config.value(QStringLiteral("previousImageRoots")).toArray()) {
            if (value.isString() && QDir::isAbsolutePath(value.toString()))
                m_previousImageRoots.append(QDir::cleanPath(value.toString()));
        }
        if (!m_baseDirectory.isEmpty()) {
            if (!QDir::isAbsolutePath(m_baseDirectory)) {
                setError(QStringLiteral("The card-art location configuration is invalid. No "
                                        "fallback directory was selected."));
                return;
            }
            m_currentDirectory =
                QDir(m_baseDirectory).filePath(QStringLiteral("hexproof-art-") + m_profileKey);
            m_imageRoot = QDir(m_currentDirectory).filePath(QStringLiteral("images"));
            m_customImageRoot = QDir(m_currentDirectory).filePath(QStringLiteral("custom-art"));
            if (!ownedDirectory(m_currentDirectory, m_profileKey)) {
                setError(
                    QStringLiteral("The configured card-art directory is unavailable or belongs to "
                                   "another profile. Reconnect its disk and restart Hexproof."));
                return;
            }
        }
    }
    if (defaultLocation()) {
        if (!QDir().mkpath(m_imageRoot) || !QDir().mkpath(m_customImageRoot)) {
            setError(QStringLiteral(
                "The card-art directory could not be created. Check directory permissions."));
            return;
        }
    }
    if (!writableDirectory(m_imageRoot) || !writableDirectory(m_customImageRoot)) {
        setError(QStringLiteral("The card-art directory is unavailable or read-only. No fallback "
                                "directory was selected."));
        return;
    }
    m_currentLock = std::make_unique<QLockFile>(
        QDir(m_currentDirectory).filePath(QString::fromLatin1(kLockFile)));
    m_currentLock->setStaleLockTime(0);
    if (!m_currentLock->tryLock(0)) {
        setError(QStringLiteral(
            "The card-art directory is already in use by another Hexproof process."));
        m_currentLock.reset();
        return;
    }
    m_available = true;
}

void CardArtStorage::setOperationGuard(std::function<bool()> guard)
{
    m_operationGuard = std::move(guard);
}

bool CardArtStorage::writesAllowed() const
{
    // An external disk can disappear after launch. Never recreate an empty
    // mount point just because startup validation previously succeeded.
    return m_available && !m_busy && !m_restartRequired && ordinaryDirectory(m_imageRoot) &&
           ordinaryDirectory(m_customImageRoot) && QFileInfo(m_imageRoot).isWritable() &&
           QFileInfo(m_customImageRoot).isWritable() &&
           (defaultLocation() || ownedDirectory(m_currentDirectory, m_profileKey));
}

QVariantMap CardArtStorage::destination(const QUrl &directory, bool useDefault) const
{
    QString base;
    if (!useDefault) {
        if (!directory.isLocalFile() || !ordinaryDirectory(directory.toLocalFile()))
            return {{QStringLiteral("ok"), false},
                    {QStringLiteral("error"),
                     QStringLiteral("Choose an existing local folder for card art.")}};
        base = absolutePath(directory.toLocalFile());
    }
    const QString managed =
        useDefault ? m_profileRoot
                   : QDir(base).filePath(QStringLiteral("hexproof-art-") + m_profileKey);
    const QString images = QDir(managed).filePath(QStringLiteral("images"));
    const QString custom = QDir(managed).filePath(QStringLiteral("custom-art"));
    if (managed == m_currentDirectory)
        return {{QStringLiteral("ok"), false},
                {QStringLiteral("error"), QStringLiteral("Card art already uses this location.")}};
    for (const QString &source : {m_imageRoot, m_customImageRoot}) {
        if (containedBy(managed, source) || containedBy(source, images) ||
            containedBy(source, custom))
            return {{QStringLiteral("ok"), false},
                    {QStringLiteral("error"),
                     QStringLiteral("Choose a directory outside the current image folders.")}};
    }
    if (QFileInfo(managed).isSymLink() ||
        (!useDefault && QFileInfo::exists(managed) && !ownedDirectory(managed, m_profileKey)))
        return {{QStringLiteral("ok"), false},
                {QStringLiteral("error"),
                 QStringLiteral(
                     "The managed destination already exists but is not owned by this profile.")}};
    if (!writableDirectory(useDefault ? m_profileRoot : base))
        return {
            {QStringLiteral("ok"), false},
            {QStringLiteral("error"), QStringLiteral("The destination folder is not writable.")}};
    return {{QStringLiteral("ok"), true},
            {QStringLiteral("baseDirectory"), base},
            {QStringLiteral("managedDirectory"), managed},
            {QStringLiteral("imageRoot"), images},
            {QStringLiteral("customImageRoot"), custom},
            {QStringLiteral("isDefault"), useDefault}};
}

QVariantMap CardArtStorage::previewDirectory(const QUrl &directory)
{
    m_preview = destination(directory, false);
    emit previewChanged();
    return m_preview;
}

QVariantMap CardArtStorage::previewDefault()
{
    m_preview = destination({}, true);
    emit previewChanged();
    return m_preview;
}

void CardArtStorage::migrateTo(const QUrl &directory)
{
    migrate(previewDirectory(directory));
}

void CardArtStorage::resetToDefault()
{
    migrate(previewDefault());
}

void CardArtStorage::migrate(const QVariantMap &target)
{
    if (m_busy || m_restartRequired) {
        setError(QStringLiteral("Wait for migration to finish, then restart Hexproof before "
                                "changing the location again."));
        return;
    }
    clearMessages();
    if (!m_available) {
        setError(QStringLiteral(
            "The current card-art directory is unavailable. Reconnect its disk before migrating."));
        return;
    }
    if (!target.value(QStringLiteral("ok")).toBool()) {
        setError(target.value(QStringLiteral("error")).toString());
        return;
    }
    if (m_operationGuard && !m_operationGuard()) {
        setError(
            QStringLiteral("Wait for the current card-art operation to finish before migrating."));
        return;
    }
    const QString managed = target.value(QStringLiteral("managedDirectory")).toString();
    const QString images = target.value(QStringLiteral("imageRoot")).toString();
    const QString custom = target.value(QStringLiteral("customImageRoot")).toString();
    if (!QDir().mkpath(managed)) {
        setError(QStringLiteral("The destination folder could not be created."));
        return;
    }
    m_destinationLock =
        std::make_unique<QLockFile>(QDir(managed).filePath(QString::fromLatin1(kLockFile)));
    m_destinationLock->setStaleLockTime(0);
    if (!m_destinationLock->tryLock(0)) {
        m_destinationLock.reset();
        setError(QStringLiteral(
            "The destination card-art directory is already in use by another Hexproof process."));
        return;
    }
    if (!target.value(QStringLiteral("isDefault")).toBool() &&
        !catalogstorage::writeJson(QDir(managed).filePath(QString::fromLatin1(kOwnerFile)),
                                   {{QStringLiteral("format"), QString::fromLatin1(kFormat)},
                                    {QStringLiteral("profileKey"), m_profileKey}})) {
        m_destinationLock.reset();
        setError(QStringLiteral("Could not record ownership of the card-art directory."));
        return;
    }
    QStringList previous = m_previousImageRoots;
    previous.append(m_imageRoot);
    previous.removeDuplicates();
    const QJsonObject config{
        {QStringLiteral("format"), QString::fromLatin1(kFormat)},
        {QStringLiteral("version"), 1},
        {QStringLiteral("profileKey"), m_profileKey},
        {QStringLiteral("baseDirectory"), target.value(QStringLiteral("baseDirectory")).toString()},
        {QStringLiteral("previousImageRoots"), QJsonArray::fromStringList(previous)}};
    m_busy = true;
    emit busyChanged();
    setProgress(0);
    setStatus(QStringLiteral("Copying and verifying downloaded and custom card images…"));
    connect(&m_watcher, &QFutureWatcher<MigrationResult>::finished, this, [this, target]() {
        const MigrationResult result = m_watcher.result();
        QObject::disconnect(&m_watcher, nullptr, this, nullptr);
        if (result.ok) {
            setError({});
            m_restartRequired = true;
            emit restartRequiredChanged();
            m_lastResult =
                QStringLiteral("Card images were copied and verified. Restart Hexproof to use the "
                               "new location. Original files were kept at %1.")
                    .arg(m_currentDirectory);
            emit lastResultChanged();
            setProgress(1);
        } else {
            m_destinationLock.reset();
            setError(result.error);
        }
        m_busy = false;
        emit busyChanged();
        setStatus({});
        emit migrationFinished(
            {{QStringLiteral("ok"), result.ok},
             {QStringLiteral("error"), result.error},
             {QStringLiteral("fileCount"), result.files},
             {QStringLiteral("bytes"), result.bytes},
             {QStringLiteral("destination"), target.value(QStringLiteral("managedDirectory"))},
             {QStringLiteral("source"), m_currentDirectory},
             {QStringLiteral("sourceRetained"), true}});
    });
    const QString sourceImages = m_imageRoot;
    const QString sourceCustom = m_customImageRoot;
    const QString configPath = m_configPath;
    m_watcher.setFuture(QtConcurrent::run(BackgroundTaskPools::catalogMaintenance(), [this,
                                                                                      sourceImages,
                                                                                      sourceCustom,
                                                                                      images,
                                                                                      custom,
                                                                                      managed,
                                                                                      configPath,
                                                                                      config]() {
        MigrationResult result;
        QList<CopyFile> files;
        qint64 totalBytes = 0;
        if (!scanTree(sourceImages, images, &files, &totalBytes, &result.error) ||
            !scanTree(sourceCustom, custom, &files, &totalBytes, &result.error))
            return result;
        QStorageInfo disk(managed);
        if (disk.isValid() && disk.bytesAvailable() >= 0 && disk.bytesAvailable() < totalBytes) {
            result.error =
                QStringLiteral("There is not enough free space to safely copy the card images.");
            return result;
        }
        if (!safeParents(images, managed) || !safeParents(custom, managed) ||
            !QDir().mkpath(images) || !QDir().mkpath(custom)) {
            result.error =
                QStringLiteral("The destination image folders could not be created safely.");
            return result;
        }
        qint64 copiedBytes = 0;
        double lastProgress = -1;
        for (const CopyFile &file : files) {
            const QString root = containedBy(file.destination, images) ? images : custom;
            if (!verifiedCopy(
                    file, root,
                    [&](qint64 amount) {
                        copiedBytes += amount;
                        const double progress =
                            totalBytes > 0 ? 0.95 * copiedBytes / totalBytes : 0;
                        if (progress - lastProgress >= 0.005) {
                            lastProgress = progress;
                            QMetaObject::invokeMethod(
                                this, [this, progress]() { setProgress(progress); },
                                Qt::QueuedConnection);
                        }
                    },
                    &result.error))
                return result;
            ++result.files;
            result.bytes += file.size;
        }
        // This single descriptor is the commit point for both image trees.
        // Legacy absolute cache paths are rebased from previousImageRoots on
        // the next launch; custom-art indexes already use relative filenames.
        if (QFileInfo(configPath).isSymLink() || !catalogstorage::writeJson(configPath, config)) {
            result.error = QStringLiteral(
                "Could not save the new card-art location. The original location remains active.");
            return result;
        }
        result.ok = true;
        return result;
    }));
}

void CardArtStorage::setError(const QString &error)
{
    if (m_lastError == error)
        return;
    m_lastError = error;
    emit lastErrorChanged();
}

void CardArtStorage::setStatus(const QString &status)
{
    if (m_status == status)
        return;
    m_status = status;
    emit statusChanged();
}

void CardArtStorage::setProgress(double progress)
{
    progress = qBound(0.0, progress, 1.0);
    if (m_progress == progress)
        return;
    m_progress = progress;
    emit progressChanged();
}

void CardArtStorage::clearMessages()
{
    // Startup failure explains why the configured location was not activated.
    if (m_available)
        setError({});
    if (!m_lastResult.isEmpty()) {
        m_lastResult.clear();
        emit lastResultChanged();
    }
}

} // namespace hexproof::client
