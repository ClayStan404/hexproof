// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "CardCatalog.h"
#include "CatalogImport.h"

namespace hexproof::client {

CardCatalog::CardRecord CardCatalog::parseCardObject(const QJsonObject &object,
                                                     const QString &language,
                                                     const QString &requestedName)
{
    return catalogimport::parseCardObject(object, language, requestedName);
}

CardCatalog::ImportResult CardCatalog::importBulkFile(const QString &jsonPath,
                                                      const QString &databasePath,
                                                      const QString &packageType,
                                                      const QString &chineseArchivePath,
                                                      const QString &localizedPrintingsPath)
{
    return catalogimport::importBulkFile(jsonPath, databasePath, packageType, chineseArchivePath,
                                         localizedPrintingsPath);
}

CardCatalog::ImportResult CardCatalog::importDatabaseFile(const QString &sourcePath,
                                                          const QString &databasePath)
{
    return catalogimport::importDatabaseFile(sourcePath, databasePath);
}

} // namespace hexproof::client
