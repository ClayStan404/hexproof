// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#pragma once

#include "BackgroundTaskPools.h"
#include "CardCatalogCommon.h"
#include "NetworkLimits.h"

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

inline void inspectImageFileAsync(QObject *context, const QString &path,
                                  std::function<void(const ImagePayloadInspection &)> finished)
{
    auto *watcher = new QFutureWatcher<ImagePayloadInspection>(context);
    QObject::connect(watcher, &QFutureWatcher<ImagePayloadInspection>::finished, context,
                     [watcher, finished = std::move(finished)]() {
                         const ImagePayloadInspection result = watcher->result();
                         watcher->deleteLater();
                         finished(result);
                     });
    // Local art remains a read-only lookup: both disk I/O and complete decode
    // run on the same bounded pool as downloads, without touching the index.
    watcher->setFuture(QtConcurrent::run(BackgroundTaskPools::cardImageValidation(), [path]() {
        QFile file(path);
        if (!file.open(QIODevice::ReadOnly) ||
            file.size() > network_limits::kMaximumCardImageResponseBytes)
            return ImagePayloadInspection{};
        const QByteArray bytes = file.read(network_limits::kMaximumCardImageResponseBytes + 1);
        if (bytes.size() > network_limits::kMaximumCardImageResponseBytes)
            return ImagePayloadInspection{};
        return inspectImagePayload(bytes);
    }));
}

} // namespace hexproof::client::catalog_internal
