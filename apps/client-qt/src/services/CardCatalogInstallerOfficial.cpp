// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "CardCatalog.h"
#include "CatalogInstaller.h"

namespace hexproof::client {

void CardCatalog::downloadCatalog(const QString &packageType)
{
    if (m_customArtBusy || m_artStorageBusy) {
        setLastError(QStringLiteral("Wait for the current card-art operation to finish."));
        return;
    }
    if (m_catalogInstaller)
        m_catalogInstaller->downloadCatalog(packageType);
}

void CardCatalog::importCatalogFile(const QUrl &fileUrl, const QString &packageType)
{
    if (m_customArtBusy || m_artStorageBusy) {
        setLastError(QStringLiteral("Wait for the current card-art operation to finish."));
        return;
    }
    if (m_catalogInstaller)
        m_catalogInstaller->importCatalogFile(fileUrl, packageType);
}

void CardCatalog::downloadTokenCatalog()
{
    if (m_customArtBusy || m_artStorageBusy) {
        setLastError(QStringLiteral("Wait for the current card-art operation to finish."));
        return;
    }
    if (m_catalogInstaller)
        m_catalogInstaller->downloadTokenCatalog();
}

} // namespace hexproof::client
