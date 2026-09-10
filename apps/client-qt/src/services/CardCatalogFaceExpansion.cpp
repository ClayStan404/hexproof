// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "CardCatalog.h"
#include "CardCatalogCommon.h"
#include "CardCatalogFaceExpansionState.h"

#include <QCoreApplication>
#include <QTimer>

namespace hexproof::client {
using namespace catalog_internal;

namespace {

void appendExpandedRequest(CardFaceExpansionState *state, QVariantMap request)
{
    const QString name = request.value(QStringLiteral("name")).toString().simplified();
    if (name.isEmpty())
        return;
    const QString setCode = request.value(QStringLiteral("setCode")).toString().toUpper();
    const QString collectorNumber =
        request.value(QStringLiteral("collectorNumber")).toString().simplified();
    request.insert(QStringLiteral("name"), name);
    request.insert(QStringLiteral("setCode"), setCode);
    request.insert(QStringLiteral("collectorNumber"), collectorNumber);
    request.insert(kCardFacesExpandedKey, true);
    const QString key =
        name.toCaseFolded() + QChar(0x1f) + setCode + QChar(0x1f) + collectorNumber + QChar(0x1f) +
        request.value(QStringLiteral("kind")).toString() + QChar(0x1f) +
        (request.value(QStringLiteral("exactArt")).toBool() ? QLatin1Char('1') : QLatin1Char('0'));
    if (state->requestKeys.contains(key))
        return;
    state->requestKeys.insert(key);
    state->expanded.append(request);
}

} // namespace

void CardCatalog::expandCardFaceRequestsIncrementally(qint64 loadId, quint64 generation,
                                                      const QVariantList &cards)
{
    auto state = std::make_unique<CardFaceExpansionState>();
    state->loadId = loadId;
    state->generation = generation;
    state->serial = ++m_faceExpansionSerial;
    state->language = m_language;
    state->cards = cards;
    m_faceExpansion = std::move(state);
    scheduleCardFaceExpansion();
}

void CardCatalog::restartCardFaceExpansion()
{
    if (!m_faceExpansion)
        return;
    m_faceExpansion->serial = ++m_faceExpansionSerial;
    m_faceExpansion->language = m_language;
    m_faceExpansion->expanded.clear();
    m_faceExpansion->requestKeys.clear();
    m_faceExpansion->nextIndex = 0;
    m_faceExpansion->scheduled = false;
    scheduleCardFaceExpansion();
}

void CardCatalog::scheduleCardFaceExpansion()
{
    if (!m_faceExpansion || m_faceExpansion->scheduled || m_shuttingDown ||
        QCoreApplication::closingDown()) {
        return;
    }
    m_faceExpansion->scheduled = true;
    const quint64 serial = m_faceExpansion->serial;
    QTimer::singleShot(0, this, [this, serial]() {
        if (!m_faceExpansion || m_faceExpansion->serial != serial)
            return;
        m_faceExpansion->scheduled = false;
        processCardFaceExpansionBatch();
    });
}

void CardCatalog::processCardFaceExpansionBatch()
{
    if (!m_faceExpansion)
        return;
    if (m_shuttingDown || QCoreApplication::closingDown()) {
        m_faceExpansion.reset();
        return;
    }
    // A temporarily unavailable catalog must not turn a double-faced printing
    // into a completed single-face request. Installation resumes this job.
    if (m_catalogBusy)
        return;
    if (m_faceExpansion->language != m_language) {
        restartCardFaceExpansion();
        return;
    }

    int batchSize = 0;
    while (batchSize < cardFaceExpansionBatchSize() &&
           m_faceExpansion->nextIndex < m_faceExpansion->cards.size()) {
        QVariantMap request = m_faceExpansion->cards.at(m_faceExpansion->nextIndex++).toMap();
        const QString name = request.value(QStringLiteral("name")).toString().simplified();
        if (!request.contains(QStringLiteral("priorityName")))
            request.insert(QStringLiteral("priorityName"), name);
        const QString setCode = request.value(QStringLiteral("setCode")).toString().toUpper();
        const QString collectorNumber = request.value(QStringLiteral("collectorNumber")).toString();
        const QVariantList faces = cardFaces(name, setCode, collectorNumber);
        if (faces.size() < 2) {
            appendExpandedRequest(m_faceExpansion.get(), request);
        } else {
            for (const QVariant &faceValue : faces) {
                const QVariantMap face = faceValue.toMap();
                QVariantMap faceRequest = request;
                faceRequest.insert(QStringLiteral("name"), face.value(QStringLiteral("name")));
                faceRequest.insert(QStringLiteral("faceName"),
                                   face.value(QStringLiteral("faceName")));
                if (face.value(QStringLiteral("relatedCard")).toBool()) {
                    faceRequest.insert(QStringLiteral("setCode"),
                                       face.value(QStringLiteral("setCode")));
                    faceRequest.insert(QStringLiteral("collectorNumber"),
                                       face.value(QStringLiteral("collectorNumber")));
                }
                appendExpandedRequest(m_faceExpansion.get(), faceRequest);
            }
        }
        ++batchSize;
    }

    emit cardFaceExpansionProgress(m_faceExpansion->loadId, m_faceExpansion->generation,
                                   m_faceExpansion->language, batchSize,
                                   static_cast<int>(m_faceExpansion->nextIndex));
    if (m_faceExpansion->nextIndex < m_faceExpansion->cards.size()) {
        scheduleCardFaceExpansion();
        return;
    }

    const qint64 loadId = m_faceExpansion->loadId;
    const quint64 generation = m_faceExpansion->generation;
    const QVariantList expanded = m_faceExpansion->expanded;
    m_faceExpansion.reset();
    emit cardFaceRequestsExpanded(loadId, generation, expanded);
}

} // namespace hexproof::client
