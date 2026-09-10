// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "CardArtManager.h"
#include "CardArtStorage.h"
#include "CardCatalog.h"
#include "CatalogRepository.h"
#include "CustomCardArtStore.h"

namespace hexproof::client {

CardArtStorage *CardCatalog::artStorage() const
{
    return m_artStorage.get();
}
CustomCardArtStore *CardCatalog::customArtStore() const
{
    return m_customArt.get();
}

bool CardCatalog::artWritesAllowed() const
{
    return m_artStorage && m_artStorage->writesAllowed() && (!m_customArt || !m_customArt->busy());
}

bool CardCatalog::artOperationsIdle() const
{
    return !m_shuttingDown && !m_catalogBusy && !m_resolving && !m_searching && !m_tokenSearching &&
           !m_limitedArtCaching && m_cardQueue.isEmpty() && m_fallbackQueue.isEmpty() &&
           m_directImageJobs.isEmpty() && m_incrementalCacheQueue.isEmpty() &&
           m_cachedHydrationQueue.isEmpty();
}

QVariantList CardCatalog::customArtBindings(const QVariantMap &card) const
{
    const QString name = card.value(QStringLiteral("name")).toString().simplified();
    const QString setCode = card.value(QStringLiteral("setCode")).toString().toUpper();
    const QString collector = card.value(QStringLiteral("collectorNumber")).toString();
    if (name.isEmpty())
        return {};
    const CardRequest request{name, setCode, collector, m_language};
    CardRecord record = lookupCatalog(request);
    QString canonicalName = record.valid() ? record.name : name;
    QString layout;
    QVariantList faces;
    if (installed() && !m_catalogBusy) {
        QString resolvedName;
        faces = guiCatalog().cardFaces(name, setCode, collector, nullptr, &layout, &resolvedName);
        if (!resolvedName.isEmpty())
            canonicalName = resolvedName;
    }
    if (!request.specifiesPrinting() && faces.isEmpty() &&
        canonicalName.contains(QStringLiteral(" // ")) &&
        canonicalName.section(QStringLiteral(" // "), 1).compare(name, Qt::CaseInsensitive) == 0) {
        // A standalone spell absent from the catalog is not the second
        // characteristic of whichever prepare/adventure happens to contain it.
        canonicalName = name;
        record = {};
    }
    // No identity is inferred from localized names, artwork or the // delimiter.
    // Only the catalog declares independent image faces.
    if (faces.isEmpty()) {
        faces.append(QVariantMap{{QStringLiteral("name"), canonicalName},
                                 {QStringLiteral("faceName"), QString{}},
                                 {QStringLiteral("setCode"), setCode},
                                 {QStringLiteral("collectorNumber"), collector}});
    }
    QVariantList result;
    for (const QVariant &value : faces) {
        const QVariantMap face = value.toMap();
        const bool related = face.value(QStringLiteral("relatedCard")).toBool();
        const QString faceName = face.value(QStringLiteral("faceName")).toString();
        const QString bindingName =
            related ? face.value(QStringLiteral("name")).toString() : canonicalName;
        const QString bindingSet = face.value(QStringLiteral("setCode"), setCode).toString();
        const QString bindingCollector =
            face.value(QStringLiteral("collectorNumber"), collector).toString();
        const CardRecord identity =
            related ? lookupCatalog({bindingName, bindingSet, bindingCollector, m_language})
                    : record;
        result.append(QVariantMap{
            {QStringLiteral("name"), bindingName},
            {QStringLiteral("faceName"), related ? QString{} : faceName},
            {QStringLiteral("setCode"), bindingSet},
            {QStringLiteral("collectorNumber"), bindingCollector},
            {QStringLiteral("oracleId"), identity.oracleId},
            {QStringLiteral("allowCardScope"), !identity.oracleId.isEmpty()},
            {QStringLiteral("label"),
             related ? tr("Meld result: %1").arg(bindingName) : face.value(QStringLiteral("name"))},
            {QStringLiteral("layout"), layout},
            {QStringLiteral("relatedCard"), related},
        });
    }
    return result;
}

QString CardCatalog::customImagePath(const CardRequest &request) const
{
    if (!m_customArt)
        return {};
    QString path = m_customArt->imagePath(request.name, request.setCode, request.collectorNumber);
    if (!path.isEmpty() || !m_customArt->hasEntries())
        return path;
    const CardRecord identity = lookupCatalog(request);
    path = m_customArt->imagePath(request.name, request.setCode, request.collectorNumber,
                                  identity.oracleId);
    if (!path.isEmpty())
        return path;
    const CardRequest related = relatedArtRequest(request);
    if (related.name != request.name || related.setCode != request.setCode ||
        related.collectorNumber != request.collectorNumber) {
        const CardRecord relatedIdentity = lookupCatalog(related);
        return m_customArt->imagePath(related.name, related.setCode, related.collectorNumber,
                                      relatedIdentity.oracleId);
    }
    // Repository records describe the whole printing, not a selected face.
    // In particular an empty record.faceName is NOT evidence of a front request.
    const auto matches = [&request](const QString &name) {
        return !name.isEmpty() &&
               name.simplified().compare(request.name.simplified(), Qt::CaseInsensitive) == 0;
    };
    const QVariantList independentFaces =
        identity.valid() ? const_cast<CardCatalog *>(this)->cardFaces(
                               identity.name, request.setCode, request.collectorNumber)
                         : QVariantList{};
    const bool completeLocalizedFaces =
        independentFaces.isEmpty() ||
        identity.localizedName.split(QStringLiteral(" // ")).size() == independentFaces.size();
    bool frontAlias = matches(identity.name) ||
                      matches(identity.name.section(QStringLiteral(" // "), 0, 0)) ||
                      (completeLocalizedFaces &&
                       (matches(identity.localizedName) ||
                        matches(identity.localizedName.section(QStringLiteral(" // "), 0, 0))));
    const QStringList canonicalFaces = identity.name.split(QStringLiteral(" // "));
    if (canonicalFaces.size() == 2 &&
        canonicalFaces.first().compare(canonicalFaces.last(), Qt::CaseInsensitive) == 0 &&
        matches(canonicalFaces.first())) {
        frontAlias = false;
    }
    if (!frontAlias && request.specifiesPrinting() &&
        identity.name.contains(QStringLiteral(" // ")) &&
        (matches(identity.name.section(QStringLiteral(" // "), 1)) ||
         matches(identity.localizedName.section(QStringLiteral(" // "), 1)))) {
        // Prepare/adventure/split characteristics share a single image. Only
        // catalog-declared independent back faces must not use the front art.
        frontAlias = independentFaces.isEmpty();
    }
    if (identity.valid() && frontAlias) {
        return m_customArt->imagePath(identity.name, request.setCode, request.collectorNumber,
                                      identity.oracleId);
    }
    return {};
}

QString CardCatalog::customImageSource(const QString &name, const QString &setCode,
                                       const QString &collectorNumber) const
{
    const QString path =
        customImagePath({name.simplified(), setCode.toUpper(), collectorNumber, m_language});
    return path.isEmpty() ? QString{} : QUrl::fromLocalFile(path).toString();
}

CardCatalog::CardRequest CardCatalog::relatedArtRequest(const CardRequest &request) const
{
    if (!installed() || m_catalogBusy || !request.specifiesPrinting())
        return request;
    const QVariantList faces = const_cast<CardCatalog *>(this)->cardFaces(
        request.name, request.setCode, request.collectorNumber);
    for (const QVariant &value : faces) {
        const QVariantMap face = value.toMap();
        if (!face.value(QStringLiteral("relatedCard")).toBool() ||
            face.value(QStringLiteral("name"))
                    .toString()
                    .compare(request.name, Qt::CaseInsensitive) != 0)
            continue;
        CardRequest result = request;
        result.setCode = face.value(QStringLiteral("setCode")).toString();
        result.collectorNumber = face.value(QStringLiteral("collectorNumber")).toString();
        return result;
    }
    return request;
}

} // namespace hexproof::client
