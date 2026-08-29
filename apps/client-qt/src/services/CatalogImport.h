// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#pragma once

#include "CatalogCancellation.h"
#include "CatalogTypes.h"

#include <QByteArray>
#include <QJsonObject>

namespace hexproof::client::catalogimport {

CardRecord parseCardObject(const QJsonObject &object, const QString &language,
                           const QString &requestedName = {});
CatalogImportResult importBulkFile(const QString &jsonPath, const QString &databasePath,
                                   const QString &packageType,
                                   const QString &chineseArchivePath = {},
                                   const QString &localizedPrintingsPath = {},
                                   CatalogImportStopToken stopToken = {});
CatalogImportResult importDatabaseFile(const QString &sourcePath, const QString &databasePath,
                                       CatalogImportStopToken stopToken = {});
CatalogImportResult importCompressedDatabaseFile(const QString &sourcePath,
                                                 const QString &databasePath,
                                                 qint64 expectedExpandedSize,
                                                 const QByteArray &expectedCompressedSha256,
                                                 const QByteArray &expectedDatabaseSha256,
                                                 CatalogImportStopToken stopToken = {});

} // namespace hexproof::client::catalogimport
