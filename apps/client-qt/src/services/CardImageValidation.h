// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#pragma once

#include "BackgroundTaskPools.h"
#include "CardCatalogCommon.h"

#include <QFutureWatcher>
#include <QtConcurrentRun>

#include <functional>

namespace hexproof::client::catalog_internal {

inline void inspectImagePayloadAsync(QObject *context, const QByteArray &bytes,
                                     std::function<void(const ImagePayloadInspection &)> finished)
{
    auto *watcher = new QFutureWatcher<ImagePayloadInspection>(context);
    QObject::connect(watcher, &QFutureWatcher<ImagePayloadInspection>::finished, context,
                     [watcher, finished = std::move(finished)]() {
                         const ImagePayloadInspection result = watcher->result();
                         watcher->deleteLater();
                         finished(result);
                     });
    // The worker owns only immutable bytes. Destroying the catalog/resolver
    // drops the callback; no background task can write into a closed profile.
    watcher->setFuture(QtConcurrent::run(BackgroundTaskPools::cardImageValidation(),
                                         [bytes]() { return inspectImagePayload(bytes); }));
}

} // namespace hexproof::client::catalog_internal
