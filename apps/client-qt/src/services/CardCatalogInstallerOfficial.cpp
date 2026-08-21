// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "CardCatalog.h"
#include "CatalogInstaller.h"

namespace hexproof::client {

void CardCatalog::downloadCatalog(const QString &packageType)
{
    if (m_catalogInstaller)
        m_catalogInstaller->downloadCatalog(packageType);
}

void CardCatalog::importCatalogFile(const QUrl &fileUrl, const QString &packageType)
{
    if (m_catalogInstaller)
        m_catalogInstaller->importCatalogFile(fileUrl, packageType);
}

void CardCatalog::downloadTokenCatalog()
{
    if (m_catalogInstaller)
        m_catalogInstaller->downloadTokenCatalog();
}

} // namespace hexproof::client
