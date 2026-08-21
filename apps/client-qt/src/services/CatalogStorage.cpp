// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "CatalogStorage.h"

#include <QFile>
#include <QFileInfo>
#include <QJsonDocument>
#include <QSaveFile>
#include <QWriteLocker>

namespace hexproof::client::catalogstorage {

namespace {

QReadWriteLock liveDatabaseLock;

void assignError(QString *error, const QString &message)
{
    if (error)
        *error = message;
}

} // namespace

QReadWriteLock &databaseLock()
{
    return liveDatabaseLock;
}

bool recoverDatabase(const QString &databasePath, QString *error)
{
    QWriteLocker locker(&databaseLock());
    const QString backupPath = databasePath + QStringLiteral(".backup");
    const QString newPath = databasePath + QStringLiteral(".new");
    if (!QFileInfo::exists(databasePath) && QFileInfo::exists(backupPath) &&
        !QFile::rename(backupPath, databasePath)) {
        assignError(error, QStringLiteral("Could not restore the previous card catalog."));
        return false;
    }
    if (QFileInfo::exists(databasePath) && QFileInfo::exists(backupPath) &&
        !QFile::remove(backupPath)) {
        assignError(error, QStringLiteral("Could not remove a stale card catalog backup."));
        return false;
    }
    if (QFileInfo::exists(newPath) && !QFile::remove(newPath)) {
        assignError(error, QStringLiteral("Could not remove an incomplete card catalog."));
        return false;
    }
    return true;
}

bool installDatabase(const QString &newPath, const QString &databasePath, QString *error)
{
    QWriteLocker locker(&databaseLock());
    const QString backupPath = databasePath + QStringLiteral(".backup");
    const bool hadDatabase = QFileInfo::exists(databasePath);
    if (hadDatabase && !QFile::rename(databasePath, backupPath)) {
        assignError(error,
                    QStringLiteral("Could not prepare the existing catalog for replacement."));
        return false;
    }
    if (!QFile::rename(newPath, databasePath)) {
        if (hadDatabase && !QFile::rename(backupPath, databasePath)) {
            assignError(
                error,
                QStringLiteral(
                    "Could not install the indexed card catalog or restore the previous catalog."));
        } else {
            assignError(error, QStringLiteral("Could not install the indexed card catalog."));
        }
        return false;
    }
    // The new database is already live. If cleanup fails, leaving the backup
    // is safe; the next startup removes it after confirming the live file.
    if (hadDatabase)
        QFile::remove(backupPath);
    return true;
}

bool writeJson(const QString &path, const QJsonObject &object, QString *error)
{
    QSaveFile file(path);
    if (!file.open(QIODevice::WriteOnly)) {
        assignError(error, file.errorString());
        return false;
    }
    const QByteArray bytes = QJsonDocument(object).toJson(QJsonDocument::Indented);
    if (file.write(bytes) != bytes.size()) {
        assignError(error, file.errorString());
        file.cancelWriting();
        return false;
    }
    if (!file.commit()) {
        assignError(error, file.errorString());
        return false;
    }
    return true;
}

} // namespace hexproof::client::catalogstorage
