// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "CardCatalog.h"
#include "CardCatalogCommon.h"

#include <QTimer>

namespace hexproof::client {

void CardCatalog::setSearchPreviewCards(const QVariantList &cards)
{
    // Replace the speculative backlog instead of accumulating intermediate
    // searches. Only one preview face may enter the resolver at a time.
    m_searchPreviewCards = cards;
    m_searchPreviewLanguage = m_language;
    emit searchPreviewChanged();
    scheduleSearchPreview();
}

void CardCatalog::scheduleSearchPreview()
{
    if (m_searchPreviewScheduled || m_searchPreviewCards.isEmpty() ||
        !m_searchPreviewIdentity.isEmpty() || m_shuttingDown || QCoreApplication::closingDown())
        return;
    m_searchPreviewScheduled = true;
    QTimer::singleShot(0, this, [this]() {
        m_searchPreviewScheduled = false;
        processSearchPreview();
    });
}

void CardCatalog::processSearchPreview()
{
    // Explicit cache work and match preparation always enter first. An already
    // started preview may finish, but closing/searching drops everything else.
    if (m_searchPreviewCards.isEmpty() || !m_searchPreviewIdentity.isEmpty() ||
        m_searchPreviewLanguage != m_language || m_shuttingDown ||
        QCoreApplication::closingDown() || !artWritesAllowed() || m_resolving ||
        cacheProgressActive() || m_faceExpansion || m_searching || m_tokenSearching ||
        !m_queuedKeys.isEmpty() || m_incrementalCacheScheduled)
        return;

    const QVariantMap card = m_searchPreviewCards.takeFirst().toMap();
    const QVariantList expanded = expandCardFaceRequests({card});
    if (expanded.isEmpty()) {
        emit searchPreviewChanged();
        scheduleSearchPreview();
        return;
    }
    // The gallery and its hover preview display the front face. A selected
    // printing's full face coverage belongs to explicit deck/match caching.
    const QVariantMap face = expanded.first().toMap();
    CardRequest request{face.value(QStringLiteral("name")).toString().simplified(),
                        face.value(QStringLiteral("setCode")).toString().toUpper(),
                        face.value(QStringLiteral("collectorNumber")).toString(), m_language};
    request.priorityName = card.value(QStringLiteral("name")).toString().simplified();
    request.supportCard = catalog_internal::isSupportCardRequest(face);
    m_searchPreviewIdentity = queuedRequestKey(request);
    m_searchPreviewAdopted = false;
    emit searchPreviewChanged();
    if (!customImagePath(request).isEmpty()) {
        emitCardCacheCompletion(request, true);
        return;
    }
    enqueueRequests({request}, true);
}

bool CardCatalog::finishSearchPreview(const CardRequest &request)
{
    if (queuedRequestKey(request) != m_searchPreviewIdentity)
        return false;
    m_searchPreviewIdentity.clear();
    m_searchPreviewAdopted = false;
    emit searchPreviewChanged();
    scheduleSearchPreview();
    return true;
}

} // namespace hexproof::client
