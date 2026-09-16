// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#pragma once

#include <QHash>
#include <QSet>
#include <QString>
#include <QVariantList>
#include <QVariantMap>

#include <memory>

class QTemporaryDir;

namespace hexproof::client::customart {

inline constexpr qint64 kMaximumImageBytes = 32 * 1024 * 1024;
inline constexpr qint64 kMaximumManifestBytes = 16 * 1024 * 1024;
inline constexpr qint64 kMaximumPayloadBytes = 4LL * 1024 * 1024 * 1024;
inline constexpr int kMaximumEntries = 20'000;

struct WorkResult
{
    bool ok = false;
    QString error;
    QVariantList entries;
    QVariantList displayEntries;
    QHash<QString, QString> lookup;
    QHash<QString, QVariantMap> entriesById;
    QVariantList changedBindings;
    QSet<QString> repairedImageFiles;
    QVariantList pendingEntries;
    QVariantMap preview;
    QVariantMap result;
    std::shared_ptr<QTemporaryDir> staging;
    bool changed = false;
};

struct ImageInfo
{
    bool ok = false;
    QString error;
    QString fileName;
    QString sha256;
    QString format;
    qint64 bytes = 0;
    int width = 0;
    int height = 0;
};

QString normalizedName(const QString &name);
QString bindingId(const QVariantMap &binding);
QVariantMap normalizeBinding(const QVariantMap &binding, QString *error);
QString familyKey(const QVariantMap &binding);
QStringList lookupKeys(const QVariantMap &binding);
QString exactLookupKey(const QString &name, const QString &setCode, const QString &collector);
QString cardLookupKey(const QString &name, const QString &oracleId);
QString safeManagedFile(const QString &root, const QString &fileName);
bool validateEntry(const QVariantMap &entry, QString *error);
QVariantMap portableEntry(const QVariantMap &entry);
bool validateBindingForCatalog(const QVariantMap &binding, const QString &databasePath,
                               QString *error);
ImageInfo validateImage(const QByteArray &bytes);
ImageInfo stageImage(const QString &source, const QString &stagingRoot);
bool readIndex(const QString &path, QVariantList *entries, QString *error);
bool writeIndex(const QString &path, const QVariantList &entries, QString *error);
WorkResult install(const QString &indexPath, const QString &imageRoot, const QVariantList &existing,
                   const QVariantList &incoming, const QString &stagingRoot, bool replaceExisting);
WorkResult remove(const QString &indexPath, const QString &imageRoot, const QVariantList &existing,
                  const QStringList &ids);
WorkResult inspectDirectory(const QString &directory, const QString &databasePath,
                            const QVariantList &existing, std::shared_ptr<QTemporaryDir> staging);
WorkResult inspectPack(const QString &path, const QString &databasePath,
                       const QVariantList &existing, std::shared_ptr<QTemporaryDir> staging);
WorkResult exportPack(const QString &path, const QString &imageRoot, const QVariantList &entries);

} // namespace hexproof::client::customart
