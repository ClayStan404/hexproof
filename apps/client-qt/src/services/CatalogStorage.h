// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#pragma once

#include <QJsonObject>
#include <QReadWriteLock>
#include <QString>

namespace hexproof::client::catalogstorage {

// Serializes replacement of the live SQLite file with active repository
// operations. Repository instances hold a read lock for their lifetime;
// install/recovery take the write lock before renaming files.
QReadWriteLock &databaseLock();

// Repairs an interrupted database replacement and removes an abandoned
// partially-built database. Returns false only when recovery itself failed.
bool recoverDatabase(const QString &databasePath, QString *error = nullptr);

// Installs a fully-built database while preserving the previous file as a
// recoverable backup until the replacement is in place.
bool installDatabase(const QString &newPath, const QString &databasePath, QString *error = nullptr);

// Writes JSON with QSaveFile so readers see either the old or new document.
bool writeJson(const QString &path, const QJsonObject &object, QString *error = nullptr);

} // namespace hexproof::client::catalogstorage
