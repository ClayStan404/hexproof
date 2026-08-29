// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#pragma once

#include <QString>
#include <QVariantList>

namespace hexproof::client {

struct CardRecord
{
    QString requestedName;
    QString name;
    QString oracleId;
    QString faceName;
    QString localizedName;
    QString typeLine;
    QString setCode;
    QString collectorNumber;
    QString illustrationId;
    QString imageUrl;
    QString imagePath;
    QString imageLanguage;
    int resolutionVersion = 0;
    bool usesSubstituteArt = false;
    // Provider language fallback and opportunistic local reuse are distinct:
    // exact-art previews reject both, while the local-reuse preference only
    // rejects the latter.
    bool reusesLocalArt = false;

    bool valid() const
    {
        return !name.isEmpty();
    }
};

struct CardRequest
{
    CardRequest() = default;
    CardRequest(const QString &requestName, const QString &requestSetCode,
                const QString &requestCollectorNumber, const QString &requestLanguage)
        : name(requestName),
          setCode(requestSetCode),
          collectorNumber(requestCollectorNumber),
          language(requestLanguage)
    {
    }

    QString name;
    QString setCode;
    QString collectorNumber;
    QString language;
    bool exactArt = false;
    CardRecord catalogHint;

    bool specifiesPrinting() const
    {
        return !setCode.isEmpty() && !collectorNumber.isEmpty();
    }

    bool allowsSubstituteArt(bool reuseLocalArt) const
    {
        // With no requested printing there is no exact identity to preserve,
        // so a compatible local printing remains the preferred default even
        // when cross-printing substitution is disabled for explicit versions.
        return !exactArt && (reuseLocalArt || !specifiesPrinting());
    }
};

struct CatalogImportResult
{
    CatalogImportResult() = default;
    CatalogImportResult(bool resultOk, const QString &resultError, int resultCardCount,
                        int resultAliasCount = 0, int resultTokenCount = 0,
                        const QString &resultPackageType = {}, int resultLocalizedPrintingCount = 0,
                        bool resultCancelled = false, const QString &resultGeneratedAt = {},
                        int resultSchemaVersion = 0)
        : ok(resultOk),
          error(resultError),
          cardCount(resultCardCount),
          aliasCount(resultAliasCount),
          tokenCount(resultTokenCount),
          packageType(resultPackageType),
          localizedPrintingCount(resultLocalizedPrintingCount),
          cancelled(resultCancelled),
          generatedAt(resultGeneratedAt),
          schemaVersion(resultSchemaVersion)
    {
    }

    bool ok = false;
    QString error;
    int cardCount = 0;
    int aliasCount = 0;
    int tokenCount = 0;
    QString packageType;
    int localizedPrintingCount = 0;
    bool cancelled = false;
    QString generatedAt;
    int schemaVersion = 0;
};

struct CatalogSearchResult
{
    QVariantList cards;
    QString error;
};

struct CatalogCardQuery
{
    QString name;
    QString setCode;
    QString collectorNumber;
    QString language;
};

struct CatalogPersistResult
{
    int localizedPrintingCount = -1;
    QString error;
};

} // namespace hexproof::client
