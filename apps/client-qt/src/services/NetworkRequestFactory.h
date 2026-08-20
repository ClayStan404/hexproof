// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#pragma once

#include <QByteArray>
#include <QNetworkRequest>
#include <QUrl>

namespace hexproof::client {

bool hostRequiresHttp11(const QUrl &url);
void applyHttpVersionPolicy(QNetworkRequest &request);

QNetworkRequest makeNetworkRequest(const QUrl &url, const QByteArray &accept,
                                   int transferTimeoutMs = 15'000);

} // namespace hexproof::client
